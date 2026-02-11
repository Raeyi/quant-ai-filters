from __future__ import annotations

import argparse
import itertools
from pathlib import Path
from typing import Dict, Iterable, List

import pandas as pd

from ai_filters.pipeline import IdentityFilter
from backtest import _apply_risk_controls
from core.config import BacktestConfig
from core.data import load_data, resample_ohlc
from core.settings import load_settings, resolve_data_path, resolve_path
from core.engine import run_backtest
from strategies.boll_mean_reversion import BollMeanReversionParams, BollMeanReversionStrategy


def _parse_grid(grid_text: str) -> Dict[str, List[str]]:
    grid: Dict[str, List[str]] = {}
    if not grid_text:
        return grid
    chunks = [c.strip() for c in grid_text.split(";") if c.strip()]
    for chunk in chunks:
        if "=" not in chunk:
            continue
        key, values = chunk.split("=", 1)
        key = key.strip()
        vals = [v.strip() for v in values.split(",") if v.strip()]
        if key and vals:
            grid[key] = vals
    return grid


def _coerce_value(key: str, value: str):
    if key in {"boll_period", "atr_period", "ma_period", "start_hour", "end_hour", "max_holding_bars"}:
        return int(value)
    if key in {"boll_dev", "struct_atr_sl", "vol_atr_sl", "mid_atr_tp", "mid_atr_tp2", "uplow_atr_tp"}:
        return float(value)
    return value


def _iter_grid(grid: Dict[str, List[str]]) -> Iterable[Dict[str, object]]:
    if not grid:
        yield {}
        return
    keys = list(grid.keys())
    values = [grid[k] for k in keys]
    for combo in itertools.product(*values):
        params = {k: _coerce_value(k, v) for k, v in zip(keys, combo)}
        yield params


