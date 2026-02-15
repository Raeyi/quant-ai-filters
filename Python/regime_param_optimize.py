"""
Regime Filter 参数优化脚本

M6.2: Q-Score 参数网格搜索
优化目标：
- MQ_Efficiency_Baseline: 效率基准值
- MQ_FBR_Baseline: 假突破率基准值
- MQ_ADX_Baseline: ADX 基准值
- MQ_Weight_Eff/FBR/ADX: 权重
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
    
    # 基准值参数范围
    parser.add_argument("--eff-baselines", default="0.08,0.10,0.12", 
                        help="Efficiency baseline values")
    parser.add_argument("--fbr-baselines", default="0.35,0.40,0.45", 
                        help="False breakout rate baseline values")
    parser.add_argument("--adx-baselines", default="20.0,25.0,30.0", 
                        help="ADX baseline values")
    
    # 权重参数范围
    parser.add_argument("--weight-eff", default="0.20,0.25,0.30", 
                        help="Efficiency weight")
    parser.add_argument("--weight-fbr", default="0.20,0.25,0.30", 
                        help="False breakout rate weight")
    parser.add_argument("--weight-adx", default="0.15,0.20,0.25", 
                        help="ADX weight")
    
    # 阈值参数范围
    parser.add_argument("--q-standby-thresholds", default="0.30,0.35,0.40",
                        help="Q-Score STANDBY thresholds")
    parser.add_argument("--q-active-thresholds", default="0.40,0.45,0.50",
                        help="Q-Score ACTIVE thresholds")
    
    # 限制
    parser.add_argument("--max-tests", type=int, default=100)
    parser.add_argument("--quick", action="store_true", help="Quick mode with fewer combinations")
    
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
    # 初始化 MarketQuality
    mq = MarketQuality(mq_params)
    quality_result = mq.calculate(df)
    
    # 初始化 Regime Filter
    regime_filter = RegimeFilter(regime_params)
    regime_result = regime_filter.calculate(df)
    
    # 使用 MarketQuality 的 Q-Score
    regime_result["q_score"] = quality_result["q_score"]
    regime_result["regime_state"] = quality_result["is_tradable"].apply(
        lambda x: RegimeState.ACTIVE if x else RegimeState.STANDBY
    )
    
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
    
    # Q-Score 统计
    q_scores = quality_result["q_score"]
    
    return {
        "signals": int((filtered_signals != 0).sum()),
        "trades": result.stats["trades"],
        "total_return": result.stats["total_return"],
        "max_drawdown": result.stats["max_drawdown"],
        "sharpe": result.stats["sharpe"],
        "win_rate": result.stats.get("win_rate", 0),
        "active_pct": active_pct,
        "active_bars": int(active_bars),
        "q_score_mean": float(q_scores.mean()),
        "q_score_std": float(q_scores.std()),
        "q_score_min": float(q_scores.min()),
        "q_score_max": float(q_scores.max()),
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
    adx_baselines = parse_list(args.adx_baselines)
    weight_effs = parse_list(args.weight_eff)
    weight_fbrs = parse_list(args.weight_fbr)
    weight_adxs = parse_list(args.weight_adx)
    q_standby = parse_list(args.q_standby_thresholds)
    q_active = parse_list(args.q_active_thresholds)
    
    # Quick 模式：减少组合
    if args.quick:
        eff_baselines = [eff_baselines[0], eff_baselines[-1]]
        fbr_baselines = [fbr_baselines[0], fbr_baselines[-1]]
        adx_baselines = [adx_baselines[len(adx_baselines)//2]]
        weight_effs = [weight_effs[len(weight_effs)//2]]
        weight_fbrs = [weight_fbrs[len(weight_fbrs)//2]]
        weight_adxs = [weight_adxs[len(weight_adxs)//2]]
    
    # 生成组合
    combinations = list(itertools.product(
        eff_baselines, fbr_baselines, adx_baselines,
        weight_effs, weight_fbrs, weight_adxs,
        q_standby, q_active
    ))
    combinations = combinations[:args.max_tests]
    
    print(f"\n{'='*70}")
    print("Regime Parameter Optimization (v2.3.0 with ADX)")
    print(f"{'='*70}")
    print(f"Data: {len(df)} bars (M5)")
    print(f"Combinations: {len(combinations)}")
    print(f"\nParameter ranges:")
    print(f"  eff_baseline: {eff_baselines}")
    print(f"  fbr_baseline: {fbr_baselines}")
    print(f"  adx_baseline: {adx_baselines}")
    print(f"  weight_eff: {weight_effs}")
    print(f"  weight_fbr: {weight_fbrs}")
    print(f"  weight_adx: {weight_adxs}")
    print(f"  q_standby: {q_standby}")
    print(f"  q_active: {q_active}")
    print(f"{'='*70}\n")
    
    results = []
    
    for i, (eff_b, fbr_b, adx_b, w_eff, w_fbr, w_adx, q_s, q_a) in enumerate(combinations):
        # 跳过无效组合
        if q_a <= q_s:
            continue
        
        # 权重归一化（可选，当前不强制）
        # w_total = w_eff + w_fbr + w_adx
        # w_eff, w_fbr, w_adx = w_eff/w_total, w_fbr/w_total, w_adx/w_total
            
        # 构建 MarketQuality 参数
        mq_params = MarketQualityParams(
            efficiency_period=20,
            breakout_lookback=5,
            breakout_threshold=0.3,
            false_breakout_window=30,
            efficiency_baseline=eff_b,
            fbr_baseline=fbr_b,
            adx_baseline=adx_b,
            weight_eff=w_eff,
            weight_fbr=w_fbr,
            weight_adx=w_adx,
            q_score_threshold=q_s,
        )
        
        # 构建 RegimeFilter 参数（传入 MarketQuality 参数）
        regime_params = RegimeFilterParams(
            quality=mq_params,
            q_score_standby=q_s,
            q_score_active=q_a,
            transition_bars=3,
            hysteresis=0.05,
            enable_subtype=True,
        )
        
        try:
            # 运行回测
            metrics = run_regime_backtest(
                df, df_htf, regime_params, mq_params, config
            )
            
            result = {
                "eff_baseline": eff_b,
                "fbr_baseline": fbr_b,
                "adx_baseline": adx_b,
                "weight_eff": w_eff,
                "weight_fbr": w_fbr,
                "weight_adx": w_adx,
                "q_standby": q_s,
                "q_active": q_a,
                **metrics,
            }
            results.append(result)
            
            print(f"[{i+1}/{len(combinations)}] "
                  f"eff_b={eff_b:.2f} fbr_b={fbr_b:.2f} adx_b={adx_b:.0f} "
                  f"w=({w_eff:.2f},{w_fbr:.2f},{w_adx:.2f}) "
                  f"q=({q_s:.2f},{q_a:.2f}) => "
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
    cols = ["eff_baseline", "fbr_baseline", "adx_baseline", 
            "weight_eff", "weight_fbr", "weight_adx",
            "q_standby", "q_active", "trades", "active_pct", 
            "total_return", "sharpe", "q_score_mean"]
    print(df_results[cols].head(10).to_string())
    print(f"\nResults saved to: {output_path}")
    
    # 推荐参数
    best = df_results.iloc[0]
    print(f"\n{'='*70}")
    print("Recommended Parameters")
    print(f"{'='*70}")
    print(f"MQ_Efficiency_Baseline = {best['eff_baseline']:.2f}")
    print(f"MQ_FBR_Baseline = {best['fbr_baseline']:.2f}")
    print(f"MQ_ADX_Baseline = {best['adx_baseline']:.1f}")
    print(f"MQ_Weight_Eff = {best['weight_eff']:.2f}")
    print(f"MQ_Weight_FBR = {best['weight_fbr']:.2f}")
    print(f"MQ_Weight_ADX = {best['weight_adx']:.2f}")
    print(f"RF_Q_Score_Standby = {best['q_standby']:.2f}")
    print(f"RF_Q_Score_Active = {best['q_active']:.2f}")
    print(f"\nExpected: {best['trades']:.0f} trades, "
          f"{best['active_pct']:.1f}% active, "
          f"Q_mean={best['q_score_mean']:.3f}, "
          f"Sharpe={best['sharpe']:.3f}")


if __name__ == "__main__":
    main()
