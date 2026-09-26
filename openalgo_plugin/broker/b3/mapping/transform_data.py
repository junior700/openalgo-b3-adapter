"""Transforma request OpenAlgo -> OrderRequest B3 (via adapter)."""
from database.token_db import get_br_symbol
from openalgo_b3_adapter.order_execution import map_openalgo_order
from openalgo_b3_adapter.order_execution.b3_validation import OrderValidationError

from utils.logging import get_logger

logger = get_logger(__name__)


def transform_data(data, auth_token=None):
    """data (schema do core) -> OrderRequest pronto para o gateway B3."""
    br_symbol = get_br_symbol(data["symbol"], data["exchange"])
    if not br_symbol:
        raise OrderValidationError(
            f"Simbolo '{data['symbol']}' nao encontrado no master contract B3",
            code="UNKNOWN_SYMBOL",
        )
    req = map_openalgo_order(data, br_symbol)
    logger.debug(
        "B3 transform: %s -> %s (%s %s %s)",
        data["symbol"], br_symbol, req.side, req.quantity, req.order_type,
    )
    return req


def transform_modify_order_data(data, order_id):
    """Request de modify -> OrderRequest (mantem simbolo da ordem original)."""
    return data, order_id
