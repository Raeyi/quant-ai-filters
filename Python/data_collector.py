"""
数据收集器 - M6.4

收集每根K线的特征数据，用于后续 ML/RL 训练。

输出格式：features_train.csv
包含：市场特征、Regime状态、交易决策、交易结果
"""
from __future__ import annotations

import argparse
import json
from dataclasses import dataclass, field, asdict
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

import numpy as np
import pandas as pd

from core.data import load_data
from core.settings import load_settings, resolve_data_path
from regime.regime_filter import RegimeFilter, RegimeFilterParams, RegimeState
from regime.regime_indicators import RegimeIndicators, RegimeIndicatorsParams
from regime.market_quality import MarketQuality, MarketQualityParams
from strategies.boll_mean_reversion import BollMeanReversionStrategy, BollMeanReversionParams
from strategies.trend_pullback import TrendPullbackStrategy, TrendPullbackParams


@dataclass
class BarFeatures:
    """单根K线特征"""
    # 时间
    time: str
    hour: int
    day_of_week: int
    session: int  # 0=asia, 1=europe, 2=us, 3=overlap
    
    # 价格
    open: float
    high: float
    low: float
    close: float
    
    # 基础指标
    atr: float
    adx: float
    rsi: float
    
    # 市场质量
    efficiency: float
    false_breakout_rate: float
    q_score: float
    
    # Regime 状态
    regime_state: int  # 0=ACTIVE, 1=STANDBY, 2=TRANSITION
    regime_type: int   # 0=RANGE, 1=TREND
    sub_type: int      # 0-7
    trend_direction: int  # -1, 0, 1
    
    # 波动率状态
    volatility_state: int  # 0=LOW, 1=NORMAL, 2=HIGH
    
    # 策略信号
    boll_signal: int    # -1, 0, 1
    trend_signal: int   # -1, 0, 1
    final_signal: int   # -1, 0, 1
    
    # 交易参数
    position_size: float
    sl_mult: float
    tp_mult: float
    
    # 结果标签（事后标注）
    pnl: float = 0.0
    holding_bars: int = 0
    win: bool = False
    labeled: bool = False


