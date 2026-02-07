from __future__ import annotations

import argparse
from pathlib import Path

from core.data import load_data, resample_ohlc
from core.settings import load_settings, resolve_data_path, resolve_path


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Normalize data for backtesting")
    parser.add_argument("--config", default="config.json", help="Path to config.json")
    parser.add_argument("--source", default="mt5", help="mt5 / dukascopy / truefx / ticks")
    parser.add_argument("--data", required=True, help="Input CSV path")
    parser.add_argument("--out", required=True, help="Output CSV path")
    parser.add_argument("--resample", default="", help="Optional resample rule, e.g. 15T or 1H")
    parser.add_argument("--tz", default="", help="Optional timezone for parsing time")
    return parser.parse_args()


def main() -> None:
    args = _parse_args()
    settings = load_settings(args.config)

    tz = args.tz or None
    data_path = resolve_data_path(settings.paths, args.source, args.data)
    out_path = resolve_path(settings.paths.data_root, args.out)

    df, source_kind = load_data(data_path, args.source, tz=tz, resample_rule=args.resample)

    if args.resample and source_kind == "ohlc":
        df = resample_ohlc(df, args.resample)

    Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(out_path, index=True)

    print(f"Saved normalized data: {out_path}")


if __name__ == "__main__":
    main()
