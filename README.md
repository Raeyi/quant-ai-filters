# quant-ai-filters

## 概览

- 目标：XAUUSD 小周期策略的可插拔体系（MQL5 实盘 + Python 回测/研究）
- 结构：**Regime 引擎 + 策略选择器 + 策略族 + 风控层**
- 版本：v2.4.0

### 架构：职业化过滤标准

**设计原则**：

1. **单一职责**：每层只做一件事
2. **状态统一**：RegimeFilter 是唯一状态来源
3. **策略简化**：策略只做入场条件判断

信号流程（优化后 - 清晰）：
┌──────────────────────────────────────────────────────────────────┐
│ Layer 1: RegimeFilter (全局状态)                                  │
│   ├─ Q-Score 计算 (eff + fbr + adx)                              │
│   ├─ 趋势状态 (TREND/RANGE)                                       │
│   ├─ 波动率状态 (LOW/NORMAL/HIGH)                                 │
│   └─ 输出：state, sub_type, q_score, direction                   │
└──────────────────────────────────────────────────────────────────┘
                              ↓ IsTradable()?
┌──────────────────────────────────────────────────────────────────┐
│ Layer 2: Global Filters (全局过滤)                                │
│   ├─ TimeFilter (时段/流动性)                                     │
│   ├─ NewsFilter (新闻事件)                                        │
│   └─ SpreadFilter (点差检查)                                      │
└──────────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────────┐
│ Layer 3: Strategy (策略入场)                                      │
│   ├─ BollMR: 只判断 BB 回归确认                                   │
│   ├─ TrendPullback: 只判断回撤结构                                │
│   └─ 不再重复判断：趋势、波动率、时间                              │
└──────────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────────┐
│ Layer 4: Risk Pipeline (风控)                                     │
│   ├─ 仓位计算 (基于 sub_type)                                     │
│   ├─ 止损设置                                                     │
│   └─ 冷却检查                                                     │
└──────────────────────────────────────────────────────────────────┘
```

---

### XAUUSD 职业化过滤标准

```
黄金市场过滤层次：

Layer 1: 市场状态（全局）
├── Q-Score > 0.35（市场质量达标）
├── ADX 状态（趋势/震荡判断）
└── 波动率状态（低/正常/高）

Layer 2: 时间过滤（全局）
├── 活跃时段（伦敦开盘 15:00、纽约开盘 20:00 北京时间）
├── 避开低流动性（亚洲深夜 00:00-06:00 北京时间）
└── 重大新闻前后 30 分钟（NFP/FOMC）

Layer 3: 策略入场（局部）
├── 策略特定条件（不再重复判断趋势/波动）
└── 信号确认（K线形态、结构突破）

Layer 4: 风控
├── Sub-Type → 仓位 scale
├── Sub-Type → 止损 multiplier
└── 冷却期
```

**黄金时段权重**：

| 时段 | 北京时间 | 权重 | 特点 |
|------|----------|------|------|
| 亚盘 | 08:00-15:00 | 0.7 | 波动小，震荡为主 |
| 欧盘 | 15:00-20:00 | 1.0 | 主要波动时段 |
| 美盘 | 20:00-24:00 | 1.2 | 最高波动，趋势机会 |
| 重叠 | 20:00-24:00 | 1.5 | 欧+美重叠，最佳时机 |
| 深夜 | 00:00-08:00 | 0.3 | 低流动性，避开 |

---

### Alpha 核心来源

> 市场不奖励"正确的结构"，市场只奖励"结构中被忽略的偏差"

| Alpha 来源 | 说明 |
|------------|------|
| **Market Quality Score** | 决定"何时不用策略"，Q<阈值 → STANDBY |
| **Regime Sub-Type** | 区分"真趋势"vs"情绪脉冲" |
| **Transition Matrix** | 提前布局下一状态 |
| **时间 × Regime** | 同一 Regime 不同时段权重不同 |
| **风险暴露结构** | Sub-Type → 不同止损/仓位参数 |

---

### Regime 状态机

```
┌─────────────────────────────────────────────────────────────┐
│                   Regime Filter 状态机                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│    Q_score > Active阈值 + hysteresis                        │
│    ┌──────────────────────────────────────┐                │
│    │                                      │                │
│    ▼                                      │                │
│ ┌────────┐  Q < Standby阈值 - hysteresis  ┌───────────┐   │
│ │ ACTIVE │ ──────────────────────────────▶│  STANDBY  │   │
│ └────────┘                                └───────────┘   │
│    ▲                                            │          │
│    │         ┌─────────────┐                    │          │
│    └─────────│ TRANSITION  │◀───────────────────┘          │
│              └─────────────┘  连续确认 N bars               │
│                                                             │
│  STANDBY 时：禁止新开仓信号                                   │
│  ACTIVE 时：允许所有交易信号                                   │
└─────────────────────────────────────────────────────────────┘
```

### Sub-Type 分类

| Sub-Type | Regime | Volatility | 特征 | 建议 |
|----------|--------|------------|------|------|
| T+V-B (真趋势) | TREND | HIGH | 高效率 + 高波动 | scale=1.2, 重仓机会 |
| T+V-A (情绪脉冲) | TREND | HIGH | 低效率 + 高波动 | scale=0.5, 轻仓 |
| T+N (温和趋势) | TREND | NORMAL | 稳步趋势 | scale=0.8 |
| R+V-A (消息震荡) | RANGE | HIGH | 高反转率 | **STANDBY** |
| R+V-B (假突破密集) | RANGE | HIGH | 高假突破率 | scale=0.5, 等待确认 |
| R+N (正常震荡) | RANGE | NORMAL | 区间稳定 | scale=1.0 |
| R+L (低波动震荡) | RANGE | LOW | 波动极低 | scale=0.3 |

---

## Q-Score 计算

### 当前公式（v2.3.0）

**三维度评分**：

```
Q = 0.5 + eff_score + fbr_score + adx_score

