"""Testes da carga de series reais de opcoes (opcoes.net.br)."""

from openalgo_b3_adapter.market_data import opcoesnet_chain as oc

_MATRIZ_HTML = """
<html><body>
  <h1>Matriz de opcoes - CALL - PETR4</h1>
  <p>Vencimento: 02/10/2026</p>
  <table>
    <tr><td>PETRA331</td><td>PETRA332</td></tr>
    <tr><td>PETRD421</td><td>PETR4</td></tr>
    <tr><td>petra331</td></tr>
  </table>
</body></html>
"""


def test_parse_expiration_iso():
    assert oc._parse_expiration("Vencimento 17/12/2026 ok") == "2026-12-17"
    assert oc._parse_expiration("sem data") is None


def test_matrix_tickers_dedup_e_case():
    tickers = oc._matrix_tickers(_MATRIZ_HTML, "PETR4")
    assert tickers == ["PETRA331", "PETRA332", "PETRD421"]


def test_fetch_chain_offline_retorna_vazio(monkeypatch):
    monkeypatch.setattr(oc, "_fetch_matrix_html", lambda u, s: None)
    assert oc.fetch_option_chain("PETR4") == []


def test_fetch_chain_consome_fonte(monkeypatch):
    chamadas = []

    def fake_fetch(underlying, side):
        chamadas.append((underlying, side))
        return _MATRIZ_HTML if side == "CALL" else None

    monkeypatch.setattr(oc, "_fetch_matrix_html", fake_fetch)
    rows = oc.fetch_option_chain("petr4")
    assert ({"PETR4", "CALL"}) in [set(c) for c in [chamadas[0]]]
    assert [r["brsymbol"] for r in rows] == ["PETRA331", "PETRA332", "PETRD421"]
    assert rows[0]["expiry"] == "2026-10-02"
    assert rows[0]["option_type"] == "CALL"
    assert rows[0]["lotsize"] == 100
    assert rows[0]["underlying"] == "PETR4"


def test_fetch_chain_subjacente_invalido(monkeypatch):
    monkeypatch.setattr(oc, "_fetch_matrix_html", lambda u, s: _MATRIZ_HTML)
    assert oc.fetch_option_chain("PET") == []
    assert oc.fetch_option_chain("PETRA") == []