import datetime as dt

from openalgo_b3_adapter.utils.b3_sessions import MarketPhase, current_phase


def _at(h, m):
    return dt.datetime(2026, 9, 24, h, m)  # quinta-feira


def test_regular_session():
    assert current_phase(_at(11, 30), "NSE") is MarketPhase.REGULAR
    assert current_phase(_at(10, 0), "equity") is MarketPhase.REGULAR
    assert current_phase(_at(16, 54), "NSE") is MarketPhase.REGULAR


def test_pre_open_and_closed():
    assert current_phase(_at(9, 30), "NSE") is MarketPhase.PRE_OPEN
    assert current_phase(_at(8, 0), "NSE") is MarketPhase.CLOSED
    assert current_phase(_at(20, 0), "NSE") is MarketPhase.CLOSED


def test_closing_auction_and_after_market():
    assert current_phase(_at(16, 56), "NSE") is MarketPhase.CLOSING_AUCTION
    assert current_phase(_at(17, 45), "NSE") is MarketPhase.AFTER_MARKET


def test_non_trading_day_is_closed():
    assert current_phase(_at(11, 0), "NSE", is_trading_day=False) is MarketPhase.CLOSED


def test_futures_segment_window():
    # futuros operam 09:00-18:25
    assert current_phase(_at(9, 30), "MCX") is MarketPhase.REGULAR
    assert current_phase(_at(18, 0), "MCX") is MarketPhase.REGULAR


def test_env_override(monkeypatch):
    monkeypatch.setenv("B3_SESSION_equity_regular", "11:00,12:00")
    assert current_phase(_at(11, 30), "equity") is MarketPhase.REGULAR
    assert current_phase(_at(10, 30), "equity") is MarketPhase.CLOSED
