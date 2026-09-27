# ============================================================
# iniciar_b3.ps1 (v1) - INICIADOR DA PLATAFORMA TRADER B3
#
# Um script so para o mer... para TODO MUNDO:
#   [1] instala a plataforma OpenAlgo completa (interface
#       grafica, tipo Profit) + nosso plugin B3 + corretora
#       fantasma - tudo sozinho
#   [2] INICIAR a plataforma: sobe o servidor e abre o
#       navegador ja no painel grafico
#   [3] atualizar tudo (OpenAlgo + plugin B3)
#   [4] aplicar patch de correcao (estrategia desktop)
#   [5] diagnostico rapido (o que falta?)
#   [6] testar adaptador (roda os 71 testes)
#
# COMO USAR: dois cliques em iniciar_b3.bat (na raiz do
# projeto replicado) ou:
#   powershell -ExecutionPolicy Bypass -File .\iniciar_b3.ps1
#
# PRIMEIRA VEZ? escolha [1] e depois [2]. Nao precisa de mais
# nada: no navegador, crie sua conta em /setup, va em
# Dashboard -> Brokers, escolha "B3 Brasil" (modo sandbox),
# gere sua API key e comece a operar na corretora fantasma.
#
# REGRAS DO PROJETO: ASCII puro, pausa antes de qualquer
# saida, confirmacao antes de instalar/tocar em arquivos,
# token so em memoria.
# ============================================================

$ErrorActionPreference = "Continue"
$Raiz = $PSScriptRoot
if (-not $Raiz) { $Raiz = (Get-Location).Path }
Set-Location $Raiz

$OpenAlgo = Join-Path $Raiz "openalgo"
$PluginB3 = Join-Path $OpenAlgo "broker\b3"

function Pausa { Read-Host "Pressione ENTER para voltar ao menu" | Out-Null }
function Confere-Comando($nome) {
    return [bool](Get-Command $nome -ErrorAction SilentlyContinue)
}

function Menu-Principal {
    Clear-Host
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   OPENALGO B3 - PLATAFORMA TRADER" -ForegroundColor Cyan
    Write-Host "   (interface grafica + corretora fantasma)"
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host " Raiz: $Raiz"
    $ok = (Test-Path $PluginB3)
    if ($ok) {
        Write-Host " Status: instalado (opcao [2] para iniciar)" -ForegroundColor Green
    } else {
        Write-Host " Status: NAO instalado (opcao [1] para instalar)" -ForegroundColor Yellow
    }
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [1] Instalar tudo (primeira vez)"
    Write-Host "  [2] INICIAR plataforma (servidor + navegador)"
    Write-Host "  [3] Sincronizar com GitHub (baixar + enviar)"
    Write-Host "  [4] Aplicar patch de correcao"
    Write-Host "  [5] Diagnostico (o que falta?)"
    Write-Host "  [6] Testar adaptador (71 testes)"
    Write-Host "  [0] Sair"
    Write-Host ""
}

