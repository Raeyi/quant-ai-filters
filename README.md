# quant-ai-filters

## AI 过滤型量化多策略交易系统（Hybrid MQL5 + Python）

这是一个专注于 XAUUSD（黄金）量化交易的个人项目，目标是构建稳定盈利的多策略组合系统，并逐步引入 AI/ML 过滤信号与风控。

## 项目概述

- 核心理念：可插拔多策略 + AI/ML 信号过滤 + 严格风控
- MQL5 部分：实盘执行 EA（MT5 平台），支持多策略并行与模块化设计
- Python 部分：高保真回测、策略研究、AI/ML/RL 集成
- 主要品种：XAUUSD（黄金），以 M5/M15 等小周期策略为主

## 路线图（Milestones）

- M1 策略族拆分（Mean Reversion Family）
- M1.a BB+ATR（基础回归）
- M1.b BB+RSI（动能过滤）
- M1.c BB+时间过滤（伦敦/美盘窗口）
- M2 Trend Pullback Family v1（M15 定方向 + M5 回撤入场）
- M2.a M15：EMA50/EMA200 方向
- M2.b M5：回撤到 EMA20/VWAP + 小结构确认
- M2.c 统一 SL/TP：ATR 1.0 / 1.5–2.0
- M3 Regime Filter（先规则后 ML）
- M3.a 输出不同策略族权重（不直接下单）
- M3.b 指标：ATR 变化、假突破频率、回撤吞没速度
- M4 回测评估升级
- M4.a 不同 Regime 下胜率/回撤/收益
- M4.b 策略间相关性矩阵
- M4.c 连续亏损分布

## 策略族设计说明

### 分层关系

- 基础因子层：定义最小可运行策略基线（如 BB + ATR）
- 组合优化层：在基线之上叠加单一过滤器（如 RSI、时间窗口），便于对比增益
- 风控层：与策略解耦的统一风险控制（仓位、止损、冷却、连亏暂停）

### M1 版本映射

- M1.a：`base`（BB + ATR 基线）
- M1.b：`rsi`（BB + ATR + RSI 过滤）
- M1.c：`time`（BB + ATR + 时间过滤）
- M1.d：`rsi_time`（BB + ATR + RSI + 时间过滤）

说明：`enhanced` 为历史增强版，包含 MA 趋势过滤 + 时间过滤 + 分层退出，属于“组合优化层的实验变体”，用于对比与迭代，不作为 M1.a/b/c 的单变量基线。

## 项目结构

- `/Core`：MQL5 核心模块（风控/执行/管理）
- `/Indicators`：MQL5 指标封装
- `/Strategies`：MQL5 策略实现
- `/Python`：Python 研究与回测模块
- `/Python/data`：数据获取与清洗
- `/Python/indicators`：Python 指标实现
- `/Python/strategies`：Python 策略实现（与 MQL5 对齐中）
- `/Python/ai_filters`：AI 过滤器管线
- `/Python/core`：回测引擎与配置
- `/Python/backtest.py`：主回测脚本

## 安装与运行

### MQL5 部分

1. 打开 MT5 -> 文件 -> 打开数据文件夹 -> MQL5 -> Experts
2. 复制本项目文件
3. 编译 `Ea_run.mq5` 并加载到图表

#### 切换 BollMR 基线/增强版

在 EA 参数中设置：

- `BollMRVariant = "base"`：启用基线版（纯 BB + ATR）
- `BollMRVariant = "rsi"`：启用 RSI 过滤版（BB + ATR + RSI）
- `BollMRVariant = "time"`：启用时间过滤版（BB + ATR + 时间窗口）
- `BollMRVariant = "rsi_time"`：启用 RSI + 时间过滤版（BB + ATR + RSI + 时间窗口）
- `BollMRVariant = "enhanced"`：启用增强版（含时间/趋势/分层退出）

#### 时间过滤配置（北京时间 → 自动换算 MT5 服务器时间）

时间窗以 **北京时间（GMT+8）** 定义，EA 内部会自动换算为 MT5 服务器时间（默认 GMT+2）。

