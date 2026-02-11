from __future__ import annotations

from dataclasses import dataclass
from typing import Literal, Optional

import pandas as pd

from indicators.atr import atr
from indicators.bollinger import bollinger_bands
from indicators.ma import ema
from indicators.rsi import rsi


# Valid logic modes matching MQL5 strategy variants
LogicMode = Literal["base", "rsi", "time", "rsi_time", "enhanced"]


@dataclass
class BollMeanReversionParams:
    # Time filter (M1.c, M1.d, enhanced)
    allowed_start_hour: int = 8
    allowed_end_hour: int = 16
    time_offset_hours: float = 0.0

    # Bollinger bands
    boll_period: int = 20
    boll_dev: float = 2.0

    # ATR
    atr_period: int = 14
    atr_vol_limit: float = 1.5  # BollMR_ATRVolLimit in MQL5

    # RSI (M1.b, M1.d)
    rsi_period: int = 14
    rsi_overbought: float = 70.0
    rsi_oversold: float = 30.0

    # Stop loss
    struct_atr_sl: float = 0.8
    vol_atr_sl: float = 2.0

    # Enhanced only: exit targets
    shortest_closing_time: int = 10
    bool_mid_atr_tp: float = 0.2
    bool_mid_atr_tp2: float = 0.5
    bool_uplow_atr_tp: float = 0.1

    # Enhanced only: MA trend filter
    ma_period: int = 50

    # Enhanced only: entry mode
    entry_mode: str = "A"

    # Strategy variant selector
    logic_mode: LogicMode = "enhanced"

    # Point value for slope calculation
    point: float = 0.01

    # Risk controls
    max_holding_bars: int = 0
    max_daily_loss_percent: float = 0.0
    risk_percent: float = 0.0
    max_losing_streak: int = 0
    cooldown_bars_after: int = 0
    cooldown_seconds: int = 0
    min_confidence: float = 0.0

    # Gap handling
    gap_cooldown_bars: int = 5
    gap_threshold_multiplier: float = 1.5


