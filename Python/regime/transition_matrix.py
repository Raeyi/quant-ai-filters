"""
Transition Matrix - Regime 转移概率矩阵

Phase 4 功能：
1. 统计历史 Regime 转移概率
2. 构建 TRANSITION_MATRIX
3. 提前布局逻辑：预测下一个 Regime 并提前调整策略

使用方法：
- 分析历史数据，了解不同 Regime 之间的转换规律
- 实时预测当前 Regime 可能转换到什么状态
- 提前调整策略参数或准备新策略
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

import numpy as np
import pandas as pd

from regime.regime_subtype import RegimeSubType


@dataclass
class TransitionStats:
    """转移统计"""
    from_type: RegimeSubType
    to_type: RegimeSubType
    count: int = 0
    probability: float = 0.0
    avg_duration: float = 0.0  # 转换前的平均持续时间


@dataclass
class TransitionPrediction:
    """转移预测"""
    current_type: RegimeSubType
    predicted_next: RegimeSubType
    probability: float = 0.0
    confidence: float = 0.0
    time_horizon: int = 5  # 预测时间范围 (K线数)
    
    # 建议行动
    suggested_action: str = ""
    prepare_strategies: List[str] = field(default_factory=list)


class TransitionMatrix:
    """
    Regime 转移概率矩阵
    
    用于：
    1. 分析历史 Regime 转换规律
    2. 预测当前 Regime 可能的转换方向
    3. 提前准备策略调整
    """
    
    def __init__(self):
        # 转移计数矩阵
        self.transition_counts: Dict[Tuple[RegimeSubType, RegimeSubType], int] = {}
        
        # 持续时间记录
        self.duration_records: Dict[RegimeSubType, List[int]] = {}
        
        # 计算后的概率矩阵
        self.probability_matrix: Dict[RegimeSubType, Dict[RegimeSubType, float]] = {}
        
        # 平均持续时间
        self.avg_durations: Dict[RegimeSubType, float] = {}
        
        # 所有已见过的 Sub-Type
        self.all_types: List[RegimeSubType] = []
    
    def fit(self, sub_types: pd.Series) -> "TransitionMatrix":
        """
        从历史数据构建转移矩阵
        
        Args:
            sub_types: Regime Sub-Type 序列 (每个 K 线一个值)
            
        Returns:
            self (链式调用)
        """
        if len(sub_types) < 2:
            return self
        
        # 重置
        self.transition_counts = {}
        self.duration_records = {}
        self.all_types = []
        
        # 统计转移
        prev_type = None
        current_duration = 0
        
        for st in sub_types:
            if not isinstance(st, RegimeSubType):
                continue
            
            if st not in self.all_types:
                self.all_types.append(st)
            
            if prev_type is not None and prev_type != st:
                # 记录转移
                key = (prev_type, st)
                self.transition_counts[key] = self.transition_counts.get(key, 0) + 1
                
                # 记录持续时间
                if prev_type not in self.duration_records:
                    self.duration_records[prev_type] = []
                self.duration_records[prev_type].append(current_duration)
                
                current_duration = 0
            
            current_duration += 1
            prev_type = st
        
        # 记录最后一个状态的持续时间
        if prev_type and prev_type not in self.duration_records:
            self.duration_records[prev_type] = []
        if prev_type:
            self.duration_records[prev_type].append(current_duration)
        
        # 计算概率矩阵
        self._calculate_probabilities()
        
        return self
    
    def _calculate_probabilities(self):
        """计算转移概率"""
        self.probability_matrix = {}
        self.avg_durations = {}
        
        # 计算每个状态的平均持续时间
        for st, durations in self.duration_records.items():
            if durations:
                self.avg_durations[st] = np.mean(durations)
        
        # 计算转移概率
        for from_type in self.all_types:
            self.probability_matrix[from_type] = {}
            
            # 计算从 from_type 出发的所有转移
            total = 0
            for to_type in self.all_types:
                key = (from_type, to_type)
                count = self.transition_counts.get(key, 0)
                total += count
                self.probability_matrix[from_type][to_type] = count
            
            # 归一化
            if total > 0:
                for to_type in self.all_types:
                    self.probability_matrix[from_type][to_type] /= total
    
    def predict_transition(
        self,
        current_type: RegimeSubType,
        current_duration: int = 0
    ) -> TransitionPrediction:
        """
        预测下一个可能的 Regime
        
        Args:
            current_type: 当前 Regime Sub-Type
            current_duration: 当前 Regime 已持续时间 (K线数)
            
        Returns:
            TransitionPrediction
        """
        if current_type not in self.probability_matrix:
            return TransitionPrediction(
                current_type=current_type,
                predicted_next=RegimeSubType.UNKNOWN,
                probability=0.0,
                suggested_action="No historical data",
            )
        
        # 获取转移概率
        transitions = self.probability_matrix[current_type]
        
        if not transitions:
            return TransitionPrediction(
                current_type=current_type,
                predicted_next=current_type,  # 假设保持不变
                probability=0.5,
                suggested_action="Maintain current strategy",
            )
        
        # 找出最可能的下一个状态
        sorted_transitions = sorted(
            transitions.items(),
            key=lambda x: x[1],
            reverse=True
        )
        
        predicted_next = sorted_transitions[0][0]
        probability = sorted_transitions[0][1]
        
        # 考虑持续时间
        avg_duration = self.avg_durations.get(current_type, 20)
        
        # 如果持续时间接近平均值，转换概率增加
        duration_factor = 1.0
        if current_duration > avg_duration * 0.8:
            duration_factor = min(1.5, 1.0 + (current_duration - avg_duration * 0.8) / avg_duration)
        
        # 生成建议
        action, strategies = self._generate_transition_advice(
            current_type, predicted_next, probability * duration_factor
        )
        
        return TransitionPrediction(
            current_type=current_type,
            predicted_next=predicted_next,
            probability=probability,
            confidence=probability * duration_factor,
            time_horizon=max(1, int(avg_duration - current_duration)),
            suggested_action=action,
            prepare_strategies=strategies,
        )
    
    def _generate_transition_advice(
        self,
        current: RegimeSubType,
        predicted: RegimeSubType,
        confidence: float
    ) -> Tuple[str, List[str]]:
        """生成转换建议"""
        strategies = []
        
        # 趋势 → 震荡
        if current in [
            RegimeSubType.TVB_TRUE_TREND,
            RegimeSubType.TN_MILD_TREND,
            RegimeSubType.TVA_EMOTION_PULSE,
        ] and predicted in [
            RegimeSubType.RN_NORMAL_RANGE,
            RegimeSubType.RVB_FALSE_BREAKOUT,
            RegimeSubType.RVA_NEWS_CHOP,
        ]:
            action = "Prepare for range trading"
            strategies = ["BollMR"]
            if confidence > 0.5:
                action = "Reduce trend positions, prepare mean reversion"
        
        # 震荡 → 趋势
        elif current in [
            RegimeSubType.RN_NORMAL_RANGE,
            RegimeSubType.RVB_FALSE_BREAKOUT,
        ] and predicted in [
            RegimeSubType.TVB_TRUE_TREND,
            RegimeSubType.TN_MILD_TREND,
        ]:
            action = "Watch for trend emergence"
            strategies = ["TrendPullback"]
        
        # 任何 → 消息震荡
        elif predicted == RegimeSubType.RVA_NEWS_CHOP:
            action = "Prepare for volatility - reduce positions"
            strategies = []
        
        # 任何 → 真趋势
        elif predicted == RegimeSubType.TVB_TRUE_TREND:
            action = "Prepare for strong trend"
            strategies = ["TrendPullback"]
        
        # 保持不变
        elif current == predicted:
            action = "Maintain current strategy"
            strategies = []
        
        else:
            action = "Monitor for regime change"
            strategies = []
        
        return action, strategies
    
    def get_matrix_dataframe(self) -> pd.DataFrame:
        """获取转移矩阵的 DataFrame 表示"""
        if not self.all_types:
            return pd.DataFrame()
        
        data = {}
        for from_type in self.all_types:
            data[from_type.value] = [
                self.probability_matrix[from_type].get(to_type, 0.0)
                for to_type in self.all_types
            ]
        
        df = pd.DataFrame(
            data,
            index=[t.value for t in self.all_types]
        )
        
        return df
    
    def get_steady_state(self) -> Dict[RegimeSubType, float]:
        """
        计算稳态分布 (长期来看各 Regime 的占比)
        
        使用幂迭代法
        """
        if not self.all_types:
            return {}
        
        n = len(self.all_types)
        
        # 构建转移矩阵
        P = np.zeros((n, n))
        for i, from_type in enumerate(self.all_types):
            for j, to_type in enumerate(self.all_types):
                P[i, j] = self.probability_matrix[from_type].get(to_type, 0.0)
            
            # 确保每行和为 1
            row_sum = P[i].sum()
            if row_sum > 0:
                P[i] /= row_sum
            else:
                P[i] = 1.0 / n  # 均匀分布
        
        # 幂迭代求稳态
        pi = np.ones(n) / n
        for _ in range(100):
            pi_new = pi @ P
            if np.allclose(pi, pi_new, atol=1e-8):
                break
            pi = pi_new
        
        return {t: float(pi[i]) for i, t in enumerate(self.all_types)}
    
    def summary(self) -> str:
        """生成摘要报告"""
        lines = ["=== Transition Matrix Summary ==="]
        
        lines.append(f"\nTotal Regime Types: {len(self.all_types)}")
        
        lines.append("\nAverage Durations (bars):")
        for st, dur in sorted(self.avg_durations.items(), key=lambda x: -x[1]):
            lines.append(f"  {st.value}: {dur:.1f}")
        
        lines.append("\nTop Transitions:")
        sorted_transitions = sorted(
            self.transition_counts.items(),
            key=lambda x: -x[1]
        )[:10]
        for (from_t, to_t), count in sorted_transitions:
            prob = self.probability_matrix[from_t].get(to_t, 0.0)
            lines.append(f"  {from_t.value} → {to_t.value}: {prob:.2%} ({count} times)")
        
        return "\n".join(lines)


def build_transition_matrix_from_backtest(
    df: pd.DataFrame,
    regime_result: pd.DataFrame
) -> TransitionMatrix:
    """
    从回测结果构建转移矩阵
    
    Args:
        df: OHLCV DataFrame
        regime_result: Regime Filter 结果
        
    Returns:
        TransitionMatrix
    """
    matrix = TransitionMatrix()
    
    if "sub_type" not in regime_result.columns:
        return matrix
    
    matrix.fit(regime_result["sub_type"])
    
    return matrix
