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
    return factory()


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

class SandboxGateway(B3OrderGateway):
    """Simulador deterministico com ciclo de vida de ordem B3.

    - Ordem MARKET: executada imediatamente a `reference_price` (ou 100.00
      se ausente) e registrada no tradebook.
    - Ordem LIMIT/SL: fica 'open' ate `fill_order()` (testes) ou cancelada.
    - Estado por auth token; funds com saldo inicial configuravel.
    """

    name = "sandbox"

    def __init__(self, initial_cash: float = 100_000.0, ignore_sessions: Optional[bool] = None):
        self._lock = threading.Lock()
        self._ids = itertools.count(1)
        self._initial_cash = initial_cash
        self._ignore_sessions = (
            get_config().sandbox_ignore_sessions
            if ignore_sessions is None else ignore_sessions
        )
        # estado por auth token
        self._orders: Dict[str, Dict[str, Dict[str, Any]]] = {}
        self._trades: Dict[str, List[Dict[str, Any]]] = {}
        self._cash: Dict[str, float] = {}
        self._positions: Dict[str, Dict[str, Dict[str, Any]]] = {}

    # -- helpers internos --------------------------------------------------
    def _state(self, auth: str, create: bool = False):
        if auth not in self._orders:
            if not create:
                raise ValueError("auth desconhecido no sandbox (chame auth primeiro)")
            self._orders[auth] = {}
            self._trades[auth] = []
            self._cash[auth] = self._initial_cash
            self._positions[auth] = {}
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
                self._fill(auth, order, price=req.reference_price or 100.0)
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
        pos = self._positions[auth].setdefault(order["symbol"], {"symbol": order["symbol"], "oa_symbol": order["oa_symbol"], "exchange": order["exchange"], "quantity": 0, "average_price": 0.0})
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
            if order["status"] not in ("new", "open"):
                return {"status": "error", "message": f"ordem no estado {order['status']}"}
            order["status"] = "open"
            self._fill(auth, order, price=price)
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
            return {"status": "success", "order_id": order_id, "message": "cancelada"}

    def modify_order(self, order_id: str, req: OrderRequest, auth: str) -> Dict[str, Any]:
        with self._lock:
            orders = self._orders.get(auth, {})
            order = orders.get(order_id)
            if not order:
                return {"status": "error", "message": "ordem inexistente"}
            if order["status"] not in ("new", "open"):
                return {"status": "error", "message": f"ordem no estado {order['status']}"}
            order.update(
                quantity=int(req.quantity), price=float(req.price or order["price"]),
                trigger_price=float(req.trigger_price or order["trigger_price"]),
                status="open",
            )
            return {"status": "success", "order_id": order_id, "message": "modificada"}

    def get_orders(self, auth: str) -> List[Dict[str, Any]]:
        with self._lock:
            return list(self._orders.get(auth, {}).values())

    def get_trades(self, auth: str) -> List[Dict[str, Any]]:
        with self._lock:
            return list(self._trades.get(auth, []))

    def get_positions(self, auth: str) -> List[Dict[str, Any]]:
        with self._lock:
            return list(self._positions.get(auth, {}).values())

    def get_holdings(self, auth: str) -> List[Dict[str, Any]]:
        # sandbox: holdings = posicoes CNC fechadas (simplificacao)
        with self._lock:
            return [
                {**p, "product": "CNC", "pnl": 0.0}
                for p in self._positions.get(auth, {}).values()
            ]

    def get_funds(self, auth: str) -> Dict[str, Any]:
        with self._lock:
            cash = self._cash.get(auth, self._initial_cash)
            used = 0.0
            for o in self._orders.get(auth, {}).values():
                if o["status"] in ("open", "new"):
                    used += o["price"] * o["quantity"]
            return {
                "availablecash": f"{cash - used:.2f}",
                "collateral": "0.00",
                "m2munrealized": "0.00",
                "m2mrealized": "0.00",
                "utiliseddebits": f"{used:.2f}",
            }
