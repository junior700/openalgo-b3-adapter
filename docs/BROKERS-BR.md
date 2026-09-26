# Panorama real das APIs de corretoras brasileiras (set/2026)

Pesquisa feita na construcao deste adapter. Realidade dura: **a B3 e as
corretoras brasileiras NAO expõem APIs publicas de trading algoritmico para
pessoa fisica**, no modelo Zerodha/Shoonya (India). O que existe:

## Fonte oficial de mercado
| Fonte | O que da | Custo | REST? |
|---|---|---|---|
| **B3 Market Data WebFeed / UMDF** | tick-a-tick, book, referencial completo | Licença mensal por segmento (contrato B3) | Nao (WebSocket/binary) |
| **B3 for Developers (apidev.b3.com.br)** | APIs de dados (consultas, precos, balcoes) | Contrato/licença | Sim |
| **Referenciais de instrumentos (B3)** | Series de opcoes/futuros vigentes | Gratuito (arquivos publicos) | Download CSV |

## APIs de corretoras
| Corretora | API publica PF? | Observacao |
|---|---|---|
| **NuInvest** | Nao oficialmente | A OpenAPI (openapi.nuinvest.com.br) foi descontinuada publicamente; hoje e via onboarding/parceria com o Nu |
| **BTG Pactual** | Parceiros | developers BTG: OAuth2 + assinatura; onboarding formal |
| **XP / Clear / Rico** | Nao | Sem API de trading para PF |
| **Genial / Órama / Terra** | Nao | Idem |
| **Tradier-like BR** | — | Nao existe equivalente |

## APIs de dados (gratuitas)
| API | Dados | Limite gratuito |
|---|---|---|
| **Brapi** (brapi.dev) | Cotações acoes/FIIs/BDRs, historico diario, dividendos | Generoso; PETR4/VALE3/ITUB4/MGLU3 sem chave |
| **HG Brasil** (hgbrasil.com) | Cotações, historico | Generoso com key gratuita |
| **Brapi intraday** | Candles intraday | Plano pago |

## Conclusao honesta para o roadmap
1. **Dados de cotacao/historico:** resolvido com Brapi/HG (este adapter).
2. **Book de ofertas em tempo real:** exige B3 WebFeed (licenca) ou
   corretora com feed. Stub `B3WebFeedBookProvider` pronto p/ quando
   houver licenca.
3. **Execucao real:** exige conta em corretora com API (ex.: Nu/BTG via
   onboarding). O gateway `B3OrderGateway` isola tudo isso; implementar
   uma corretora = preencher ~9 metodos (veja brokers/nuinvest.py).
4. **Series de opcoes/futuros:** download dos referenciais publicos da B3
   (arquivos oficiais) para popular o master contract - proximo passo
   natural do roadmap.

Fontes: docs.brapi.dev, developers.hgbrasil.com, developers.b3.com,
github.com (buscas por "openapi nuinvest", "btg api python"). Sempre confirme
direto na fonte antes de decisoes de producao.
