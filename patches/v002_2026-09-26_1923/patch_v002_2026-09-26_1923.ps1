# ============================================================
# patch.ps1 - aplicador automatico de correcoes
# Projeto: openalgo-b3-adapter
# Versao:  v002_2026-09-26_1923  |  Arquivos: 3
# Descricao: singleton gateway + persistencia sandbox + schema master contract
#
# COMO USAR (na raiz da instalacao replicada):
#   powershell -ExecutionPolicy Bypass -File .\patch_v002_2026-09-26_1923.ps1
#
# O QUE ELE FAZ (nesta ordem):
#   0. recusa re-aplicacao (patches\registro.csv) e pede confirmacao
#   1. cria a pasta patches\v002_2026-09-26_1923\
#   2. backup dos arquivos ATUAIS em v002_2026-09-26_1923\anteriores\
#      (arquivo novo = inclusao, sem backup)
#   3. grava os arquivos corrigidos nos lugares devidos
#      (UTF-8 sem BOM; cria subpastas se faltar)
#   4. guarda copia versionada dos novos em v002_2026-09-26_1923\
#   5. guarda copia versionada DE SI MESMO em v002_2026-09-26_1923\
#   6. anexa uma linha no patches\registro.csv
#   7. mostra o resumo, espera ENTER e SE AUTODESTRUI
#
# RASTREIO: patches\registro.csv guarda versao, data, arquivos e
# resultado. ROLLBACK MANUAL: copie de v002_2026-09-26_1923\anteriores\.
#
# REGRAS DO PROJETO: pausa antes de qualquer saida, confirmacao
# antes de tocar em qualquer arquivo, token nunca gravado.
# ============================================================

$ErrorActionPreference = "Stop"
$Raiz = $PSScriptRoot
if (-not $Raiz) { $Raiz = (Get-Location).Path }

$Ver  = "v002_2026-09-26_1923"
$Desc = "singleton gateway + persistencia sandbox + schema master contract"

Write-Host ""
Write-Host "=== PATCH AUTOMATICO - openalgo-b3-adapter ===" -ForegroundColor Cyan
Write-Host "Versao: $Ver"
Write-Host "Descricao: $Desc"
Write-Host "Raiz do projeto: $Raiz"
Write-Host ""

# --- 0. recusa re-aplicacao ---
$Registro = Join-Path $Raiz "patches\registro.csv"
if (Test-Path $Registro) {
    $ja = Get-Content $Registro -ErrorAction SilentlyContinue |
          Where-Object { $_ -match "^$Ver;" }
    if ($ja) {
        Write-Host "Patch $Ver JA aplicado (registro.csv). Nada a fazer." -ForegroundColor Yellow
        Read-Host "Pressione ENTER para sair"
        exit 0
    }
}

# --- confirmacao antes de tocar em qualquer arquivo ---
$r = Read-Host "Aplicar este patch? [S/N]"
if ($r -ne "S" -and $r -ne "s") {
    Write-Host "Cancelado. Nenhum arquivo foi tocado."
    Read-Host "Pressione ENTER para sair"
    exit 0
}

# --- pasta da versao ---
$DirVer = Join-Path $Raiz "patches\$Ver"
$DirAnt = Join-Path $DirVer "anteriores"
New-Item -ItemType Directory -Force -Path $DirVer | Out-Null
New-Item -ItemType Directory -Force -Path $DirAnt | Out-Null

