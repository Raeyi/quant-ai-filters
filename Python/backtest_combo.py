"""
多策略组合回测脚本
同时运行 BollMR + TrendPullback，分析信号冲突和组合效果

Usage:
    python backtest_combo.py --data XAUUSD_M5.csv --data-htf XAUUSD_M15.csv
"""
from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd
import numpy as np

from core.config import BacktestConfig
from core.data import load_data, resample_ohlc
from core.settings import load_settings, resolve_data_path, resolve_path
from core.engine import run_backtest
from strategies.boll_mean_reversion import BollMeanReversionParams, BollMeanReversionStrategy
from strategies.trend_pullback import TrendPullbackParams, TrendPullbackStrategy
from strategies.combo_strategy import ComboStrategy, ComboMode, ComboParams
from utils.io import write_csv


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Multi-strategy combo backtest")
    parser.add_argument("--config", default="config.json", help="Path to config.json")
    parser.add_argument("--source", default="mt5", help="mt5 / dukascopy / truefx / ticks")
    parser.add_argument("--data", required=True, help="Path to LTF CSV data (M5)")
    parser.add_argument("--data-htf", default="", help="Path to HTF CSV data (M15)")
    parser.add_argument("--symbol", default="XAUUSD", help="Symbol name")
    parser.add_argument("--timeframe", default="M5", help="LTF timeframe")
    parser.add_argument("--resample", default="", help="Optional pandas resample rule")
    parser.add_argument("--initial-cash", type=float, default=None)
    parser.add_argument("--spread-points", type=float, default=None)
    parser.add_argument("--commission", type=float, default=None)
    parser.add_argument("--point", type=float, default=None)
    parser.add_argument("--lot-size", type=int, default=None)
    parser.add_argument("--tz", default="", help="Optional timezone for parsing time")
    
    # BollMR 参数
    parser.add_argument("--boll-start-hour", type=int, default=2, help="BollMR 允许开始小时")
    parser.add_argument("--boll-end-hour", type=int, default=14, help="BollMR 允许结束小时")
    
    # TrendPullback 参数
    parser.add_argument("--tp-session", default="us,overlap", help="TrendPullback session")
    
    # Combo 参数
    parser.add_argument("--combo-mode", default="conflict_skip", 
                        choices=["first_signal", "same_direction", "majority_vote", 
                                 "priority_first", "conflict_skip", "best_confidence"],
                        help="组合模式")
    parser.add_argument("--min-agreement", type=int, default=2, help="多数投票最小同意数")
    
    # 输出
    parser.add_argument("--export-signals", default="", help="Output path for signals CSV")
    parser.add_argument("--export-equity", default="", help="Output path for equity CSV")
    parser.add_argument("--export-report", default="", help="Output path for report CSV")
    
    # 分析
    parser.add_argument("--analyze-only", action="store_true", help="只分析信号，不跑回测")
    return parser.parse_args()


