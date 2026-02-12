# quant-ai-filters

## 概览

- 目标：XAUUSD 小周期策略的可插拔体系（MQL5 实盘 + Python 回测/研究）
- 结构：策略层 + 过滤层 + 风控层，逐步引入 AI/ML

## 代码架构

### 目录结构

```
quant-ai-filters/
├── Ea_run.mq5              # EA 主入口
├── Core/                   # 核心模块
│   ├── Signal.mqh          # 信号结构体定义
│   ├── TradeTypes.mqh      # 交易类型枚举
│   ├── TradeExecutor.mqh   # 交易执行器
│   ├── Strategy.mqh        # 策略接口
│   ├── StrategyManager.mqh # 策略管理器
│   ├── PositionCoordinator.mqh # 持仓协调器
│   ├── Inputs_All.mqh      # 统一输入参数
│   ├── Risk/               # 风控子模块
│   │   ├── RiskPipeline.mqh    # 风控管道（统一入口）
│   │   ├── Cooldown.mqh        # 普通冷却器
│   │   ├── LosingStreakGuard.mqh # 连亏冷却器
│   │   ├── StructuralCooldown.mqh # 结构冷却器
│   │   ├── AccountRisk.mqh     # 账户风险控制
│   │   ├── PositionRisk.mqh    # 仓位风险控制
│   │   ├── TradeRisk.mqh       # 交易风险控制
│   │   ├── PositionSizer.mqh   # 仓位计算器
│   │   ├── AddPositionManager.mqh # 加仓管理器
│   │   ├── TimeStop.mqh        # 时间止损
│   │   └── RiskStatus.mqh      # 风控状态
│   └── UI/
│       └── StatusPanel.mqh     # 状态面板
├── Strategies/             # 策略实现
│   ├── Strategy_BollMR_Base.mqh
│   ├── Strategy_BollMR_RSI.mqh
│   ├── Strategy_BollMR_Time.mqh
│   ├── Strategy_BollMR_RSI_Time.mqh
│   ├── Strategy_BollMR_enhanced.mqh
│   ├── Strategy_TrendPullback.mqh
│   └── Strategy_Combo.mqh
├── Indicators/             # 指标模块
│   ├── Bollinger.mqh
│   └── ATR.mqh
└── Python/                 # Python 回测工具
```

### 核心模块职责

| 模块 | 职责 | 说明 |
|------|------|------|
| `Ea_run.mq5` | 主入口 | 初始化、事件处理、协调各模块 |
| `Signal` | 信号载体 | 策略产生的交易信号，包含方向、价格、ATR等上下文 |
| `StrategyManager` | 策略调度 | 遍历已注册策略，获取第一个有效信号 |
| `IStrategy` | 策略接口 | 定义 `GenerateSignal()` 方法，策略只负责信号生成 |
| `RiskPipeline` | 风控管道 | 统一管理所有风控检查，是风控的**唯一入口** |
| `TradeExecutor` | 交易执行 | 封装 MT5 交易 API，执行买卖操作 |
| `PositionCoordinator` | 持仓协调 | 单品种单向一仓管理 |

### 数据流向

```
┌─────────────────────────────────────────────────────────────────┐
│                         Ea_run.mq5                              │
│  (OnTick / OnTimer)                                            │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                     StrategyManager                             │
│  遍历策略 → GenerateSignal() → 返回 Signal                      │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Signal
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                      RiskPipeline                               │
│  BuildTrade(signal, req)                                        │
│  ├── AccountRisk: 日内亏损限制                                   │
│  ├── LosingStreakGuard: 连续止损冷却                             │
│  ├── Cooldown: 交易后普通冷却                                    │
│  ├── StructuralCooldown: 结构冷却（假突破保护）                   │
│  ├── PositionRisk: 持仓检查                                     │
│  ├── PositionSizer: 仓位计算                                    │
│  └── TradeRisk: SL/TP 验证                                      │
└───────────────────────────┬─────────────────────────────────────┘
                            │ TradeRequest
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                     TradeExecutor                               │
│  Execute(req) → 调用 MT5 API 下单                               │
└─────────────────────────────────────────────────────────────────┘
```

### 风控管道设计

