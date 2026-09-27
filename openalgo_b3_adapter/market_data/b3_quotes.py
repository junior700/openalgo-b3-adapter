"""Provedores de cotações da B3 (Brapi + HG Brasil).

- BrapiQuoteProvider:    https://brapi.dev (gratuito; PETR4/VALE3/ITUB4/MGLU3 sem chave)
- HGBrasilQuoteProvider: https://hgbrasil.com (gratuito com key)
- CompositeQuoteProvider: fallback em cadeia com cache TTL.

Provedores recebem `fetch` injetável (httpx por padrão) -> testes offline.

Nota honesta: cotação intraday da Brapi é o último preço consolidado disponível
(atraso depende do plano), NÃO tick-a-tick. Tempo real real exige B3 WebFeed
(licença paga) — veja docs/BROKERS-BR.md.
"""
from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional

from openalgo_b3_adapter.config.b3_config import get_config
from openalgo_b3_adapter.utils.b3_instruments import classify_symbol, strip_fractional

__all__ = ["Quote", "QuoteProvider", "BrapiQuoteProvider",
           "HGBrasilQuoteProvider", "CompositeQuoteProvider", "to_openalgo_quote"]

Fetch = Callable[..., Any]


@dataclass
class Quote:
    symbol: str
    ltp: float = 0.0
    open: float = 0.0
    high: float = 0.0
    low: float = 0.0
    prev_close: float = 0.0
    bid: float = 0.0
    ask: float = 0.0
    volume: int = 0
    oi: int = 0
    tick_size: Optional[float] = None
    source: str = ""
    fetched_at: float = field(default_factory=time.time)
    # Epoch (segundos) do ULTIMO NEGOCIO segundo o provedor. Usado para
    # carimbar o candle em formacao com o tempo real do negocio, evitando
    # que o terminal crie um candle 'de hoje' com preco de sexta em dias
    # sem pregao (fallback do polling com o relogio do navegador).
    market_time: Optional[float] = None


def _norm_epoch(value) -> Optional[float]:
    """Normaliza epoch em segundos; aceita segundos ou milissegundos."""
    try:
        ts = float(value)
    except (TypeError, ValueError):
        return None
    if ts <= 0:
        return None
    if ts > 1e12:  # veio em milissegundos
        ts /= 1000.0
    return ts


_B3_TZ = None


def _b3_tz():
    """Fuso de Brasilia. Sem DST desde 2019, entao -03:00 fixo serve como
    fallback quando o tzdata nao esta disponivel (Windows)."""
    global _B3_TZ
    if _B3_TZ is None:
        try:
            from zoneinfo import ZoneInfo
            _B3_TZ = ZoneInfo("America/Sao_Paulo")
        except Exception:
            import datetime as _dt
            _B3_TZ = _dt.timezone(_dt.timedelta(hours=-3))
    return _B3_TZ


def _b3_session_stamp(now_epoch=None):
    """Epoch do fechamento do ultimo pregao util (16:50 BRT) quando o mercado
    esta FECHADO; None quando esta aberto (seg-sex, 10:00-16:59 BRT).

    Usado para carimbar o tick do polling com o tempo real do ultimo negocio:
    sem isso o terminal carimba com o relogio do navegador e cria um candle
    'de hoje' com o preco de sexta em dias sem pregao (candle fantasma).
    """
    import datetime as _dt
    tz = _b3_tz()
    now = _dt.datetime.fromtimestamp(now_epoch if now_epoch is not None else time.time(), tz)
    if now.weekday() < 5 and _dt.time(10, 0) <= now.time() < _dt.time(17, 0):
        return None  # pregao aberto: provedor/nowSec mandam
    d = now.date()
    if not (now.weekday() < 5 and now.time() >= _dt.time(17, 0)):
        d -= _dt.timedelta(days=1)
        while d.weekday() >= 5:
            d -= _dt.timedelta(days=1)
    return _dt.datetime.combine(d, _dt.time(16, 50), tzinfo=tz).timestamp()


def to_openalgo_quote(q: Quote) -> Dict[str, Any]:
    """Formato padronizado esperado pelo core do OpenAlgo (BrokerData.get_quotes)."""
    out = {
        "bid": float(q.bid), "ask": float(q.ask), "open": float(q.open),
        "high": float(q.high), "low": float(q.low), "ltp": float(q.ltp),
        "prev_close": float(q.prev_close), "volume": int(q.volume),
        "oi": int(q.oi),
        "tick_size": q.tick_size if q.tick_size is not None else 0.01,
    }
    # Epoch do ultimo negocio: o terminal em queda de WebSocket usa isso
    # para carimbar o candle em formacao (injecao v022 no bundle). Com o
    # mercado fechado, carimba o fechamento do ultimo pregao util em vez do
    # 'agora' do navegador, evitando o candle fantasma em dias sem pregao.
    stamp = _b3_session_stamp()
    if stamp is None:
        stamp = q.market_time
    if stamp:
        out["timeSec"] = int(stamp)
    return out


def _default_fetch() -> Fetch:
    import httpx

    def fetch(url: str, headers: Dict[str, str] = None, params: Dict[str, Any] = None):
        with httpx.Client(timeout=10) as client:
            resp = client.get(url, headers=headers or {}, params=params or {})
            resp.raise_for_status()
            return resp.json()

    return fetch


