"""
Regime Sub-Type Classification - 市场状态细分

Phase 2 功能：
细分市场状态以提供更精确的策略选择

Sub-Type 定义：
- T+V-A (情绪脉冲): TREND + HIGH_VOL + LOW_EFFICIENCY → 短暂趋势，容易反转
- T+V-B (真趋势): TREND + HIGH_VOL + HIGH_EFFICIENCY → 持续趋势，顺势交易
- R+V-A (消息震荡): RANGE + HIGH_VOL + HIGH_REVERSAL → 剧烈震荡，观望为主
- R+V-B (假突破密集): RANGE + HIGH_FALSE_BREAKOUT → 频繁假突破，减少交易
- R+N (正常震荡): RANGE + NORMAL_VOL → 可做均值回归
- T+N (温和趋势): TREND + NORMAL_VOL → 可顺势交易
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Optional

import numpy as np
import pandas as pd

from regime.regime_indicators import RegimeType, VolatilityState


class RegimeSubType(Enum):
    """Regime 细分类型"""
    # 趋势类
    TVA_EMOTION_PULSE = "T+V-A"      # 情绪脉冲：高波动趋势 + 低效率
    TVB_TRUE_TREND = "T+V-B"          # 真趋势：高波动趋势 + 高效率
    TN_MILD_TREND = "T+N"             # 温和趋势：正常波动趋势
    
    # 震荡类
    RVA_NEWS_CHOP = "R+V-A"           # 消息震荡：高波动震荡 + 高反转
    RVB_FALSE_BREAKOUT = "R+V-B"      # 假突破密集：高假突破率
    RN_NORMAL_RANGE = "R+N"           # 正常震荡：可做均值回归
    RL_LOW_VOL_RANGE = "R+L"          # 低波动震荡：极少交易

    # 默认
    UNKNOWN = "UNKNOWN"


@dataclass
class SubTypeParams:
    """Sub-Type 分类参数"""
    # 效率阈值
    efficiency_high_threshold: float = 0.5   # 高效率阈值
    efficiency_low_threshold: float = 0.3    # 低效率阈值
    
    # 反转率阈值
    reversal_high_threshold: float = 0.4     # 高反转率阈值
    
    # 假突破率阈值
    false_breakout_high_threshold: float = 0.35  # 高假突破率阈值
    
    # 趋势强度阈值
    trend_strong_threshold: float = 0.5      # 强趋势阈值
    trend_weak_threshold: float = 0.3        # 弱趋势阈值


@dataclass
class SubTypeData:
    """Sub-Type 数据"""
    sub_type: RegimeSubType = RegimeSubType.UNKNOWN
    
    # 特征值
    efficiency: float = 0.5
    reversal_rate: float = 0.0
    false_breakout_rate: float = 0.0
    
    # 推荐操作
    recommended_action: str = "observe"      # observe, trend_follow, mean_revert, standby
    scale_multiplier: float = 1.0            # 仓位缩放
    preferred_strategies: list = None
    
    # 风险参数调整
    sl_multiplier: float = 1.0               # 止损乘数
    tp_multiplier: float = 1.0               # 止盈乘数
    max_positions: int = 1                    # 最大持仓数
    
    def __post_init__(self):
        if self.preferred_strategies is None:
            self.preferred_strategies = []


class RegimeSubTypeClassifier:
    """Regime Sub-Type 分类器"""
    
    def __init__(self, params: Optional[SubTypeParams] = None):
        self.params = params or SubTypeParams()
    
    def classify(
        self,
        regime_df: pd.DataFrame,
        quality_df: pd.DataFrame
    ) -> pd.DataFrame:
        """
        分类 Regime Sub-Type
        
        Args:
            regime_df: Regime 指标 DataFrame (来自 RegimeIndicators)
            quality_df: 质量 DataFrame (来自 MarketQuality)
            
        Returns:
            DataFrame with columns:
            - sub_type: RegimeSubType
            - reversal_rate: 反转率
            - recommended_action: 推荐操作
            - scale_multiplier: 仓位缩放
            - preferred_strategies: 推荐策略
            - sl_multiplier: 止损乘数
            - tp_multiplier: 止盈乘数
            - max_positions: 最大持仓数
        """
        result = pd.DataFrame(index=regime_df.index)
        
        # 计算反转率
        result["reversal_rate"] = self._calculate_reversal_rate(
            regime_df["trend_direction"]
        )
        
        # Sub-Type 分类
        sub_types = []
        actions = []
        scales = []
        strategies = []
        sl_mults = []
        tp_mults = []
        max_pos = []
        
        for i in range(len(regime_df)):
            row_data = {
                "regime_type": regime_df["regime_type"].iloc[i],
                "volatility_state": regime_df["volatility_state"].iloc[i],
                "trend_strength": regime_df["trend_strength"].iloc[i],
                "efficiency": quality_df["efficiency"].iloc[i],
                "false_breakout_rate": quality_df["false_breakout_rate"].iloc[i],
                "reversal_rate": result["reversal_rate"].iloc[i],
            }
            
            sub_type, config = self._classify_single(row_data)
            
            sub_types.append(sub_type)
            actions.append(config["action"])
            scales.append(config["scale"])
            strategies.append(config["strategies"])
            sl_mults.append(config["sl_mult"])
            tp_mults.append(config["tp_mult"])
            max_pos.append(config["max_positions"])
        
        result["sub_type"] = sub_types
        result["recommended_action"] = actions
        result["scale_multiplier"] = pd.Series(scales, index=result.index)
        result["preferred_strategies"] = strategies
        result["sl_multiplier"] = pd.Series(sl_mults, index=result.index)
        result["tp_multiplier"] = pd.Series(tp_mults, index=result.index)
        result["max_positions"] = pd.Series(max_pos, index=result.index)
        
        return result
    
    def _calculate_reversal_rate(self, trend_direction: pd.Series) -> pd.Series:
        """
        计算反转率
        
        反转率 = 近期趋势方向变化的频率
        """
        # 计算方向变化
        direction_change = (trend_direction != trend_direction.shift(1)).astype(int)
        
        # 计算滚动反转率
        reversal_rate = direction_change.rolling(20, min_periods=5).mean()
        
        return reversal_rate.fillna(0.0)
    
    def _classify_single(self, data: dict) -> tuple:
        """
        分类单个数据点
        
        Returns:
            (sub_type, config_dict)
        """
        regime = data["regime_type"]
        vol = data["volatility_state"]
        trend_str = data["trend_strength"]
        eff = data["efficiency"]
        fbr = data["false_breakout_rate"]
        rev = data["reversal_rate"]
        
        p = self.params
        
        # 默认配置
        default_config = {
            "action": "observe",
            "scale": 0.5,
            "strategies": [],
            "sl_mult": 1.0,
            "tp_mult": 1.0,
            "max_positions": 1,
        }
        
        # 趋势状态分类
        if regime == RegimeType.TREND:
            if vol == VolatilityState.HIGH:
                if eff < p.efficiency_low_threshold:
                    # T+V-A: 情绪脉冲 - 高波动趋势但效率低
                    return RegimeSubType.TVA_EMOTION_PULSE, {
                        "action": "cautious_trend",
                        "scale": 0.6,
                        "strategies": ["TrendPullback"],
                        "sl_mult": 1.3,  # 放宽止损
                        "tp_mult": 0.8,  # 快速止盈
                        "max_positions": 1,
                    }
                elif eff > p.efficiency_high_threshold:
                    # T+V-B: 真趋势 - 高波动 + 高效率
                    return RegimeSubType.TVB_TRUE_TREND, {
                        "action": "trend_follow",
                        "scale": 1.2,
                        "strategies": ["TrendPullback"],
                        "sl_mult": 1.0,
                        "tp_mult": 1.2,  # 扩大止盈
                        "max_positions": 2,
                    }
                else:
                    # 中等效率的趋势
                    return RegimeSubType.TN_MILD_TREND, {
                        "action": "trend_follow",
                        "scale": 0.8,
                        "strategies": ["TrendPullback"],
                        "sl_mult": 1.1,
                        "tp_mult": 1.0,
                        "max_positions": 1,
                    }
            else:
                # 正常波动的趋势
                if trend_str > p.trend_strong_threshold:
                    return RegimeSubType.TN_MILD_TREND, {
                        "action": "trend_follow",
                        "scale": 1.0,
                        "strategies": ["TrendPullback"],
                        "sl_mult": 1.0,
                        "tp_mult": 1.0,
                        "max_positions": 2,
                    }
                else:
                    # 弱趋势，可能转震荡
                    return RegimeSubType.TN_MILD_TREND, {
                        "action": "cautious_trend",
                        "scale": 0.7,
                        "strategies": ["BollMR"],  # 可做轻仓回归
                        "sl_mult": 1.0,
                        "tp_mult": 0.9,
                        "max_positions": 1,
                    }
        
        # 震荡状态分类
        else:  # RANGE
            if vol == VolatilityState.HIGH:
                if rev > p.reversal_high_threshold:
                    # R+V-A: 消息震荡 - 高波动 + 高反转
                    return RegimeSubType.RVA_NEWS_CHOP, {
                        "action": "standby",
                        "scale": 0.3,
                        "strategies": [],
                        "sl_mult": 1.5,
                        "tp_mult": 0.5,
                        "max_positions": 1,
                    }
                elif fbr > p.false_breakout_high_threshold:
                    # R+V-B: 假突破密集
                    return RegimeSubType.RVB_FALSE_BREAKOUT, {
                        "action": "cautious_revert",
                        "scale": 0.5,
                        "strategies": ["BollMR"],
                        "sl_mult": 1.2,
                        "tp_mult": 0.8,
                        "max_positions": 1,
                    }
                else:
                    # 高波动但无明确特征
                    return RegimeSubType.RN_NORMAL_RANGE, {
                        "action": "cautious_revert",
                        "scale": 0.6,
                        "strategies": ["BollMR"],
                        "sl_mult": 1.1,
                        "tp_mult": 0.9,
                        "max_positions": 1,
                    }
            elif vol == VolatilityState.LOW:
                # R+L: 低波动震荡
                return RegimeSubType.RL_LOW_VOL_RANGE, {
                    "action": "observe",
                    "scale": 0.3,
                    "strategies": [],
                    "sl_mult": 1.0,
                    "tp_mult": 0.7,
                    "max_positions": 1,
                }
            else:
                # R+N: 正常震荡 - 最佳均值回归环境
                return RegimeSubType.RN_NORMAL_RANGE, {
                    "action": "mean_revert",
                    "scale": 1.0,
                    "strategies": ["BollMR"],
                    "sl_mult": 1.0,
                    "tp_mult": 1.0,
                    "max_positions": 2,
                }
        
        return RegimeSubType.UNKNOWN, default_config
    
    def get_subtype_snapshot(
        self,
        regime_df: pd.DataFrame,
        quality_df: pd.DataFrame
    ) -> SubTypeData:
        """获取当前 Sub-Type 快照"""
        result = self.classify(regime_df, quality_df)
        
        if len(result) == 0:
            return SubTypeData()
        
        last = result.iloc[-1]
        
        return SubTypeData(
            sub_type=last["sub_type"],
            efficiency=quality_df["efficiency"].iloc[-1],
            reversal_rate=last["reversal_rate"],
            false_breakout_rate=quality_df["false_breakout_rate"].iloc[-1],
            recommended_action=last["recommended_action"],
            scale_multiplier=last["scale_multiplier"],
            preferred_strategies=last["preferred_strategies"],
            sl_multiplier=last["sl_multiplier"],
            tp_multiplier=last["tp_multiplier"],
            max_positions=last["max_positions"],
        )