**模式一：按盘面时段选择**
- `BollMR_TimeMode = "session"`
- `BollMR_Session = "asia" | "europe" | "us" | "overlap" | "europe+us"`
  - `asia`：北京时间 08:00–16:00（亚盘）
  - `europe`：北京时间 15:00–24:00（欧盘）
  - `us`：北京时间 20:00–次日04:00（美盘）
  - `overlap`：北京时间 20:00–24:00（欧/美重叠时段）
  - `europe+us`：欧盘或美盘任一满足即允许（并集）

**模式二：自定义时间段（北京时间）**
- `BollMR_TimeMode = "custom"`
- `BollMR_StartHour / BollMR_EndHour`（北京时间小时）

**服务器时区与夏令时**
- `BollMR_ServerUTCOffset = 2`（MT5 服务器 UTC 偏移，默认 GMT+2）
- `BollMR_UseDST = true/false`（手动夏令时开关）
- `BollMR_DSTShiftHours = 1`（DST 平移小时数，默认 +1）

说明：
- 开启 `BollMR_UseDST` 时，仅对 **欧盘/美盘/重叠时段** 平移 1 小时。
- 自定义模式 `custom` 仍以北京时间填写。

### Python 部分（回测与研究）

```bash
cd Python
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt
python backtest.py --help
```

## Python 回测 - 快速验证步骤

1. 配置 `Python/config.json`：
   - `active_profile` 选择 `backtest` 或 `live`
   - `paths.mt5_root`：MT5 导出数据的根目录
   - `paths.mt5_common_root`：MT5 Common/Files 根目录（features/signals 导出）
   - `paths.third_party_root`：第三方数据根目录（Dukascopy/TrueFX）
   - `paths.data_root`：Python 相对路径的默认根目录
   - `strategy.boll_mr`：回测策略参数（需与 MT5 输入一致）
   - `broker.initial_cash`：回测初始资金（建议与 MT5 回测入金一致）
   - `broker.leverage`：回测杠杆（用于保证金约束，建议与 MT5 一致）
   - `broker.trade_lot`：回测每次下单手数（默认 0.01；用于保证金与收益缩放）
2. 准备数据：
   - MT5 导出（K 线 OHLC）使用 `--source mt5`
   - 第三方 OHLC 使用 `--source dukascopy` 或 `--source truefx`
   - Tick 数据需要先 `--resample` 转成 OHLC
3. 运行回测：
   - MT5 示例：
     `python ..\Python\backtest.py --config ..\Python\config.json --source mt5 --data XAUUSD_M5.csv --symbol XAUUSD --timeframe M5`
   - 第三方 OHLC 示例：
     `python ..\Python\backtest.py --config ..\Python\config.json --source dukascopy --data XAUUSD_M5.csv --symbol XAUUSD --timeframe M5`
4. 可选导出（用于 EA 对接）：
   - `--export-features Python/data/features.csv`
   - `--export-signals Python/data/signals.csv`

备注：

- 如果使用 Tick 数据，必须传 `--resample`（如 `1T`、`5T`、`15T`）。
- 策略逻辑正在与 MQL5 的 BollMR 对齐（近期 MQL5 侧已更新：入场用已收盘K线、回归中轨过滤、缺口冷却、Bollinger 缓冲对齐）。

## 回测行情输入文件是什么？怎么获取？

回测行情输入文件指 **历史 K 线 CSV（OHLC）**，需要包含 `Date/Time/Open/High/Low/Close` 列。
这个文件不是 EA 写出来的 `features.csv`。

### 获取方式（MT5）

新版 MT5 没有 “历史数据中心” 菜单时，推荐这样导出：

1. 按 `Ctrl+U` 打开 **品种(Symbols)** 窗口
2. 选择品种（如 `XAUUSD`）
3. 切换到 **Bars**（K 线）标签页
4. 点击 **Request** 下载数据
5. 点击 **Export** 导出 CSV

### 获取方式（第三方）

