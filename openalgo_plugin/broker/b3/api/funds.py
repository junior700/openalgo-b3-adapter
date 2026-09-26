"""Funds (saldo/margem) no formato padronizado do OpenAlgo."""
from openalgo_b3_adapter.order_execution import get_gateway

from utils.logging import get_logger

logger = get_logger(__name__)


def get_margin_data(auth_token):
    """Devolve dict com availablecash, collateral, m2munrealized, m2mrealized,
    utiliseddebits (valores como string, convensao do core)."""
    try:
        gateway = get_gateway()
        return gateway.get_funds(auth_token)
    except Exception as exc:  # noqa: BLE001
        logger.exception(f"B3 funds error: {exc}")
        return {
            "availablecash": "0.00",
            "collateral": "0.00",
            "m2munrealized": "0.00",
            "m2mrealized": "0.00",
            "utiliseddebits": "0.00",
        }
