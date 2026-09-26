# ============================================================
# patch.ps1 - aplicador automatico de correcoes
# Projeto: openalgo-b3-adapter
# Versao:  v001_2026-09-26_1839  |  Arquivos: 1
# Descricao: fix-replicar-sem-subpasta-duplicada
#
# COMO USAR (na raiz da instalacao replicada):
#   powershell -ExecutionPolicy Bypass -File .\patch_v001_2026-09-26_1839.ps1
#
# O QUE ELE FAZ (nesta ordem):
#   0. recusa re-aplicacao (patches\registro.csv) e pede confirmacao
#   1. cria a pasta patches\v001_2026-09-26_1839\
#   2. backup dos arquivos ATUAIS em v001_2026-09-26_1839\anteriores\
#      (arquivo novo = inclusao, sem backup)
#   3. grava os arquivos corrigidos nos lugares devidos
#      (UTF-8 sem BOM; cria subpastas se faltar)
#   4. guarda copia versionada dos novos em v001_2026-09-26_1839\
#   5. guarda copia versionada DE SI MESMO em v001_2026-09-26_1839\
#   6. anexa uma linha no patches\registro.csv
#   7. mostra o resumo, espera ENTER e SE AUTODESTRUI
#
# RASTREIO: patches\registro.csv guarda versao, data, arquivos e
# resultado. ROLLBACK MANUAL: copie de v001_2026-09-26_1839\anteriores\.
#
# REGRAS DO PROJETO: pausa antes de qualquer saida, confirmacao
# antes de tocar em qualquer arquivo, token nunca gravado.
# ============================================================

$ErrorActionPreference = "Stop"
$Raiz = $PSScriptRoot
if (-not $Raiz) { $Raiz = (Get-Location).Path }

$Ver  = "v001_2026-09-26_1839"
$Desc = "fix-replicar-sem-subpasta-duplicada"

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

    "replicar_github.ps1" = @'
# ============================================================
# replicar_github.ps1 (v2) - Replica o projeto do GitHub NA PROPRIA
# pasta raiz onde este script esta (SEM criar subpasta):
#   https://github.com/junior700/openalgo-b3-adapter
#
# COMO USAR: coloque este arquivo (e o .bat) na PASTA RAIZ
# generica e rode:
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
Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $DirVer "patch_v001_2026-09-26_1839.ps1") -Force

# --- 6. registro ---
$linha = "$Ver;2026-09-26 18:39;replicar_github.ps1;fix-replicar-sem-subpasta-duplicada`n"
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