class DataCollector:
    """数据收集器"""
    
    # Session 定义
    ASIA_START = 0    # 00:00 UTC
    ASIA_END = 8
    EUROPE_START = 7
    EUROPE_END = 16
    US_START = 13
    US_END = 21
    
    def __init__(
        self,
        regime_params: Optional[RegimeFilterParams] = None,
        mq_params: Optional[MarketQualityParams] = None,
    ):
        self.regime_filter = RegimeFilter(regime_params)
        self.regime_indicators = RegimeIndicators(
            RegimeIndicatorsParams() if not regime_params else 
            RegimeIndicatorsParams()
        )
        self.market_quality = MarketQuality(mq_params)
        
        # 策略
        self.boll_strategy = None
        self.trend_strategy = None
        
        # 收集的数据
        self.features: List[BarFeatures] = []
        
    def initialize_strategies(self, point: float = 0.01):
        """初始化策略"""
        self.boll_strategy = BollMeanReversionStrategy(
            BollMeanReversionParams(logic_mode="enhanced", point=point)
        )
        self.trend_strategy = TrendPullbackStrategy(
            TrendPullbackParams(point=point)
        )
    
    def get_session(self, hour: int) -> int:
        """获取交易时段"""
        if self.ASIA_START <= hour < self.ASIA_END:
            if self.EUROPE_START <= hour < self.EUROPE_END:
                return 3  # overlap
            return 0  # asia
        elif self.EUROPE_START <= hour < self.EUROPE_END:
            if self.US_START <= hour < self.US_END:
                return 3  # overlap
            return 1  # europe
        elif self.US_START <= hour < self.US_END:
            return 2  # us
        return 0  # default to asia
    
    def collect(
        self,
        df: pd.DataFrame,
        df_htf: Optional[pd.DataFrame] = None,
        point: float = 0.01,
    ) -> pd.DataFrame:
        """
        收集特征数据
        
        Args:
            df: M5 OHLCV 数据
            df_htf: M15 OHLCV 数据
            point: 点值
            
        Returns:
            DataFrame with all features
        """
        print("Collecting features...")
        
        # 初始化
        self.initialize_strategies(point)
        
        # 计算 Regime
        print("  Calculating regime indicators...")
        regime_result = self.regime_filter.calculate(df)
        indicators = self.regime_indicators.calculate(df)
        quality = self.market_quality.calculate(df)
        
        # 生成策略信号
        print("  Generating strategy signals...")
        boll_signals = self.boll_strategy.generate_signals(df)
        trend_signals = self.trend_strategy.generate_signals(df, df_htf)
        
        # 收集每根K线的特征
        print("  Collecting bar features...")
        self.features = []
        
        for i, (idx, row) in enumerate(df.iterrows()):
            if i < 50:  # 预热期
                continue
            
            # 时间特征
            hour = idx.hour
            day_of_week = idx.weekday()
            session = self.get_session(hour)
            
            # 基础指标
            atr = indicators.iloc[i]["atr"] if i < len(indicators) else 0
            adx = indicators.iloc[i]["adx"] if i < len(indicators) else 0
            rsi = indicators.iloc[i].get("rsi", 50) if i < len(indicators) else 50
            
            # 市场质量
            eff = quality.iloc[i]["efficiency"] if i < len(quality) else 0.5
            fbr = quality.iloc[i]["false_breakout_rate"] if i < len(quality) else 0.5
            q_score = quality.iloc[i]["q_score"] if i < len(quality) else 0.5
            
            # Regime 状态
            regime_state = regime_result.iloc[i]["regime_state"]
            regime_type = regime_result.iloc[i].get("regime_type", 0)
            sub_type = regime_result.iloc[i].get("sub_type", 0)
            trend_dir = regime_result.iloc[i].get("trend_direction", 0)
            vol_state = regime_result.iloc[i].get("volatility_state", 1)
            
            # 转换为整数编码
            state_map = {RegimeState.ACTIVE: 0, RegimeState.STANDBY: 1, RegimeState.TRANSITION: 2}
            regime_state_int = state_map.get(regime_state, 1)
            
            # 策略信号
            boll_sig = int(boll_signals.iloc[i]) if i < len(boll_signals) else 0
            trend_sig = int(trend_signals.iloc[i]) if i < len(trend_signals) else 0
            
            # 最终信号（简化：只在 ACTIVE 时允许）
            final_sig = 0
            if regime_state == RegimeState.ACTIVE:
                final_sig = boll_sig if boll_sig != 0 else trend_sig
            
            # 风险参数
            sl_mult = regime_result.iloc[i].get("sl_multiplier", 1.0)
            tp_mult = regime_result.iloc[i].get("tp_multiplier", 1.0)
            
            feature = BarFeatures(
                time=idx.isoformat(),
                hour=hour,
                day_of_week=day_of_week,
                session=session,
                open=row["open"],
                high=row["high"],
                low=row["low"],
                close=row["close"],
                atr=float(atr),
                adx=float(adx),
                rsi=float(rsi),
                efficiency=float(eff),
                false_breakout_rate=float(fbr),
                q_score=float(q_score),
                regime_state=regime_state_int,
                regime_type=int(regime_type) if not isinstance(regime_type, int) else regime_type,
                sub_type=int(sub_type) if not isinstance(sub_type, int) else sub_type,
                trend_direction=int(trend_dir),
                volatility_state=int(vol_state) if not isinstance(vol_state, int) else vol_state,
                boll_signal=boll_sig,
                trend_signal=trend_sig,
                final_signal=final_sig,
                position_size=0.01,
                sl_mult=float(sl_mult),
                tp_mult=float(tp_mult),
            )
            
            self.features.append(feature)
        
        print(f"  Collected {len(self.features)} bars")
        
        # 转换为 DataFrame
        return pd.DataFrame([asdict(f) for f in self.features])
    
    def label_trades(
        self,
        df: pd.DataFrame,
        features_df: pd.DataFrame,
        point: float = 0.01,
        lookforward: int = 24,  # 最大持仓K线数
    ) -> pd.DataFrame:
        """
        标注交易结果
        
        Args:
            df: 原始 OHLCV 数据
            features_df: 特征 DataFrame
            point: 点值
            lookforward: 最大持仓K线数
            
        Returns:
            标注后的 DataFrame
        """
        print("Labeling trade results...")
        
        close = df["close"].values
        
        for i, row in features_df.iterrows():
            if row["final_signal"] == 0:
                continue
            
            # 计算持仓期间收益
            signal = row["final_signal"]
            entry_price = row["close"]
            entry_idx = i
            
            # 简化：固定止损止盈
            atr = row["atr"]
            sl_mult = row["sl_mult"]
            tp_mult = row["tp_mult"]
            
            if signal > 0:  # 多头
                sl_price = entry_price - atr * sl_mult
                tp_price = entry_price + atr * tp_mult
            else:  # 空头
                sl_price = entry_price + atr * sl_mult
                tp_price = entry_price - atr * tp_mult
            
            # 模拟持仓
            pnl = 0.0
            holding = 0
            win = False
            
            for j in range(1, min(lookforward + 1, len(close) - entry_idx)):
                holding = j
                future_idx = entry_idx + j
                future_close = close[future_idx]
                future_high = df.iloc[future_idx]["high"]
                future_low = df.iloc[future_idx]["low"]
                
                if signal > 0:  # 多头
                    if future_low <= sl_price:
                        pnl = -abs(entry_price - sl_price) / point * 100
                        break
                    if future_high >= tp_price:
                        pnl = abs(tp_price - entry_price) / point * 100
                        win = True
                        break
                else:  # 空头
                    if future_high >= sl_price:
                        pnl = -abs(sl_price - entry_price) / point * 100
                        break
                    if future_low <= tp_price:
                        pnl = abs(entry_price - tp_price) / point * 100
                        win = True
                        break
            
            # 如果没有触发止损止盈，按市价平仓
            if pnl == 0 and holding > 0:
                exit_price = close[entry_idx + holding]
                pnl = (exit_price - entry_price) * signal / point * 100
                win = pnl > 0
            
            # 更新特征
            features_df.at[i, "pnl"] = pnl
            features_df.at[i, "holding_bars"] = holding
            features_df.at[i, "win"] = win
            features_df.at[i, "labeled"] = True
        
        labeled_count = features_df["labeled"].sum()
        print(f"  Labeled {labeled_count} trades")
        
        return features_df
    
    def save(
        self,
        features_df: pd.DataFrame,
        output_path: str,
    ):
        """保存特征数据"""
        output = Path(output_path)
        output.parent.mkdir(parents=True, exist_ok=True)
        features_df.to_csv(output, index=False)
        print(f"Saved {len(features_df)} rows to {output}")


