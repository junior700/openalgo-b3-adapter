# ============================================================
# replicar_github.ps1 (v1) - Replica o projeto do GitHub nesta
# pasta raiz generica:
#   https://github.com/junior700/openalgo-b3-adapter
#
# COMO USAR: coloque este arquivo (e o .bat) na PASTA RAIZ
# generica e rode:
#   powershell -ExecutionPolicy Bypass -File .\replicar_github.ps1
# ou de dois cliques em replicar_github.bat
#
# O QUE ELE FAZ:
#   1. confere se o git esta instalado
#   2. pasta openalgo-b3-adapter NAO existe -> git clone
#      (repositorio publico, nao precisa de token)
#   3. pasta JA existe -> oferece atualizar com git pull
#      (token do token_github.txt opcional: usado so em
#      memoria, NUNCA gravado no .git/config - convencoes
#      do projeto)
#   4. mostra o resumo e pausa antes de sair
# ============================================================

$ErrorActionPreference = "Continue"

$Repo   = "https://github.com/junior700/openalgo-b3-adapter.git"
$Pasta  = "openalgo-b3-adapter"

Write-Host ""
Write-Host "=== REPLICAR PROJETO DO GITHUB ===" -ForegroundColor Cyan
Write-Host "Projeto: openalgo-b3-adapter (OpenAlgo <-> B3)"
Write-Host ""

# --- raiz: pasta onde este script vive ---
$Raiz = $PSScriptRoot
if (-not $Raiz) { $Raiz = (Get-Location).Path }
Set-Location $Raiz
Write-Host "Pasta raiz: $Raiz"
Write-Host ""

# --- git instalado? ---
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "ERRO: git nao encontrado. Instale em https://git-scm.com" -ForegroundColor Red
    Read-Host "Pressione ENTER para sair"
    exit 1
}

# --- token opcional (so em memoria, convencoes do projeto) ---
$UrlPush = $Repo
$TokenFile = Join-Path $Raiz "token_github.txt"
if (Test-Path $TokenFile) {
    $tok = (Get-Content $TokenFile -First 1).Trim()
    if ($tok) {
        $UrlPush = "https://$tok@github.com/junior700/openalgo-b3-adapter.git"
        Write-Host "token_github.txt encontrado (token usado so em memoria)."
    }
}
Write-Host ""

# --- clone ou pull ---
if (Test-Path (Join-Path $Pasta ".git")) {
    Write-Host "O projeto JA existe aqui ($Pasta)."
    $r = Read-Host "Atualizar com git pull? [S/N]"
    if ($r -eq "S" -or $r -eq "s") {
        Push-Location $Pasta
        git pull $UrlPush main
        Pop-Location
    } else {
        Write-Host "Atualizacao cancelada."
    }
} elseif (Test-Path $Pasta) {
    Write-Host "ERRO: a pasta $Pasta existe mas nao e um clone git." -ForegroundColor Red
    Write-Host "Mova ou remova a pasta e rode de novo."
    Read-Host "Pressione ENTER para sair"
    exit 1
} else {
    Write-Host "Clonando repositorio (publico)..."
    git clone $Repo $Pasta
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERRO no clone. Verifique a conexao e rode de novo." -ForegroundColor Red
        Read-Host "Pressione ENTER para sair"
        exit 1
    }
}

# --- resumo ---
Write-Host ""
Write-Host "========================================"
if (Test-Path (Join-Path $Pasta ".git")) {
    $n = (Get-ChildItem $Pasta -Recurse -File |
          Measure-Object).Count
    Write-Host "Replica pronta: $Pasta ($n arquivos)"
    Write-Host ""
    Write-Host "Proximos passos:"
    Write-Host "  cd $Pasta"
    Write-Host "  pip install -e .[dev]"
    Write-Host "  pytest -q"
    Write-Host "  (veja README.md e docs/INSTALL.md)"
} else {
    Write-Host "Replica incompleta - revise as mensagens acima."
}
Write-Host "========================================"
Read-Host "Pressione ENTER para sair"