# ------------------------------------------------------------
# [1] INSTALAR TUDO
# ------------------------------------------------------------
function Instalar-Tudo {
    Write-Host ""
    Write-Host "--- Instalacao completa ---" -ForegroundColor Cyan
    Write-Host "Vou instalar: OpenAlgo (plataforma grafica), plugin B3,"
    Write-Host "corretora fantasma e dependencias."
    Write-Host "Requisitos: git, Python 3.12+, Node.js (npm)."
    Write-Host ""

    # --- git ---
    if (-not (Confere-Comando "git")) {
        Write-Host "ERRO: git nao encontrado. Instale https://git-scm.com" -ForegroundColor Red
        return
    }

    # --- python 3.12+ ---
    $pyOk = $false
    foreach ($cmd in @("python", "py")) {
        if (Confere-Comando $cmd) {
            $v = & $cmd --version 2>$null
            if ($v -match "Python (3\.(\d+))") {
                $minor = [int]$Matches[2]
                if ($minor -ge 12) { $script:Python = $cmd; $pyOk = $true; break }
            }
        }
    }
    if (-not $pyOk) {
        Write-Host "ERRO: Python 3.12+ nao encontrado. Instale https://python.org" -ForegroundColor Red
        return
    }
    Write-Host "OK: Python ($Python, $v)"

    # --- confirmacao antes de instalar ---
    $r = Read-Host "Prosseguir com a instalacao? [S/N]"
    if ($r -ne "S" -and $r -ne "s") { Write-Host "Cancelado."; return }

    # --- 1. OpenAlgo ---
    if (Test-Path (Join-Path $OpenAlgo "app.py")) {
        Write-Host "OpenAlgo ja existe aqui - pulando o clone."
    } else {
        Write-Host "[1/6] Baixando a plataforma OpenAlgo..."
        git clone --depth 1 https://github.com/marketcalls/openalgo
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERRO no clone. Verifique a internet e rode de novo." -ForegroundColor Red
            return
        }
    }

    # --- 2. dependencias Python do OpenAlgo ---
    Write-Host "[2/6] Instalando dependencias Python da plataforma..."
    Push-Location $OpenAlgo
    & $Python -m pip install --quiet -r requirements.txt
    Pop-Location

    # --- 3. CSS (Node opcional: repo ja traz compilado) ---
    if (Confere-Comando "npm") {
        Write-Host "[3/6] Compilando CSS da interface (npm)..."
        Push-Location $OpenAlgo
        npm install --silent 2>$null
        npm run build 2>$null
        Pop-Location
    } else {
        Write-Host "[3/6] npm nao achado - usando o CSS que ja vem no repo."
    }

    # --- 4. adaptador B3 ---
    Write-Host "[4/6] Instalando o adaptador B3 (openalgo-b3-adapter)..."
    & $Python -m pip install --quiet -e $Raiz

    # --- 5. plugin dentro do OpenAlgo ---
    Write-Host "[5/6] Encaixando o plugin B3 Brasil na plataforma..."
    $dest = Join-Path $OpenAlgo "broker"
    if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Force -Path $dest | Out-Null }
    if (Test-Path $PluginB3) { Remove-Item -Recurse -Force $PluginB3 }
    Copy-Item -Recurse (Join-Path $Raiz "openalgo_plugin\broker\b3") $PluginB3

    # --- 6. .env com corretora fantasma ---
    Write-Host "[6/6] Configurando a corretora fantasma (.env)..."
    $envFile = Join-Path $OpenAlgo ".env"
    if (-not (Test-Path $envFile)) {
        $sample = Join-Path $OpenAlgo ".sample.env"
        if (Test-Path $sample) { Copy-Item $sample $envFile }
        else { New-Item -ItemType File -Path $envFile | Out-Null }
    }
    Add-Content $envFile ""

    # evita duplicar as linhas se rodar 2x
    $atual = Get-Content $envFile -ErrorAction SilentlyContinue
    if (-not ($atual -match "^B3_BROKER_GATEWAY=")) {
        Add-Content $envFile "B3_BROKER_GATEWAY=sandbox"
    }
    if (-not ($atual -match "^B3_SANDBOX_STATE_FILE=")) {
        Add-Content $envFile "B3_SANDBOX_STATE_FILE=ghost_state.json"
    }
    if (-not ($atual -match "^B3_SANDBOX_LIVE_FILLS=")) {
        Add-Content $envFile "B3_SANDBOX_LIVE_FILLS=1"
    }
    if (-not ($atual -match "^B3_SANDBOX_AUTO_TICK=")) {
        Add-Content $envFile "B3_SANDBOX_AUTO_TICK=30"
    }
    if (-not ($atual -match "^B3_SANDBOX_INITIAL_CASH=")) {
        Add-Content $envFile "B3_SANDBOX_INITIAL_CASH=100000"
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host " INSTALACAO CONCLUIDA" -ForegroundColor Green
    Write-Host " Proximo passo: opcao [2] para iniciar a"
    Write-Host " plataforma. No navegador:"
    Write-Host "   1. crie sua conta em /setup"
    Write-Host "   2. Dashboard -> Brokers -> B3 Brasil (sandbox)"
    Write-Host "   3. gere sua API key e opere na fantasma"
    Write-Host "========================================" -ForegroundColor Green
}

