from __future__ import annotations

import math
from typing import Tuple

import pandas as pd


def max_drawdown(equity: pd.Series) -> Tuple[float, pd.Timestamp | None]:
    if equity.empty:
        return 0.0, None
    running_max = equity.cummax()
    drawdown = (equity - running_max) / running_max
    min_dd = drawdown.min()
    min_time = drawdown.idxmin() if not drawdown.empty else None
    return float(min_dd), min_time


def sharpe_ratio(returns: pd.Series, bars_per_year: int) -> float:
    if returns.empty or returns.std() == 0:
        return 0.0
    mean = returns.mean() * bars_per_year
    vol = returns.std() * math.sqrt(bars_per_year)
    return float(mean / vol)


def bars_per_year_from_timeframe(timeframe: str) -> int:
    tf = timeframe.strip().upper()
    if tf.endswith("M"):
        minutes = int(tf[:-1])
        return int((252 * 24 * 60) / minutes)
    if tf.endswith("H"):
        hours = int(tf[:-1])
        return int((252 * 24) / hours)
    if tf.endswith("D"):
        days = int(tf[:-1])
        return int(252 / days)
    return 252

