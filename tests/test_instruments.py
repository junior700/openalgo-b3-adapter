from openalgo_b3_adapter.utils.b3_instruments import (
    InstrumentKind, classify_symbol, is_valid_quantity, round_to_tick,
    strip_fractional,
)


def test_classify_equity():
    inst = classify_symbol("PETR4")
    assert inst.kind is InstrumentKind.EQUITY
    assert inst.lot_size == 100
    assert inst.tick_size == 0.01


def test_classify_fii_and_etf():
    assert classify_symbol("HGLG11").kind is InstrumentKind.FII
    assert classify_symbol("MXRF11").kind is InstrumentKind.FII
    assert classify_symbol("BOVA11").kind is InstrumentKind.ETF


def test_classify_fractional():
    inst = classify_symbol("PETR4F")
    assert inst.kind is InstrumentKind.FRACTIONAL
    assert inst.lot_size == 1
    assert inst.underlying == "PETR4"
    assert strip_fractional("PETR4F") == "PETR4"


def test_classify_futures():
    inst = classify_symbol("WINJ26")
    assert inst.kind is InstrumentKind.FUTURE
    assert inst.tick_size == 5.0
    assert classify_symbol("WDOJ26").tick_size == 0.5


def test_classify_option_raw_code():
    assert classify_symbol("PETRA331").kind is InstrumentKind.OPTION


def test_lot_validation():
    inst = classify_symbol("PETR4")
    assert is_valid_quantity(200, inst)
    assert not is_valid_quantity(150, inst)
    frac = classify_symbol("PETR4F")
    assert is_valid_quantity(7, frac)


def test_round_to_tick():
    assert round_to_tick(33.456, 0.01) in (33.46, 33.45)
    assert round_to_tick(33.45, 0.01) == 33.45
    assert round_to_tick(789456.0, 5.0) == 789455.0
