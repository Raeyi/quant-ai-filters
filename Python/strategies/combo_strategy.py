"""
Combo Strategy - 多策略组合回测
与 MT5 Strategy_Combo.mqh 对齐

组合逻辑：
1. 各策略独立运行（自带过滤条件）
2. 收集所有策略信号
3. 按模式组合决策
"""
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import List, Optional, Tuple

import numpy as np
import pandas as pd

from strategies.boll_mean_reversion import BollMeanReversionParams, BollMeanReversionStrategy
from strategies.trend_pullback import TrendPullbackParams, TrendPullbackStrategy


class ComboMode(Enum):
    """组合模式"""
    FIRST_SIGNAL = "first_signal"           # 先到先得
    SAME_DIRECTION = "same_direction"       # 同向叠加
    MAJORITY_VOTE = "majority_vote"         # 多数投票
    PRIORITY_FIRST = "priority_first"       # 优先级
    CONFLICT_SKIP = "conflict_skip"         # 冲突跳过
    BEST_CONFIDENCE = "best_confidence"     # 最高置信度


@dataclass
class ComboParams:
    """组合策略参数"""
    mode: ComboMode = ComboMode.CONFLICT_SKIP
    min_agreement: int = 2                  # 多数投票最小同意数
    confidence_boost: float = 0.1           # 同向信号置信度加成
    log_signals: bool = True                # 是否打印信号日志


@dataclass
class StrategySignal:
    """策略信号"""
    strategy_name: str
    signal: int              # 1=多, -1=空, 0=无
    confidence: float = 0.5
    time: Optional[pd.Timestamp] = None
    price: float = 0.0
    reason: str = ""


@dataclass
class ComboStats:
    """组合统计"""
    total_bars: int = 0
    boll_signals: int = 0
    tp_signals: int = 0
    both_signals: int = 0
    same_direction: int = 0
    conflict_skip: int = 0
    boll_only: int = 0
    tp_only: int = 0
    final_signals: int = 0


