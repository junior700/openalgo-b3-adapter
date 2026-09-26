"""Calendário de pregão da B3.

A B3 não opera nos feriados nacionais brasileiros, no Carnaval (segunda e
terça) e em Corpus Christi (quarta). Feriados municipais/estaduais NÃO fecham
a B3 (ex.: aniversário de São Paulo, 20/01, a B3 opera normalmente).

Os feriados móveis são derivados da data da Páscoa (algoritmo de Gauss/Meeus):
    Carnaval       = Páscoa - 47 dias  (terça)
    (segunda de Carnaval = Páscoa - 48)
    Corpus Christi = Páscoa + 60 dias

Para datas fora do intervalo suportado ou feriados extraordinários
(ex.: decretos pontuais), use B3_EXTRA_HOLIDAYS="2027-01-01,2027-11-15"
e B3_EXTRA_TRADING_DAYS="2027-12-24" (env vars, datas ISO).
"""

from __future__ import annotations

import datetime as _dt
import os
from functools import lru_cache

__all__ = [
    "easter",
    "b3_holidays",
    "is_trading_day",
    "next_trading_day",
    "previous_trading_day",
]


def easter(year: int) -> _dt.date:
    """Domingo de Páscoa (algoritmo de Meeus/Jones/Butcher)."""
    a = year % 19
    b, c = divmod(year, 100)
    d, e = divmod(b, 4)
    f = (b + 8) // 25
    g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30
    i, k = divmod(c, 4)
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) // 451
    month = (h + l - 7 * m + 114) // 31
    day = ((h + l - 7 * m + 114) % 31) + 1
    return _dt.date(year, month, day)


def _fixed_holidays(year: int) -> list[_dt.date]:
    return [
        _dt.date(year, 1, 1),    # Ano Novo
        _dt.date(year, 4, 21),   # Tiradentes
        _dt.date(year, 5, 1),    # Dia do Trabalho
        _dt.date(year, 9, 7),    # Independência
        _dt.date(year, 10, 12),  # N. Sra. Aparecida
        _dt.date(year, 11, 2),   # Finados
        _dt.date(year, 11, 15),  # Proclamação da República
        _dt.date(year, 12, 25),  # Natal
    ]


def _movable_holidays(year: int) -> list[_dt.date]:
    e = easter(year)
    return [
        e - _dt.timedelta(days=48),  # segunda de Carnaval
        e - _dt.timedelta(days=47),  # terça de Carnaval
        e - _dt.timedelta(days=2),   # Sexta-feira da Paixão
        e + _dt.timedelta(days=60),  # Corpus Christi
    ]


def _env_dates(varname: str) -> list[_dt.date]:
    out: list[_dt.date] = []
    raw = os.getenv(varname, "")
    for token in raw.split(","):
        token = token.strip()
        if not token:
            continue
        try:
            out.append(_dt.date.fromisoformat(token))
        except ValueError:
            continue
    return out


@lru_cache(maxsize=16)
def b3_holidays(year: int) -> frozenset[_dt.date]:
    """Conjunto de datas sem pregão na B3 no ano dado."""
    days = set(_fixed_holidays(year)) | set(_movable_holidays(year))
    # Feriados nacionais "secularizados" que a B3 observa: 24/12 e 31/12
    # têm encerramento antecipado em alguns anos; tratamos como pregão
    # normal (sessão regular encurtada), exceto se cair o leilão — mantemos
    # simples e o usuário pode adicionar via env se desejar.
    days |= set(_env_dates("B3_EXTRA_HOLIDAYS"))
    days -= set(_env_dates("B3_EXTRA_TRADING_DAYS"))
    return frozenset(days)


def is_trading_day(day: _dt.date) -> bool:
    """True se a B3 opera pregão na data (seg-sex, exceto feriados)."""
    return day.weekday() < 5 and day not in b3_holidays(day.year)


def next_trading_day(day: _dt.date) -> _dt.date:
    """Primeiro dia útil de pregão estritamente posterior a `day`."""
    probe = day + _dt.timedelta(days=1)
    while not is_trading_day(probe):
        probe += _dt.timedelta(days=1)
    return probe


def previous_trading_day(day: _dt.date) -> _dt.date:
    """Último dia de pregão estritamente anterior a `day`."""
    probe = day - _dt.timedelta(days=1)
    while not is_trading_day(probe):
        probe -= _dt.timedelta(days=1)
    return probe
