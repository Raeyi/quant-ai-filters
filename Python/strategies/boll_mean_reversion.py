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
    time_offset_hours: float = 0.0
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
        self.last_diagnostics: dict[str, int | float] = {}
        self.last_signal_events: pd.Series | None = None
        self.last_signal_state: pd.Series | None = None

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
        if self.params.time_offset_hours:
            ts = ts + pd.Timedelta(hours=self.params.time_offset_hours)
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

    def generate_signals(self, df: pd.DataFrame, diagnose: bool = False) -> pd.Series:
        diag: dict[str, int] = {}
        def bump(key: str, inc: int = 1) -> None:
            if not diagnose:
                return
            diag[key] = diag.get(key, 0) + inc

        bands = bollinger_bands(df["close"], self.params.boll_period, self.params.boll_dev)
        atr_series = atr(df, self.params.atr_period)
        ma_series = ema(df["close"], self.params.ma_period)

        close0 = df["close"]
        close1 = df["close"].shift(1)
        high1 = df["high"].shift(1)
        low1 = df["low"].shift(1)

        # MT5 CopyBuffer for Bollinger starts at shift=1 (closed bar),
        # so GetBoll*(0) maps to bands.shift(1) and GetBoll*(1) maps to shift(2).
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
        events = []
        signal_state = 0

        total = len(df.index)
        for idx, ts in enumerate(df.index):
            if self.progress_step and idx % self.progress_step == 0:
                print(f"[progress] {idx}/{total}", flush=True)
            bump("bars_total")
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
                bump("bars_skipped_nan")
                signals.append(position)
                events.append(None)
                continue
            bump("bars_valid")

            c0, c1, h1, l1, bu0, bu1, bm0, bm1, bl0, bl1, a1, a_mean, m0, m1, m10 = values

            middle_up = bm0 >= bm1
            middle_down = bm0 <= bm1
            if middle_up:
                bump("middle_up")
            if middle_down:
                bump("middle_down")

            diff = m0 - m10
            slope_abs = abs(diff) / (10.0 * self.params.point) if self.params.point > 0 else 0.0

            long_trend_ok = diff >= 0 and slope_abs <= 100
            short_trend_ok = diff <= 0 and slope_abs <= 100
            if long_trend_ok:
                bump("long_trend_ok")
            if short_trend_ok:
                bump("short_trend_ok")

            trend_state = self._trend_state(m0, m1, middle_up, middle_down)
            bump(f"trend_{trend_state.lower()}")

            def volatility_ok() -> bool:
                if a_mean <= 0:
                    return False
                return a1 <= a_mean * 1.5

            def reversion_failed() -> bool:
                if a_mean <= 0:
                    return True
                return a1 > a_mean * 1.4

            def long_signal() -> bool:
                time_ok = self._time_filter_ok(ts)
                if time_ok:
                    bump("time_ok")
                else:
                    bump("time_blocked")
                if not time_ok:
                    return False
                if self.params.entry_mode == "A":
                    ok = (
                        long_trend_ok
                        and c1 < bl1
                        and c0 > bl0
                        and middle_up
                        and volatility_ok()
                    )
                    if c1 < bl1:
                        bump("long_c1_below_bl1")
                    if c0 > bl0:
                        bump("long_c0_above_bl0")
                    if volatility_ok():
                        bump("vol_ok")
                    return ok
                if self.params.entry_mode == "B":
                    wick_break = l1 < bl1
                    close_recover = c0 > bl0
                    if wick_break:
                        bump("long_wick_break")
                    if close_recover:
                        bump("long_close_recover")
                    if volatility_ok():
                        bump("vol_ok")
                    return long_trend_ok and wick_break and close_recover and middle_up and volatility_ok()
                if self.params.entry_mode == "C":
                    if trend_state == "BEAR":
                        return False
                    if volatility_ok():
                        bump("vol_ok")
                    return c1 < bl1 and c0 > bl0 and volatility_ok()
                return False

            def short_signal() -> bool:
                time_ok = self._time_filter_ok(ts)
                if time_ok:
                    bump("time_ok")
                else:
                    bump("time_blocked")
                if not time_ok:
                    return False
                if self.params.entry_mode == "A":
                    ok = (
                        short_trend_ok
                        and c1 > bu1
                        and c0 < bu0
                        and middle_down
                        and volatility_ok()
                    )
                    if c1 > bu1:
                        bump("short_c1_above_bu1")
                    if c0 < bu0:
                        bump("short_c0_below_bu0")
                    if volatility_ok():
                        bump("vol_ok")
                    return ok
                if self.params.entry_mode == "B":
                    wick_break = h1 > bu1
                    close_recover = c0 < bu0
                    if wick_break:
                        bump("short_wick_break")
                    if close_recover:
                        bump("short_close_recover")
                    if volatility_ok():
                        bump("vol_ok")
                    return short_trend_ok and wick_break and close_recover and middle_down and volatility_ok()
                if self.params.entry_mode == "C":
                    if trend_state == "BULL":
                        return False
                    if volatility_ok():
                        bump("vol_ok")
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
                signal_state = 0
                events.append(0)
                signals.append(position)
                continue

            if position == 0:
                if long_signal():
                    bump("long_entries")
                    position = 1
                    open_time = ts
                    signal_state = 1
                    events.append(1)
                elif short_signal():
                    bump("short_entries")
                    position = -1
                    open_time = ts
                    signal_state = -1
                    events.append(-1)
                else:
                    events.append(None)
            else:
                events.append(None)

            signals.append(position)

        series = pd.Series(signals, index=df.index, name="signal")
        event_series = pd.Series(events, index=df.index, name="signal_event")
        state_series = event_series.ffill().fillna(0).astype(int)
        state_series.name = "signal_state"
        if diagnose:
            diag["signals_nonzero"] = int((series != 0).sum())
            diag["signals_long"] = int((series == 1).sum())
            diag["signals_short"] = int((series == -1).sum())
            self.last_diagnostics = diag
        self.last_signal_events = event_series
        self.last_signal_state = state_series
        return series
