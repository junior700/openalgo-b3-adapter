# ============================================================
# patch.ps1 - aplicador automatico de correcoes
# Projeto: openalgo-b3-adapter
# Versao:  v020_2026-09-27_1732  |  Arquivos: 2
# Descricao: seletor W/M (Yahoo 1wk/1mo) + fuso horario America/Sao_Paulo do grafico (injecao no frontend, padrao v012)
#
# COMO USAR (na raiz da instalacao replicada):
#   powershell -ExecutionPolicy Bypass -File .\patch_v020_2026-09-27_1732.ps1
#
# O QUE ELE FAZ (nesta ordem):
#   0. recusa re-aplicacao (patches\registro.csv) e pede confirmacao
#   1. cria a pasta patches\v020_2026-09-27_1732\
#   2. backup dos arquivos ATUAIS em v020_2026-09-27_1732\anteriores\
#      (arquivo novo = inclusao, sem backup)
#   3. grava os arquivos corrigidos nos lugares devidos
#      (UTF-8 sem BOM; cria subpastas se faltar)
#   4. guarda copia versionada dos novos em v020_2026-09-27_1732\
#   5. guarda copia versionada DE SI MESMO em v020_2026-09-27_1732\
#   6. anexa uma linha no patches\registro.csv
#   7. mostra o resumo, espera ENTER e SE AUTODESTRUI
#
# RASTREIO: patches\registro.csv guarda versao, data, arquivos e
# resultado. ROLLBACK MANUAL: copie de v020_2026-09-27_1732\anteriores\.
#
# REGRAS DO PROJETO: pausa antes de qualquer saida, confirmacao
# antes de tocar em qualquer arquivo, token nunca gravado.
# ============================================================

$ErrorActionPreference = "Stop"
$Raiz = $PSScriptRoot
if (-not $Raiz) { $Raiz = (Get-Location).Path }

$Ver  = "v020_2026-09-27_1732"
$Desc = "seletor W/M (Yahoo 1wk/1mo) + fuso horario America/Sao_Paulo do grafico (injecao no frontend, padrao v012)"

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

        resp = httpx.get(
            f"https://query2.finance.yahoo.com/v8/finance/chart/{yahoo_symbol}",
            headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"},
            params={
                "interval": y_interval,
                "period1": int(p1.timestamp()),
                "period2": int(max(p2.timestamp(), p1.timestamp())) + 86399,
                "includePrePost": "false",
                "events": "div,splits",
            },
            timeout=10,
        )
        if resp.status_code != 200:
            raise Exception(
                f"Yahoo Finance retornou HTTP {resp.status_code} para "
                f"{yahoo_symbol} intervalo '{norm}'. Papeis sem intraday no "
                "Yahoo (ex. opcoes) exigem licenca B3 Market Data."
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

    "iniciar_openalgo.ps1" = @'
# ============================================================
#  iniciar_openalgo.ps1 - iniciador automatico do OpenAlgo + plugin B3
#  Uso: clique direito -> "Executar com PowerShell", ou no terminal:
#       powershell -ExecutionPolicy Bypass -File .\iniciar_openalgo.ps1
#  Faz tudo: localiza o core, espelha o plugin B3, prepara o
#  ambiente virtual, abre o navegador e sobe o servidor.
# ============================================================
# --- Auto-Bypass: reabre com -ExecutionPolicy Bypass (e janela que nao fecha) ---
if ($env:OA_SELFRELAUNCH -ne "1") {
    $env:OA_SELFRELAUNCH = "1"
    $raiz = $PSScriptRoot
    $arq  = $PSCommandPath
    Start-Process -FilePath "powershell.exe" -ArgumentList @(
        "-NoProfile","-ExecutionPolicy","Bypass","-NoExit",
        "-Command","`$env:OA_SELFRELAUNCH='1'; Set-Location -LiteralPath '$raiz'; & '$arq'"
    )
    exit
}

$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

# --- [1/5] localiza o core do OpenAlgo ---
$candidates = @(@(
    (Join-Path $PSScriptRoot "openalgo"),
    (Join-Path (Split-Path $PSScriptRoot -Parent) "openalgo"),
    $env:OPENALGO_HOME
) | Where-Object { $_ -and (Test-Path (Join-Path $_ "app.py")) })

if (-not $candidates) {
    # Auto-instalacao: clona o OpenAlgo oficial (zero modificacoes) na raiz
    Write-Host "[1/5] Core do OpenAlgo ausente. Clonando o oficial do GitHub..."
    $dest = Join-Path $PSScriptRoot "openalgo"
    git clone --depth 1 https://github.com/marketcalls/openalgo.git $dest
    if (Test-Path (Join-Path $dest "app.py")) {
        $OA = (Resolve-Path -LiteralPath $dest).Path
    } else {
        Write-Host "[ERRO] Clone do OpenAlgo falhou (git instalado? internet?)." -ForegroundColor Red
        Read-Host "Enter para sair"
        exit 1
    }
} else {
    $OA = (Resolve-Path -LiteralPath $candidates[0]).Path
}
Write-Host "[1/5] Core do OpenAlgo: $OA"

# --- [2/5] espelha o plugin B3 (drop-in, zero modificacao no core) ---
$pluginSrc = Join-Path $PSScriptRoot "openalgo_plugin\broker\b3"
$pluginDst = Join-Path $OA "broker\b3"
if (Test-Path $pluginSrc) {
    if (-not (Test-Path $pluginDst)) { New-Item -ItemType Directory -Path $pluginDst -Force | Out-Null }
    Copy-Item -Path "$pluginSrc\*" -Destination $pluginDst -Recurse -Force
    Write-Host "[2/5] Plugin B3 espelhado para o core."
} else {
    Write-Host "[2/5] AVISO: plugin nao encontrado em openalgo_plugin\broker\b3." -ForegroundColor Yellow
}

# --- [2b] injeta a B3 no dropdown do frontend (idempotente) ---
$distAssets = Join-Path $OA "frontend\dist\assets"
$bsFile = Get-ChildItem -Path $distAssets -Filter "BrokerSelect-*.js" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($bsFile -and -not (Select-String -Path $bsFile.FullName -Pattern 'id:`b3`' -Quiet)) {
    Write-Host "[2b] Injetando B3 no dropdown do frontend..."
    $c = Get-Content $bsFile.FullName -Raw
    $c = $c.Replace('zerodha`,name:`Zerodha`,authType:`oauth`}', 'zerodha`,name:`Zerodha`,authType:`oauth`},{id:`b3`,name:`B3 Brasil (Sandbox)`,authType:`totp`}')
    $c = $c.Replace('case`aliceblue`:case`angel`', 'case`b3`:case`aliceblue`:case`angel`')
    if ($c.Contains('id:`b3`')) {
        [System.IO.File]::WriteAllText($bsFile.FullName, $c, (New-Object System.Text.UTF8Encoding($false)))
        Get-ChildItem -Path $distAssets -Filter ($bsFile.Name + ".*") -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne $bsFile.Name } | Remove-Item -Force
        Write-Host "[2b] Dropdown atualizado (B3 visivel na lista)."
    } else {
        Write-Host "[2b] AVISO: padrao do frontend nao reconhecido; dropdown nao alterado." -ForegroundColor Yellow
    }
}

