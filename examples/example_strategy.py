"""Estrategia de exemplo via SDK oficial do OpenAlgo (gateway sandbox).

Requisitos: OpenAlgo rodando com o plugin b3 conectado.
"""
from openalgo import OpenAlgo

api = OpenAlgo(api_key="SUA_API_KEY", host="http://localhost:5000")

# estado da conta
print("funds:", api.get_margin_data(broker="b3"))

# cotacao e ordem
print("quote:", api.quote(symbol="PETR4", exchange="NSE"))
resp = api.place_order(
    symbol="PETR4", action="BUY", exchange="NSE",
    quantity=100, pricetype="LIMIT", price=33.50, product="CNC",
    strategy="exemplo-py",
)
print("ordem:", resp)

print("orderbook:", api.get_order_book(broker="b3"))
print("posicoes:", api.get_positions(broker="b3"))
