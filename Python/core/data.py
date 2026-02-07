from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, Optional, Tuple

import pandas as pd


@dataclass
class DataSpec:
    symbol: str
    timeframe: str
    tz: Optional[str] = None


_COLUMN_MAP: Dict[str, str] = {
    "open": "open",
    "high": "high",
    "low": "low",
    "close": "close",
    "bid": "bid",
    "ask": "ask",
    "tickvol": "tick_volume",
    "tick volume": "tick_volume",
    "tick_volume": "tick_volume",
    "volume": "volume",
    "spread": "spread",
    "datetime": "time",
    "timestamp": "time",
    "gmt time": "time",
    "date time": "time",
    "日期": "date",
    "时间": "time",
    "开盘": "open",
    "最高": "high",
    "最低": "low",
    "收盘": "close",
    "成交量": "volume",
    "交易量": "volume",
    "点差": "spread",
}


def _normalize_columns(columns) -> Dict[str, str]:
    mapping: Dict[str, str] = {}
    for col in columns:
        key = col.strip().lstrip("\ufeff")
        if key.startswith("<") and key.endswith(">"):
            key = key[1:-1]
        key = key.strip().lower()
        if key in _COLUMN_MAP:
            mapping[col] = _COLUMN_MAP[key]
        elif key in ("date", "time"):
            mapping[col] = key
    return mapping


def _parse_time_column(df: pd.DataFrame, tz: Optional[str]) -> pd.DataFrame:
    if "date" in df.columns and "time" in df.columns:
        dt = df["date"].astype(str) + " " + df["time"].astype(str)
        df["time"] = pd.to_datetime(dt, errors="coerce")
    elif "date" in df.columns:
        df["time"] = pd.to_datetime(df["date"], errors="coerce")
    elif "time" in df.columns:
        df["time"] = pd.to_datetime(df["time"], errors="coerce")
    else:
        raise ValueError("CSV must include Date+Time or Time columns")

    if tz:
        df["time"] = df["time"].dt.tz_localize(tz, nonexistent="shift_forward", ambiguous="NaT")
    return df


def _load_csv(path: str) -> pd.DataFrame:
    # MT5 exports can be comma/semicolon/tab separated. Let pandas infer.
    df = pd.read_csv(path, sep=None, engine="python")
    col_map = _normalize_columns(df.columns)
    df = df.rename(columns=col_map)
    return df


def _ensure_ohlc(df: pd.DataFrame) -> pd.DataFrame:
    required = ["open", "high", "low", "close"]
    missing = [name for name in required if name not in df.columns]
    if missing:
        raise ValueError(f"Missing required columns: {missing}")
    return df


def load_mt5_csv(path: str, tz: Optional[str] = None) -> pd.DataFrame:
    df = _load_csv(path)
    df = _parse_time_column(df, tz)
    df = _ensure_ohlc(df)
    df = df.sort_values("time")
    df = df.dropna(subset=["time", "open", "high", "low", "close"])
    return df.set_index("time")


def load_ohlc_csv(path: str, tz: Optional[str] = None) -> pd.DataFrame:
    df = _load_csv(path)
    df = _parse_time_column(df, tz)
    df = _ensure_ohlc(df)
    df = df.sort_values("time")
    df = df.dropna(subset=["time", "open", "high", "low", "close"])
    return df.set_index("time")


def load_tick_csv(path: str, tz: Optional[str] = None) -> pd.DataFrame:
    df = _load_csv(path)
    df = _parse_time_column(df, tz)
    if "bid" not in df.columns and "ask" not in df.columns:
        raise ValueError("Tick CSV must include bid/ask columns")
    df = df.sort_values("time")
    df = df.dropna(subset=["time"])
    df = df.set_index("time")
    return df


def resample_ohlc(df: pd.DataFrame, rule: str) -> pd.DataFrame:
    ohlc = df[["open", "high", "low", "close"]].resample(rule).agg(
        {"open": "first", "high": "max", "low": "min", "close": "last"}
    )
    extra = []
    for col in ("volume", "tick_volume", "spread"):
        if col in df.columns:
            extra.append(col)
    if extra:
        extra_df = df[extra].resample(rule).sum()
        ohlc = ohlc.join(extra_df, how="left")
    return ohlc.dropna(subset=["open", "high", "low", "close"])


def resample_ticks_to_ohlc(df: pd.DataFrame, rule: str) -> pd.DataFrame:
    if "bid" in df.columns and "ask" in df.columns:
        mid = (df["bid"] + df["ask"]) / 2.0
    elif "bid" in df.columns:
        mid = df["bid"]
    else:
        mid = df["ask"]
    mid = mid.rename("mid")
    ohlc = mid.resample(rule).ohlc()
    ohlc = ohlc.rename(columns={"open": "open", "high": "high", "low": "low", "close": "close"})
    return ohlc.dropna(subset=["open", "high", "low", "close"])


def load_data(
    path: str,
    source: str,
    tz: Optional[str] = None,
    resample_rule: str = "",
) -> Tuple[pd.DataFrame, str]:
    source_key = source.strip().lower()
    if source_key in ("mt5", "mt5_csv"):
        df = load_mt5_csv(path, tz=tz)
        return df, "ohlc"
    if source_key in ("dukascopy", "truefx", "ohlc"):
        df = load_ohlc_csv(path, tz=tz)
        return df, "ohlc"
    if source_key in ("ticks", "tick"):
        if not resample_rule:
            raise ValueError("Tick data requires --resample to build OHLC bars")
        ticks = load_tick_csv(path, tz=tz)
        return resample_ticks_to_ohlc(ticks, resample_rule), "ticks"
    raise ValueError(f"Unknown source: {source}")
