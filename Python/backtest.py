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


def _apply_risk_controls(
    df: pd.DataFrame,
    desired: pd.Series,
    confidence: pd.Series,
    config: BacktestConfig,
    params: BollMeanReversionParams,
) -> pd.Series:
    price = df["close"]
    position = 0
    prev_position = 0
    entry_price = None
    bars_held = 0
    cooldown_until = None
    cooldown_bars = 0
    losing_streak = 0
    daily_block = False
    daily_date = None
    equity = config.initial_cash
    daily_start_equity = equity

    executed = []

    for idx, ts in enumerate(df.index):
        if daily_date is None or ts.date() != daily_date:
            daily_date = ts.date()
            daily_start_equity = equity
            daily_block = False

        if cooldown_bars > 0:
            cooldown_bars -= 1
        if cooldown_until is not None and ts >= cooldown_until:
            cooldown_until = None

        desired_pos = int(desired.iloc[idx])
        if confidence is not None and params.min_confidence > 0:
            if confidence.iloc[idx] < params.min_confidence:
                desired_pos = 0

        if position != 0:
            bars_held += 1
            if params.max_holding_bars > 0 and bars_held >= params.max_holding_bars:
                desired_pos = 0

        # handle reversals as exit then optional entry
        wants_reverse = position != 0 and desired_pos != 0 and desired_pos != position

        if position != 0 and (desired_pos == 0 or wants_reverse):
            # exit
            exit_price = float(price.iloc[idx])
            trade_pnl = (exit_price - float(entry_price)) * position * config.lot_size
            trade_cost = (config.spread_points * config.point + config.slippage_points * config.point) * config.lot_size
            trade_cost += config.commission_per_lot
            trade_pnl -= trade_cost

            if trade_pnl < 0:
                losing_streak += 1
            elif trade_pnl > 0:
                losing_streak = 0

            if params.max_losing_streak > 0 and losing_streak >= params.max_losing_streak:
                cooldown_bars = max(cooldown_bars, params.cooldown_bars_after)
                losing_streak = 0

            if params.cooldown_seconds > 0:
                cooldown_until = ts + pd.Timedelta(seconds=params.cooldown_seconds)

            position = 0
            entry_price = None
            bars_held = 0

        if position == 0 and desired_pos != 0:
            if daily_block or cooldown_bars > 0 or cooldown_until is not None:
                desired_pos = 0
            else:
                position = 1 if desired_pos > 0 else -1
                entry_price = float(price.iloc[idx])
                bars_held = 0

        executed.append(position)

        # update equity using current position
        if idx > 0:
            price_change = float(price.iloc[idx] - price.iloc[idx - 1])
            pnl = position * price_change * config.lot_size
            trade_change = abs(position - prev_position)
            if trade_change > 0:
                pnl -= trade_change * (
                    (config.spread_points * config.point + config.slippage_points * config.point) * config.lot_size
                    + config.commission_per_lot
                )
            equity += pnl

            if params.max_daily_loss_percent > 0:
                if daily_start_equity > 0:
                    daily_return = (equity - daily_start_equity) / daily_start_equity
                    if daily_return <= -(params.max_daily_loss_percent / 100.0):
                        daily_block = True

        prev_position = position

    return pd.Series(executed, index=df.index, name="signal")


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
    parser.add_argument("--diagnose-signals", action="store_true", help="Print signal diagnostics")
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
        time_offset_hours=cfg_boll.time_offset_hours,
        max_holding_bars=cfg_boll.max_holding_bars,
        max_daily_loss_percent=cfg_boll.max_daily_loss_percent,
        risk_percent=cfg_boll.risk_percent,
        max_losing_streak=cfg_boll.max_losing_streak,
        cooldown_bars_after=cfg_boll.cooldown_bars_after,
        cooldown_seconds=cfg_boll.cooldown_seconds,
        min_confidence=cfg_boll.min_confidence,
    )
    strategy = BollMeanReversionStrategy(params, progress_step=args.progress_step)
    features = strategy.build_features(df)
    signals = strategy.generate_signals(df, diagnose=args.diagnose_signals)
    if args.diagnose_signals:
        print("Signal diagnostics:")
        for key, value in (strategy.last_diagnostics or {}).items():
            print(f"  {key}: {value}")

    if args.filter == "zscore":
        filt = ZScoreThresholdFilter(threshold=args.zscore_threshold)
    else:
        filt = IdentityFilter()
    filtered = filt.apply(features, signals)
    config = BacktestConfig(
        symbol=args.symbol,
        timeframe=args.timeframe,
        initial_cash=args.initial_cash,
        spread_points=spread_points,
        commission_per_lot=commission,
        point=point,
        lot_size=lot_size,
    )

    if params.min_confidence > 0:
        filtered.signals = filtered.signals.where(filtered.confidence >= params.min_confidence, 0)
    filtered.signals = _apply_risk_controls(df, filtered.signals, filtered.confidence, config, params)

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
        if strategy.last_signal_state is not None:
            state_path = export_path.with_name("signals_state.csv")
            state_df = pd.DataFrame(
                {
                    "time": strategy.last_signal_state.index,
                    "signal": strategy.last_signal_state.values,
                }
            )
            state_df.to_csv(state_path, index=False)
        if strategy.last_signal_events is not None:
            event_path = export_path.with_name("signals_event.csv")
            event_df = pd.DataFrame(
                {
                    "time": strategy.last_signal_events.index,
                    "signal": strategy.last_signal_events.values,
                }
            )
            event_df.to_csv(event_path, index=False)

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
