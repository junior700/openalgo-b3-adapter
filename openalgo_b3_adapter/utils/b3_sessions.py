"""Sessões de negociação da B3 (horário de Brasília).

Fases do mercado à vista (equity):
    pré-abertura -> pregão regular -> leilão de fechamento -> after-market

Todas as janelas vêm do B3Config (defaults configuráveis via env,
ex.: B3_SESSION_equity_regular="10:00,16:55"). Confira sempre o horário
oficial vigente da B3 antes de uso produtivo.
"""
from __future__ import annotations

import datetime as _dt
from dataclasses import dataclass
from enum import Enum
from typing import Dict, Optional, Tuple
from zoneinfo import ZoneInfo

from openalgo_b3_adapter.config.b3_config import get_config

B3_TZ = ZoneInfo("America/Sao_Paulo")


class MarketPhase(str, Enum):
    CLOSED = "closed"                    # fechado (fim de semana/feriado/fora do horário)
    PRE_OPEN = "pre_open"                # pré-abertura (leilão; ordens aceitas, sem matching)
    REGULAR = "regular"                  # pregão regular (matching contínuo)
    CLOSING_AUCTION = "closing_auction"  # leilão de fechamento
    AFTER_MARKET = "after_market"        # after-market (limites de preço e só fracionário)


PHASES_ACCEPTING_ORDERS = {
    MarketPhase.PRE_OPEN, MarketPhase.REGULAR, MarketPhase.CLOSING_AUCTION,
}


@dataclass(frozen=True)
class Window:
    name: str
    start: Tuple[int, int]
    end: Tuple[int, int]

    def contains(self, t: _dt.time) -> bool:
        return _dt.time(*self.start) <= t < _dt.time(*self.end)


def _parse_hhmm(value: str) -> Tuple[int, int]:
    hh, mm = value.split(":")
    return int(hh), int(mm)


def windows_for(segment: str) -> list[Window]:
    sessions: Dict[str, Tuple[str, str]] = get_config().sessions(segment)
    return [
        Window(name, _parse_hhmm(start), _parse_hhmm(end))
        for name, (start, end) in sessions.items()
    ]


def current_phase(
    at: Optional[_dt.datetime] = None,
    segment: str = "equity",
    is_trading_day: bool = True,
) -> MarketPhase:
    """Fase de mercado do instante `at` (naive datetime = horário de Brasília).

    `segment` aceita segmento ('equity', 'futures'...) ou código OpenAlgo
    ('NSE', 'NFO', 'MCX'...).
    """
    from openalgo_b3_adapter.config.b3_config import resolve_segment

    try:
        segment = resolve_segment(segment)
    except ValueError:
        pass  # segmento bruto já é válido

    if not is_trading_day:
        return MarketPhase.CLOSED

    if at is None:
        at = _dt.datetime.now(B3_TZ)
    elif at.tzinfo is None:
        at = at.replace(tzinfo=B3_TZ)
    else:
        at = at.astimezone(B3_TZ)

    t = at.time()
    for w in windows_for(segment):
        if w.contains(t):
            if w.name == "pre_open":
                return MarketPhase.PRE_OPEN
            if w.name == "regular":
                return MarketPhase.REGULAR
            if w.name in ("closing_auction", "closing"):
                return MarketPhase.CLOSING_AUCTION
            if w.name in ("after_market", "after"):
                return MarketPhase.AFTER_MARKET
    return MarketPhase.CLOSED


def can_accept_orders(
    at: Optional[_dt.datetime] = None,
    segment: str = "equity",
    is_trading_day: bool = True,
) -> bool:
    """True se ordens podem ser registradas no segmento neste instante.

    Consideramos pre_open + regular + closing_auction (leilões aceitam
    registro) e after_market como janela válida.
    """
    phase = current_phase(at=at, segment=segment, is_trading_day=is_trading_day)
    return phase in PHASES_ACCEPTING_ORDERS or phase == MarketPhase.AFTER_MARKET
