# ============================================================
# patch.ps1 - aplicador automatico de correcoes
# Projeto: openalgo-b3-adapter
# Versao:  v022_2026-09-27_2149  |  Arquivos: 2
# Descricao: candle fantasma: cotacao com timeSec (tempo real do ultimo negocio) + injecao no bundle para o tick do polling + sonda do WebSocket 8765 pos-start
#
# COMO USAR (na raiz da instalacao replicada):
#   powershell -ExecutionPolicy Bypass -File .\patch_v022_2026-09-27_2149.ps1
#
# O QUE ELE FAZ (nesta ordem):
#   0. recusa re-aplicacao (patches\registro.csv) e pede confirmacao
#   1. cria a pasta patches\v022_2026-09-27_2149\
#   2. backup dos arquivos ATUAIS em v022_2026-09-27_2149\anteriores\
#      (arquivo novo = inclusao, sem backup)
#   3. grava os arquivos corrigidos nos lugares devidos
#      (UTF-8 sem BOM; cria subpastas se faltar)
#   4. guarda copia versionada dos novos em v022_2026-09-27_2149\
#   5. guarda copia versionada DE SI MESMO em v022_2026-09-27_2149\
#   6. anexa uma linha no patches\registro.csv
#   7. mostra o resumo, espera ENTER e SE AUTODESTRUI
#
# RASTREIO: patches\registro.csv guarda versao, data, arquivos e
# resultado. ROLLBACK MANUAL: copie de v022_2026-09-27_2149\anteriores\.
#
# REGRAS DO PROJETO: pausa antes de qualquer saida, confirmacao
# antes de tocar em qualquer arquivo, token nunca gravado.
# ============================================================

$ErrorActionPreference = "Stop"
$Raiz = $PSScriptRoot
if (-not $Raiz) { $Raiz = (Get-Location).Path }

$Ver  = "v022_2026-09-27_2149"
$Desc = "candle fantasma: cotacao com timeSec (tempo real do ultimo negocio) + injecao no bundle para o tick do polling + sonda do WebSocket 8765 pos-start"

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

# --- [2d] fuso horario do grafico: America/Sao_Paulo em vez do padrao indiano (idempotente) ---
# A biblioteca openalgo-charts usa Asia/Kolkata como padrao; o Brasil merece
# o fuso local. Procura o bundle que cria o grafico (opcao priceAxisWidth:78)
# em QUALQUER arquivo .js do dist, aceitando formatacao com ou sem espacos,
# e injeta a opcao `timezone` com fallback America/Sao_Paulo. A escolha
# manual nas configuracoes do grafico continua valendo (sobrescreve e persiste).
$fusoFeito = $false
$cand2d = Get-ChildItem -Path $distAssets -Filter "*.js" -ErrorAction SilentlyContinue |
    Where-Object { Select-String -Path $_.FullName -Pattern 'priceAxisWidth\s*:\s*78\s*,' -Quiet } |
    Sort-Object { $_.Name -notmatch '^(Trading|trading)' } | Select-Object -First 1
