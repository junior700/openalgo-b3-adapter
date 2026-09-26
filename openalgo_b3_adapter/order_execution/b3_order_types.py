"""Tipos de ordem e validade no padrão B3 x OpenAlgo.

OpenAlgo (pricetype):  MARKET | LIMIT | SL (stop limit) | SL-M (stop market)
B3 (tipo de ordem):   01=Market, 02=Limit, 03=Stop, 04=Stop Limitado (aprox.)
Validade B3:          DAY (padrão), IOC (Immediate-or-Cancel), FOK (Fill-or-Kill),
                       GTD (Good-till-Date), GTC (Good-till-Cancelled)

Mapeamento:
    MARKET -> MARKET (executa a mercado com protecao de preco da B3)
    LIMIT  -> LIMIT   (ordem a limite)
    SL     -> STOP_LIMIT (dispara e entra a limite; requiere price + trigger_price)
    SL-M   -> STOP_MARKET (dispara e entra a mercado)

O OpenAlgo nao tem campo de validade; o padrao e DAY. Estrategias podem usar
`validity` programaticamente via o gateway (IOC/FOK suportados pela B3).
"""
from __future__ import annotations

from enum import Enum

__all__ = ["B3OrderType", "B3Validity", "map_openalgo_pricetype", "map_validity"]


class B3OrderType(str, Enum):
    MARKET = "MARKET"
    LIMIT = "LIMIT"
    STOP_MARKET = "STOP_MARKET"   # SL-M
    STOP_LIMIT = "STOP_LIMIT"     # SL


class B3Validity(str, Enum):
    DAY = "DAY"
    IOC = "IOC"
    FOK = "FOK"
    GTD = "GTD"
    GTC = "GTC"


# pricetype OpenAlgo -> tipo B3
_PRICETYPE_MAP = {
    "MARKET": B3OrderType.MARKET,
    "LIMIT": B3OrderType.LIMIT,
    "SL": B3OrderType.STOP_LIMIT,
    "SL-M": B3OrderType.STOP_MARKET,
}

# product OpenAlgo -> descricao B3
_PRODUCT_MAP = {
    "CNC": "posicionado (mercado a vista, sem alavancagem intraday)",
    "MIS": "intraday (sugere encerramento ate o fim do pregao)",
    "NRML": "normal (derivativos; margem conforme garantias)",
}


def map_openalgo_pricetype(pricetype: str) -> B3OrderType:
    """Converte pricetype do OpenAlgo em tipo de ordem B3."""
    key = (pricetype or "").strip().upper()
    if key not in _PRICETYPE_MAP:
        raise ValueError(
            f"pricetype '{pricetype}' invalido. Use: MARKET, LIMIT, SL ou SL-M"
        )
    return _PRICETYPE_MAP[key]


def map_validity(validity: str) -> B3Validity:
    """Normaliza validade para o enum B3 (padrao DAY)."""
    key = (validity or "DAY").strip().upper()
    if key not in {v.value for v in B3Validity}:
        raise ValueError(f"validity '{validity}' invalido. Use: DAY, IOC, FOK, GTD, GTC")
    return B3Validity(key)


def describe_product(product: str) -> str:
    return _PRODUCT_MAP.get((product or "").strip().upper(), "produto desconhecido")