# --- [2c] espelha indicadores customizados do grafico (drop-in) ---
$indSrc = Join-Path $PSScriptRoot "openalgo_plugin\strategies\indicators"
$indDst = Join-Path $OA "strategies\indicators"
if (Test-Path $indSrc) {
    if (-not (Test-Path $indDst)) { New-Item -ItemType Directory -Path $indDst -Force | Out-Null }
    Copy-Item -Path "$indSrc\*" -Destination $indDst -Force
    Write-Host "[2c] Indicadores customizados espelhados para o core (strategies\indicators)."
} else {
    Write-Host "[2c] Sem indicadores customizados para espelhar." -ForegroundColor DarkGray
}

# --- [2d] fuso horario do grafico: America/Sao_Paulo em vez do padrao indiano (idempotente) ---
# A biblioteca openalgo-charts usa Asia/Kolkata como padrao; o Brasil merece
# o fuso local. Injeta a opcao `timezone` na criacao do grafico (bundle do
# terminal), com fallback para America/Sao_Paulo quando o navegador nao
# informa um fuso. Escolha manual nas configuracoes do grafico continua
# valendo (ela sobrescreve e persiste).
$trFile = Get-ChildItem -Path $distAssets -Filter "Trading-*.js" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($trFile -and (Select-String -Path $trFile.FullName -Pattern 'priceAxisWidth:78,theme:' -Quiet) -and -not (Select-String -Path $trFile.FullName -Pattern 'priceAxisWidth:78,timezone:' -Quiet)) {
    Write-Host "[2d] Injetando fuso horario do navegador no grafico (padrao America/Sao_Paulo)..."
    $c = Get-Content $trFile.FullName -Raw
    $c = $c.Replace('priceAxisWidth:78,theme:', 'priceAxisWidth:78,timezone:(Intl.DateTimeFormat().resolvedOptions().timeZone||`America/Sao_Paulo`),theme:')
    [System.IO.File]::WriteAllText($trFile.FullName, $c, (New-Object System.Text.UTF8Encoding($false)))
    Get-ChildItem -Path $distAssets -Filter ($trFile.Name + ".*") -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne $trFile.Name } | Remove-Item -Force
    Write-Host "[2d] Grafico abrira no fuso do navegador (Brasilia no Brasil)."
} else {
    Write-Host "[2d] Fuso do grafico ja injetado ou bundle nao encontrado." -ForegroundColor DarkGray
}

