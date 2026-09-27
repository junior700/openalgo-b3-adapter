# ============================================================
# patch.ps1 - aplicador automatico de correcoes
# Projeto: openalgo-b3-adapter
# Versao:  v017_2026-09-27_1227  |  Arquivos: 2
# Descricao: Indicador HILO Ativador: media das maximas/minimas X periodos, Y adiantado, HI vermelho e LO verde com trecho inativo tracejado; espelhamento [2c] de indicadores customizados
#
# COMO USAR (na raiz da instalacao replicada):
#   powershell -ExecutionPolicy Bypass -File .\patch_v017_2026-09-27_1227.ps1
#
# O QUE ELE FAZ (nesta ordem):
#   0. recusa re-aplicacao (patches\registro.csv) e pede confirmacao
#   1. cria a pasta patches\v017_2026-09-27_1227\
#   2. backup dos arquivos ATUAIS em v017_2026-09-27_1227\anteriores\
#      (arquivo novo = inclusao, sem backup)
#   3. grava os arquivos corrigidos nos lugares devidos
#      (UTF-8 sem BOM; cria subpastas se faltar)
#   4. guarda copia versionada dos novos em v017_2026-09-27_1227\
#   5. guarda copia versionada DE SI MESMO em v017_2026-09-27_1227\
#   6. anexa uma linha no patches\registro.csv
#   7. mostra o resumo, espera ENTER e SE AUTODESTRUI
#
# RASTREIO: patches\registro.csv guarda versao, data, arquivos e
# resultado. ROLLBACK MANUAL: copie de v017_2026-09-27_1227\anteriores\.
#
# REGRAS DO PROJETO: pausa antes de qualquer saida, confirmacao
# antes de tocar em qualquer arquivo, token nunca gravado.
# ============================================================

$ErrorActionPreference = "Stop"
$Raiz = $PSScriptRoot
if (-not $Raiz) { $Raiz = (Get-Location).Path }

$Ver  = "v017_2026-09-27_1227"
$Desc = "Indicador HILO Ativador: media das maximas/minimas X periodos, Y adiantado, HI vermelho e LO verde com trecho inativo tracejado; espelhamento [2c] de indicadores customizados"

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

    "openalgo_plugin\strategies\indicators\hilo_ativador.js" = @'
/**
 * HILO Ativador (mercado B3).
 *
 * Média móvel das máximas (HI, vermelho) e das mínimas (LO, verde) de X
 * períodos, deslocada Y períodos à frente (adiantada), desenhada como linha
 * contínua, sem escada.
 *
 * Regra do ativador: em alta, quando o fechamento cruza abaixo do LO o estado
 * vira baixa e o HI passa a ser o ativador (resistência); em baixa, quando o
 * fechamento cruza acima do HI o estado vira alta e o LO passa a ser o
 * ativador (suporte). No HILO clássico o lado inativo desaparece do gráfico;
 * aqui ele permanece visível TRACEJADO, então o trader vê a linha completa e
 * ainda sabe qual lado está ativo.
 *
 * Indicador customizado do gráfico do OpenAlgo: arquivo de usuário em
 * strategies/indicators, carregado em runtime sem qualquer modificação no core.
 */