- Dukascopy / TrueFX 下载的 OHLC 或 Tick 数据
- OHLC 可直接回测；Tick 需要先 `--resample` 转成 OHLC

## 说明

- `features.csv` 是 EA 在 MT5 中导出的特征文件，默认位于 `Common/Files`，不是回测行情输入。
- `signals_mt5.csv` 是 EA 在 MT5 中导出的信号文件，默认位于 `Common/Files`，可用于与 Python 信号对齐验证。
- 如果需要自动导出行情 CSV，我可以提供 MQL5 脚本。

## 图形化配置与一键运行（Web）

启动本地 Web 面板：

scripts\start_web_ui.cmd

浏览器打开：

<http://127.0.0.1:8787>

在网页上你可以：

- 修改 `config.json`（路径/成本/策略参数）
- 一键导入 MT5 `.set` 参数文件
- 上传 CSV 并一键运行
- 直接下载 MT5 导出的 `features.csv` / `signals_mt5.csv`
- 查看回测结果图表
- 查看 mt5_root 下的 CSV 列表并一键选用
- 导出当前策略参数为 `.set`
- 一键执行回测与数据导出

## AI 数据与工具

1. 字段说明文档：
   - `docs/ai_data_schema.md`
2. 训练样本构建脚本（features + signals -> dataset）：
   - `Python/utils/build_dataset.py`
   - 示例：
     `python Python/utils/build_dataset.py --features Python/data/features.csv --signals Python/data/signals.csv --out Python/data/dataset.csv --label-shift 1`
3. MT5 vs Python 信号对齐对比脚本：
   - `Python/utils/compare_signals.py`
   - 示例：
     `python Python/utils/compare_signals.py --python Python/data/signals.csv --mt5 Python/data/signals_mt5.csv --out Python/data/signal_diff.csv`
   - 可选过滤参数：
     `--start-time "2025-01-01 00:00:00" --end-time "2025-02-01 00:00:00" --drop-first 50 --drop-last 50 --event-only`

## 一键运行（单命令）

在 Windows 终端执行：

scripts\run_pipeline.cmd -Data XAUUSD_M5_202409050345_202602062350.csv -Source mt5 -Symbol XAUUSD -Timeframe M5

可选参数示例：

scripts\run_pipeline.cmd -Data XAUUSD_M5_202409050345_202602062350.csv -Source mt5 -Symbol XAUUSD -Timeframe M5 -OutDir data -LabelShift 1 -Filter identity

如果有 MT5 导出的信号文件（`signals_mt5.csv`），可以加：

scripts\run_pipeline.cmd -Data XAUUSD_M5_202409050345_202602062350.csv -Source mt5 -Symbol XAUUSD -Timeframe M5 -Mt5Signals data/signals_mt5.csv

自动选取最新 CSV 并自动切换 profile：

scripts\run_pipeline.cmd -AutoProfile -DataPattern *.csv -Source mt5 -Symbol XAUUSD -Timeframe M5

手动切换 profile：

scripts\run_pipeline.cmd -Profile backtest -Data XAUUSD_M5_202409050345_202602062350.csv -Source mt5 -Symbol XAUUSD -Timeframe M5

策略参数对齐（与 MT5 输入一致）：

scripts\run_pipeline.cmd -Data XAUUSD_M5_202409050345_202602062350.csv -Source mt5 -Symbol XAUUSD -Timeframe M5 -EntryMode A -StartHour 20 -EndHour 14 -BollPeriod 18 -BollDev 1.8 -AtrPeriod 14 -ShortestClosingTime 10 -StructAtrSl 0.8 -VolAtrSl 2.0 -MidAtrTp 0.2 -UplowAtrTp 0.1 -MaPeriod 50

说明：

- `run_pipeline.cmd` 是 Windows 的快捷入口，它会调用 `run_pipeline.ps1`
- 脚本会依次执行：回测 -> 导出 features/signals -> 构建训练集 ->（可选）信号对齐对比
- 如果不传策略参数，脚本会使用 `config.json` 里的 `strategy.boll_mr` 默认值
