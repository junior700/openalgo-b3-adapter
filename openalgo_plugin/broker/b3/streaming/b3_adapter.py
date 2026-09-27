"""Adapter WebSocket no-op para o broker B3 (websocket_proxy do OpenAlgo).

O websocket_proxy do core resolve `broker.b3.streaming.b3_adapter.B3WebSocketAdapter`
dinamicamente (broker_factory._get_adapter_class). Sem feed ao vivo (licenca
B3 Market Data / plano pago de market data), este adapter:

  - aceita initialize/connect/subscribe/unsubscribe sem erro (a GUI nao
    quebra nem fica em loop de reconstrucao);
  - NAO publica ticks no barramento ZeroMQ (nada a publicar);
  - anuncia zero modos suportados (capabilities honestas), entao clientes
    capazes de ler a resposta sabem que nao havera stream.

Quando houver feed real, este modulo sera substituido pela implementacao
completa (resolucao de token via master contract + publicacao no ZMQ).
"""
from websocket_proxy.base_adapter import BaseBrokerWebSocketAdapter

from utils.logging import get_logger

logger = get_logger("b3_websocket")


class B3WebSocketAdapter(BaseBrokerWebSocketAdapter):
    """Adapter de streaming B3 sem feed real (sandbox/desenvolvimento)."""

    def __init__(self):
        super().__init__()
        self.broker_name = "b3"
        self.user_id = None
        self.running = False
        self._advertised = False

    # --- lifecycle ------------------------------------------------------

    def initialize(self, broker_name, user_id, auth_data=None):
        self.broker_name = broker_name or self.broker_name
        self.user_id = user_id
        if not self._advertised:
            logger.info(
                "B3 streaming: adapter no-op (sem feed ao vivo; "
                "requer licenca B3 Market Data). Subscribes aceitos sem ticks."
            )
            self._advertised = True
        return self._create_success_response(
            "B3 streaming inicializado (modo no-op, sem feed ao vivo)"
        )

    def connect(self):
        # connected=True evita que o proxy evite/reconstrua o adapter em loop
        # (server.py getattr(adapter, 'connected', ...)); nada conecta de fato.
        self.connected = True
        self.running = True
        return self._create_success_response("B3 streaming no-op conectado")

    def disconnect(self):
        self.connected = False
        self.running = False
        return self._create_success_response("B3 streaming desconectado")

    # --- subscriptions --------------------------------------------------

    def subscribe(self, symbol, exchange, mode=2, depth_level=5):
        return self._create_success_response(
            f"Subscribed {exchange}:{symbol} (B3 no-op: sem ticks ao vivo)",
            symbol=symbol,
            exchange=exchange,
            mode=mode,
            actual_depth=None,
        )

    def unsubscribe(self, symbol, exchange, mode=2):
        return self._create_success_response(
            f"Unsubscribed {exchange}:{symbol}",
            symbol=symbol,
            exchange=exchange,
            mode=mode,
        )