def main():
    parser = argparse.ArgumentParser(description="Data Collector for ML/RL Training")
    parser.add_argument("--config", default="config.json")
    parser.add_argument("--data", required=True, help="M5 data path")
    parser.add_argument("--data-htf", default="", help="M15 data path")
    parser.add_argument("--output", default="data/features_train.csv")
    parser.add_argument("--label", action="store_true", help="Label trade results")
    
    args = parser.parse_args()
    
    # 加载配置
    settings = load_settings(args.config)
    point = settings.broker.point
    
    # 加载数据
    data_path = Path(resolve_data_path(settings.paths, "mt5", args.data))
    df, _ = load_data(str(data_path), "mt5")
    
    df_htf = None
    if args.data_htf:
        htf_path = Path(resolve_data_path(settings.paths, "mt5", args.data_htf))
        if htf_path.exists():
            df_htf, _ = load_data(str(htf_path), "mt5")
    
    print(f"Loaded {len(df)} bars")
    
    # 收集特征
    collector = DataCollector()
    features_df = collector.collect(df, df_htf, point)
    
    # 标注结果
    if args.label:
        features_df = collector.label_trades(df, features_df, point)
    
    # 保存
    collector.save(features_df, args.output)
    
    # 统计
    print(f"\n{'='*50}")
    print("Data Summary")
    print(f"{'='*50}")
    print(f"Total bars: {len(features_df)}")
    print(f"Signal bars: {(features_df['final_signal'] != 0).sum()}")
    print(f"ACTIVE bars: {(features_df['regime_state'] == 0).sum()}")
    if args.label:
        trades = features_df[features_df["labeled"]]
        if len(trades) > 0:
            print(f"Labeled trades: {len(trades)}")
            print(f"Win rate: {trades['win'].mean()*100:.1f}%")
            print(f"Avg PnL: {trades['pnl'].mean():.2f}")


if __name__ == "__main__":
    main()
