"""Gateway BTG Pactual (stub honesto).

O BTG expoe APIs REST (api.br.btg.com) para clientes e parceiros com
onboarding formal (developer portal do BTG). Autenticacao via OAuth2
(client credentials) com assinatura. Os endpoints de execucao seguem o
padrao de "orders" do BTG Trade/API Empresas.

Implemente os metodos seguindo o contrato `B3OrderGateway` quando tiver
client_id/client_secret aprovados (env: BTG_CLIENT_ID, BTG_CLIENT_SECRET).
"""
from __future__ import annotations

from typing import Any, Dict, List

from openalgo_b3_adapter.config.b3_config import get_config
from openalgo_b3_adapter.order_execution.b3_orders import B3OrderGateway
from openalgo_b3_adapter.order_execution.b3_validation import OrderRequest

_NOT_IMPLEMENTED = (
    "Gateway BTG ainda nao implementado: a API BTG exige onboarding formal "
    "(client_id/secret aprovados). Implemente conforme docs/BROKERS-BR.md, "
    "ou use B3_BROKER_GATEWAY=sandbox para dev/testes."
)


class BTGGateway(B3OrderGateway):
    name = "btg"

    def __init__(self):
        cfg = get_config()
        if not (cfg.btg_client_id and cfg.btg_client_secret):
            raise NotImplementedError(_NOT_IMPLEMENTED)
        self.base_url = cfg.btg_base_url

    def place_order(self, req: OrderRequest, auth: str) -> Dict[str, Any]:
        raise NotImplementedError(_NOT_IMPLEMENTED)

    def cancel_order(self, order_id: str, auth: str) -> Dict[str, Any]:
        raise NotImplementedError(_NOT_IMPLEMENTED)

    def modify_order(self, order_id: str, req: OrderRequest, auth: str) -> Dict[str, Any]:
        raise NotImplementedError(_NOT_IMPLEMENTED)

    def get_orders(self, auth: str) -> List[Dict[str, Any]]:
        raise NotImplementedError(_NOT_IMPLEMENTED)

    def get_trades(self, auth: str) -> List[Dict[str, Any]]:
        raise NotImplementedError(_NOT_IMPLEMENTED)

    def get_positions(self, auth: str) -> List[Dict[str, Any]]:
        raise NotImplementedError(_NOT_IMPLEMENTED)

    def get_holdings(self, auth: str) -> List[Dict[str, Any]]:
        raise NotImplementedError(_NOT_IMPLEMENTED)

    def get_funds(self, auth: str) -> Dict[str, Any]:
        raise NotImplementedError(_NOT_IMPLEMENTED)
