# Arquitetura

## Camadas

```
┌─────────────────────────────────────────────────────────────┐
│ Estrategias (SDK openalgo, REST, WebSocket dashboard)       │
└──────────────────────────┬──────────────────────────────────┘
                           │ REST /api/v1/*
┌──────────────────────────▼──────────────────────────────────┐
│ CORE OpenAlgo (intocado)                                    │
│  - valida schema, despacha por plugin                       │
│  - despacho de ordens: services/place_order_service.py      │
│  - dados: services/{quotes,history,funds,...}_service.py    │
│  - plugins: utils/plugin_loader.py descobre broker/*/      │
└──────────────────────────┬──────────────────────────────────┘
                           │ broker.b3.api.* + mapping.*
┌──────────────────────────▼──────────────────────────────────┐
│ PLUGIN B3 (openalgo_plugin/broker/b3 -> openalgo/broker/b3) │
│  api/auth_api.py      authenticate_broker()                │
│  api/order_api.py     place/cancel/modify/consultas         │
│  api/data.py          BrokerData (quotes/history/depth)    │
│  api/funds.py         get_margin_data()                     │
│  mapping/             OA <-> B3 (símbolos, campos, status)  │
│  database/master_contract_db.py  symtoken (semente + Brapi) │
└──────────────────────────┬──────────────────────────────────┘
                           │ importa pacote instalado
┌──────────────────────────▼──────────────────────────────────┐
│ PACOTE openalgo_b3_adapter (standalone, pip install -e .)   │
│  config/      B3Config (env-driven) + mapa de camaras       │
│  utils/       calendario B3, sessoes, instrumentos          │
│  market_data/ provedores Brapi/HG, book, symbol mapper      │
│  order_execution/ gateways (sandbox/nuinvest/btg),          │
│                 tipos de ordem B3, validacao                │
└─────────────────────────────────────────────────────────────┘
```

## Decisoes de design

1. **Zero modificacao no core.** O core valida `exchange` contra
   VALID_EXCHANGES (lista fixa indiana em utils/constants.py). Em vez de
   editar o core, o plugin mapeia segmentos B3 sobre codigos genericos:
   NSE=a vista, NFO=opcoes, MCX=futuros, NSE_INDEX=indices. Codigos nativos
   via patch opcional de 3 linhas.

2. **Pacote standalone + plugin fino.** Toda a logica vive no pacote
   `openalgo_b3_adapter` (testavel sem OpenAlgo); o plugin apenas cola o
   core no pacote. Testes rodam 100% offline com pytest.

3. **Gateways por env.** `B3_BROKER_GATEWAY` seleciona a implementacao de
   B3OrderGateway. Sandbox completo em memoria (mesma ideia do
   dhan_sandbox do OpenAlgo); nuinvest/btg como stubs honestos que
   levantam NotImplementedError ate onboarding.

4. **Símbolos de opcoes estruturados.** Notacao OpenAlgo
   (BASE-YYYY-MM-DD-STRIKE-C/P) como `symbol` e codigo oficial B3
   (PETRA331) como `brsymbol` no symtoken. A serie de opcoes muda todo
   mes e exige fonte oficial (master contract da corretora ou licenca);
   sem isso, opcoes ficam limitadas aos exemplos da semente.

5. **Datas honestas.** Brapi/HG = cotação consolidada com atraso de plano
   gratuito. Nao vendemos "tempo real". B3 WebFeed/licenca documentada em
   BROKERS-BR.md e o caminho oficial para tick-a-tick.

## Fluxo de uma ordem (sandbox)

```
POST /api/v1/placeorder
  -> core valida schema (PlaceOrderSchema)
  -> broker.b3.api.order_api.place_order_api(data, auth)
  -> mapping.transform_data: OA symbol -> br_symbol (symtoken)
  -> map_openalgo_order -> OrderRequest B3
  -> gateway.place_order -> validate_order (lote/tick/sessao/pregao)
  -> SandboxGateway: MARKET executa na hora; LIMIT fica 'new'
  -> resposta {"status":"success","orderid":...}
```

## Estados de ordem

```
new/open -> complete | cancelled | rejected
(ciclo do SandboxGateway; corretores reais traduzem os status da B3
 para esse vocabulario em mapping/order_data.normalize_order_status)
```
