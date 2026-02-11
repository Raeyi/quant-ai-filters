# quant-ai-filters

## 概览

- 目标：XAUUSD 小周期策略的可插拔体系（MQL5 实盘 + Python 回测/研究）
- 结构：策略层 + 过滤层 + 风控层，逐步引入 AI/ML

## 执行顺序总览

- M1（Mean Reversion）：先 base 基线验证 → 再小范围参数优化 → 再逐项叠加 enhanced 组件
- M2（Trend Pullback）：先 M15 方向框架 → 再 M5 回撤入场 → 再小范围优化 → 再过滤/风控叠加
- M3（Regime Filter）：先规则过滤验证 → 再 ML 打分/权重 → 最后接入策略组合与风控
- M4（回测评估）：先指标口径统一 → 再批量评估/相关性 → 最后引入更复杂评估维度
- XAUUSD Alpha：先结构识别 → 再仓位结构 → 最后参数优化

## 快速开始

### MQL5

1. MT5 数据目录 → `MQL5/Experts` 放入项目
2. 编译 `Ea_run.mq5`
3. 图表加载 EA，调整参数

### Python

```bash
cd Python
python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt
python backtest.py --help
```

## 策略族（M1）

### 分层关系

- 基础因子层：最小可运行基线（如 BB + ATR）
- 组合优化层：在基线上叠加单一过滤器（便于对比增益）
- 风控层：与策略解耦的统一风险控制

### 版本映射

- `base`：BB + ATR 基线
- `rsi`：BB + ATR + RSI 过滤
- `time`：BB + ATR + 时间过滤
- `rsi_time`：BB + ATR + RSI + 时间过滤
- `enhanced`：时间 + 趋势 + 分层退出（实验对照）

## 时间过滤（北京时间 → 自动换算 MT5 服务器时间）

**模式一：按盘面时段选择**
- `BollMR_TimeMode = "session"`
- `BollMR_Session = "asia" | "europe" | "us" | "overlap" | "europe+us"`
  - `asia`：08:00–16:00
  - `europe`：15:00–24:00
  - `us`：20:00–次日04:00
  - `overlap`：20:00–24:00
  - `europe+us`：欧盘或美盘任一满足

**模式二：自定义时间段（北京时间）**
- `BollMR_TimeMode = "custom"`
- `BollMR_StartHour / BollMR_EndHour`

**服务器时区与夏令时**
- `BollMR_ServerUTCOffset = 2`
- `BollMR_UseDST = true/false`
- `BollMR_DSTShiftHours = 1`

## 参数扫面（Python）

```bash
python Python/utils/param_sweep.py ^
  --config Python/config.json ^
  --source mt5 ^
  --data XAUUSD_M5.csv ^
  --symbol XAUUSD ^
  --timeframe M5 ^
  --grid "boll_period=18,20,22;boll_dev=1.8,2.0;ma_period=40,50" ^
  --top 20 ^
  --sort ret_over_dd ^
  --out data/param_sweep.csv
```

筛选建议：
- `--min-trades 80 --max-dd 0.25 --min-profit-factor 1.05`

输出字段包含：`total_return`、`max_drawdown`、`sharpe`、`win_rate`、`ending_balance`。

## 数据输入

- 回测输入为历史 K 线 CSV（OHLC）
- MT5 导出路径由 `Python/config.json` 的 `paths.mt5_root` 控制

## XAUUSD Alpha 体系（摘要）

- 不是均值回归，核心是“结构失衡”
- 顺序：结构识别 → 仓位结构 → 参数优化
- 详细规范见 `TODO.md`

## 说明

- `features.csv` / `signals_mt5.csv` 用于 MT5 与 Python 对齐
- 回测逻辑与 MQL5 对齐中，近期完成了 Bollinger 缓冲修正

## 细节（Web UI）

启动本地 Web 面板：

```bash
scripts\start_web_ui.cmd
```

浏览器打开：

```
http://127.0.0.1:8787
```

可用功能：

- 修改 `config.json`（路径/成本/策略参数）
- 上传 CSV 并一键运行
- 下载 MT5 导出的 `features.csv` / `signals_mt5.csv`
- 查看回测结果图表
- 查看 `mt5_root` 下的 CSV 列表并一键选用
- 导出当前策略参数为 `.set`
- 一键执行回测与数据导出

