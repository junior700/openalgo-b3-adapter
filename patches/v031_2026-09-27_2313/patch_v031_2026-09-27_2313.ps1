# ============================================================
# patch.ps1 - aplicador automatico de correcoes
# Projeto: openalgo-b3-adapter
# Versao:  v031_2026-09-27_2313  |  Arquivos: 1
# Descricao: Amplia B3_OPTION_UNDERLYINGS para o set completo do backtest (PETR4,VALE3,ITUB4,BBDC4,BBAS3,ABEV3): opcoes reais carregam para todos os 6 papeis
#
# COMO USAR (na raiz da instalacao replicada):
#   powershell -ExecutionPolicy Bypass -File .\patch_v031_2026-09-27_2313.ps1
#
# O QUE ELE FAZ (nesta ordem):
#   0. recusa re-aplicacao (patches\registro.csv) e pede confirmacao
#   1. cria a pasta patches\v031_2026-09-27_2313\
#   2. backup dos arquivos ATUAIS em v031_2026-09-27_2313\anteriores\
#      (arquivo novo = inclusao, sem backup)
#   3. grava os arquivos corrigidos nos lugares devidos
#      (UTF-8 sem BOM; cria subpastas se faltar)
#   4. guarda copia versionada dos novos em v031_2026-09-27_2313\
#   5. guarda copia versionada DE SI MESMO em v031_2026-09-27_2313\
#   6. anexa uma linha no patches\registro.csv
#   7. mostra o resumo, espera ENTER e SE AUTODESTRUI
#
# RASTREIO: patches\registro.csv guarda versao, data, arquivos e
# resultado. ROLLBACK MANUAL: copie de v031_2026-09-27_2313\anteriores\.
#
# REGRAS DO PROJETO: pausa antes de qualquer saida, confirmacao
# antes de tocar em qualquer arquivo, token nunca gravado.
# ============================================================

$ErrorActionPreference = "Stop"
$Raiz = $PSScriptRoot
if (-not $Raiz) { $Raiz = (Get-Location).Path }

$Ver  = "v031_2026-09-27_2313"
$Desc = "Amplia B3_OPTION_UNDERLYINGS para o set completo do backtest (PETR4,VALE3,ITUB4,BBDC4,BBAS3,ABEV3): opcoes reais carregam para todos os 6 papeis"

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

    "openalgo_plugin\broker\b3\database\master_contract_db.py" = @'
"""Master contract B3: popula a tabela symtoken do OpenAlgo.

Fontes:
  1. Semente offline (openalgo_b3_adapter.market_data.b3_seed) — sempre disponivel,
     cobre os papeis/futuros mais liquidos.
  2. Brapi (opcional): lista completa de tickers quando BRAPI_API_KEY esta
     definida (best-effort; falha silenciosa cai na semente).

Simbolos no espaco OpenAlgo:
  - a vista/futuros/indices: idênticos ao código B3 (PETR4, WINJ26, IBOV)
  - opcoes: notacao estruturada (BASE-YYYY-MM-DD-STRIKE-C/P) com brsymbol
    = código oficial da B3 (ex.: PETRA331)
Exchanges gravadas: codigos genericos aceitos pelo core (NSE/NFO/MCX/NSE_INDEX)
com brexchange B3/B3OPT/B3FUT — veja docs/INSTALL.md (modo zero-mod).
"""
import os

import pandas as pd
from sqlalchemy import Column, Float, Index, Integer, Sequence, String
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import scoped_session, sessionmaker

from database.engine_factory import create_db_engine
from openalgo_b3_adapter.config.b3_config import (
    OA_EXCHANGE_SEGMENT_MAP, SEGMENT_BREXCHANGE,
)
from openalgo_b3_adapter.market_data.b3_seed import SEED_INSTRUMENTS, SEED_OPTION_EXAMPLES
from openalgo_b3_adapter.market_data.opcoesnet_chain import fetch_option_chain