# --- [3/5] ambiente virtual ---
$py = Join-Path $OA ".venv\Scripts\python.exe"
if (-not (Test-Path $py)) {
    Write-Host "[3/5] Criando ambiente virtual..."
    $corePy = Get-Command python -ErrorAction SilentlyContinue
    if (-not $corePy) { $corePy = Get-Command py -ErrorAction SilentlyContinue }
    if (-not $corePy) {
        Write-Host "[ERRO] Python nao encontrado. Instale 3.12+ em https://python.org" -ForegroundColor Red
        Read-Host "Enter para sair"
        exit 1
    }
    & $corePy.Source -m venv (Join-Path $OA ".venv")
    & $py -m pip install --upgrade pip
    & $py -m pip install -r (Join-Path $OA "requirements.txt")
    & $py -m pip install -e $PSScriptRoot
} else {
    Write-Host "[3/5] Ambiente virtual encontrado."
}
if (-not (Test-Path $py)) {
    Write-Host "[ERRO] Falha ao criar o ambiente virtual." -ForegroundColor Red
    Read-Host "Enter para sair"
    exit 1
}

# --- [4/5] adapter B3 instalado/atualizado no venv ---
& $py -m pip install -e $PSScriptRoot --quiet --no-deps 2>$null
Write-Host "[4/5] Adapter B3 instalado no ambiente."

# --- configura o .env do OpenAlgo (padrao + plugin B3) ---
$envFile = Join-Path $OA ".env"
$envSample = Join-Path $OA ".sample.env"
$precisa = $true
if (Test-Path $envFile) {
    $linhaVb = Select-String -Path $envFile -Pattern "VALID_BROKERS" | Select-Object -First 1
    if ($null -ne $linhaVb -and $linhaVb.Line.Contains(",b3")) { $precisa = $false }
}
if ($precisa -and (Test-Path $envSample)) {
    Write-Host "[4b] Gerando .env (padrao do OpenAlgo + plugin B3)..."
    $bytes = New-Object byte[] 32
    (New-Object System.Security.Cryptography.RNGCryptoServiceProvider).GetBytes($bytes)
    $appkey = ($bytes | ForEach-Object { $_.ToString("x2") }) -join ""
    (New-Object System.Security.Cryptography.RNGCryptoServiceProvider).GetBytes($bytes)
    $pepper = ($bytes | ForEach-Object { $_.ToString("x2") }) -join ""
    (New-Object System.Security.Cryptography.RNGCryptoServiceProvider).GetBytes($bytes)
    $salt = (($bytes | ForEach-Object { $_.ToString("x2") }) -join "").Substring(0, 32)

    $final = @()
    foreach ($l in (Get-Content $envSample)) {
        if     ($l.StartsWith("VALID_BROKERS"))  { $l = $l.TrimEnd("'") + ",b3'" }
        elseif ($l.StartsWith("REDIRECT_URL"))   { $l = $l.Replace("<broker>", "b3") }
        elseif ($l.StartsWith("APP_KEY"))        { $l = "APP_KEY = '" + $appkey + "'" }
        elseif ($l.StartsWith("API_KEY_PEPPER")) { $l = "API_KEY_PEPPER = '" + $pepper + "'" }
        elseif ($l.StartsWith("FERNET_SALT"))     { $l = "FERNET_SALT = '" + $salt + "'" }
        $final += $l
    }
    $final += ""
    $final += "# --- Plugin B3 Brasil (corretora fantasma) ---"
    $final += "B3_BROKER_GATEWAY=sandbox"
    $final += "B3_SANDBOX_STATE_FILE=ghost_state.json"
    $final += "B3_SANDBOX_LIVE_FILLS=1"
    $final += "B3_SANDBOX_AUTO_TICK=30"
    $final += "B3_SANDBOX_INITIAL_CASH=100000"
    [System.IO.File]::WriteAllLines($envFile, $final, (New-Object System.Text.ASCIIEncoding))
}

# --- [5/5] abre o navegador apos o servidor subir e sobe o servidor ---
Start-Process powershell -ArgumentList "-NoProfile -Command `"Start-Sleep -Seconds 18; Start-Process 'http://127.0.0.1:5000'`""
Write-Host "[5/5] Subindo o OpenAlgo... o navegador abre sozinho em instantes." -ForegroundColor Green
Write-Host ""
Write-Host "Login da GUI: admin / OpenAlgo@B3Demo2026"
Write-Host "Feche esta janela (ou Ctrl+C) para parar o servidor."
Write-Host ""

Set-Location $OA
try { & $py app.py } finally {
    Write-Host ""
    Write-Host "Servidor encerrado."
    Read-Host "Enter para sair"
}
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
Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $DirVer "patch_v020_2026-09-27_1732.ps1") -Force

# --- 6. registro ---
$linha = "$Ver;2026-09-27 17:32;openalgo_plugin\broker\b3\api\data.py|iniciar_openalgo.ps1;seletor W/M (Yahoo 1wk/1mo) + fuso horario America/Sao_Paulo do grafico (injecao no frontend, padrao v012)`n"
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
