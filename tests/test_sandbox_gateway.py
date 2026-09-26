import pytest

from openalgo_b3_adapter.order_execution import (
    OrderRequest, SandboxGateway, get_gateway,
)


def _gw():
    return SandboxGateway(ignore_sessions=True)


def _place(gw, **kw):
    base = dict(symbol="PETR4", side="BUY", quantity=100, order_type="MARKET",
                exchange="NSE", oa_symbol="PETR4")
    base.update(kw)
    req = OrderRequest(**base)
    return gw.place_order(req, "user1")


def test_market_order_fills_immediately():
    gw = _gw()
    res = _place(gw, reference_price=33.50)
    assert res["status"] == "success"
    orders = gw.get_orders("user1")
    assert orders[0]["status"] == "complete"
    assert orders[0]["average_price"] == 33.50
    trades = gw.get_trades("user1")
    assert trades[0]["price"] == 33.50
    assert gw.get_positions("user1")[0]["quantity"] == 100


def test_limit_order_stays_open_until_fill():
    gw = _gw()
    res = _place(gw, order_type="LIMIT", price=33.45)
    oid = res["order_id"]
    assert gw.get_orders("user1")[0]["status"] == "new"
    # cancelamento
    assert gw.cancel_order(oid, "user1")["status"] == "success"
    assert gw.get_orders("user1")[0]["status"] == "cancelled"
    assert gw.cancel_order(oid, "user1")["status"] == "error"


def test_fill_and_modify():
    gw = _gw()
    res = _place(gw, order_type="LIMIT", price=33.45)
    oid = res["order_id"]
    mod = OrderRequest(symbol="PETR4", side="BUY", quantity=200, order_type="LIMIT",
                       price=33.40, exchange="NSE", oa_symbol="PETR4")
    assert gw.modify_order(oid, mod, "user1")["status"] == "success"
    assert gw.get_orders("user1")[0]["quantity"] == 200
    assert gw.fill_order(oid, "user1", price=33.40)["status"] == "success"
    assert gw.get_orders("user1")[0]["status"] == "complete"


def test_sell_flattens_position():
    gw = _gw()
    _place(gw, reference_price=30.0)
    _place(gw, side="SELL", reference_price=31.0)
    assert gw.get_positions("user1") == []


def test_rejected_order_on_invalid_lot():
    gw = SandboxGateway(ignore_sessions=True)
    req = OrderRequest(symbol="PETR4", side="BUY", quantity=150, order_type="MARKET",
                       exchange="NSE")
    res = gw.place_order(req, "u")
    assert res["status"] == "rejected"
    assert "lote" in res["message"]


def test_funds_shape():
    gw = _gw()
    funds = gw.get_funds("user1")
    assert set(funds) == {"availablecash", "collateral", "m2munrealized",
                          "m2mrealized", "utiliseddebits"}
    assert float(funds["availablecash"]) == 100000.00


def test_gateway_registry_default_sandbox(monkeypatch):
    monkeypatch.delenv("B3_BROKER_GATEWAY", raising=False)
    gw = get_gateway()
    assert isinstance(gw, SandboxGateway)


def test_gateway_registry_unknown(monkeypatch):
    monkeypatch.setenv("B3_BROKER_GATEWAY", "xpinvest")
    with pytest.raises(ValueError, match="desconhecido"):
        get_gateway()


def test_nuinvest_gateway_stub_raises_without_credentials(monkeypatch):
    monkeypatch.setenv("NUINVEST_BEARER_TOKEN", "")
    from openalgo_b3_adapter.order_execution.brokers.nuinvest import NuInvestGateway
    with pytest.raises(NotImplementedError):
        NuInvestGateway()
