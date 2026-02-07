# MT5 Data Format

This backtest runner supports MT5 exports and third-party CSV data.

Required columns:
- Date + Time, or Time
- Open, High, Low, Close

Optional columns:
- Spread
- Tick Volume or Volume

Example MT5 export steps:
1. Open MT5 -> Tools -> History Center.
2. Select symbol + timeframe.
3. Right click -> Export to CSV.
4. Use the exported file as `--data`.

If the export uses `Date` and `Time` columns, both are supported.
Separators such as comma, semicolon, or tab are detected automatically.

Third-party data:
- If your CSV already contains OHLC columns, use `--source dukascopy` or `--source truefx`.
- If your CSV is tick data with bid/ask, use `--source ticks` and `--resample 1T/5T/15T/...`.

All paths can be configured in `Python/config.json`:
- `paths.data_root`: default base for relative paths
- `paths.mt5_root`: base for MT5 exports
- `paths.third_party_root`: base for Dukascopy/TrueFX data
