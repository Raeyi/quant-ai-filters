# AI 数据文件说明（features.csv / signals.csv）

本文件说明用于回测与 AI 过滤的 CSV 数据字段规范。

## 1. Python 回测导出的 features.csv

导出方式：`backtest.py --export-features ...`

字段说明：

- `time`：时间戳（UTC 或本地时间，取决于数据源）
- `close`：上一根 K 线收盘价
- `boll_u`：上一根 K 线布林带上轨
- `boll_l`：上一根 K 线布林带下轨
- `boll_mid`：上一根 K 线布林带中轨
- `atr`：上一根 K 线 ATR
- `zscore`：上一根 K 线收盘价相对中轨的 z-score
- `band_width`：上一根 K 线布林带宽度（(upper-lower)/mid）

说明：
- “上一根 K 线”与 EA 中 `shift=1` 对齐，避免前视。

## 2. Python 回测导出的 signals.csv

导出方式：`backtest.py --export-signals ...`

字段说明：

- `time`：时间戳
- `signal`：信号方向（`1`=多，`-1`=空，`0`=空仓）
- `confidence`：信号置信度（当前为过滤器输出的 0~1）

## 3. MT5 EA 导出的 features.csv（可选）

EA 在 MT5 中会写出特征文件（默认在 `Common/Files`）：

字段说明：

- `time`
- `close`
- `boll_u`
- `boll_l`
- `atr`

用途：
- 可与 Python 端特征对齐用于一致性检查
- 可作为实盘实时特征流
