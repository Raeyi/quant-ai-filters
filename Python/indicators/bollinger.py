from __future__ import annotations

import pandas as pd


def bollinger_bands(close: pd.Series, window: int, num_std: float) -> pd.DataFrame:
    mid = close.rolling(window).mean()
    # MT5 iBands uses population stddev
    std = close.rolling(window).std(ddof=0)
    upper = mid + num_std * std
    lower = mid - num_std * std
    return pd.DataFrame({"mid": mid, "upper": upper, "lower": lower})
