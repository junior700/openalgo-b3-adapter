# ============================================================
# patch.ps1 - aplicador automatico de correcoes
# Projeto: openalgo-b3-adapter
# Versao:  v028_2026-09-27_2232  |  Arquivos: 1
# Descricao: Teste de shape da cotacao atualizado p/ incluir timeSec (campo adicionado no v022 que acabou com o candle fantasma). Suite 76/76 verde.
#
# COMO USAR (na raiz da instalacao replicada):
#   powershell -ExecutionPolicy Bypass -File .\patch_v028_2026-09-27_2232.ps1
#
# O QUE ELE FAZ (nesta ordem):
#   0. recusa re-aplicacao (patches\registro.csv) e pede confirmacao
#   1. cria a pasta patches\v028_2026-09-27_2232\
#   2. backup dos arquivos ATUAIS em v028_2026-09-27_2232\anteriores\
#      (arquivo novo = inclusao, sem backup)
#   3. grava os arquivos corrigidos nos lugares devidos
#      (UTF-8 sem BOM; cria subpastas se faltar)
#   4. guarda copia versionada dos novos em v028_2026-09-27_2232\
#   5. guarda copia versionada DE SI MESMO em v028_2026-09-27_2232\
#   6. anexa uma linha no patches\registro.csv
#   7. mostra o resumo, espera ENTER e SE AUTODESTRUI
#
# RASTREIO: patches\registro.csv guarda versao, data, arquivos e
# resultado. ROLLBACK MANUAL: copie de v028_2026-09-27_2232\anteriores\.
#
# REGRAS DO PROJETO: pausa antes de qualquer saida, confirmacao
# antes de tocar em qualquer arquivo, token nunca gravado.
# ============================================================

$ErrorActionPreference = "Stop"
$Raiz = $PSScriptRoot
if (-not $Raiz) { $Raiz = (Get-Location).Path }

$Ver  = "v028_2026-09-27_2232"
$Desc = "Teste de shape da cotacao atualizado p/ incluir timeSec (campo adicionado no v022 que acabou com o candle fantasma). Suite 76/76 verde."

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

    "tests\test_quotes_mapping.py" = @'
from openalgo_b3_adapter.market_data.b3_quotes import (
    BrapiQuoteProvider, CompositeQuoteProvider, HGBrasilQuoteProvider,
    to_openalgo_quote,
)


def _brapi_fetch(url, headers=None, params=None):
    assert "brapi.dev" in url
    assert params["symbols"] == "PETR4"
    if headers and "Authorization" in headers:
        assert headers["Authorization"].startswith("Bearer ")
    return {
        "results": [{
            "symbol": "PETR4",
            "data": {
                "regularMarketPrice": 41.18,
                "regularMarketOpen": 40.90,
                "regularMarketDayHigh": 41.40,
                "regularMarketDayLow": 40.75,
                "regularMarketPreviousClose": 41.76,
                "regularMarketBidPrice": 41.17,
                "regularMarketAskPrice": 41.18,
                "regularMarketVolume": 34024700,
            },
        }],
    }


def _hg_fetch(url, headers=None, params=None):
    assert "hgbrasil" in url
    return {
        "by": "HG Brasil",
        "results": {"VALE3": {"symbol": "VALE3", "name": "Vale ON",
                               "region": "Sao Paulo", "currency": "BRL",
                               "price": 61.92, "open": 61.20, "higher": 62.10,
                               "lower": 61.10, "close": 61.55, "volume": 28000000}},
    }


def test_brapi_provider_maps_to_quote():
    prov = BrapiQuoteProvider(fetch=_brapi_fetch)
    q = prov.get_quote("PETR4")
    assert q.ltp == 41.18
    assert q.prev_close == 41.76
    assert q.volume == 34024700
    assert q.source == "brapi"


def test_hgbrasil_provider_maps_to_quote():
    prov = HGBrasilQuoteProvider(fetch=_hg_fetch)
    q = prov.get_quote("VALE3")
    assert q.ltp == 61.92
    assert q.high == 62.10


def test_openalgo_quote_shape():
    prov = BrapiQuoteProvider(fetch=_brapi_fetch)
    data = to_openalgo_quote(prov.get_quote("PETR4"))
    # timeSec (epoch do ultimo negocio) entrou no v022: e ele que acaba
    # com o candle fantasma - o terminal passa a carimbar o tick com o
    # tempo real do negocio, nao com o relogio do navegador.
    assert set(data) == {"bid", "ask", "open", "high", "low", "ltp",
                         "prev_close", "volume", "oi", "tick_size", "timeSec"}
    assert data["ltp"] == 41.18
    assert data["oi"] == 0
    assert isinstance(data["volume"], int)


def test_composite_fallback_and_cache():
    calls = {"n": 0}

    def failing(url, headers=None, params=None):
        calls["n"] += 1
        raise ConnectionError("brapi fora")

    composite = CompositeQuoteProvider(
        providers=[
            BrapiQuoteProvider(fetch=failing),
            HGBrasilQuoteProvider(fetch=_hg_fetch),
        ],
        ttl=60,
    )
    q = composite.get_quote("VALE3")
    assert q.ltp == 61.92
    # cache: segunda chamada nao bate na rede
    composite.get_quote("VALE3")
    assert calls["n"] == 1
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
Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $DirVer "patch_v028_2026-09-27_2232.ps1") -Force

# --- 6. registro ---
$linha = "$Ver;2026-09-27 22:32;tests\test_quotes_mapping.py;Teste de shape da cotacao atualizado p/ incluir timeSec (campo adicionado no v022 que acabou com o candle fantasma). Suite 76/76 verde.`n"
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
