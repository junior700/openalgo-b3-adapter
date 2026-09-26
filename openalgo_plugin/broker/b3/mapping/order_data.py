"""Mapeamentos orderbook/tradebook/positions/holdings -> formato OpenAlgo.

O formato raw do gateway B3 (veja SandboxGateway) ja carrega
oa_symbol/exchange, entao map_* resolve pouco e transform_* devolve os
campos padronizados esperados pelo core:
    transform_order_data: symbol, exchange, action, quantity, price,
        trigger_price, pricetype, product, orderid, order_status, timestamp,
        filled_quantity, pending_quantity, average_price
    transform_tradebook_data: symbol, exchange, product, action, quantity,
        average_price, trade_value, orderid, timestamp
    transform_positions_data: symbol, exchange, product, quantity,
        average_price, realized_pnl, unrealized_pnl, ltp, pnl
    transform_holdings_data: symbol, exchange, quantity, product, avg_price,
        pnl, pnlpercent
"""
from utils.logging import get_logger

logger = get_logger(__name__)

_B3_TO_OA_STATUS = {
    "new": "open", "open": "open",
    "complete": "complete",
    "cancelled": "cancelled", "canceled": "cancelled",
    "rejected": "rejected",
}
_B3_TO_OA_PRICETYPE = {
    "MARKET": "MARKET", "LIMIT": "LIMIT",
    "STOP_LIMIT": "SL", "STOP_MARKET": "SL-M",
}


def normalize_order_status(raw_status):
    s = str(raw_status or "").strip().lower()
    if s in _B3_TO_OA_STATUS:
        return _B3_TO_OA_STATUS[s]
    return s


# ---------------------------------------------------------------- orderbook
def map_order_data(order_data):
    """Resolve oa_symbol/exchange no payload raw (gateway ja os carrega)."""
    if not order_data:
        return order_data or []
    for order in order_data:
        if isinstance(order, dict) and "oa_symbol" in order:
            order["tsym"] = order["oa_symbol"]
    return order_data


def transform_order_data(orders):
    out = []
    for order in orders or []:
        if not isinstance(order, dict):
            continue
        qty = int(order.get("quantity", 0) or 0)
        filled = int(order.get("filled_quantity", 0) or 0)
        out.append({
            "symbol": order.get("oa_symbol") or order.get("tsym") or order.get("symbol", ""),
            "exchange": order.get("exchange", ""),
            "action": order.get("side", ""),
            "quantity": qty,
            "price": float(order.get("price", 0) or 0),
            "trigger_price": float(order.get("trigger_price", 0) or 0),
            "pricetype": _B3_TO_OA_PRICETYPE.get(order.get("order_type", ""), order.get("order_type", "")),
            "product": order.get("product", ""),
            "orderid": order.get("order_id", ""),
            "order_status": normalize_order_status(order.get("status")),
            "timestamp": order.get("created_at", ""),
            "filled_quantity": filled,
            "pending_quantity": max(qty - filled, 0),
            "average_price": float(order.get("average_price", 0) or 0),
        })
    return out


def calculate_order_statistics(order_data):
    stats = {"total_buy_orders": 0, "total_sell_orders": 0, "total_completed_orders": 0,
             "total_open_orders": 0, "total_rejected_orders": 0, "total_cancelled_orders": 0}
    for order in transform_order_data(order_data or []):
        if order["action"] == "BUY":
            stats["total_buy_orders"] += 1
        elif order["action"] == "SELL":
            stats["total_sell_orders"] += 1
        st = order["order_status"]
        if st == "complete":
            stats["total_completed_orders"] += 1
        elif st == "open":
            stats["total_open_orders"] += 1
        elif st == "rejected":
            stats["total_rejected_orders"] += 1
        elif st == "cancelled":
            stats["total_cancelled_orders"] += 1
    return stats


# --------------------------------------------------------------- tradebook
def map_trade_data(trade_data):
    return trade_data or []


def transform_tradebook_data(tradebook_data):
    out = []
    for trade in tradebook_data or []:
        qty = int(trade.get("quantity", 0) or 0)
        avg_price = round(float(trade.get("price", 0) or 0), 2)
        out.append({
            "symbol": trade.get("oa_symbol") or trade.get("symbol", ""),
            "exchange": trade.get("exchange", ""),
            "product": trade.get("product", "CNC"),
            "action": trade.get("side", ""),
            "quantity": qty,
            "average_price": avg_price,
            "trade_value": round(avg_price * qty, 2),
            "orderid": trade.get("order_id", ""),
            "timestamp": trade.get("executed_at", ""),
        })
    return out


# ---------------------------------------------------------------- positions
def map_position_data(position_data):
    return position_data or []


def transform_positions_data(positions_data):
    out = []
    for p in positions_data or []:
        qty = int(p.get("quantity", 0) or 0)
        avg = float(p.get("average_price", 0) or 0)
        out.append({
            "symbol": p.get("oa_symbol") or p.get("symbol", ""),
            "exchange": p.get("exchange", ""),
            "product": p.get("product", "CNC"),
            "quantity": qty,
            "average_price": avg,
            "realized_pnl": float(p.get("realized_pnl", 0) or 0),
            "unrealized_pnl": float(p.get("unrealized_pnl", 0) or 0),
            "ltp": float(p.get("ltp", 0) or 0),
            "pnl": round(float(p.get("realized_pnl", 0) or 0) + float(p.get("unrealized_pnl", 0) or 0), 2),
        })
    return out


# ---------------------------------------------------------------- holdings
def map_portfolio_data(portfolio_data):
    return portfolio_data or []


def calculate_portfolio_statistics(holdings_data):
    data = holdings_data or []
    return {
        "total_holdings": len(data),
        "total_investment": round(sum(float(h.get("avg_price", 0)) * int(h.get("quantity", 0)) for h in data), 2),
        "total_pnl": round(sum(float(h.get("pnl", 0) or 0) for h in data), 2),
    }


def transform_holdings_data(holdings_data):
    out = []
    for h in holdings_data or []:
        qty = int(h.get("quantity", 0) or 0)
        avg = float(h.get("average_price", 0) or 0)
        pnl = float(h.get("pnl", 0) or 0)
        invested = avg * qty
        out.append({
            "symbol": h.get("oa_symbol") or h.get("symbol", ""),
            "exchange": h.get("exchange", ""),
            "quantity": qty,
            "product": h.get("product", "CNC"),
            "avg_price": avg,
            "pnl": pnl,
            "pnlpercent": round((pnl / invested) * 100, 2) if invested else 0.0,
        })
    return out
