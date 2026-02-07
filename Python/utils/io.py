from __future__ import annotations

import pandas as pd


def write_csv(df: pd.DataFrame, path: str, index: bool = False) -> None:
    df.to_csv(path, index=index)
