"""
参数优化脚本
对 BollMR 和 TrendPullback 进行参数网格搜索
"""
from __future__ import annotations

import argparse
import itertools
from pathlib import Path
from typing import Dict, List, Any

import pandas as pd
import numpy as np

from core.config import BacktestConfig
from core.data import load_data
from core.settings import load_settings, resolve_data_path
from core.engine import run_backtest
from strategies.boll_mean_reversion import BollMeanReversionParams, BollMeanReversionStrategy
from strategies.trend_pullback import TrendPullbackParams, TrendPullbackStrategy
from strategies.combo_strategy import ComboStrategy, ComboMode, ComboParams


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Parameter optimization")
    parser.add_argument("--config", default="config.json")
    parser.add_argument("--source", default="mt5")
    parser.add_argument("--data", required=True, help="LTF data path")
    parser.add_argument("--data-htf", default="", help="HTF data path")
    parser.add_argument("--symbol", default="XAUUSD")
    parser.add_argument("--timeframe", default="M5")
    parser.add_argument("--tz", default="")
    parser.add_argument("--output", default="param_optimize_results.csv", help="Output file")
    
    # 固定参数
    parser.add_argument("--boll-start-hour", type=int, default=2)
    parser.add_argument("--boll-end-hour", type=int, default=20)
    parser.add_argument("--tp-session", default="europe,us,overlap")
    parser.add_argument("--combo-mode", default="conflict_skip")
    
    # BollMR 优化参数范围
    parser.add_argument("--boll-periods", default="18,20,22", help="Comma-separated boll periods")
    parser.add_argument("--boll-devs", default="1.5,1.8,2.0", help="Comma-separated boll devs")
    parser.add_argument("--struct-atr-sls", default="0.6,0.8,1.0", help="Comma-separated struct ATR SL")
    parser.add_argument("--mid-atr-tps", default="0.15,0.2,0.3", help="Comma-separated mid ATR TP")
    
    # TrendPullback 优化参数范围
    parser.add_argument("--ema50-periods", default="40,50,60", help="Comma-separated EMA50 periods")
    parser.add_argument("--atr-sl-multis", default="0.8,1.0,1.2", help="Comma-separated ATR SL multi")
    parser.add_argument("--pullback-depths", default="0.5,0.618,0.8", help="Comma-separated pullback depth")
    
    # 限制
    parser.add_argument("--max-tests", type=int, default=50, help="Max tests to run")
    parser.add_argument("--strategy", default="both", choices=["boll", "tp", "both"], help="Which strategy to optimize")
    
    return parser.parse_args()


def _parse_list(s: str) -> List:
    """Parse comma-separated values"""
    return [float(x) if '.' in x else int(x) for x in s.split(',')]


def run_boll_test(
    df: pd.DataFrame,
    params: Dict[str, Any],
    base_params: Dict[str, Any],
    config: BacktestConfig,
) -> Dict[str, float]:
    """Run single BollMR test"""
    params_obj = BollMeanReversionParams(
        logic_mode="enhanced",
        allowed_start_hour=base_params['boll_start_hour'],
        allowed_end_hour=base_params['boll_end_hour'],
        boll_period=int(params['boll_period']),
        boll_dev=params['boll_dev'],
        atr_period=14,
        struct_atr_sl=params['struct_atr_sl'],
        vol_atr_sl=2.0,
        bool_mid_atr_tp=params['mid_atr_tp'],
        point=config.point,
    )
    
    strategy = BollMeanReversionStrategy(params_obj)
    signals = strategy.generate_signals(df)
    result = run_backtest(df, signals, config)
    
    return {
        'signals': int((signals != 0).sum()),
        'total_return': result.stats['total_return'],
        'max_drawdown': result.stats['max_drawdown'],
        'sharpe': result.stats['sharpe'],
        'trades': result.stats['trades'],
    }


def run_tp_test(
    df: pd.DataFrame,
    df_htf: pd.DataFrame,
    params: Dict[str, Any],
    base_params: Dict[str, Any],
    config: BacktestConfig,
) -> Dict[str, float]:
    """Run single TrendPullback test"""
    params_obj = TrendPullbackParams(
        session=base_params['tp_session'],
        ema50_period=int(params['ema50_period']),
        ema200_period=200,
        atr_period=14,
        atr_sl_multi=params['atr_sl_multi'],
        pullback_depth_atr=params['pullback_depth'],
        value_zone_atr=0.3,
        point=config.point,
    )
    
    strategy = TrendPullbackStrategy(params_obj)
    signals = strategy.generate_signals(df, df_htf)
    result = run_backtest(df, signals, config)
    
    return {
        'signals': int((signals != 0).sum()),
        'total_return': result.stats['total_return'],
        'max_drawdown': result.stats['max_drawdown'],
        'sharpe': result.stats['sharpe'],
        'trades': result.stats['trades'],
    }