export default function ({ registerIndicator, sourceValues, sma }) {
  registerIndicator({
    id: 'b3-hilo-ativador',
    name: 'HILO Ativador',
    category: 'Custom',
    placement: 'onchart',

    inputs: [
      {
        key: 'length',
        type: 'number',
        label: 'Períodos (X)',
        default: 10,
        min: 1,
        max: 400,
        step: 1,
        tooltip: 'Quantidade de períodos da média móvel das máximas (HI) e das mínimas (LO).',
      },
      {
        key: 'shift',
        type: 'number',
        label: 'Adiantamento (Y)',
        default: 1,
        min: 0,
        max: 100,
        step: 1,
        tooltip: 'Períodos adiantados: a linha na barra i é a média calculada até a barra i-Y. 0 = sem deslocamento.',
      },
    ],

    plots: [
      {
        key: 'hi',
        type: 'line',
        title: 'HI',
        style: { color: '#ef5350', lineWidth: 2 },
        tooltip: 'Média das máximas, ativa (ativador) quando o estado é baixa.',
      },
      {
        key: 'hiGhost',
        type: 'line',
        title: 'HI (inativo)',
        style: { color: '#ef5350', lineWidth: 1, lineStyle: 'dashed' },
        tooltip: 'Média das máximas no trecho que a regra do ativador esconderia.',
      },
      {
        key: 'lo',
        type: 'line',
        title: 'LO',
        style: { color: '#26a69a', lineWidth: 2 },
        tooltip: 'Média das mínimas, ativa (ativador) quando o estado é alta.',
      },
      {
        key: 'loGhost',
        type: 'line',
        title: 'LO (inativo)',
        style: { color: '#26a69a', lineWidth: 1, lineStyle: 'dashed' },
        tooltip: 'Média das mínimas no trecho que a regra do ativador esconderia.',
      },
    ],

    calc(bars, settings) {
      const n = bars.length
      const length = Math.max(1, Math.floor(Number(settings.length) || 10))
      const shift = Math.max(0, Math.floor(Number(settings.shift) ?? 1))

      const highs = sourceValues(bars, 'high')
      const lows = sourceValues(bars, 'low')
      const closes = sourceValues(bars, 'close')

      // Médias móveis simples das máximas e mínimas.
      const maHigh = sma(highs, length)
      const maLow = sma(lows, length)

      // Linha adiantada: o valor na barra i é a média calculada até i-Y.
      // Isso desloca a média Y barras à frente sem usar escada (step).
      const hi = new Array(n).fill(null)
      const lo = new Array(n).fill(null)
      for (let i = shift; i < n; i += 1) {
        hi[i] = maHigh[i - shift]
        lo[i] = maLow[i - shift]
      }

      // Estado do ativador: 'up' (LO ativo) / 'down' (HI ativo) / null antes do
      // primeiro gatilho. Histerese clássica do HILO: em alta só vira baixa se o
      // fechamento cair abaixo do LO; em baixa só vira alta se passar do HI.
      const state = new Array(n).fill(null)
      for (let i = 0; i < n; i += 1) {
        const prev = i > 0 ? state[i - 1] : null
        const h = hi[i]
        const l = lo[i]
        const c = closes[i]
        if (h == null || l == null || c == null) {
          state[i] = prev
          continue
        }
        if (prev === 'up') state[i] = c < l ? 'down' : 'up'
        else if (prev === 'down') state[i] = c > h ? 'up' : 'down'
        else if (c > h) state[i] = 'up'
        else if (c < l) state[i] = 'down'
        else state[i] = null
      }

      // Colunas sólida/tracejada por lado. O trecho ativo fica sólido; o
      // inativo, tracejado. Nas barras de transição o valor entra nas duas
      // colunas para os segmentos se conectarem e a linha parecer contínua.
      const hiSolid = new Array(n).fill(null)
      const hiGhost = new Array(n).fill(null)
      const loSolid = new Array(n).fill(null)
      const loGhost = new Array(n).fill(null)
      for (let i = 0; i < n; i += 1) {
        const s = state[i]
        const prev = i > 0 ? state[i - 1] : null
        if (hi[i] != null) {
          const solid = s === 'down' || (prev === 'down' && s !== 'down')
          if (solid) hiSolid[i] = hi[i]
          if (!solid || prev === 'down') hiGhost[i] = hi[i]
        }
        if (lo[i] != null) {
          const solid = s === 'up' || (prev === 'up' && s !== 'up')
          if (solid) loSolid[i] = lo[i]
          if (!solid || prev === 'up') loGhost[i] = lo[i]
        }
      }

      return { hi: hiSolid, hiGhost, lo: loSolid, loGhost }
    },
  })
}
'@

    "iniciar_openalgo.ps1" = @'
# ============================================================
#  iniciar_openalgo.ps1 - iniciador automatico do OpenAlgo + plugin B3
#  Uso: clique direito -> "Executar com PowerShell", ou no terminal:
#       powershell -ExecutionPolicy Bypass -File .\iniciar_openalgo.ps1
#  Faz tudo: localiza o core, espelha o plugin B3, prepara o
#  ambiente virtual, abre o navegador e sobe o servidor.
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

$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

# --- [1/5] localiza o core do OpenAlgo ---
$candidates = @(@(
    (Join-Path $PSScriptRoot "openalgo"),
    (Join-Path (Split-Path $PSScriptRoot -Parent) "openalgo"),
    $env:OPENALGO_HOME
) | Where-Object { $_ -and (Test-Path (Join-Path $_ "app.py")) })

if (-not $candidates) {
    # Auto-instalacao: clona o OpenAlgo oficial (zero modificacoes) na raiz
    Write-Host "[1/5] Core do OpenAlgo ausente. Clonando o oficial do GitHub..."
    $dest = Join-Path $PSScriptRoot "openalgo"
    git clone --depth 1 https://github.com/marketcalls/openalgo.git $dest
    if (Test-Path (Join-Path $dest "app.py")) {
        $OA = (Resolve-Path -LiteralPath $dest).Path
    } else {
        Write-Host "[ERRO] Clone do OpenAlgo falhou (git instalado? internet?)." -ForegroundColor Red
        Read-Host "Enter para sair"
        exit 1
    }
} else {
    $OA = (Resolve-Path -LiteralPath $candidates[0]).Path
}
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

