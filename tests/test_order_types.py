import pytest

from openalgo_b3_adapter.order_execution.b3_order_types import (
    B3OrderType, B3Validity, map_openalgo_pricetype, map_validity,
)


def test_pricetype_mapping():
    assert map_openalgo_pricetype("MARKET") is B3OrderType.MARKET
    assert map_openalgo_pricetype("LIMIT") is B3OrderType.LIMIT
    assert map_openalgo_pricetype("SL") is B3OrderType.STOP_LIMIT
    assert map_openalgo_pricetype("SL-M") is B3OrderType.STOP_MARKET


def test_pricetype_invalid():
    with pytest.raises(ValueError):
        map_openalgo_pricetype("IOC")
    with pytest.raises(ValueError):
        map_openalgo_pricetype("")


def test_validity():
    assert map_validity("DAY") is B3Validity.DAY
    assert map_validity("ioc") is B3Validity.IOC
    assert map_validity("FOK") is B3Validity.FOK
    assert map_validity("") is B3Validity.DAY  # default
    with pytest.raises(ValueError):
        map_validity("AMANHA")
