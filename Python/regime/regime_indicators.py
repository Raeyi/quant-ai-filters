"""
Regime Indicators - 市场状态指标

计算：
- trend_strength: 趋势强度 [0, 1]
- volatility_state: 波动率状态 (LOW/NORMAL/HIGH)
- regime_type: 基础状态类型 (TREND/RANGE)
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Optional

import numpy as np
import pandas as pd


class VolatilityState(Enum):
    """波动率状态"""
    LOW = "low"
    NORMAL = "normal"
    HIGH = "high"


class RegimeType(Enum):
    """基础市场状态"""
    TREND = "trend"
    RANGE = "range"


class TrendDirection(Enum):
    """趋势方向（与 MQL5 统一）"""
    NONE = 0   # 无趋势/震荡
    BULL = 1   # 多头
    BEAR = -1  # 空头


@dataclass
class RegimeParams:
    """Regime 指标参数"""
    # ADX 参数
    adx_period: int = 14
    adx_trend_threshold: float = 25.0  # ADX > 25 认为有趋势
    adx_strong_threshold: float = 40.0  # ADX > 40 强趋势
    
    # 波动率参数
    atr_period: int = 14
    vol_low_percentile: float = 25.0  # 低于此百分位 = 低波动
    vol_high_percentile: float = 75.0  # 高于此百分位 = 高波动
    vol_lookback: int = 100  # 波动率百分位计算窗口
    
    # 趋势确认参数
    ema_fast: int = 20
    ema_slow: int = 50
    trend_slope_period: int = 10  # 趋势斜率计算周期


@dataclass
class RegimeData:
    """Regime 指标数据"""
    adx: float = 0.0
    trend_strength: float = 0.0  # [0, 1]
    volatility: float = 0.0
    volatility_state: VolatilityState = VolatilityState.NORMAL
    regime_type: RegimeType = RegimeType.RANGE
    trend_direction: TrendDirection = TrendDirection.NONE


class RegimeIndicators:
    """市场状态指标计算器"""
    
    def __init__(self, params: Optional[RegimeParams] = None):
        self.params = params or RegimeParams()
        self._cache: dict = {}
    
    def calculate(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        计算 Regime 指标
        
        Args:
            df: OHLCV DataFrame
            
        Returns:
            DataFrame with regime columns:
            - adx: ADX 值
            - trend_strength: 趋势强度 [0, 1]
            - volatility: ATR 值
            - volatility_state: 波动率状态
            - regime_type: 市场状态类型
            - trend_direction: 趋势方向
        """
        result = pd.DataFrame(index=df.index)
        
        # 计算 ADX
        adx_data = self._calculate_adx(df)
        result["adx"] = adx_data["adx"]
        result["plus_di"] = adx_data["plus_di"]
        result["minus_di"] = adx_data["minus_di"]
        
        # 计算趋势强度 (基于 ADX)
        result["trend_strength"] = self._calculate_trend_strength(result["adx"])
        
        # 计算波动率
        result["volatility"] = self._calculate_atr(df)
        result["volatility_state"] = self._classify_volatility(result["volatility"])
        
        # 判断市场状态
        result["regime_type"] = self._classify_regime(result["trend_strength"])
        
        # 判断趋势方向
        result["trend_direction"] = self._calculate_trend_direction(
            df, result["plus_di"], result["minus_di"]
        )
        
        return result
    
    def _calculate_adx(self, df: pd.DataFrame) -> pd.DataFrame:
        """计算 ADX 指标"""
        high = df["high"]
        low = df["low"]
        close = df["close"]
        period = self.params.adx_period
        
        # +DM 和 -DM
        up_move = high - high.shift(1)
        down_move = low.shift(1) - low
        
        plus_dm = pd.Series(np.where((up_move > down_move) & (up_move > 0), up_move, 0.0), index=df.index)
        minus_dm = pd.Series(np.where((down_move > up_move) & (down_move > 0), down_move, 0.0), index=df.index)
        
        # True Range
        tr = pd.concat([
            (high - low).abs(),
            (high - close.shift(1)).abs(),
            (low - close.shift(1)).abs()
        ], axis=1).max(axis=1)
        
        # 平滑
        atr = tr.ewm(alpha=1.0 / period, adjust=False).mean()
        plus_di = 100.0 * plus_dm.ewm(alpha=1.0 / period, adjust=False).mean() / (atr + 1e-10)
        minus_di = 100.0 * minus_dm.ewm(alpha=1.0 / period, adjust=False).mean() / (atr + 1e-10)
        
        # DX 和 ADX
        dx = 100.0 * (plus_di - minus_di).abs() / (plus_di + minus_di + 1e-10)
        adx = dx.ewm(alpha=1.0 / period, adjust=False).mean()
        
        return pd.DataFrame({
            "adx": adx,
            "plus_di": plus_di,
            "minus_di": minus_di
        }, index=df.index)
    
    def _calculate_trend_strength(self, adx: pd.Series) -> pd.Series:
        """
        将 ADX 转换为趋势强度 [0, 1]
        
        ADX < 20: 无趋势 → 0.0 ~ 0.2
        ADX 20-25: 趋势形成 → 0.2 ~ 0.4
        ADX 25-40: 有趋势 → 0.4 ~ 0.7
        ADX > 40: 强趋势 → 0.7 ~ 1.0
        """
        strength = pd.Series(0.0, index=adx.index)
        
        # 分段线性映射
        strength = np.where(
            adx < 20,
            adx / 100.0,  # 0 ~ 0.2
            np.where(
                adx < 25,
                0.2 + (adx - 20) * 0.04,  # 0.2 ~ 0.4
                np.where(
                    adx < 40,
                    0.4 + (adx - 25) * 0.02,  # 0.4 ~ 0.7
                    0.7 + (adx - 40) * 0.01  # 0.7 ~ 1.0+
                )
            )
        )
        
        return pd.Series(np.clip(strength, 0.0, 1.0), index=adx.index)
    
    def _calculate_atr(self, df: pd.DataFrame) -> pd.Series:
        """计算 ATR"""
        high = df["high"]
        low = df["low"]
        close = df["close"]
        
        tr = pd.concat([
            (high - low).abs(),
            (high - close.shift(1)).abs(),
            (low - close.shift(1)).abs()
        ], axis=1).max(axis=1)
        
        return tr.ewm(alpha=1.0 / self.params.atr_period, adjust=False).mean()
    
    def _classify_volatility(self, atr: pd.Series) -> pd.Series:
        """
        分类波动率状态
        
        使用滚动百分位动态判断
        """
        # 计算滚动百分位
        atr_rank = atr.rolling(self.params.vol_lookback, min_periods=20).apply(
            lambda x: pd.Series(x).rank(pct=True).iloc[-1] * 100,
            raw=False
        )
        
        # 分类
        state = pd.Series(VolatilityState.NORMAL, index=atr.index)
        state = state.where(atr_rank >= self.params.vol_low_percentile, VolatilityState.LOW)
        state = state.where(atr_rank <= self.params.vol_high_percentile, VolatilityState.HIGH)
        
        return state
    
    def _classify_regime(self, trend_strength: pd.Series) -> pd.Series:
        """
        判断市场状态类型
        
        trend_strength > 0.4 → TREND
        否则 → RANGE
        """
        regime = pd.Series(RegimeType.RANGE, index=trend_strength.index)
        regime = regime.where(trend_strength <= 0.4, RegimeType.TREND)
        return regime
    
    def _calculate_trend_direction(
        self,
        df: pd.DataFrame,
        plus_di: pd.Series,
        minus_di: pd.Series
    ) -> pd.Series:
        """
        判断趋势方向

        Returns:
            TrendDirection 枚举 Series
        """
        direction = pd.Series(TrendDirection.NONE, index=df.index)

        # 基于 DI 差值判断
        di_diff = plus_di - minus_di

        direction = direction.where(di_diff <= 5, TrendDirection.BULL)
        direction = direction.where(di_diff >= -5, TrendDirection.BEAR)

        return direction

    def get_current_regime(self, df: pd.DataFrame) -> RegimeData:
        """获取当前最新的 Regime 数据"""
        result = self.calculate(df)

        if len(result) == 0:
            return RegimeData()

        last = result.iloc[-1]

        # 转换 trend_direction 为枚举
        trend_dir = last["trend_direction"]
        if isinstance(trend_dir, TrendDirection):
            trend_direction = trend_dir
        else:
            trend_direction = TrendDirection(int(trend_dir))

        return RegimeData(
            adx=float(last["adx"]),
            trend_strength=float(last["trend_strength"]),
            volatility=float(last["volatility"]),
            volatility_state=last["volatility_state"],
            regime_type=last["regime_type"],
            trend_direction=trend_direction
        )
