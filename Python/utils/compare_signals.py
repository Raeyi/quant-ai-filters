from __future__ import annotations

import argparse
from pathlib import Path
import csv

import pandas as pd


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Compare MT5 vs Python signals")
    parser.add_argument("--python", required=True, help="Python signals.csv path")
    parser.add_argument("--mt5", required=True, help="MT5 signals CSV path")
    parser.add_argument("--out", default="", help="Optional diff CSV output path")
    parser.add_argument("--start-time", default="", help="Filter start time (YYYY-MM-DD HH:MM:SS)")
    parser.add_argument("--end-time", default="", help="Filter end time (YYYY-MM-DD HH:MM:SS)")
    parser.add_argument(
        "--mt5-offset-hours",
        type=float,
        default=0.0,
        help="Shift MT5 timestamps by N hours to align timezones",
    )
    parser.add_argument("--drop-first", type=int, default=0, help="Drop first N aligned rows")
    parser.add_argument("--drop-last", type=int, default=0, help="Drop last N aligned rows")
    parser.add_argument(
        "--event-only",
        action="store_true",
        help="Compare only bars where signal changed (entry/exit events)",
    )
    return parser.parse_args()


def _detect_delimiter(path: str, encoding: str) -> str:
    try:
        with open(path, "r", encoding=encoding, errors="ignore") as f:
            sample = f.read(4096)
        if "\t" in sample and "," not in sample:
            return "\t"
        return csv.Sniffer().sniff(sample).delimiter
    except Exception:  # noqa: BLE001
        return ","


def _read_csv_with_fallback(path: str) -> pd.DataFrame:
    encodings = ["utf-8-sig", "utf-16", "utf-16-le", "utf-16-be", "gbk"]
    last_err: Exception | None = None
    for enc in encodings:
        try:
            delim = _detect_delimiter(path, enc)
            return pd.read_csv(path, encoding=enc, sep=delim)
        except Exception as exc:  # noqa: BLE001
            last_err = exc
            continue
    if last_err:
        raise last_err
    return pd.read_csv(path)


def _read_signals(path: str) -> pd.DataFrame:
    df = _read_csv_with_fallback(path)
    if "time" not in df.columns or "signal" not in df.columns:
        raise ValueError("signals file must include 'time' and 'signal' columns")
    df["time"] = pd.to_datetime(df["time"], errors="coerce")
    df = df.set_index("time")
    return df[["signal"]].rename(columns={"signal": "signal"})


def main() -> None:
    args = _parse_args()
    py = _read_signals(args.python).rename(columns={"signal": "py_signal"})
    mt5 = _read_signals(args.mt5).rename(columns={"signal": "mt5_signal"})
    if args.mt5_offset_hours:
        mt5.index = mt5.index + pd.Timedelta(hours=args.mt5_offset_hours)

    merged = py.join(mt5, how="inner")
    if merged.empty:
        raise ValueError("No overlapping timestamps between Python and MT5 signals")

    if args.start_time:
        start = pd.to_datetime(args.start_time, errors="coerce")
        if pd.isna(start):
            raise ValueError("Invalid --start-time format")
        merged = merged.loc[merged.index >= start]
    if args.end_time:
        end = pd.to_datetime(args.end_time, errors="coerce")
        if pd.isna(end):
            raise ValueError("Invalid --end-time format")
        merged = merged.loc[merged.index <= end]

    if args.drop_first > 0:
        merged = merged.iloc[args.drop_first :]

    if args.drop_last > 0:
        merged = merged.iloc[: -args.drop_last]

    if args.event_only and not merged.empty:
        py_changed = merged["py_signal"].ne(merged["py_signal"].shift(1))
        mt5_changed = merged["mt5_signal"].ne(merged["mt5_signal"].shift(1))
        merged = merged[py_changed | mt5_changed]

    if merged.empty:
        raise ValueError("No data after applying filters")

    merged["match"] = merged["py_signal"] == merged["mt5_signal"]
    total = len(merged)
    matched = int(merged["match"].sum())
    mismatched = total - matched
    ratio = matched / total if total > 0 else 0.0

    print(f"Total aligned bars: {total}")
    print(f"Matched: {matched}")
    print(f"Mismatched: {mismatched}")
    print(f"Match ratio: {ratio:.4f}")

    if args.out:
        diff = merged[~merged["match"]].copy()
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        diff.insert(0, "time", diff.index)
        diff.to_csv(out_path, index=False)
        print(f"Saved diff: {out_path}")


if __name__ == "__main__":
    main()
