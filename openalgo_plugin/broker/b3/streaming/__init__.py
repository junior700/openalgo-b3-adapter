"""Streaming do plugin B3: adapter no-op para o websocket_proxy do core.

O sandbox/fracionario nao tem feed ao vivo (a licenca B3 Market Data e
necessaria para book/ticks em tempo real). Sem este modulo, o
websocket_proxy/broker_factory.py do core levanta ModuleNotFoundError e
"Unsupported broker: b3" a cada tentativa de subscribe da GUI. O adapter
no-op registra a assinatura e responde sucesso sem publicar ticks, com
capacidades honestas: nenhum modo suportado por enquanto.
"""
