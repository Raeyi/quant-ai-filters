"""
Regime Filter Module - 市场状态识别与过滤

Phase 1:
- RegimeIndicators: trend_strength, volatility_state
- MarketQuality: efficiency, false_breakout_rate
- Q_score: 综合质量分数，Q<0.5 → STANDBY

Phase 2:
- RegimeSubType: 市场状态细分
- Sub-Type → 策略选择 + 风险参数映射

Phase 3:
- StrategySelector: 策略选择器
- TIME_REGIME_WEIGHTS: 时段权重矩阵
- Position Rules: 持仓处理规则

Phase 4:
- TransitionMatrix: Regime 转移概率矩阵
- 转移预测与提前布局

Phase 5:
- RiskExposureManager: 风险暴露管理
- Sub-Type → SL/TP/Position 映射
"""

from regime.regime_indicators import RegimeIndicators, RegimeParams, RegimeType, VolatilityState
from regime.market_quality import MarketQuality, MarketQualityParams
from regime.regime_filter import RegimeFilter, RegimeFilterParams, RegimeState
from regime.regime_subtype import (
    RegimeSubTypeClassifier,
    SubTypeParams,
    SubTypeData,
    RegimeSubType,
)
from regime.strategy_selector import (
    StrategySelector,
    StrategySelection,
    StrategyConfig,
    TradingSession,
    TIME_REGIME_WEIGHTS,
    SESSION_CONFIGS,
)
from regime.transition_matrix import (
    TransitionMatrix,
    TransitionStats,
    TransitionPrediction,
)
from regime.risk_exposure import (
    RiskExposureManager,
    RiskExposureConfig,
    RiskAdjustment,
    RiskLevel,
)

__all__ = [
    # Phase 1
    "RegimeIndicators",
    "RegimeParams",
    "RegimeType",
    "VolatilityState",
    "MarketQuality",
    "MarketQualityParams",
    "RegimeFilter",
    "RegimeFilterParams",
    "RegimeState",
    # Phase 2
    "RegimeSubTypeClassifier",
    "SubTypeParams",
    "SubTypeData",
    "RegimeSubType",
    # Phase 3
    "StrategySelector",
    "StrategySelection",
    "StrategyConfig",
    "TradingSession",
    "TIME_REGIME_WEIGHTS",
    "SESSION_CONFIGS",
    # Phase 4
    "TransitionMatrix",
    "TransitionStats",
    "TransitionPrediction",
    # Phase 5
    "RiskExposureManager",
    "RiskExposureConfig",
    "RiskAdjustment",
    "RiskLevel",
]