def _build_params(cfg_boll, overrides: Dict[str, object], point: float) -> BollMeanReversionParams:
    def pick(name: str, default):
        return overrides.get(name, default)

    return BollMeanReversionParams(
        entry_mode=pick("entry_mode", cfg_boll.entry_mode),
        logic_mode=pick("logic_mode", getattr(cfg_boll, "logic_mode", "enhanced")),
        allowed_start_hour=pick("start_hour", cfg_boll.allowed_start_hour),
        allowed_end_hour=pick("end_hour", cfg_boll.allowed_end_hour),
        boll_period=pick("boll_period", cfg_boll.boll_period),
        boll_dev=pick("boll_dev", cfg_boll.boll_dev),
        atr_period=pick("atr_period", cfg_boll.atr_period),
        shortest_closing_time=cfg_boll.shortest_closing_time,
        struct_atr_sl=pick("struct_atr_sl", cfg_boll.struct_atr_sl),
        vol_atr_sl=pick("vol_atr_sl", cfg_boll.vol_atr_sl),
        bool_mid_atr_tp=pick("mid_atr_tp", cfg_boll.mid_atr_tp),
        bool_mid_atr_tp2=pick("mid_atr_tp2", cfg_boll.mid_atr_tp2),
        bool_uplow_atr_tp=pick("uplow_atr_tp", cfg_boll.uplow_atr_tp),
        ma_period=pick("ma_period", cfg_boll.ma_period),
        point=point,
        time_offset_hours=cfg_boll.time_offset_hours,
        max_holding_bars=cfg_boll.max_holding_bars,
        max_daily_loss_percent=cfg_boll.max_daily_loss_percent,
        risk_percent=cfg_boll.risk_percent,
        max_losing_streak=cfg_boll.max_losing_streak,
        cooldown_bars_after=cfg_boll.cooldown_bars_after,
        cooldown_seconds=cfg_boll.cooldown_seconds,
        min_confidence=cfg_boll.min_confidence,
        gap_cooldown_bars=cfg_boll.gap_cooldown_bars,
        gap_threshold_multiplier=cfg_boll.gap_threshold_multiplier,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Small parameter sweep for BollMR.")
    parser.add_argument("--config", default="Python/config.json")
    parser.add_argument("--source", default="mt5")
    parser.add_argument("--sources", default="")
    parser.add_argument("--data", required=True)
    parser.add_argument("--symbol", required=True)
    parser.add_argument("--timeframe", required=True)
    parser.add_argument("--resample", default=None)
    parser.add_argument("--grid", default="")
    parser.add_argument("--logic", default="enhanced", choices=["base", "enhanced"])
    parser.add_argument("--out", default="Python/data/param_sweep.csv")
    parser.add_argument("--top", type=int, default=0)
    parser.add_argument("--sort", default="total_return")
    parser.add_argument("--sort-secondary", default="sharpe")
    parser.add_argument("--min-sharpe", type=float, default=None)
    parser.add_argument("--min-trades", type=int, default=None)
    parser.add_argument("--max-dd", type=float, default=None)
    parser.add_argument("--min-profit-factor", type=float, default=None)
    parser.add_argument("--min-ret-over-dd", type=float, default=None)
    parser.add_argument("--bollmr-filter", action="store_true")
    parser.add_argument("--tz", default=None)
    args = parser.parse_args()

    settings = load_settings(args.config)
    sources = [args.source]
    if args.sources:
        sources = [s.strip() for s in args.sources.split(",") if s.strip()]

    broker = settings.broker
    config = BacktestConfig(
        symbol=args.symbol,
        timeframe=args.timeframe,
        initial_cash=broker.initial_cash,
        spread_points=broker.spread_points,
        commission_per_lot=broker.commission_per_lot,
        point=broker.point,
        lot_size=broker.lot_size,
        leverage=broker.leverage,
        trade_lot=broker.trade_lot,
    )

    grid = _parse_grid(args.grid)
    if "logic_mode" not in grid:
        grid["logic_mode"] = [args.logic]
    results = []

    for source in sources:
        data_path = resolve_data_path(settings.paths, source, args.data)
        df, source_kind = load_data(str(data_path), source, tz=args.tz, resample_rule=args.resample)
        if args.resample and source_kind == "ohlc":
            df = resample_ohlc(df, args.resample)

        for overrides in _iter_grid(grid):
            params = _build_params(settings.strategy.boll_mr, overrides, broker.point)
            strategy = BollMeanReversionStrategy(params)
            signals = strategy.generate_signals(df)
            filtered = IdentityFilter().apply(strategy.build_features(df), signals)
            if params.min_confidence > 0:
                filtered.signals = filtered.signals.where(filtered.confidence >= params.min_confidence, 0)
            filtered.signals = _apply_risk_controls(df, filtered.signals, filtered.confidence, config, params)

            result = run_backtest(df, filtered.signals, config)
            trades_df = result.trades
            gross_profit = float(trades_df.loc[trades_df["pnl"] > 0, "pnl"].sum()) if not trades_df.empty else 0.0
            gross_loss = float(trades_df.loc[trades_df["pnl"] < 0, "pnl"].sum()) if not trades_df.empty else 0.0
            profit_factor = 0.0
            if gross_loss < 0:
                profit_factor = gross_profit / abs(gross_loss)
            ret = float(result.stats.get("total_return", 0.0))
            dd = float(result.stats.get("max_drawdown", 0.0))
            ret_over_dd = ret / abs(dd) if dd < 0 else 0.0
            ending_balance = float(result.equity.iloc[-1]) if not result.equity.empty else float(config.initial_cash)
            win_rate = 0.0
            if not trades_df.empty:
                wins = int((trades_df["pnl"] > 0).sum())
                win_rate = wins / len(trades_df)

            row = {
                "source": source,
                **overrides,
                "total_return": ret,
                "max_drawdown": dd,
                "sharpe": result.stats.get("sharpe", 0.0),
                "trades": result.stats.get("trades", 0),
                "profit_factor": profit_factor,
                "ret_over_dd": ret_over_dd,
                "win_rate": win_rate,
                "ending_balance": ending_balance,
            }
            results.append(row)

    out_path = Path(resolve_path(settings.paths.data_root, args.out))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    df_out = pd.DataFrame(results)

    if args.bollmr_filter:
        # BollMR default screening thresholds (stable mean-reversion expectations)
        args.min_sharpe = 1.0 if args.min_sharpe is None else args.min_sharpe
        args.max_dd = 0.15 if args.max_dd is None else args.max_dd
        args.min_trades = 80 if args.min_trades is None else args.min_trades
        args.min_profit_factor = 1.2 if args.min_profit_factor is None else args.min_profit_factor

    if args.min_sharpe is not None:
        df_out = df_out[df_out["sharpe"] >= args.min_sharpe]
    if args.min_trades is not None:
        df_out = df_out[df_out["trades"] >= args.min_trades]
    if args.max_dd is not None:
        df_out = df_out[df_out["max_drawdown"] >= -abs(args.max_dd)]
    if args.min_profit_factor is not None:
        df_out = df_out[df_out["profit_factor"] >= args.min_profit_factor]
    if args.min_ret_over_dd is not None:
        df_out = df_out[df_out["ret_over_dd"] >= args.min_ret_over_dd]

    df_out.to_csv(out_path, index=False)
    print(f"[param_sweep] saved: {out_path}")

    if args.top and args.top > 0 and not df_out.empty:
        sort_col = args.sort if args.sort in df_out.columns else "total_return"
        sort_secondary = args.sort_secondary if args.sort_secondary in df_out.columns else None

        ascending_primary = sort_col in {"max_drawdown"}
        if sort_secondary is None:
            top_df = df_out.sort_values(sort_col, ascending=ascending_primary).head(args.top)
        else:
            ascending_secondary = sort_secondary in {"max_drawdown"}
            top_df = df_out.sort_values(
                [sort_col, sort_secondary],
                ascending=[ascending_primary, ascending_secondary],
            ).head(args.top)

        top_path = out_path.with_name(out_path.stem + f"_top{args.top}" + out_path.suffix)
        top_df.to_csv(top_path, index=False)
        print(f"[param_sweep] saved: {top_path}")
        preview_cols = [
            c for c in [
                "source", "entry_mode", "boll_period", "boll_dev", "ma_period",
                "max_holding_bars", "total_return", "max_drawdown", "sharpe",
                "trades", "win_rate", "profit_factor", "ret_over_dd", "ending_balance",
            ] if c in top_df.columns
        ]
        if preview_cols:
            print("[param_sweep] top preview:")
            print(top_df[preview_cols].head(min(10, len(top_df))).to_string(index=False))


if __name__ == "__main__":
    main()
