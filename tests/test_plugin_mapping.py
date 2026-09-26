"""Testa os modulos de mapping do plugin com os stubs do conftest."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "openalgo_plugin"))

from broker.b3.mapping.order_data import (  # noqa: E402
    calculate_order_statistics, transform_holdings_data, transform_order_data,
    transform_positions_data, transform_tradebook_data,
)
from broker.b3.mapping.transform_data import transform_data  # noqa: E402


def test_transform_data_resolves_br_symbol():
    data = {"symbol": "PETR4", "exchange": "NSE", "action": "BUY",
            "quantity": 100, "pricetype": "LIMIT", "price": 33.45}
    req = transform_data(data)
    assert req.symbol == "PETR4"
    assert req.side == "BUY"
    assert req.quantity == 100
    assert req.order_type == "LIMIT"


def test_transform_data_option_uses_master_contract():
    data = {"symbol": "PETR4-2026-06-19-35.00-C", "exchange": "NFO",
            "action": "SELL", "quantity": 100, "pricetype": "MARKET"}
    req = transform_data(data)
    assert req.symbol == "PETRA331"          # código B3 via symtoken
    assert req.oa_symbol == "PETR4-2026-06-19-35.00-C"


RAW_ORDERS = [{
    "order_id": "B3SBX-000001", "symbol": "PETR4", "oa_symbol": "PETR4",
    "exchange": "NSE", "side": "BUY", "quantity": 100, "order_type": "LIMIT",
    "price": 33.45, "trigger_price": 0.0, "product": "CNC", "status": "complete",
    "filled_quantity": 100, "average_price": 33.45,
    "created_at": "2026-09-24T11:30:00+00:00",
}]


def test_transform_order_data():
    out = transform_order_data(RAW_ORDERS)
    assert out[0]["symbol"] == "PETR4"
    assert out[0]["exchange"] == "NSE"
    assert out[0]["action"] == "BUY"
    assert out[0]["pricetype"] == "LIMIT"
    assert out[0]["orderid"] == "B3SBX-000001"
    assert out[0]["order_status"] == "complete"
    assert out[0]["pending_quantity"] == 0
    assert out[0]["average_price"] == 33.45


def test_statistics_and_stop_pricetype():
    raw = [
        dict(RAW_ORDERS[0]),
        {**RAW_ORDERS[0], "order_id": "B2", "status": "open",
         "filled_quantity": 0, "order_type": "SL-M"},
        {**RAW_ORDERS[0], "order_id": "B3", "status": "rejected", "side": "SELL"},
    ]
    stats = calculate_order_statistics(raw)
    assert stats["total_buy_orders"] == 2
    assert stats["total_sell_orders"] == 1
    assert stats["total_completed_orders"] == 1
    assert stats["total_open_orders"] == 1
    assert stats["total_rejected_orders"] == 1
    assert transform_order_data(raw)[1]["pricetype"] == "SL-M"


def test_transform_tradebook_and_positions_and_holdings():
    trades = [{
        "trade_id": "T-1", "order_id": "B3SBX-000001", "symbol": "PETR4",
        "oa_symbol": "PETR4", "exchange": "NSE", "side": "BUY",
        "quantity": 100, "price": 33.45, "executed_at": "2026-09-24T11:30:00+00:00",
        "product": "CNC",
    }]
    t = transform_tradebook_data(trades)[0]
    assert t["average_price"] == 33.45
    assert t["trade_value"] == 3345.0

    positions = [{"symbol": "PETR4", "oa_symbol": "PETR4", "exchange": "NSE",
                  "quantity": 100, "average_price": 33.45,
                  "realized_pnl": 0.0, "unrealized_pnl": 55.0, "ltp": 34.0,
                  "product": "CNC"}]
    p = transform_positions_data(positions)[0]
    assert p["pnl"] == 55.0
    assert p["quantity"] == 100

    holdings = [{"symbol": "PETR4", "oa_symbol": "PETR4", "exchange": "NSE",
                 "quantity": 100, "average_price": 33.45, "pnl": 55.0,
                 "product": "CNC"}]
    h = transform_holdings_data(holdings)[0]
    assert h["product"] == "CNC"
    assert h["pnlpercent"] == round(55.0 / (33.45 * 100) * 100, 2)
