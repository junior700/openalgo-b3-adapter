# ============================================================
# patch.ps1 - aplicador automatico de correcoes
# Projeto: openalgo-b3-adapter
# Versao:  v014_2026-09-27_0014  |  Arquivos: 2
# Descricao: correcao: historico do grafico (bug de case sensitivity no intervalo D) + cotacao/historico do mercado fracionario (sufixo F) usam ticker base na Brapi/HG Brasil
#
# COMO USAR (na raiz da instalacao replicada):
#   powershell -ExecutionPolicy Bypass -File .\patch_v014_2026-09-27_0014.ps1
#
# O QUE ELE FAZ (nesta ordem):
#   0. recusa re-aplicacao (patches\registro.csv) e pede confirmacao
#   1. cria a pasta patches\v014_2026-09-27_0014\
#   2. backup dos arquivos ATUAIS em v014_2026-09-27_0014\anteriores\
#      (arquivo novo = inclusao, sem backup)
#   3. grava os arquivos corrigidos nos lugares devidos
#      (UTF-8 sem BOM; cria subpastas se faltar)
#   4. guarda copia versionada dos novos em v014_2026-09-27_0014\
#   5. guarda copia versionada DE SI MESMO em v014_2026-09-27_0014\
#   6. anexa uma linha no patches\registro.csv
#   7. mostra o resumo, espera ENTER e SE AUTODESTRUI
#
# RASTREIO: patches\registro.csv guarda versao, data, arquivos e
# resultado. ROLLBACK MANUAL: copie de v014_2026-09-27_0014\anteriores\.
#
# REGRAS DO PROJETO: pausa antes de qualquer saida, confirmacao
# antes de tocar em qualquer arquivo, token nunca gravado.
# ============================================================

$ErrorActionPreference = "Stop"
$Raiz = $PSScriptRoot
if (-not $Raiz) { $Raiz = (Get-Location).Path }

$Ver  = "v014_2026-09-27_0014"
$Desc = "correcao: historico do grafico (bug de case sensitivity no intervalo D) + cotacao/historico do mercado fracionario (sufixo F) usam ticker base na Brapi/HG Brasil"

Write-Host ""
Write-Host "=== PATCH AUTOMATICO - openalgo-b3-adapter ===" -ForegroundColor Cyan
Write-Host "Versao: $Ver"
Write-Host "Descricao: $Desc"
Write-Host "Raiz do projeto: $Raiz"
Write-Host ""

# --- 0. recusa re-aplicacao ---
$Registro = Join-Path $Raiz "patches\registro.csv"
if (Test-Path $Registro) {
    $ja = Get-Content $Registro -ErrorAction SilentlyContinue |
          Where-Object { $_ -match "^$Ver;" }
    if ($ja) {
        Write-Host "Patch $Ver JA aplicado (registro.csv). Nada a fazer." -ForegroundColor Yellow
        Read-Host "Pressione ENTER para sair"
        exit 0
    }
}

# --- confirmacao antes de tocar em qualquer arquivo ---
$r = Read-Host "Aplicar este patch? [S/N]"
if ($r -ne "S" -and $r -ne "s") {
    Write-Host "Cancelado. Nenhum arquivo foi tocado."
    Read-Host "Pressione ENTER para sair"
    exit 0
}

# --- pasta da versao ---
$DirVer = Join-Path $Raiz "patches\$Ver"
$DirAnt = Join-Path $DirVer "anteriores"
New-Item -ItemType Directory -Force -Path $DirVer | Out-Null
New-Item -ItemType Directory -Force -Path $DirAnt | Out-Null

