import datetime as dt

from openalgo_b3_adapter.utils.b3_calendar import (
    b3_holidays, easter, is_trading_day, next_trading_day, previous_trading_day,
)


def test_easter_known_dates():
    assert easter(2025) == dt.date(2025, 4, 20)
    assert easter(2026) == dt.date(2026, 4, 5)


def test_carnival_2026_closed():
    # Carnaval 2026: segunda 16/fev e terça 17/fev
    assert dt.date(2026, 2, 16) in b3_holidays(2026)
    assert dt.date(2026, 2, 17) in b3_holidays(2026)
    assert not is_trading_day(dt.date(2026, 2, 16))
    # quarta de cinzas: B3 opera (dia util normal)
    assert is_trading_day(dt.date(2026, 2, 18))


def test_carnival_2025_closed():
    assert dt.date(2025, 3, 3) in b3_holidays(2025)
    assert dt.date(2025, 3, 4) in b3_holidays(2025)


def test_corpus_christi_closed():
    assert dt.date(2025, 6, 19) in b3_holidays(2025)
    assert dt.date(2026, 6, 4) in b3_holidays(2026)


def test_fixed_holidays_closed():
    for d in [dt.date(2026, 1, 1), dt.date(2026, 4, 21), dt.date(2026, 5, 1),
              dt.date(2026, 9, 7), dt.date(2026, 10, 12), dt.date(2026, 11, 2),
              dt.date(2026, 11, 15), dt.date(2026, 12, 25)]:
        assert not is_trading_day(d), d


def test_weekends_closed_and_weekday_open():
    assert not is_trading_day(dt.date(2026, 9, 26))  # sábado
    assert not is_trading_day(dt.date(2026, 9, 27))  # domingo
    assert is_trading_day(dt.date(2026, 9, 24))      # quinta normal


def test_next_and_previous_trading_day():
    # sexta 20/fev/2026 é Carnaval -> próximo pregão após 19/fev é 18? não:
    # 16-17 são Carnaval, 18 é pregão. Após 18/fev, próximo pregão é 19/fev.
    assert next_trading_day(dt.date(2026, 2, 15)) == dt.date(2026, 2, 18)
    assert next_trading_day(dt.date(2026, 9, 25)) == dt.date(2026, 9, 28)  # pula fds
    assert previous_trading_day(dt.date(2026, 2, 18)) == dt.date(2026, 2, 13)
