"""Corretora fantasma: persistencia, caixa, fills por cotacao e ticks."""
import json

import pytest

from openalgo_b3_adapter.order_execution import OrderRequest, SandboxGateway


class _FakeProvider:
    def __init__(self, prices):
        self.prices = prices

    def get_quote(self, symbol):
        from openalgo_b3_adapter.market_data.b3_quotes import Quote
        return Quote(symbol=symbol, ltp=float(self.prices[symbol]))


def _buy(sym="PETR4", **kw):
    base = dict(symbol=sym, side="BUY", quantity=100, order_type="MARKET",
                exchange="NSE", oa_symbol=sym, reference_price=33.50)
    base.update(kw)
    return OrderRequest(**base)


def test_state_file_persists_across_instances(tmp_path):
    state = tmp_path / "ghost.json"
    gw = SandboxGateway(state_file=str(state), ignore_sessions=True)
    gw.place_order(_buy(), "user1")
    assert state.exists()
    # nova instancia (ex.: restart do OpenAlgo) recupera o estado
    gw2 = SandboxGateway(state_file=str(state), ignore_sessions=True)
    orders = gw2.get_orders("user1")
    assert orders and orders[0]["order_id"] == "B3SBX-000001"
    assert gw2.get_positions("user1")[0]["quantity"] == 100
    assert float(gw2.get_funds("user1")["availablecash"]) == 100000.00 - 3350.00
    # e o contador de ids continua de onde parou
    res = gw2.place_order(_buy(), "user1")
    assert res["order_id"] == "B3SBX-000002"


def test_corrupted_state_file_starts_clean(tmp_path):
    state = tmp_path / "broken.json"
    state.write_text("{invalido", encoding="utf-8")
    gw = SandboxGateway(state_file=str(state), ignore_sessions=True)
    gw.ensure_auth("u")
    assert gw.get_orders("u") == []


def test_cash_accounting_buy_and_sell():
    gw = SandboxGateway(ignore_sessions=True)
    gw.place_order(_buy(reference_price=30.0), "u")
    funds = gw.get_funds("u")
    assert float(funds["availablecash"]) == 100000.00 - 3000.00  # comprou 100 x 30
    gw.place_order(_buy(side="SELL", reference_price=32.0), "u")
    assert float(gw.get_funds("u")["availablecash"]) == 100000.00 - 3000.00 + 3200.00
    # posicao zerada: caixa reflete o lucro realizado de 200
    assert gw.get_positions("u") == []


def test_market_fill_uses_live_quote_when_enabled():
    gw = SandboxGateway(
        ignore_sessions=True, use_live_quotes=True,
        quote_provider=_FakeProvider({"PETR4": 41.20}),
    )
    gw.place_order(_buy(reference_price=10.0), "u")  # live vence o reference
    assert gw.get_trades("u")[0]["price"] == 41.20


def test_live_quotes_off_keeps_deterministic_fill():
    gw = SandboxGateway(ignore_sessions=True, use_live_quotes=False,
                       quote_provider=_FakeProvider({"PETR4": 99.0}))
    gw.place_order(_buy(reference_price=33.50), "u")
    assert gw.get_trades("u")[0]["price"] == 33.50  # provider ignorado


def test_tick_fills_limit_when_price_crosses():
    prices = {"PETR4": 34.00}
    gw = SandboxGateway(ignore_sessions=True, use_live_quotes=True,
                        quote_provider=_FakeProvider(prices))
    res = gw.place_order(_buy(order_type="LIMIT", price=33.50), "u")
    oid = res["order_id"]
    assert gw.get_orders("u")[0]["status"] == "new"   # 34 > 33.50: nao executa
    prices["PETR4"] = 33.45                            # preco cai abaixo do limite
    out = gw.tick()
    assert oid in out["filled"]
    assert gw.get_orders("u")[0]["status"] == "complete"
    assert gw.get_trades("u")[0]["price"] == 33.45


def test_tick_sells_limit_when_price_rises():
    prices = {"VALE3": 60.00}
    gw = SandboxGateway(ignore_sessions=True, use_live_quotes=True,
                        quote_provider=_FakeProvider(prices))
    gw.place_order(_buy(sym="VALE3", reference_price=60.0), "u")
    res = gw.place_order(
        _buy(sym="VALE3", side="SELL", order_type="LIMIT", price=61.00), "u")
    oid = res["order_id"]
    prices["VALE3"] = 61.10
    assert oid in gw.tick()["filled"]


def test_tick_triggers_stop_loss():
    prices = {"PETR4": 35.00}
    gw = SandboxGateway(ignore_sessions=True, use_live_quotes=True,
                        quote_provider=_FakeProvider(prices))
    gw.place_order(_buy(reference_price=35.0), "u")
    res = gw.place_order(
        _buy(side="SELL", order_type="SL-M", trigger_price=34.00), "u")
    oid = res["order_id"]
    assert gw.get_orders("u")[1]["status"] == "trigger_pending"
    prices["PETR4"] = 33.90                                # caiu abaixo do gatilho
    out = gw.tick()
    assert oid in out["triggered"]
    assert gw.get_orders("u")[1]["status"] == "complete"
    assert gw.get_positions("u") == []                      # stop vendeu tudo


def test_positions_unrealized_pnl_uses_ltp():
    prices = {"PETR4": 36.00}
    gw = SandboxGateway(ignore_sessions=True, use_live_quotes=True,
                        quote_provider=_FakeProvider(prices))
    gw.place_order(_buy(reference_price=33.50), "u")   # executa a 36.00 (live)
    assert gw.get_positions("u")[0]["average_price"] == 36.00
    prices["PETR4"] = 38.00                            # cotacao sobe
    pos = gw.get_positions("u")[0]
    assert pos["ltp"] == 38.00
    assert pos["unrealized_pnl"] == round((38.00 - 36.00) * 100, 2)  # 200.00


def test_env_config_enables_ghost_mode(tmp_path, monkeypatch):
    monkeypatch.setenv("B3_SANDBOX_STATE_FILE", str(tmp_path / "s.json"))
    monkeypatch.setenv("B3_SANDBOX_LIVE_FILLS", "1")
    monkeypatch.setenv("B3_SANDBOX_AUTO_TICK", "30")
    gw = SandboxGateway(ignore_sessions=True,
                        quote_provider=_FakeProvider({"PETR4": 40.0}))
    assert gw._state_file.endswith("s.json")
    assert gw._use_live_quotes is True
    assert gw._auto_tick_seconds == 30.0
    assert gw._tick_thread is not None and gw._tick_thread.is_alive()
    gw.stop_tick()
    assert not gw._tick_thread.is_alive()


def test_holdings_report_pnl():
    prices = {"PETR4": 36.00}
    gw = SandboxGateway(ignore_sessions=True, use_live_quotes=True,
                        quote_provider=_FakeProvider(prices))
    gw.place_order(_buy(reference_price=33.50), "u")   # executa a 36.00 (live)
    prices["PETR4"] = 38.00
    h = gw.get_holdings("u")[0]
    assert h["product"] == "CNC"
    assert h["pnl"] == 200.00                          # (38-36) x 100