if ($cand2d) {
    $c2d = Get-Content $cand2d.FullName -Raw
    if ($c2d -match 'priceAxisWidth\s*:\s*78\s*,\s*timezone') {
        Write-Host "[2d] Fuso do grafico ja injetado ($($cand2d.Name))." -ForegroundColor DarkGray
        $fusoFeito = $true
    } else {
        Write-Host "[2d] Injetando fuso do navegador no bundle $($cand2d.Name)..."
        $re2d = [regex]'(priceAxisWidth\s*:\s*78)\s*,'
        $novo2d = $re2d.Replace($c2d, '${1},timezone:(Intl.DateTimeFormat().resolvedOptions().timeZone||`America/Sao_Paulo`),', 1)
        if ($novo2d -ne $c2d) {
            [System.IO.File]::WriteAllText($cand2d.FullName, $novo2d, (New-Object System.Text.UTF8Encoding($false)))
            Get-ChildItem -Path $distAssets -Filter ($cand2d.Name + ".*") -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ne $cand2d.Name } | Remove-Item -Force
            Write-Host "[2d] Grafico abrira no fuso do navegador (padrao America/Sao_Paulo)." -ForegroundColor Green
            $fusoFeito = $true
        } else {
            Write-Host "[2d] AVISO: padrao encontrado mas substituicao falhou em $($cand2d.Name)." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "[2d] AVISO: nenhum bundle do grafico encontrado em frontend\dist\assets." -ForegroundColor Yellow
    Write-Host ("      Arquivos .js: " + ((Get-ChildItem -Path $distAssets -Filter "*.js" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name) -join ", "))
}
if (-not $fusoFeito) {
    Write-Host "[2d] O grafico seguira no fuso indiano ate esta secao funcionar." -ForegroundColor Yellow
}

# --- [2e] candle fantasma: tick do polling usa o tempo real do negocio (idempotente) ---
# Com o WebSocket caido, o terminal recorre ao polling de cotacao (a cada 4s) e
# carimba cada tick com o RELOGIO DO NAVEGADOR. Em dia sem pregao isso fabrica
# um candle "de hoje" com o preco de sexta (o candle duplicado). O adapter B3
# agora envia o epoch do ultimo negocio (timeSec) na cotacao; esta injecao faz
# o terminal preferir esse tempo em vez do relogio local.
$tickFeito = $false
$cand2e = Get-ChildItem -Path $distAssets -Filter "*.js" -ErrorAction SilentlyContinue |
    Where-Object { Select-String -Path $_.FullName -Pattern 'ltp:[A-Za-z_$][\w$]*\.ltp,timeSec:' -Quiet } |
    Select-Object -First 1
if ($cand2e) {
    $c2e = Get-Content $cand2e.FullName -Raw
    if ($c2e -match 'ltp:[A-Za-z_$][\w$]*\.ltp,timeSec:\(') {
        Write-Host "[2e] Carimbo de tempo do tick ja injetado ($($cand2e.Name))." -ForegroundColor DarkGray
        $tickFeito = $true
    } else {
        Write-Host "[2e] Injetando preferencia pelo tempo real do negocio em $($cand2e.Name)..."
        $re2e = [regex]'(ltp:([A-Za-z_$][\w$]*)\.ltp,timeSec:)([A-Za-z_$][\w$]*)\(\)'
        $novo2e = $re2e.Replace($c2e, '${1}(${2}.timeSec||${3}())', 1)
        if ($novo2e -ne $c2e) {
            [System.IO.File]::WriteAllText($cand2e.FullName, $novo2e, (New-Object System.Text.UTF8Encoding($false)))
            Get-ChildItem -Path $distAssets -Filter ($cand2e.Name + ".*") -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ne $cand2e.Name } | Remove-Item -Force
            Write-Host "[2e] Tick do polling carimba o tempo real do negocio (fim do candle fantasma)." -ForegroundColor Green
            $tickFeito = $true
        } else {
            Write-Host "[2e] AVISO: padrao do tick encontrado mas substituicao falhou." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "[2e] AVISO: bundle do tick nao encontrado em frontend\dist\assets." -ForegroundColor Yellow
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

# --- [4b] porta 8765 precisa estar livre (WebSocket do SDK) ---
$ocup8765 = netstat -ano | Select-String ":8765\s+.*LISTENING"
if ($ocup8765) {
    $procIds = $ocup8765 | ForEach-Object { ($_.Line -split '\s+')[-1] } | Sort-Object -Unique
    Write-Host "[4b] ATENCAO: porta 8765 ja esta ocupada (outra janela do OpenAlgo aberta?)." -ForegroundColor Yellow
    foreach ($procId in $procIds) {
        try { $pr = Get-Process -Id $procId -ErrorAction Stop; Write-Host ("      PID {0} = {1}" -f $procId, $pr.ProcessName) } catch {}
    }
    $r = Read-Host "      Encerrar esse(s) processo(s) agora? [S/N]"
    if ($r -eq "S" -or $r -eq "s") {
        foreach ($procId in $procIds) { taskkill /PID $procId /F 2>$null | Out-Null }
        Start-Sleep -Seconds 2
        Write-Host "[4b] Processos encerrados; porta liberada." -ForegroundColor Green
    } else {
        Write-Host "[4b] Processos mantidos. Se a porta ainda estiver ocupada, o WebSocket nao sobe." -ForegroundColor DarkGray
    }
}

# --- [5/5] abre o navegador apos o servidor subir e sobe o servidor ---
Start-Process powershell -ArgumentList "-NoProfile -Command `"Start-Sleep -Seconds 18; Start-Process 'http://127.0.0.1:5000'`""
# --- [4c] sonda pos-start: o WebSocket precisa subir na porta 8765 ---
# Se a porta nao abrir, o terminal cai no polling de cotacao e volta o risco
# do candle fantasma; avisa em janela propria se isso acontecer.
Start-Process powershell -ArgumentList "-NoProfile -Command `"Start-Sleep -Seconds 25; if (-not (netstat -ano | Select-String ':8765\s+.*LISTENING')) { Write-Host 'ATENCAO: o WebSocket (porta 8765) NAO subiu.' -ForegroundColor Red; Write-Host 'Feche e rode iniciar_openalgo.ps1 de novo; se persistir, encerre o processo da porta 8765.' -ForegroundColor Yellow; Read-Host 'Fechar' }`""

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

    "openalgo_b3_adapter\market_data\b3_quotes.py" = @'
"""Provedores de cotações da B3 (Brapi + HG Brasil).

- BrapiQuoteProvider:    https://brapi.dev (gratuito; PETR4/VALE3/ITUB4/MGLU3 sem chave)
- HGBrasilQuoteProvider: https://hgbrasil.com (gratuito com key)
- CompositeQuoteProvider: fallback em cadeia com cache TTL.

Provedores recebem `fetch` injetável (httpx por padrão) -> testes offline.

Nota honesta: cotação intraday da Brapi é o último preço consolidado disponível
(atraso depende do plano), NÃO tick-a-tick. Tempo real real exige B3 WebFeed
(licença paga) — veja docs/BROKERS-BR.md.
"""
from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional

from openalgo_b3_adapter.config.b3_config import get_config
from openalgo_b3_adapter.utils.b3_instruments import classify_symbol, strip_fractional

__all__ = ["Quote", "QuoteProvider", "BrapiQuoteProvider",
           "HGBrasilQuoteProvider", "CompositeQuoteProvider", "to_openalgo_quote"]

Fetch = Callable[..., Any]


@dataclass
class Quote:
    symbol: str
    ltp: float = 0.0
    open: float = 0.0
    high: float = 0.0
    low: float = 0.0
    prev_close: float = 0.0
    bid: float = 0.0
    ask: float = 0.0
    volume: int = 0
    oi: int = 0
    tick_size: Optional[float] = None
    source: str = ""
    fetched_at: float = field(default_factory=time.time)
    # Epoch (segundos) do ULTIMO NEGOCIO segundo o provedor. Usado para
    # carimbar o candle em formacao com o tempo real do negocio, evitando
    # que o terminal crie um candle 'de hoje' com preco de sexta em dias
    # sem pregao (fallback do polling com o relogio do navegador).
    market_time: Optional[float] = None


def _norm_epoch(value) -> Optional[float]:
    """Normaliza epoch em segundos; aceita segundos ou milissegundos."""
    try:
        ts = float(value)
    except (TypeError, ValueError):
        return None
    if ts <= 0:
        return None
    if ts > 1e12:  # veio em milissegundos
        ts /= 1000.0
    return ts


_B3_TZ = None


def _b3_tz():
    """Fuso de Brasilia. Sem DST desde 2019, entao -03:00 fixo serve como
    fallback quando o tzdata nao esta disponivel (Windows)."""
    global _B3_TZ
    if _B3_TZ is None:
        try:
            from zoneinfo import ZoneInfo
            _B3_TZ = ZoneInfo("America/Sao_Paulo")
        except Exception:
            import datetime as _dt
            _B3_TZ = _dt.timezone(_dt.timedelta(hours=-3))
    return _B3_TZ


def _b3_session_stamp(now_epoch=None):
    """Epoch do fechamento do ultimo pregao util (16:50 BRT) quando o mercado
    esta FECHADO; None quando esta aberto (seg-sex, 10:00-16:59 BRT).

    Usado para carimbar o tick do polling com o tempo real do ultimo negocio:
    sem isso o terminal carimba com o relogio do navegador e cria um candle
    'de hoje' com o preco de sexta em dias sem pregao (candle fantasma).
    """
    import datetime as _dt
    tz = _b3_tz()
    now = _dt.datetime.fromtimestamp(now_epoch if now_epoch is not None else time.time(), tz)
    if now.weekday() < 5 and _dt.time(10, 0) <= now.time() < _dt.time(17, 0):
        return None  # pregao aberto: provedor/nowSec mandam
    d = now.date()
    if not (now.weekday() < 5 and now.time() >= _dt.time(17, 0)):
        d -= _dt.timedelta(days=1)
        while d.weekday() >= 5:
            d -= _dt.timedelta(days=1)
    return _dt.datetime.combine(d, _dt.time(16, 50), tzinfo=tz).timestamp()


def to_openalgo_quote(q: Quote) -> Dict[str, Any]:
    """Formato padronizado esperado pelo core do OpenAlgo (BrokerData.get_quotes)."""
    out = {
        "bid": float(q.bid), "ask": float(q.ask), "open": float(q.open),
        "high": float(q.high), "low": float(q.low), "ltp": float(q.ltp),
        "prev_close": float(q.prev_close), "volume": int(q.volume),
        "oi": int(q.oi),
        "tick_size": q.tick_size if q.tick_size is not None else 0.01,
    }
    # Epoch do ultimo negocio: o terminal em queda de WebSocket usa isso
    # para carimbar o candle em formacao (injecao v022 no bundle). Com o
    # mercado fechado, carimba o fechamento do ultimo pregao util em vez do
    # 'agora' do navegador, evitando o candle fantasma em dias sem pregao.
    stamp = _b3_session_stamp()
    if stamp is None:
        stamp = q.market_time
    if stamp:
        out["timeSec"] = int(stamp)
    return out


def _default_fetch() -> Fetch:
    import httpx

    def fetch(url: str, headers: Dict[str, str] = None, params: Dict[str, Any] = None):
        with httpx.Client(timeout=10) as client:
            resp = client.get(url, headers=headers or {}, params=params or {})
            resp.raise_for_status()
            return resp.json()

    return fetch


class QuoteProvider:
    name = "base"

    def __init__(self, fetch: Optional[Fetch] = None):
        self._fetch = fetch or _default_fetch()

    def get_quote(self, symbol: str) -> Quote:
        raise NotImplementedError

    def get_quotes(self, symbols: List[str]) -> Dict[str, Quote]:
        return {s: self.get_quote(s) for s in symbols}


class BrapiQuoteProvider(QuoteProvider):
    """GET /api/v2/stocks/quote?symbols=PETR4 | Authorization: Bearer $KEY"""
    name = "brapi"

    def get_quote(self, symbol: str) -> Quote:
        cfg = get_config()
        # Mercado fracionario (sufixo "F") compartilha o mesmo preco do lote
        # padrao; provedores externos (Brapi/HG) nao conhecem o ticker "F".
        query_symbol = strip_fractional(symbol)
        headers = {"Authorization": f"Bearer {cfg.brapi_api_key}"} if cfg.brapi_api_key else {}
        payload = self._fetch(f"{cfg.brapi_base_url}/api/v2/stocks/quote",
                              headers=headers, params={"symbols": query_symbol})
        results = payload.get("results") or []
        if not results:
            raise ValueError(f"Sem dados para '{symbol}' na Brapi")
        data = results[0].get("data", {})
        inst = classify_symbol(symbol)
        return Quote(
            symbol=symbol,
            ltp=float(data.get("regularMarketPrice", 0) or 0),
            open=float(data.get("regularMarketOpen", 0) or 0),
            high=float(data.get("regularMarketDayHigh", 0) or 0),
            low=float(data.get("regularMarketDayLow", 0) or 0),
            prev_close=float(data.get("regularMarketPreviousClose", 0) or 0),
            bid=float(data.get("regularMarketBidPrice", 0) or 0),
            ask=float(data.get("regularMarketAskPrice", 0) or 0),
            volume=int(data.get("regularMarketVolume", 0) or 0),
            tick_size=inst.tick_size, source=self.name,
            market_time=_norm_epoch(data.get("regularMarketTime") or data.get("updatedAt")),
        )


def _parse_hg_time(value) -> Optional[float]:
    """Converte data/hora da HG Brasil ('2026-09-26 16:30:01',
    '26/09/2026 16:30:01', '26/09/2026 16:30') em epoch."""
    if not value or not isinstance(value, str):
        return None
    import datetime as _dt
    for fmt in ("%Y-%m-%d %H:%M:%S", "%d/%m/%Y %H:%M:%S", "%d/%m/%Y %H:%M"):
        try:
            return _dt.datetime.strptime(value.strip(), fmt).timestamp()
        except ValueError:
            continue
    return None


class HGBrasilQuoteProvider(QuoteProvider):
    """GET /finance/stock?symbol=PETR4&key=KEY"""
    name = "hgbrasil"

    def get_quote(self, symbol: str) -> Quote:
        cfg = get_config()
        query_symbol = strip_fractional(symbol)
        payload = self._fetch(f"{cfg.hgbrasil_base_url}/finance/stock",
                              params={"symbol": query_symbol, "key": cfg.hgbrasil_api_key or "SUA-CHAVE"})
        results = (payload or {}).get("results") or {}
        data = results.get(query_symbol)
        if not data:
            raise ValueError(f"Sem dados para '{symbol}' na HG Brasil")
        inst = classify_symbol(symbol)
        return Quote(
            symbol=symbol,
            ltp=float(data.get("price", 0) or 0),
            open=float(data.get("open", 0) or 0),
            high=float(data.get("higher", 0) or 0),
            low=float(data.get("lower", 0) or 0),
            prev_close=float(data.get("close", 0) or 0),
            bid=float(data.get("bid", 0) or 0),
            ask=float(data.get("ask", 0) or 0),
            volume=int(float(data.get("volume", 0) or 0)),
            tick_size=inst.tick_size, source=self.name,
            market_time=_parse_hg_time(data.get("updated_at") or data.get("updatedAt")),
        )


class CompositeQuoteProvider(QuoteProvider):
    """Tenta provedores em ordem; primeiro que responde vence. Cache TTL por símbolo."""

    def __init__(self, providers: Optional[List[QuoteProvider]] = None,
                 fetch: Optional[Fetch] = None, ttl: Optional[float] = None):
        super().__init__(fetch=fetch)
        self.providers = providers or []
        self.ttl = ttl if ttl is not None else get_config().quote_cache_ttl
        self._cache: Dict[str, Quote] = {}

    def get_quote(self, symbol: str) -> Quote:
        now = time.time()
        cached = self._cache.get(symbol)
        if cached and (now - cached.fetched_at) < self.ttl:
            return cached
        errors = []
        for provider in self.providers:
            try:
                q = provider.get_quote(symbol)
                if q.ltp > 0:
                    self._cache[symbol] = q
                    return q
                errors.append(f"{provider.name}: preço zerado")
            except Exception as exc:  # noqa: BLE001 - fallback intencional
                errors.append(f"{provider.name}: {exc}")
        raise ValueError(f"Nenhum provedor retornou cotação para '{symbol}': {'; '.join(errors)}")
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
Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $DirVer "patch_v022_2026-09-27_2149.ps1") -Force

# --- 6. registro ---
$linha = "$Ver;2026-09-27 21:49;iniciar_openalgo.ps1|openalgo_b3_adapter\market_data\b3_quotes.py;candle fantasma: cotacao com timeSec (tempo real do ultimo negocio) + injecao no bundle para o tick do polling + sonda do WebSocket 8765 pos-start`n"
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