eff_score = w_eff × (efficiency / baseline_eff - 1)
fbr_score = w_fbr × (baseline_fbr - fbr) / baseline_fbr
adx_score = w_adx × max(0, (adx - baseline_adx) / 25)
```

**当前参数**：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `w_eff` | 0.25 | 效率权重 |
| `w_fbr` | 0.25 | 假突破率权重 |
| `w_adx` | 0.20 | ADX 权重 |
| `baseline_eff` | 0.10 | 效率基准值 |
| `baseline_fbr` | 0.40 | 假突破率基准值 |
| `baseline_adx` | 25.0 | ADX 基准值（趋势分界线） |

**设计依据**：

| 设计点 | 说明 | 问题 |
|--------|------|------|
| 基准值 0.5 | 中性起点 | ✅ 合理 |
| 权重参数 | 三个因子各自贡献 | ⚠️ 需要优化 |
| 基准值来源 | 回测数据观察 | ⚠️ 可能不稳定 |
| 三维度 | eff + fbr + adx | ✅ 信息更全面 |
| 线性关系 | 线性贡献 | ⚠️ 可能非线性 |

### 优化路径

**Phase 1: 特征扩展（已完成）**

新增 ADX 维度：
- adx_score: 趋势强度贡献
- ADX > 25 时加分，最高贡献 0.20

**Phase 2: 参数网格搜索**

```bash
# 运行参数优化
cd Python
python regime_param_optimize.py \
  --data "E:/mt5_test_datas/mt5/XAUUSD_M5.csv" \
  --output data/regime_optimize_results.csv \
  --quick  # 快速模式
```

**Phase 3: ML 权重优化**

使用监督学习学习最优权重：

```python
# 目标：最大化 Sharpe / 胜率
# 特征：[eff, fbr, adx, atr_ratio, ...]
# 标签：未来 N 根 K 线的胜率/盈亏比
# 模型：线性回归 / XGBoost
```

**Phase 4: 动态基准（RL）**

基准值根据市场环境动态调整：

```python
baseline_eff = f(volatility_state, session)
baseline_fbr = f(volatility_state, session)
```

---
## 代码架构

### 目录结构

```
quant-ai-filters/
├── Ea_run.mq5              # EA 主入口
├── Core/
│   ├── Signal.mqh          # 信号结构体
│   ├── TradeTypes.mqh      # 交易类型枚举
│   ├── TradeExecutor.mqh   # 交易执行器
│   ├── Strategy.mqh        # 策略接口
│   ├── StrategyManager.mqh # 策略调度器
│   ├── StrategyRegistry.mqh # 策略注册表
│   ├── PositionCoordinator.mqh # 持仓协调器
│   ├── Inputs_All.mqh      # 统一输入参数
│   ├── Regime/             # Regime Filter 模块
│   │   ├── RegimeTypes.mqh
│   │   ├── RegimeIndicators.mqh
│   │   ├── MarketQuality.mqh
│   │   └── RegimeFilter.mqh
│   ├── Risk/               # 风控子模块
│   │   ├── RiskPipeline.mqh
│   │   ├── StructuralCooldown.mqh
│   │   ├── AddPositionManager.mqh
│   │   └── ...
│   └── UI/
│       └── StatusPanel.mqh
├── Strategies/             # 策略实现
│   ├── Strategy_BollMR_enhanced.mqh
│   ├── Strategy_BollMR_Base.mqh
│   ├── Strategy_TrendPullback.mqh
│   └── Strategy_Combo.mqh
├── Indicators/             # 指标模块
│   ├── Bollinger.mqh
│   └── ATR.mqh
├── Python/                 # Python 回测工具
│   ├── regime_param_optimize.py  # 参数网格搜索
│   ├── data_collector.py         # 数据收集器
│   └── regime/             # Regime Filter Python 模块
└── docs/
    └── ai_data_schema.md   # 数据 Schema
