# ============================================================
# patch.ps1 - aplicador automatico de correcoes
# Projeto: openalgo-b3-adapter
# Versao:  v013_2026-09-26_2315  |  Arquivos: 1
# Descricao: sandbox B3: auto-autenticar sem credencial no Connect Account da GUI (loop resolvido)
#
# COMO USAR (na raiz da instalacao replicada):
#   powershell -ExecutionPolicy Bypass -File .\patch_v013_2026-09-26_2315.ps1
#
# O QUE ELE FAZ (nesta ordem):
#   0. recusa re-aplicacao (patches\registro.csv) e pede confirmacao
#   1. cria a pasta patches\v013_2026-09-26_2315\
#   2. backup dos arquivos ATUAIS em v013_2026-09-26_2315\anteriores\
#      (arquivo novo = inclusao, sem backup)
#   3. grava os arquivos corrigidos nos lugares devidos
#      (UTF-8 sem BOM; cria subpastas se faltar)
#   4. guarda copia versionada dos novos em v013_2026-09-26_2315\
#   5. guarda copia versionada DE SI MESMO em v013_2026-09-26_2315\
#   6. anexa uma linha no patches\registro.csv
#   7. mostra o resumo, espera ENTER e SE AUTODESTRUI
#
# RASTREIO: patches\registro.csv guarda versao, data, arquivos e
# resultado. ROLLBACK MANUAL: copie de v013_2026-09-26_2315\anteriores\.
#
# REGRAS DO PROJETO: pausa antes de qualquer saida, confirmacao
# antes de tocar em qualquer arquivo, token nunca gravado.
# ============================================================

$ErrorActionPreference = "Stop"
$Raiz = $PSScriptRoot
if (-not $Raiz) { $Raiz = (Get-Location).Path }

$Ver  = "v013_2026-09-26_2315"
$Desc = "sandbox B3: auto-autenticar sem credencial no Connect Account da GUI (loop resolvido)"

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

    "openalgo_plugin\broker\b3\api\auth_api.py" = @'
"""Autenticacao do plugin B3.

O fluxo generico do OpenAlgo chama authenticate_broker(code) no callback
/broker/b3 com o `code` digitado na tela de credenciais.

Modo sandbox (padrao): qualquer entrada gera um token de sessao
deterministico, registrado no SandboxGateway. Corretoras reais devem
validar a credencial na API da corretora e devolver o token de sessao.
"""
import os

from openalgo_b3_adapter.order_execution import get_gateway

from utils.logging import get_logger

logger = get_logger(__name__)


def authenticate_broker(code, password=None, totp_code=None):
    """Valida credencial e devolve (auth_token, error_message).

    No modo sandbox a credencial e irrelevante: a GUI do OpenAlgo conecta
    sem digitar nada (o botao "Connect Account" navega para /b3/callback
    sem parametros), entao ausencia de code auto-autentica como "sandbox".
    """
    code = (code or "").strip()

    try:
        gateway = get_gateway()
    except NotImplementedError as exc:
        return None, str(exc)
    except ValueError as exc:
        return None, str(exc)

    if getattr(gateway, "name", "") == "sandbox":
        if not code:
            code = "sandbox"
        token = f"SANDBOX::{code}"
        try:
            gateway.ensure_auth(token)
        except AttributeError:
            pass
        logger.info("B3 plugin: sessao sandbox autenticada")
        return token, None

    # Gateways reais (nuinvest/btg): o token de sessao e a propria credencial
    # validada pela corretora. Ate os gateways concretos serem implementados,
    # get_gateway() ja levanta NotImplementedError quando nao ha credenciais.
    if not code:
        return None, "Informe a credencial da corretora (campo API KEY)"
    return code, None
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
Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $DirVer "patch_v013_2026-09-26_2315.ps1") -Force

# --- 6. registro ---
$linha = "$Ver;2026-09-26 23:15;openalgo_plugin\broker\b3\api\auth_api.py;sandbox B3: auto-autenticar sem credencial no Connect Account da GUI (loop resolvido)`n"
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