# --- arquivos embutidos: destino relativo -> conteudo novo ---
$Arquivos = @{

    "openalgo_plugin\broker\b3\api\data.py" = @'
"""Dados de mercado do plugin B3 (contrato: broker.<n>.api.data).

BrokerData e a classe que o core instancia com o auth token; metodos:
    get_quotes(symbol, exchange)         -> dict padronizado
    get_multiquotes(symbols)             -> lista padronizada
    get_history(symbol, exchange, interval, start, end) -> pd.DataFrame
    get_depth(symbol, exchange)          -> dict bids/asks

Fontes: Brapi/HG Brasil (plano gratuito, cotação consolidada) + book
simulado para dev. Tempo real/licenca B3: docs/BROKERS-BR.md.
"""
import datetime as _dt

import pandas as pd

from database.token_db import get_br_symbol
from openalgo_b3_adapter.config.b3_config import resolve_segment
from openalgo_b3_adapter.utils.b3_instruments import strip_fractional
from openalgo_b3_adapter.market_data.b3_orderbook import (
    SimulatedBookProvider, book_to_openalgo_depth,
)
from openalgo_b3_adapter.market_data.b3_quotes import (
    BrapiQuoteProvider, CompositeQuoteProvider, HGBrasilQuoteProvider,
    to_openalgo_quote,
)

from utils.logging import get_logger

logger = get_logger(__name__)

# intervalos suportados: 'D' (diario) via Brapi; intraday exige plano/licenca
# (comparacao normalizada em minusculas no metodo, entao guardamos ja assim)
_SUPPORTED_INTERVALS = {"d", "1d"}
_HIST_CACHE: dict = {}


def _provider():
    cfg_composite = CompositeQuoteProvider(providers=[
        BrapiQuoteProvider(),
        HGBrasilQuoteProvider(),
    ])
    return cfg_composite


class BrokerData:
    def __init__(self, auth_token, feed_token=None):
        self.auth_token = auth_token
        self.provider = _provider()

    # ---------------------------------------------------------------- quotes
    def get_quotes(self, symbol: str, exchange: str) -> dict:
        br_symbol = get_br_symbol(symbol, exchange) or symbol
        q = self.provider.get_quote(br_symbol)
        return to_openalgo_quote(q)

    def get_multiquotes(self, symbols: list) -> list:
        out = []
        for item in symbols or []:
            symbol, exchange = item.get("symbol"), item.get("exchange")
            try:
                out.append({
                    "symbol": symbol, "exchange": exchange,
                    "data": self.get_quotes(symbol, exchange),
                })
            except Exception as exc:  # noqa: BLE001
                out.append({"symbol": symbol, "exchange": exchange,
                            "error": str(exc)})
        return out

    # ---------------------------------------------------------------- depth
    def get_depth(self, symbol: str, exchange: str) -> dict:
        br_symbol = get_br_symbol(symbol, exchange) or symbol
        try:
            quote = self.provider.get_quote(br_symbol)
        except Exception:  # noqa: BLE001
            from openalgo_b3_adapter.market_data.b3_quotes import Quote
            quote = Quote(symbol=br_symbol)
        book = SimulatedBookProvider(quote=quote).get_book(br_symbol)
        return book_to_openalgo_depth(book)

    # --------------------------------------------------------------- history
    def get_history(self, symbol, exchange, interval, start_date, end_date) -> pd.DataFrame:
        if str(interval).lower() not in _SUPPORTED_INTERVALS:
            raise Exception(
                f"Intervalo '{interval}' ainda nao suportado no adapter B3. "
                "Suportado: 'D' (diario, via Brapi). Intraday exige plano "
                "pago da Brapi ou licenca B3 Market Data (docs/BROKERS-BR.md)."
            )
        br_symbol = get_br_symbol(symbol, exchange) or symbol
        # Mercado fracionario (sufixo "F") compartilha o mesmo historico do
        # lote padrao; a Brapi nao conhece o ticker "F".
        query_symbol = strip_fractional(br_symbol)
        import os
        import httpx
        from openalgo_b3_adapter.config.b3_config import get_config

        cfg = get_config()
        headers = {"Authorization": f"Bearer {cfg.brapi_api_key}"} if cfg.brapi_api_key else {}
        start = start_date.strftime("%Y-%m-%d") if hasattr(start_date, "strftime") else str(start_date)
        end = end_date.strftime("%Y-%m-%d") if hasattr(end_date, "strftime") else str(end_date)
        resp = httpx.get(
            f"{cfg.brapi_base_url}/api/v2/stocks/historical",
            headers=headers,
            params={"symbols": query_symbol, "startDate": start, "endDate": end, "interval": "1d"},
            timeout=10,
        )
        resp.raise_for_status()
        payload = resp.json()
        rows = []
        results = payload.get("results") or []
        if results:
            series = (results[0] or {}).get("data", {}).get("historicalDataPrice", [])
            for r in series:
                rows.append({
                    "timestamp": _dt.datetime.fromtimestamp(r["date"], _dt.timezone.utc),
                    "open": r.get("open"), "high": r.get("high"),
                    "low": r.get("low"), "close": r.get("close"),
                    "volume": r.get("volume", 0), "oi": 0,
                })
        df = pd.DataFrame(rows, columns=["timestamp", "open", "high", "low", "close", "volume", "oi"])
        return df
'@

    "openalgo_b3_adapter\market_data\b3_quotes.py" = @'
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


def to_openalgo_quote(q: Quote) -> Dict[str, Any]:
    """Formato padronizado esperado pelo core do OpenAlgo (BrokerData.get_quotes)."""
    return {
        "bid": float(q.bid), "ask": float(q.ask), "open": float(q.open),
        "high": float(q.high), "low": float(q.low), "ltp": float(q.ltp),
        "prev_close": float(q.prev_close), "volume": int(q.volume),
        "oi": int(q.oi),
        "tick_size": q.tick_size if q.tick_size is not None else 0.01,
    }


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
        )


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
'@

}

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Alterados = @()
$Incluidos = @()

