# ============================================================
# patch.ps1 - aplicador automatico de correcoes
# Projeto: openalgo-b3-adapter
# Versao:  v024_2026-09-27_2203  |  Arquivos: 1
# Descricao: sincronizar: opcao 1 e 3 agora APLICAM as novidades (merge --ff-only) - fetch so baixava e o projeto ficava travado em versao velha
#
# COMO USAR (na raiz da instalacao replicada):
#   powershell -ExecutionPolicy Bypass -File .\patch_v024_2026-09-27_2203.ps1
#
# O QUE ELE FAZ (nesta ordem):
#   0. recusa re-aplicacao (patches\registro.csv) e pede confirmacao
#   1. cria a pasta patches\v024_2026-09-27_2203\
#   2. backup dos arquivos ATUAIS em v024_2026-09-27_2203\anteriores\
#      (arquivo novo = inclusao, sem backup)
#   3. grava os arquivos corrigidos nos lugares devidos
#      (UTF-8 sem BOM; cria subpastas se faltar)
#   4. guarda copia versionada dos novos em v024_2026-09-27_2203\
#   5. guarda copia versionada DE SI MESMO em v024_2026-09-27_2203\
#   6. anexa uma linha no patches\registro.csv
#   7. mostra o resumo, espera ENTER e SE AUTODESTRUI
#
# RASTREIO: patches\registro.csv guarda versao, data, arquivos e
# resultado. ROLLBACK MANUAL: copie de v024_2026-09-27_2203\anteriores\.
#
# REGRAS DO PROJETO: pausa antes de qualquer saida, confirmacao
# antes de tocar em qualquer arquivo, token nunca gravado.
# ============================================================

$ErrorActionPreference = "Stop"
$Raiz = $PSScriptRoot
if (-not $Raiz) { $Raiz = (Get-Location).Path }

$Ver  = "v024_2026-09-27_2203"
$Desc = "sincronizar: opcao 1 e 3 agora APLICAM as novidades (merge --ff-only) - fetch so baixava e o projeto ficava travado em versao velha"

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

    "sincronizar_github.ps1" = @'
# ============================================================
# sincronizar_github.ps1 - Sincroniza a PASTA RAIZ onde for
# executado com o repositorio GitHub:
#   https://github.com/junior700/openalgo-b3-adapter
#
# Convencao herdada do Desktop_Agent_BASE44 (v4):
#   - TOKEN NUNCA gravado no .git/config: fetch/push usam a URL
#     com token apenas em memoria; o remote origin fica limpo
#   - FETCH UNICO por execucao; opcao de envio so depois do
#     Baixar terminar bem
#   - .gitignore gravado SEM BOM
#   - identidade git local configurada automaticamente se faltar
#   - NUNCA usa --force
#
# Uso: powershell -ExecutionPolicy Bypass -File .\sincronizar_github.ps1
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

$ErrorActionPreference = "Continue"

$script:Repo = "https://github.com/junior700/openalgo-b3-adapter.git"

# token pessoal (arquivo local, NUNCA versionado): usado so na memoria
$TokenFile = Join-Path $PSScriptRoot "token_github.txt"
$script:Token = ""
if (Test-Path $TokenFile) {
    $script:Token = (Get-Content $TokenFile -First 1).Trim()
}

function Url-Com-Token([string]$url) {
    if ($script:Token) { return "https://$($script:Token)@github.com/junior700/openalgo-b3-adapter.git" }
    return $url
}

function Garantir-Identidade {
    if (-not (git config user.name))  { git config user.name  "junior700" }
    if (-not (git config user.email)) { git config user.email "hrdfjmaris@gmail.com" }
}

Write-Host "========================================"
Write-Host "  Sincronizar com GitHub"
Write-Host "  openalgo-b3-adapter"
Write-Host "========================================"
Write-Host ""
Write-Host "  1) Baixar novidades do GitHub"
Write-Host "  2) Enviar commits para o GitHub"
Write-Host "  3) Baixar e depois enviar"
Write-Host "  0) Sair"
Write-Host ""
$op = Read-Host "Opcao"

Garantir-Identidade

switch ($op) {
    "1" {
        git fetch (Url-Com-Token $script:Repo) main
        if ($LASTEXITCODE -eq 0) {
            # fetch so BAIXA os commits; o merge --ff-only e quem aplica no projeto.
            git merge --ff-only FETCH_HEAD
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Novidades do GitHub aplicadas no projeto." -ForegroundColor Green
            } else {
                Write-Host "Nao foi possivel avancar automaticamente (historicos divergentes)." -ForegroundColor Yellow
                Write-Host "No cmd, na pasta do projeto, rode: git pull --no-rebase" -ForegroundColor Yellow
                Write-Host "Se pedir mensagem de commit, aceite o texto sugerido e salve." -ForegroundColor Yellow
            }
        } else { Write-Host "Fetch falhou." -ForegroundColor Red }
    }
    "2" {
        git add -A
        if (-not (git diff --cached --quiet)) {
            $msg = Read-Host "Mensagem de commit"
            if (-not $msg) { $msg = "chore: sincronizacao automatica" }
            git commit -m $msg
        } else { Write-Host "Nada a commitar." }
        git push (Url-Com-Token $script:Repo) main --tags
    }
    "3" {
        git fetch (Url-Com-Token $script:Repo) main
        if ($LASTEXITCODE -eq 0) {
            # aplicar as novidades ANTES de enviar (evita push reprovado por divergencia)
            git merge --ff-only FETCH_HEAD
            git add -A
            if (-not (git diff --cached --quiet)) {
                $msg = Read-Host "Mensagem de commit"
                if (-not $msg) { $msg = "chore: sincronizacao automatica" }
                git commit -m $msg
            }
            git push (Url-Com-Token $script:Repo) main --tags
        } else { Write-Host "Fetch falhou; envio cancelado." }
    }
    default { Write-Host "Saindo." }
}
Write-Host ""
Read-Host "Enter para fechar"
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
Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $DirVer "patch_v024_2026-09-27_2203.ps1") -Force

# --- 6. registro ---
$linha = "$Ver;2026-09-27 22:03;sincronizar_github.ps1;sincronizar: opcao 1 e 3 agora APLICAM as novidades (merge --ff-only) - fetch so baixava e o projeto ficava travado em versao velha`n"
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
