# Instalação

## Pré-requisitos
- OpenAlgo instalado (v1.x) e rodando (`python app.py`)
- Python 3.10+ (mesmo ambiente virtual do OpenAlgo)
- Conta Brapi (gratuita) para cotações — https://brapi.dev

## 1. Instalar o pacote adapter

```bash
cd openalgo-b3-adapter
pip install -e .
```

## 2. Copiar o plugin para dentro do OpenAlgo

```bash
cp -r openalgo_plugin/broker/b3 /caminho/para/openalgo/broker/b3
```

## 3. Configurar ambiente (.env do OpenAlgo ou shell)

```bash
B3_BROKER_GATEWAY=sandbox    # sandbox | nuinvest | btg
BRAPI_API_KEY=               # opcional no plano gratuito p/ PETR4/VALE3/ITUB4/MGLU3
HGBRASIL_API_KEY=            # opcional (fallback de cotação)
MASTER_CONTRACT_CUTOFF_TIME=00:00   # revalida o master contract a cada dia util
```

## 4. Rodar

Reinicie o OpenAlgo. Em **Settings → Brokers**, conecte a corretora `B3 Brasil`
(digite qualquer valor no campo API KEY no modo sandbox). O master contract é
baixado no primeiro login (semente offline: ~100 simbolos; com BRAPI_API_KEY,
a lista completa de tickers da B3).

## 5. Testar com o SDK oficial

```python
from openalgo import OpenAlgo
api = OpenAlgo(api_key="SUA_API_KEY_OPENALGO", host="http://localhost:5000")
print(api.search("PETR"))
print(api.quote(symbol="PETR4", exchange="NSE"))
print(api.place_order(symbol="PETR4", action="BUY", exchange="NSE",
                      quantity=100, pricetype="LIMIT", price=33.50, product="CNC"))
```

## Modo nativo (opcional)

Sem o patch, o plugin reutiliza os codigos de camara genericos aceitos pelo core
(NSE/NFO/MCX/NSE_INDEX). Para usar codigos nativos B3 (B3/B3OPT/B3FUT), aplique:

```bash
cd /caminho/para/openalgo
git apply caminho/para/openalgo-b3-adapter/patches/b3_native_exchanges.patch
```

O patch altera apenas `utils/constants.py` (adiciona as camaras B3) e o plugin
aceita os dois conjuntos simultaneamente (sem patch, codigos nativos nao
funcionam; com patch, os genericos continuam funcionando).

## Testes

```bash
pip install -e .[dev]
pytest -q            # 100% offline
```
