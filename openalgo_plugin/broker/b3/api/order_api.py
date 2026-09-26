"""Execucao de ordens do plugin B3 (contrato do core: broker.<n>.api.order_api).

Todos os metodos delegam ao gateway B3 (sandbox por padrao). Respostas seguem
a convencao do OpenAlgo:
    place_order_api -> (res, response_data, orderid)
    cancel/modify   -> (res, response_data)
"""
from openalgo_b3_adapter.order_execution import get_gateway
from openalgo_b3_adapter.order_execution.b3_validation import OrderRequest

from broker.b3.mapping.transform_data import transform_data
from utils.logging import get_logger

logger = get_logger(__name__)


class _Res:
    """Wrapper minimo compativel com o `res` que o core espera."""

    def __init__(self, ok: bool):
        self.status_code = 200 if ok else 500
        self.status = self.status_code


# ------------------------------------------------------------------ ordens
def place_order_api(data, auth):
    try:
        req = transform_data(data, auth_token=auth)
        gateway = get_gateway()
        result = gateway.place_order(req, auth)
    except Exception as exc:  # noqa: BLE001
        logger.exception("B3 place_order error")
        return _Res(False), {"status": "error", "message": str(exc)}, None

    if result.get("status") == "success":
        orderid = result.get("order_id")
        return _Res(True), {"status": "success", "orderid": orderid,
                            "message": result.get("message", "")}, orderid
    return _Res(False), {"status": "error", "message": result.get("message", "rejeitada")}, None


def place_smartorder_api(data, auth):
    """Smart order: agrega posicao atual (mesma semantica dos outros plugins)."""
    try:
        req = transform_data(data, auth_token=auth)
        gateway = get_gateway()
        current_qty = 0
        for pos in gateway.get_positions(auth):
            if pos.get("oa_symbol") == req.oa_symbol:
                current_qty = int(pos.get("quantity", 0) or 0)
                break
        target = int(data.get("position_size") or 0)
        delta = target - current_qty
        if delta == 0:
            return _Res(True), {"status": "success", "orderid": None,
                                "message": "posicao ja igual ao alvo"}, None
        req.side = "BUY" if delta > 0 else "SELL"
        req.quantity = abs(delta)
        # fracionario alvo abaixo do lote: cancela e avisa
        result = gateway.place_order(req, auth)
        if result.get("status") == "success":
            return _Res(True), {"status": "success", "orderid": result.get("order_id"),
                                "message": result.get("message", "")}, result.get("order_id")
        return _Res(False), {"status": "error", "message": result.get("message", "")}, None
    except Exception as exc:  # noqa: BLE001
        logger.exception("B3 smart order error")
        return _Res(False), {"status": "error", "message": str(exc)}, None


def cancel_order(orderid, auth):
    gateway = get_gateway()
    result = gateway.cancel_order(str(orderid), auth)
    ok = result.get("status") == "success"
    return _Res(ok), result


def modify_order(data, auth):
    gateway = get_gateway()
    orderid = str(data.get("orderid"))
    try:
        req = transform_data(data, auth_token=auth)
    except Exception as exc:  # noqa: BLE001
        return _Res(False), {"status": "error", "message": str(exc)}
    result = gateway.modify_order(orderid, req, auth)
    ok = result.get("status") == "success"
    return _Res(ok), result


def cancel_all_orders_api(data, auth):
    gateway = get_gateway()
    cancelled = 0
    for order in gateway.get_orders(auth):
        if order.get("status") in ("new", "open"):
            res = gateway.cancel_order(order["order_id"], auth)
            cancelled += 1 if res.get("status") == "success" else 0
    return _Res(True), {"status": "success", "message": f"{cancelled} ordens canceladas"}


def close_all_positions(current_api_key, auth):
    gateway = get_gateway()
    closed = 0
    for pos in gateway.get_positions(auth):
        req = OrderRequest(
            symbol=pos["symbol"], oa_symbol=pos.get("oa_symbol"),
            side="SELL" if pos["quantity"] > 0 else "BUY",
            quantity=abs(pos["quantity"]), order_type="MARKET",
            product="CNC", exchange=pos.get("exchange", "NSE"),
        )
        result = gateway.place_order(req, auth)
        closed += 1 if result.get("status") == "success" else 0
    return _Res(True), {"status": "success", "message": f"{closed} posicoes encerradas"}


# -------------------------------------------------------------- consultas
def get_order_book(auth):
    return get_gateway().get_orders(auth)


def get_trade_book(auth):
    return get_gateway().get_trades(auth)


def get_positions(auth):
    return get_gateway().get_positions(auth)


def get_holdings(auth):
    return get_gateway().get_holdings(auth)


def get_open_position(tradingsymbol, exchange, product, auth):
    """Posicao liquida do simbolo (usado pelo core em smart orders)."""
    for pos in get_gateway().get_positions(auth):
        if pos.get("oa_symbol") == tradingsymbol and pos.get("exchange") == exchange:
            return int(pos.get("quantity", 0) or 0)
    return 0
