"""
Regime Filter - 市场状态过滤器

整合 RegimeIndicators 和 MarketQuality
实现状态机：ACTIVE / STANDBY / TRANSITION

Phase 1 核心功能：
- 计算 Q_score
- Q < 0.5 → STANDBY
- 输出市场状态供策略使用

Phase 2 功能：
- Regime Sub-Type 分类
- Sub-Type → 策略选择 + 风险参数映射
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Optional, Tuple, List

import numpy as np
import pandas as pd

from regime.regime_indicators import RegimeIndicators, RegimeParams, RegimeType, VolatilityState, TrendDirection
from regime.market_quality import MarketQuality, MarketQualityParams
from regime.regime_subtype import RegimeSubTypeClassifier, SubTypeParams, SubTypeData, RegimeSubType


class RegimeState(Enum):
    """Regime 状态"""
    ACTIVE = "active"        # 可交易
    STANDBY = "standby"      # 观望
    TRANSITION = "transition"  # 过渡中


@dataclass
class RegimeFilterParams:
    """Regime Filter 参数"""
    # Regime 指标参数
    regime: RegimeParams = None
    
    # 市场质量参数
    quality: MarketQualityParams = None
    
    # Sub-Type 分类参数
    subtype: SubTypeParams = None
    
    # Q_score 阈值
    q_score_standby: float = 0.5   # Q < 此值 → STANDBY
    q_score_active: float = 0.6    # Q > 此值 → ACTIVE
    
    # 状态转换参数
    transition_bars: int = 3       # 过渡期K线数
    hysteresis: float = 0.05       # 滞后阈值，防止频繁切换
    
    # 是否启用 Sub-Type 分类
    enable_subtype: bool = True
    
    def __post_init__(self):
        if self.regime is None:
            self.regime = RegimeParams()
        if self.quality is None:
            self.quality = MarketQualityParams()
        if self.subtype is None:
            self.subtype = SubTypeParams()


@dataclass
class RegimeSnapshot:
    """Regime 快照"""
    # 状态
    state: RegimeState = RegimeState.STANDBY
    regime_type: RegimeType = RegimeType.RANGE
    volatility_state: VolatilityState = VolatilityState.NORMAL
    trend_direction: TrendDirection = TrendDirection.NONE
    
    # Sub-Type (Phase 2)
    sub_type: RegimeSubType = RegimeSubType.UNKNOWN
    recommended_action: str = "observe"
    
    # 指标
    trend_strength: float = 0.0
    efficiency: float = 0.5
    false_breakout_rate: float = 0.0
    q_score: float = 0.5
    
    # 建议
    scale_multiplier: float = 1.0  # 仓位缩放因子
    recommended_strategies: List[str] = field(default_factory=list)
    
    # 风险参数 (Phase 2)
    sl_multiplier: float = 1.0
    tp_multiplier: float = 1.0
    max_positions: int = 1


class RegimeFilter:
    """
    市场状态过滤器
    
    使用方法：
    ```python
    filter = RegimeFilter(params)
    result = filter.calculate(df)
    
    # 获取当前状态
    snapshot = filter.get_snapshot(df)
    if snapshot.state == RegimeState.ACTIVE:
        # 可交易
        pass
    ```
    """
    
    def __init__(self, params: Optional[RegimeFilterParams] = None):
        self.params = params or RegimeFilterParams()
        self.regime_indicators = RegimeIndicators(self.params.regime)
        self.market_quality = MarketQuality(self.params.quality)
        self.subtype_classifier = RegimeSubTypeClassifier(self.params.subtype)
        
        # 状态跟踪
        self._current_state = RegimeState.STANDBY
        self._transition_counter = 0
        self._last_q_score = 0.5
        
        # 缓存
        self._last_regime_df: Optional[pd.DataFrame] = None
        self._last_quality_df: Optional[pd.DataFrame] = None
    
    def calculate(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        计算 Regime Filter 结果
        
        Args:
            df: OHLCV DataFrame
            
        Returns:
            DataFrame with columns:
            - trend_strength
            - volatility_state
            - regime_type
            - trend_direction
            - efficiency
            - false_breakout_rate
            - q_score
            - regime_state
            - scale_multiplier
            - sub_type (Phase 2)
            - recommended_action (Phase 2)
            - sl_multiplier (Phase 2)
            - tp_multiplier (Phase 2)
            - max_positions (Phase 2)
        """
        # 计算 Regime 指标
        self._last_regime_df = self.regime_indicators.calculate(df)
        
        # 计算市场质量（只传递 adx 列）
        adx_series = self._last_regime_df["adx"] if "adx" in self._last_regime_df.columns else None
        self._last_quality_df = self.market_quality.calculate(df, adx_series)
        
        # 合并结果
        result = pd.DataFrame(index=df.index)
        result["trend_strength"] = self._last_regime_df["trend_strength"]
        result["volatility_state"] = self._last_regime_df["volatility_state"]
        result["regime_type"] = self._last_regime_df["regime_type"]
        result["trend_direction"] = self._last_regime_df["trend_direction"]
        result["efficiency"] = self._last_quality_df["efficiency"]
        result["false_breakout_rate"] = self._last_quality_df["false_breakout_rate"]
        result["q_score"] = self._last_quality_df["q_score"]
        
        # 计算状态
        result["regime_state"] = self._calculate_state(result["q_score"])
        
        # Sub-Type 分类 (Phase 2)
        if self.params.enable_subtype:
            subtype_result = self.subtype_classifier.classify(
                self._last_regime_df, 
                self._last_quality_df
            )
            result["sub_type"] = subtype_result["sub_type"]
            result["recommended_action"] = subtype_result["recommended_action"]
            result["sl_multiplier"] = subtype_result["sl_multiplier"]
            result["tp_multiplier"] = subtype_result["tp_multiplier"]
            result["max_positions"] = subtype_result["max_positions"]
            result["preferred_strategies"] = subtype_result["preferred_strategies"]
            
            # 使用 Sub-Type 的 scale_multiplier
            result["scale_multiplier"] = subtype_result["scale_multiplier"]
        else:
            # Phase 1 fallback
            result["scale_multiplier"] = self._calculate_scale_multiplier(result)
            result["sub_type"] = RegimeSubType.UNKNOWN
            result["recommended_action"] = "observe"
            result["sl_multiplier"] = 1.0
            result["tp_multiplier"] = 1.0
            result["max_positions"] = 1
            result["preferred_strategies"] = [""]
        
        return result
    
    def _calculate_state(self, q_score: pd.Series) -> pd.Series:
        """
        计算 Regime 状态
        
        使用滞后机制防止频繁切换
        """
        states = []
        current = self._current_state
        counter = self._transition_counter
        
        p = self.params
        
        for q in q_score:
            if current == RegimeState.ACTIVE:
                # 从 ACTIVE 转 STANDBY 需要确认
                if q < p.q_score_standby - p.hysteresis:
                    counter += 1
                    if counter >= p.transition_bars:
                        current = RegimeState.STANDBY
                        counter = 0
                    else:
                        current = RegimeState.TRANSITION
                else:
                    counter = 0
                    
            elif current == RegimeState.STANDBY:
                # 从 STANDBY 转 ACTIVE 需要确认
                if q > p.q_score_active + p.hysteresis:
                    counter += 1
                    if counter >= p.transition_bars:
                        current = RegimeState.ACTIVE
                        counter = 0
                    else:
                        current = RegimeState.TRANSITION
                else:
                    counter = 0
                    
            else:  # TRANSITION
                if q > p.q_score_active:
                    counter += 1
                    if counter >= p.transition_bars:
                        current = RegimeState.ACTIVE
                        counter = 0
                elif q < p.q_score_standby:
                    counter += 1
                    if counter >= p.transition_bars:
                        current = RegimeState.STANDBY
                        counter = 0
                else:
                    counter = 0
            
            states.append(current)
        
        # 更新内部状态
        if len(states) > 0:
            self._current_state = states[-1]
            self._transition_counter = counter
        
        return pd.Series(states, index=q_score.index)
    
    def _calculate_scale_multiplier(self, result: pd.DataFrame) -> pd.Series:
        """
        计算仓位缩放因子
        
        基于 Q_score 和 Regime 类型动态调整
        """
        q_score = result["q_score"]
        regime_type = result["regime_type"]
        volatility_state = result["volatility_state"]
        
        # 基础缩放：基于 Q_score
        scale = q_score.copy()
        
        # Regime 类型调整
        # 趋势市场可以提高仓位
        scale = np.where(
            regime_type == RegimeType.TREND,
            scale * 1.2,
            scale * 0.8
        )
        
        # 波动率调整
        # 高波动降低仓位
        scale = np.where(
            volatility_state == VolatilityState.HIGH,
            scale * 0.7,
            scale
        )
        # 低波动可以略微提高
        scale = np.where(
            volatility_state == VolatilityState.LOW,
            scale * 1.1,
            scale
        )
        
        return pd.Series(np.clip(scale, 0.2, 1.5), index=result.index)
    
    def get_snapshot(self, df: pd.DataFrame) -> RegimeSnapshot:
        """获取当前 Regime 快照"""
        result = self.calculate(df)

        if len(result) == 0:
            return RegimeSnapshot()

        last = result.iloc[-1]

        # 获取推荐策略
        strategies = self._get_strategies_from_result(last)

        # 转换 trend_direction 为枚举
        trend_dir = last["trend_direction"]
        if isinstance(trend_dir, TrendDirection):
            trend_direction = trend_dir
        else:
            trend_direction = TrendDirection(int(trend_dir))

        return RegimeSnapshot(
            state=last["regime_state"],
            regime_type=last["regime_type"],
            volatility_state=last["volatility_state"],
            trend_direction=trend_direction,
            sub_type=last.get("sub_type", RegimeSubType.UNKNOWN),
            recommended_action=last.get("recommended_action", "observe"),
            trend_strength=float(last["trend_strength"]),
            efficiency=float(last["efficiency"]),
            false_breakout_rate=float(last["false_breakout_rate"]),
            q_score=float(last["q_score"]),
            scale_multiplier=float(last["scale_multiplier"]),
            recommended_strategies=strategies,
            sl_multiplier=float(last.get("sl_multiplier", 1.0)),
            tp_multiplier=float(last.get("tp_multiplier", 1.0)),
            max_positions=int(last.get("max_positions", 1)),
        )
    
    def _get_strategies_from_result(self, row: pd.Series) -> List[str]:
        """从结果中获取策略列表"""
        if "preferred_strategies" in row and row["preferred_strategies"]:
            strategies = row["preferred_strategies"]
            if isinstance(strategies, list):
                return [s for s in strategies if s]
            elif isinstance(strategies, str) and strategies:
                return [strategies]
        return self._recommend_strategies(row)
    
    def _recommend_strategies(self, row: pd.Series) -> list:
        """
        基于当前 Regime 推荐策略

        Phase 1 简单规则：
        - TREND + HIGH_VOL → TrendPullback
        - RANGE + NORMAL_VOL → BollMR
        """
        strategies = []

        regime_type = row["regime_type"]
        vol_state = row["volatility_state"]
        trend_dir = row["trend_direction"]

        if regime_type == RegimeType.TREND:
            if trend_dir != TrendDirection.NONE:
                strategies.append("TrendPullback")
            if vol_state == VolatilityState.HIGH:
                # 高波动趋势中也可以做回归
                strategies.append("BollMR")
        else:  # RANGE
            if vol_state != VolatilityState.HIGH:
                strategies.append("BollMR")

        return strategies
    
    def is_tradable(self, df: pd.DataFrame) -> bool:
        """快速检查当前是否可交易"""
        snapshot = self.get_snapshot(df)
        return snapshot.state == RegimeState.ACTIVE
    
    def get_q_score(self, df: pd.DataFrame) -> float:
        """快速获取当前 Q_score"""
        result = self.calculate(df)
        if len(result) == 0:
            return 0.0
        return float(result.iloc[-1]["q_score"])
