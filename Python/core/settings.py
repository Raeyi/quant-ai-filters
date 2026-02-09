from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict


@dataclass
class BrokerSettings:
    name: str = "ECMarkets"
    spread_points: float = 0.0
    commission_per_lot: float = 0.0
    slippage_points: float = 0.0
    lot_size: int = 100000
    point: float = 0.0001


@dataclass
class DataPaths:
    data_root: str = "data"
    mt5_root: str = ""
    third_party_root: str = ""
    mt5_common_root: str = ""


@dataclass
class BollMrSettings:
    entry_mode: str = "A"
    allowed_start_hour: int = 2
    allowed_end_hour: int = 20
    boll_period: int = 20
    boll_dev: float = 2.0
    atr_period: int = 14
    shortest_closing_time: int = 10
    struct_atr_sl: float = 0.8
    vol_atr_sl: float = 2.0
    mid_atr_tp: float = 0.2
    mid_atr_tp2: float = 0.5
    uplow_atr_tp: float = 0.1
    ma_period: int = 50
    time_offset_hours: float = 0.0
    max_holding_bars: int = 0
    max_daily_loss_percent: float = 0.0
    risk_percent: float = 0.0
    max_losing_streak: int = 0
    cooldown_bars_after: int = 0
    cooldown_seconds: int = 0
    min_confidence: float = 0.0
    gap_cooldown_bars: int = 5
    gap_threshold_multiplier: float = 1.5


@dataclass
class StrategySettings:
    boll_mr: BollMrSettings


@dataclass
class AppSettings:
    broker: BrokerSettings
    paths: DataPaths
    strategy: StrategySettings


def _get(d: Dict[str, Any], key: str, default: Any) -> Any:
    if key in d:
        return d[key]
    return default


def load_settings(path: str | Path) -> AppSettings:
    p = Path(path)
    if not p.exists():
        return AppSettings(
            broker=BrokerSettings(),
            paths=DataPaths(),
            strategy=StrategySettings(boll_mr=BollMrSettings()),
        )

    raw = json.loads(p.read_text(encoding="utf-8-sig"))
    active_profile = raw.get("active_profile", "")
    profiles = raw.get("profiles", {})
    if active_profile and isinstance(profiles, dict) and active_profile in profiles:
        profile = profiles[active_profile]
    else:
        profile = raw

    broker_raw = profile.get("broker", {})
    paths_raw = profile.get("paths", {})
    strategy_raw = profile.get("strategy", {})
    boll_raw = strategy_raw.get("boll_mr", {})

    broker = BrokerSettings(
        name=_get(broker_raw, "name", "ECMarkets"),
        spread_points=float(_get(broker_raw, "spread_points", 0.0)),
        commission_per_lot=float(_get(broker_raw, "commission_per_lot", 0.0)),
        slippage_points=float(_get(broker_raw, "slippage_points", 0.0)),
        lot_size=int(_get(broker_raw, "lot_size", 100000)),
        point=float(_get(broker_raw, "point", 0.0001)),
    )

    paths = DataPaths(
        data_root=_get(paths_raw, "data_root", "data"),
        mt5_root=_get(paths_raw, "mt5_root", ""),
        third_party_root=_get(paths_raw, "third_party_root", ""),
        mt5_common_root=_get(paths_raw, "mt5_common_root", ""),
    )
    boll = BollMrSettings(
        entry_mode=_get(boll_raw, "entry_mode", "A"),
        allowed_start_hour=int(_get(boll_raw, "allowed_start_hour", 2)),
        allowed_end_hour=int(_get(boll_raw, "allowed_end_hour", 20)),
        boll_period=int(_get(boll_raw, "boll_period", 20)),
        boll_dev=float(_get(boll_raw, "boll_dev", 2.0)),
        atr_period=int(_get(boll_raw, "atr_period", 14)),
        shortest_closing_time=int(_get(boll_raw, "shortest_closing_time", 10)),
        struct_atr_sl=float(_get(boll_raw, "struct_atr_sl", 0.8)),
        vol_atr_sl=float(_get(boll_raw, "vol_atr_sl", 2.0)),
        mid_atr_tp=float(_get(boll_raw, "mid_atr_tp", 0.2)),
        mid_atr_tp2=float(_get(boll_raw, "mid_atr_tp2", 0.5)),
        uplow_atr_tp=float(_get(boll_raw, "uplow_atr_tp", 0.1)),
        ma_period=int(_get(boll_raw, "ma_period", 50)),
        time_offset_hours=float(_get(boll_raw, "time_offset_hours", 0.0)),
        max_holding_bars=int(_get(boll_raw, "max_holding_bars", 0)),
        max_daily_loss_percent=float(_get(boll_raw, "max_daily_loss_percent", 0.0)),
        risk_percent=float(_get(boll_raw, "risk_percent", 0.0)),
        max_losing_streak=int(_get(boll_raw, "max_losing_streak", 0)),
        cooldown_bars_after=int(_get(boll_raw, "cooldown_bars_after", 0)),
        cooldown_seconds=int(_get(boll_raw, "cooldown_seconds", 0)),
        min_confidence=float(_get(boll_raw, "min_confidence", 0.0)),
        gap_cooldown_bars=int(_get(boll_raw, "gap_cooldown_bars", 5)),
        gap_threshold_multiplier=float(_get(boll_raw, "gap_threshold_multiplier", 1.5)),
    )
    strategy = StrategySettings(boll_mr=boll)
    return AppSettings(broker=broker, paths=paths, strategy=strategy)


def resolve_path(base: str, path: str) -> str:
    if not path:
        return path
    p = Path(path)
    if p.is_absolute():
        return str(p)
    if not base:
        return str(p)
    base_path = Path(base)
    try:
        if p.parts and base_path.name and p.parts[0].lower() == base_path.name.lower():
            return str(p.resolve())
    except OSError:
        pass
    return str((base_path / p).resolve())


def resolve_data_path(paths: DataPaths, source: str, path: str) -> str:
    key = source.strip().lower()
    base = paths.data_root
    if key in ("mt5", "mt5_csv") and paths.mt5_root:
        base = paths.mt5_root
    elif key in ("dukascopy", "truefx", "ticks", "tick") and paths.third_party_root:
        base = paths.third_party_root
    return resolve_path(base, path)
