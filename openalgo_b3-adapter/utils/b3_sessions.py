"""Sessões de negociação da B3 (horário de Brasília).

Fases do mercado à vista (equity):
    pré-abertura -> pregão regular -> leilão de fechamento -> after-market

Fases são consultáveis para decidir se uma ordem pode ser enviada agora.
Todas as janelas vêm do B3Config (overrides via env).
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
    PRE_OPEN = "pre_open"                # pré-abertura (leilão, ordens aceitas mas não executadas)
    REGULAR = "regular"                  # pregão regular (matching contínuo)
    CLOSING_AUCTION = "closing_auction"  # leilão de fechamento
    AFTER_MARKET = "after_market"        # after-market (só mercado fracionário, limites de preço)


# Fases em que a bolsa aceita/envia ordens com matching imediato possível
PHASES_ACCEPTING_ORDERS = {MarketPhase.PRE_OPEN, MarketPhase.REGULAR, MarketPhase.CLOSING_AUCTION}


@dataclass(frozen=True)
class Window:
    name: str
    start: Tuple[int, int]  # (hh, mm)
    end: Tuple[int, int]    # (hh, mm)

    def contains(self, t: _dt.time) -> bool:
        start = _dt.time(*self.start)
        end = _dt.time(*self.end)
        return start <= t < end


def _parse_hhmm(value: str) -> Tuple[int, int]:
    hh, mm = value.split(":")
    return int(hh), int(mm)


def windows_for(segment: str) -> list[Window]:
    """Janelas ordenadas de início para o segmento (ex.: 'equity')."""
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
    """Fase de mercado do instante `at` (datetime com tz; assume BRT se naive).

    `segment` aceita tanto o segmento ('equity', 'futures'...) quanto o código
    de câmara OpenAlgo ('NSE', 'NFO', 'MCX'...).
    """
    from openalgo_b3_adapter.config.b3_config import resolve_segment

    try:
        segment = resolve_segment(segment)
    except ValueError:
        pass  # deixa segmento bruto passar (ex.: 'futures' já é válido)

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
    allow_pre_open: bool = True,
) -> bool:
    """True se ordens podem ser registradas no segmento neste instante."""
    phase = current_phase(at=at, segment=segment, is_trading_day=is_trading_day)
    if phase in PHASES_ACCEPTING_ORDERS:
        return True
    if phase == MarketPhase.PRE_OPEN and not allow_pre_open:
        return False
    return phase == MarketPhase.AFTER_MARKET
