"""Origem da API do plugin B3 (usada pelo keepalive do core).

Sandbox nao tem origem real; gateways concretos devem exportar BASE_URL.
"""

BASE_URL = os.getenv("B3_BROKER_BASE_URL", "")

import os  # noqa: E402  (mantido simples; BASE_URL lida antes por clareza)
