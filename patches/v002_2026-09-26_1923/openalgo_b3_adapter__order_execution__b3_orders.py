"""Gateways de execucao de ordens (padrao B3).

`B3OrderGateway` e a interface que cada corretora brasileira implementa.
O registro global escolhe o gateway via env B3_BROKER_GATEWAY (padrao:
sandbox). Gateways reais dependem de onboarding com a corretora (veja
brokers/nuinvest.py e brokers/btg.py para stubs documentados).

SandboxGateway: simulador in-memory deterministico, com ciclo de vida de
ordem (new/open/complete/cancelled/rejected), book, posicoes e funds â€”
para desenvolvimento e testes, no espirito do plugin dhan_sandbox do
OpenAlgo.
"""
from __future__ import annotations

import datetime as _dt
import itertools
import threading
from typing import Any, Callable, Dict, List, Optional

from openalgo_b3_adapter.config.b3_config import DEFAULT_GATEWAY, get_config
from openalgo_b3_adapter.order_execution.b3_validation import (
    OrderRequest, OrderValidationError, validate_order,
)

__all__ = ["B3OrderGateway", "register_gateway", "get_gateway", "SandboxGateway",
           "map_openalgo_order"]


class B3OrderGateway:
    """Contrato de gateway de corretora B3 (uma instancia por auth token)."""

    name = "base"

    def place_order(self, req: OrderRequest, auth: str) -> Dict[str, Any]:
        raise NotImplementedError

    def cancel_order(self, order_id: str, auth: str) -> Dict[str, Any]:
        raise NotImplementedError

    def modify_order(self, order_id: str, req: OrderRequest, auth: str) -> Dict[str, Any]:
        raise NotImplementedError

    def get_orders(self, auth: str) -> List[Dict[str, Any]]:
        raise NotImplementedError

    def get_trades(self, auth: str) -> List[Dict[str, Any]]:
        raise NotImplementedError

    def get_positions(self, auth: str) -> List[Dict[str, Any]]:
        raise NotImplementedError

    def get_holdings(self, auth: str) -> List[Dict[str, Any]]:
        raise NotImplementedError

    def get_funds(self, auth: str) -> Dict[str, Any]:
        raise NotImplementedError


# ---------------------------------------------------------------------------
# Registro de gateways
# ---------------------------------------------------------------------------

_GATEWAYS: Dict[str, Callable[[], B3OrderGateway]] = {}


_GATEWAY_INSTANCES: Dict[str, "B3OrderGateway"] = {}
_GATEWAY_INSTANCES_LOCK = threading.Lock()


def register_gateway(name: str, factory: Callable[[], B3OrderGateway]) -> None:
    _GatewaysProxy._factories[name] = factory


def get_gateway(name: Optional[str] = None) -> "B3OrderGateway":
    from openalgo_b3_adapter.order_execution.brokers.nuinvest import NuInvestGateway
    from openalgo_b3_adapter.order_execution.brokers.btg import BTGGateway

    registry: Dict[str, Callable[[], B3OrderGateway]] = {
        "sandbox": SandboxGateway,
        "nuinvest": NuInvestGateway,
        "btg": BTGGateway,
    }
    import os as _os
    gateway_name = (name or _os.getenv("B3_BROKER_GATEWAY") or get_config().gateway or DEFAULT_GATEWAY).lower()
    factory = registry.get(gateway_name)
    if factory is None:
        raise ValueError(
            f"Gateway '{gateway_name}' desconhecido. Disponiveis: {sorted(registry)}"
        )
    # Singleton por nome: sem isso cada chamada cria uma instancia nova e o
    # estado (ordens/posicoes/caixa) se perde entre chamadas do core.
    with _GATEWAY_INSTANCES_LOCK:
        if gateway_name not in _GATEWAY_INSTANCES:
            _GATEWAY_INSTANCES[gateway_name] = factory()
        return _GATEWAY_INSTANCES[gateway_name]


class _GatewaysProxy:  # mantem compat futura com factories dinamicos
    _factories: Dict[str, Callable[[], B3OrderGateway]] = {}


