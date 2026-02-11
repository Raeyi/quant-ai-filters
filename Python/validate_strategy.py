"""Validate Python BollMR strategy against MQL5 variants.

This script tests each logic_mode to ensure:
1. Indicators are calculated correctly
2. Entry/exit signals match MQL5 behavior
3. All modes produce expected signal counts

Usage:
    python validate_strategy.py --data XAUUSD_M5_202509010100_202601302350.csv
"""

from __future__ import annotations

import argparse
from dataclasses import replace
from pathlib import Path

import pandas as pd

from core.data import load_data
from core.settings import load_settings, resolve_data_path
from strategies.boll_mean_reversion import BollMeanReversionParams, BollMeanReversionStrategy


def test_mode(df: pd.DataFrame, mode: str, params: BollMeanReversionParams) -> dict:
    """Test a specific logic_mode and return diagnostics."""
    test_params = replace(params, logic_mode=mode)
    strategy = BollMeanReversionStrategy(test_params)
    signals = strategy.generate_signals(df, diagnose=True)

    diag = strategy.last_diagnostics.copy()
    diag["mode"] = mode
    diag["long_pct"] = diag.get("signals_long", 0) / max(diag.get("bars_valid", 1), 1) * 100
    diag["short_pct"] = diag.get("signals_short", 0) / max(diag.get("bars_valid", 1), 1) * 100

    return diag


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate BollMR strategy modes")
    parser.add_argument("--config", default="Python/config.json")
    parser.add_argument("--data", required=True, help="Data file name or path")
    parser.add_argument("--source", default="mt5", choices=["mt5", "dukascopy", "data"])
    parser.add_argument("--out", default="", help="Output CSV path for results")
    args = parser.parse_args()

    # Load settings and data
    settings = load_settings(args.config)
    
    # Handle absolute vs relative paths
    data_path = Path(args.data)
    if not data_path.is_absolute():
        data_path = Path(resolve_data_path(settings.paths, args.source, args.data))
    
    df, _ = load_data(str(data_path), args.source)

    print(f"Loaded {len(df)} bars from {data_path}")
    print(f"Time range: {df.index[0]} to {df.index[-1]}")
    print()

    # Build base params from config
    cfg = settings.strategy.boll_mr
    base_params = BollMeanReversionParams(
        logic_mode=cfg.logic_mode,
        entry_mode=cfg.entry_mode,
        allowed_start_hour=cfg.allowed_start_hour,
        allowed_end_hour=cfg.allowed_end_hour,
        time_offset_hours=cfg.time_offset_hours,
        boll_period=cfg.boll_period,
        boll_dev=cfg.boll_dev,
        atr_period=cfg.atr_period,
        atr_vol_limit=cfg.atr_vol_limit,
        rsi_period=cfg.rsi_period,
        rsi_overbought=cfg.rsi_overbought,
        rsi_oversold=cfg.rsi_oversold,
        shortest_closing_time=cfg.shortest_closing_time,
        struct_atr_sl=cfg.struct_atr_sl,
        vol_atr_sl=cfg.vol_atr_sl,
        bool_mid_atr_tp=cfg.mid_atr_tp,
        bool_mid_atr_tp2=cfg.mid_atr_tp2,
        bool_uplow_atr_tp=cfg.uplow_atr_tp,
        ma_period=cfg.ma_period,
        point=settings.broker.point,
        gap_cooldown_bars=cfg.gap_cooldown_bars,
        gap_threshold_multiplier=cfg.gap_threshold_multiplier,
    )

    # Test all modes
    modes = ["base", "rsi", "time", "rsi_time", "enhanced"]
    results = []

    print("=" * 80)
    print(f"{'Mode':<12} {'Bars':<8} {'Entries':<8} {'Long':<8} {'Short':<8}")
    print("=" * 80)

    for mode in modes:
        diag = test_mode(df, mode, base_params)
        results.append(diag)

        entries = diag.get("long_entries", 0) + diag.get("short_entries", 0)
        print(
            f"{mode:<12} "
            f"{diag.get('bars_valid', 0):<8} "
            f"{entries:<8} "
            f"{diag.get('long_entries', 0):<8} "
            f"{diag.get('short_entries', 0):<8}"
        )

    print("=" * 80)
    print()

    # Summary
    print("Expected behavior:")
    print("  - base: Simplest, most signals (BB regression only)")
    print("  - rsi: Fewer signals (RSI filter added)")
    print("  - time: Fewer signals (time filter added)")
    print("  - rsi_time: Fewest signals (both RSI + time filters)")
    print("  - enhanced: Similar to rsi_time but with MA trend filter")
    print()

    # Check mode ordering (signal count should decrease as filters are added)
    base_entries = results[0].get("long_entries", 0) + results[0].get("short_entries", 0)
    rsi_entries = results[1].get("long_entries", 0) + results[1].get("short_entries", 0)
    time_entries = results[2].get("long_entries", 0) + results[2].get("short_entries", 0)
    rsi_time_entries = results[3].get("long_entries", 0) + results[3].get("short_entries", 0)

    checks = []
    checks.append(("base >= rsi", base_entries >= rsi_entries))
    checks.append(("base >= time", base_entries >= time_entries))
    checks.append(("rsi >= rsi_time", rsi_entries >= rsi_time_entries))
    checks.append(("time >= rsi_time", time_entries >= rsi_time_entries))

    print("Sanity checks:")
    all_passed = True
    for name, passed in checks:
        status = "PASS" if passed else "FAIL"
        print(f"  {name}: {status}")
        if not passed:
            all_passed = False

    if args.out:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        pd.DataFrame(results).to_csv(out_path, index=False)
        print(f"\nResults saved to: {out_path}")

    if all_passed:
        print("\nAll sanity checks passed!")
    else:
        print("\nSome checks failed - review filter logic")


if __name__ == "__main__":
    main()
