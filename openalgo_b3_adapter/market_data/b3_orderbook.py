"""Book de ofertas da B3.

Realidade do ecossistema FOSS BR (veja docs/BROKERS-BR.md):
    - Brapi/HG Brasil NÃO expõem profundidade (book) — apenas top-of-book.
    - O book completo em tempo real exige B3 Market Data WebFeed / UMDF
      (licença paga) ou a API da corretora (quando disponível).

Interface:
    BookProvider.get_book(symbol, depth=5) -> {"bids": [...], "asks": [...]}

Implementações:
    - SimulatedBookProvider: book sintético determinístico a partir de uma
      cotação (útil para dev/testes, honestamente rotulado como simulado).
    - B3WebFeedBookProvider: stub com instruções de integração (licença).
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional, Protocol, runtime_checkable

from openalgo_b3_adapter.market_data.b3_quotes import Quote

__all__ = ["BookProvider", "SimulatedBookProvider", "B3WebFeedBookProvider",
           "book_to_openalgo_depth"]


@runtime_checkable
class BookProvider(Protocol):
    def get_book(self, symbol: str, depth: int = 5) -> Dict[str, List[Dict[str, float]]]: ...


def book_to_openalgo_depth(book: Dict[str, List[dict]]) -> Dict[str, list]:
    """Formato de depth esperado pelo core do OpenAlgo (BrokerData.get_depth)."""
    return {
        "bids": [{"price": float(b["price"]), "quantity": int(b.get("quantity", 0)),
                  "orders": int(b.get("orders", 1))} for b in book.get("bids", [])],
        "asks": [{"price": float(a["price"]), "quantity": int(a.get("quantity", 0)),
                  "orders": int(a.get("orders", 1))} for a in book.get("asks", [])],
    }


class SimulatedBookProvider:
    """Book sintético e DETERMINÍSTICO a partir de um `Quote`.

    Útil para desenvolvimento e testes end-to-end do plugin. Nunca use como
    sinal de decisão: os níveis são gerados por spread fixo e quantidade
    pseudo-aleatória estável (hash do símbolo + preço).
    """

    name = "simulated"

    def __init__(self, quote: Optional[Quote] = None, spread: float = 0.01, lot: int = 100):
        self.quote = quote
        self.spread = spread
        self.lot = lot

    def get_book(self, symbol: str, depth: int = 5) -> Dict[str, List[dict]]:
        mid = self.quote.ltp if self.quote and self.quote.ltp > 0 else 100.0
        half = self.spread / 2
        seed = sum(ord(c) for c in symbol)
        bids, asks = [], []
        for i in range(depth):
            qty = self.lot * (1 + ((seed + i * 3) % 10))
            bids.append({"price": round(mid - half - i * self.spread, 2),
                         "quantity": qty, "orders": 1 + ((seed + i) % 3)})
            asks.append({"price": round(mid + half + i * self.spread, 2),
                         "quantity": qty, "orders": 1 + ((seed + i) % 4)})
        return {"bids": bids, "asks": asks}


class B3WebFeedBookProvider:
    """Stub para o B3 Market Data WebFeed (requer licença B3).

    Passos de integração (docs/BROKERS-BR.md):
      1. Contratar Market Data WebFeed na B3 (planos por segmento).
      2. Assinar o canal de book do instrumento (JSON/protobuf via WebSocket).
      3. Manter cache L1 local e publicar via get_book().
    """
    name = "b3webfeed"

    def __init__(self, *args, **kwargs):
        raise NotImplementedError(
            "B3WebFeedBookProvider requer licença de Market Data da B3. "
            "Implemente conforme docs/BROKERS-BR.md ou use SimulatedBookProvider para dev."
        )