```

### 核心模块职责

| 模块 | 职责 | 说明 |
|------|------|------|
| `Ea_run.mq5` | 主入口 | 初始化、事件处理、协调各模块 |
| `StrategyRegistry` | 策略管理 | 统一注册、选择、初始化、更新策略 |
| `CRegimeFilter` | 市场状态过滤 | Q_score 计算，STANDBY 时拒绝开仓 |
| `StrategyManager` | 策略调度 | 获取策略信号 |
| `RiskPipeline` | 风控管道 | 统一管理所有风控检查 |
| `TradeExecutor` | 交易执行 | 封装 MT5 交易 API |

### 数据流向

```
Ea_run.mq5 (OnTick)
    ↓
    ↓
ManagePositionExitOnTick(signal); 
    ↓
    ↓
CRegimeFilter.Update()
    ↓ → Q_score, State, Direction, Volatility
    ↓
Global Filters (Time, Spread, News)
    ↓ IsTradable()?
StrategyManager.GetSignal()
    ↓ 策略只做入场条件判断
RiskPipeline.BuildTrade()
    ↓ 基于 Sub-Type 调整仓位/止损
TradeExecutor.Execute()
```

---

## 策略族

### M3: Mean Reversion Family (v2.1.0)

| 策略 | 说明 |
|------|------|
| `Strategy_BollMR_Base` | BB + ATR 基线 |
| `Strategy_BollMR_RSI` | + RSI 过滤 |
| `Strategy_BollMR_Time` | + 时间过滤 |
| `Strategy_BollMR_RSI_Time` | + RSI + 时间过滤 |
| `Strategy_BollMR_enhanced` | 时间 + 趋势 + 分层退出 |

### M4: Trend Pullback Family (v2.1.0)

| 组件 | 说明 |
|------|------|
| M15 方向判断 | EMA50/EMA200 + VWAP |
| M5 回撤入场 | 价值区 + 结构确认 |
| 四层出场 | L1防御 → L2最小兑现 → L3趋势持有 → L4时间止盈 |
| 结构冷却器 | 假突破保护 |
| 加仓管理器 | 趋势验证后加仓 |

### 组合策略 (Strategy_Combo)

| 模式 | 说明 |
|------|------|
| `COMBO_FIRST_SIGNAL` | 先到先得 |
| `COMBO_SAME_DIRECTION` | 所有策略同向才交易 |
| `COMBO_MAJORITY_VOTE` | 多数投票 |
| `COMBO_PRIORITY_FIRST` | 按添加顺序优先 |
| `COMBO_CONFLICT_SKIP` | 有反向信号时跳过（默认） |
| `COMBO_BEST_CONFIDENCE` | 选择置信度最高的信号 |

---

## M9: Donchian 突破 + 波动过滤策略

> 美盘强化版：在美盘高波动时段捕捉趋势突破

### 核心思想

在美盘高波动时段，等待价格突破近期区间（Donchian通道），同时确认趋势方向（均线同向）和波动率支持（ATR/布林带扩张），顺势入场。

### 时间过滤

| 时段 | 北京时间 | 策略模式 | 说明 |
|------|----------|----------|------|
| **美盘** | 20:30-23:30 | 完全信任 | 高胜率基础模式，完全信任规则 |
| 欧盘 | 15:00-20:30 | 观察模式 | 15分钟均线排列确认后轻仓介入 |
| 亚盘 | 其他 | 试错模式 | 降低预期，快速止盈或减仓 |

### 技术指标

| 指标 | 参数 | 用途 |
|------|------|------|
| **Donchian通道** | 周期20 | 突破信号识别 |
| **ATR(14)** | 14 | 波动率衡量 + 止损设置 |
| **EMA55** | 55 | 中期趋势方向 |
| **EMA144** | 144 | 长期趋势方向 |
| RSI(14) | 14 | 可选：过滤弱势行情（RSI>55做多） |
| 布林带 | 20,2 | 可选：波动率扩张判断 |

### 过滤条件

**波动状态过滤**（满足任一即可）：
```
条件1: ATR扩张
  当前ATR(14) > ATR(14)的N日均值 (N=30或50)