def main() -> None:
    args = _parse_args()
    settings = load_settings(args.config)
    
    # 加载数据
    data_path = Path(resolve_data_path(settings.paths, args.source, args.data))
    tz = args.tz or None
    df, _ = load_data(str(data_path), args.source, tz=tz)
    
    df_htf = None
    if args.data_htf:
        htf_path = Path(resolve_data_path(settings.paths, args.source, args.data_htf))
        if htf_path.exists():
            df_htf, _ = load_data(str(htf_path), args.source, tz=tz)
    
    # 配置
    config = BacktestConfig(
        symbol=args.symbol,
        timeframe=args.timeframe,
        initial_cash=settings.broker.initial_cash,
        spread_points=settings.broker.spread_points,
        commission_per_lot=settings.broker.commission_per_lot,
        point=settings.broker.point,
        lot_size=settings.broker.lot_size,
        leverage=settings.broker.leverage,
        trade_lot=settings.broker.trade_lot,
    )
    
    base_params = {
        'boll_start_hour': args.boll_start_hour,
        'boll_end_hour': args.boll_end_hour,
        'tp_session': args.tp_session,
    }
    
    results = []
    
    print(f"\n{'='*70}")
    print(f"Parameter Optimization")
    print(f"{'='*70}")
    print(f"Data: {len(df)} bars (LTF), {len(df_htf) if df_htf is not None else 0} bars (HTF)")
    print(f"Strategy: {args.strategy}")
    print(f"{'='*70}\n")
    
    # BollMR 参数优化
    if args.strategy in ['boll', 'both']:
        boll_periods = _parse_list(args.boll_periods)
        boll_devs = _parse_list(args.boll_devs)
        struct_atr_sls = _parse_list(args.struct_atr_sls)
        mid_atr_tps = _parse_list(args.mid_atr_tps)
        
        combinations = list(itertools.product(boll_periods, boll_devs, struct_atr_sls, mid_atr_tps))
        combinations = combinations[:args.max_tests]
        
        print(f"\n[BollMR] Testing {len(combinations)} combinations...")
        print(f"  boll_period: {boll_periods}")
        print(f"  boll_dev: {boll_devs}")
        print(f"  struct_atr_sl: {struct_atr_sls}")
        print(f"  mid_atr_tp: {mid_atr_tps}")
        print()
        
        for i, (bp, bd, sas, mat) in enumerate(combinations):
            params = {
                'boll_period': bp,
                'boll_dev': bd,
                'struct_atr_sl': sas,
                'mid_atr_tp': mat,
            }
            
            try:
                metrics = run_boll_test(df, params, base_params, config)
                results.append({
                    'strategy': 'BollMR',
                    **params,
                    **metrics,
                })
                print(f"  [{i+1}/{len(combinations)}] boll={bp}, dev={bd}, sl={sas}, tp={mat} => "
                      f"signals={metrics['signals']}, ret={metrics['total_return']:.2f}, "
                      f"dd={metrics['max_drawdown']:.4f}, sharpe={metrics['sharpe']:.3f}")
            except Exception as e:
                print(f"  [{i+1}/{len(combinations)}] Error: {e}")
    
    # TrendPullback 参数优化
    if args.strategy in ['tp', 'both']:
        ema50_periods = _parse_list(args.ema50_periods)
        atr_sl_multis = _parse_list(args.atr_sl_multis)
        pullback_depths = _parse_list(args.pullback_depths)
        
        combinations = list(itertools.product(ema50_periods, atr_sl_multis, pullback_depths))
        combinations = combinations[:args.max_tests]
        
        print(f"\n[TrendPullback] Testing {len(combinations)} combinations...")
        print(f"  ema50_period: {ema50_periods}")
        print(f"  atr_sl_multi: {atr_sl_multis}")
        print(f"  pullback_depth: {pullback_depths}")
        print()
        
        for i, (e50, asl, pd) in enumerate(combinations):
            params = {
                'ema50_period': e50,
                'atr_sl_multi': asl,
                'pullback_depth': pd,
            }
            
            try:
                metrics = run_tp_test(df, df_htf, params, base_params, config)
                results.append({
                    'strategy': 'TrendPullback',
                    **params,
                    **metrics,
                })
                print(f"  [{i+1}/{len(combinations)}] ema50={e50}, sl_multi={asl}, depth={pd} => "
                      f"signals={metrics['signals']}, ret={metrics['total_return']:.2f}, "
                      f"dd={metrics['max_drawdown']:.4f}, sharpe={metrics['sharpe']:.3f}")
            except Exception as e:
                print(f"  [{i+1}/{len(combinations)}] Error: {e}")
    
    # 保存结果
    if results:
        df_results = pd.DataFrame(results)
        
        # 排序：按 Sharpe 降序
        df_results = df_results.sort_values('sharpe', ascending=False)
        
        output_path = Path(args.output)
        df_results.to_csv(output_path, index=False)
        
        print(f"\n{'='*70}")
        print(f"Top 10 Results (by Sharpe)")
        print(f"{'='*70}")
        print(df_results.head(10).to_string())
        print(f"\nResults saved to: {output_path}")


if __name__ == "__main__":
    main()
