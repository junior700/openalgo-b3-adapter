# ============================================================
# patch.ps1 - aplicador automatico de correcoes
# Projeto: openalgo-b3-adapter
# Versao:  v026_2026-09-27_2223  |  Arquivos: 3
# Descricao: PONTO DE ENTRADA UNICO: iniciar_b3.ps1 v2 funde o fluxo completo do iniciar_openalgo (espelho plugin, injecoes de fuso/candle/dropdown, venv, .env) nas opcoes [1]/[2]. Deleta iniciar_openalgo.ps1/.bat da maquina. So resta replicar_github (primeiro clone).
#
# COMO USAR (na raiz da instalacao replicada):
#   powershell -ExecutionPolicy Bypass -File .\patch_v026_2026-09-27_2223.ps1
#
# O QUE ELE FAZ (nesta ordem):
#   0. recusa re-aplicacao (patches\registro.csv) e pede confirmacao
#   1. cria a pasta patches\v026_2026-09-27_2223\
#   2. backup dos arquivos ATUAIS em v026_2026-09-27_2223\anteriores\
#      (arquivo novo = inclusao, sem backup)
#   3. grava os arquivos corrigidos nos lugares devidos
#      (UTF-8 sem BOM; cria subpastas se faltar)
#   4. guarda copia versionada dos novos em v026_2026-09-27_2223\
#   5. guarda copia versionada DE SI MESMO em v026_2026-09-27_2223\
#   6. anexa uma linha no patches\registro.csv
#   7. mostra o resumo, espera ENTER e SE AUTODESTRUI
#
# RASTREIO: patches\registro.csv guarda versao, data, arquivos e
# resultado. ROLLBACK MANUAL: copie de v026_2026-09-27_2223\anteriores\.
#
# REGRAS DO PROJETO: pausa antes de qualquer saida, confirmacao
# antes de tocar em qualquer arquivo, token nunca gravado.
# ============================================================

$ErrorActionPreference = "Stop"
$Raiz = $PSScriptRoot
if (-not $Raiz) { $Raiz = (Get-Location).Path }

$Ver  = "v026_2026-09-27_2223"
$Desc = "PONTO DE ENTRADA UNICO: iniciar_b3.ps1 v2 funde o fluxo completo do iniciar_openalgo (espelho plugin, injecoes de fuso/candle/dropdown, venv, .env) nas opcoes [1]/[2]. Deleta iniciar_openalgo.ps1/.bat da maquina. So resta replicar_github (primeiro clone)."

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

    "iniciar_b3.ps1" = @'
# ============================================================
# iniciar_b3.ps1 (v2) - PONTO DE ENTRADA UNICO do projeto
#
# Um arquivo so. Antes existiam iniciar_openalgo.ps1/.bat
# (iniciador) + iniciar_b3.ps1 (menu) + publicar_github.bat +
# sincronizar_github.ps1 (git) - quase a mesma coisa espalhada
# em quatro scripts. Agora TUDO vive aqui:
#
#   [1] Instalar   (primeira vez)
#   [2] INICIAR    (espelho plugin + injecoes frontend + servidor
#                   + navegador - sempre refaz a preparacao)
#   [3] Sincronizar com GitHub (baixar novidades + enviar mudancas)
#   [4] Aplicar patch de correcao
#   [5] Diagnostico
#   [6] Testar adaptador
#   [0] Sair
#
# Uso: dois cliques em iniciar_b3.bat, ou:
#   powershell -ExecutionPolicy Bypass -File .\iniciar_b3.ps1
#
# REGRAS DO PROJETO: zero modificacao no core do OpenAlgo
# (plugin espelhado + injecoes via script no bundle), token do
# GitHub so em memoria (token_github.txt), ASCII puro.
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

# ============================================================
# FUNCOES COMPARTILHADAS (usadas por [1] instalar e [2] iniciar)
# ============================================================

# --- acha o core do OpenAlgo (ou clona o oficial na 1a vez) ---
function Garantir-Core {
    if (Test-Path (Join-Path $OpenAlgo "app.py")) {
        $script:OA = (Resolve-Path -LiteralPath $OpenAlgo).Path
        return
    }
    if (-not (Confere-Comando "git")) {
        Write-Host "ERRO: git nao encontrado. Instale https://git-scm.com" -ForegroundColor Red
        return
    }
    Write-Host "Core do OpenAlgo ausente. Clonando o oficial do GitHub..."
    git clone --depth 1 https://github.com/marketcalls/openalgo $OpenAlgo
    if (-not (Test-Path (Join-Path $OpenAlgo "app.py"))) {
        Write-Host "ERRO no clone do OpenAlgo (internet?)." -ForegroundColor Red
        return
    }
    $script:OA = (Resolve-Path -LiteralPath $OpenAlgo).Path
}

