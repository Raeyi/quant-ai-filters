"""
Strategy Selector - 策略选择器

Phase 3 功能：
根据 Sub-Type × Session × Quality 选择最佳策略

核心设计：
1. TIME_REGIME_WEIGHTS 矩阵：不同时段对不同 Sub-Type 的权重
2. 策略匹配：根据 Sub-Type 和时段选择策略
3. 参数调整：根据 Quality Score 调整策略参数
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Dict, List, Optional, Tuple

import numpy as np
import pandas as pd

from regime.regime_subtype import RegimeSubType


class TradingSession(Enum):
    """交易时段"""
    ASIAN = "asian"          # 亚盘 00:00-08:00 GMT
    EUROPEAN = "european"    # 欧盘 08:00-14:00 GMT
    OVERLAP = "overlap"      # 欧美重叠 14:00-17:00 GMT
    US = "us"                # 美盘 17:00-21:00 GMT
    LATE_US = "late_us"      # 美盘尾段 21:00-00:00 GMT


@dataclass
class SessionConfig:
    """时段配置"""
    start_hour: int
    end_hour: int
    weight_base: float = 1.0


@dataclass
class StrategyConfig:
    """策略配置"""
    name: str
    enabled: bool = True
    base_scale: float = 1.0
    min_quality: float = 0.4
    preferred_sessions: List[TradingSession] = field(default_factory=list)
    preferred_subtypes: List[RegimeSubType] = field(default_factory=list)


@dataclass
class StrategySelection:
    """策略选择结果"""
    primary_strategy: str = ""
    secondary_strategies: List[str] = field(default_factory=list)
    scale: float = 1.0
    confidence: float = 0.5
    reason: str = ""
    
    # 调整后的参数
    adjusted_params: Dict = field(default_factory=dict)


# 时段定义 (GMT)
SESSION_CONFIGS: Dict[TradingSession, SessionConfig] = {
    TradingSession.ASIAN: SessionConfig(0, 8, 0.7),
    TradingSession.EUROPEAN: SessionConfig(8, 14, 1.0),
    TradingSession.OVERLAP: SessionConfig(14, 17, 1.2),
    TradingSession.US: SessionConfig(17, 21, 1.1),
    TradingSession.LATE_US: SessionConfig(21, 24, 0.8),
}

# TIME_REGIME_WEIGHTS 矩阵
# 定义不同 Sub-Type 在不同时段的交易权重
# 行: Sub-Type, 列: Session
# 值越高表示该时段该 Sub-Type 下交易价值越高
TIME_REGIME_WEIGHTS: Dict[RegimeSubType, Dict[TradingSession, float]] = {
    # 趋势类
    RegimeSubType.TVA_EMOTION_PULSE: {
        TradingSession.ASIAN: 0.3,     # 亚盘情绪脉冲通常不可靠
        TradingSession.EUROPEAN: 0.6,
        TradingSession.OVERLAP: 0.8,   # 重叠时段波动大，可能捕捉
        TradingSession.US: 0.7,
        TradingSession.LATE_US: 0.4,
    },
    RegimeSubType.TVB_TRUE_TREND: {
        TradingSession.ASIAN: 0.5,
        TradingSession.EUROPEAN: 1.0,  # 欧盘趋势最可靠
        TradingSession.OVERLAP: 1.2,   # 重叠时段最佳
        TradingSession.US: 1.0,
        TradingSession.LATE_US: 0.7,
    },
    RegimeSubType.TN_MILD_TREND: {
        TradingSession.ASIAN: 0.6,
        TradingSession.EUROPEAN: 0.9,
        TradingSession.OVERLAP: 1.0,
        TradingSession.US: 0.8,
        TradingSession.LATE_US: 0.5,
    },
    # 震荡类
    RegimeSubType.RVA_NEWS_CHOP: {
        TradingSession.ASIAN: 0.2,
        TradingSession.EUROPEAN: 0.3,
        TradingSession.OVERLAP: 0.2,   # 重叠时段震荡最危险
        TradingSession.US: 0.3,
        TradingSession.LATE_US: 0.2,
    },
    RegimeSubType.RVB_FALSE_BREAKOUT: {
        TradingSession.ASIAN: 0.4,
        TradingSession.EUROPEAN: 0.5,
        TradingSession.OVERLAP: 0.4,
        TradingSession.US: 0.5,
        TradingSession.LATE_US: 0.3,
    },
    RegimeSubType.RN_NORMAL_RANGE: {
        TradingSession.ASIAN: 0.8,     # 亚盘震荡适合回归
        TradingSession.EUROPEAN: 0.9,
        TradingSession.OVERLAP: 0.7,
        TradingSession.US: 0.8,
        TradingSession.LATE_US: 0.6,
    },
    RegimeSubType.RL_LOW_VOL_RANGE: {
        TradingSession.ASIAN: 0.3,     # 低波动不适合交易
        TradingSession.EUROPEAN: 0.4,
        TradingSession.OVERLAP: 0.3,
        TradingSession.US: 0.4,
        TradingSession.LATE_US: 0.2,
    },
    RegimeSubType.UNKNOWN: {
        TradingSession.ASIAN: 0.3,
        TradingSession.EUROPEAN: 0.4,
        TradingSession.OVERLAP: 0.4,
        TradingSession.US: 0.4,
        TradingSession.LATE_US: 0.3,
    },
}

# 策略配置
STRATEGY_CONFIGS: Dict[str, StrategyConfig] = {
    "TrendPullback": StrategyConfig(
        name="TrendPullback",
        base_scale=1.0,
        min_quality=0.5,
        preferred_sessions=[
            TradingSession.EUROPEAN,
            TradingSession.OVERLAP,
            TradingSession.US,
        ],
        preferred_subtypes=[
            RegimeSubType.TVB_TRUE_TREND,
            RegimeSubType.TN_MILD_TREND,
            RegimeSubType.TVA_EMOTION_PULSE,
        ],
    ),
    "BollMR": StrategyConfig(
        name="BollMR",
        base_scale=1.0,
        min_quality=0.4,
        preferred_sessions=[
            TradingSession.ASIAN,
            TradingSession.EUROPEAN,
            TradingSession.US,
        ],
        preferred_subtypes=[
            RegimeSubType.RN_NORMAL_RANGE,
            RegimeSubType.RVB_FALSE_BREAKOUT,
            RegimeSubType.TN_MILD_TREND,  # 弱趋势也可以做回归
        ],
    ),
}


class StrategySelector:
    """策略选择器"""
    
    def __init__(self):
        self.session_configs = SESSION_CONFIGS
        self.time_weights = TIME_REGIME_WEIGHTS
        self.strategy_configs = STRATEGY_CONFIGS
    
    def get_current_session(
        self, 
        hour: int, 
        timezone_offset: int = 0
    ) -> TradingSession:
        """
        获取当前交易时段
        
        Args:
            hour: 当前小时 (本地时间)
            timezone_offset: 时区偏移 (本地时间 = GMT + offset)
        """
        # 转换为 GMT
        gmt_hour = (hour - timezone_offset) % 24
        
        for session, config in self.session_configs.items():
            if config.start_hour <= config.end_hour:
                if config.start_hour <= gmt_hour < config.end_hour:
                    return session
            else:  # 跨午夜时段
                if gmt_hour >= config.start_hour or gmt_hour < config.end_hour:
                    return session
        
        return TradingSession.ASIAN  # 默认
    
    def calculate_session_weight(
        self,
        sub_type: RegimeSubType,
        session: TradingSession
    ) -> float:
        """计算时段权重"""
        if sub_type not in self.time_weights:
            return 0.3
        
        return self.time_weights[sub_type].get(session, 0.5)
    
    def select_strategy(
        self,
        sub_type: RegimeSubType,
        session: TradingSession,
        q_score: float,
        trend_direction: int = 0,
    ) -> StrategySelection:
        """
        选择策略
        
        Args:
            sub_type: Regime Sub-Type
            session: 当前交易时段
            q_score: Quality Score
            trend_direction: 趋势方向 (1=多, -1=空, 0=无)
            
        Returns:
            StrategySelection
        """
        # 计算时段权重
        session_weight = self.calculate_session_weight(sub_type, session)
        
        # 综合权重
        combined_weight = session_weight * q_score
        
        # 如果权重太低，不推荐任何策略
        if combined_weight < 0.3:
            return StrategySelection(
                primary_strategy="",
                scale=0.0,
                confidence=combined_weight,
                reason=f"Weight too low: session={session_weight:.2f}, q={q_score:.2f}",
            )
        
        # 选择策略
        primary = ""
        secondary = []
        
        # 根据Sub-Type选择策略
        if sub_type in [
            RegimeSubType.TVB_TRUE_TREND,
            RegimeSubType.TN_MILD_TREND,
        ]:
            if trend_direction != 0:
                primary = "TrendPullback"
                secondary = ["BollMR"]  # 可以辅助做轻仓回归
        elif sub_type == RegimeSubType.TVA_EMOTION_PULSE:
            # 情绪脉冲需要谨慎
            if trend_direction != 0 and q_score > 0.6:
                primary = "TrendPullback"
        elif sub_type in [
            RegimeSubType.RN_NORMAL_RANGE,
            RegimeSubType.RVB_FALSE_BREAKOUT,
        ]:
            primary = "BollMR"
        elif sub_type == RegimeSubType.RVA_NEWS_CHOP:
            # 消息震荡不建议交易
            return StrategySelection(
                primary_strategy="",
                scale=0.2,
                confidence=0.2,
                reason="News chop - standby recommended",
            )
        elif sub_type == RegimeSubType.RL_LOW_VOL_RANGE:
            # 低波动观望
            return StrategySelection(
                primary_strategy="",
                scale=0.3,
                confidence=0.3,
                reason="Low volatility - standby recommended",
            )
        
        # 验证策略是否适合当前时段
        if primary:
            config = self.strategy_configs.get(primary)
            if config:
                if session not in config.preferred_sessions:
                    # 降低权重
                    combined_weight *= 0.7
                
                if q_score < config.min_quality:
                    # 质量不达标
                    return StrategySelection(
                        primary_strategy="",
                        scale=0.3,
                        confidence=q_score,
                        reason=f"Q score {q_score:.2f} below minimum {config.min_quality}",
                    )
        
        # 计算最终 scale
        final_scale = min(combined_weight, 1.5)
        
        # 根据条件调整参数
        adjusted_params = self._adjust_params(
            primary, 
            sub_type, 
            session, 
            q_score
        )
        
        return StrategySelection(
            primary_strategy=primary,
            secondary_strategies=secondary,
            scale=final_scale,
            confidence=combined_weight,
            reason=f"Selected {primary} for {sub_type.value} in {session.value}",
            adjusted_params=adjusted_params,
        )
    
    def _adjust_params(
        self,
        strategy: str,
        sub_type: RegimeSubType,
        session: TradingSession,
        q_score: float
    ) -> Dict:
        """
        调整策略参数
        
        根据市场条件调整策略的具体参数
        """
        params = {}
        
        if strategy == "TrendPullback":
            # 趋势策略参数调整
            if sub_type == RegimeSubType.TVA_EMOTION_PULSE:
                # 情绪脉冲：收紧止损，快速止盈
                params["sl_atr_mult"] = 1.2
                params["tp_atr_mult"] = 1.5
                params["trail_trigger"] = 0.5
            elif sub_type == RegimeSubType.TVB_TRUE_TREND:
                # 真趋势：可以放宽止盈
                params["sl_atr_mult"] = 1.5
                params["tp_atr_mult"] = 3.0
                params["trail_trigger"] = 1.0
            
            # 时段调整
            if session == TradingSession.OVERLAP:
                params["confirm_bars"] = 2  # 重叠时段快进快出
            elif session == TradingSession.ASIAN:
                params["confirm_bars"] = 3  # 亚盘多确认
                
        elif strategy == "BollMR":
            # 回归策略参数调整
            if sub_type == RegimeSubType.RVB_FALSE_BREAKOUT:
                # 假突破密集：等待更极端位置
                params["entry_zscore"] = 1.2
                params["exit_zscore"] = 0.3
            elif sub_type == RegimeSubType.RN_NORMAL_RANGE:
                # 正常震荡：标准参数
                params["entry_zscore"] = 1.0
                params["exit_zscore"] = 0.0
            
            # 时段调整
            if session == TradingSession.ASIAN:
                # 亚盘波动小，需要更大的偏离
                params["entry_zscore"] = params.get("entry_zscore", 1.0) + 0.2
        
        # 质量调整
        if q_score < 0.5:
            # 低质量环境下保守
            params["position_scale"] = 0.7
        
        return params
    
    def calculate_for_dataframe(
        self,
        df: pd.DataFrame,
        regime_result: pd.DataFrame,
        timezone_offset: int = 0
    ) -> pd.DataFrame:
        """
        为 DataFrame 中的每一行计算策略选择
        
        Args:
            df: OHLCV DataFrame with time index
            regime_result: Regime Filter 结果
            timezone_offset: 时区偏移
            
        Returns:
            DataFrame with strategy selection columns
        """
        results = []
        
        for i, (idx, row) in enumerate(regime_result.iterrows()):
            hour = idx.hour
            session = self.get_current_session(hour, timezone_offset)
            
            sub_type = row.get("sub_type", RegimeSubType.UNKNOWN)
            q_score = row.get("q_score", 0.5)
            trend_dir = row.get("trend_direction", 0)
            
            selection = self.select_strategy(
                sub_type, session, q_score, trend_dir
            )
            
            results.append({
                "selected_strategy": selection.primary_strategy,
                "strategy_scale": selection.scale,
                "strategy_confidence": selection.confidence,
                "session": session.value,
                "session_weight": self.calculate_session_weight(sub_type, session),
            })
        
        return pd.DataFrame(results, index=df.index)
    
    def get_position_rules(
        self,
        sub_type: RegimeSubType,
        has_position: bool,
        position_direction: int = 0
    ) -> Dict:
        """
        获取持仓处理规则
        
        Args:
            sub_type: 当前 Regime Sub-Type
            has_position: 是否有持仓
            position_direction: 持仓方向 (1=多, -1=空)
            
        Returns:
            Dict with rules:
            - allow_new: 是否允许新仓位
            - allow_add: 是否允许加仓
            - tighten_sl: 是否收紧止损
            - quick_exit: 是否快速平仓
            - reason: 原因
        """
        rules = {
            "allow_new": True,
            "allow_add": False,
            "tighten_sl": False,
            "quick_exit": False,
            "trail_stop": True,
            "reason": "",
        }
        
        # 情绪脉冲：有仓则收紧，无仓需谨慎
        if sub_type == RegimeSubType.TVA_EMOTION_PULSE:
            if has_position:
                rules["tighten_sl"] = True
                rules["quick_exit"] = True
                rules["reason"] = "Emotion pulse - tighten exit"
            else:
                rules["allow_new"] = True
                rules["allow_add"] = False
                rules["reason"] = "Emotion pulse - cautious entry"
        
        # 真趋势：可以加仓
        elif sub_type == RegimeSubType.TVB_TRUE_TREND:
            if has_position:
                rules["allow_add"] = True
                rules["trail_stop"] = True
                rules["reason"] = "True trend - trail and add"
            else:
                rules["allow_new"] = True
                rules["reason"] = "True trend - enter"
        
        # 消息震荡：快速平仓
        elif sub_type == RegimeSubType.RVA_NEWS_CHOP:
            if has_position:
                rules["quick_exit"] = True
                rules["tighten_sl"] = True
                rules["allow_add"] = False
                rules["reason"] = "News chop - exit immediately"
            else:
                rules["allow_new"] = False
                rules["reason"] = "News chop - no new positions"
        
        # 假突破密集：保守
        elif sub_type == RegimeSubType.RVB_FALSE_BREAKOUT:
            rules["allow_add"] = False
            if has_position:
                rules["tighten_sl"] = True
            rules["reason"] = "False breakout zone - conservative"
        
        # 低波动：不交易
        elif sub_type == RegimeSubType.RL_LOW_VOL_RANGE:
            rules["allow_new"] = False
            rules["allow_add"] = False
            rules["reason"] = "Low volatility - no trading"
        
        # 正常震荡或温和趋势：标准规则
        else:
            rules["allow_add"] = True
            rules["reason"] = "Normal conditions"
        
        return rules
