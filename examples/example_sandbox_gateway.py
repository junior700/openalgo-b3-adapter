"""Ciclo completo de ordens direto no gateway sandbox (sem OpenAlgo)."""
from openalgo_b3_adapter.order_execution import (
    OrderRequest, SandboxGateway,
)

gw = SandboxGateway(ignore_sessions=True)
auth = "demo"

req = OrderRequest(symbol="PETR4", side="BUY", quantity=100, order_type="MARKET",
                   exchange="NSE", oa_symbol="PETR4", reference_price=33.50)
res = gw.place_order(req, auth)
print("place:", res["status"], res["order_id"])
print("posicoes:", gw.get_positions(auth))
print("trades:", gw.get_trades(auth))
print("funds:", gw.get_funds(auth))
