from __future__ import annotations

import argparse
import sys
from pathlib import Path

import pandas as pd

ROOT_DIR = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT_DIR / "Python"))

from indicators.atr import atr
from indicators.bollinger import bollinger_bands


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Compare MT5 vs Python features")
    parser.add_argument("--mt5", required=True, help="MT5 features.csv path")
    parser.add_argument("--data", required=True, help="Python OHLC CSV (same source as MT5)")
    parser.add_argument("--out", default="", help="Optional diff CSV output path")
    parser.add_argument("--boll-period", type=int, default=20)
    parser.add_argument("--boll-dev", type=float, default=2.0)
    parser.add_argument("--atr-period", type=int, default=14)
    parser.add_argument("--tz", default="", help="Optional timezone for parsing time")
    parser.add_argument(
        "--mt5-offset-hours",
        type=float,
        default=0.0,
        help="Shift MT5 feature timestamps by N hours to align timezones",
    )
    return parser.parse_args()


def _read_mt5(path: str) -> pd.DataFrame:
    try:
        df = pd.read_csv(path, encoding="utf-16", sep="\t")
    except UnicodeError:
        df = pd.read_csv(path, encoding="utf-8-sig", sep="\t")
    if "time" not in df.columns:
        raise ValueError("MT5 features must include 'time' column")
    df["time"] = pd.to_datetime(df["time"], errors="coerce")
    df = df.set_index("time")
    return df


def _read_ohlc(path: str, tz: str) -> pd.DataFrame:
    df = pd.read_csv(path, sep="\t")
    if "time" in df.columns:
        df["time"] = pd.to_datetime(df["time"], errors="coerce")
        df = df.set_index("time")
    else:
        # try common MT5 export columns
        if "<DATE>" in df.columns and "<TIME>" in df.columns:
            df["time"] = pd.to_datetime(df["<DATE>"] + " " + df["<TIME>"], errors="coerce")
            df = df.set_index("time")
            # normalize column names
            ren = {
                "<OPEN>": "open",
                "<HIGH>": "high",
                "<LOW>": "low",
                "<CLOSE>": "close",
                "<TICKVOL>": "tickvol",
                "<VOL>": "vol",
                "<SPREAD>": "spread",
            }
            df = df.rename(columns=ren)
        elif "Date" in df.columns and "Time" in df.columns:
            df["time"] = pd.to_datetime(df["Date"] + " " + df["Time"], errors="coerce")
            df = df.set_index("time")
        else:
            raise ValueError("OHLC CSV must include time or Date+Time columns")
    if tz:
        df.index = df.index.tz_localize(tz).tz_convert(None)
    return df


def main() -> None:
    args = _parse_args()
    mt5 = _read_mt5(args.mt5)
    if args.mt5_offset_hours:
        mt5.index = mt5.index + pd.Timedelta(hours=args.mt5_offset_hours)
    ohlc = _read_ohlc(args.data, args.tz)

    bands = bollinger_bands(ohlc["close"], args.boll_period, args.boll_dev)
    atr_series = atr(ohlc, args.atr_period)

    py = pd.DataFrame(
        {
            "close": ohlc["close"],
            "boll_u": bands["upper"],
            "boll_l": bands["lower"],
            "atr": atr_series,
        },
        index=ohlc.index,
    )

    merged = mt5.join(py, how="inner", lsuffix="_mt5", rsuffix="_py")
    if merged.empty:
        raise ValueError("No overlapping timestamps between MT5 and Python features")

    for col in ("close", "boll_u", "boll_l", "atr"):
        merged[f"{col}_diff"] = merged[f"{col}_py"] - merged[f"{col}_mt5"]

    summary = {}
    for col in ("close", "boll_u", "boll_l", "atr"):
        diff = merged[f"{col}_diff"].abs()
        summary[col] = {
            "mean_abs": float(diff.mean()),
            "max_abs": float(diff.max()),
            "p95_abs": float(diff.quantile(0.95)),
        }

    print("Feature diff summary:")
    for col, stats in summary.items():
        print(f"  {col}: mean_abs={stats['mean_abs']:.6f} p95_abs={stats['p95_abs']:.6f} max_abs={stats['max_abs']:.6f}")

    # Show a few sample rows for close mismatches
    close_diff = (merged["close_diff"].abs()).sort_values(ascending=False)
    print("Top close diffs:")
    for t in close_diff.head(5).index:
        row = merged.loc[t]
        print(f"  {t} mt5={row['close_mt5']} py={row['close_py']} diff={row['close_diff']}")

    if args.out:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        merged.reset_index().to_csv(out_path, index=False)
        print(f"Saved diff: {out_path}")


if __name__ == "__main__":
    main()