# ------------------------------------------------------------
# [2] INICIAR PLATAFORMA
# ------------------------------------------------------------
function Iniciar-Plataforma {
    Write-Host ""
    if (-not (Test-Path $PluginB3)) {
        Write-Host "Ainda nao esta instalado. Rode a opcao [1] primeiro." -ForegroundColor Yellow
        return
    }
    Write-Host "Subindo o servidor da plataforma..." -ForegroundColor Cyan
    Write-Host "(janela do servidor abre ao lado; nao feche ela)"
    Write-Host ""

    Push-Location $OpenAlgo
    Start-Process $Python -ArgumentList "app.py" -WorkingDirectory $OpenAlgo
    Pop-Location

    Start-Sleep -Seconds 5
    Write-Host "Abrindo o navegador..."
    $setup = Join-Path $OpenAlgo "database\openalgo.db"
    if (Test-Path $setup) {
        Start-Process "http://127.0.0.1:5000"
    } else {
        Start-Process "http://127.0.0.1:5000/setup"
    }
    Write-Host ""
    Write-Host "Plataforma no ar: http://127.0.0.1:5000"
    Write-Host "Para encerrar, feche a janela do servidor."
}

# ------------------------------------------------------------
# [3] SINCRONIZAR COM GITHUB (baixar + enviar) - unico lugar para
# isso no projeto. Absorve o que antes estava espalhado em
# publicar_github.bat + sincronizar_github.ps1 (removidos: eram
# 3 scripts de git soltos na raiz, causando confusao/bagunca).
# replicar_github.ps1/.bat continua existindo APENAS para o
# primeiro clone numa pasta vazia (antes deste script existir ali).
# ------------------------------------------------------------
function Garantir-Identidade-Git {
    if (-not (git config user.name))  { git config user.name  "junior700" }
    if (-not (git config user.email)) { git config user.email "hrdfjmaris@gmail.com" }
}

function Url-Adapter-Com-Token {
    $limpo = "https://github.com/junior700/openalgo-b3-adapter.git"
    $tokenFile = Join-Path $Raiz "token_github.txt"
    if (Test-Path $tokenFile) {
        $tok = (Get-Content $tokenFile -First 1).Trim()
        if ($tok) { return "https://$tok@github.com/junior700/openalgo-b3-adapter.git" }
    }
    return $limpo
}

function Sincronizar-Github {
    Write-Host ""
    Write-Host "--- Sincronizar com GitHub ---" -ForegroundColor Cyan
    if (-not (Test-Path (Join-Path $Raiz ".git"))) {
        Write-Host "Esta pasta ainda nao e um clone do GitHub." -ForegroundColor Yellow
        Write-Host "Use replicar_github.ps1 (primeira vez, pasta vazia) e rode de novo." -ForegroundColor Yellow
        return
    }
    Garantir-Identidade-Git
    $UrlRepo = Url-Adapter-Com-Token

    Write-Host "[1/2] Baixando novidades do GitHub..."
    git fetch $UrlRepo main
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Fetch falhou (rede/token). Sincronizacao cancelada." -ForegroundColor Red
        return
    }
    git merge --ff-only FETCH_HEAD
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Ha mudancas locais nao commitadas que impedem avancar direto." -ForegroundColor Yellow
        $r = Read-Host "Guardar mudancas locais num backup (git stash) e continuar? [S/N]"
        if ($r -eq "S" -or $r -eq "s") {
            $carimbo = Get-Date -Format "yyyy-MM-dd_HHmm"
            git stash push --include-untracked -m "auto-backup antes do sync $carimbo"
            git merge --ff-only FETCH_HEAD
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Novidades aplicadas. Backup guardado (veja com: git stash list)." -ForegroundColor Green
            } else {
                Write-Host "Ainda nao foi possivel avancar. Rode 'git status' e resolva manualmente." -ForegroundColor Red
                return
            }
        } else {
            Write-Host "Sincronizacao cancelada." -ForegroundColor Yellow
            return
        }
    } else {
        Write-Host "Novidades do GitHub aplicadas no adaptador." -ForegroundColor Green
    }

    # --- OpenAlgo (core, upstream puro - zero modificacao local) ---
    if (Test-Path (Join-Path $OpenAlgo ".git")) {
        Write-Host "Atualizando a plataforma OpenAlgo (core)..."
        Push-Location $OpenAlgo
        git pull
        Pop-Location
    }
    # --- plugin refresh ---
    if (Test-Path (Join-Path $Raiz "openalgo_plugin\broker\b3")) {
        Write-Host "Re-encaixando o plugin B3..."
        if (Test-Path $PluginB3) { Remove-Item -Recurse -Force $PluginB3 }
        Copy-Item -Recurse (Join-Path $Raiz "openalgo_plugin\broker\b3") $PluginB3
    }

    Write-Host ""
    $r2 = Read-Host "[2/2] Enviar suas mudancas locais para o GitHub agora? [S/N]"
    if ($r2 -eq "S" -or $r2 -eq "s") {
        git add -A
        git diff --cached --quiet
        if ($LASTEXITCODE -ne 0) {
            $msg = Read-Host "Mensagem de commit"
            if (-not $msg) { $msg = "chore: sincronizacao automatica" }
            git commit -m $msg
        } else {
            Write-Host "Nada a commitar." -ForegroundColor DarkGray
        }
        git push $UrlRepo main --tags
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Enviado com sucesso para o GitHub." -ForegroundColor Green
        } else {
            Write-Host "ERRO no push. Verifique token_github.txt e a rede." -ForegroundColor Red
        }
    }
    Write-Host ""
    Write-Host "Sincronizacao concluida." -ForegroundColor Green
}

