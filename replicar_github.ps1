# ============================================================
# replicar_github.ps1 (v3) - USO UNICO: primeira vez, numa pasta
# AINDA SEM o projeto (sem .git aqui). Depois deste passo, TODO
# git (baixar novidades e enviar mudancas) passa a ser feito
# pelo iniciar_b3.ps1 -> opcao [3] Sincronizar com GitHub. Nao
# ha mais scripts soltos de git (publicar_github/sincronizar_github
# foram absorvidos pelo iniciar_b3.ps1 para acabar com a bagunca
# de varios arquivos de sincronizacao na raiz).
#
# Replica o projeto do GitHub NA PROPRIA pasta raiz onde este
# script esta (SEM criar subpasta):
#   https://github.com/junior700/openalgo-b3-adapter
#
# COMO USAR (so na primeira vez): coloque este arquivo (e o .bat)
# na PASTA RAIZ generica e rode:
#   powershell -ExecutionPolicy Bypass -File .\replicar_github.ps1
# ou de dois cliques em replicar_github.bat
#
# IMPORTANTE (v2): a pasta onde este script esta VIRA o proprio
# repositorio - nao cria mais "openalgo-b3-adapter\" por dentro.
# Assim sincronizar_github.ps1 e os demais scripts, TODOS soltos
# na mesma raiz, ficam operando no mesmo lugar - sem bagunca de
# dois niveis.
#
# O QUE ELE FAZ:
#   1. confere se o git esta instalado
#   2. raiz JA e um clone (tem .git) -> so atualiza (git pull/reset)
#   3. raiz NAO e um clone -> git init + remote + fetch + checkout
#      NESTA MESMA pasta (funciona mesmo com os scripts soltos aqui,
#      baixados do zip: eles sao sobrescritos pelas versoes do repo,
#      que sao identicas ou mais novas - nada se perde)
#   4. token opcional (token_github.txt): usado so em memoria,
#      NUNCA gravado no .git/config - convencoes do projeto
#   5. mostra o resumo e pausa antes de sair
# ============================================================

$ErrorActionPreference = "Continue"

$Repo = "https://github.com/junior700/openalgo-b3-adapter.git"

Write-Host ""
Write-Host "=== REPLICAR PROJETO DO GITHUB (nesta mesma pasta) ===" -ForegroundColor Cyan
Write-Host "Projeto: openalgo-b3-adapter (OpenAlgo <-> B3)"
Write-Host ""

# --- raiz: pasta onde este script vive (SEM criar subpasta) ---
$Raiz = $PSScriptRoot
if (-not $Raiz) { $Raiz = (Get-Location).Path }
Set-Location $Raiz
Write-Host "Pasta raiz (vira o repositorio): $Raiz"
Write-Host ""

# --- git instalado? ---
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "ERRO: git nao encontrado. Instale em https://git-scm.com" -ForegroundColor Red
    Read-Host "Pressione ENTER para sair"
    exit 1
}

# --- token opcional (so em memoria, convencoes do projeto) ---
$UrlFetch = $Repo
$TokenFile = Join-Path $Raiz "token_github.txt"
if (Test-Path $TokenFile) {
    $tok = (Get-Content $TokenFile -First 1).Trim()
    if ($tok) {
        $UrlFetch = "https://$tok@github.com/junior700/openalgo-b3-adapter.git"
        Write-Host "token_github.txt encontrado (token usado so em memoria)."
    }
}
Write-Host ""

# --- ja e um clone aqui? so atualiza ---
if (Test-Path (Join-Path $Raiz ".git")) {
    Write-Host "Esta pasta JA e o repositorio (contem .git)."
    $r = Read-Host "Atualizar com git pull? [S/N]"
    if ($r -eq "S" -or $r -eq "s") {
        git fetch $UrlFetch main
        git merge origin/main -m "merge: sincronizacao automatica" 2>$null
        if ($LASTEXITCODE -ne 0) { git reset --hard FETCH_HEAD }
    } else {
        Write-Host "Atualizacao cancelada."
    }
} else {
    # --- transforma a PROPRIA pasta no repositorio (sem subpasta) ---
    Write-Host "Transformando esta pasta no repositorio (git init + fetch)..."
    git init -q
    git remote add origin $Repo 2>$null
    git fetch $UrlFetch main
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERRO no fetch. Verifique a conexao e rode de novo." -ForegroundColor Red
        Read-Host "Pressione ENTER para sair"
        exit 1
    }
    # sobrescreve os arquivos soltos que ja estavam aqui (identicos/mais novos)
    git checkout -f -B main FETCH_HEAD
}

# --- resumo ---
Write-Host ""
Write-Host "========================================"
if (Test-Path (Join-Path $Raiz ".git")) {
    $n = (Get-ChildItem $Raiz -Recurse -File -Exclude ".git" |
          Where-Object { $_.FullName -notmatch "\\\.git\\" } |
          Measure-Object).Count
    Write-Host "Replica pronta AQUI MESMO: $Raiz ($n arquivos, sem subpasta)"
    Write-Host ""
    Write-Host "Proximos passos:"
    Write-Host "  pip install -e .[dev]"
    Write-Host "  pytest -q"
    Write-Host "  .\sincronizar_github.ps1   (mesma pasta, mesmo repo)"
    Write-Host "  (veja README.md e docs/INSTALL.md)"
} else {
    Write-Host "Replica incompleta - revise as mensagens acima."
}
Write-Host "========================================"
Read-Host "Pressione ENTER para sair"