# --- arquivos embutidos: destino relativo -> conteudo novo ---
$Arquivos = @{

    "openalgo_b3_adapter\order_execution\b3_orders.py" = @'
"""Gateways de execucao de ordens (padrao B3).

`B3OrderGateway` e a interface que cada corretora brasileira implementa.
O registro global escolhe o gateway via env B3_BROKER_GATEWAY (padrao:
sandbox). Gateways reais dependem de onboarding com a corretora (veja
brokers/nuinvest.py e brokers/btg.py para stubs documentados).

SandboxGateway: simulador in-memory deterministico, com ciclo de vida de
ordem (new/open/complete/cancelled/rejected), book, posicoes e funds —
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
    `br_symbol` e o código B3 resolvido pelo master contract (plugin).
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
      e SL/SL-M (disparo no gatilho) — comportamento de corretora,
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
        except Exception:  # noqa: BLE001 — estado corrompido: comeca limpo
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
        except Exception:  # noqa: BLE001 — sem rede: usa ultimo preco conhecido
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
            except Exception:  # noqa: BLE001 — thread nunca derruba o processo
                pass

    def stop_tick(self) -> None:
        """Encerra o motor de ticks em background."""
        self._tick_stop.set()
        if self._tick_thread and self._tick_thread.is_alive():
            self._tick_thread.join(timeout=2.0)
'@

    "tests\conftest.py" = @'
"""Stubs das dependências do core OpenAlgo para importar o plugin standalone."""
import logging
import sys
import types


def _ensure_module(name):
    if name in sys.modules:
        return sys.modules[name]
    mod = types.ModuleType(name)
    sys.modules[name] = mod
    return mod


# --- utils.logging (openalgo) ---
utils_mod = _ensure_module("utils")
logging_mod = _ensure_module("utils.logging")
logging_mod.get_logger = lambda name=None: logging.getLogger(name or "test")
utils_mod.logging = logging_mod
if not hasattr(utils_mod, "__path__"):
    utils_mod.__path__ = []  # marca como pacote para submodulos

# --- database.token_db (openalgo) ---
database_mod = _ensure_module("database")
token_db = _ensure_module("database.token_db")
_FAKE_MAP = {
    # (oa_symbol, exchange) -> br_symbol
    ("PETR4", "NSE"): "PETR4",
    ("VALE3", "NSE"): "VALE3",
    ("PETR4F", "NSE"): "PETR4F",
    ("WINJ26", "MCX"): "WINJ26",
    ("PETR4-2026-06-19-35.00-C", "NFO"): "PETRA331",
}
token_db.get_br_symbol = lambda symbol, exchange: _FAKE_MAP.get((symbol, exchange))
token_db.get_oa_symbol = lambda br_symbol, exchange: br_symbol
token_db.get_token = lambda symbol, exchange: _FAKE_MAP.get((symbol, exchange))
database_mod.token_db = token_db
if not hasattr(database_mod, "__path__"):
    database_mod.__path__ = []


# --- isolacao da corretora fantasma -------------------------------------
# O SandboxGateway agora persiste por padrao em ~/.b3_adapter/sandbox_state.json.
# Cada teste recebe um arquivo de estado proprio para nao vazar estado entre
# testes nem para o ambiente real do usuario.
try:
    import pytest

    @pytest.fixture(autouse=True)
    def _b3_isolated_sandbox_state(monkeypatch, tmp_path):
        monkeypatch.setenv(
            "B3_SANDBOX_STATE_FILE", str(tmp_path / "b3_sandbox_state.json")
        )
except ImportError:  # pragma: no cover — ambiente sem pytest (stubs standalone)
    pass
'@

    "openalgo_plugin\broker\b3\database\master_contract_db.py" = @'
"""Master contract B3: popula a tabela symtoken do OpenAlgo.

Fontes:
  1. Semente offline (openalgo_b3_adapter.market_data.b3_seed) — sempre disponivel,
     cobre os papeis/futuros mais liquidos.
  2. Brapi (opcional): lista completa de tickers quando BRAPI_API_KEY esta
     definida (best-effort; falha silenciosa cai na semente).

Simbolos no espaco OpenAlgo:
  - a vista/futuros/indices: idênticos ao código B3 (PETR4, WINJ26, IBOV)
  - opcoes: notacao estruturada (BASE-YYYY-MM-DD-STRIKE-C/P) com brsymbol
    = código oficial da B3 (ex.: PETRA331)
Exchanges gravadas: codigos genericos aceitos pelo core (NSE/NFO/MCX/NSE_INDEX)
com brexchange B3/B3OPT/B3FUT — veja docs/INSTALL.md (modo zero-mod).
"""
import os

import pandas as pd
from sqlalchemy import Column, Float, Index, Integer, Sequence, String
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import scoped_session, sessionmaker

from database.engine_factory import create_db_engine
from openalgo_b3_adapter.config.b3_config import (
    OA_EXCHANGE_SEGMENT_MAP, SEGMENT_BREXCHANGE,
)
from openalgo_b3_adapter.market_data.b3_seed import SEED_INSTRUMENTS, SEED_OPTION_EXAMPLES

try:
    from extensions import socketio
except ImportError:
    socketio = None

DATABASE_URL = os.getenv("DATABASE_URL")
engine = create_db_engine(DATABASE_URL)
db_session = scoped_session(sessionmaker(autocommit=False, autoflush=False, bind=engine))
Base = declarative_base()
Base.query = db_session.query_property()

_SEGMENT_TO_OA_EXCHANGE = {v: k for k, v in OA_EXCHANGE_SEGMENT_MAP.items()}


class SymToken(Base):
    __tablename__ = "symtoken"
    id = Column(Integer, Sequence("symtoken_id_seq"), primary_key=True)
    symbol = Column(String, nullable=False, index=True)
    brsymbol = Column(String, nullable=False, index=True)
    name = Column(String)
    exchange = Column(String, index=True)
    brexchange = Column(String, index=True)
    token = Column(String, index=True)
    expiry = Column(String)
    strike = Column(Float)
    lotsize = Column(Integer)
    instrumenttype = Column(String)
    tick_size = Column(Float)
    contract_value = Column(Float)
    __table_args__ = (Index("idx_symbol_exchange", "symbol", "exchange"),)


def init_db():
    db_path = os.path.dirname(DATABASE_URL.replace("sqlite:///", "")) if DATABASE_URL else None
    if db_path and not os.path.exists(db_path):
        os.makedirs(db_path)
    Base.metadata.create_all(bind=engine)


def delete_symtoken_table():
    try:
        SymToken.__table__.drop(bind=engine)
        db_session.commit()
    except Exception:
        db_session.rollback()


def copy_from_dataframe(df):
    if df is None or df.empty:
        return 0
    engine_exec = db_session.get_bind()
    df.to_sql("symtoken", engine_exec, if_exists="append", index=False)
    db_session.commit()
    return len(df)


def _seed_rows():
    rows = []
    for symbol, name, kind, lot, tick, segment in SEED_INSTRUMENTS:
        rows.append({
            "symbol": symbol, "brsymbol": symbol, "name": name,
            "exchange": _SEGMENT_TO_OA_EXCHANGE.get(segment, "NSE"),
            "brexchange": SEGMENT_BREXCHANGE.get(segment, "B3"),
            "token": symbol, "expiry": "", "strike": 0.0,
            "lotsize": lot, "instrumenttype": kind, "tick_size": tick,
        })
    # opcoes ilustrativas (produção: download oficial da série vigente)
    for oa_symbol, br_symbol, base, lot, tick in SEED_OPTION_EXAMPLES:
        parts = oa_symbol.split("-")
        rows.append({
            "symbol": oa_symbol, "brsymbol": br_symbol, "name": f"Opcao {base}",
            "exchange": "NFO", "brexchange": "B3OPT", "token": br_symbol,
            "expiry": parts[1], "strike": float(parts[2]),
            "lotsize": lot, "instrumenttype": "OPTSTK", "tick_size": tick,
        })
    # mercado fracionario dos papeis a vista mais liquidos
    for symbol, name, kind, lot, tick, segment in SEED_INSTRUMENTS:
        if segment == "equity" and kind in ("equity", "fii", "etf"):
            rows.append({
                "symbol": f"{symbol}F", "brsymbol": f"{symbol}F", "name": f"{name} (fracionario)",
                "exchange": "NSE", "brexchange": "B3F", "token": f"{symbol}F",
                "expiry": "", "strike": 0.0, "lotsize": 1,
                "instrumenttype": "fractional", "tick_size": tick,
            })
    return rows


def _brapi_ticker_rows():
    """Best-effort: lista de tickers da Brapi quando há chave."""
    import httpx

    from openalgo_b3_adapter.config.b3_config import get_config
    cfg = get_config()
    if not cfg.brapi_api_key:
        return []
    try:
        resp = httpx.get(
            f"{cfg.brapi_base_url}/api/v2/tickers",
            headers={"Authorization": f"Bearer {cfg.brapi_api_key}"},
            timeout=15,
        )
        resp.raise_for_status()
        payload = resp.json()
        tickers = payload.get("tickers") or payload.get("results") or []
        rows = []
        for t in tickers:
            if isinstance(t, dict):
                sym = (t.get("symbol") or t.get("ticker") or "").upper().strip()
            else:
                sym = str(t).upper().strip()
            if not sym or sym in {r["symbol"] for r in _seed_rows()}:
                continue
            kind, lot = ("fii", 10) if sym.endswith("11") else ("equity", 100)
            rows.append({
                "symbol": sym, "brsymbol": sym, "name": sym,
                "exchange": "NSE", "brexchange": "B3", "token": sym,
                "expiry": "", "strike": 0.0, "lotsize": lot,
                "instrumenttype": kind, "tick_size": 0.01,
            })
        return rows
    except Exception:
        return []


def master_contract_download():
    """Ponto de entrada chamado pelo core (async_master_contract_download)."""
    try:
        init_db()
        delete_symtoken_table()
    except Exception:
        db_session.rollback()
    # Recria a tabela com o esquema do core (id PK, indices) antes do to_sql,
    # que senao recriaria a tabela sem a coluna id e quebraria SymToken.query.
    Base.metadata.create_all(bind=engine)

    rows = _seed_rows()
    rows += _brapi_ticker_rows()
    df = pd.DataFrame(rows)
    count = copy_from_dataframe(df)

    if socketio:
        try:
            socketio.emit("master_contract_download_event", {"status": "success", "broker": "b3"})
        except Exception:
            pass
    return {"status": "success", "message": f"B3 master contract: {count} simbolos"}
'@

}

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Alterados = @()
$Incluidos = @()

foreach ($dest in $Arquivos.Keys) {
    $alvo = Join-Path $Raiz $dest
    $dirAlvo = Split-Path $alvo -Parent
    if (-not (Test-Path $dirAlvo)) {
        New-Item -ItemType Directory -Force -Path $dirAlvo | Out-Null
    }
    if (Test-Path $alvo) {
        # 2. backup da versao ATUAL (antiga) antes de sobrescrever
        $bk = Join-Path $DirAnt ($dest -replace "[\\/]", "__")
        Copy-Item -LiteralPath $alvo -Destination $bk -Force
        $Alterados += $dest
    } else {
        $Incluidos += $dest
    }
    # 3. grava o conteudo corrigido (UTF-8 sem BOM)
    [System.IO.File]::WriteAllText($alvo, $Arquivos[$dest], $Utf8NoBom)
    # 4. copia versionada do arquivo novo
    $cp = Join-Path $DirVer ($dest -replace "[\\/]", "__")
    Copy-Item -LiteralPath $alvo -Destination $cp -Force
}

# --- 5. copia versionada de si mesmo ---
Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $DirVer "patch_v002_2026-09-26_1923.ps1") -Force

# --- 6. registro ---
$linha = "$Ver;2026-09-26 19:23;openalgo_b3_adapter\order_execution\b3_orders.py|tests\conftest.py|openalgo_plugin\broker\b3\database\master_contract_db.py;singleton gateway + persistencia sandbox + schema master contract`n"
[System.IO.File]::AppendAllText($Registro, $linha, $Utf8NoBom)

# --- 7. resumo + autodestruicao ---
Write-Host ""
Write-Host "========================================"
Write-Host "Patch $Ver aplicado:"
foreach ($a in $Alterados) { Write-Host "  alterado : $a" }
foreach ($a in $Incluidos) { Write-Host "  incluido : $a" }
Write-Host "Backup (versao antiga): patches\$Ver\anteriores\"
Write-Host "Copias versionadas    : patches\$Ver\"
Write-Host "Registro atualizado   : patches\registro.csv"
Write-Host "========================================"
Read-Host "Pressione ENTER para concluir e remover o script"

Remove-Item -LiteralPath $PSCommandPath -Force
Write-Host "Script de patch removido (autodestruicao). Ate logo."
