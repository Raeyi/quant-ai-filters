from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

import pandas as pd

from indicators.atr import atr
from indicators.bollinger import bollinger_bands
from indicators.ma import ema


@dataclass
class BollMeanReversionParams:
    allowed_start_hour: int = 2
    allowed_end_hour: int = 20
    boll_period: int = 20
    boll_dev: float = 2.0
    atr_period: int = 14
    shortest_closing_time: int = 10
    struct_atr_sl: float = 0.8
    vol_atr_sl: float = 2.0
    bool_mid_atr_tp: float = 0.2
    bool_uplow_atr_tp: float = 0.1
    ma_period: int = 50
    entry_mode: str = "A"
    point: float = 0.0001
    max_holding_bars: int = 0
    max_daily_loss_percent: float = 0.0
    risk_percent: float = 0.0
    max_losing_streak: int = 0
    cooldown_bars_after: int = 0
    cooldown_seconds: int = 0
    min_confidence: float = 0.0


class BollMeanReversionStrategy:
    def __init__(self, params: BollMeanReversionParams, progress_step: int = 0):
        self.params = params
        self.progress_step = progress_step

    def build_features(self, df: pd.DataFrame) -> pd.DataFrame:
        bands = bollinger_bands(df["close"], self.params.boll_period, self.params.boll_dev)
        atr_series = atr(df, self.params.atr_period)
        close_prev = df["close"].shift(1)
        boll_u_prev = bands["upper"].shift(1)
        boll_l_prev = bands["lower"].shift(1)
        boll_m_prev = bands["mid"].shift(1)
        atr_prev = atr_series.shift(1)

        zscore = (close_prev - boll_m_prev) / (boll_u_prev - boll_m_prev)
        width = (boll_u_prev - boll_l_prev) / boll_m_prev

        features = pd.DataFrame(
            {
                "close": close_prev,
                "boll_u": boll_u_prev,
                "boll_l": boll_l_prev,
                "boll_mid": boll_m_prev,
                "atr": atr_prev,
                "zscore": zscore,
                "band_width": width,
            }
        )
        return features

    def _time_filter_ok(self, ts: pd.Timestamp) -> bool:
        hour = ts.hour
        start = self.params.allowed_start_hour
        end = self.params.allowed_end_hour
        if start <= end:
            return start <= hour < end
        return hour >= start or hour < end

    def _trend_state(self, ma0: float, ma1: float, middle_up: bool, middle_down: bool) -> str:
        if ma0 > ma1 and middle_up:
            return "BULL"
        if ma0 < ma1 and middle_down:
            return "BEAR"
        return "FLAT"

    def generate_signals(self, df: pd.DataFrame) -> pd.Series:
        bands = bollinger_bands(df["close"], self.params.boll_period, self.params.boll_dev)
        atr_series = atr(df, self.params.atr_period)
        ma_series = ema(df["close"], self.params.ma_period)

        close0 = df["close"]
        close1 = df["close"].shift(1)
        high1 = df["high"].shift(1)
        low1 = df["low"].shift(1)

        boll_u0 = bands["upper"].shift(1)
        boll_u1 = bands["upper"].shift(2)
        boll_m0 = bands["mid"].shift(1)
        boll_m1 = bands["mid"].shift(2)
        boll_l0 = bands["lower"].shift(1)
        boll_l1 = bands["lower"].shift(2)

        atr1 = atr_series.shift(1)
        atr_mean10 = atr_series.shift(1).rolling(10).mean()

        ma0 = ma_series
        ma1 = ma_series.shift(1)
        ma10 = ma_series.shift(10)

        position = 0
        open_time: Optional[pd.Timestamp] = None
        signals = []

        total = len(df.index)
        for idx, ts in enumerate(df.index):
            if self.progress_step and idx % self.progress_step == 0:
                print(f"[progress] {idx}/{total}", flush=True)
            values = (
                close0.iloc[idx],
                close1.iloc[idx],
                high1.iloc[idx],
                low1.iloc[idx],
                boll_u0.iloc[idx],
                boll_u1.iloc[idx],
                boll_m0.iloc[idx],
                boll_m1.iloc[idx],
                boll_l0.iloc[idx],
                boll_l1.iloc[idx],
                atr1.iloc[idx],
                atr_mean10.iloc[idx],
                ma0.iloc[idx],
                ma1.iloc[idx],
                ma10.iloc[idx],
            )
            if any(pd.isna(v) for v in values):
                signals.append(position)
                continue

            c0, c1, h1, l1, bu0, bu1, bm0, bm1, bl0, bl1, a1, a_mean, m0, m1, m10 = values

            middle_up = bm0 >= bm1
            middle_down = bm0 <= bm1

            diff = m0 - m10
            slope_abs = abs(diff) / (10.0 * self.params.point) if self.params.point > 0 else 0.0

            long_trend_ok = diff >= 0 and slope_abs <= 100
            short_trend_ok = diff <= 0 and slope_abs <= 100

            trend_state = self._trend_state(m0, m1, middle_up, middle_down)

            def volatility_ok() -> bool:
                if a_mean <= 0:
                    return False
                return a1 <= a_mean * 1.5

            def reversion_failed() -> bool:
                if a_mean <= 0:
                    return True
                return a1 > a_mean * 1.4

            def long_signal() -> bool:
                if not self._time_filter_ok(ts):
                    return False
                if self.params.entry_mode == "A":
                    return (
                        long_trend_ok
                        and c1 < bl1
                        and c0 > bl0
                        and middle_up
                        and volatility_ok()
                    )
                if self.params.entry_mode == "B":
                    wick_break = l1 < bl1
                    close_recover = c0 > bl0
                    return long_trend_ok and wick_break and close_recover and middle_up and volatility_ok()
                if self.params.entry_mode == "C":
                    if trend_state == "BEAR":
                        return False
                    return c1 < bl1 and c0 > bl0 and volatility_ok()
                return False

            def short_signal() -> bool:
                if not self._time_filter_ok(ts):
                    return False
                if self.params.entry_mode == "A":
                    return (
                        short_trend_ok
                        and c1 > bu1
                        and c0 < bu0
                        and middle_down
                        and volatility_ok()
                    )
                if self.params.entry_mode == "B":
                    wick_break = h1 > bu1
                    close_recover = c0 < bu0
                    return short_trend_ok and wick_break and close_recover and middle_down and volatility_ok()
                if self.params.entry_mode == "C":
                    if trend_state == "BULL":
                        return False
                    return c1 > bu1 and c0 < bu0 and volatility_ok()
                return False

            def exit_signal() -> bool:
                if position == 0:
                    return False
                if open_time is not None:
                    elapsed = (ts - open_time).total_seconds()
                    if elapsed < self.params.shortest_closing_time:
                        return False
                if reversion_failed():
                    return False

                bid_now = c0
                bid_prev = c1
                if position > 0:
                    if (
                        bid_prev < bm1
                        and bid_now >= bm0
                        and abs(bid_now - bm0) < a1 * self.params.bool_mid_atr_tp
                    ):
                        return True
                    if bid_now >= bu1 - a1 * self.params.bool_uplow_atr_tp:
                        return True
                else:
                    if (
                        bid_prev > bm1
                        and bid_now <= bm0
                        and abs(bid_now - bm0) < a1 * self.params.bool_mid_atr_tp
                    ):
                        return True
                    if bid_now <= bl1 + a1 * self.params.bool_uplow_atr_tp:
                        return True
                return False

            if position != 0 and exit_signal():
                position = 0
                open_time = None
                signals.append(position)
                continue

            if position == 0:
                if long_signal():
                    position = 1
                    open_time = ts
                elif short_signal():
                    position = -1
                    open_time = ts

            signals.append(position)

        return pd.Series(signals, index=df.index, name="signal")
