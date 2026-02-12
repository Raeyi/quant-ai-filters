"""
Trend Pullback Strategy (M2)
大趋势 + 小级别回撤吃第二段

M15 确定方向（EMA50/EMA200）→ M5 寻找回撤入场点 → 吃趋势的第二段利润
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional

import numpy as np
import pandas as pd

from indicators.atr import atr
from indicators.ma import ema


@dataclass
class TrendPullbackParams:
    """TrendPullback 策略参数"""
    # HTF (M15) 趋势参数
    htf_timeframe: str = "M15"  # 高时间周期
    ema50_period: int = 50
    ema200_period: int = 200

    # LTF (M5) 入场参数
    ltf_timeframe: str = "M5"  # 低时间周期
    ema20_period: int = 20
    atr_period: int = 14

    # 结构参数
    structure_lookback: int = 20  # 结构查找回溯
    pullback_depth_atr: float = 0.618  # 最大回撤深度 (ATR倍数)
    value_zone_atr: float = 0.3  # 价值区容差 (ATR倍数)
    require_break: bool = False  # 是否要求结构突破

    # 入场参数
    time_filter_entry: bool = True
    session: str = "us,overlap"  # 默认美盘+重叠

    # 出场参数 - 四层结构
    atr_sl_multi: float = 1.0  # 初始止损倍数
    partial_exit1_atr: float = 1.5  # L2 部分平仓阈值
    partial_exit1_ratio: float = 0.35  # L2 平仓比例
    trail_atr_multi: float = 2.5  # Trailing 距离
    enable_trailing: bool = True

    # 时间参数
    server_utc_offset: int = 2  # 服务器 UTC 偏移
    use_dst: bool = True
    dst_shift_hours: int = 1
    time_offset_hours: float = 0.0  # 数据时区偏移

    # 其他
    point: float = 0.0001


@dataclass
class PositionState:
    """持仓状态跟踪"""
    position: int = 0  # 1=多头, -1=空头, 0=空仓
    entry_price: float = 0.0
    entry_time: Optional[pd.Timestamp] = None
    initial_sl: float = 0.0
    atr_at_entry: float = 0.0
    partial1_done: bool = False
    recent_high: float = 0.0  # 结构高点
    recent_low: float = 0.0   # 结构低点


class TrendPullbackStrategy:
    """Trend Pullback 策略 Python 实现"""

    def __init__(self, params: TrendPullbackParams, progress_step: int = 0):
        self.params = params
        self.progress_step = progress_step
        self.last_diagnostics: dict[str, int | float] = {}
        self.last_signal_events: pd.Series | None = None
        self.last_signal_state: pd.Series | None = None

    def build_features(self, df: pd.DataFrame, df_htf: Optional[pd.DataFrame] = None) -> pd.DataFrame:
        """
        构建特征

        Args:
            df: 低时间周期数据 (M5)
            df_htf: 高时间周期数据 (M15)，可选
        """
        # LTF 指标
        ema20 = ema(df["close"], self.params.ema20_period)
        atr_series = atr(df, self.params.atr_period)

        # HTF 指标 (如果提供了 HTF 数据)
        ema50_htf = None
        ema200_htf = None
        if df_htf is not None and len(df_htf) > 0:
            ema50_htf = ema(df_htf["close"], self.params.ema50_period)
            ema200_htf = ema(df_htf["close"], self.params.ema200_period)

        features = pd.DataFrame({
            "close": df["close"],
            "high": df["high"],
            "low": df["low"],
            "open": df["open"],
            "ema20": ema20,
            "atr": atr_series,
        })

        # 将 HTF 指标对齐到 LTF
        if ema50_htf is not None and ema200_htf is not None:
            # 使用 forward fill 将 HTF 数据映射到 LTF
            features["ema50_htf"] = self._align_htf_to_ltf(df.index, df_htf.index, ema50_htf)
            features["ema200_htf"] = self._align_htf_to_ltf(df.index, df_htf.index, ema200_htf)

        return features

    def _align_htf_to_ltf(self, ltf_index: pd.DatetimeIndex, htf_index: pd.DatetimeIndex,
                          htf_series: pd.Series) -> pd.Series:
        """将 HTF 数据对齐到 LTF 时间戳"""
        # 创建 HTF 的 DataFrame
        htf_df = pd.DataFrame({"value": htf_series}, index=htf_index)
        # 重新采样到 LTF，使用 forward fill
        aligned = htf_df.reindex(ltf_index, method="ffill")
        return aligned["value"]

    def _time_filter_ok(self, ts: pd.Timestamp) -> bool:
        """时间过滤"""
        if self.params.time_offset_hours:
            ts = ts + pd.Timedelta(hours=self.params.time_offset_hours)

        # 转换为北京时间
        bj_hour = ts.hour

        # 时段定义（北京时间）
        asia_start, asia_end = 8, 16
        eu_start, eu_end = 15, 24
        us_start, us_end = 20, 4  # 跨午夜
        ov_start, ov_end = 20, 24

        # DST 调整
        if self.params.use_dst:
            eu_start = (eu_start + self.params.dst_shift_hours) % 24
            eu_end = (eu_end + self.params.dst_shift_hours) % 24
            us_start = (us_start + self.params.dst_shift_hours) % 24
            us_end = (us_end + self.params.dst_shift_hours) % 24
            ov_start = (ov_start + self.params.dst_shift_hours) % 24
            ov_end = (ov_end + self.params.dst_shift_hours) % 24

        def in_window(hour: int, start: int, end: int) -> bool:
            if start == end:
                return True
            if start <= end:
                return start <= hour < end
            return hour >= start or hour < end  # 跨午夜

        sessions = [s.strip().lower() for s in self.params.session.split(",")]

        for s in sessions:
            if s == "asia" and in_window(bj_hour, asia_start, asia_end):
                return True
            if s == "europe" and in_window(bj_hour, eu_start, eu_end):
                return True
            if s == "us" and in_window(bj_hour, us_start, us_end):
                return True
            if s == "overlap" and in_window(bj_hour, ov_start, ov_end):
                return True

        return False

    def _get_trend_state(self, ema50: float, ema200: float, price: float) -> int:
        """
        判断趋势状态

        Returns:
            1 = BULL, -1 = BEAR, 0 = FLAT
        """
        if pd.isna(ema50) or pd.isna(ema200):
            return 0

        if ema50 > ema200:
            return 1  # BULL
        elif ema50 < ema200:
            return -1  # BEAR
        return 0  # FLAT

    def _is_in_value_zone(self, price: float, ema20: float, atr: float, for_long: bool) -> bool:
        """判断是否在价值区（EMA20 附近）"""
        if pd.isna(ema20) or atr <= 0:
            return False

        tolerance = atr * self.params.value_zone_atr
        return abs(price - ema20) <= tolerance

    def _is_pullback_ended(self, df: pd.DataFrame, idx: int, for_long: bool) -> bool:
        """
        回撤结束确认

        核心：价格不再创新低/高 + 动能衰竭
        K线形态作为加分项
        """
        if idx < 8:
            return False

        # 动量衰竭检测
        momentum_weak = self._pullback_momentum_weak(df, idx, for_long)

        # K线形态（加分项）
        open1 = df["open"].iloc[idx - 1]
        close1 = df["close"].iloc[idx - 1]
        high1 = df["high"].iloc[idx - 1]
        low1 = df["low"].iloc[idx - 1]

        open2 = df["open"].iloc[idx - 2]
        close2 = df["close"].iloc[idx - 2]
        high2 = df["high"].iloc[idx - 2]
        low2 = df["low"].iloc[idx - 2]

        body1 = abs(close1 - open1)

        # 计算平均实体
        avg_body = 0.0
        for i in range(3, 8):
            avg_body += abs(df["close"].iloc[idx - i] - df["open"].iloc[idx - i])
        avg_body /= 5

        pattern_bonus = False

        if for_long:
            # 多头止跌形态
            bullish_engulf = (close1 > open1) and (open1 <= low2) and (close1 >= high2)
            small_body = (avg_body > 0) and (body1 < avg_body * 0.5)
            lower_wick = min(open1, close1) - low1
            hammer_like = lower_wick > body1 * 1.5 and lower_wick > 0
            pattern_bonus = bullish_engulf or (small_body and hammer_like)
        else:
            # 空头止涨形态
            bearish_engulf = (close1 < open1) and (open1 >= high2) and (close1 <= low2)
            small_body = (avg_body > 0) and (body1 < avg_body * 0.5)
            upper_wick = high1 - max(open1, close1)
            shooting_star = upper_wick > body1 * 1.5 and upper_wick > 0
            pattern_bonus = bearish_engulf or (small_body and shooting_star)

        return momentum_weak or pattern_bonus

    def _pullback_momentum_weak(self, df: pd.DataFrame, idx: int, for_long: bool) -> bool:
        """动量衰竭检测"""
        if idx < 3:
            return False

        if for_long:
            # 多头：不再创新低
            return df["low"].iloc[idx - 1] >= df["low"].iloc[idx - 2] or \
                   df["low"].iloc[idx - 2] >= df["low"].iloc[idx - 3]
        else:
            # 空头：不再创新高
            return df["high"].iloc[idx - 1] <= df["high"].iloc[idx - 2] or \
                   df["high"].iloc[idx - 2] <= df["high"].iloc[idx - 3]

    def _is_structure_break(self, df: pd.DataFrame, idx: int, for_long: bool) -> bool:
        """
        结构突破确认

        v3.2: 回撤策略不需要等待突破，检查"开始反弹"即可
        """
        if not self.params.require_break:
            return True

        close1 = df["close"].iloc[idx - 1]
        open1 = df["open"].iloc[idx - 1]
        close2 = df["close"].iloc[idx - 2]

        if for_long:
            return (close1 > open1) or (close1 > close2)
        else:
            return (close1 < open1) or (close1 < close2)

    def _find_swing_points(self, df: pd.DataFrame, idx: int, lookback: int) -> tuple[float, float]:
        """寻找波段高低点"""
        start = max(1, idx - lookback)
        swing_high = df["high"].iloc[start:idx].max()
        swing_low = df["low"].iloc[start:idx].min()
        return swing_high, swing_low

    def _has_long_exit_signal(self, state: PositionState, bid: float, atr: float,
                               ema20: float, recent_low: float) -> tuple[bool, bool]:
        """
        多头出场信号

        Returns:
            (exit_signal, partial_exit)
        """
        # L1: 防御止损
        if bid < recent_low:
            return True, False
        if state.initial_sl > 0 and bid <= state.initial_sl:
            return True, False

        # L2: 最小兑现（部分平仓）
        if not state.partial1_done and state.entry_price > 0 and atr > 0:
            profit_atr = (bid - state.entry_price) / atr
            if profit_atr >= self.params.partial_exit1_atr:
                return False, True  # 部分平仓

        # L3: 趋势持有（EMA20 跌破）
        if not pd.isna(ema20) and bid < ema20:
            return True, False

        return False, False

    def _has_short_exit_signal(self, state: PositionState, ask: float, atr: float,
                                ema20: float, recent_high: float) -> tuple[bool, bool]:
        """
        空头出场信号

        Returns:
            (exit_signal, partial_exit)
        """
        # L1: 防御止损
        if ask > recent_high:
            return True, False
        if state.initial_sl > 0 and ask >= state.initial_sl:
            return True, False

        # L2: 最小兑现（部分平仓）
        if not state.partial1_done and state.entry_price > 0 and atr > 0:
            profit_atr = (state.entry_price - ask) / atr
            if profit_atr >= self.params.partial_exit1_atr:
                return False, True

        # L3: 趋势持有（EMA20 突破）
        if not pd.isna(ema20) and ask > ema20:
            return True, False

        return False, False

    def generate_signals(
        self,
        df: pd.DataFrame,
        df_htf: Optional[pd.DataFrame] = None,
        diagnose: bool = False,
        debug_index: Optional[int] = None,
        debug_window: int = 2,
    ) -> pd.Series:
        """
        生成交易信号

        Args:
            df: 低时间周期数据 (M5)
            df_htf: 高时间周期数据 (M15)
            diagnose: 是否输出诊断信息
            debug_index: 调试的 K 线索引
            debug_window: 调试窗口大小

        Returns:
            pd.Series: 信号序列 (1=多头, -1=空头, 0=空仓)
        """
        diag: dict[str, int] = {}

        def bump(key: str, inc: int = 1) -> None:
            if not diagnose:
                return
            diag[key] = diag.get(key, 0) + inc

        # 构建特征
        features = self.build_features(df, df_htf)

        # 准备 HTF 指标
        ema50_htf = features.get("ema50_htf")
        ema200_htf = features.get("ema200_htf")

        signals = []
        events = []

        # 持仓状态
        state = PositionState()

        total = len(df.index)
        for idx, ts in enumerate(df.index):
            if self.progress_step and idx % self.progress_step == 0:
                print(f"[progress] {idx}/{total}", flush=True)

            bump("bars_total")

            # 获取当前值
            close = df["close"].iloc[idx]
            high = df["high"].iloc[idx]
            low = df["low"].iloc[idx]

            # 使用 shift(1) 避免未来数据
            close_prev = df["close"].iloc[idx - 1] if idx > 0 else np.nan
            high_prev = df["high"].iloc[idx - 1] if idx > 0 else np.nan
            low_prev = df["low"].iloc[idx - 1] if idx > 0 else np.nan

            ema20 = features["ema20"].iloc[idx - 1] if idx > 0 else np.nan
            atr_val = features["atr"].iloc[idx - 1] if idx > 0 else np.nan

            ema50_h = ema50_htf.iloc[idx - 1] if ema50_htf is not None and idx > 0 else np.nan
            ema200_h = ema200_htf.iloc[idx - 1] if ema200_htf is not None and idx > 0 else np.nan

            # 检查 NaN
            if any(pd.isna(v) for v in [close, high, low]):
                signals.append(state.position)
                events.append(None)
                continue

            bump("bars_valid")

            # 判断趋势状态
            trend_state = self._get_trend_state(ema50_h, ema200_h, close)

            # 寻找波段点
            swing_high, swing_low = self._find_swing_points(df, idx, self.params.structure_lookback)

            # ===== 出场逻辑 =====
            if state.position != 0:
                if state.position > 0:
                    exit_sig, partial_sig = self._has_long_exit_signal(
                        state, close, atr_val, ema20, state.recent_low
                    )
                else:
                    exit_sig, partial_sig = self._has_short_exit_signal(
                        state, close, atr_val, ema20, state.recent_high
                    )

                if exit_sig:
                    bump("exits")
                    state = PositionState()
                    events.append(0)
                    signals.append(0)
                    continue
                elif partial_sig:
                    # 部分平仓（简化处理：标记但不平仓）
                    state.partial1_done = True
                    bump("partial_exits")

            # ===== 入场逻辑 =====
            if state.position == 0:
                # 时间过滤
                if self.params.time_filter_entry and not self._time_filter_ok(ts):
                    bump("time_blocked")
                    signals.append(0)
                    events.append(None)
                    continue

                bump("time_ok")

                # ATR 检查
                if pd.isna(atr_val) or atr_val <= 0:
                    signals.append(0)
                    events.append(None)
                    continue

                # 多头入场
                if trend_state == 1:  # BULL
                    bump("trend_bull")

                    # 回撤深度限制
                    if swing_high > 0:
                        pullback_depth = swing_high - close
                        if pullback_depth > atr_val * self.params.pullback_depth_atr:
                            bump("pullback_too_deep")
                            signals.append(0)
                            events.append(None)
                            continue

                    # 价值区检查
                    if self._is_in_value_zone(close, ema20, atr_val, True):
                        bump("in_value_zone")

                        # 回撤结束确认
                        if self._is_pullback_ended(df, idx, True):
                            bump("pullback_ended")

                            # 结构突破
                            if self._is_structure_break(df, idx, True):
                                bump("structure_break")

                                # 入场
                                bump("long_entries")
                                state = PositionState(
                                    position=1,
                                    entry_price=close,
                                    entry_time=ts,
                                    initial_sl=close - atr_val * self.params.atr_sl_multi,
                                    atr_at_entry=atr_val,
                                    recent_high=swing_high,
                                    recent_low=swing_low,
                                )
                                events.append(1)
                                signals.append(1)
                                continue

                # 空头入场
                elif trend_state == -1:  # BEAR
                    bump("trend_bear")

                    # 回撤深度限制
                    if swing_low > 0 and swing_low < float("inf"):
                        pullback_depth = close - swing_low
                        if pullback_depth > atr_val * self.params.pullback_depth_atr:
                            bump("pullback_too_deep")
                            signals.append(0)
                            events.append(None)
                            continue

                    # 价值区检查
                    if self._is_in_value_zone(close, ema20, atr_val, False):
                        bump("in_value_zone")

                        # 回撤结束确认
                        if self._is_pullback_ended(df, idx, False):
                            bump("pullback_ended")

                            # 结构突破
                            if self._is_structure_break(df, idx, False):
                                bump("structure_break")

                                # 入场
                                bump("short_entries")
                                state = PositionState(
                                    position=-1,
                                    entry_price=close,
                                    entry_time=ts,
                                    initial_sl=close + atr_val * self.params.atr_sl_multi,
                                    atr_at_entry=atr_val,
                                    recent_high=swing_high,
                                    recent_low=swing_low,
                                )
                                events.append(-1)
                                signals.append(-1)
                                continue

            events.append(None)
            signals.append(state.position)

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