def map_openalgo_order(
    data: Dict[str, Any],
    br_symbol: str,
    reference_price: Optional[float] = None,
) -> OrderRequest:
    """Converte payload de ordem do OpenAlgo em OrderRequest B3.

    `data` e o dict validado pelo schema do core (apikey, strategy, symbol,
    exchange, action, quantity, pricetype, price, trigger_price, product...).
    `br_symbol` e o cÃ³digo B3 resolvido pelo master contract (plugin).
    """
    pricetype = (data.get("pricetype") or "MARKET").strip().upper()
    side_map = {"BUY": "BUY", "SELL": "SELL"}
    side = side_map.get((data.get("action") or "").strip().upper())
    if side is None:
        raise OrderValidationError("action deve ser BUY ou SELL", code="INVALID_SIDE")
    return OrderRequest(
        symbol=br_symbol,
        oa_symbol=str(data.get("symbol") or br_symbol),
        side=side,
        quantity=int(data.get("quantity") or 0),
        order_type=pricetype,
        price=float(data.get("price") or 0),
        trigger_price=float(data.get("trigger_price") or 0),
        validity="DAY",
        product=(data.get("product") or "CNC").strip().upper(),
        exchange=(data.get("exchange") or "NSE").strip().upper(),
        reference_price=reference_price,
    )


# ---------------------------------------------------------------------------
# Sandbox: simulador in-memory
# ---------------------------------------------------------------------------

def _default_sandbox_state_file() -> Optional[str]:
    """Caminho padrao do estado da corretora fantasma (~/.b3_adapter/).

    Persistencia por padrao: sem arquivo, ordens e posicoes morrem com o
    processo. Falha silenciosa retorna None (modo volatil, como antes).
    """
    import os as _os

    try:
        base = _os.path.join(_os.path.expanduser("~"), ".b3_adapter")
        _os.makedirs(base, exist_ok=True)
        return _os.path.join(base, "sandbox_state.json")
    except Exception:  # noqa: BLE001
        return None