**核心理念**：所有冷却逻辑由 `RiskPipeline` 统一管理，策略只负责信号生成。

```
RiskPipeline
├── 普通冷却器 (Cooldown)
│   └── 每笔交易后强制冷却 N 秒
├── 连亏冷却器 (LosingStreakGuard)
│   └── 连续止损 N 次后触发冷却
├── 结构冷却器 (StructuralCooldown)
│   ├── 快速止损触发（入场后 N 根 K 线内被止损）
│   ├── 无动量触发（未达 +M ATR 就反向）
│   ├── 连续失败触发（同方向连续 N 次 Probe 失败）
│   └── 二次确认机制（冷却解除后首次入场需更高质量）
├── 账户风险 (AccountRisk)
│   └── 日内最大亏损限制
├── 仓位风险 (PositionRisk)
│   └── 持仓数量/方向检查
└── 仓位计算 (PositionSizer)
    └── 基于风险比例计算手数
```

### 策略层设计

**策略接口**：
```cpp
class IStrategy {
public:
    virtual void GenerateSignal(Signal &sig) = 0;
    virtual void OnNewBar() {}
};
```

**策略只负责**：
1. 判断入场条件是否满足
2. 填充 `Signal` 结构体（type, price, sl, tp, atr, structure_price）
3. **不负责**冷却判断、仓位计算、风控检查

**当前策略族**：
| 策略 | 类型 | 说明 |
|------|------|------|
| `Strategy_BollMR_Base` | 均值回归 | BB + ATR 基线 |
| `Strategy_BollMR_RSI` | 均值回归 | + RSI 过滤 |
| `Strategy_BollMR_Time` | 均值回归 | + 时间过滤 |
| `Strategy_BollMR_RSI_Time` | 均值回归 | + RSI + 时间过滤 |
| `Strategy_BollMR_enhanced` | 均值回归 | 时间 + 趋势 + 分层退出 |
| `Strategy_TrendPullback` | 趋势跟踪 | M15 方向 + M5 回撤入场 |

### Signal 结构体

```cpp
struct Signal {
    SignalType type;        // BUY / SELL / EXIT / ADD_LONG / ADD_SHORT
    double confidence;      // 置信度 (0.0 ~ 1.0)
    string source;          // 策略来源
    datetime time;          // 信号时间
    double price;           // 触发价格
    double sl, tp;          // 止损止盈
    double exit_volume;     // 部分平仓手数
    double atr;             // ATR（用于结构冷却器）
    double structure_price; // 结构点价格（用于结构冷却器）
};
```

### 扩展指南

**新增策略**：
1. 继承 `IStrategy` 接口
2. 实现 `GenerateSignal(Signal &sig)`
3. 在 `Ea_run.mq5` 中注册到 `StrategyManager` 或 `Strategy_Combo`

**新增风控模块**：
1. 在 `Core/Risk/` 下创建新模块
2. 在 `RiskPipeline` 中集成
3. 在 `BuildTrade()` 中添加检查逻辑

**新增策略到组合**：
1. 创建新策略类继承 `IStrategy`
2. 在 `Ea_run.mq5` 中实例化策略
3. 在 combo 初始化时调用 `combo.AddStrategy(&new_strategy, "名称")`
4. 初始化新策略：`new_strategy.Init()`

### 多策略组合架构

**核心设计**：`Strategy_Combo` 采用策略列表模式，支持动态添加任意数量策略（最多 8 个）。

```
Strategy_Combo
├── m_strategies[]     // 策略数组
├── AddStrategy()      // 添加策略
└── GenerateSignal()   // 组合信号
```

**组合模式**：
| 模式 | 说明 |
|------|------|
| `COMBO_FIRST_SIGNAL` | 先到先得：取第一个有效信号 |
| `COMBO_SAME_DIRECTION` | 同向叠加：所有策略同向才交易 |
| `COMBO_MAJORITY_VOTE` | 多数投票：多数同向才交易 |
| `COMBO_PRIORITY_FIRST` | 优先级：按添加顺序优先 |
| `COMBO_CONFLICT_SKIP` | 冲突跳过：有反向信号时跳过（默认） |
| `COMBO_BEST_CONFIDENCE` | 最高置信度：选置信度最高的信号 |

