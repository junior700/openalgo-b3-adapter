"""Normalização de símbolos entre OpenAlgo e B3.

Convenção deste adapter (docs/ARCHITECTURE.md):

    À vista        — código B3 como está:            PETR4
    Fracionário    — código + F:                     PETR4F
    Índices        — nome do índice:                 IBOV
    Futuros        — código do contrato B3:          WINJ26
    Opções         — notação estruturada estilo OA:  PETR4-2026-06-19-35.00-C

A notação estruturada é o `symbol` gravado no master contract (symtoken)
do OpenAlgo; o código oficial da B3 (ex.: PETRA331) fica em `brsymbol`.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Callable, Optional

from openalgo_b3_adapter.utils.b3_instruments import (
    B3Instrument, InstrumentKind, classify_symbol, normalize_symbol,
)

__all__ = [
    "OpenAlgoOptionSymbol", "build_option_symbol", "parse_option_symbol",
    "looks_like_option_symbol", "to_broker_symbol", "b3_instrument_of",
]

_OPT_RE = re.compile(
    r"^(?P<base>[A-Z0-9]{4,6})-(?:"
    r"(?P<expiry>20\d{2}-\d{2}-\d{2})"
    r"|(?P<expiry_short>\d{6})"
    r")-(?P<strike>\d+(?:\.\d+)?)-(?P<type>[CP])$"
)


@dataclass(frozen=True)
class OpenAlgoOptionSymbol:
    base: str
    expiry: str        # ISO YYYY-MM-DD
    strike: float
    option_type: str   # "C" | "P"

    def __str__(self) -> str:
        return f"{self.base}-{self.expiry}-{self.strike:.2f}-{self.option_type}"


def build_option_symbol(base: str, expiry: str, strike: float, option_type: str) -> str:
    """Monta a notação estruturada. `expiry` aceita ISO (YYYY-MM-DD) ou YYMMDD."""
    base = normalize_symbol(base)
    option_type = option_type.strip().upper()
    if option_type not in ("C", "P"):
        raise ValueError("option_type deve ser 'C' (call) ou 'P' (put)")
    if re.fullmatch(r"20(\d{2})-(\d{2})-(\d{2})", expiry):
        iso = expiry
    else:
        m = re.fullmatch(r"(\d{2})(\d{2})(\d{2})", expiry)
        if not m:
            raise ValueError("expiry deve ser YYYY-MM-DD ou YYMMDD")
        iso = f"20{m.group(1)}-{m.group(2)}-{m.group(3)}"
    return f"{base}-{iso}-{float(strike):.2f}-{option_type}"


def parse_option_symbol(symbol: str) -> Optional[OpenAlgoOptionSymbol]:
    m = _OPT_RE.match(normalize_symbol(symbol))
    if not m:
        return None
    if m.group("expiry"):
        iso = m.group("expiry")
    else:
        s = m.group("expiry_short")
        iso = f"20{s[0:2]}-{s[2:4]}-{s[4:6]}"
    return OpenAlgoOptionSymbol(
        base=m.group("base"), expiry=iso,
        strike=float(m.group("strike")), option_type=m.group("type"),
    )


def looks_like_option_symbol(symbol: str) -> bool:
    return parse_option_symbol(symbol) is not None


def to_broker_symbol(openalgo_symbol: str, br_symbol_lookup: Optional[Callable] = None) -> str:
    """Símbolo OpenAlgo -> código B3.

    À vista/fracionário/futuros: código passa direto (com normalização).
    Opções (notação estruturada): requer lookup no master contract.
    """
    s = normalize_symbol(openalgo_symbol)
    opt = parse_option_symbol(s)
    if opt:
        if br_symbol_lookup is None:
            raise ValueError(
                f"Símbolo de opção '{s}' requer o master contract "
                "(passe br_symbol_lookup ou use get_br_symbol do plugin)"
            )
        resolved = br_symbol_lookup(s)
        if resolved is None:
            raise ValueError(f"Símbolo '{s}' não encontrado no master contract")
        return resolved
    return s


def b3_instrument_of(symbol: str) -> B3Instrument:
    """Instrumento B3 associado ao símbolo (trata notação de opção)."""
    s = normalize_symbol(symbol)
    opt = parse_option_symbol(s)
    if opt:
        return B3Instrument(symbol=s, kind=InstrumentKind.OPTION, lot_size=100,
                            tick_size=0.01, underlying=opt.base)
    return classify_symbol(s)