class SandboxGateway(B3OrderGateway):
    """Corretora fantasma: simulador com ciclo de vida de ordem B3.

    Modo dev (padrao, deterministico, offline):
    - MARKET executa a `reference_price` (ou 100.00) na hora.
    - LIMIT/SL ficam 'open' ate `fill_order()` (testes) ou canceladas.

    Modo corretora fantasma (paper trading):
    - `state_file` (ou env B3_SANDBOX_STATE_FILE): estado persistido em
      JSON; ordens/trades/posicoes/caixa sobrevivem a restarts.
    - `use_live_quotes=True` (ou env B3_SANDBOX_LIVE_FILLS=1): fills MARKET
      usam cotacao real (Brapi/HG) com fallback deterministico; posicoes
      ganham ltp e PnL nao realizado.
    - `auto_tick_seconds > 0` (ou env B3_SANDBOX_AUTO_TICK=<segundos>):
      motor de ticks em background que busca cotacoes periodicamente e
      executa sozinho: LIMIT (compra preco<=limite, venda preco>=limite)
      e SL/SL-M (disparo no gatilho) â€” comportamento de corretora,
      sem dinheiro real.
    """

    name = "sandbox"

    def __init__(
        self,
        initial_cash: float = 100_000.0,
        ignore_sessions: Optional[bool] = None,
        state_file: Optional[str] = None,
        use_live_quotes: Optional[bool] = None,
        auto_tick_seconds: Optional[float] = None,
        quote_provider: Optional[Any] = None,
    ):
        import os as _os

        self._lock = threading.RLock()
        self._ids = itertools.count(1)
        self._initial_cash = float(initial_cash)
        self._ignore_sessions = (
            get_config().sandbox_ignore_sessions
            if ignore_sessions is None else ignore_sessions
        )
        self._state_file = (
            state_file
            or _os.getenv("B3_SANDBOX_STATE_FILE")
            or _default_sandbox_state_file()
        )
        _env_cash = _os.getenv("B3_SANDBOX_INITIAL_CASH", "").strip()
        if _env_cash and initial_cash == 100_000.0:
            initial_cash = float(_env_cash)
        if use_live_quotes is None:
            use_live_quotes = _os.getenv("B3_SANDBOX_LIVE_FILLS", "").strip().lower() in ("1", "true", "yes", "on")
        if auto_tick_seconds is None:
            _env = _os.getenv("B3_SANDBOX_AUTO_TICK", "").strip()
            auto_tick_seconds = float(_env) if _env else 0.0
        self._auto_tick_seconds = float(auto_tick_seconds or 0.0)
        self._use_live_quotes = bool(use_live_quotes) or self._auto_tick_seconds > 0
        self._quote_provider = quote_provider
        self._quotes: Dict[str, float] = {}
        self._tick_thread: Optional[threading.Thread] = None
        self._tick_stop = threading.Event()

        # estado por auth token
        self._orders: Dict[str, Dict[str, Dict[str, Any]]] = {}
        self._trades: Dict[str, List[Dict[str, Any]]] = {}
        self._cash: Dict[str, float] = {}
        self._positions: Dict[str, Dict[str, Dict[str, Any]]] = {}

        self._load()
        if self._auto_tick_seconds > 0:
            self._tick_thread = threading.Thread(
                target=self._tick_loop, name="b3-ghost-tick", daemon=True,
            )
            self._tick_thread.start()

    # -- persistencia ------------------------------------------------------
    def _load(self) -> None:
        import json as _json
        import os as _os

        if not (self._state_file and _os.path.exists(self._state_file)):
            return
        try:
            with open(self._state_file, "r", encoding="utf-8") as fh:
                data = _json.load(fh)
            self._orders = {a: {oid: dict(o) for oid, o in orders.items()}
                            for a, orders in data.get("orders", {}).items()}
            self._trades = {a: list(t) for a, t in data.get("trades", {}).items()}
            self._cash = {a: float(c) for a, c in data.get("cash", {}).items()}
            self._positions = {a: {s: dict(p) for s, p in pos.items()}
                               for a, pos in data.get("positions", {}).items()}
            self._quotes = {s: float(q) for s, q in data.get("quotes", {}).items()}
            max_id = 0
            for orders in self._orders.values():
                for oid in orders:
                    try:
                        max_id = max(max_id, int(oid.rsplit("-", 1)[1]))
                    except (ValueError, IndexError):
                        pass
            self._ids = itertools.count(max_id + 1)
        except Exception:  # noqa: BLE001 â€” estado corrompido: comeca limpo
            self._orders, self._trades = {}, {}
            self._cash, self._positions, self._quotes = {}, {}, {}

    def _persist(self) -> None:
        import json as _json
        import os as _os

        if not self._state_file:
            return
        data = {
            "orders": self._orders,
            "trades": self._trades,
            "cash": self._cash,
            "positions": self._positions,
            "quotes": self._quotes,
            "updated_at": _dt.datetime.now(_dt.timezone.utc).isoformat(timespec="seconds"),
        }
        tmp = self._state_file + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            _json.dump(data, fh, ensure_ascii=False, indent=1)
        _os.replace(tmp, self._state_file)

    # -- precos ------------------------------------------------------------
    def _get_quote_price(self, br_symbol: str) -> Optional[float]:
        """Cotacao atual via provider injetado ou composite (best-effort).

        O provider tem cache proprio com TTL (CompositeQuoteProvider), entao
        sempre consultamos ele primeiro; `self._quotes` guarda o ultimo preco
        conhecido apenas como fallback offline.
        """
        provider = self._quote_provider
        if provider is None:
            try:
                from openalgo_b3_adapter.market_data.b3_quotes import (
                    CompositeQuoteProvider,
                )
                provider = self._quote_provider = CompositeQuoteProvider(ttl=15)
            except Exception:  # noqa: BLE001
                return self._quotes.get(br_symbol)
        try:
            q = provider.get_quote(br_symbol)
            if q and getattr(q, "ltp", None):
                self._quotes[br_symbol] = float(q.ltp)
                return float(q.ltp)
        except Exception:  # noqa: BLE001 â€” sem rede: usa ultimo preco conhecido
            pass
        return self._quotes.get(br_symbol)

    def _fill_price(self, order: Dict[str, Any], reference_price: Optional[float]) -> float:
        """Preco de execucao: cotacao real (se habilitado), senao fallback."""
        if self._use_live_quotes:
            live = self._get_quote_price(order["symbol"])
            if live:
                return live
        return float(reference_price or 100.0)

    # -- helpers internos ---------------------------------------------------
    def _state(self, auth: str, create: bool = False):
        if auth not in self._orders:
            if not create:
                raise ValueError("auth desconhecido no sandbox (chame auth primeiro)")
            self._orders[auth] = {}
            self._trades[auth] = []
            self._cash[auth] = self._initial_cash
            self._positions[auth] = {}
            self._persist()
        return self._orders[auth]

    def ensure_auth(self, auth: str) -> None:
        with self._lock:
            self._state(auth, create=True)

    def _next_id(self) -> str:
        return f"B3SBX-{next(self._ids):06d}"

    # -- API do gateway ----------------------------------------------------
    def place_order(self, req: OrderRequest, auth: str) -> Dict[str, Any]:
        with self._lock:
            self._state(auth, create=True)
            try:
                validate_order(req, check_session=not self._ignore_sessions)
            except OrderValidationError as exc:
                return {"status": "rejected", "order_id": None, "message": exc.message}
        order_id = self._next_id()
        now = _dt.datetime.now(_dt.timezone.utc).isoformat(timespec="seconds")
        otype = (req.order_type or "MARKET").upper()
        with self._lock:
            order = {
                "order_id": order_id,
                "symbol": req.symbol,
                "oa_symbol": req.oa_symbol or req.symbol,
                "exchange": req.exchange,
                "side": req.side,
                "quantity": int(req.quantity),
                "order_type": otype,
                "price": float(req.price or 0),
                "trigger_price": float(req.trigger_price or 0),
                "validity": req.validity,
                "product": req.product,
                "status": "new",
                "filled_quantity": 0,
                "average_price": 0.0,
                "created_at": now,
                "updated_at": now,
            }
            self._orders[auth][order_id] = order
            if otype == "MARKET":
                self._fill(auth, order, price=self._fill_price(order, req.reference_price))
            elif otype in ("SL", "SL-M", "STOP_LIMIT", "STOP_MARKET"):
                # stop registrado como gatilho pendente (disparo no tick)
                order["status"] = "trigger_pending"
            self._persist()
            return {
                "status": "success",
                "order_id": order_id,
                "message": "Ordem recebida (sandbox)",
                "raw": order,
            }

    def _fill(self, auth: str, order: Dict[str, Any], price: float) -> None:
        order.update(status="complete", filled_quantity=order["quantity"],
                     average_price=float(price),
                     updated_at=_dt.datetime.now(_dt.timezone.utc).isoformat(timespec="seconds"))
        self._trades[auth].append({
            "trade_id": f"T-{order['order_id']}",
            "order_id": order["order_id"],
            "symbol": order["symbol"],
            "oa_symbol": order["oa_symbol"],
            "exchange": order["exchange"],
            "side": order["side"],
            "quantity": order["quantity"],
            "price": float(price),
            "executed_at": order["updated_at"],
        })
        signed = 1 if order["side"] == "BUY" else -1
        notional = float(price) * order["quantity"]
        self._cash[auth] = self._cash.get(auth, self._initial_cash) - signed * notional
        pos = self._positions[auth].setdefault(order["symbol"], {"symbol": order["symbol"], "oa_symbol": order["oa_symbol"], "exchange": order["exchange"], "quantity": 0, "average_price": 0.0, "ltp": float(price), "realized_pnl": 0.0, "unrealized_pnl": 0.0})
        total_cost = pos["average_price"] * pos["quantity"] + price * order["quantity"] * signed
        pos["quantity"] += signed * order["quantity"]
        pos["average_price"] = abs(total_cost / pos["quantity"]) if pos["quantity"] != 0 else 0.0
        if pos["quantity"] == 0:
            del self._positions[auth][order["symbol"]]

    def fill_order(self, order_id: str, auth: str, price: float) -> Dict[str, Any]:
        """Executa manualmente uma ordem open (usado em testes)."""
        with self._lock:
            order = self._orders[auth].get(order_id)
            if not order:
                return {"status": "error", "message": "ordem inexistente"}
            if order["status"] not in ("new", "open", "trigger_pending"):
                return {"status": "error", "message": f"ordem no estado {order['status']}"}
            order["status"] = "open"
            self._fill(auth, order, price=price)
            self._persist()
            return {"status": "success", "order_id": order_id}

    def cancel_order(self, order_id: str, auth: str) -> Dict[str, Any]:
        with self._lock:
            orders = self._orders.get(auth, {})
            order = orders.get(order_id)
            if not order:
                return {"status": "error", "message": "ordem inexistente"}
            if order["status"] in ("complete", "cancelled", "rejected"):
                return {"status": "error", "message": f"ordem ja {order['status']}"}
            order["status"] = "cancelled"
            self._persist()
            return {"status": "success", "order_id": order_id, "message": "cancelada"}

    def modify_order(self, order_id: str, req: OrderRequest, auth: str) -> Dict[str, Any]:
        with self._lock:
            orders = self._orders.get(auth, {})
            order = orders.get(order_id)
            if not order:
                return {"status": "error", "message": "ordem inexistente"}
            if order["status"] not in ("new", "open", "trigger_pending"):
                return {"status": "error", "message": f"ordem no estado {order['status']}"}
            order.update(
                quantity=int(req.quantity), price=float(req.price or order["price"]),
                trigger_price=float(req.trigger_price or order["trigger_price"]),
                status="open",
            )
            self._persist()
            return {"status": "success", "order_id": order_id, "message": "modificada"}

    def get_orders(self, auth: str) -> List[Dict[str, Any]]:
        with self._lock:
            return list(self._orders.get(auth, {}).values())

    def get_trades(self, auth: str) -> List[Dict[str, Any]]:
        with self._lock:
            return list(self._trades.get(auth, []))

    def get_positions(self, auth: str) -> List[Dict[str, Any]]:
        with self._lock:
            out = []
            for p in self._positions.get(auth, {}).values():
                p = dict(p)
                if self._use_live_quotes:
                    live = self._get_quote_price(p["symbol"])
                    if live:
                        p["ltp"] = live
                ltp = float(p.get("ltp") or p["average_price"])
                p["unrealized_pnl"] = round(
                    (ltp - p["average_price"]) * p["quantity"], 2)
                p["realized_pnl"] = float(p.get("realized_pnl", 0.0) or 0.0)
                out.append(p)
            return out

    def get_holdings(self, auth: str) -> List[Dict[str, Any]]:
        # corretora fantasma: holdings = posicoes CNC com PnL pela cotacao
        return [
            {**p, "product": "CNC", "pnl": p["unrealized_pnl"]}
            for p in self.get_positions(auth)
        ]

    def get_funds(self, auth: str) -> Dict[str, Any]:
        with self._lock:
            cash = self._cash.get(auth, self._initial_cash)
            used = 0.0
            for o in self._orders.get(auth, {}).values():
                if o["status"] in ("open", "new", "trigger_pending"):
                    used += o["price"] * o["quantity"]
            return {
                "availablecash": f"{cash - used:.2f}",
                "collateral": "0.00",
                "m2munrealized": "0.00",
                "m2mrealized": "0.00",
                "utiliseddebits": f"{used:.2f}",
            }

    # -- motor de ticks (corretora fantasma) -------------------------------
    def tick(self) -> Dict[str, Any]:
        """Um ciclo da corretora: busca cotacoes e executa ordens que cruzaram.

        LIMIT: compra executa se preco <= limite; venda se preco >= limite.
        SL/SL-M: gatilho disparado quando preco cruza trigger; SL vira
        ordem a mercado simulada (execucao no preco do tick).
        Retorna resumo {"quotes": n, "filled": [ids], "triggered": [ids]}.
        """
        filled: List[str] = []
        triggered: List[str] = []
        with self._lock:
            for auth, orders in list(self._orders.items()):
                for oid, order in list(orders.items()):
                    if order["status"] not in ("new", "open", "trigger_pending"):
                        continue
                    price = self._get_quote_price(order["symbol"])
                    if price is None:
                        continue
                    otype = order["order_type"]
                    side = order["side"]
                    if otype == "LIMIT":
                        ok = (side == "BUY" and price <= order["price"]) or \
                             (side == "SELL" and price >= order["price"])
                        if ok:
                            self._fill(auth, order, price=price)
                            filled.append(oid)
                    elif otype in ("SL", "SL-M", "STOP_LIMIT", "STOP_MARKET"):
                        trig = order["trigger_price"] or order["price"]
                        crossed = (side == "BUY" and price >= trig) or \
                                  (side == "SELL" and price <= trig)
                        if crossed:
                            self._fill(auth, order, price=price)
                            triggered.append(oid)
            # atualiza ltp das posicoes
            for positions in self._positions.values():
                for p in positions.values():
                    live = self._get_quote_price(p["symbol"])
                    if live:
                        p["ltp"] = live
            self._persist()
        return {"quotes": len(self._quotes), "filled": filled, "triggered": triggered}

    def _tick_loop(self) -> None:
        while not self._tick_stop.wait(self._auto_tick_seconds):
            try:
                self.tick()
            except Exception:  # noqa: BLE001 â€” thread nunca derruba o processo
                pass

    def stop_tick(self) -> None:
        """Encerra o motor de ticks em background."""
        self._tick_stop.set()
        if self._tick_thread and self._tick_thread.is_alive():
            self._tick_thread.join(timeout=2.0)