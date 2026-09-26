"""Classificação de instrumentos da B3.

Regras de formação de código (fonte: regulamento da B3 / Manual de
Referência — confira sempre a versão vigente):

    Ações / BDRs / units:   RADICAL + N  (N = 3,4,5,6,7,8; 3=ON, 4=PN, 6=PN A, 11=units)
    FIIs / ETFs / FI-INFRA: RADICAL + 11
    Fracionário:            código do mercado a vista + 'F' (ex.: PETR4F, HGLG11F)
    Opções de ações/índice: RADICAL + série (1 letra) + código de emissão,
                            ex.: PETRA331 (PETR4, série A, strike 33)
    Futuros:                RADICAL + MÊS + ANO, ex.: WINJ26 (mini índice jan/2026),
                            WDOJ26 (mini dólar), DI1F26 (DI jan/2026)

Lote padrão e tick size variam por instrumento; as tabelas abaixo cobrem os
casos mais comuns e são extensíveis via dict.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from enum import Enum
from typing import Dict, Optional


class InstrumentKind(str, Enum):
    EQUITY = "equity"          # ações, BDRs, units
    FII = "fii"                # fundos imobiliários
    ETF = "etf"
    FRACTIONAL = "fractional" # mercado fracionário (qualquer ativo + F)
    OPTION = "option"
    FUTURE = "future"
    INDEX = "index"
    UNKNOWN = "unknown"


# Meses dos códigos de futuros da B3 (padrão global de commodities)
FUTURE_MONTH_CODES: Dict[str, int] = {
    "F": 1, "G": 2, "H": 3, "J": 4, "K": 5, "M": 6,
    "N": 7, "Q": 8, "U": 9, "V": 10, "X": 11, "Z": 12,
}

# Radicais de futuros mais negociados e seus lotes/ticks
_FUTURE_SPECS: Dict[str, Dict[str, float]] = {
    "WIN":  {"lot_size": 1, "tick_size": 5.0,   "point_value": 0.20},   # mini índice, R$0,20/pto
    "IND":  {"lot_size": 1, "tick_size": 5.0,   "point_value": 1.0},    # índice cheio
    "WDO":  {"lot_size": 1, "tick_size": 0.5,   "point_value": 10.0},   # mini dólar, R$10/pto
    "DOL":  {"lot_size": 1, "tick_size": 0.5,   "point_value": 50.0},   # dólar cheio
    "DI1":  {"lot_size": 1, "tick_size": 0.01,  "point_value": 1.0},
    "WSP":  {"lot_size": 1, "tick_size": 0.5,   "point_value": 2.5},
}

# Lote padrão do mercado a vista: a maioria dos papéis usa 100, mas há
# exceções históricas. Default: 100; fracionário: 1.
# Fonte dos lotes por papel: melhor consultar o master contract oficial;
# esta tabela é um fallback razoável para os papéis mais líquidos.
_DEFAULT_SPOT_LOT = 100
_EQUITY_LOT_OVERRIDES: Dict[str, int] = {}

# Tick sizes do mercado à vista (regime de leilão da B3):
#   preço < 2,00   -> tick 0,01 | >= 2,00 -> 0,01 (à vista); mudanças de
#   regime em leilões não afetam ordens enviadas via API na maioria dos
#   casos; mantemos 0,01 como tick único do à vista.
_SPOT_TICK_SIZE = 0.01

# ETFs/FIIs conhecidos (para desambiguar sufixo 11, que serve para ambos)
_KNOWN_ETFS = {
    "BOVA11", "BOVB11", "IVVB11", "SMAL11", "SPXI11", "HASH11", "PACT11",
}
_KNOWN_FIIS_PREFIX_HINT = True  # FIIs usam 4 letras + 11 (HGLG11, MXRF11...)


@dataclass
class B3Instrument:
    symbol: str
    kind: InstrumentKind
    lot_size: int
    tick_size: float
    underlying: Optional[str] = None
    fractional: bool = False
    point_value: float = 1.0

    @property
    def is_derivative(self) -> bool:
        return self.kind in (InstrumentKind.OPTION, InstrumentKind.FUTURE)


def is_fractional(symbol: str) -> bool:
    return symbol.endswith("F") and len(symbol) >= 5 and symbol[:-1][-1].isdigit() is False


def normalize_symbol(symbol: str) -> str:
    """Maiúsculas, sem espaços e sem acentuação comum de tickers."""
    s = (symbol or "").strip().upper()
    return s


def strip_fractional(symbol: str) -> str:
    """PETR4F -> PETR4; HGLG11F -> HGLG11; PETR4 -> PETR4."""
    s = normalize_symbol(symbol)
    if s.endswith("F") and re.fullmatch(r"[A-Z0-9]{4,6}F", s):
        return s[:-1]
    return s


_FUTURE_RE = re.compile(r"^(WIN|IND|WDO|DOL|DI1|WSP|BGI|ICF|CCM|SFI)([FGHJKMNQUVXZ])(\d{2})$")
_OPTION_RE = re.compile(r"^([A-Z]{4,5})([A-Z])(\d{2,3})$")
_SPOT_RE = re.compile(r"^[A-Z]{4}([345678]|11)$")


def classify_symbol(symbol: str) -> B3Instrument:
    """Classifica um código B3 e retorna lote/tick/underlying."""
    raw = normalize_symbol(symbol)

    if not raw:
        return B3Instrument(raw, InstrumentKind.UNKNOWN, 0, _SPOT_TICK_SIZE)

    # Índices
    if raw in {"IBOV", "IFUL", "IBRA", "IBXX", "SMLL", "ILPT", "IDIV"} or raw.endswith("INDEX"):
        return B3Instrument(raw, InstrumentKind.INDEX, 1, 0.0)

    # Fracionário (qualquer ativo + F)
    base = strip_fractional(raw)
    if base != raw:
        inner = classify_symbol(base)
        return B3Instrument(
            symbol=raw,
            kind=InstrumentKind.FRACTIONAL,
            lot_size=1,
            tick_size=inner.tick_size,
            underlying=base,
            fractional=True,
        )

    # Futuros
    m = _FUTURE_RE.match(raw)
    if m:
        spec = _FUTURE_SPECS.get(m.group(1), {"lot_size": 1, "tick_size": 0.5, "point_value": 1.0})
        month = FUTURE_MONTH_CODES.get(m.group(2), 0)
        year = 2000 + int(m.group(3))
        return B3Instrument(
            symbol=raw,
            kind=InstrumentKind.FUTURE,
            lot_size=int(spec["lot_size"]),
            tick_size=float(spec["tick_size"]),
            point_value=float(spec.get("point_value", 1.0)),
            underlying=f"{m.group(1)}",
        )

    # Opções: RADICAL + SÉRIE + EMISSÃO (ex.: PETRA331)
    m = _OPTION_RE.match(raw)
    if m and not _SPOT_RE.match(raw):
        return B3Instrument(
            symbol=raw,
            kind=InstrumentKind.OPTION,
            lot_size=100,      # lote de opções de ações: 100 ações (padrão)
            tick_size=0.01,
            underlying=None,   # precisa de tabela oficial para resolver o subjacente
        )

    # À vista: FIIs/ETFs/units (sufixo 11) vs ações (3,4,5,6,7,8)
    if re.fullmatch(r"[A-Z]{4}11", raw):
        kind = InstrumentKind.ETF if raw in _KNOWN_ETFS else InstrumentKind.FII
        return B3Instrument(raw, kind, 10 if kind is InstrumentKind.FII else 10,
                            _SPOT_TICK_SIZE)
    if re.fullmatch(r"[A-Z]{4}[345678]", raw):
        return B3Instrument(raw, InstrumentKind.EQUITY,
                            _EQUITY_LOT_OVERRIDES.get(raw, _DEFAULT_SPOT_LOT),
                            _SPOT_TICK_SIZE)

    return B3Instrument(raw, InstrumentKind.UNKNOWN, 0, _SPOT_TICK_SIZE)


def round_to_tick(price: float, tick_size: float) -> float:
    """Arredonda o preço ao múltiplo de tick mais próximo (tolerância 1e-9)."""
    if tick_size <= 0:
        return price
    steps = round(price / tick_size)
    out = steps * tick_size
    # tolerância numérica
    if abs(price - out) < 1e-9:
        return price
    return out


def is_valid_quantity(quantity: int, instrument: B3Instrument) -> bool:
    """Quantidade válida para o mercado (lote padrão ou fracionário)."""
    if quantity <= 0:
        return False
    if instrument.kind is InstrumentKind.FRACTIONAL:
        return True  # fracionário: qualquer quantidade >= 1
    if instrument.lot_size <= 0:
        return False
    return quantity % instrument.lot_size == 0