# --- espelha plugin B3 + indicadores customizados (drop-in) ---
function Espelhar-Plugin {
    if (-not $script:OA) { return }
    $pluginSrc = Join-Path $Raiz "openalgo_plugin\broker\b3"
    $pluginDst = Join-Path $script:OA "broker\b3"
    if (Test-Path $pluginSrc) {
        if (-not (Test-Path $pluginDst)) { New-Item -ItemType Directory -Path $pluginDst -Force | Out-Null }
        Copy-Item -Path "$pluginSrc\*" -Destination $pluginDst -Recurse -Force
        Write-Host "Plugin B3 espelhado para o core."
    } else {
        Write-Host "AVISO: plugin nao encontrado em openalgo_plugin\broker\b3." -ForegroundColor Yellow
    }
    $indSrc = Join-Path $Raiz "openalgo_plugin\strategies\indicators"
    $indDst = Join-Path $script:OA "strategies\indicators"
    if (Test-Path $indSrc) {
        if (-not (Test-Path $indDst)) { New-Item -ItemType Directory -Path $indDst -Force | Out-Null }
        Copy-Item -Path "$indSrc\*" -Destination $indDst -Force
        Write-Host "Indicadores customizados espelhados (strategies\indicators)."
    }
}

# --- injetcoes idempotentes no bundle do frontend (2b/2d/2e) ---
function Injetar-Frontend {
    if (-not $script:OA) { return }
    $distAssets = Join-Path $script:OA "frontend\dist\assets"

    # [2b] B3 no dropdown de corretoras
    $bsFile = Get-ChildItem -Path $distAssets -Filter "BrokerSelect-*.js" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($bsFile -and -not (Select-String -Path $bsFile.FullName -Pattern 'id:`b3`' -Quiet)) {
        Write-Host "Injetando B3 no dropdown do frontend..."
        $c = Get-Content $bsFile.FullName -Raw
        $c = $c.Replace('zerodha`,name:`Zerodha`,authType:`oauth`}', 'zerodha`,name:`Zerodha`,authType:`oauth`},{id:`b3`,name:`B3 Brasil (Sandbox)`,authType:`totp`}')
        $c = $c.Replace('case`aliceblue`:case`angel`', 'case`b3`:case`aliceblue`:case`angel`')
        if ($c.Contains('id:`b3`')) {
            [System.IO.File]::WriteAllText($bsFile.FullName, $c, (New-Object System.Text.UTF8Encoding($false)))
            Get-ChildItem -Path $distAssets -Filter ($bsFile.Name + ".*") -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ne $bsFile.Name } | Remove-Item -Force
            Write-Host "Dropdown atualizado (B3 visivel na lista)."
        } else {
            Write-Host "AVISO: padrao do frontend nao reconhecido; dropdown nao alterado." -ForegroundColor Yellow
        }
    }

    # [2d] fuso horario do grafico: America/Sao_Paulo
    $cand2d = Get-ChildItem -Path $distAssets -Filter "*.js" -ErrorAction SilentlyContinue |
        Where-Object { Select-String -Path $_.FullName -Pattern 'priceAxisWidth\s*:\s*78\s*,' -Quiet } |
        Sort-Object { $_.Name -notmatch '^(Trading|trading)' } | Select-Object -First 1
    if ($cand2d) {
        $c2d = Get-Content $cand2d.FullName -Raw
        if ($c2d -match 'priceAxisWidth\s*:\s*78\s*,\s*timezone') {
            Write-Host "Fuso do grafico ja injetado." -ForegroundColor DarkGray
        } else {
            $re2d = [regex]'(priceAxisWidth\s*:\s*78)\s*,'
            $novo2d = $re2d.Replace($c2d, '${1},timezone:(Intl.DateTimeFormat().resolvedOptions().timeZone||`America/Sao_Paulo`),', 1)
            if ($novo2d -ne $c2d) {
                [System.IO.File]::WriteAllText($cand2d.FullName, $novo2d, (New-Object System.Text.UTF8Encoding($false)))
                Get-ChildItem -Path $distAssets -Filter ($cand2d.Name + ".*") -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -ne $cand2d.Name } | Remove-Item -Force
                Write-Host "Grafico abrira no fuso do navegador (padrao America/Sao_Paulo)." -ForegroundColor Green
            } else {
                Write-Host "AVISO: substituicao do fuso falhou em $($cand2d.Name)." -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "AVISO: nenhum bundle do grafico encontrado em frontend\dist\assets." -ForegroundColor Yellow
    }

    # [2e] candle fantasma: tick do polling usa o tempo real do negocio
    $cand2e = Get-ChildItem -Path $distAssets -Filter "*.js" -ErrorAction SilentlyContinue |
        Where-Object { Select-String -Path $_.FullName -Pattern 'ltp:[A-Za-z_$][\w$]*\.ltp,timeSec:' -Quiet } |
        Select-Object -First 1
    if ($cand2e) {
        $c2e = Get-Content $cand2e.FullName -Raw
        if ($c2e -match 'ltp:[A-Za-z_$][\w$]*\.ltp,timeSec:\(') {
            Write-Host "Carimbo de tempo do tick ja injetado." -ForegroundColor DarkGray
        } else {
            $re2e = [regex]'(ltp:([A-Za-z_$][\w$]*)\.ltp,timeSec:)([A-Za-z_$][\w$]*)\(\)'
            $novo2e = $re2e.Replace($c2e, '${1}(${2}.timeSec||${3}())', 1)
            if ($novo2e -ne $c2e) {
                [System.IO.File]::WriteAllText($cand2e.FullName, $novo2e, (New-Object System.Text.UTF8Encoding($false)))
                Get-ChildItem -Path $distAssets -Filter ($cand2e.Name + ".*") -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -ne $cand2e.Name } | Remove-Item -Force
                Write-Host "Tick do polling carimba o tempo real do negocio (fim do candle fantasma)." -ForegroundColor Green
            } else {
                Write-Host "AVISO: substituicao do tick falhou." -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "AVISO: bundle do tick nao encontrado em frontend\dist\assets." -ForegroundColor Yellow
    }
}

# --- ambiente virtual (.venv) com dependencias + adapter B3 ---
function Garantir-Venv {
    if (-not $script:OA) { return $false }
    $script:Py = Join-Path $script:OA ".venv\Scripts\python.exe"
    if (Test-Path $script:Py) {
        Write-Host "Ambiente virtual encontrado."
    } else {
        Write-Host "Criando ambiente virtual..."
        $corePy = Get-Command python -ErrorAction SilentlyContinue
        if (-not $corePy) { $corePy = Get-Command py -ErrorAction SilentlyContinue }
        if (-not $corePy) {
            Write-Host "ERRO: Python 3.12+ nao encontrado. Instale https://python.org" -ForegroundColor Red
            return $false
        }
        & $corePy.Source -m venv (Join-Path $script:OA ".venv")
        & $script:Py -m pip install --upgrade pip
        & $script:Py -m pip install -r (Join-Path $script:OA "requirements.txt")
    }
    & $script:Py -m pip install -e $Raiz --quiet --no-deps 2>$null
    Write-Host "Adapter B3 instalado no ambiente."
    return $true
}

# --- .env do OpenAlgo (padrao + plugin B3 corretora fantasma) ---
function Configurar-Env {
    if (-not $script:OA) { return }
    $envFile = Join-Path $script:OA ".env"
    $envSample = Join-Path $script:OA ".sample.env"
    $precisa = $true
    if (Test-Path $envFile) {
        $linhaVb = Select-String -Path $envFile -Pattern "VALID_BROKERS" | Select-Object -First 1
        if ($null -ne $linhaVb -and $linhaVb.Line.Contains(",b3")) { $precisa = $false }
    }
    if (-not $precisa) { return }
    if (-not (Test-Path $envSample)) {
        if (-not (Test-Path $envFile)) { New-Item -ItemType File -Path $envFile | Out-Null }
    }
    Write-Host "Gerando .env (padrao do OpenAlgo + plugin B3)..."
    $bytes = New-Object byte[] 32
    (New-Object System.Security.Cryptography.RNGCryptoServiceProvider).GetBytes($bytes)
    $appkey = ($bytes | ForEach-Object { $_.ToString("x2") }) -join ""
    (New-Object System.Security.Cryptography.RNGCryptoServiceProvider).GetBytes($bytes)
    $pepper = ($bytes | ForEach-Object { $_.ToString("x2") }) -join ""
    (New-Object System.Security.Cryptography.RNGCryptoServiceProvider).GetBytes($bytes)
    $salt = (($bytes | ForEach-Object { $_.ToString("x2") }) -join "").Substring(0, 32)
    if (Test-Path $envSample) {
        $final = @()
        foreach ($l in (Get-Content $envSample)) {
            if     ($l.StartsWith("VALID_BROKERS"))  { $l = $l.TrimEnd("'") + ",b3'" }
            elseif ($l.StartsWith("REDIRECT_URL"))   { $l = $l.Replace("<broker>", "b3") }
            elseif ($l.StartsWith("APP_KEY"))        { $l = "APP_KEY = '" + $appkey + "'" }
            elseif ($l.StartsWith("API_KEY_PEPPER")) { $l = "API_KEY_PEPPER = '" + $pepper + "'" }
            elseif ($l.StartsWith("FERNET_SALT"))     { $l = "FERNET_SALT = '" + $salt + "'" }
            $final += $l
        }
    } else {
        $final = @()
    }
    $final += ""
    $final += "# --- Plugin B3 Brasil (corretora fantasma) ---"
    $final += "B3_BROKER_GATEWAY=sandbox"
    $final += "B3_SANDBOX_STATE_FILE=ghost_state.json"
    $final += "B3_SANDBOX_LIVE_FILLS=1"
    $final += "B3_SANDBOX_AUTO_TICK=30"
    $final += "B3_SANDBOX_INITIAL_CASH=100000"
    [System.IO.File]::WriteAllLines($envFile, $final, (New-Object System.Text.ASCIIEncoding))
}

function Menu-Principal {
    Clear-Host
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   OPENALGO B3 - PLATAFORMA TRADER" -ForegroundColor Cyan
    Write-Host "   (interface grafica + corretora fantasma)"
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host " Raiz: $Raiz"
    if (Test-Path $PluginB3) {
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
    Write-Host "  [6] Testar adaptador"
    Write-Host "  [0] Sair"
    Write-Host ""
}

# ------------------------------------------------------------
# [1] INSTALAR TUDO (primeira vez)
# ------------------------------------------------------------
function Instalar-Tudo {
    Write-Host ""
    Write-Host "--- Instalacao completa ---" -ForegroundColor Cyan
    Write-Host "Vou instalar: OpenAlgo (plataforma grafica), plugin B3,"
    Write-Host "corretora fantasma e dependencias."
    Write-Host "Requisitos: git, Python 3.12+."
    Write-Host ""
    $r = Read-Host "Prosseguir com a instalacao? [S/N]"
    if ($r -ne "S" -and $r -ne "s") { Write-Host "Cancelado."; return }

    Garantir-Core
    if (-not $script:OA) { return }
    if (-not (Garantir-Venv)) { return }
    Espelhar-Plugin
    Configurar-Env

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
# [2] INICIAR PLATAFORMA (preparacao completa + servidor)
# ------------------------------------------------------------
function Iniciar-Plataforma {
    Write-Host ""
    Garantir-Core
    if (-not $script:OA) { return }
    Espelhar-Plugin
    Injetar-Frontend
    if (-not (Garantir-Venv)) { return }
    Configurar-Env

    # --- porta 8765 precisa estar livre (WebSocket do SDK) ---
    $ocup8765 = netstat -ano | Select-String ":8765\s+.*LISTENING"
    if ($ocup8765) {
        $procIds = $ocup8765 | ForEach-Object { ($_.Line -split '\s+')[-1] } | Sort-Object -Unique
        Write-Host "ATENCAO: porta 8765 ja esta ocupada (outra janela do OpenAlgo aberta?)." -ForegroundColor Yellow
        foreach ($procId in $procIds) {
            try { $pr = Get-Process -Id $procId -ErrorAction Stop; Write-Host ("      PID {0} = {1}" -f $procId, $pr.ProcessName) } catch {}
        }
        $r = Read-Host "      Encerrar esse(s) processo(s) agora? [S/N]"
        if ($r -eq "S" -or $r -eq "s") {
            foreach ($procId in $procIds) { taskkill /PID $procId /F 2>$null | Out-Null }
            Start-Sleep -Seconds 2
            Write-Host "Processos encerrados; porta liberada." -ForegroundColor Green
        } else {
            Write-Host "Processos mantidos. Se a porta ainda estiver ocupada, o WebSocket nao sobe." -ForegroundColor DarkGray
        }
    }

    # --- navegador abre sozinho; sonda do WebSocket apos 25s ---
    Start-Process powershell -ArgumentList "-NoProfile -Command `"Start-Sleep -Seconds 18; Start-Process 'http://127.0.0.1:5000'`""
    Start-Process powershell -ArgumentList "-NoProfile -Command `"Start-Sleep -Seconds 25; if (-not (netstat -ano | Select-String ':8765\s+.*LISTENING')) { Write-Host 'ATENCAO: o WebSocket (porta 8765) NAO subiu.' -ForegroundColor Red; Read-Host 'Fechar' }`""

    Write-Host ""
    Write-Host "Subindo o OpenAlgo... o navegador abre sozinho em instantes." -ForegroundColor Green
    Write-Host ""
    Write-Host "Login da GUI: admin / OpenAlgo@B3Demo2026"
    Write-Host "Ctrl+C aqui para parar o servidor (e voltar ao menu)."
    Write-Host ""
    Push-Location $script:OA
    try { & $script:Py app.py } finally { Pop-Location }
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
    Write-Host "Rodando a suite de testes do adaptador..." -ForegroundColor Cyan
    $pyTest = Join-Path $OpenAlgo ".venv\Scripts\python.exe"
    if (Test-Path $pyTest) { & $pyTest -m pytest tests -q --no-header 2>$null }
    else {
        $corePy = Get-Command python -ErrorAction SilentlyContinue
        if ($corePy) { & $corePy.Source -m pytest tests -q --no-header 2>$null }
        else { Write-Host "Python nao encontrado." -ForegroundColor Red }
    }
    Write-Host ""
}

# ------------------------------------------------------------
# Laco do menu
# ------------------------------------------------------------
$script:OA = $null
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
'@

    "iniciar_b3.bat" = @'
@echo off
REM dois cliques: PONTO DE ENTRADA UNICO (instalar, iniciar, sync GitHub, patch, diagnostico, testes)
powershell -ExecutionPolicy Bypass -File "%~dp0iniciar_b3.ps1"
'@

    "LEIA-ME.txt" = @'
OPENALGO + B3 (1 clique)
========================
1. Extraia TODO o conteudo deste zip na RAIZ do projeto
2. De dois cliques em: iniciar_b3.bat
3. Primeira vez: opcao [1] instalar, depois opcao [2] iniciar
   (sobe o servidor, ajusta o fuso do grafico p/ Brasil e abre
   o navegador em http://127.0.0.1:5000)
4. Na tela de conectividade, selecione "B3 Brasil (Sandbox)" e
   clique em Connect Account

TUDO se faz pelo iniciar_b3.bat:
  [1] instalar  [2] iniciar  [3] sincronizar GitHub (baixar+enviar)
  [4] aplicar patch  [5] diagnostico  [6] testes
Nao ha mais outros scripts de inicio/git na raiz; replicar_github
existe so para o primeiro clone numa pasta vazia.

IMPORTANTE: apos atualizar, faca um hard refresh no navegador
(Ctrl+Shift+R) para pegar o frontend novo.
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
Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $DirVer "patch_v026_2026-09-27_2223.ps1") -Force

# --- 6. registro ---
$linha = "$Ver;2026-09-27 22:23;iniciar_b3.ps1|iniciar_b3.bat|LEIA-ME.txt;PONTO DE ENTRADA UNICO: iniciar_b3.ps1 v2 funde o fluxo completo do iniciar_openalgo (espelho plugin, injecoes de fuso/candle/dropdown, venv, .env) nas opcoes [1]/[2]. Deleta iniciar_openalgo.ps1/.bat da maquina. So resta replicar_github (primeiro clone).`n"
[System.IO.File]::AppendAllText($Registro, $linha, $Utf8NoBom)

# --- 6b. remove scripts antigos absorvidos pelo iniciar_b3.ps1 v2 ---
$Removidos = @()
foreach ($obsoleto in @("iniciar_openalgo.ps1", "iniciar_openalgo.bat")) {
    $alvoObs = Join-Path $Raiz $obsoleto
    if (Test-Path $alvoObs) {
        $bkObs = Join-Path $DirAnt ($obsoleto -replace "[\\/]", "__")
        Copy-Item -LiteralPath $alvoObs -Destination $bkObs -Force
        Remove-Item -LiteralPath $alvoObs -Force
        $Removidos += $obsoleto
    }
}

# --- 7. resumo + autodestruicao ---
Write-Host ""
Write-Host "========================================"
Write-Host "Patch $Ver aplicado:"
foreach ($a in $Alterados) { Write-Host "  alterado : $a" }
foreach ($a in $Incluidos) { Write-Host "  incluido : $a" }
foreach ($a in $Removidos) { Write-Host "  removido : $a (absorvido pelo iniciar_b3.ps1 v2)" }
Write-Host "Backup (versao antiga): patches\$Ver\anteriores\"
Write-Host "Copias versionadas    : patches\$Ver\"
Write-Host "Registro atualizado   : patches\registro.csv"
Write-Host "========================================"
Read-Host "Pressione ENTER para concluir e remover o script"

Remove-Item -LiteralPath $PSCommandPath -Force
Write-Host "Script de patch removido (autodestruicao). Ate logo."
