"""Stubs das dependÃªncias do core OpenAlgo para importar o plugin standalone."""
import logging
import sys
import types


def _ensure_module(name):
    if name in sys.modules:
        return sys.modules[name]
    mod = types.ModuleType(name)
    sys.modules[name] = mod
    return mod


# --- utils.logging (openalgo) ---
utils_mod = _ensure_module("utils")
logging_mod = _ensure_module("utils.logging")
logging_mod.get_logger = lambda name=None: logging.getLogger(name or "test")
utils_mod.logging = logging_mod
if not hasattr(utils_mod, "__path__"):
    utils_mod.__path__ = []  # marca como pacote para submodulos

# --- database.token_db (openalgo) ---
database_mod = _ensure_module("database")
token_db = _ensure_module("database.token_db")
_FAKE_MAP = {
    # (oa_symbol, exchange) -> br_symbol
    ("PETR4", "NSE"): "PETR4",
    ("VALE3", "NSE"): "VALE3",
    ("PETR4F", "NSE"): "PETR4F",
    ("WINJ26", "MCX"): "WINJ26",
    ("PETR4-2026-06-19-35.00-C", "NFO"): "PETRA331",
}
token_db.get_br_symbol = lambda symbol, exchange: _FAKE_MAP.get((symbol, exchange))
token_db.get_oa_symbol = lambda br_symbol, exchange: br_symbol
token_db.get_token = lambda symbol, exchange: _FAKE_MAP.get((symbol, exchange))
database_mod.token_db = token_db
if not hasattr(database_mod, "__path__"):
    database_mod.__path__ = []


# --- isolacao da corretora fantasma -------------------------------------
# O SandboxGateway agora persiste por padrao em ~/.b3_adapter/sandbox_state.json.
# Cada teste recebe um arquivo de estado proprio para nao vazar estado entre
# testes nem para o ambiente real do usuario.
try:
    import pytest

    @pytest.fixture(autouse=True)
    def _b3_isolated_sandbox_state(monkeypatch, tmp_path):
        monkeypatch.setenv(
            "B3_SANDBOX_STATE_FILE", str(tmp_path / "b3_sandbox_state.json")
        )
except ImportError:  # pragma: no cover â€” ambiente sem pytest (stubs standalone)
    pass