class QuoteProvider:
    name = "base"

    def __init__(self, fetch: Optional[Fetch] = None):
        self._fetch = fetch or _default_fetch()

    def get_quote(self, symbol: str) -> Quote:
        raise NotImplementedError

    def get_quotes(self, symbols: List[str]) -> Dict[str, Quote]:
        return {s: self.get_quote(s) for s in symbols}


class BrapiQuoteProvider(QuoteProvider):
    """GET /api/v2/stocks/quote?symbols=PETR4 | Authorization: Bearer $KEY"""
    name = "brapi"

    def get_quote(self, symbol: str) -> Quote:
        cfg = get_config()
        # Mercado fracionario (sufixo "F") compartilha o mesmo preco do lote
        # padrao; provedores externos (Brapi/HG) nao conhecem o ticker "F".
        query_symbol = strip_fractional(symbol)
        headers = {"Authorization": f"Bearer {cfg.brapi_api_key}"} if cfg.brapi_api_key else {}
        payload = self._fetch(f"{cfg.brapi_base_url}/api/v2/stocks/quote",
                              headers=headers, params={"symbols": query_symbol})
        results = payload.get("results") or []
        if not results:
            raise ValueError(f"Sem dados para '{symbol}' na Brapi")
        data = results[0].get("data", {})
        inst = classify_symbol(symbol)
        return Quote(
            symbol=symbol,
            ltp=float(data.get("regularMarketPrice", 0) or 0),
            open=float(data.get("regularMarketOpen", 0) or 0),
            high=float(data.get("regularMarketDayHigh", 0) or 0),
            low=float(data.get("regularMarketDayLow", 0) or 0),
            prev_close=float(data.get("regularMarketPreviousClose", 0) or 0),
            bid=float(data.get("regularMarketBidPrice", 0) or 0),
            ask=float(data.get("regularMarketAskPrice", 0) or 0),
            volume=int(data.get("regularMarketVolume", 0) or 0),
            tick_size=inst.tick_size, source=self.name,
            market_time=_norm_epoch(data.get("regularMarketTime") or data.get("updatedAt")),
        )


def _parse_hg_time(value) -> Optional[float]:
    """Converte data/hora da HG Brasil ('2026-09-26 16:30:01',
    '26/09/2026 16:30:01', '26/09/2026 16:30') em epoch."""
    if not value or not isinstance(value, str):
        return None
    import datetime as _dt
    for fmt in ("%Y-%m-%d %H:%M:%S", "%d/%m/%Y %H:%M:%S", "%d/%m/%Y %H:%M"):
        try:
            return _dt.datetime.strptime(value.strip(), fmt).timestamp()
        except ValueError:
            continue
    return None


class HGBrasilQuoteProvider(QuoteProvider):
    """GET /finance/stock?symbol=PETR4&key=KEY"""
    name = "hgbrasil"

    def get_quote(self, symbol: str) -> Quote:
        cfg = get_config()
        query_symbol = strip_fractional(symbol)
        payload = self._fetch(f"{cfg.hgbrasil_base_url}/finance/stock",
                              params={"symbol": query_symbol, "key": cfg.hgbrasil_api_key or "SUA-CHAVE"})
        results = (payload or {}).get("results") or {}
        data = results.get(query_symbol)
        if not data:
            raise ValueError(f"Sem dados para '{symbol}' na HG Brasil")
        inst = classify_symbol(symbol)
        return Quote(
            symbol=symbol,
            ltp=float(data.get("price", 0) or 0),
            open=float(data.get("open", 0) or 0),
            high=float(data.get("higher", 0) or 0),
            low=float(data.get("lower", 0) or 0),
            prev_close=float(data.get("close", 0) or 0),
            bid=float(data.get("bid", 0) or 0),
            ask=float(data.get("ask", 0) or 0),
            volume=int(float(data.get("volume", 0) or 0)),
            tick_size=inst.tick_size, source=self.name,
            market_time=_parse_hg_time(data.get("updated_at") or data.get("updatedAt")),
        )


class CompositeQuoteProvider(QuoteProvider):
    """Tenta provedores em ordem; primeiro que responde vence. Cache TTL por símbolo."""

    def __init__(self, providers: Optional[List[QuoteProvider]] = None,
                 fetch: Optional[Fetch] = None, ttl: Optional[float] = None):
        super().__init__(fetch=fetch)
        self.providers = providers or []
        self.ttl = ttl if ttl is not None else get_config().quote_cache_ttl
        self._cache: Dict[str, Quote] = {}

    def get_quote(self, symbol: str) -> Quote:
        now = time.time()
        cached = self._cache.get(symbol)
        if cached and (now - cached.fetched_at) < self.ttl:
            return cached
        errors = []
        for provider in self.providers:
            try:
                q = provider.get_quote(symbol)
                if q.ltp > 0:
                    self._cache[symbol] = q
                    return q
                errors.append(f"{provider.name}: preço zerado")
            except Exception as exc:  # noqa: BLE001 - fallback intencional
                errors.append(f"{provider.name}: {exc}")
        raise ValueError(f"Nenhum provedor retornou cotação para '{symbol}': {'; '.join(errors)}")