foreach ($dest in $Arquivos.Keys) {
    $alvo = Join-Path $Raiz $dest
    $dirAlvo = Split-Path $alvo -Parent
    if (-not (Test-Path $dirAlvo)) {
        New-Item -ItemType Directory -Force -Path $dirAlvo | Out-Null
    }
    if (Test-Path $alvo) {
        # 2. backup da versao ATUAL (antiga) antes de sobrescrever
        $bk = Join-Path $DirAnt ($dest -replace "[\\/]", "__")
        Copy-Item -LiteralPath $alvo -Destination $bk -Force
        $Alterados += $dest
    } else {
        $Incluidos += $dest
    }
    # 3. grava o conteudo corrigido (UTF-8 sem BOM)
    [System.IO.File]::WriteAllText($alvo, $Arquivos[$dest], $Utf8NoBom)
    # 4. copia versionada do arquivo novo
    $cp = Join-Path $DirVer ($dest -replace "[\\/]", "__")
    Copy-Item -LiteralPath $alvo -Destination $cp -Force
}

# --- 5. copia versionada de si mesmo ---
Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $DirVer "patch_v014_2026-09-27_0014.ps1") -Force

# --- 6. registro ---
$linha = "$Ver;2026-09-27 00:14;openalgo_plugin\broker\b3\api\data.py|openalgo_b3_adapter\market_data\b3_quotes.py;correcao: historico do grafico (bug de case sensitivity no intervalo D) + cotacao/historico do mercado fracionario (sufixo F) usam ticker base na Brapi/HG Brasil`n"
[System.IO.File]::AppendAllText($Registro, $linha, $Utf8NoBom)

# --- 7. resumo + autodestruicao ---
Write-Host ""
Write-Host "========================================"
Write-Host "Patch $Ver aplicado:"
foreach ($a in $Alterados) { Write-Host "  alterado : $a" }
foreach ($a in $Incluidos) { Write-Host "  incluido : $a" }
Write-Host "Backup (versao antiga): patches\$Ver\anteriores\"
Write-Host "Copias versionadas    : patches\$Ver\"
Write-Host "Registro atualizado   : patches\registro.csv"
Write-Host "========================================"
Read-Host "Pressione ENTER para concluir e remover o script"

Remove-Item -LiteralPath $PSCommandPath -Force
Write-Host "Script de patch removido (autodestruicao). Ate logo."
