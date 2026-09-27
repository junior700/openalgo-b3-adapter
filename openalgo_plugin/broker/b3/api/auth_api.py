"""Autenticacao do plugin B3.

O fluxo generico do OpenAlgo chama authenticate_broker(code) no callback
/broker/b3 com o `code` digitado na tela de credenciais.

Modo sandbox (padrao): qualquer entrada gera um token de sessao
deterministico, registrado no SandboxGateway. Corretoras reais devem
validar a credencial na API da corretora e devolver o token de sessao.
"""
import os

from openalgo_b3_adapter.order_execution import get_gateway

from utils.logging import get_logger

logger = get_logger(__name__)


def authenticate_broker(code, password=None, totp_code=None):
    """Valida credencial e devolve (auth_token, error_message).

    No modo sandbox a credencial e irrelevante: a GUI do OpenAlgo conecta
    sem digitar nada (o botao "Connect Account" navega para /b3/callback
    sem parametros), entao ausencia de code auto-autentica como "sandbox".
    """
    code = (code or "").strip()

    try:
        gateway = get_gateway()
    except NotImplementedError as exc:
        return None, str(exc)
    except ValueError as exc:
        return None, str(exc)

    if getattr(gateway, "name", "") == "sandbox":
        if not code:
            code = "sandbox"
        token = f"SANDBOX::{code}"
        try:
            gateway.ensure_auth(token)
        except AttributeError:
            pass
        logger.info("B3 plugin: sessao sandbox autenticada")
        return token, None

    # Gateways reais (nuinvest/btg): o token de sessao e a propria credencial
    # validada pela corretora. Ate os gateways concretos serem implementados,
    # get_gateway() ja levanta NotImplementedError quando nao ha credenciais.
    if not code:
        return None, "Informe a credencial da corretora (campo API KEY)"
    return code, None
