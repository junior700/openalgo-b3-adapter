"""Serie real de opcoes de acoes B3 via matrizes publicas do opcoes.net.br.

Portado do projeto OpenAlgoBR-PRO (data_sources/opcoesnet.py) para o adapter.

- Duas requisicoes por subjacente (matriz CALL + matriz PUT), sem scraping
  individual por contrato por padrao.
- Qualquer falha (rede, parse, timeout) degrada para serie vazia: o contrato
  mestre continua com as sementes ilustrativas, nunca quebra o startup.
- Formato do vencimento normalizado para ISO (YYYY-MM-DD), como o restante
  do contrato mestre.

Roadmap: referenciais oficiais B3 substituem esta fonte quando disponiveis
(livros com MIDIA/lotes por faixa de premio exigem arquivo oficial).
"""

from __future__ import annotations

import re
from datetime import date, datetime
from typing import Any, Dict, List, Optional

import requests

BASE_URL = "https://opcoes.net.br"
TIMEOUT = 20

_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "Chrome/124 Safari/537.36"
    ),
    "Accept-Language": "pt-BR,pt;q=0.9,en;q=0.8",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
}

# lot padrao de opcoes de acoes B3 (lote oficial varia por faixa de premio)
DEFAULT_OPTION_LOT = 100


def _symbol(value: str) -> str:
    return re.sub(r"[^A-Z0-9]", "", str(value or "").upper())


def _parse_expiration(text: str) -> Optional[str]:
    """Extrai a primeira data dd/mm/aaaa e devolve ISO, ou None."""
    match = re.search(r"\b(\d{2})/(\d{2})/(\d{4})\b", text)
    if not match:
        return None
    d, m, y = match.groups()
    return f"{y}-{m}-{d}"


def _matrix_tickers(html: str, underlying: str) -> List[str]:
    """Tickers de opcao contidos no HTML da matriz, sem duplicar."""
    code_pattern = re.compile(rf"\b{re.escape(underlying[:4])}[A-Z][A-Z0-9]{{1,7}}\b")
    return list(dict.fromkeys(code_pattern.findall(html.upper())))


def _fetch_matrix_html(underlying: str, side: str) -> Optional[str]:
    """Baixa a matriz de um lado (CALL/PUT). None em falha."""
    url = f"{BASE_URL}/matriz-opcoes-strike-x-vencimento/{side}s/{underlying}"
    try:
        response = requests.get(url, headers=_HEADERS, timeout=TIMEOUT)
        response.raise_for_status()
        return response.text
    except Exception:  # noqa: BLE001 â€” offline e uma condicao normal aqui
        return None


def fetch_option_chain(underlying: str) -> List[Dict[str, Any]]:
    """Serie completa de opcoes (CALL+PUT) de um subjacente B3.

    Retorna lista de dicts:
        brsymbol, underlying, option_type (CALL/PUT), strike (float|None),
        expiry (ISO|None), lotsize.
    Serie vazia se a fonte estiver indisponivel ou o subjacente for invalido.
    """
    base = _symbol(underlying)
    if not re.fullmatch(r"[A-Z]{4}\d{1,2}", base):
        return []
    rows: List[Dict[str, Any]] = []
    seen = set()
    for side in ("CALL", "PUT"):
        html = _fetch_matrix_html(base, side)
        if not html:
            continue
        expiry = _parse_expiration(re.sub(r"<[^>]+>", " ", html))
        for ticker in _matrix_tickers(html, base):
            if ticker in seen or ticker == base:
                continue
            seen.add(ticker)
            rows.append({
                "brsymbol": ticker,
                "underlying": base,
                "option_type": side,
                "strike": None,
                "expiry": expiry,
                "lotsize": DEFAULT_OPTION_LOT,
            })
    return rows