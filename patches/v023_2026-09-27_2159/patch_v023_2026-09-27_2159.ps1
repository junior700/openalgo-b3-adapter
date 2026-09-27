# ============================================================
# patch.ps1 - aplicador automatico de correcoes
# Projeto: openalgo-b3-adapter
# Versao:  v023_2026-09-27_2159  |  Arquivos: 1
# Descricao: Yahoo 422 local: cadeia robusta (query2/query1/range/cookie+crumb) no intraday + erro detalhado com dicas
#
# COMO USAR (na raiz da instalacao replicada):
#   powershell -ExecutionPolicy Bypass -File .\patch_v023_2026-09-27_2159.ps1
#
# O QUE ELE FAZ (nesta ordem):
#   0. recusa re-aplicacao (patches\registro.csv) e pede confirmacao
#   1. cria a pasta patches\v023_2026-09-27_2159\
#   2. backup dos arquivos ATUAIS em v023_2026-09-27_2159\anteriores\
#      (arquivo novo = inclusao, sem backup)
#   3. grava os arquivos corrigidos nos lugares devidos
#      (UTF-8 sem BOM; cria subpastas se faltar)
#   4. guarda copia versionada dos novos em v023_2026-09-27_2159\
#   5. guarda copia versionada DE SI MESMO em v023_2026-09-27_2159\
#   6. anexa uma linha no patches\registro.csv
#   7. mostra o resumo, espera ENTER e SE AUTODESTRUI
#
# RASTREIO: patches\registro.csv guarda versao, data, arquivos e
# resultado. ROLLBACK MANUAL: copie de v023_2026-09-27_2159\anteriores\.
#
# REGRAS DO PROJETO: pausa antes de qualquer saida, confirmacao
# antes de tocar em qualquer arquivo, token nunca gravado.
# ============================================================

$ErrorActionPreference = "Stop"
$Raiz = $PSScriptRoot
if (-not $Raiz) { $Raiz = (Get-Location).Path }

$Ver  = "v023_2026-09-27_2159"
$Desc = "Yahoo 422 local: cadeia robusta (query2/query1/range/cookie+crumb) no intraday + erro detalhado com dicas"

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

Fontes:
    - Diario 'D': Brapi/HG Brasil (plano gratuito, historico diario).
    - Intraday (1m/5m/15m/30m/1h): Yahoo Finance (dados reais da B3, sem
      chave; atraso de ~15 min em alguns papeis).
    - Semanal 'W' / mensal 'M': Yahoo Finance (1wk/1mo, ~20 anos).
    - Book: simulado para dev. Tempo real/licenca B3: docs/BROKERS-BR.md.
