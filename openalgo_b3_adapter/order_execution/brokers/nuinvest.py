"""Gateway NuInvest (stub honesto).

A NuInvest mantinha a OpenAPI publica em https://openapi.nuinvest.com.br
(endpoints no padrao /gateway/... com autenticacao Bearer). O dominio publico
nao responde mais e o acesso hoje e mediante onboarding com o Nu. Quando voce
obtiver credenciais, implemente os metodos abaixo seguindo o contrato
`B3OrderGateway`; a estrutura do payload B3 ja esta pronta em `OrderRequest`.

Referencias uteis: docs.openalgo.in (modelo de plugin), repositorios da
comunidade que integravam a OpenAPI NuInvest (busque "openapi nuinvest
gateway execute" no GitHub).
"""
from __future__ import annotations

from typing import Any, Dict, List

from openalgo_b3_adapter.config.b3_config import get_config
from openalgo_b3_adapter.order_execution.b3_orders import B3OrderGateway
from openalgo_b3_adapter.order_execution.b3_validation import OrderRequest

_NOT_IMPLEMENTED = (
    "Gateway NuInvest ainda nao implementado: a OpenAPI NuInvest exige "
    "onboarding/credenciais junto ao Nu. Implemente os metodos desta classe "
    "conforme docs/BROKERS-BR.md, ou use B3_BROKER_GATEWAY=sandbox para dev/testes."
)


class NuInvestGateway(B3OrderGateway):
    name = "nuinvest"

    def __init__(self):
        cfg = get_config()
        if not cfg.nuinvest_bearer_token:
            raise NotImplementedError(_NOT_IMPLEMENTED)
        self.base_url = cfg.nuinvest_base_url
        self.bearer = cfg.nuinvest_bearer_token

    def place_order(self, req: OrderRequest, auth: str) -> Dict[str, Any]:
        # TODO: POST {base_url}/gateway/execute (padrao OpenAPI NuInvest)
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
