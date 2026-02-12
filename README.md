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

- 不是均值回归，核心是"结构失衡"
- 顺序：结构识别 → 仓位结构 → 参数优化
- 详细规范见 `TODO.md`

## 策略族（M2）- Trend Pullback

### 核心理念

**大趋势 + 小级别回撤吃第二段**

- M15 确定方向（EMA50/EMA200）
- M5 寻找回撤入场点
- 吃趋势的第二段利润

### 适合品种与时段

| 推荐程度 | 时段 | 说明 |
|----------|------|------|
| ⭐⭐⭐ 最适合 | 美盘 (us) | 趋势明确，回撤结构清晰 |
| ⭐⭐ 次优 | 欧/美重叠 (overlap) | 流动性最好 |
| ⭐ 可用 | 欧盘后半段 | 需观察 |
| ❌ 不推荐 | 亚盘 | 假突破多，趋势不明确 |

### 入场逻辑

#### 1. 方向判断（M15）
```
多头趋势：EMA50 > EMA200 + 价格在 VWAP 上方
空头趋势：EMA50 < EMA200 + 价格在 VWAP 下方
```

#### 2. 回撤确认（M5）

**价值区判断**：
- 价格回撤到 EMA20 或 VWAP 附近
- 容差：±0.3 ATR

**回撤深度限制**：
- 最大回撤 < 0.618 ATR
- 防止回撤太深变成反转

#### 3. 止跌/止涨信号（K线形态）

**多头止跌**（满足其一）：
- 阳线反包：当前阳线完全包含前一根K线
- 小实体 + 锤子线：实体 < 平均实体一半 + 下影线 > 实体1.5倍

**空头止涨**（满足其一）：
- 阴线反包：当前阴线完全包含前一根K线
- 小实体 + 流星线：实体 < 平均实体一半 + 上影线 > 实体1.5倍

#### 4. 结构突破确认

**关键改进**：
- 多头：用 **Ask** 判断突破（真实买入价）
- 空头：用 **Bid** 判断跌破（真实卖出价）

**突破目标**：
- 多头突破回撤 Lower High（非简单 High[1]）
- 空头跌破回撤 Higher Low（非简单 Low[1]）

### 出场逻辑（四层结构）

```
核心原则：先活下来 → 再吃趋势 → 再放飞
```

| 层级 | 名称 | 触发条件 | 动作 |
|------|------|----------|------|
| L1 | 防御止损 | 结构破坏 / 初始SL触及 | 全平 |
| L2 | 最小兑现 | 盈利 ≥ +1.5 ATR | 平仓30-40% |
| L3 | 趋势持有 | EMA20+VWAP 双双跌破 / 趋势反转 | 全平 |
| L4 | 时间止盈 | 交易时段结束 | 全平 |

**Trailing Stop**（可选）：
- 启用后，止损跟随价格移动
- 距离：2.5 ATR

### 风控参数

```
TrendPullback.Risk:
- TP_ATR_Period    = 14    // ATR 周期
- TP_ATR_SL_Multi  = 1.0   // 初始止损倍数

TrendPullback.Exit:
- TP_PartialExit1_ATR   = 1.5   // L2 触发阈值
- TP_PartialExit1_Ratio = 0.35  // L2 平仓比例
- TP_TrailATR_Multi     = 2.5   // Trailing 距离
- TP_EnableTrailing     = true  // 启用 Trailing
```

### 时间过滤

```
TrendPullback.TimeFilter:
- TP_Session            = "us,overlap"  // 默认美盘+重叠
- TP_TimeFilterEntry    = true          // 入场时间过滤
- TP_TimeExitEndSession = true          // 时段结束平仓
```

复用 BollMR 的时间参数：
- `BollMR_ServerUTCOffset` - 服务器 UTC 偏移
- `BollMR_UseDST` - 夏令时开关
- `BollMR_DSTShiftHours` - 夏令时平移小时数

### 参数分组

| 分组 | 用途 |
|------|------|
| TrendPullback.HTF | M15 方向判断参数 |
| TrendPullback.LTF | M5 回撤入场参数 |
| TrendPullback.Structure | 结构确认参数 |
| TrendPullback.Risk | 初始止损参数 |
| TrendPullback.Exit | 四层出场参数 |
| TrendPullback.Timeframe | 周期设置 |
| TrendPullback.TimeFilter | 时间过滤参数 |

### 实盘注意事项

1. **Ask/Bid 使用**：多头用 Ask 入场，空头用 Bid 入场，避免点差陷阱
2. **回撤深度**：必须限制，否则变成"抄底逃顶"
3. **时段选择**：美盘最佳，亚盘假信号多
4. **K线形态**：小实体必须配合方向性信号，单独不成立

## 参数优化关键发现（BollMR base 模式）

基于 2025.09.01 - 2026.01.30 的 XAUUSD M5 数据参数扫描结果：

| 参数 | 优化建议 | 说明 |
|------|----------|------|
| boll_dev | **2.5**（原 2.0） | 更宽的布林带能过滤更多假信号 |
| atr_vol_limit | **1.2**（原 1.5） | 更严格的波动率过滤效果更好 |
| boll_period | **15-20** | 最佳范围 |
| atr_period | **10**（原 14） | 较短周期反应更快 |

**最佳组合**：`boll_period=15, boll_dev=2.5, atr_period=10, atr_vol_limit=1.2`
- 总收益：+5412（5个月）
- 胜率：61.8%
- 盈亏比：1.38
- 交易数：421笔

> 注意：以上优化基于 base 模式（无时间/RSI/MA过滤），enhanced 模式参数需单独验证。

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

