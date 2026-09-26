# ============================================================
# patch.ps1 - aplicador automatico de correcoes
# Projeto: openalgo-b3-adapter
# Versao:  v003_2026-09-26_1938  |  Arquivos: 3
# Descricao: serie real de opcoes B3 via opcoes.net.br no contrato mestre
#
# COMO USAR (na raiz da instalacao replicada):
#   powershell -ExecutionPolicy Bypass -File .\patch_v003_2026-09-26_1938.ps1
#
# O QUE ELE FAZ (nesta ordem):
#   0. recusa re-aplicacao (patches\registro.csv) e pede confirmacao
#   1. cria a pasta patches\v003_2026-09-26_1938\
#   2. backup dos arquivos ATUAIS em v003_2026-09-26_1938\anteriores\
#      (arquivo novo = inclusao, sem backup)
#   3. grava os arquivos corrigidos nos lugares devidos
#      (UTF-8 sem BOM; cria subpastas se faltar)
#   4. guarda copia versionada dos novos em v003_2026-09-26_1938\
#   5. guarda copia versionada DE SI MESMO em v003_2026-09-26_1938\
#   6. anexa uma linha no patches\registro.csv
#   7. mostra o resumo, espera ENTER e SE AUTODESTRUI
#
# RASTREIO: patches\registro.csv guarda versao, data, arquivos e
# resultado. ROLLBACK MANUAL: copie de v003_2026-09-26_1938\anteriores\.
#
# REGRAS DO PROJETO: pausa antes de qualquer saida, confirmacao
# antes de tocar em qualquer arquivo, token nunca gravado.
# ============================================================

$ErrorActionPreference = "Stop"
$Raiz = $PSScriptRoot
if (-not $Raiz) { $Raiz = (Get-Location).Path }

$Ver  = "v003_2026-09-26_1938"
$Desc = "serie real de opcoes B3 via opcoes.net.br no contrato mestre"

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

    "openalgo_b3_adapter\market_data\opcoesnet_chain.py" = @'
"""Serie real de opcoes de acoes B3 via matrizes publicas do opcoes.net.br.

Portado do projeto OpenAlgoBR-PRO (data_sources/opcoesnet.py) para o adapter.

- Duas requisicoes por subjacente (matriz CALL + matriz PUT), sem scraping
  individual por contrato por padrao.
- Qualquer falha (rede, parse, timeout) degrada para serie vazia: o contrato
  mestre continua com as sementes ilustrativas, nunca quebra o startup.
- Formato do vencimento normalizado para ISO (YYYY-MM-DD), como o restante
  do contrato mestre.

Roadmap: referenciais oficiais B3 substituem esta fonte quando disponiveis
(livros com MIDIA/lotes por faixa de premio exigem arquivo oficial).
"""

from __future__ import annotations

import re
from datetime import date, datetime
from typing import Any, Dict, List, Optional

import requests

BASE_URL = "https://opcoes.net.br"
TIMEOUT = 20

_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "Chrome/124 Safari/537.36"
    ),
    "Accept-Language": "pt-BR,pt;q=0.9,en;q=0.8",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
}

# lot padrao de opcoes de acoes B3 (lote oficial varia por faixa de premio)
DEFAULT_OPTION_LOT = 100


def _symbol(value: str) -> str:
    return re.sub(r"[^A-Z0-9]", "", str(value or "").upper())


def _parse_expiration(text: str) -> Optional[str]:
    """Extrai a primeira data dd/mm/aaaa e devolve ISO, ou None."""
    match = re.search(r"\b(\d{2})/(\d{2})/(\d{4})\b", text)
    if not match:
        return None
    d, m, y = match.groups()
    return f"{y}-{m}-{d}"


def _matrix_tickers(html: str, underlying: str) -> List[str]:
    """Tickers de opcao contidos no HTML da matriz, sem duplicar."""
    code_pattern = re.compile(rf"\b{re.escape(underlying[:4])}[A-Z][A-Z0-9]{{1,7}}\b")
    return list(dict.fromkeys(code_pattern.findall(html.upper())))


def _fetch_matrix_html(underlying: str, side: str) -> Optional[str]:
    """Baixa a matriz de um lado (CALL/PUT). None em falha."""
    url = f"{BASE_URL}/matriz-opcoes-strike-x-vencimento/{side}s/{underlying}"
    try:
        response = requests.get(url, headers=_HEADERS, timeout=TIMEOUT)
        response.raise_for_status()
        return response.text
    except Exception:  # noqa: BLE001 — offline e uma condicao normal aqui
        return None


