from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build ML dataset from features + signals")
    parser.add_argument("--features", required=True, help="Path to features.csv")
    parser.add_argument("--signals", required=True, help="Path to signals.csv")
    parser.add_argument("--out", required=True, help="Output dataset CSV path")
    parser.add_argument(
        "--label-shift",
        type=int,
        default=0,
        help="Shift labels forward by N bars (positive = future label)",
    )
    parser.add_argument(
        "--drop-flat",
        action="store_true",
        help="Drop rows where signal == 0",
    )
    return parser.parse_args()


def _read_csv(path: str) -> pd.DataFrame:
    df = pd.read_csv(path)
    if "time" in df.columns:
        df["time"] = pd.to_datetime(df["time"], errors="coerce")
        df = df.set_index("time")
    else:
        df.index = pd.to_datetime(df.index, errors="coerce")
    return df


def main() -> None:
    args = _parse_args()
    features_path = Path(args.features)
    signals_path = Path(args.signals)
    out_path = Path(args.out)

    features = _read_csv(str(features_path))
    signals = _read_csv(str(signals_path))

    if "signal" not in signals.columns:
        raise ValueError("signals.csv must include 'signal' column")

    labels = signals[["signal"]].copy()
    if args.label_shift != 0:
        labels["signal"] = labels["signal"].shift(-args.label_shift)

    dataset = features.join(labels, how="inner")
    dataset = dataset.dropna()

    if args.drop_flat:
        dataset = dataset[dataset["signal"] != 0]

    dataset.insert(0, "time", dataset.index)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    dataset.to_csv(out_path, index=False)

    print(f"Saved dataset: {out_path}")


if __name__ == "__main__":
    main()
