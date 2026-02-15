"""
Market Quality - 市场质量指标

计算：
- efficiency: 市场效率 (价格变动 / 总波幅)
- false_breakout_rate: 假突破率
- adx: ADX 趋势强度
- q_score: 综合质量分数 [0, 1]

公式（v2.3.0）：
Q = 0.5 + eff_score + fbr_score + adx_score
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional, Dict

import numpy as np
import pandas as pd


@dataclass
class MarketQualityParams:
    """市场质量参数"""
    # 效率计算
    efficiency_period: int = 20  # 效率计算窗口
    
    # 假突破检测
    breakout_lookback: int = 5   # 突破回看周期
    breakout_threshold: float = 0.3  # 假突破定义
    false_breakout_window: int = 30  # 假突破率计算窗口
    
    # Q_score 基准值
    efficiency_baseline: float = 0.10  # 效率基准（震荡市正常水平）
    fbr_baseline: float = 0.40         # 假突破率基准（震荡市正常水平）
    adx_baseline: float = 25.0         # ADX 基准（趋势分界线）
    
    # Q_score 权重
    weight_eff: float = 0.25   # 效率权重
    weight_fbr: float = 0.25   # 假突破率权重
    weight_adx: float = 0.20   # ADX 权重
    
    # 阈值
    q_score_threshold: float = 0.5  # Q < 0.5 → STANDBY


@dataclass
class QualityData:
    """市场质量数据"""
    efficiency: float = 0.5
    false_breakout_rate: float = 0.0
    adx: float = 25.0
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
        adx: Optional[pd.Series] = None,
    ) -> pd.DataFrame:
        """
        计算市场质量指标
        
        Args:
            df: OHLCV DataFrame
            adx: ADX 序列（可选，如果不提供则计算）
            
        Returns:
            DataFrame with quality columns:
            - efficiency: 市场效率
            - false_breakout_rate: 假突破率
            - adx: ADX 值
            - q_score: 综合质量分数
            - is_tradable: 是否可交易
        """
        result = pd.DataFrame(index=df.index)
        
        # 计算市场效率
        result["efficiency"] = self._calculate_efficiency(df)
        
        # 计算假突破率
        result["false_breakout_rate"] = self._calculate_false_breakout_rate(df)
        
        # 计算 ADX（如果未提供）
        if adx is not None:
            result["adx"] = adx
        else:
            result["adx"] = self._calculate_adx(df)
        
        # 计算综合 Q_score
        result["q_score"] = self._calculate_q_score(result)
        
        # 判断是否可交易
        result["is_tradable"] = result["q_score"] >= self.params.q_score_threshold
        
        return result
    
    def _calculate_efficiency(self, df: pd.DataFrame) -> pd.Series:
        """
        计算市场效率
        
        效率 = |价格净变动| / 总波幅
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
        
        return efficiency.fillna(0.15).clip(0.0, 1.0)
    
    def _calculate_false_breakout_rate(self, df: pd.DataFrame) -> pd.Series:
        """
        计算假突破率
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
        
        return false_rate.fillna(0.4).clip(0.0, 1.0)
    
    def _calculate_adx(self, df: pd.DataFrame, period: int = 14) -> pd.Series:
        """
        计算 ADX 指标
        """
        high = df["high"]
        low = df["low"]
        close = df["close"]
        
        # +DM 和 -DM
        plus_dm = high.diff()
        minus_dm = -low.diff()
        
        plus_dm = plus_dm.where((plus_dm > minus_dm) & (plus_dm > 0), 0.0)
        minus_dm = minus_dm.where((minus_dm > plus_dm) & (minus_dm > 0), 0.0)
        
        # True Range
        tr1 = high - low
        tr2 = (high - close.shift()).abs()
        tr3 = (low - close.shift()).abs()
        tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
        
        # 平滑
        atr = tr.ewm(alpha=1.0 / period, adjust=False).mean()
        plus_di = 100 * (plus_dm.ewm(alpha=1.0 / period, adjust=False).mean() / (atr + 1e-10))
        minus_di = 100 * (minus_dm.ewm(alpha=1.0 / period, adjust=False).mean() / (atr + 1e-10))
        
        # DX 和 ADX
        dx = 100 * ((plus_di - minus_di).abs() / (plus_di + minus_di + 1e-10))
        adx = dx.ewm(alpha=1.0 / period, adjust=False).mean()
        
        return adx.fillna(25.0).clip(0.0, 100.0)
    
    def _calculate_q_score(self, metrics: pd.DataFrame) -> pd.Series:
        """
        计算综合质量分数（v2.3.0 公式）
        
        Q = 0.5 + eff_score + fbr_score + adx_score
        """
        p = self.params
        
        # 效率贡献：高于基准加分，低于基准减分
        eff_score = p.weight_eff * (metrics["efficiency"] / p.efficiency_baseline - 1.0)
        
        # 假突破惩罚：低于基准加分，高于基准减分
        fbr_score = p.weight_fbr * (p.fbr_baseline - metrics["false_breakout_rate"]) / p.fbr_baseline
        
        # ADX 贡献：高于基准（趋势市）加分
        # 归一化：ADX 25 → 0, ADX 40 → 0.6, ADX 50 → 1.0
        adx_normalized = ((metrics["adx"] - p.adx_baseline) / 25.0).clip(0.0, 1.0)
        adx_score = p.weight_adx * adx_normalized
        
        # 综合分数
        q_score = 0.5 + eff_score + fbr_score + adx_score
        
        return q_score.clip(0.1, 0.9)
    
    def get_current_quality(
        self, 
        df: pd.DataFrame,
        adx: Optional[pd.Series] = None,
    ) -> QualityData:
        """获取当前最新的质量数据"""
        result = self.calculate(df, adx)
        
        if len(result) == 0:
            return QualityData()
        
        last = result.iloc[-1]
        
        return QualityData(
            efficiency=float(last["efficiency"]),
            false_breakout_rate=float(last["false_breakout_rate"]),
            adx=float(last["adx"]),
            q_score=float(last["q_score"]),
            is_tradable=bool(last["is_tradable"])
        )
    
    def get_feature_contributions(self, metrics: pd.DataFrame) -> pd.DataFrame:
        """
        获取各特征的贡献分数（用于分析）
        """
        p = self.params
        
        result = pd.DataFrame(index=metrics.index)
        
        result["eff_score"] = p.weight_eff * (metrics["efficiency"] / p.efficiency_baseline - 1.0)
        result["fbr_score"] = p.weight_fbr * (p.fbr_baseline - metrics["false_breakout_rate"]) / p.fbr_baseline
        result["adx_score"] = p.weight_adx * ((metrics["adx"] - p.adx_baseline) / 25.0).clip(0.0, 1.0)
        
        return result