try:
    from extensions import socketio
except ImportError:
    socketio = None

DATABASE_URL = os.getenv("DATABASE_URL")
engine = create_db_engine(DATABASE_URL)
db_session = scoped_session(sessionmaker(autocommit=False, autoflush=False, bind=engine))
Base = declarative_base()
Base.query = db_session.query_property()

_SEGMENT_TO_OA_EXCHANGE = {v: k for k, v in OA_EXCHANGE_SEGMENT_MAP.items()}


class SymToken(Base):
    __tablename__ = "symtoken"
    id = Column(Integer, Sequence("symtoken_id_seq"), primary_key=True)
    symbol = Column(String, nullable=False, index=True)
    brsymbol = Column(String, nullable=False, index=True)
    name = Column(String)
    exchange = Column(String, index=True)
    brexchange = Column(String, index=True)
    token = Column(String, index=True)
    expiry = Column(String)
    strike = Column(Float)
    lotsize = Column(Integer)
    instrumenttype = Column(String)
    tick_size = Column(Float)
    contract_value = Column(Float)
    __table_args__ = (Index("idx_symbol_exchange", "symbol", "exchange"),)


def init_db():
    db_path = os.path.dirname(DATABASE_URL.replace("sqlite:///", "")) if DATABASE_URL else None
    if db_path and not os.path.exists(db_path):
        os.makedirs(db_path)
    Base.metadata.create_all(bind=engine)


def delete_symtoken_table():
    try:
        SymToken.__table__.drop(bind=engine)
        db_session.commit()
    except Exception:
        db_session.rollback()


def copy_from_dataframe(df):
    if df is None or df.empty:
        return 0
    engine_exec = db_session.get_bind()
    df.to_sql("symtoken", engine_exec, if_exists="append", index=False)
    db_session.commit()
    return len(df)


def _seed_rows():
    rows = []
    for symbol, name, kind, lot, tick, segment in SEED_INSTRUMENTS:
        rows.append({
            "symbol": symbol, "brsymbol": symbol, "name": name,
            "exchange": _SEGMENT_TO_OA_EXCHANGE.get(segment, "NSE"),
            "brexchange": SEGMENT_BREXCHANGE.get(segment, "B3"),
            "token": symbol, "expiry": "", "strike": 0.0,
            "lotsize": lot, "instrumenttype": kind, "tick_size": tick,
        })
    # opcoes ilustrativas (produção: download oficial da série vigente)
    for oa_symbol, br_symbol, base, lot, tick in SEED_OPTION_EXAMPLES:
        parts = oa_symbol.split("-")
        rows.append({
            "symbol": oa_symbol, "brsymbol": br_symbol, "name": f"Opcao {base}",
            "exchange": "NFO", "brexchange": "B3OPT", "token": br_symbol,
            "expiry": parts[1], "strike": float(parts[2]),
            "lotsize": lot, "instrumenttype": "OPTSTK", "tick_size": tick,
        })
    # mercado fracionario dos papeis a vista mais liquidos
    for symbol, name, kind, lot, tick, segment in SEED_INSTRUMENTS:
        if segment == "equity" and kind in ("equity", "fii", "etf"):
            rows.append({
                "symbol": f"{symbol}F", "brsymbol": f"{symbol}F", "name": f"{name} (fracionario)",
                "exchange": "NSE", "brexchange": "B3F", "token": f"{symbol}F",
                "expiry": "", "strike": 0.0, "lotsize": 1,
                "instrumenttype": "fractional", "tick_size": tick,
            })
    return rows


