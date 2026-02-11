from __future__ import annotations

import pandas as pd


def rsi(series: pd.Series, period: int) -> pd.Series:
    """Calculate RSI (Relative Strength Index).
    
    Matches MT5 iRSI behavior using Wilder's smoothing.
    
    Args:
        series: Price series (typically close prices)
        period: RSI period (default 14)
    
    Returns:
        RSI values (0-100 range)
    """
    delta = series.diff()
    gain = delta.where(delta > 0, 0.0)
    loss = (-delta).where(delta < 0, 0.0)
    
    # Wilder's smoothing (same as MT5)
    avg_gain = gain.ewm(alpha=1.0 / period, adjust=False).mean()
    avg_loss = loss.ewm(alpha=1.0 / period, adjust=False).mean()
    
    rs = avg_gain / avg_loss.replace(0, pd.NA)
    rsi_series = 100.0 - (100.0 / (1.0 + rs))
    
    return rsi_series.fillna(0.0).rename("rsi")
