"""
Regime Filter 参数优化脚本

M6.2: Q-Score 参数网格搜索
优化目标：
- MQ_Efficiency_Baseline: 效率基准值
- MQ_FBR_Baseline: 假突破率基准值
- RF_Q_Score_Standby: STANDBY 阈值
- RF_Q_Score_Active: ACTIVE 阈值
"""
from __future__ import annotations

import argparse
import itertools
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import numpy as np
import pandas as pd

from core.config import BacktestConfig
from core.data import load_data
from core.settings import load_settings, resolve_data_path
from core.engine import run_backtest
from regime.regime_filter import RegimeFilter, RegimeFilterParams, RegimeState
from regime.market_quality import MarketQuality, MarketQualityParams
from strategies.boll_mean_reversion import BollMeanReversionStrategy, BollMeanReversionParams
from strategies.trend_pullback import TrendPullbackStrategy, TrendPullbackParams


@dataclass
class RegimeOptResult:
    """优化结果"""
    params: Dict
    metrics: Dict
    

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Regime Parameter Optimization")
    parser.add_argument("--config", default="config.json")
    parser.add_argument("--data", required=True, help="M5 data path")
    parser.add_argument("--data-htf", default="", help="M15 data path")
    parser.add_argument("--output", default="data/regime_optimize_results.csv")
    
    # Q-Score 参数范围
    parser.add_argument("--eff-baselines", default="0.10,0.15,0.20", 
                        help="Efficiency baseline values")
    parser.add_argument("--fbr-baselines", default="0.40,0.50,0.60", 
                        help="False breakout rate baseline values")
    
    # 阈值参数范围
    parser.add_argument("--q-standby-thresholds", default="0.30,0.35,0.40",
                        help="Q-Score STANDBY thresholds")
    parser.add_argument("--q-active-thresholds", default="0.40,0.45,0.50",
                        help="Q-Score ACTIVE thresholds")
    
    # 限制
    parser.add_argument("--max-tests", type=int, default=50)
    
    return parser.parse_args()


def parse_list(s: str) -> List[float]:
    """解析逗号分隔的数值列表"""
    return [float(x.strip()) for x in s.split(",")]


def run_regime_backtest(
    df: pd.DataFrame,
    df_htf: Optional[pd.DataFrame],
    regime_params: RegimeFilterParams,
    mq_params: MarketQualityParams,
    config: BacktestConfig,
) -> Dict:
    """
    运行单次 Regime 过滤回测
    
    Returns:
        包含统计指标的字典
    """
    # 初始化 Regime Filter
    regime_filter = RegimeFilter(regime_params)
    regime_result = regime_filter.calculate(df)
    
    # 初始化策略
    boll_params = BollMeanReversionParams(logic_mode="enhanced", point=config.point)
    trend_params = TrendPullbackParams(point=config.point)
    
    boll_strategy = BollMeanReversionStrategy(boll_params)
    trend_strategy = TrendPullbackStrategy(trend_params)
    
    # 生成信号
    boll_signals = boll_strategy.generate_signals(df)
    trend_signals = trend_strategy.generate_signals(df, df_htf)
    
    # 应用 Regime 过滤
    filtered_signals = boll_signals.copy()
    
    # 只在 ACTIVE 状态允许交易
    active_mask = regime_result["regime_state"] == RegimeState.ACTIVE
    filtered_signals = filtered_signals.where(active_mask, 0)
    
    # 运行回测
    result = run_backtest(df, filtered_signals, config)
    
    # 计算额外指标
    total_bars = len(df)
    active_bars = active_mask.sum()
    active_pct = active_bars / total_bars * 100
    
    return {
        "signals": int((filtered_signals != 0).sum()),
        "trades": result.stats["trades"],
        "total_return": result.stats["total_return"],
        "max_drawdown": result.stats["max_drawdown"],
        "sharpe": result.stats["sharpe"],
        "win_rate": result.stats.get("win_rate", 0),
        "active_pct": active_pct,
        "active_bars": int(active_bars),
    }