def fetch_option_chain(underlying: str) -> List[Dict[str, Any]]:
    """Serie completa de opcoes (CALL+PUT) de um subjacente B3.

    Retorna lista de dicts:
        brsymbol, underlying, option_type (CALL/PUT), strike (float|None),
        expiry (ISO|None), lotsize.
    Serie vazia se a fonte estiver indisponivel ou o subjacente for invalido.
    """
    base = _symbol(underlying)
    if not re.fullmatch(r"[A-Z]{4}\d{1,2}", base):
        return []
    rows: List[Dict[str, Any]] = []
    seen = set()
    for side in ("CALL", "PUT"):
        html = _fetch_matrix_html(base, side)
        if not html:
            continue
        expiry = _parse_expiration(re.sub(r"<[^>]+>", " ", html))
        for ticker in _matrix_tickers(html, base):
            if ticker in seen or ticker == base:
                continue
            seen.add(ticker)
            rows.append({
                "brsymbol": ticker,
                "underlying": base,
                "option_type": side,
                "strike": None,
                "expiry": expiry,
                "lotsize": DEFAULT_OPTION_LOT,
            })
    return rows
'@

    "tests\test_opcoesnet_chain.py" = @'
"""Testes da carga de series reais de opcoes (opcoes.net.br)."""

from openalgo_b3_adapter.market_data import opcoesnet_chain as oc

_MATRIZ_HTML = """
<html><body>
  <h1>Matriz de opcoes - CALL - PETR4</h1>
  <p>Vencimento: 02/10/2026</p>
  <table>
    <tr><td>PETRA331</td><td>PETRA332</td></tr>
    <tr><td>PETRD421</td><td>PETR4</td></tr>
    <tr><td>petra331</td></tr>
  </table>
</body></html>
"""


def test_parse_expiration_iso():
    assert oc._parse_expiration("Vencimento 17/12/2026 ok") == "2026-12-17"
    assert oc._parse_expiration("sem data") is None


def test_matrix_tickers_dedup_e_case():
    tickers = oc._matrix_tickers(_MATRIZ_HTML, "PETR4")
    assert tickers == ["PETRA331", "PETRA332", "PETRD421"]


def test_fetch_chain_offline_retorna_vazio(monkeypatch):
    monkeypatch.setattr(oc, "_fetch_matrix_html", lambda u, s: None)
    assert oc.fetch_option_chain("PETR4") == []


def test_fetch_chain_consome_fonte(monkeypatch):
    chamadas = []

    def fake_fetch(underlying, side):
        chamadas.append((underlying, side))
        return _MATRIZ_HTML if side == "CALL" else None

    monkeypatch.setattr(oc, "_fetch_matrix_html", fake_fetch)
    rows = oc.fetch_option_chain("petr4")
    assert ({"PETR4", "CALL"}) in [set(c) for c in [chamadas[0]]]
    assert [r["brsymbol"] for r in rows] == ["PETRA331", "PETRA332", "PETRD421"]
    assert rows[0]["expiry"] == "2026-10-02"
    assert rows[0]["option_type"] == "CALL"
    assert rows[0]["lotsize"] == 100
    assert rows[0]["underlying"] == "PETR4"


def test_fetch_chain_subjacente_invalido(monkeypatch):
    monkeypatch.setattr(oc, "_fetch_matrix_html", lambda u, s: _MATRIZ_HTML)
    assert oc.fetch_option_chain("PET") == []
    assert oc.fetch_option_chain("PETRA") == []
'@

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
        B3_OPTION_UNDERLYINGS="PETR4,VALE3"  (padrao)
        B3_OPTION_CHAIN=0 desativa a carga.
    """
    if os.getenv("B3_OPTION_CHAIN", "1") != "1":
        return []
    underlyings = [
        u.strip().upper()
        for u in os.getenv("B3_OPTION_UNDERLYINGS", "PETR4,VALE3").split(",")
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
Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $DirVer "patch_v003_2026-09-26_1938.ps1") -Force

# --- 6. registro ---
$linha = "$Ver;2026-09-26 19:38;openalgo_b3_adapter\market_data\opcoesnet_chain.py|tests\test_opcoesnet_chain.py|openalgo_plugin\broker\b3\database\master_contract_db.py;serie real de opcoes B3 via opcoes.net.br no contrato mestre`n"
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
