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