def _opcoesnet_chain_rows(existing_symbols):
    """Opcoes reais (serie vigente) via matrizes publicas do opcoes.net.br.

    Falha de rede degrada para lista vazia — as sementes ilustrativas e a
    carga Brapi permanecem. Subjacentes configuraveis:
        B3_OPTION_UNDERLYINGS="PETR4,VALE3,ITUB4,BBDC4,BBAS3,ABEV3" (padrao)
        B3_OPTION_CHAIN=0 desativa a carga.
    """
    if os.getenv("B3_OPTION_CHAIN", "1") != "1":
        return []
    underlyings = [
        u.strip().upper()
        for u in os.getenv("B3_OPTION_UNDERLYINGS", "PETR4,VALE3,ITUB4,BBDC4,BBAS3,ABEV3").split(",")
        if u.strip()
    ]
    rows = []
    for underlying in underlyings:
        for opt in fetch_option_chain(underlying):
            brsymbol = opt["brsymbol"]
            if not brsymbol or brsymbol in existing_symbols:
                continue
            existing_symbols.add(brsymbol)
            rows.append({
                "symbol": brsymbol, "brsymbol": brsymbol,
                "name": f"Opcao {underlying} {opt['option_type']}",
                "exchange": "NFO", "brexchange": "B3OPT", "token": brsymbol,
                "expiry": opt.get("expiry") or "",
                "strike": float(opt["strike"]) if opt.get("strike") else 0.0,
                "lotsize": opt.get("lotsize", 100),
                "instrumenttype": "OPTSTK", "tick_size": 0.01,
            })
    return rows


def _brapi_ticker_rows():
    """Best-effort: lista de tickers da Brapi quando há chave."""
    import httpx

    from openalgo_b3_adapter.config.b3_config import get_config
    cfg = get_config()
    if not cfg.brapi_api_key:
        return []
    try:
        resp = httpx.get(
            f"{cfg.brapi_base_url}/api/v2/tickers",
            headers={"Authorization": f"Bearer {cfg.brapi_api_key}"},
            timeout=15,
        )
        resp.raise_for_status()
        payload = resp.json()
        tickers = payload.get("tickers") or payload.get("results") or []
        rows = []
        for t in tickers:
            if isinstance(t, dict):
                sym = (t.get("symbol") or t.get("ticker") or "").upper().strip()
            else:
                sym = str(t).upper().strip()
            if not sym or sym in {r["symbol"] for r in _seed_rows()}:
                continue
            kind, lot = ("fii", 10) if sym.endswith("11") else ("equity", 100)
            rows.append({
                "symbol": sym, "brsymbol": sym, "name": sym,
                "exchange": "NSE", "brexchange": "B3", "token": sym,
                "expiry": "", "strike": 0.0, "lotsize": lot,
                "instrumenttype": kind, "tick_size": 0.01,
            })
        return rows
    except Exception:
        return []


def master_contract_download():
    """Ponto de entrada chamado pelo core (async_master_contract_download)."""
    try:
        init_db()
        delete_symtoken_table()
    except Exception:
        db_session.rollback()
    # Recria a tabela com o esquema do core (id PK, indices) antes do to_sql,
    # que senao recriaria a tabela sem a coluna id e quebraria SymToken.query.
    Base.metadata.create_all(bind=engine)

    rows = _seed_rows()
    rows += _opcoesnet_chain_rows({r["symbol"] for r in rows})
    rows += _brapi_ticker_rows()
    df = pd.DataFrame(rows)
    count = copy_from_dataframe(df)

    if socketio:
        try:
            socketio.emit("master_contract_download_event", {"status": "success", "broker": "b3"})
        except Exception:
            pass
    return {"status": "success", "message": f"B3 master contract: {count} simbolos"}
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
Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $DirVer "patch_v031_2026-09-27_2313.ps1") -Force

# --- 6. registro ---
$linha = "$Ver;2026-09-27 23:13;openalgo_plugin\broker\b3\database\master_contract_db.py;Amplia B3_OPTION_UNDERLYINGS para o set completo do backtest (PETR4,VALE3,ITUB4,BBDC4,BBAS3,ABEV3): opcoes reais carregam para todos os 6 papeis`n"
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
