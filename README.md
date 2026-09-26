# openalgo-b3-adapter

**Adaptador FOSS do [OpenAlgo](https://openalgo.in/) para o mercado de ações brasileiro (B3).**

Este projeto cria um "mini universo FOSS" de compatibilização que permite ao OpenAlgo:

1. Consumir dados de mercado da B3 (cotações, histórico, book de ofertas)
2. Executar ordens no padrão B3 (ações, opções, futuros, FIIs)
3. Manter **zero modificações no núcleo do OpenAlgo** (uso do sistema de plugins nativo)

> ⚠️ **Status:** Alpha / MVP. Execute ordens reais somente após validar em ambiente
> sandbox. Leia [docs/LIMITATIONS.md](docs/LIMITATIONS.md) antes de qualquer uso com dinheiro real.

---

## Arquitetura em 30 segundos

O OpenAlgo carrega corretoras via plugins: qualquer pasta em `broker/<nome>/` com
`plugin.json` e os módulos `api/`, `mapping/` e `database/` se integra ao núcleo
*sem nenhuma alteração no core*. Este repositório fornece:

```
openalgo-b3-adapter/
├── openalgo_b3_adapter/          # pacote Python standalone (instalável via pip)
│   ├── config/                   # configurações centralizadas (env-driven)
│   ├── market_data/              # cotações (Brapi, HG Brasil), book, símbolos
│   ├── order_execution/          # gateways de corretora, tipos/validação de ordem
│   └── utils/                    # calendário B3, sessões, instrumentos
├── openalgo_plugin/b3/           # plugin drop-in → copiar para openalgo/broker/b3/
├── patches/                      # (opcional) patch para códigos de câmara nativos B3
├── examples/                     # exemplos de uso
├── tests/                        # testes unitários (pytest, 100% offline)
└── docs/                         # instalação, arquitetura, corretoras, limitações
```

Fluxo de uma ordem:

```
Estratégia (SDK openalgo)          Core OpenAlgo (intocado)
        │                                 │
        └──────► POST /api/v1/placeorder ──┘
                                          │ valida schema + despacha por plugin
                                          ▼
                          broker/b3/api/order_api.py   (plugin)
                                          │  mapeia OA → B3 (símbolo, tipo, lote)
                                          ▼
                    openalgo_b3_adapter.order_execution (gateway)
                                          │  sandbox | nuinvest | btg | ...
                                          ▼
                                     Corretora B3
```

Dados de mercado:

```
broker/b3/api/data.py ──► openalgo_b3_adapter.market_data ──► Brapi / HG Brasil / B3 WebFeed*
* WebFeed oficial da B3 requer licença paga (docs/BROKERS-BR.md)
```

## Replica e patches (estratégia Desktop_Agent)

- **`replicar_github.ps1`** (ou `.bat`): coloque numa pasta raiz genérica e
  rode — clona o projeto do GitHub (repositório público) e oferece
  atualização por `git pull` quando já existe.
- **Correções futuras** viram patches versionados e autodestrutivos:
  `python gerar_patch.py -m "desc" arquivos...` gera
  `patches/vNNN_data/patch_vNNN.ps1` que embute os novos conteúdos, faz
  backup da versão antiga em `anteriores/`, se registra em `registro.csv`
  e se autodestrói após aplicar. Detalhes em
  [docs/PATCHES.md](docs/PATCHES.md).

## Corretora fantasma (ambiente simulado de operação)

O gateway `sandbox` pode virar uma **corretora fantasma completa** para
funcionamento simulado — estado persistente, preços reais, execução
automática de ordens LIMIT/SL:

```bash
export B3_BROKER_GATEWAY=sandbox
export B3_SANDBOX_STATE_FILE=ghost_state.json   # sobrevive a restarts
export B3_SANDBOX_LIVE_FILLS=1                  # fills à cotação real (Brapi/HG)
export B3_SANDBOX_AUTO_TICK=30                  # motor de ticks: executa LIMIT/SL sozinho
export B3_SANDBOX_INITIAL_CASH=100000           # caixa inicial
```

Com isso, `place_order` de compra LIMIT a 33,50 é executado sozinho quando a
cotação real cai a 33,45; stop-loss SL-M dispara quando o preço cruza o
gatilho; posições exibem PnL não realizado pela última cotação — tudo sem
dinheiro real. Sem as flags, o sandbox permanece determinístico/offline
(recomendado para testes automatizados).

---

## Instalação rápida

```bash
# 1. Dentro do ambiente virtual do seu OpenAlgo
pip install -e /caminho/para/openalgo-b3-adapter

# 2. Copiar o plugin para dentro do OpenAlgo
cp -r openalgo_plugin/broker/b3 /caminho/para/openalgo/broker/b3

# 3. Configurar (opcional)
export BRAPI_API_KEY="sua-chave"        # https://brapi.dev
export B3_BROKER_GATEWAY="sandbox"      # sandbox | nuinvest | btg

# 4. Reiniciar o OpenAlgo e conectar a corretora "b3" na tela de brokers
```

Guia completo em [docs/INSTALL.md](docs/INSTALL.md).

## Mapeamento de câmaras (exchanges)

O núcleo do OpenAlgo valida `exchange` contra uma lista fixa de câmaras indianas
(`utils/constants.py`). Para **zero modificações no core**, o plugin mapeia os
segmentos da B3 sobre códigos genéricos já aceitos:

| Código OpenAlgo | Segmento B3 usado pelo plugin | Exemplos |
|---|---|---|
| `NSE` | Mercado à vista (ações, FIIs, ETFs) | `PETR4`, `VALE3`, `HGLG11` |
| `NFO` | Opções de ações e índices | `PETR4-26JUN-35.00-C` |
| `MCX` | Futuros (WIN, WDO, DI…) | `WINJ26`, `WDOJ26` |
| `NSE_INDEX` | Índices | `IBOV`, `IFUL` |

Se você preferir códigos nativos (`B3`, `B3OPT`, `B3FUT`), aplique o patch opcional
`patches/b3_native_exchanges.patch` (3 linhas no core) — documentado em
[docs/INSTALL.md](docs/INSTALL.md#modo-nativo-opcional).

## Cotações de exemplo (funciona sem chave para PETR4/VALE3/ITUB4/MGLU3)

```python
from openalgo_b3_adapter.market_data import BrapiQuoteProvider

quote = BrapiQuoteProvider().get_quote("PETR4")
print(quote.ltp, quote.volume)   # 41.18 34024700
```

Ordem via SDK oficial do OpenAlgo (após conectar o plugin):

```python
from openalgo import OpenAlgo   # SDK oficial, sem mudanças
api = OpenAlgo(api_key="...", host="http://localhost:5000")
api.place_order({
    "symbol": "PETR4", "action": "BUY", "exchange": "NSE",
    "quantity": 100, "pricetype": "LIMIT", "price": 33.50, "product": "CNC",
})
```

## O que já funciona hoje

- ✅ Mapeamento e normalização de símbolos B3 (à vista, fracionário, opções, futuros)
- ✅ Cotações e histórico via Brapi (plano gratuito) e HG Brasil (plano gratuito)
- ✅ Calendário de pregão da B3 (feriados nacionais + Carnaval/Corpus Christi, 2024–2030)
- ✅ Sessões da B3 (pré-abertura, pregão, leilão de fechamento, after-market)
- ✅ Validação de ordens (lote padrão, tick, sessão, tipo de preço)
- ✅ Gateway **sandbox** completo (place/cancel/modify, book de ordens, posições, funds)
- ✅ Plugin OpenAlgo com estrutura idêntica aos 35+ plugins indianos
- ✅ 100% offline nos testes unitários (`pytest -m "not network"`)

## O que NÃO funciona ainda (leia docs/BROKERS-BR.md)

- ❌ Execução em corretora real: as grandes corretas brasileiras **não oferecem API
  pública de trading algorítmico** para pessoa física. NuInvest e BTG têm APIs
  documentadas, mas sujeitas a onboarding/approval. O adapter fornece o *gateway*
  pronto e stubs documentados (`openalgo_b3_adapter/order_execution/brokers/`).
- ❌ Book de ofertas em tempo real (Brapi/HG não expõem profundidade; B3 WebFeed é pago)
- ❌ Streaming websocket integrado ao `websocket_proxy` do OpenAlgo (roadmap)

## Documentação

- [docs/INSTALL.md](docs/INSTALL.md) — instalação passo a passo
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — arquitetura e decisões de design
- [docs/BROKERS-BR.md](docs/BROKERS-BR.md) — panorama real das APIs de corretoras BR
- [docs/LIMITATIONS.md](docs/LIMITATIONS.md) — limitações conhecidas
- [docs/REGULATORY.md](docs/REGULATORY.md) — notas regulatórias (CVM/B3)

## Licença

MIT — mesmo espírito do OpenAlgo. Veja [LICENSE](LICENSE).
