# ============================================================
# patch.ps1 - aplicador automatico de correcoes
# Projeto: openalgo-b3-adapter
# Versao:  v004_2026-09-26_2008  |  Arquivos: 1
# Descricao: iniciador automatico: iniciar_openalgo.ps1 (sobe OpenAlgo + plugin B3 + abre navegador)
#
# COMO USAR (na raiz da instalacao replicada):
#   powershell -ExecutionPolicy Bypass -File .\patch_v004_2026-09-26_2008.ps1
#
# O QUE ELE FAZ (nesta ordem):
#   0. recusa re-aplicacao (patches\registro.csv) e pede confirmacao
#   1. cria a pasta patches\v004_2026-09-26_2008\
#   2. backup dos arquivos ATUAIS em v004_2026-09-26_2008\anteriores\
#      (arquivo novo = inclusao, sem backup)
#   3. grava os arquivos corrigidos nos lugares devidos
#      (UTF-8 sem BOM; cria subpastas se faltar)
#   4. guarda copia versionada dos novos em v004_2026-09-26_2008\
#   5. guarda copia versionada DE SI MESMO em v004_2026-09-26_2008\
#   6. anexa uma linha no patches\registro.csv
#   7. mostra o resumo, espera ENTER e SE AUTODESTRUI
#
# RASTREIO: patches\registro.csv guarda versao, data, arquivos e
# resultado. ROLLBACK MANUAL: copie de v004_2026-09-26_2008\anteriores\.
#
# REGRAS DO PROJETO: pausa antes de qualquer saida, confirmacao
# antes de tocar em qualquer arquivo, token nunca gravado.
# ============================================================

$ErrorActionPreference = "Stop"
$Raiz = $PSScriptRoot
if (-not $Raiz) { $Raiz = (Get-Location).Path }

$Ver  = "v004_2026-09-26_2008"
$Desc = "iniciador automatico: iniciar_openalgo.ps1 (sobe OpenAlgo + plugin B3 + abre navegador)"

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

    "iniciar_openalgo.ps1" = @'
# ============================================================
#  iniciar_openalgo.ps1 - iniciador automatico do OpenAlgo + plugin B3
#  Uso: clique direito -> "Executar com PowerShell", ou no terminal:
#       powershell -ExecutionPolicy Bypass -File .\iniciar_openalgo.ps1
#  Faz tudo: localiza o core, espelha o plugin B3, prepara o
#  ambiente virtual, abre o navegador e sobe o servidor.
# ============================================================
$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

# --- [1/5] localiza o core do OpenAlgo ---
$candidates = @(
    (Join-Path $PSScriptRoot "openalgo"),
    (Join-Path (Split-Path $PSScriptRoot -Parent) "openalgo"),
    $env:OPENALGO_HOME
) | Where-Object { $_ -and (Test-Path (Join-Path $_ "app.py")) }

if (-not $candidates) {
    Write-Host "[ERRO] Nao encontrei o app.py do OpenAlgo." -ForegroundColor Red
    Write-Host "Coloque este script na raiz do openalgo-b3-adapter com o core em"
    Write-Host "'openalgo\' ou '..\openalgo\', ou defina `$env:OPENALGO_HOME."
    Read-Host "Enter para sair"
    exit 1
}
$OA = Resolve-Path $candidates[0]
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
Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $DirVer "patch_v004_2026-09-26_2008.ps1") -Force

# --- 6. registro ---
$linha = "$Ver;2026-09-26 20:08;iniciar_openalgo.ps1;iniciador automatico: iniciar_openalgo.ps1 (sobe OpenAlgo + plugin B3 + abre navegador)`n"
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
