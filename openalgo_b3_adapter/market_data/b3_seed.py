"""Semente de instrumentos B3 para o master contract do plugin.

O master contract oficial usa a lista de tickers da Brapi quando há chave
(BRAPI_API_KEY); sem chave, esta semente offline garante que o plugin
funcione com os papéis mais líquidos (e nos testes).

Formato de cada linha: (symbol, name, kind, lot_size, tick_size, segment)
"""
from __future__ import annotations

# symbol, nome, kind, lote, tick, segmento
SEED_INSTRUMENTS = [
    # --- Ações (mercado à vista) ---
    ("PETR4", "Petrobras PN", "equity", 100, 0.01, "equity"),
    ("PETR3", "Petrobras ON", "equity", 100, 0.01, "equity"),
    ("VALE3", "Vale ON", "equity", 100, 0.01, "equity"),
    ("ITUB4", "Itau Unibanco PN", "equity", 100, 0.01, "equity"),
    ("BBDC4", "Bradesco PN", "equity", 100, 0.01, "equity"),
    ("BBAS3", "Banco do Brasil ON", "equity", 100, 0.01, "equity"),
    ("BBSE3", "BB Seguridade ON", "equity", 100, 0.01, "equity"),
    ("ABEV3", "Ambev ON", "equity", 100, 0.01, "equity"),
    ("MGLU3", "Magazine Luiza ON", "equity", 100, 0.01, "equity"),
    ("B3SA3", "B3 ON", "equity", 100, 0.01, "equity"),
    ("ITSA4", "Itausa PN", "equity", 100, 0.01, "equity"),
    ("WEGE3", "WEG ON", "equity", 100, 0.01, "equity"),
    ("SUZB3", "Suzano ON", "equity", 100, 0.01, "equity"),
    ("RENT3", "Localiza ON", "equity", 100, 0.01, "equity"),
    ("LREN3", "Lojas Renner ON", "equity", 100, 0.01, "equity"),
    ("PRIO3", "PRIO ON", "equity", 100, 0.01, "equity"),
    ("RADL3", "Raia Drogasil ON", "equity", 100, 0.01, "equity"),
    ("EQTL3", "Equatorial ON", "equity", 100, 0.01, "equity"),
    ("ELET3", "Eletrobras ON", "equity", 100, 0.01, "equity"),
    ("ELET6", "Eletrobras PNA", "equity", 100, 0.01, "equity"),
    ("GGBR4", "Gerdau PN", "equity", 100, 0.01, "equity"),
    ("CSNA3", "CSN ON", "equity", 100, 0.01, "equity"),
    ("USIM5", "Usiminas PNA", "equity", 100, 0.01, "equity"),
    ("JBSS3", "JBS ON", "equity", 100, 0.01, "equity"),
    ("BRFS3", "BRF ON", "equity", 100, 0.01, "equity"),
    ("BRKM5", "Braskem PNA", "equity", 100, 0.01, "equity"),
    ("CMIG4", "Cemig PN", "equity", 100, 0.01, "equity"),
    ("SBSP3", "Sabesp ON", "equity", 100, 0.01, "equity"),
    ("TAEE11", "Taesa UNT", "equity", 100, 0.01, "equity"),
    ("VIVT3", "Telefonica Brasil ON", "equity", 100, 0.01, "equity"),
    ("TIMS3", "TIM ON", "equity", 100, 0.01, "equity"),
    ("FLRY3", "Fleury ON", "equity", 100, 0.01, "equity"),
    ("CYRE3", "Cyrela ON", "equity", 100, 0.01, "equity"),
    ("MRFG3", "Marfrig ON", "equity", 100, 0.01, "equity"),
    ("AZUL4", "Azul PN", "equity", 100, 0.01, "equity"),
    ("GOLL4", "Gol PN", "equity", 100, 0.01, "equity"),
    ("CIEL3", "Cielo ON", "equity", 100, 0.01, "equity"),
    ("KLBN11", "Klabin UNT", "equity", 100, 0.01, "equity"),
    ("RAND3", "Americanas ON", "equity", 100, 0.01, "equity"),
    ("SANB11", "Santander Brasil UNT", "equity", 100, 0.01, "equity"),
    ("BPAC11", "BTG Pactual UNT", "equity", 100, 0.01, "equity"),
    ("NTCO3", "Natura ON", "equity", 100, 0.01, "equity"),
    ("EMBR3", "Embraer ON", "equity", 100, 0.01, "equity"),
    ("HAPV3", "Hapvida ON", "equity", 100, 0.01, "equity"),
    ("UGPA3", "Ultrapar ON", "equity", 100, 0.01, "equity"),
    ("CSAN3", "Cosan ON", "equity", 100, 0.01, "equity"),
    ("TOTS3", "Totvs ON", "equity", 100, 0.01, "equity"),
    ("QUAL3", "Qualicorp ON", "equity", 100, 0.01, "equity"),
    ("CCRO3", "CCR ON", "equity", 100, 0.01, "equity"),
    ("RRRP3", "PetroReconcavo ON", "equity", 100, 0.01, "equity"),
    # --- FIIs / ETFs (sufixo 11) ---
    ("HGLG11", "CSHG Logistica FII", "fii", 10, 0.01, "equity"),
    ("MXRF11", "Maxi Renda FII", "fii", 10, 0.01, "equity"),
    ("HGBS11", "CSHG Brasil FII", "fii", 10, 0.01, "equity"),
    ("KNRI11", "Kinea Renda Imobiliaria FII", "fii", 10, 0.01, "equity"),
    ("XPLG11", "XP Log FII", "fii", 10, 0.01, "equity"),
    ("HFOF11", "Hedge TOP FOF FII", "fii", 10, 0.01, "equity"),
    ("BCFF11", "BTG Fund FII", "fii", 10, 0.01, "equity"),
    ("BOVA11", "iShares Ibovespa ETF", "etf", 10, 0.01, "equity"),
    ("IVVB11", "iShares S&P 500 ETF", "etf", 10, 0.01, "equity"),
    ("SMAL11", "iShares Small Cap ETF", "etf", 10, 0.01, "equity"),
    ("HASH11", "Hashdex BITNEXO ETF", "etf", 10, 0.01, "equity"),
    # --- Futuros (derivativos) ---
    ("WINJ26", "Mini Indice Jan/26", "future", 1, 5.0, "futures"),
    ("WINK26", "Mini Indice Mai/26", "future", 1, 5.0, "futures"),
    ("WINM26", "Mini Indice Jun/26", "future", 1, 5.0, "futures"),
    ("WINZ26", "Mini Indice Dez/26", "future", 1, 5.0, "futures"),
    ("WDOJ26", "Mini Dolar Jan/26", "future", 1, 0.5, "futures"),
    ("WDOZ26", "Mini Dolar Dez/26", "future", 1, 0.5, "futures"),
    ("DOLJ26", "Dolar Comercial Jan/26", "future", 1, 0.5, "futures"),
    ("DI1F26", "DI Jan/26", "future", 1, 0.01, "futures"),
    ("DI1N26", "DI Jan/27", "future", 1, 0.01, "futures"),
    # --- Índices ---
    ("IBOV", "Ibovespa", "index", 1, 0.0, "index"),
    ("IFUL", "IFULL", "index", 1, 0.0, "index"),
]

# Opções de exemplo (notação estruturada -> código B3) apenas ilustrativas;
# em produção o download oficial resolve a série vigente.
SEED_OPTION_EXAMPLES = [
    ("PETR4-2026-06-19-35.00-C", "PETRA331", "PETR4", 100, 0.01),
]