def main() -> None:
    args = _parse_args()
    settings = load_settings(args.config)
    
    # 加载 LTF 数据
    data_path = Path(resolve_data_path(settings.paths, args.source, args.data))
    if not data_path.exists():
        raise FileNotFoundError(f"Data file not found: {data_path}")
    
    tz = args.tz or None
    df, source_kind = load_data(str(data_path), args.source, tz=tz, resample_rule=args.resample)
    if args.resample and source_kind == "ohlc":
        df = resample_ohlc(df, args.resample)
    
    # 加载 HTF 数据
    df_htf = None
    if args.data_htf:
        htf_path = Path(resolve_data_path(settings.paths, args.source, args.data_htf))
        if htf_path.exists():
            df_htf, _ = load_data(str(htf_path), args.source, tz=tz)
            print(f"Loaded HTF data: {len(df_htf)} bars")
    
    # 配置
    spread_points = args.spread_points or settings.broker.spread_points
    commission = args.commission or settings.broker.commission_per_lot
    point = args.point or settings.broker.point
    lot_size = args.lot_size or settings.broker.lot_size
    initial_cash = args.initial_cash or settings.broker.initial_cash
    trade_lot = settings.broker.trade_lot
    
    # BollMR 参数（亚欧盘）
    boll_params = BollMeanReversionParams(
        logic_mode="enhanced",
        allowed_start_hour=args.boll_start_hour,
        allowed_end_hour=args.boll_end_hour,
        point=point,
    )
    
    # TrendPullback 参数（欧美盘）
    tp_params = TrendPullbackParams(
        session=args.tp_session,
        point=point,
    )
    
    # Combo 参数
    mode_map = {
        "first_signal": ComboMode.FIRST_SIGNAL,
        "same_direction": ComboMode.SAME_DIRECTION,
        "majority_vote": ComboMode.MAJORITY_VOTE,
        "priority_first": ComboMode.PRIORITY_FIRST,
        "conflict_skip": ComboMode.CONFLICT_SKIP,
        "best_confidence": ComboMode.BEST_CONFIDENCE,
    }
    combo_params = ComboParams(
        mode=mode_map[args.combo_mode],
        min_agreement=args.min_agreement,
        log_signals=True,
    )
    
    # 创建组合策略
    combo = ComboStrategy(
        boll_params=boll_params,
        tp_params=tp_params,
        combo_params=combo_params,
    )
    
    print(f"\n{'='*60}")
    print(f"Multi-Strategy Combo Backtest")
    print(f"{'='*60}")
    print(f"Symbol: {args.symbol}")
    print(f"LTF: {args.timeframe} ({len(df)} bars)")
    print(f"HTF: {'M15' if df_htf is not None else 'N/A'}")
    print(f"Combo mode: {args.combo_mode}")
    print(f"BollMR hours: {args.boll_start_hour}:00 - {args.boll_end_hour}:00 (Asia/Europe)")
    print(f"TrendPullback session: {args.tp_session}")
    print(f"{'='*60}\n")
    
    # 生成组合信号
    combo_signals = combo.generate_signals(df, df_htf)
    
    # 统计
    stats = combo.get_stats_summary()
    print("\nSignal Statistics:")
    print(f"  Total bars: {stats['total_bars']}")
    print(f"  BollMR signals: {stats['boll_signals']}")
    print(f"  TrendPullback signals: {stats['tp_signals']}")
    print(f"  Both signals: {stats['both_signals']}")
    print(f"    - Same direction: {stats['same_direction']}")
    print(f"    - Conflict skip: {stats['conflict_skip']}")
    print(f"  Single signals:")
    print(f"    - BollMR only: {stats['boll_only']}")
    print(f"    - TP only: {stats['tp_only']}")
    print(f"  Final signals: {stats['final_signals']} ({stats['signal_rate']*100:.2f}%)")
    print(f"  Conflict rate: {stats['conflict_rate']*100:.1f}%")
    
    # 导出信号
    if args.export_signals:
        export_path = Path(resolve_path(settings.paths.data_root, args.export_signals))
        sig_df = combo.get_signal_dataframe()
        if not sig_df.empty:
            sig_df.to_csv(export_path, index=False)
            print(f"\nSignals exported to: {export_path}")
    
    # 只分析模式
    if args.analyze_only:
        print("\n[Analyze only mode - skipping backtest]")
        return
    
    # 运行回测
    config = BacktestConfig(
        symbol=args.symbol,
        timeframe=args.timeframe,
        initial_cash=initial_cash,
        spread_points=spread_points,
        commission_per_lot=commission,
        point=point,
        lot_size=lot_size,
        leverage=settings.broker.leverage,
        trade_lot=trade_lot,
    )
    
    result = run_backtest(df, combo_signals, config)
    
    print("\nBacktest Results:")
    for key, value in result.stats.items():
        if isinstance(value, float):
            print(f"  {key}: {value:.4f}")
        else:
            print(f"  {key}: {value}")
    
    # 导出权益曲线
    if args.export_equity:
        export_path = Path(resolve_path(settings.paths.data_root, args.export_equity))
        eq_df = pd.DataFrame({
            "time": result.equity.index,
            "equity": result.equity.values,
            "returns": result.returns.values,
        })
        eq_df.to_csv(export_path, index=False)
        print(f"\nEquity exported to: {export_path}")
    
    # 导出报告
    if args.export_report:
        export_path = Path(resolve_path(settings.paths.data_root, args.export_report))
        report = pd.DataFrame([{
            "symbol": args.symbol,
            "timeframe": args.timeframe,
            "combo_mode": args.combo_mode,
            "total_bars": stats['total_bars'],
            "boll_signals": stats['boll_signals'],
            "tp_signals": stats['tp_signals'],
            "both_signals": stats['both_signals'],
            "same_direction": stats['same_direction'],
            "conflict_skip": stats['conflict_skip'],
            "final_signals": stats['final_signals'],
            "signal_rate": stats['signal_rate'],
            "conflict_rate": stats['conflict_rate'],
            **{f"bt_{k}": v for k, v in result.stats.items()},
        }])
        report.to_csv(export_path, index=False)
        print(f"\nReport exported to: {export_path}")
    
    # 单独运行各策略对比
    print("\n" + "="*60)
    print("Individual Strategy Comparison")
    print("="*60)
    
    # BollMR 单独
    boll_strategy = BollMeanReversionStrategy(boll_params)
    boll_signals = boll_strategy.generate_signals(df)
    boll_result = run_backtest(df, boll_signals, config)
    print(f"\nBollMR (Asia/Europe {args.boll_start_hour}:00-{args.boll_end_hour}:00):")
    print(f"  Signals: {int((boll_signals != 0).sum())}")
    print(f"  Total return: {boll_result.stats['total_return']:.4f}")
    print(f"  Max drawdown: {boll_result.stats['max_drawdown']:.4f}")
    print(f"  Sharpe: {boll_result.stats['sharpe']:.4f}")
    
    # TrendPullback 单独
    tp_strategy = TrendPullbackStrategy(tp_params)
    tp_signals = tp_strategy.generate_signals(df, df_htf)
    tp_result = run_backtest(df, tp_signals, config)
    print(f"\nTrendPullback ({args.tp_session}):")
    print(f"  Signals: {int((tp_signals != 0).sum())}")
    print(f"  Total return: {tp_result.stats['total_return']:.4f}")
    print(f"  Max drawdown: {tp_result.stats['max_drawdown']:.4f}")
    print(f"  Sharpe: {tp_result.stats['sharpe']:.4f}")
    
    print("\n" + "="*60)
    print("Summary")
    print("="*60)
    print(f"{'Strategy':<20} {'Signals':>10} {'Return':>12} {'MaxDD':>10} {'Sharpe':>8}")
    print("-"*60)
    print(f"{'BollMR':<20} {int((boll_signals != 0).sum()):>10} {boll_result.stats['total_return']:>12.4f} {boll_result.stats['max_drawdown']:>10.4f} {boll_result.stats['sharpe']:>8.4f}")
    print(f"{'TrendPullback':<20} {int((tp_signals != 0).sum()):>10} {tp_result.stats['total_return']:>12.4f} {tp_result.stats['max_drawdown']:>10.4f} {tp_result.stats['sharpe']:>8.4f}")
    print(f"{'Combo':<20} {stats['final_signals']:>10} {result.stats['total_return']:>12.4f} {result.stats['max_drawdown']:>10.4f} {result.stats['sharpe']:>8.4f}")


if __name__ == "__main__":
    main()
