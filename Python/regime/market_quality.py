"""
Market Quality - 市场质量指标

计算：
- efficiency: 市场效率 (价格变动 / 总波幅)
- false_breakout_rate: 假突破率
- q_score: 综合质量分数 [0, 1]
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

import numpy as np
import pandas as pd


@dataclass
class MarketQualityParams:
    """市场质量参数"""
    # 效率计算
    efficiency_period: int = 20  # 效率计算窗口
    
    # 假突破检测
    breakout_lookback: int = 5   # 突破回看周期
    breakout_threshold: float = 0.3  # 假突破定义：回撤超过突破幅度的30%
    false_breakout_window: int = 30  # 假突破率计算窗口
    
    # Q_score 权重
    efficiency_weight: float = 0.4
    breakout_weight: float = 0.3
    spread_weight: float = 0.15
    momentum_weight: float = 0.15
    
    # 最低质量阈值
    q_score_threshold: float = 0.5  # Q < 0.5 → STANDBY


@dataclass
class QualityData:
    """市场质量数据"""
    efficiency: float = 0.5
    false_breakout_rate: float = 0.0
    spread_ratio: float = 0.0
    momentum_quality: float = 0.5
    q_score: float = 0.5
    is_tradable: bool = True  # q_score >= threshold


class MarketQuality:
    """市场质量计算器"""
    
    def __init__(self, params: Optional[MarketQualityParams] = None):
        self.params = params or MarketQualityParams()
        self._breakout_history: list = []
    
    def calculate(
        self, 
        df: pd.DataFrame,
        regime_data: Optional[pd.DataFrame] = None
    ) -> pd.DataFrame:
        """
        计算市场质量指标
        
        Args:
            df: OHLCV DataFrame
            regime_data: Regime 指标数据 (可选，用于增强判断)
            
        Returns:
            DataFrame with quality columns:
            - efficiency: 市场效率
            - false_breakout_rate: 假突破率
            - spread_ratio: 点差比率 (如果有)
            - momentum_quality: 动量质量
            - q_score: 综合质量分数
            - is_tradable: 是否可交易
        """
        result = pd.DataFrame(index=df.index)
        
        # 计算市场效率
        result["efficiency"] = self._calculate_efficiency(df)
        
        # 计算假突破率
        result["false_breakout_rate"] = self._calculate_false_breakout_rate(df)
        
        # 计算动量质量
        result["momentum_quality"] = self._calculate_momentum_quality(df)
        
        # 点差比率 (模拟，实际需要真实点差数据)
        result["spread_ratio"] = self._estimate_spread_ratio(df)
        
        # 计算综合 Q_score
        result["q_score"] = self._calculate_q_score(result)
        
        # 判断是否可交易
        result["is_tradable"] = result["q_score"] >= self.params.q_score_threshold
        
        return result
    
    def _calculate_efficiency(self, df: pd.DataFrame) -> pd.Series:
        """
        计算市场效率
        
        效率 = |价格净变动| / 总波幅
        
        高效率 (>0.6): 趋势明确，价格单方向移动
        中效率 (0.3-0.6): 有一定趋势
        低效率 (<0.3): 震荡，价格来回波动
        """
        period = self.params.efficiency_period
        
        close = df["close"]
        high = df["high"]
        low = df["low"]
        
        # 净变动 (绝对值)
        net_change = (close - close.shift(period)).abs()
        
        # 总波幅
        total_range = (high - low).rolling(period).sum()
        
        # 效率
        efficiency = net_change / (total_range + 1e-10)
        
        # 额外因子：方向一致性
        direction_consistency = self._calculate_direction_consistency(df, period)
        
        # 综合效率
        combined_efficiency = 0.6 * efficiency + 0.4 * direction_consistency
        
        return combined_efficiency.clip(0.0, 1.0)
    
    def _calculate_direction_consistency(
        self, 
        df: pd.DataFrame, 
        period: int
    ) -> pd.Series:
        """
        计算方向一致性
        
        连续同向K线比例
        """
        close = df["close"]
        
        # 计算每根K线的方向
        bar_direction = np.sign(close.diff())
        
        # 滚动计算同向比例
        def consistency_score(window):
            if len(window) < 2:
                return 0.5
            # 取众数方向
            pos_count = (window > 0).sum()
            neg_count = (window < 0).sum()
            total = pos_count + neg_count
            if total == 0:
                return 0.5
            return max(pos_count, neg_count) / total
        
        consistency = bar_direction.rolling(period).apply(consistency_score, raw=False)
        
        return consistency.fillna(0.5)
    
    def _calculate_false_breakout_rate(self, df: pd.DataFrame) -> pd.Series:
        """
        计算假突破率
        
        检测最近N根K线内的假突破比例
        
        假突破定义：
        1. 价格突破前高/前低
        2. 但收盘价回到突破区间内
        3. 或回撤超过突破幅度的30%
        """
        lookback = self.params.breakout_lookback
        window = self.params.false_breakout_window
        
        high = df["high"]
        low = df["low"]
        close = df["close"]
        
        # 前期高低点
        prev_high = high.shift(1).rolling(lookback).max()
        prev_low = low.shift(1).rolling(lookback).min()
        
        # 突破检测
        breakout_up = high > prev_high
        breakout_down = low < prev_low
        
        # 假突破检测
        false_up = breakout_up & (close < prev_high)
        false_down = breakout_down & (close > prev_low)
        
        # 计算假突破率
        total_breakouts = (breakout_up | breakout_down).astype(int)
        false_breakouts = (false_up | false_down).astype(int)
        
        # 滚动计算假突破率
        false_rate = false_breakouts.rolling(window, min_periods=5).sum() / \
                     (total_breakouts.rolling(window, min_periods=5).sum() + 1e-10)
        
        return false_rate.fillna(0.3).clip(0.0, 1.0)
    
    def _calculate_momentum_quality(self, df: pd.DataFrame) -> pd.Series:
        """
        计算动量质量
        
        基于 RSI 偏离度和动量持续性
        """
        close = df["close"]
        
        # RSI (14)
        delta = close.diff()
        gain = delta.where(delta > 0, 0.0)
        loss = (-delta).where(delta < 0, 0.0)
        
        avg_gain = gain.ewm(alpha=1.0 / 14, adjust=False).mean()
        avg_loss = loss.ewm(alpha=1.0 / 14, adjust=False).mean()
        
        rs = avg_gain / (avg_loss + 1e-10)
        rsi = 100.0 - (100.0 / (1.0 + rs))
        
        # RSI 质量：距离中性的距离
        # RSI 在 40-60 之间表示低动量质量
        # RSI 极端值表示高动量质量
        rsi_quality = pd.Series(0.5, index=df.index)
        
        # RSI > 60 或 RSI < 40 表示有动量
        rsi_quality = np.where(rsi > 60, 0.5 + (rsi - 60) / 80.0, rsi_quality)
        rsi_quality = np.where(rsi < 40, 0.5 + (40 - rsi) / 80.0, rsi_quality)
        
        # 动量持续性
        momentum = close.diff()
        momentum_sign = np.sign(momentum)
        momentum_persistence = momentum_sign.rolling(10).apply(
            lambda x: abs(x.mean()) if len(x) > 0 else 0.0,
            raw=False
        ).fillna(0.0)
        
        # 综合
        quality = 0.7 * pd.Series(rsi_quality, index=df.index) + 0.3 * momentum_persistence
        
        return quality.clip(0.0, 1.0)
    
    def _estimate_spread_ratio(self, df: pd.DataFrame) -> pd.Series:
        """
        估计点差比率
        
        实际项目中应使用真实点差数据
        这里使用 OHLC 估算
        """
        # 使用 (high - low) / close 作为波动率代理
        # 高波动时点差通常更大
        volatility_ratio = (df["high"] - df["low"]) / df["close"]
        
        # 归一化
        spread_ratio = volatility_ratio.rolling(20).apply(
            lambda x: (x.iloc[-1] - x.min()) / (x.max() - x.min() + 1e-10) if len(x) > 0 else 0.0,
            raw=False
        )
        
        return spread_ratio.fillna(0.5).clip(0.0, 1.0)
    
    def _calculate_q_score(self, metrics: pd.DataFrame) -> pd.Series:
        """
        计算综合质量分数
        
        Q = w1 * efficiency + w2 * (1 - false_breakout_rate) + w3 * (1 - spread_ratio) + w4 * momentum
        """
        p = self.params
        
        # 假突破率反向 (低假突破率 = 高质量)
        breakout_quality = 1.0 - metrics["false_breakout_rate"]
        
        # 点差反向 (低点差 = 高质量)
        spread_quality = 1.0 - metrics["spread_ratio"]
        
        q_score = (
            p.efficiency_weight * metrics["efficiency"] +
            p.breakout_weight * breakout_quality +
            p.spread_weight * spread_quality +
            p.momentum_weight * metrics["momentum_quality"]
        )
        
        return q_score.clip(0.0, 1.0)
    
    def get_current_quality(
        self, 
        df: pd.DataFrame,
        regime_data: Optional[pd.DataFrame] = None
    ) -> QualityData:
        """获取当前最新的质量数据"""
        result = self.calculate(df, regime_data)
        
        if len(result) == 0:
            return QualityData()
        
        last = result.iloc[-1]
        
        return QualityData(
            efficiency=float(last["efficiency"]),
            false_breakout_rate=float(last["false_breakout_rate"]),
            spread_ratio=float(last["spread_ratio"]),
            momentum_quality=float(last["momentum_quality"]),
            q_score=float(last["q_score"]),
            is_tradable=bool(last["is_tradable"])
        )