# ------------------------------------------------------------
# [4] APLICAR PATCH
# ------------------------------------------------------------
function Aplicar-Patch {
    Write-Host ""
    Write-Host "Procurando patches na raiz..."
    $patch = Get-ChildItem -Path $Raiz -Filter "patch_v*.ps1" -File -ErrorAction SilentlyContinue |
             Sort-Object Name | Select-Object -Last 1
    if ($patch) {
        Write-Host "Patch encontrado: $($patch.Name)"
        & powershell -ExecutionPolicy Bypass -File $patch.FullName
    } else {
        Write-Host "Nenhum patch_v*.ps1 solto na raiz." -ForegroundColor Yellow
        Write-Host "Patches versionados ficam em .\patches\vNNN_... - copie o"
        Write-Host ".ps1 desejado para a raiz e rode esta opcao de novo."
    }
}

# ------------------------------------------------------------
# [5] DIAGNOSTICO
# ------------------------------------------------------------
function Diagnostico {
    Write-Host ""
    Write-Host "--- Diagnostico ---" -ForegroundColor Cyan
    $itens = @(
        @{ n = "git";       ok = (Confere-Comando "git") },
        @{ n = "python";   ok = (Confere-Comando "python") },
        @{ n = "npm";      ok = (Confere-Comando "npm") },
        @{ n = "repo adapter (raiz e clone?)"; ok = (Test-Path (Join-Path $Raiz ".git")) },
        @{ n = "OpenAlgo baixado"; ok = (Test-Path (Join-Path $OpenAlgo "app.py")) },
        @{ n = "Plugin B3 encaixado"; ok = (Test-Path $PluginB3) },
        @{ n = ".env da plataforma"; ok = (Test-Path (Join-Path $OpenAlgo ".env")) }
    )
    foreach ($i in $itens) {
        if ($i.ok) { Write-Host "  [OK]      $($i.n)" -ForegroundColor Green }
        else       { Write-Host "  [FALTA]   $($i.n)" -ForegroundColor Yellow }
    }
    Write-Host ""
    Write-Host "Faltando algo? A opcao [1] resolve quase tudo."
}

# ------------------------------------------------------------
# [6] TESTAR ADAPTADOR
# ------------------------------------------------------------
function Testar-Adaptador {
    Write-Host ""
    Write-Host "Rodando a suíte de testes do adaptador..." -ForegroundColor Cyan
    & $Python -m pytest tests -q --no-header 2>$null
    Write-Host ""
}

# ------------------------------------------------------------
# Laco do menu
# ------------------------------------------------------------
$Python = "python"
while ($true) {
    Menu-Principal
    $op = Read-Host "Escolha uma opcao"
    switch ($op) {
        "1" { Instalar-Tudo; Pausa }
        "2" { Iniciar-Plataforma; Pausa }
        "3" { Sincronizar-Github; Pausa }
        "4" { Aplicar-Patch; Pausa }
        "5" { Diagnostico; Pausa }
        "6" { Testar-Adaptador; Pausa }
        "0" { exit 0 }
        default { Write-Host "Opcao invalida."; Start-Sleep -Seconds 1 }
    }
}
