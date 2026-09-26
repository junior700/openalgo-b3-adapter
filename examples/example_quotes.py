"""Cotações B3 com o pacote standalone (sem OpenAlgo).

Plano gratuito da Brapi serve PETR4/VALE3/ITUB4/MGLU3 sem chave.
"""
from openalgo_b3_adapter.market_data import BrapiQuoteProvider, to_openalgo_quote

prov = BrapiQuoteProvider()
for sym in ["PETR4", "VALE3", "ITUB4"]:
    try:
        print(sym, to_openalgo_quote(prov.get_quote(sym)))
    except Exception as exc:
        print(sym, "->", exc)
