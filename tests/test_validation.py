import datetime as dt

import pytest

from openalgo_b3_adapter.order_execution.b3_validation import (
    OrderRequest, OrderValidationError, validate_order,
)


def _req(**kw):
    base = dict(symbol="PETR4", side="BUY", quantity=100, order_type="MARKET")
    base.update(kw)
    return OrderRequest(**base)


def test_valid_market_order():
    req = validate_order(_req(), check_session=False)
    assert req.symbol == "PETR4"


def test_invalid_side_and_qty():
    with pytest.raises(OrderValidationError, match="BUY"):
        validate_order(_req(side="HOLD"), check_session=False)
    with pytest.raises(OrderValidationError, match="zero"):
        validate_order(_req(quantity=0), check_session=False)


def test_limit_requires_price():
    with pytest.raises(OrderValidationError, match="Preco obrigatorio"):
        validate_order(_req(order_type="LIMIT", price=0), check_session=False)
    validate_order(_req(order_type="LIMIT", price=33.45), check_session=False)


def test_stop_requires_trigger():
    with pytest.raises(OrderValidationError, match="Trigger"):
        validate_order(_req(order_type="SL", price=33.45, trigger_price=0), check_session=False)
    validate_order(_req(order_type="SL-M", trigger_price=33.0), check_session=False)


def test_lot_multiple_enforced():
    with pytest.raises(OrderValidationError, match="lote"):
        validate_order(_req(quantity=150), check_session=False)
    # fracionario aceita quantidade menor
    validate_order(_req(symbol="PETR4F", quantity=7), check_session=False)


def test_tick_alignment():
    with pytest.raises(OrderValidationError, match="tick"):
        validate_order(_req(order_type="LIMIT", price=33.455), check_session=False)
    # WIN: tick 5 pontos
    validate_order(_req(symbol="WINJ26", order_type="LIMIT", price=789455.0), check_session=False)
    with pytest.raises(OrderValidationError, match="tick"):
        validate_order(_req(symbol="WINJ26", order_type="LIMIT", price=789456.0), check_session=False)


def test_unknown_symbol_rejected():
    with pytest.raises(OrderValidationError, match="nao reconhecido"):
        validate_order(_req(symbol="ZZZZZ9"), check_session=False)


def test_session_checks():
    # sábado 11:30 -> dia sem pregao
    with pytest.raises(OrderValidationError, match="sem pregao"):
        validate_order(_req(), now=dt.datetime(2026, 9, 26, 11, 30))
    # quinta 20:00 -> fora da janela
    with pytest.raises(OrderValidationError, match="janela"):
        validate_order(_req(), now=dt.datetime(2026, 9, 24, 20, 0))
    # quinta 11:30 -> ok
    validate_order(_req(), now=dt.datetime(2026, 9, 24, 11, 30))
