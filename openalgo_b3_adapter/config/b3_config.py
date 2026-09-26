"""Configurações centralizadas do adaptador B3.

Tudo é controlado por variáveis de ambiente, no mesmo espírito do OpenAlgo
(`.env`), para que o plugin não precise de nenhuma alteração no core.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import Dict, Tuple

# ---------------------------------------------------------------------------
# Mapeamento câmara OpenAlgo  ->  segmento B3
#
# O core do OpenAlgo valida `exchange` contra VALID_EXCHANGES (lista fixa de
# câmaras indianas em utils/constants.py). Para manter ZERO modificação no
# core, o plugin reutiliza códigos genéricos já aceitos e os interpreta como
# segmentos da B3. O modo "nativo" (B3, B3OPT, B3FUT) é opcional via patch.
# ---------------------------------------------------------------------------

# Códigos genéricos (modo padrão, zero-modificação)
OA_EXCHANGE_SEGMENT_MAP: Dict[str, str] = {
    "NSE": "equity",       # mercado à vista: ações, FIIs, ETFs, BDRs
    "NFO": "options",      # opções sobre ações e índices
    "MCX": "futures",      # futuros de índice, dólar, juros (WIN, WDO, DI...)
    "NSE_INDEX": "index",  # índices (IBOV, IFUL, ...)
}

# Códigos nativos (modo com patch opcional `patches/b3_native_exchanges.patch`)
OA_NATIVE_EXCHANGE_MAP: Dict[str, str] = {
    "B3": "equity",
    "B3OPT": "options",
    "B3FUT": "futures",
    "B3_INDEX": "index",
}

# Segmento -> exchange/brexchange gravados no master contract do plugin
SEGMENT_BREXCHANGE: Dict[str, str] = {
    "equity": "B3",
    "options": "B3OPT",
    "futures": "B3FUT",
    "index": "B3I",
}

# Gateway padrão quando nenhuma env B3_BROKER_GATEWAY é definida
DEFAULT_GATEWAY = "sandbox"

# Gateways conhecidos (sandbox vem incluído)
KNOWN_GATEWAYS = ("sandbox", "nuinvest", "btg")


def resolve_segment(exchange: str) -> str:
    """Converte um código de câmara OpenAlgo em segmento B3.

    Aceita tanto os códigos genéricos (modo zero-mod) quanto os nativos
    (modo com patch), então o plugin funciona nos dois modos.
    """
    exchange = (exchange or "").upper().strip()
    if exchange in OA_EXCHANGE_SEGMENT_MAP:
        return OA_EXCHANGE_SEGMENT_MAP[exchange]
    if exchange in OA_NATIVE_EXCHANGE_MAP:
        return OA_NATIVE_EXCHANGE_MAP[exchange]
    raise ValueError(
        f"Câmara '{exchange}' não mapeada para a B3. "
        f"Use: {sorted(set(OA_EXCHANGE_SEGMENT_MAP) | set(OA_NATIVE_EXCHANGE_MAP))}"
    )


# ---------------------------------------------------------------------------
# Sessões de negociação (horário de Brasília, America/Sao_Paulo)
#
# Valores de referência do mercado à vista e de derivativos da B3.
# Confira sempre o horário oficial vigente em b3.com.br; todos os valores
# são sobreponíveis por env vars (veja B3Config.sessions).
# ---------------------------------------------------------------------------

DEFAULT_SESSIONS: Dict[str, Dict[str, Tuple[str, str]]] = {
    # Mercadorias/horário padrão do segmento de ações (B3, horário de Brasília)
    "equity": {
        "pre_open": ("09:00", "10:00"),       # pré-abertura (leilão aleatório)
        "regular": ("10:00", "16:55"),        # pregão regular
        "closing_auction": ("16:55", "17:00"),  # leilão de fechamento
        "after_market": ("17:30", "18:00"),   # after-market eletrônico
    },
    # Derivativos: WIN/WDO/DI operam janela contínua mais ampla
    "futures": {
        "regular": ("09:00", "18:25"),
    },
    "options": {
        "regular": ("10:00", "17:00"),
    },
    "index": {},
}

# Env vars usadas para sobrepor janelas, ex.:
#   B3_SESSION_equity_regular = "10:00,16:55"
SESSION_ENV_PREFIX = "B3_SESSION_"


@dataclass
class B3Config:
    """Snapshot de configuração lido das variáveis de ambiente."""

    # Provedores de dados
    brapi_api_key: str = field(default_factory=lambda: os.getenv("BRAPI_API_KEY", ""))
    brapi_base_url: str = field(
        default_factory=lambda: os.getenv("BRAPI_BASE_URL", "https://brapi.dev")
    )
    hgbrasil_api_key: str = field(
        default_factory=lambda: os.getenv("HGBRASIL_API_KEY", "")
    )
    hgbrasil_base_url: str = field(
        default_factory=lambda: os.getenv("HGBRASIL_BASE_URL", "https://api.hgbrasil.com")
    )

    # Gateway de execução (sandbox | nuinvest | btg | ...)
    gateway: str = field(
        default_factory=lambda: os.getenv("B3_BROKER_GATEWAY", DEFAULT_GATEWAY).lower()
    )

    # TTL de cache de cotação (segundos). Plano gratuito da Brapi tem limite
    # de requisições; 30s é um bom equilíbrio para dashboards.
    quote_cache_ttl: float = field(
        default_factory=lambda: float(os.getenv("B3_QUOTE_CACHE_TTL", "30"))
    )

    # Se true, o sandbox aceita ordens fora do horário de pregão (útil em dev)
    sandbox_ignore_sessions: bool = field(
        default_factory=lambda: os.getenv("B3_SANDBOX_IGNORE_SESSIONS", "1") == "1"
    )

    # Credenciais de corretoras (usadas pelos gateways concretos)
    # Mantidas como env puro: o plugin nunca persiste segredos.
    nuinvest_base_url: str = field(
        default_factory=lambda: os.getenv(
            "NUINVEST_BASE_URL", "https://openapi.nuinvest.com.br"
        )
    )
    nuinvest_bearer_token: str = field(
        default_factory=lambda: os.getenv("NUINVEST_BEARER_TOKEN", "")
    )
    btg_base_url: str = field(
        default_factory=lambda: os.getenv("BTG_BASE_URL", "https://api.br.btg.com")
    )
    btg_client_id: str = field(default_factory=lambda: os.getenv("BTG_CLIENT_ID", ""))
    btg_client_secret: str = field(
        default_factory=lambda: os.getenv("BTG_CLIENT_SECRET", "")
    )

    def sessions(self, segment: str) -> Dict[str, Tuple[str, str]]:
        """Janelas de sessão do segmento, com overrides via env."""
        base = dict(DEFAULT_SESSIONS.get(segment, {}))
        env_key = f"{SESSION_ENV_PREFIX}{segment}_"
        for name in list(base.keys()):
            override = os.getenv(f"{env_key}{name}")
            if override and "," in override:
                start, end = override.split(",", 1)
                base[name] = (start.strip(), end.strip())
        return base


_config: B3Config | None = None


def get_config() -> B3Config:
    """Retorna a configuração global (lê env na primeira chamada)."""
    global _config
    if _config is None:
        _config = B3Config()
    return _config


def reset_config() -> None:
    """Força releitura das env vars (usado em testes)."""
    global _config
    _config = None
