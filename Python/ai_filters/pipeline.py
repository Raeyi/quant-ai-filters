from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

import pandas as pd


@dataclass
class FilterOutput:
    signals: pd.Series
    confidence: pd.Series


class IdentityFilter:
    def apply(self, features: pd.DataFrame, raw_signals: pd.Series) -> FilterOutput:
        confidence = pd.Series(1.0, index=raw_signals.index, name="confidence")
        return FilterOutput(signals=raw_signals, confidence=confidence)


class ZScoreThresholdFilter:
    def __init__(self, feature_name: str = "zscore", threshold: float = 0.5):
        self.feature_name = feature_name
        self.threshold = threshold

    def apply(self, features: pd.DataFrame, raw_signals: pd.Series) -> FilterOutput:
        if self.feature_name not in features.columns:
            raise ValueError(f"Missing feature: {self.feature_name}")
        strength = features[self.feature_name].abs()
        keep = strength >= self.threshold
        signals = raw_signals.where(keep, 0)
        confidence = strength.clip(0.0, 3.0) / 3.0
        confidence = confidence.rename("confidence")
        return FilterOutput(signals=signals, confidence=confidence)


def load_features(path: str) -> pd.DataFrame:
    return pd.read_csv(path, parse_dates=["time"]).set_index("time")

