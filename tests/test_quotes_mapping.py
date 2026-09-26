from openalgo_b3_adapter.market_data.b3_quotes import (
    BrapiQuoteProvider, CompositeQuoteProvider, HGBrasilQuoteProvider,
    to_openalgo_quote,
)


def _brapi_fetch(url, headers=None, params=None):
    assert "brapi.dev" in url
    assert params["symbols"] == "PETR4"
    if headers and "Authorization" in headers:
        assert headers["Authorization"].startswith("Bearer ")
    return {
        "results": [{
            "symbol": "PETR4",
            "data": {
                "regularMarketPrice": 41.18,
                "regularMarketOpen": 40.90,
                "regularMarketDayHigh": 41.40,
                "regularMarketDayLow": 40.75,
                "regularMarketPreviousClose": 41.76,
                "regularMarketBidPrice": 41.17,
                "regularMarketAskPrice": 41.18,
                "regularMarketVolume": 34024700,
            },
        }],
    }


def _hg_fetch(url, headers=None, params=None):
    assert "hgbrasil" in url
    return {
        "by": "HG Brasil",
        "results": {"VALE3": {"symbol": "VALE3", "name": "Vale ON",
                               "region": "Sao Paulo", "currency": "BRL",
                               "price": 61.92, "open": 61.20, "higher": 62.10,
                               "lower": 61.10, "close": 61.55, "volume": 28000000}},
    }


def test_brapi_provider_maps_to_quote():
    prov = BrapiQuoteProvider(fetch=_brapi_fetch)
    q = prov.get_quote("PETR4")
    assert q.ltp == 41.18
    assert q.prev_close == 41.76
    assert q.volume == 34024700
    assert q.source == "brapi"


def test_hgbrasil_provider_maps_to_quote():
    prov = HGBrasilQuoteProvider(fetch=_hg_fetch)
    q = prov.get_quote("VALE3")
    assert q.ltp == 61.92
    assert q.high == 62.10


def test_openalgo_quote_shape():
    prov = BrapiQuoteProvider(fetch=_brapi_fetch)
    data = to_openalgo_quote(prov.get_quote("PETR4"))
    assert set(data) == {"bid", "ask", "open", "high", "low", "ltp",
                         "prev_close", "volume", "oi", "tick_size"}
    assert data["ltp"] == 41.18
    assert data["oi"] == 0
    assert isinstance(data["volume"], int)


def test_composite_fallback_and_cache():
    calls = {"n": 0}

    def failing(url, headers=None, params=None):
        calls["n"] += 1
        raise ConnectionError("brapi fora")

    composite = CompositeQuoteProvider(
        providers=[
            BrapiQuoteProvider(fetch=failing),
            HGBrasilQuoteProvider(fetch=_hg_fetch),
        ],
        ttl=60,
    )
    q = composite.get_quote("VALE3")
    assert q.ltp == 61.92
    # cache: segunda chamada nao bate na rede
    composite.get_quote("VALE3")
    assert calls["n"] == 1
