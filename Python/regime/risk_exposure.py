"""
Risk Exposure - 风险暴露管理

Phase 5 功能：
根据 Regime Sub-Type 动态调整风险暴露

核心设计：
1. Sub-Type → SL/TP 乘数映射
2. 最大持仓数控制
3. 加仓权限管理
4. 整体风险暴露限制
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Dict, List, Optional

import numpy as np
import pandas as pd

from regime.regime_subtype import RegimeSubType


class RiskLevel(Enum):
    """风险等级"""
    LOW = "low"           # 低风险
    MEDIUM = "medium"     # 中等风险
    HIGH = "high"         # 高风险
    EXTREME = "extreme"   # 极端风险


@dataclass
class RiskExposureConfig:
    """风险暴露配置"""
    # 基础参数
    base_risk_percent: float = 1.0    # 基础单笔风险比例
    max_total_risk: float = 5.0        # 最大总风险暴露
    max_positions: int = 3             # 最大持仓数
    
    # 止损止盈乘数 (基于 Sub-Type)
    sl_mult_default: float = 1.0
    tp_mult_default: float = 1.0
    
    # 加仓参数
    allow_add_position: bool = True
    add_position_min_profit_atr: float = 1.0  # 加仓最小盈利 ATR
    max_add_positions: int = 2                 # 最大加仓次数


@dataclass
class RiskAdjustment:
    """风险调整结果"""
    # 仓位参数
    position_size: float = 0.01        # 建议仓位大小
    sl_multiplier: float = 1.0         # 止损乘数
    tp_multiplier: float = 1.0         # 止盈乘数
    
    # 持仓控制
    allow_new_position: bool = True    # 是否允许新仓位
    allow_add_position: bool = False   # 是否允许加仓
    max_positions: int = 1             # 最大持仓数
    
    # 风险等级
    risk_level: RiskLevel = RiskLevel.MEDIUM
    
    # 原因
    reason: str = ""


# Sub-Type 风险参数预设
SUBTYPE_RISK_PARAMS: Dict[RegimeSubType, Dict] = {
    # 趋势类 - 顺势交易
    RegimeSubType.TVB_TRUE_TREND: {
        "sl_mult": 1.5,          # 放宽止损，让趋势发展
        "tp_mult": 2.0,          # 扩大止盈
        "max_positions": 2,      # 可加仓
        "allow_add": True,
        "risk_level": RiskLevel.MEDIUM,
    },
    RegimeSubType.TN_MILD_TREND: {
        "sl_mult": 1.2,
        "tp_mult": 1.5,
        "max_positions": 2,
        "allow_add": True,
        "risk_level": RiskLevel.MEDIUM,
    },
    RegimeSubType.TVA_EMOTION_PULSE: {
        "sl_mult": 0.8,          # 收紧止损
        "tp_mult": 1.0,          # 快速止盈
        "max_positions": 1,      # 不加仓
        "allow_add": False,
        "risk_level": RiskLevel.HIGH,
    },
    
    # 震荡类 - 均值回归
    RegimeSubType.RN_NORMAL_RANGE: {
        "sl_mult": 1.0,
        "tp_mult": 1.0,
        "max_positions": 2,
        "allow_add": True,
        "risk_level": RiskLevel.LOW,
    },
    RegimeSubType.RVB_FALSE_BREAKOUT: {
        "sl_mult": 1.2,          # 稍微放宽止损
        "tp_mult": 0.8,          # 快速止盈
        "max_positions": 1,
        "allow_add": False,
        "risk_level": RiskLevel.MEDIUM,
    },
    RegimeSubType.RVA_NEWS_CHOP: {
        "sl_mult": 1.5,          # 大幅放宽止损
        "tp_mult": 0.5,          # 快速止盈
        "max_positions": 1,
        "allow_add": False,
        "risk_level": RiskLevel.EXTREME,
    },
    RegimeSubType.RL_LOW_VOL_RANGE: {
        "sl_mult": 0.8,
        "tp_mult": 0.6,
        "max_positions": 1,
        "allow_add": False,
        "risk_level": RiskLevel.LOW,
    },
    
    # 默认
    RegimeSubType.UNKNOWN: {
        "sl_mult": 1.0,
        "tp_mult": 1.0,
        "max_positions": 1,
        "allow_add": False,
        "risk_level": RiskLevel.MEDIUM,
    },
}


class RiskExposureManager:
    """风险暴露管理器"""
    
    def __init__(self, config: Optional[RiskExposureConfig] = None):
        self.config = config or RiskExposureConfig()
        self.subtype_params = SUBTYPE_RISK_PARAMS
        
        # 追踪当前风险暴露
        self._current_positions: int = 0
        self._current_risk: float = 0.0
        self._position_history: List[Dict] = []
    
    def get_risk_adjustment(
        self,
        sub_type: RegimeSubType,
        q_score: float,
        current_positions: int = 0,
        current_risk: float = 0.0,
        account_balance: float = 10000.0,
        atr: float = 10.0,
    ) -> RiskAdjustment:
        """
        获取风险调整建议
        
        Args:
            sub_type: 当前 Regime Sub-Type
            q_score: Quality Score
            current_positions: 当前持仓数
            current_risk: 当前风险暴露比例
            account_balance: 账户余额
            atr: 当前 ATR 值
            
        Returns:
            RiskAdjustment
        """
        # 获取基础参数
        params = self.subtype_params.get(sub_type, self.subtype_params[RegimeSubType.UNKNOWN])
        
        # 初始化调整结果
        adjustment = RiskAdjustment(
            sl_multiplier=params["sl_mult"],
            tp_multiplier=params["tp_mult"],
            max_positions=params["max_positions"],
            risk_level=params["risk_level"],
        )
        
        # 检查是否允许新仓位
        if current_positions >= params["max_positions"]:
            adjustment.allow_new_position = False
            adjustment.reason = f"Max positions reached ({current_positions}/{params['max_positions']})"
            return adjustment
        
        # 检查总风险暴露
        potential_risk = self.config.base_risk_percent * (current_positions + 1)
        if current_risk + potential_risk > self.config.max_total_risk:
            adjustment.allow_new_position = False
            adjustment.reason = f"Total risk limit reached ({current_risk:.1f}% + {potential_risk:.1f}% > {self.config.max_total_risk:.1f}%)"
            return adjustment
        
        # 根据 Q_score 调整
        if q_score < 0.4:
            adjustment.allow_new_position = False
            adjustment.reason = f"Q score too low ({q_score:.2f})"
            return adjustment
        elif q_score < 0.5:
            adjustment.position_size *= 0.5
            adjustment.risk_level = RiskLevel.HIGH
            adjustment.reason = "Reduced position due to low Q score"
        elif q_score > 0.7:
            adjustment.position_size *= 1.2
            adjustment.reason = "Increased position due to high Q score"
        
        # 根据 Risk Level 调整
        if params["risk_level"] == RiskLevel.EXTREME:
            adjustment.allow_new_position = False
            adjustment.reason = "Extreme risk environment - no new positions"
            return adjustment
        elif params["risk_level"] == RiskLevel.HIGH:
            adjustment.position_size *= 0.5
            adjustment.sl_multiplier *= 0.8
        elif params["risk_level"] == RiskLevel.LOW:
            adjustment.position_size *= 1.2
        
        # 加仓权限
        adjustment.allow_add_position = (
            params["allow_add"] and 
            current_positions > 0 and
            current_positions < params["max_positions"]
        )
        
        # 计算建议仓位大小
        # 基于风险比例和 ATR
        risk_amount = account_balance * self.config.base_risk_percent / 100
        sl_distance = atr * adjustment.sl_multiplier
        if sl_distance > 0:
            adjustment.position_size = risk_amount / sl_distance
        
        adjustment.reason = f"Sub-Type: {sub_type.value}, Risk Level: {params['risk_level'].value}"
        
        return adjustment
    
    def calculate_position_size(
        self,
        account_balance: float,
        risk_percent: float,
        sl_distance: float,
        point_value: float = 1.0,
    ) -> float:
        """
        计算仓位大小
        
        Args:
            account_balance: 账户余额
            risk_percent: 风险比例
            sl_distance: 止损距离 (点数)
            point_value: 每点价值
            
        Returns:
            仓位大小 (手数)
        """
        if sl_distance <= 0:
            return 0.0
        
        risk_amount = account_balance * risk_percent / 100
        position_size = risk_amount / (sl_distance * point_value)
        
        return max(0.01, position_size)  # 最小 0.01 手
    
    def can_add_position(
        self,
        sub_type: RegimeSubType,
        current_positions: int,
        position_profit_atr: float = 0.0,
    ) -> bool:
        """
        检查是否可以加仓
        
        Args:
            sub_type: 当前 Regime Sub-Type
            current_positions: 当前持仓数
            position_profit_atr: 当前持仓盈利 (ATR 单位)
            
        Returns:
            是否可以加仓
        """
        params = self.subtype_params.get(sub_type, {})
        
        if not params.get("allow_add", False):
            return False
        
        if current_positions >= params.get("max_positions", 1):
            return False
        
        # 检查当前持仓是否有足够盈利
        if position_profit_atr < self.config.add_position_min_profit_atr:
            return False
        
        return True
    
    def get_trail_stop_params(
        self,
        sub_type: RegimeSubType,
        profit_atr: float,
    ) -> Dict:
        """
        获取移动止损参数
        
        Args:
            sub_type: 当前 Regime Sub-Type
            profit_atr: 当前盈利 (ATR 单位)
            
        Returns:
            Dict with trail_stop parameters
        """
        params = {
            "enable": True,
            "trigger_atr": 1.0,    # 盈利超过此值启动
            "distance_atr": 0.5,   # 距离当前价格
            "step_atr": 0.2,       # 每次移动步长
        }
        
        if sub_type == RegimeSubType.TVB_TRUE_TREND:
            # 真趋势：宽松移动止损
            params["trigger_atr"] = 1.5
            params["distance_atr"] = 1.0
            params["step_atr"] = 0.5
        
        elif sub_type == RegimeSubType.TVA_EMOTION_PULSE:
            # 情绪脉冲：快速保护
            params["trigger_atr"] = 0.5
            params["distance_atr"] = 0.3
            params["step_atr"] = 0.1
        
        elif sub_type in [
            RegimeSubType.RVA_NEWS_CHOP,
            RegimeSubType.RVB_FALSE_BREAKOUT,
        ]:
            # 震荡环境：快速锁定利润
            params["trigger_atr"] = 0.5
            params["distance_atr"] = 0.3
        
        return params
    
    def calculate_for_dataframe(
        self,
        regime_result: pd.DataFrame,
        account_balance: float = 10000.0,
        atr_series: Optional[pd.Series] = None,
    ) -> pd.DataFrame:
        """
        为 DataFrame 中的每一行计算风险调整
        
        Args:
            regime_result: Regime Filter 结果
            account_balance: 账户余额
            atr_series: ATR 序列
            
        Returns:
            DataFrame with risk adjustment columns
        """
        results = []
        
        for i, (idx, row) in enumerate(regime_result.iterrows()):
            sub_type = row.get("sub_type", RegimeSubType.UNKNOWN)
            q_score = row.get("q_score", 0.5)
            atr = atr_series.iloc[i] if atr_series is not None else 10.0
            
            adj = self.get_risk_adjustment(
                sub_type=sub_type,
                q_score=q_score,
                account_balance=account_balance,
                atr=atr,
            )
            
            results.append({
                "sl_mult": adj.sl_multiplier,
                "tp_mult": adj.tp_multiplier,
                "allow_new": adj.allow_new_position,
                "allow_add": adj.allow_add_position,
                "max_pos": adj.max_positions,
                "risk_level": adj.risk_level.value,
                "position_size": adj.position_size,
            })
        
        return pd.DataFrame(results, index=regime_result.index)
