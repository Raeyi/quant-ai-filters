from __future__ import annotations

from dataclasses import dataclass
from typing import Dict

import pandas as pd

from core.config import BacktestConfig
from utils.metrics import bars_per_year_from_timeframe, max_drawdown, sharpe_ratio


@dataclass
class BacktestResult:
    equity: pd.Series
    returns: pd.Series
    trades: pd.DataFrame
    stats: Dict[str, float]


def _build_trades(df: pd.DataFrame, position: pd.Series, pnl: pd.Series) -> pd.DataFrame:
    trades = []
    entry_time = None
    entry_price = None
    entry_pos = 0
    running_pnl = 0.0

    for time, pos, price, step_pnl in zip(df.index, position, df["close"], pnl):
        if entry_pos == 0 and pos != 0:
            entry_time = time
            entry_price = price
            entry_pos = pos
            running_pnl = 0.0
        elif entry_pos != 0:
            running_pnl += step_pnl
            if pos == 0:
                trades.append(
                    {
                        "entry_time": entry_time,
                        "exit_time": time,
                        "side": "long" if entry_pos > 0 else "short",
                        "entry_price": entry_price,
                        "exit_price": price,
                        "pnl": running_pnl,
                    }
                )
                entry_time = None
                entry_price = None
                entry_pos = 0
                running_pnl = 0.0

    if entry_pos != 0:
        last_time = df.index[-1]
        last_price = df["close"].iloc[-1]
        trades.append(
            {
                "entry_time": entry_time,
                "exit_time": last_time,
                "side": "long" if entry_pos > 0 else "short",
                "entry_price": entry_price,
                "exit_price": last_price,
                "pnl": running_pnl,
            }
        )

    return pd.DataFrame(trades)


def run_backtest(
    df: pd.DataFrame,
    signals: pd.Series,
    config: BacktestConfig,
) -> BacktestResult:
    if df.empty:
        raise ValueError("DataFrame is empty")
    signals = signals.reindex(df.index).fillna(0.0)

    # Avoid look-ahead by trading on the next bar by default.
    if config.trade_on_close:
        position = signals
    else:
        position = signals.shift(1).fillna(0.0)

    price = df["close"]
    price_change = price.diff().fillna(0.0)
    gross_pnl = position * price_change * config.lot_size

    trade_change = position.diff().abs().fillna(0.0)
    if "spread" in df.columns:
        spread_points = df["spread"]
        spread_cost = trade_change * (spread_points * config.point) * config.lot_size
    else:
        spread_cost = trade_change * (config.spread_points * config.point) * config.lot_size

    commission_cost = trade_change * config.commission_per_lot
    slippage_cost = trade_change * (config.slippage_points * config.point) * config.lot_size
    pnl = gross_pnl - spread_cost - commission_cost - slippage_cost

    equity = pnl.cumsum() + config.initial_cash
    returns = pnl / equity.shift(1).replace(0.0, pd.NA)
    returns = returns.fillna(0.0)

    dd, dd_time = max_drawdown(equity)
    bars_per_year = bars_per_year_from_timeframe(config.timeframe)
    sharpe = sharpe_ratio(returns, bars_per_year)

    stats = {
        "total_return": float(equity.iloc[-1] / config.initial_cash - 1.0),
        "max_drawdown": dd,
        "max_drawdown_time": dd_time.isoformat() if dd_time is not None else "",
        "sharpe": sharpe,
        "trades": int(trade_change.gt(0).sum() / 2),
    }

    trades = _build_trades(df, position, pnl)

    return BacktestResult(equity=equity, returns=returns, trades=trades, stats=stats)
