from dataclasses import dataclass


@dataclass
class BacktestConfig:
    symbol: str
    timeframe: str
    initial_cash: float = 10000.0
    lot_size: int = 100000
    trade_lot: float = 0.01
    leverage: float = 1.0
    spread_points: float = 0.0
    commission_per_lot: float = 0.0
    slippage_points: float = 0.0
    point: float = 0.0001
    trade_on_close: bool = False

