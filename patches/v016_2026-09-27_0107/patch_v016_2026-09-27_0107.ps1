# ============================================================
# patch.ps1 - aplicador automatico de correcoes
# Projeto: openalgo-b3-adapter
# Versao:  v016_2026-09-27_0107  |  Arquivos: 1
# Descricao: correcao: grafico com erro 'unparseable IST time string' - timestamp do historico devolvido como datetime (serializado pelo Flask em RFC-1123) em vez de epoch inteiro, que e o formato esperado pelo openalgo-charts
#
# COMO USAR (na raiz da instalacao replicada):
#   powershell -ExecutionPolicy Bypass -File .\patch_v016_2026-09-27_0107.ps1
#
# O QUE ELE FAZ (nesta ordem):
#   0. recusa re-aplicacao (patches\registro.csv) e pede confirmacao
#   1. cria a pasta patches\v016_2026-09-27_0107\
#   2. backup dos arquivos ATUAIS em v016_2026-09-27_0107\anteriores\
#      (arquivo novo = inclusao, sem backup)
#   3. grava os arquivos corrigidos nos lugares devidos
#      (UTF-8 sem BOM; cria subpastas se faltar)
#   4. guarda copia versionada dos novos em v016_2026-09-27_0107\
#   5. guarda copia versionada DE SI MESMO em v016_2026-09-27_0107\
#   6. anexa uma linha no patches\registro.csv
#   7. mostra o resumo, espera ENTER e SE AUTODESTRUI
#
# RASTREIO: patches\registro.csv guarda versao, data, arquivos e
# resultado. ROLLBACK MANUAL: copie de v016_2026-09-27_0107\anteriores\.
#
# REGRAS DO PROJETO: pausa antes de qualquer saida, confirmacao
# antes de tocar em qualquer arquivo, token nunca gravado.
# ============================================================

$ErrorActionPreference = "Stop"
$Raiz = $PSScriptRoot
if (-not $Raiz) { $Raiz = (Get-Location).Path }

$Ver  = "v016_2026-09-27_0107"
$Desc = "correcao: grafico com erro 'unparseable IST time string' - timestamp do historico devolvido como datetime (serializado pelo Flask em RFC-1123) em vez de epoch inteiro, que e o formato esperado pelo openalgo-charts"

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
        # intervals_service.get_intervals_with_auth() anuncia ao grafico os
        # intervalos deste mapa; so o diario 'D' e suportado (Brapi).
        self.timeframe_map = {"D": "D"}

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
        df = pd.DataFrame(rows, columns=["timestamp", "open", "high", "low", "close", "volume", "oi"])
        return df
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
Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $DirVer "patch_v016_2026-09-27_0107.ps1") -Force

# --- 6. registro ---
$linha = "$Ver;2026-09-27 01:07;openalgo_plugin\broker\b3\api\data.py;correcao: grafico com erro 'unparseable IST time string' - timestamp do historico devolvido como datetime (serializado pelo Flask em RFC-1123) em vez de epoch inteiro, que e o formato esperado pelo openalgo-charts`n"
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
