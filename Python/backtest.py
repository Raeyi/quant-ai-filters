from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd

from ai_filters.pipeline import IdentityFilter, ZScoreThresholdFilter
from core.config import BacktestConfig
from core.data import load_data, resample_ohlc
from core.settings import load_settings, resolve_data_path, resolve_path
from core.engine import run_backtest
from strategies.boll_mean_reversion import BollMeanReversionParams, BollMeanReversionStrategy
from utils.io import write_csv


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="MT5 Forex backtest runner")
    parser.add_argument("--config", default="config.json", help="Path to config.json")
    parser.add_argument("--source", default="mt5", help="mt5 / dukascopy / truefx / ticks")
    parser.add_argument("--data", required=True, help="Path to CSV data")
    parser.add_argument("--symbol", default="EURUSD", help="Symbol name")
    parser.add_argument("--timeframe", default="M15", help="Timeframe label (e.g. M5, M15, H1)")
    parser.add_argument("--resample", default="", help="Optional pandas resample rule, e.g. 15T or 1H")
    parser.add_argument("--initial-cash", type=float, default=10000.0)
    parser.add_argument("--spread-points", type=float, default=None)
    parser.add_argument("--commission", type=float, default=None)
    parser.add_argument("--point", type=float, default=None)
    parser.add_argument("--lot-size", type=int, default=None)
    parser.add_argument("--tz", default="", help="Optional timezone for parsing time")
    parser.add_argument("--export-features", default="", help="Output path for features CSV")
    parser.add_argument("--export-signals", default="", help="Output path for signals CSV")
    parser.add_argument("--export-equity", default="", help="Output path for equity CSV")
    parser.add_argument("--filter", default="identity", choices=["identity", "zscore"])
    parser.add_argument("--zscore-threshold", type=float, default=0.5)
    parser.add_argument("--entry-mode", default=None, choices=["A", "B", "C"])
    parser.add_argument("--start-hour", type=int, default=None)
    parser.add_argument("--end-hour", type=int, default=None)
    parser.add_argument("--boll-period", type=int, default=None)
    parser.add_argument("--boll-dev", type=float, default=None)
    parser.add_argument("--atr-period", type=int, default=None)
    parser.add_argument("--shortest-closing-time", type=int, default=None)
    parser.add_argument("--struct-atr-sl", type=float, default=None)
    parser.add_argument("--vol-atr-sl", type=float, default=None)
    parser.add_argument("--mid-atr-tp", type=float, default=None)
    parser.add_argument("--uplow-atr-tp", type=float, default=None)
    parser.add_argument("--ma-period", type=int, default=None)
    parser.add_argument("--progress-step", type=int, default=0, help="Print progress every N bars")
    return parser.parse_args()


def main() -> None:
    args = _parse_args()
    settings = load_settings(args.config)

    data_path = Path(resolve_data_path(settings.paths, args.source, args.data))
    if not data_path.exists():
        raise FileNotFoundError(f"Data file not found: {data_path}")

    tz = args.tz or None
    df, source_kind = load_data(str(data_path), args.source, tz=tz, resample_rule=args.resample)
    if args.resample and source_kind == "ohlc":
        df = resample_ohlc(df, args.resample)

    spread_points = args.spread_points if args.spread_points is not None else settings.broker.spread_points
    commission = args.commission if args.commission is not None else settings.broker.commission_per_lot
    point = args.point if args.point is not None else settings.broker.point
    lot_size = args.lot_size if args.lot_size is not None else settings.broker.lot_size

    cfg_boll = settings.strategy.boll_mr
    params = BollMeanReversionParams(
        entry_mode=args.entry_mode if args.entry_mode is not None else cfg_boll.entry_mode,
        allowed_start_hour=args.start_hour if args.start_hour is not None else cfg_boll.allowed_start_hour,
        allowed_end_hour=args.end_hour if args.end_hour is not None else cfg_boll.allowed_end_hour,
        boll_period=args.boll_period if args.boll_period is not None else cfg_boll.boll_period,
        boll_dev=args.boll_dev if args.boll_dev is not None else cfg_boll.boll_dev,
        atr_period=args.atr_period if args.atr_period is not None else cfg_boll.atr_period,
        shortest_closing_time=(
            args.shortest_closing_time
            if args.shortest_closing_time is not None
            else cfg_boll.shortest_closing_time
        ),
        struct_atr_sl=args.struct_atr_sl if args.struct_atr_sl is not None else cfg_boll.struct_atr_sl,
        vol_atr_sl=args.vol_atr_sl if args.vol_atr_sl is not None else cfg_boll.vol_atr_sl,
        bool_mid_atr_tp=args.mid_atr_tp if args.mid_atr_tp is not None else cfg_boll.mid_atr_tp,
        bool_uplow_atr_tp=args.uplow_atr_tp if args.uplow_atr_tp is not None else cfg_boll.uplow_atr_tp,
        ma_period=args.ma_period if args.ma_period is not None else cfg_boll.ma_period,
        point=point,
    )
    strategy = BollMeanReversionStrategy(params, progress_step=args.progress_step)
    features = strategy.build_features(df)
    signals = strategy.generate_signals(df)

    if args.filter == "zscore":
        filt = ZScoreThresholdFilter(threshold=args.zscore_threshold)
    else:
        filt = IdentityFilter()
    filtered = filt.apply(features, signals)

    if args.export_features:
        export_path = Path(resolve_path(settings.paths.data_root, args.export_features))
        output = features.copy()
        output.insert(0, "time", output.index)
        write_csv(output, str(export_path))

    if args.export_signals:
        export_path = Path(resolve_path(settings.paths.data_root, args.export_signals))
        sig_df = pd.DataFrame(
            {
                "time": filtered.signals.index,
                "signal": filtered.signals.values,
                "confidence": filtered.confidence.values,
            }
        )
        sig_df.to_csv(export_path, index=False)

    config = BacktestConfig(
        symbol=args.symbol,
        timeframe=args.timeframe,
        initial_cash=args.initial_cash,
        spread_points=spread_points,
        commission_per_lot=commission,
        point=point,
        lot_size=lot_size,
    )
    result = run_backtest(df, filtered.signals, config)

    if args.export_equity:
        export_path = Path(resolve_path(settings.paths.data_root, args.export_equity))
        eq_df = pd.DataFrame(
            {
                "time": result.equity.index,
                "equity": result.equity.values,
                "returns": result.returns.values,
            }
        )
        eq_df.to_csv(export_path, index=False)

    print("Backtest stats:")
    for key, value in result.stats.items():
        print(f"  {key}: {value}")


if __name__ == "__main__":
    main()