def main():
    args = parse_args()
    settings = load_settings(args.config)
    
    # 加载数据
    data_path = Path(resolve_data_path(settings.paths, "mt5", args.data))
    df, _ = load_data(str(data_path), "mt5")
    
    df_htf = None
    if args.data_htf:
        htf_path = Path(resolve_data_path(settings.paths, "mt5", args.data_htf))
        if htf_path.exists():
            df_htf, _ = load_data(str(htf_path), "mt5")
    
    # 配置
    config = BacktestConfig(
        symbol="XAUUSD",
        timeframe="M5",
        initial_cash=settings.broker.initial_cash,
        spread_points=settings.broker.spread_points,
        commission_per_lot=settings.broker.commission_per_lot,
        point=settings.broker.point,
        lot_size=settings.broker.lot_size,
        leverage=settings.broker.leverage,
        trade_lot=settings.broker.trade_lot,
    )
    
    # 参数网格
    eff_baselines = parse_list(args.eff_baselines)
    fbr_baselines = parse_list(args.fbr_baselines)
    q_standby = parse_list(args.q_standby_thresholds)
    q_active = parse_list(args.q_active_thresholds)
    
    combinations = list(itertools.product(
        eff_baselines, fbr_baselines, q_standby, q_active
    ))
    combinations = combinations[:args.max_tests]
    
    print(f"\n{'='*70}")
    print("Regime Parameter Optimization")
    print(f"{'='*70}")
    print(f"Data: {len(df)} bars (M5)")
    print(f"Combinations: {len(combinations)}")
    print(f"\nParameter ranges:")
    print(f"  eff_baseline: {eff_baselines}")
    print(f"  fbr_baseline: {fbr_baselines}")
    print(f"  q_standby: {q_standby}")
    print(f"  q_active: {q_active}")
    print(f"{'='*70}\n")
    
    results = []
    
    for i, (eff_b, fbr_b, q_s, q_a) in enumerate(combinations):
        # 跳过无效组合
        if q_a <= q_s:
            continue
            
        # 构建 MarketQuality 参数
        mq_params = MarketQualityParams(
            efficiency_period=20,
            breakout_lookback=5,
            breakout_threshold=0.3,
            false_breakout_window=30,
            q_score_threshold=q_s,
        )
        
        # 构建 RegimeFilter 参数
        regime_params = RegimeFilterParams(
            q_score_standby=q_s,
            q_score_active=q_a,
            transition_bars=3,
            hysteresis=0.05,
            enable_sub_type=True,
        )
        
        try:
            # 运行回测
            metrics = run_regime_backtest(
                df, df_htf, regime_params, mq_params, config
            )
            
            result = {
                "eff_baseline": eff_b,
                "fbr_baseline": fbr_b,
                "q_standby": q_s,
                "q_active": q_a,
                **metrics,
            }
            results.append(result)
            
            print(f"[{i+1}/{len(combinations)}] "
                  f"eff={eff_b:.2f} fbr={fbr_b:.2f} "
                  f"q_s={q_s:.2f} q_a={q_a:.2f} => "
                  f"active={metrics['active_pct']:.1f}% "
                  f"trades={metrics['trades']} "
                  f"ret={metrics['total_return']:.2f}% "
                  f"sharpe={metrics['sharpe']:.3f}")
        except Exception as e:
            print(f"[{i+1}/{len(combinations)}] Error: {e}")
    
    if not results:
        print("No valid results!")
        return
    
    # 保存结果
    df_results = pd.DataFrame(results)
    df_results = df_results.sort_values("sharpe", ascending=False)
    
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    df_results.to_csv(output_path, index=False)
    
    print(f"\n{'='*70}")
    print("Top 10 Results (by Sharpe)")
    print(f"{'='*70}")
    print(df_results.head(10).to_string())
    print(f"\nResults saved to: {output_path}")
    
    # 推荐参数
    best = df_results.iloc[0]
    print(f"\n{'='*70}")
    print("Recommended Parameters")
    print(f"{'='*70}")
    print(f"MQ_Efficiency_Baseline = {best['eff_baseline']:.2f}")
    print(f"MQ_FBR_Baseline = {best['fbr_baseline']:.2f}")
    print(f"RF_Q_Score_Standby = {best['q_standby']:.2f}")
    print(f"RF_Q_Score_Active = {best['q_active']:.2f}")
    print(f"\nExpected: {best['trades']:.0f} trades, "
          f"{best['active_pct']:.1f}% active, "
          f"Sharpe={best['sharpe']:.3f}")


if __name__ == "__main__":
    main()