# --- [2b] injeta a B3 no dropdown do frontend (idempotente) ---
$distAssets = Join-Path $OA "frontend\dist\assets"
$bsFile = Get-ChildItem -Path $distAssets -Filter "BrokerSelect-*.js" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($bsFile -and -not (Select-String -Path $bsFile.FullName -Pattern 'id:`b3`' -Quiet)) {
    Write-Host "[2b] Injetando B3 no dropdown do frontend..."
    $c = Get-Content $bsFile.FullName -Raw
    $c = $c.Replace('zerodha`,name:`Zerodha`,authType:`oauth`}', 'zerodha`,name:`Zerodha`,authType:`oauth`},{id:`b3`,name:`B3 Brasil (Sandbox)`,authType:`totp`}')
    $c = $c.Replace('case`aliceblue`:case`angel`', 'case`b3`:case`aliceblue`:case`angel`')
    if ($c.Contains('id:`b3`')) {
        [System.IO.File]::WriteAllText($bsFile.FullName, $c, (New-Object System.Text.UTF8Encoding($false)))
        Get-ChildItem -Path $distAssets -Filter ($bsFile.Name + ".*") -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne $bsFile.Name } | Remove-Item -Force
        Write-Host "[2b] Dropdown atualizado (B3 visivel na lista)."
    } else {
        Write-Host "[2b] AVISO: padrao do frontend nao reconhecido; dropdown nao alterado." -ForegroundColor Yellow
    }
}

# --- [2c] espelha indicadores customizados do grafico (drop-in) ---
$indSrc = Join-Path $PSScriptRoot "openalgo_plugin\strategies\indicators"
$indDst = Join-Path $OA "strategies\indicators"
if (Test-Path $indSrc) {
    if (-not (Test-Path $indDst)) { New-Item -ItemType Directory -Path $indDst -Force | Out-Null }
    Copy-Item -Path "$indSrc\*" -Destination $indDst -Force
    Write-Host "[2c] Indicadores customizados espelhados para o core (strategies\indicators)."
} else {
    Write-Host "[2c] Sem indicadores customizados para espelhar." -ForegroundColor DarkGray
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

# --- configura o .env do OpenAlgo (padrao + plugin B3) ---
$envFile = Join-Path $OA ".env"
$envSample = Join-Path $OA ".sample.env"
$precisa = $true
if (Test-Path $envFile) {
    $linhaVb = Select-String -Path $envFile -Pattern "VALID_BROKERS" | Select-Object -First 1
    if ($null -ne $linhaVb -and $linhaVb.Line.Contains(",b3")) { $precisa = $false }
}
if ($precisa -and (Test-Path $envSample)) {
    Write-Host "[4b] Gerando .env (padrao do OpenAlgo + plugin B3)..."
    $bytes = New-Object byte[] 32
    (New-Object System.Security.Cryptography.RNGCryptoServiceProvider).GetBytes($bytes)
    $appkey = ($bytes | ForEach-Object { $_.ToString("x2") }) -join ""
    (New-Object System.Security.Cryptography.RNGCryptoServiceProvider).GetBytes($bytes)
    $pepper = ($bytes | ForEach-Object { $_.ToString("x2") }) -join ""
    (New-Object System.Security.Cryptography.RNGCryptoServiceProvider).GetBytes($bytes)
    $salt = (($bytes | ForEach-Object { $_.ToString("x2") }) -join "").Substring(0, 32)

    $final = @()
    foreach ($l in (Get-Content $envSample)) {
        if     ($l.StartsWith("VALID_BROKERS"))  { $l = $l.TrimEnd("'") + ",b3'" }
        elseif ($l.StartsWith("REDIRECT_URL"))   { $l = $l.Replace("<broker>", "b3") }
        elseif ($l.StartsWith("APP_KEY"))        { $l = "APP_KEY = '" + $appkey + "'" }
        elseif ($l.StartsWith("API_KEY_PEPPER")) { $l = "API_KEY_PEPPER = '" + $pepper + "'" }
        elseif ($l.StartsWith("FERNET_SALT"))     { $l = "FERNET_SALT = '" + $salt + "'" }
        $final += $l
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
Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $DirVer "patch_v017_2026-09-27_1227.ps1") -Force

# --- 6. registro ---
$linha = "$Ver;2026-09-27 12:27;openalgo_plugin\strategies\indicators\hilo_ativador.js|iniciar_openalgo.ps1;Indicador HILO Ativador: media das maximas/minimas X periodos, Y adiantado, HI vermelho e LO verde com trecho inativo tracejado; espelhamento [2c] de indicadores customizados`n"
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
