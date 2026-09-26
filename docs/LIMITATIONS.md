# Limitações (leia antes de usar com dinheiro real)

## Execucao
- **Sandbox apenas.** Gateways de corretoras reais (nuinvest/btg) são stubs
  documentados; executam ordens reais SOMENTE apos implementacao + onboarding.
- Ordem fracionaria: o OpenAlgo trata quantidade como inteiro; fracionario B3
  usa o sufixo F (PETR4F) e o adapter aceita qualquer quantidade >= 1.
- SL/SL-M dependem da corretora manter ordem stop na B3 (stop nativo);
  sandbox simula o ciclo, sem monitoramento de disparo.

## Dados
- Cotações Brapi/HG sao consolidadas com atraso (plano gratuito);
  NAO usar para estrategias de alta frequencia.
- Historico: apenas diario ('D') via Brapi. Intraday exige plano pago
  (Brapi) ou licenca B3.
- Book de ofertas: `SimulatedBookProvider` e sintetico (dev/testes);
  book real exige B3 WebFeed (licenca) - `B3WebFeedBookProvider` stub.
- WebSocket streaming do core (websocket_proxy) ainda nao integrado.

## Master contract
- Semente offline (~100 simbolos) + Brapi tickers (se houver chave).
- Series de opcoes completas exigem referenciais oficiais da B3
  (roadmap); hoje apenas exemplos estruturados.

## Calendario / sessoes
- Feriados nacionais + Carnaval + Corpus Christi derivados da Pascoa.
  Feriados extraordinarios: usar env B3_EXTRA_HOLIDAYS (datas ISO).
- Horarios de sessao configuraveis (B3_SESSION_*); confira sempre o
  horario oficial vigente da B3 antes de producao.

## Compatibilidade core
- Modo zero-mod reutiliza codigos NSE/NFO/MCX/NSE_INDEX (validacao do
  core e fixa em camaras indianas). Modo nativo exige patch opcional de
  3 linhas (patches/b3_native_exchanges.patch).