"""
import datetime as _dt
import os
import time as _time

import httpx
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

# diario via Brapi; intraday via Yahoo Finance (dados reais da B3)
_SUPPORTED_INTERVALS = {"d", "1d", "w", "m", "1m", "2m", "5m", "15m", "30m", "1h", "60m"}

# intervalos intraday que o Yahoo atende e o janela maxima de cada um
# (limites da API publica do Yahoo; pedir mais antigo que isso e recusado)
_YAHOO_WINDOWS = {
    "1m": ("1m", 7),      # 7 dias
    "2m": ("2m", 60),
    "5m": ("5m", 60),     # 60 dias
    "15m": ("15m", 60),
    "30m": ("30m", 60),
    "60m": ("60m", 730),  # ~2 anos (Yahoo trata 60m == 1h)
    "1h": ("60m", 730),
    # Semanal/mensal: o Yahoo aceita janelas longas sem limite de intervalo
    # fino; ~20 anos cobre o lookback maximo que o grafico pede (10 anos).
    "w": ("1wk", 7300),
    "m": ("1mo", 7300),
}

_HIST_CACHE: dict = {}
_HIST_CACHE_TTL = 60  # segundos; evita martelar Yahoo/Brapi a cada clique


def _provider():
    cfg_composite = CompositeQuoteProvider(providers=[
        BrapiQuoteProvider(),
        HGBrasilQuoteProvider(),
    ])
    return cfg_composite


def _to_yahoo_symbol(br_symbol: str) -> str:
    """PETR4/PETR4F -> PETR4.SA (sufixo do Yahoo para papeis da B3)."""
    base = strip_fractional(br_symbol)
    if "." in base:
        return base
    return f"{base}.SA"


class BrokerData:
    def __init__(self, auth_token, feed_token=None):
        self.auth_token = auth_token
        self.provider = _provider()
        # intervals_service.get_intervals_with_auth() anuncia ao grafico os
        # intervalos deste mapa (chaves filtradas pelo SUPPORTED_INTERVALS do
        # core). Diario via Brapi; intraday via Yahoo Finance.
        self.timeframe_map = {
            "1m": "1m", "2m": "2m", "5m": "5m", "15m": "15m",
            "30m": "30m", "1h": "1h", "D": "D",
            "W": "W", "M": "M",
        }

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
        norm = str(interval).lower()
        if norm not in _SUPPORTED_INTERVALS:
            raise Exception(
                f"Intervalo '{interval}' ainda nao suportado no adapter B3. "
                "Suportado: 'D' (diario, Brapi), intraday 1m/2m/5m/15m/30m/1h "
                "e semanal/mensal W/M (Yahoo Finance, dados reais da B3)."
            )
        br_symbol = get_br_symbol(symbol, exchange) or symbol
        # Mercado fracionario (sufixo "F") compartilha o mesmo historico do
        # lote padrao; nenhuma fonte conhece o ticker "F".
        query_symbol = strip_fractional(br_symbol)

        # cache curto por (simbolo, intervalo, janela)
        start = start_date.strftime("%Y-%m-%d") if hasattr(start_date, "strftime") else str(start_date)
        end = end_date.strftime("%Y-%m-%d") if hasattr(end_date, "strftime") else str(end_date)
        cache_key = (query_symbol, norm, start, end)
        hit = _HIST_CACHE.get(cache_key)
        if hit is not None and _time.time() - hit[0] < _HIST_CACHE_TTL:
            return hit[1].copy()

        if norm in ("d", "1d"):
            df = self._history_brapi(query_symbol, start, end)
        else:
            df = self._history_yahoo(query_symbol, norm, start, end)
        _HIST_CACHE[cache_key] = (_time.time(), df)
        return df.copy()

    def _history_brapi(self, query_symbol, start, end) -> pd.DataFrame:
        from openalgo_b3_adapter.config.b3_config import get_config

        cfg = get_config()
        headers = {"Authorization": f"Bearer {cfg.brapi_api_key}"} if cfg.brapi_api_key else {}
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
                    # Epoch (segundos, UTC) diretamente -- e o formato que o
                    # front-end (openalgo-charts) espera na coluna timestamp.
                    # Um datetime aqui e serializado pelo Flask como string
                    # RFC-1123 ("Sat, 26 Sep 2026 03:00:00 GMT"), que o parser
                    # do grafico rejeita com "unparseable IST time string".
                    "timestamp": int(r["date"]),
                    "open": r.get("open"), "high": r.get("high"),
                    "low": r.get("low"), "close": r.get("close"),
                    "volume": r.get("volume", 0), "oi": 0,
                })
        return pd.DataFrame(rows, columns=["timestamp", "open", "high", "low", "close", "volume", "oi"])

    def _yahoo_chart(self, yahoo_symbol, params, y_interval):
        """Chart da Yahoo com cadeia de tentativas robusta.

        Alguns IPs/redes do Brasil recebem HTTP 422/401 do Yahoo sem cookie de
        sessao (provider bloqueia scraping de ranges regionais). Tenta em ordem:
        query2 com periodos -> query1 com periodos -> query1 com range ->
        sessao com cookie+crumb. Se tudo falhar, erro detalhado com dicas.
        """
        ua = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"}
        chart_url = "https://{h}.finance.yahoo.com/v8/finance/chart/" + yahoo_symbol
        if y_interval == "1m":
            rng = "5d"
        elif y_interval in ("2m", "5m", "15m", "30m"):
            rng = "1mo"
        elif y_interval == "60m":
            rng = "2y"
        else:  # 1wk/1mo/1d
            rng = "10y"
        tentativas = [
            ("query2+periodos", chart_url.format(h="query2"), dict(params)),
            ("query1+periodos", chart_url.format(h="query1"), dict(params)),
            ("query1+range", chart_url.format(h="query1"), {
                "interval": y_interval, "range": rng,
                "includePrePost": "false", "events": "div,splits",
            }),
        ]
        ultima = ("nenhuma", 0)
        for tag, url, p in tentativas:
            try:
                resp = httpx.get(url, headers=ua, params=p, timeout=10)
            except Exception:
                continue
            if resp.status_code == 200:
                return resp
            ultima = (tag, resp.status_code)
        # ultima tentativa: sessao com cookie+crumb (exigida em alguns IPs)
        try:
            with httpx.Client(headers=ua, timeout=10) as client:
                client.get("https://fc.yahoo.com")  # fixa o cookie de sessao
                crumb = client.get(
                    "https://query1.finance.yahoo.com/v1/test/getcrumb"
                ).text.strip()
                if crumb and 0 < len(crumb) < 64:
                    p = dict(params)
                    p["crumb"] = crumb
                    resp = client.get(chart_url.format(h="query2"), params=p)
                    if resp.status_code == 200:
                        return resp
                    ultima = ("crumb", resp.status_code)
        except Exception:
            pass
        raise Exception(
            f"Yahoo Finance recusou a chamada para {yahoo_symbol} "
            f"(HTTP {ultima[1]} via {ultima[0]}). Causas comuns na maquina local: "
            "antivirus/proxy interceptando HTTPS (Avast Web Shield), VPN, "
            "relogio do Windows errado ou IP bloqueado pelo Yahoo. Teste no "
            "navegador: https://query1.finance.yahoo.com/v8/finance/chart/"
            f"{yahoo_symbol}?interval={y_interval}&range=5d"
        )

    def _history_yahoo(self, query_symbol, norm, start, end) -> pd.DataFrame:
        """Candles intraday reais da B3 via Yahoo Finance (sem chave)."""
        if norm not in _YAHOO_WINDOWS:
            raise Exception(f"Intervalo intraday '{norm}' nao disponivel no Yahoo.")
        y_interval, dias_max = _YAHOO_WINDOWS[norm]

        yahoo_symbol = _to_yahoo_symbol(query_symbol)
        # Yahoo recusa janelas mais antigas que o limite do intervalo: clampa
        # o inicio ao maximo permitido para nao devolver erro ao grafico.
        try:
            p1 = _dt.datetime.strptime(start, "%Y-%m-%d")
            p2 = _dt.datetime.strptime(end, "%Y-%m-%d")
        except ValueError:
            p1, p2 = None, None
        limit_ts = _dt.datetime.now() - _dt.timedelta(days=dias_max)
        if p1 is None or p1 < limit_ts:
            p1 = limit_ts
        if p2 is None:
            p2 = _dt.datetime.now()

        resp = self._yahoo_chart(
            yahoo_symbol,
            {
                "interval": y_interval,
                "period1": int(p1.timestamp()),
                "period2": int(max(p2.timestamp(), p1.timestamp())) + 86399,
                "includePrePost": "false",
                "events": "div,splits",
            },
            y_interval,
        )
        result = (resp.json().get("chart") or {}).get("result") or []
        if not result:
            raise Exception(f"Yahoo Finance sem dados intraday para {yahoo_symbol} '{norm}'.")
        chart = result[0]
        stamps = chart.get("timestamp") or []
        quote = ((chart.get("indicators") or {}).get("quote") or [{}])[0]
        opens, highs = quote.get("open") or [], quote.get("high") or []
        lows, closes = quote.get("low") or [], quote.get("close") or []
        vols = quote.get("volume") or []

        rows = []
        for i, ts in enumerate(stamps):
            o, h = (opens[i] if i < len(opens) else None), (highs[i] if i < len(highs) else None)
            l, c = (lows[i] if i < len(lows) else None), (closes[i] if i < len(closes) else None)
            if o is None or h is None or l is None or c is None:
                continue  # barra incompleta (leilao/leilao de abertura)
            rows.append({
                "timestamp": int(ts),  # epoch UTC, mesmo contrato do diario
                "open": float(o), "high": float(h), "low": float(l), "close": float(c),
                "volume": int(vols[i]) if i < len(vols) and vols[i] is not None else 0,
                "oi": 0,
            })
        return pd.DataFrame(rows, columns=["timestamp", "open", "high", "low", "close", "volume", "oi"])
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
Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $DirVer "patch_v023_2026-09-27_2159.ps1") -Force

# --- 6. registro ---
$linha = "$Ver;2026-09-27 21:59;openalgo_plugin\broker\b3\api\data.py;Yahoo 422 local: cadeia robusta (query2/query1/range/cookie+crumb) no intraday + erro detalhado com dicas`n"
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
