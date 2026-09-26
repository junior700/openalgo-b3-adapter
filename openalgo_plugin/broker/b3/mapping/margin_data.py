"""Mapeamento de posicoes para calculo de margem/PnL (padrao OpenAlgo)."""
from utils.logging import get_logger

logger = get_logger(__name__)


def transform_margin_positions(positions, userid, auth_token=None):
    """Posicoes raw do gateway B3 -> formato de margem do core."""
    out = []
    for p in positions or []:
        out.append({
            "tsym": p.get("oa_symbol") or p.get("symbol", ""),
            "exch": p.get("exchange", ""),
            "prd": p.get("product", "CNC"),
            "netqty": int(p.get("quantity", 0) or 0),
            "netavgprc": float(p.get("average_price", 0) or 0),
            "lp": float(p.get("ltp", 0) or 0),
            "rpnl": float(p.get("realized_pnl", 0) or 0),
            "urmtom": float(p.get("unrealized_pnl", 0) or 0),
        })
    return out
