"""Validacao de ordens no padrao B3.

Checagens antes do envio a corretora:
  1. Lado (BUY/SELL), quantidade positiva e multiplo do lote
  2. Preco obrigatorio para LIMIT/SL; trigger para SL/SL-M
  3. Preco alinhado ao tick size
  4. Instrumento reconhecido (acao/opcao/futuro/FII)
  5. Pregao aberto (data de pregao + fase de mercado aceitando ordens)

Lanca `OrderValidationError` (com `code`) — o plugin converte em resposta
de erro do OpenAlgo.
"""
from __future__ import annotations

import datetime as _dt
from dataclasses import dataclass
from typing import Optional

from openalgo_b3_adapter.market_data.symbol_mapper import b3_instrument_of
from openalgo_b3_adapter.order_execution.b3_order_types import (
    B3OrderType, map_openalgo_pricetype,
)
from openalgo_b3_adapter.utils.b3_calendar import is_trading_day
from openalgo_b3_adapter.utils.b3_instruments import InstrumentKind, round_to_tick
from openalgo_b3_adapter.utils.b3_sessions import can_accept_orders

__all__ = ["OrderValidationError", "validate_order"]


class OrderValidationError(Exception):
    def __init__(self, message: str, code: str = "INVALID_ORDER"):
        super().__init__(message)
        self.code = code
        self.message = message


@dataclass
class OrderRequest:
    """Ordem ja mapeada para o espaco B3 (símbolo raw + tipo B3)."""
    symbol: str
    side: str                    # BUY | SELL
    quantity: int
    order_type: str              # B3OrderType.value
    price: float = 0.0
    trigger_price: float = 0.0
    validity: str = "DAY"
    product: str = "CNC"
    exchange: str = "NSE"        # código OpenAlgo original
    oa_symbol: Optional[str] = None  # símbolo no espaço OpenAlgo (estruturado p/ opções)
    reference_price: Optional[float] = None  # usado p/ fill do sandbox


def validate_order(
    req: OrderRequest,
    *,
    now: Optional[_dt.datetime] = None,
    check_session: bool = True,
) -> OrderRequest:
    """Valida a ordem; devolve a propria requisicao ou levanta erro."""

    # 1. Lado e quantidade
    side = (req.side or "").strip().upper()
    if side not in ("BUY", "SELL"):
        raise OrderValidationError("Lado invalido: use BUY ou SELL", code="INVALID_SIDE")
    if req.quantity is None or int(req.quantity) <= 0:
        raise OrderValidationError("Quantidade deve ser maior que zero", code="INVALID_QTY")

    # 2. Tipo de ordem / precos obrigatorios
    try:
        otype = map_openalgo_pricetype(req.order_type)
    except ValueError as exc:
        raise OrderValidationError(str(exc), code="INVALID_PRICETYPE") from exc

    if otype in (B3OrderType.LIMIT, B3OrderType.STOP_LIMIT) and float(req.price or 0) <= 0:
        raise OrderValidationError(
            f"Preco obrigatorio para ordens {otype.value}", code="MISSING_PRICE"
        )
    if otype in (B3OrderType.STOP_LIMIT, B3OrderType.STOP_MARKET):
        if float(req.trigger_price or 0) <= 0:
            raise OrderValidationError(
                "Trigger price obrigatorio para ordens stop", code="MISSING_TRIGGER"
            )
        if float(req.trigger_price or 0) <= 0:
            raise OrderValidationError("Trigger price invalido", code="INVALID_TRIGGER")

    # 3. Instrumento, lote e tick
    instrument = b3_instrument_of(req.symbol)
    if instrument.kind is InstrumentKind.UNKNOWN:
        raise OrderValidationError(
            f"Instrumento '{req.symbol}' nao reconhecido na B3", code="UNKNOWN_SYMBOL"
        )
    if instrument.lot_size > 0 and int(req.quantity) % instrument.lot_size != 0:
        raise OrderValidationError(
            f"Quantidade {req.quantity} fora do lote padrao "
            f"({instrument.lot_size}). Use o mercado fracionario "
            f"('{req.symbol}F') para quantidades menores.",
            code="INVALID_LOT",
        )
    if otype in (B3OrderType.LIMIT, B3OrderType.STOP_LIMIT) and instrument.tick_size > 0:
        if abs(float(req.price) - round_to_tick(float(req.price), instrument.tick_size)) > 1e-9:
            raise OrderValidationError(
                f"Preco {req.price} fora do tick ({instrument.tick_size:0.2f})",
                code="INVALID_TICK",
            )

    # 4. Sessao de negociacao
    if check_session:
        day = now.date() if now else _dt.date.today()
        if not is_trading_day(day):
            raise OrderValidationError(
                "B3 fechada: dia sem pregao (feriado/fim de semana)",
                code="MARKET_CLOSED",
            )
        if not can_accept_orders(at=now, segment=req.exchange):
            raise OrderValidationError(
                "Fora da janela de aceite de ordens (consulte sessoes B3)",
                code="SESSION_CLOSED",
            )
    return req