class BollMeanReversionStrategy:
    """Bollinger Mean Reversion Strategy.

    Supports multiple logic modes matching MQL5 variants:
    - base: M1.a - BB+ATR only (simplest)
    - rsi: M1.b - BB+ATR+RSI momentum filter
    - time: M1.c - BB+ATR+Time filter
    - rsi_time: M1.d - BB+ATR+RSI+Time filter
    - enhanced: Full version with MA trend, layered exits, etc.
    """

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
        """Check if current time is within allowed trading window.

        Supports cross-midnight windows (e.g., 20:00 -> 14:00).
        Time is adjusted by time_offset_hours before checking.
        """
        if self.params.time_offset_hours:
            ts = ts + pd.Timedelta(hours=self.params.time_offset_hours)
        hour = ts.hour
        start = self.params.allowed_start_hour
        end = self.params.allowed_end_hour
        if start <= end:
            return start <= hour < end
        # Cross-midnight window
        return hour >= start or hour < end

    def _trend_state(self, ma0: float, ma1: float, middle_up: bool, middle_down: bool) -> str:
        if ma0 > ma1 and middle_up:
            return "BULL"
        if ma0 < ma1 and middle_down:
            return "BEAR"
        return "FLAT"

    def _is_simple_mode(self) -> bool:
        """Check if this is a simple mode (base/rsi/time/rsi_time).

        Simple modes share: BB regression + volatility filter + middle-band exit.
        """
        return self.params.logic_mode in ("base", "rsi", "time", "rsi_time")

    def generate_signals(
        self,
        df: pd.DataFrame,
        diagnose: bool = False,
        debug_index: Optional[int] = None,
        debug_window: int = 2,
    ) -> pd.Series:
        diag: dict[str, int] = {}

        def bump(key: str, inc: int = 1) -> None:
            if not diagnose:
                return
            diag[key] = diag.get(key, 0) + inc

        # Calculate all indicators
        bands = bollinger_bands(df["close"], self.params.boll_period, self.params.boll_dev)
        atr_series = atr(df, self.params.atr_period)
        rsi_series = rsi(df["close"], self.params.rsi_period) if self.params.logic_mode in ("rsi", "rsi_time") else None
        ma_series = ema(df["close"], self.params.ma_period) if self.params.logic_mode == "enhanced" else None

        # Price data with shifts
        open0 = df["open"]
        close0 = df["close"]
        close1 = df["close"].shift(1)
        close2 = df["close"].shift(2)
        high1 = df["high"].shift(1)
        high2 = df["high"].shift(2)
        low1 = df["low"].shift(1)
        low2 = df["low"].shift(2)

        # Bollinger bands with shifts (MT5 CopyBuffer alignment)
        boll_u0 = bands["upper"].shift(0)
        boll_u1 = bands["upper"].shift(1)
        boll_u2 = bands["upper"].shift(2)
        boll_m0 = bands["mid"].shift(0)
        boll_m1 = bands["mid"].shift(1)
        boll_m2 = bands["mid"].shift(2)
        boll_l0 = bands["lower"].shift(0)
        boll_l1 = bands["lower"].shift(1)
        boll_l2 = bands["lower"].shift(2)

        # ATR with shifts
        atr1 = atr_series.shift(1)
        atr_mean10 = atr_series.shift(1).rolling(10).mean()

        # RSI with shift
        rsi1 = rsi_series.shift(1) if rsi_series is not None else None

        # MA with shifts (enhanced only)
        ma0 = ma_series if ma_series is not None else pd.Series(0.0, index=df.index)
        ma1 = ma_series.shift(1) if ma_series is not None else pd.Series(0.0, index=df.index)
        ma10 = ma_series.shift(10) if ma_series is not None else pd.Series(0.0, index=df.index)

        # State variables
        position = 0
        open_time: Optional[pd.Timestamp] = None
        gap_skip_bars_remaining = 0
        period_seconds = 0.0
        if len(df.index) > 1:
            diffs = df.index.to_series().diff().dropna().dt.total_seconds()
            if not diffs.empty:
                period_seconds = float(diffs.median())

        signals = []
        events = []

        is_simple = self._is_simple_mode()
        logic = self.params.logic_mode
        use_time_filter = logic in ("time", "rsi_time", "enhanced")
        use_rsi_filter = logic in ("rsi", "rsi_time")

        total = len(df.index)
        for idx, ts in enumerate(df.index):
            if self.progress_step and idx % self.progress_step == 0:
                print(f"[progress] {idx}/{total}", flush=True)
            bump("bars_total")

            debug_active = debug_index is not None and abs(idx - debug_index) <= max(debug_window, 0)

            def debug_print(msg: str) -> None:
                if debug_active:
                    print(f"[debug] {ts} idx={idx} {msg}")

            # Collect values for NaN check
            base_values = (
                close0.iloc[idx],
                close1.iloc[idx],
                close2.iloc[idx],
                boll_u1.iloc[idx],
                boll_u2.iloc[idx],
                boll_m1.iloc[idx],
                boll_m2.iloc[idx],
                boll_l1.iloc[idx],
                boll_l2.iloc[idx],
                atr1.iloc[idx],
                atr_mean10.iloc[idx],
            )
            rsi_value = rsi1.iloc[idx] if rsi1 is not None else None

            if any(pd.isna(v) for v in base_values):
                bump("bars_skipped_nan")
                debug_print("skipped_nan")
                signals.append(position)
                events.append(None)
                continue

            if use_rsi_filter and (rsi_value is None or pd.isna(rsi_value) or rsi_value <= 0):
                bump("bars_skipped_rsi_nan")
                signals.append(position)
                events.append(None)
                continue

            bump("bars_valid")

            # Unpack values
            (
                c0, c1, c2,
                bu1, bu2, bm1, bm2, bl1, bl2,
                a1, a_mean,
            ) = base_values

            # MA values (enhanced only)
            m0 = ma0.iloc[idx] if logic == "enhanced" else 0.0
            m1 = ma1.iloc[idx] if logic == "enhanced" else 0.0
            m10 = ma10.iloc[idx] if logic == "enhanced" else 0.0

            # Enhanced mode: additional shifts for entry modes
            bu0 = boll_u0.iloc[idx] if logic == "enhanced" else 0.0
            bm0 = boll_m0.iloc[idx] if logic == "enhanced" else 0.0
            bl0 = boll_l0.iloc[idx] if logic == "enhanced" else 0.0
            h1 = high1.iloc[idx] if logic == "enhanced" else 0.0
            h2 = high2.iloc[idx] if logic == "enhanced" else 0.0
            l1 = low1.iloc[idx] if logic == "enhanced" else 0.0
            l2 = low2.iloc[idx] if logic == "enhanced" else 0.0

            # Middle band direction
            middle_up_closed = bm1 >= bm2
            middle_down_closed = bm1 <= bm2
            middle_up_current = bm0 >= bm1 if logic == "enhanced" else False
            middle_down_current = bm0 <= bm1 if logic == "enhanced" else False

            if middle_up_closed:
                bump("middle_up")
            if middle_down_closed:
                bump("middle_down")

            # Gap cooldown
            if gap_skip_bars_remaining > 0:
                gap_skip_bars_remaining -= 1
                bump("bars_skipped_gap")
                debug_print(f"gap_skip remaining={gap_skip_bars_remaining}")
                signals.append(position)
                events.append(None)
                continue

            if idx >= 1 and self.params.gap_cooldown_bars > 0 and period_seconds > 0:
                prev_ts = df.index[idx - 1]
                actual_delta = ts - prev_ts
                if actual_delta.total_seconds() > period_seconds * self.params.gap_threshold_multiplier:
                    gap_skip_bars_remaining = self.params.gap_cooldown_bars
                    bump("gap_detected")
                    debug_print(
                        f"gap_detected period={period_seconds} actual={actual_delta} cooldown={gap_skip_bars_remaining}"
                    )
                    signals.append(position)
                    events.append(None)
                    continue

            # --- Volatility filter (all modes) ---
            def volatility_ok() -> bool:
                if a_mean <= 0:
                    return False
                return a1 <= a_mean * self.params.atr_vol_limit

            def reversion_failed() -> bool:
                if a_mean <= 0:
                    return True
                return a1 > a_mean * 1.4

            # --- Time filter ---
            time_ok = self._time_filter_ok(ts) if use_time_filter else True
            if use_time_filter:
                if time_ok:
                    bump("time_ok")
                else:
                    bump("time_blocked")

            # --- RSI filter ---
            def rsi_ok_long() -> bool:
                if not use_rsi_filter:
                    return True
                return rsi_value is not None and rsi_value <= self.params.rsi_oversold

            def rsi_ok_short() -> bool:
                if not use_rsi_filter:
                    return True
                return rsi_value is not None and rsi_value >= self.params.rsi_overbought

            # --- Entry signals ---
            def long_signal_simple() -> bool:
                """Simple modes (base/rsi/time/rsi_time): BB regression + filters."""
                if use_time_filter and not time_ok:
                    return False
                if not volatility_ok():
                    return False
                if not rsi_ok_long():
                    return False
                # BB regression: c2 below lower band, c1 back inside and below middle
                return c2 < bl2 and c1 > bl1 and c1 <= bm1

            def short_signal_simple() -> bool:
                """Simple modes (base/rsi/time/rsi_time): BB regression + filters."""
                if use_time_filter and not time_ok:
                    return False
                if not volatility_ok():
                    return False
                if not rsi_ok_short():
                    return False
                # BB regression: c2 above upper band, c1 back inside and above middle
                return c2 > bu2 and c1 < bu1 and c1 >= bm1

            def long_signal_enhanced() -> bool:
                """Enhanced mode: MA trend + entry modes A/B/C."""
                if not time_ok:
                    return False

                diff = m0 - m10
                slope_abs = abs(diff) / (10.0 * self.params.point) if self.params.point > 0 else 0.0
                long_trend_ok = diff >= 0 and slope_abs <= 100

                if long_trend_ok:
                    bump("long_trend_ok")

                if self.params.entry_mode == "A":
                    ok = (
                        long_trend_ok
                        and c2 < bl2
                        and c1 > bl1
                        and c1 <= bm1
                        and middle_up_closed
                        and volatility_ok()
                    )
                    if c2 < bl2:
                        bump("long_c2_below_bl2")
                    if c1 > bl1:
                        bump("long_c1_above_bl1")
                    if c1 <= bm1:
                        bump("long_c1_below_mid1")
                    if volatility_ok():
                        bump("vol_ok")
                    return ok
                elif self.params.entry_mode == "B":
                    wick_break = l2 < bl2
                    close_recover = c1 > bl1
                    if wick_break:
                        bump("long_wick_break")
                    if close_recover:
                        bump("long_close_recover")
                    if volatility_ok():
                        bump("vol_ok")
                    return (
                        long_trend_ok
                        and wick_break
                        and close_recover
                        and c1 <= bm1
                        and middle_up_closed
                        and volatility_ok()
                    )
                elif self.params.entry_mode == "C":
                    trend_state = self._trend_state(m0, m1, middle_up_current, middle_down_current)
                    bump(f"trend_{trend_state.lower()}")
                    if trend_state == "BEAR":
                        return False
                    if volatility_ok():
                        bump("vol_ok")
                    return c2 < bl2 and c1 > bl1 and c1 <= bm1 and volatility_ok()
                return False

            def short_signal_enhanced() -> bool:
                """Enhanced mode: MA trend + entry modes A/B/C."""
                if not time_ok:
                    return False

                diff = m0 - m10
                slope_abs = abs(diff) / (10.0 * self.params.point) if self.params.point > 0 else 0.0
                short_trend_ok = diff <= 0 and slope_abs <= 100

                if short_trend_ok:
                    bump("short_trend_ok")

                if self.params.entry_mode == "A":
                    ok = (
                        short_trend_ok
                        and c2 > bu2
                        and c1 < bu1
                        and c1 >= bm1
                        and middle_down_closed
                        and volatility_ok()
                    )
                    if c2 > bu2:
                        bump("short_c2_above_bu2")
                    if c1 < bu1:
                        bump("short_c1_below_bu1")
                    if c1 >= bm1:
                        bump("short_c1_above_mid1")
                    if volatility_ok():
                        bump("vol_ok")
                    return ok
                elif self.params.entry_mode == "B":
                    wick_break = h2 > bu2
                    close_recover = c1 < bu1
                    if wick_break:
                        bump("short_wick_break")
                    if close_recover:
                        bump("short_close_recover")
                    if volatility_ok():
                        bump("vol_ok")
                    return (
                        short_trend_ok
                        and wick_break
                        and close_recover
                        and c1 >= bm1
                        and middle_down_closed
                        and volatility_ok()
                    )
                elif self.params.entry_mode == "C":
                    trend_state = self._trend_state(m0, m1, middle_up_current, middle_down_current)
                    bump(f"trend_{trend_state.lower()}")
                    if trend_state == "BULL":
                        return False
                    if volatility_ok():
                        bump("vol_ok")
                    return c2 > bu2 and c1 < bu1 and c1 >= bm1 and volatility_ok()
                return False

            # --- Exit signals ---
            def exit_signal_simple() -> bool:
                """Simple modes: exit when price reaches middle band."""
                if position == 0:
                    return False
                bid_now = open0.iloc[idx]
                middle_ref = bm1
                if position > 0:
                    return bid_now >= middle_ref
                return bid_now <= middle_ref

            def exit_signal_enhanced() -> bool:
                """Enhanced mode: layered exits + pullback protection."""
                if position == 0:
                    return False
                if open_time is not None:
                    elapsed = (ts - open_time).total_seconds()
                    if elapsed < self.params.shortest_closing_time:
                        return False
                if reversion_failed():
                    return False

                bid_now = open0.iloc[idx]
                bid_prev = c1
                middle_ref = bm1

                if position > 0:
                    # Pullback protection: was above middle, now below
                    if bid_prev >= middle_ref and bid_now < middle_ref:
                        return True
                    # Layered TP levels
                    level1 = middle_ref + a1 * self.params.bool_mid_atr_tp
                    level2 = middle_ref + a1 * self.params.bool_mid_atr_tp2
                    if bid_now >= level1:
                        return True
                    if bid_now >= level2:
                        return True
                    if bid_now >= bu1:
                        return True
                else:
                    # Pullback protection: was below middle, now above
                    if bid_prev <= middle_ref and bid_now > middle_ref:
                        return True
                    # Layered TP levels
                    level1 = middle_ref - a1 * self.params.bool_mid_atr_tp
                    level2 = middle_ref - a1 * self.params.bool_mid_atr_tp2
                    if bid_now <= level1:
                        return True
                    if bid_now <= level2:
                        return True
                    if bid_now <= bl1:
                        return True
                return False

            # Select signal functions based on mode
            if is_simple:
                long_signal = long_signal_simple
                short_signal = short_signal_simple
                exit_signal = exit_signal_simple
            else:
                long_signal = long_signal_enhanced
                short_signal = short_signal_enhanced
                exit_signal = exit_signal_enhanced

            # Debug output
            if debug_active:
                vol_ok_dbg = volatility_ok()
                debug_print(
                    f"vals c0={c0} c1={c1} c2={c2} "
                    f"bu1={bu1} bu2={bu2} bm1={bm1} bm2={bm2} bl1={bl1} bl2={bl2} "
                    f"atr1={a1} atr_mean10={a_mean} rsi1={rsi_value}"
                )
                debug_print(f"conds time_ok={time_ok} vol_ok={vol_ok_dbg} logic={logic}")

            # Process exit
            if position != 0 and exit_signal():
                position = 0
                open_time = None
                events.append(0)
                signals.append(position)
                continue

            # Process entry
            if position == 0:
                if long_signal():
                    bump("long_entries")
                    position = 1
                    open_time = ts
                    events.append(1)
                elif short_signal():
                    bump("short_entries")
                    position = -1
                    open_time = ts
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
            # Count entries from events, not positions
            long_entries = sum(1 for e in events if e == 1)
            short_entries = sum(1 for e in events if e == -1)
            diag["long_entries"] = long_entries
            diag["short_entries"] = short_entries
            diag["signals_nonzero"] = int((series != 0).sum())
            diag["signals_long"] = int((series == 1).sum())
            diag["signals_short"] = int((series == -1).sum())
            # Store a copy to prevent mutation
            self.last_diagnostics = diag.copy()

        self.last_signal_events = event_series
        self.last_signal_state = state_series
        return series
