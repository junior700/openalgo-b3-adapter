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

    rows = _seed_rows()
    rows += _brapi_ticker_rows()
    df = pd.DataFrame(rows)
    count = copy_from_dataframe(df)

    if socketio:
        try:
            socketio.emit("master_contract_download_event", {"status": "success", "broker": "b3"})
        except Exception:
            pass
    return {"status": "success", "message": f"B3 master contract: {count} simbolos"}
