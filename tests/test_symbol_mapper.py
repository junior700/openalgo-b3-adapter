import pytest

from openalgo_b3_adapter.market_data.symbol_mapper import (
    build_option_symbol, looks_like_option_symbol, parse_option_symbol,
    to_broker_symbol,
)


def test_build_and_parse_option_symbol_roundtrip():
    s = build_option_symbol("petr4", "2026-06-19", 35.0, "C")
    assert s == "PETR4-2026-06-19-35.00-C"
    assert looks_like_option_symbol(s)
    opt = parse_option_symbol(s)
    assert opt.base == "PETR4"
    assert opt.expiry == "2026-06-19"
    assert opt.strike == 35.0
    assert opt.option_type == "C"


def test_parse_short_expiry():
    opt = parse_option_symbol("VALE3-260918-70.50-P")
    assert opt.expiry == "2026-09-18"
    assert opt.strike == 70.5
    assert opt.option_type == "P"


def test_spot_symbols_are_not_options():
    assert not looks_like_option_symbol("PETR4")
    assert not looks_like_option_symbol("PETR4-2026-06-19")  # sem strike/tipo


def test_build_option_symbol_rejects_bad_type():
    with pytest.raises(ValueError):
        build_option_symbol("PETR4", "2026-06-19", 35.0, "X")


def test_to_broker_symbol_spot_passthrough():
    assert to_broker_symbol(" petr4 ") == "PETR4"
    assert to_broker_symbol("WINJ26") == "WINJ26"
    assert to_broker_symbol("PETR4F") == "PETR4F"


def test_to_broker_symbol_option_requires_lookup():
    with pytest.raises(ValueError, match="master contract"):
        to_broker_symbol("PETR4-2026-06-19-35.00-C")
    assert to_broker_symbol("PETR4-2026-06-19-35.00-C",
                            br_symbol_lookup=lambda s: "PETRA331") == "PETRA331"