**使用示例**（Ea_run.mq5）：
```cpp
combo.AddStrategy(&boll_enhanced, "BollMR");      // M1: 亚欧盘
combo.AddStrategy(&trend_pullback, "TrendPullback"); // M2: 欧美盘
// combo.AddStrategy(&xauusd_alpha, "XauusdAlpha");   // M3 (未来)
```

**各策略独立过滤条件**：
| 策略 | 时间过滤 | 说明 |
|------|----------|------|
| BollMR | 亚欧盘 | 均值回归适合震荡时段 |
| TrendPullback | 欧美盘 | 趋势跟踪适合趋势时段 |
| XauusdAlpha | 美盘 | 未来：结构策略 |

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
| TrendPullback.Cooldown | 结构冷却器参数 |
| TrendPullback.AddPosition | 加仓管理参数 |

### 结构冷却器（StructuralCooldown）

**唯一使命**：阻止"同一结构+同一段行情"被连续假突破反复收割。

```
核心理念：市场骗过你一次，在给出更高质量证据前不再相信
```

#### 触发条件

| 条件 | 描述 | 说明 |
|------|------|------|
| 快速止损 | 入场后3根K线内被止损 | 100%假突破 |
| 无动量 | 未达+0.5 ATR就反向 | 缺乏真实需求 |
| 连续失败 | 同方向连续2次Probe失败 | 结构质量极差 |

#### 冷却期间

**禁止**：新的 Probe、Main、同方向任何入场
**允许**：结构更新、记录新高/新低、计算新的 Pullback

#### 解除条件

```
解除 = 时间条件 + 结构条件（二选一）
```

- **时间条件**：5根K线走完
- **结构条件A**：形成新Pullback结构（回撤更浅 或 突破点更优）
- **结构条件B**：价格拉开 ≥ 1 ATR（脱离假突破区域）

#### 二次确认

冷却解除后，只允许"更高质量"的入场：

| 方案 | 条件 |
|------|------|
| 方案1（结构） | 突破点 > 上一次假突破点 |
| 方案2（动量） | 突破后1-2根K线推进 ≥ 0.5 ATR |
| 方案3（撤回） | 回撤深度 < 上一次回撤深度 |

```
TrendPullback.Cooldown:
- TP_EnableCooldown        = true    // 启用冷却器
- TP_CooldownBars          = 5       // 冷却K线数
- TP_FastFailBars          = 3       // 快速失败判定
- TP_MinMomentumATR        = 0.5     // 最小动量要求
- TP_StructureUpgradeATR   = 1.0     // 结构升级距离
```

### 加仓管理器（AddPositionManager）

**核心原则**：不是"价格涨了我加"，而是"市场第二次证明我是对的，我才敢更重"

#### 三条铁律

1. 不在浮亏时加仓
2. 不在第一次突破后立即加仓
3. 冷却器激活时禁止加仓

#### 加仓条件（必须全部满足）

| 条件 | 要求 |
|------|------|
| 主仓验证 | 已达TP1（≥+1.5 ATR）+ 已部分止盈 + SL≥BE |
| 趋势加速 | 第二次回撤失败（趋势从"成立"到"加速"） |
| 冷却器 | 未激活 |
| 风险上限 | 总风险 ≤ 2.5R |

#### 加仓结构

| 加仓 | 触发条件 | 比例 |
|------|----------|------|
| 加仓#1 | 第二次回撤失败 | 主仓的40% |
| 加仓#2 | 连续推进 ≥ 2 ATR | 主仓的25% |
| 加仓#3 | ❌ 禁止 | — |

#### 独立止损

```
加仓单止损 = 最近回撤结构点
❌ 不与主仓共用一个SL
→ 永远不会因一次加仓把整个趋势单炸掉
```

```
TrendPullback.AddPosition:
- TP_EnableAddPosition = true   // 启用加仓
- TP_Add1_Ratio        = 0.4    // 第一次加仓比例
- TP_Add2_Ratio        = 0.25   // 第二次加仓比例
- TP_Add2_ProfitATR    = 2.0    // 第二次加仓盈利要求
- TP_MaxTotalRisk      = 2.5    // 最大总风险(R倍数)
```

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