条件2: 布林带扩张
  BB宽度(上轨-下轨)快速扩张
```

**方向确认**：
```
多头确认:
  - 价格 > EMA55 > EMA144 (同向排列)
  - EMA55斜率 > 0 (均线向上)

空头确认:
  - 价格 < EMA55 < EMA144 (同向排列)
  - EMA55斜率 < 0 (均线向下)
```

### 入场条件

**多头信号**：
```
Alpha因子 = 1 
          × (收盘价 > Donchian上轨)        // 突破确认
          × (ATR扩张 OR 布林带扩张)         // 波动率支持
          × (价格>EMA55>EMA144)            // 趋势同向
          × (EMA55斜率 > 0)                // 趋势向上
          × (RSI>55)                       // 可选：动量确认
```

**空头信号**：反之亦然

### 止损与出场

| 类型 | 设置方式 | 说明 |
|------|----------|------|
| **初始止损** | 入场价 - (1.5~2) × ATR | 根据波动性调整 |
| **止盈目标** | 风险 × (2.2~2.6) | 固定盈亏比 |
| **移动止损** | 5分钟Donchian下轨拖尾 | 不破轨就持有 |
| **时间出场** | 超过23:30收紧止损 | 流动性降低前离场 |

### 策略优势

1. **时段聚焦**：只在高胜率时段交易，避开低效时段
2. **多维度确认**：突破 + 趋势 + 波动三重过滤
3. **动态止损**：ATR自适应，波动大时止损宽，波动小时止损紧
4. **趋势跟随**：Donchian拖尾止损，吃到整段趋势

### Alpha 因子公式

```
信号 = Donchian突破 × 波动率扩张 × 趋势确认 × 斜率确认
```

### M7: XAUUSD 职业化过滤

#### 7.1 黄金市场特点

| 特点 | 说明 | 过滤策略 |
|------|------|----------|
| 时段特性 | 伦敦/纽约时段波动大 | 时间权重过滤 |
| 避险属性 | 风险事件时波动剧增 | 新闻事件过滤 |
| 流动性 | 期货/现货联动 | 点差/成交量过滤 |

#### 7.2 职业化过滤实现

| 任务 | 状态 | 说明 |
|------|------|------|
| M7.3.1 | ⏳ | XAUUSD 时段过滤器 |
| M7.3.2 | ⏳ | 新闻事件过滤器（NFP/FOMC） |
| M7.3.3 | ⏳ | 流动性过滤器（点差/成交量） |
| M7.3.4 | ⏳ | 统一过滤层入口（FilterPipeline） |

---

### M8: AI 参数优化

#### 8.1 参数网格搜索

```bash
# 完整优化
python Python/regime_param_optimize.py \
  --data "E:/mt5_test_datas/mt5/XAUUSD_M5.csv" \
  --output data/regime_optimize_results.csv

# 快速模式
python Python/regime_param_optimize.py \
  --data "E:/mt5_test_datas/mt5/XAUUSD_M5.csv" \
  --quick
```

#### 8.2 数据收集

```bash
python Python/data_collector.py \
  --data "E:/mt5_test_datas/mt5/XAUUSD_M5.csv" \
  --output data/features_train.csv \
  --label
```

#### 8.3 ML 参数优化

```python
# 特征 → Q-Score 权重
model = XGBRegressor(
    objective='reg:squarederror',
    n_estimators=100,
    max_depth=5,
)

model.fit(X_train, y_train)
importance = model.feature_importances_
```

## 快速开始

### MQL5

1. MT5 数据目录 → `MQL5/Experts` 放入项目
2. 编译 `Ea_run.mq5`
3. 图表加载 EA，调整参数

### Python 回测

```bash
cd Python
pip install -r requirements.txt

# Regime 参数优化
python regime_param_optimize.py --data /path/to/XAUUSD_M5.csv

# 数据收集
python data_collector.py --data /path/to/XAUUSD_M5.csv --label
```

---

## 版本历史

| 版本 | 里程碑 | 说明 |
|------|--------|------|
| v2.3.0 | M6 | 架构清理 + ADX 维度 |
| v2.2.0 | M5 | Regime Filter + StrategyRegistry + Q-Score优化 |
| v2.1.0 | M3-M4 | Mean Reversion + TrendPullback 策略族 |
| v2.0.0 | M1-M2 | 策略框架 + 风控管道 |