class ComboStrategy:
    """多策略组合"""
    
    def __init__(
        self,
        boll_params: Optional[BollMeanReversionParams] = None,
        tp_params: Optional[TrendPullbackParams] = None,
        combo_params: Optional[ComboParams] = None,
    ):
        # 默认参数
        if boll_params is None:
            boll_params = BollMeanReversionParams(
                logic_mode="enhanced",
                allowed_start_hour=2,    # 亚欧盘
                allowed_end_hour=14,
            )
        if tp_params is None:
            tp_params = TrendPullbackParams(
                session="us,overlap",    # 欧美盘
            )
        if combo_params is None:
            combo_params = ComboParams()
        
        self.boll_params = boll_params
        self.tp_params = tp_params
        self.combo_params = combo_params
        
        # 策略实例
        self.boll_strategy = BollMeanReversionStrategy(boll_params)
        self.tp_strategy = TrendPullbackStrategy(tp_params)
        
        # 统计
        self.stats = ComboStats()
        
        # 信号记录（用于分析）
        self.signal_log: List[dict] = []
    
    def generate_signals(
        self,
        df: pd.DataFrame,
        df_htf: Optional[pd.DataFrame] = None,
    ) -> pd.Series:
        """
        生成组合信号
        
        Args:
            df: 低时间周期数据 (M5)
            df_htf: 高时间周期数据 (M15)，用于 TrendPullback
        """
        # 1. 分别生成各策略信号
        boll_signals = self.boll_strategy.generate_signals(df)
        tp_signals = self.tp_strategy.generate_signals(df, df_htf)
        
        # 2. 组合信号
        combo_signals = pd.Series(0.0, index=df.index)
        
        self.stats = ComboStats(total_bars=len(df))
        
        for i, (time, boll_sig, tp_sig) in enumerate(zip(df.index, boll_signals, tp_signals)):
            # 收集有效信号
            signals: List[StrategySignal] = []
            
            if boll_sig != 0:
                signals.append(StrategySignal(
                    strategy_name="BollMR",
                    signal=int(np.sign(boll_sig)),
                    confidence=abs(boll_sig) if abs(boll_sig) <= 1.0 else 0.5,
                    time=time,
                    price=df["close"].iloc[i],
                ))
                self.stats.boll_signals += 1
            
            if tp_sig != 0:
                signals.append(StrategySignal(
                    strategy_name="TrendPullback",
                    signal=int(np.sign(tp_sig)),
                    confidence=abs(tp_sig) if abs(tp_sig) <= 1.0 else 0.5,
                    time=time,
                    price=df["close"].iloc[i],
                ))
                self.stats.tp_signals += 1
            
            # 组合决策
            final_signal = self._combine_signals(signals, time)
            combo_signals.iloc[i] = final_signal.signal * final_signal.confidence
            
            if final_signal.signal != 0:
                self.stats.final_signals += 1
            
            # 记录信号日志
            if self.combo_params.log_signals and len(signals) > 0:
                self.signal_log.append({
                    "time": time,
                    "boll_signal": boll_sig,
                    "tp_signal": tp_sig,
                    "final_signal": final_signal.signal,
                    "final_confidence": final_signal.confidence,
                    "source": final_signal.reason,
                })
        
        return combo_signals
    
    def _combine_signals(
        self,
        signals: List[StrategySignal],
        time: pd.Timestamp,
    ) -> StrategySignal:
        """组合信号决策"""
        
        # 无信号
        if len(signals) == 0:
            return StrategySignal(
                strategy_name="none",
                signal=0,
                time=time,
            )
        
        # 单一信号
        if len(signals) == 1:
            if signals[0].strategy_name == "BollMR":
                self.stats.boll_only += 1
            else:
                self.stats.tp_only += 1
            return signals[0]
        
        # 多个信号
        self.stats.both_signals += 1
        
        # 统计方向
        long_count = sum(1 for s in signals if s.signal > 0)
        short_count = sum(1 for s in signals if s.signal < 0)
        
        # 按模式组合
        mode = self.combo_params.mode
        
        if mode == ComboMode.FIRST_SIGNAL:
            return SignalSignal(
                strategy_name="combo_first",
                signal=signals[0].signal,
                confidence=signals[0].confidence,
                time=time,
                reason="first_signal",
            )
        
        elif mode == ComboMode.SAME_DIRECTION:
            if long_count > 0 and short_count > 0:
                self.stats.conflict_skip += 1
                return StrategySignal(
                    strategy_name="combo_skip",
                    signal=0,
                    time=time,
                    reason="conflict_skip",
                )
            # 同向叠加
            self.stats.same_direction += 1
            sig = signals[0]
            total_conf = sum(s.confidence for s in signals) / len(signals)
            return StrategySignal(
                strategy_name="combo_same",
                signal=sig.signal,
                confidence=min(total_conf + self.combo_params.confidence_boost, 1.0),
                time=time,
                reason="same_direction",
            )
        
        elif mode == ComboMode.MAJORITY_VOTE:
            agree_count = max(long_count, short_count)
            if agree_count >= self.combo_params.min_agreement:
                self.stats.same_direction += 1
                direction = 1 if long_count > short_count else -1
                return StrategySignal(
                    strategy_name="combo_majority",
                    signal=direction,
                    confidence=0.7,
                    time=time,
                    reason="majority_vote",
                )
            else:
                self.stats.conflict_skip += 1
                return StrategySignal(
                    strategy_name="combo_skip",
                    signal=0,
                    time=time,
                    reason="no_majority",
                )
        
        elif mode == ComboMode.PRIORITY_FIRST:
            # 优先级：第一个策略优先
            return StrategySignal(
                strategy_name="combo_priority",
                signal=signals[0].signal,
                confidence=signals[0].confidence,
                time=time,
                reason="priority_first",
            )
        
        elif mode == ComboMode.BEST_CONFIDENCE:
            best = max(signals, key=lambda s: s.confidence)
            return StrategySignal(
                strategy_name="combo_best",
                signal=best.signal,
                confidence=best.confidence,
                time=time,
                reason="best_confidence",
            )
        
        else:  # CONFLICT_SKIP (默认)
            if long_count > 0 and short_count > 0:
                self.stats.conflict_skip += 1
                return StrategySignal(
                    strategy_name="combo_skip",
                    signal=0,
                    time=time,
                    reason="conflict_skip",
                )
            # 同向
            self.stats.same_direction += 1
            sig = signals[0]
            total_conf = sum(s.confidence for s in signals) / len(signals)
            return StrategySignal(
                strategy_name="combo_agree",
                signal=sig.signal,
                confidence=min(total_conf + self.combo_params.confidence_boost, 1.0),
                time=time,
                reason="agree",
            )
    
    def get_signal_dataframe(self) -> pd.DataFrame:
        """获取信号记录 DataFrame"""
        if not self.signal_log:
            return pd.DataFrame()
        return pd.DataFrame(self.signal_log)
    
    def get_stats_summary(self) -> dict:
        """获取统计摘要"""
        return {
            "total_bars": self.stats.total_bars,
            "boll_signals": self.stats.boll_signals,
            "tp_signals": self.stats.tp_signals,
            "both_signals": self.stats.both_signals,
            "same_direction": self.stats.same_direction,
            "conflict_skip": self.stats.conflict_skip,
            "boll_only": self.stats.boll_only,
            "tp_only": self.stats.tp_only,
            "final_signals": self.stats.final_signals,
            "signal_rate": self.stats.final_signals / max(self.stats.total_bars, 1),
            "conflict_rate": self.stats.conflict_skip / max(self.stats.both_signals, 1),
        }
