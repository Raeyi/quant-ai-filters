# quant-ai-filters

## 概览

- 目标：XAUUSD 小周期策略的可插拔体系（MQL5 实盘 + Python 回测/研究）
- 结构：**Regime 引擎 + 策略选择器 + 策略族 + 风控层**
- 版本：v2.2.0

## 开发路线

```
Phase 1: 基础架构 ✅
├── M1: 策略框架           → v2.0.0
└── M2: 风控管道           → v2.1.0

Phase 2: 策略开发 ✅
├── M3: Mean Reversion     → v2.1.0
└── M4: Trend Pullback     → v2.1.0

Phase 3: Regime 引擎 ✅
└── M5: Regime Filter      → v2.2.0

Phase 4: AI 增强 🔄
├── M6: 参数优化 + 数据收集  → v2.3.0 ← 当前
├── M7: ML 参数优化         → v2.3.0
└── M8: RL 状态决策         → v2.4.0

Phase 5: 策略扩展 ⏳
└── M9: XAUUSD Alpha        → v2.5.0
```

### 分支策略

```
main
├── release/v2.0.0          # Phase 1 完成
├── release/v2.1.0          # Phase 2 完成
├── release/v2.2.0          # Phase 3 完成 ← 当前稳定版
├── release/v2.3.0          # Phase 4 M6+M7
└── release/v2.4.0          # Phase 4 M8

开发分支：
├── feature/m6-param-optimization   # M6 开发 ← 当前
├── feature/m7-ml-optimization      # M7 开发
└── feature/m8-rl-decision          # M8 开发
```

## 系统架构

### Alpha 核心来源

> 市场不奖励"正确的结构"，市场只奖励"结构中被忽略的偏差"

| Alpha 来源 | 说明 |
|------------|------|
| **Market Quality Score** | 决定"何时不用策略"，Q<阈值 → STANDBY |
| **Regime Sub-Type** | 区分"真趋势"vs"情绪脉冲" |
| **Transition Matrix** | 提前布局下一状态 |
| **时间 × Regime** | 同一 Regime 不同时段权重不同 |
| **风险暴露结构** | Sub-Type → 不同止损/仓位参数 |

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

### Q-Score 计算

**公式**：基于基准值的动态评分

```
Q = 0.5 + eff_score + fbr_score

eff_score = 0.25 × (efficiency / baseline_eff - 1)
fbr_score = 0.25 × (baseline_fbr - fbr) / baseline_fbr
```

**基准值**：
- `MQ_Efficiency_Baseline = 0.15`（震荡市正常效率）
- `MQ_FBR_Baseline = 0.50`（震荡市正常假突破率）

**效果**：
- 效率高于基准 → 加分
- 假突破率低于基准 → 加分
- Q 范围：0.1 ~ 0.9

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
└── Python/                 # Python 回测工具
    └── regime/             # Regime Filter Python 模块
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
StrategyRegistry.UpdateIndicators()
    ↓
CRegimeFilter.Update() → Q_score → State
    ↓ (ACTIVE)
StrategyManager.GetSignal() → Signal
    ↓
RiskPipeline.BuildTrade() → TradeRequest
    ↓
TradeExecutor.Execute() → MT5 API
```

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

## M6-M8: AI 增强设计

### M6: 参数优化 + 数据收集

**目标**：优化参数配置 + 建立数据收集管道

| 步骤 | 任务 | 输出 |
|------|------|------|
| M6.1 | Q-Score 阈值调优 | 最优阈值参数 |
| M6.2 | 参数网格搜索 | 最优策略参数组合 |
| M6.3 | Walk-Forward 验证 | 参数稳定性报告 |
| M6.4 | 数据收集器实现 | 特征数据集 CSV |
| M6.5 | 数据 Schema 定义 | ai_data_schema.md |

**数据收集设计**：

```python
features = {
    # 市场特征
    "efficiency": float,
    "false_breakout_rate": float,
    "adx": float,
    "atr": float,
    "volatility_state": int,
    "trend_strength": float,
    
    # Regime 状态
    "regime_state": int,
    "regime_type": int,
    "sub_type": int,
    "q_score": float,
    
    # 时间特征
    "hour": int,
    "day_of_week": int,
    "session": int,
    
    # 决策与结果
    "signal": int,
    "position_size": float,
    "sl_mult": float,
    "tp_mult": float,
    "pnl": float,
    "holding_bars": int,
    "win": bool
}
```

### M7: ML 参数优化

**目标**：用监督学习优化 Q-Score 权重和阈值

| 步骤 | 任务 | 工具 |
|------|------|------|
| M7.1 | 特征工程 | pandas, sklearn |
| M7.2 | 标签生成 | 自定义脚本 |
| M7.3 | 模型训练 | XGBoost / LightGBM |
| M7.4 | 特征重要性 | SHAP |
| M7.5 | 参数导出 | 代码生成脚本 |

### M8: RL 状态决策

**目标**：用强化学习动态调整 Regime 参数

```python
class RegimeTradingEnv(gym.Env):
    observation_space = Dict({
        "efficiency": Box(0, 1),
        "false_breakout_rate": Box(0, 1),
        "adx": Box(0, 100),
    })
    
    action_space = Dict({
        "q_score_weight_eff": Box(0, 1),
        "standby_threshold": Box(0.3, 0.7),
    })
    
    def reward(self):
        return sharpe_ratio - max_drawdown_penalty
```

## 参数配置

### Regime Filter 参数

```
Regime Filter 设置:
├── RF_Q_Score_Standby = 0.35  # STANDBY 阈值（建议调低）
├── RF_Q_Score_Active = 0.45   # ACTIVE 阈值（建议调低）
├── RF_Transition_Bars = 3     # 过渡期 K 线数
├── RF_Hysteresis = 0.05       # 滞后阈值
└── RF_Enable_SubType = true   # 启用 Sub-Type

市场质量设置:
├── MQ_Efficiency_Period = 20
├── MQ_Efficiency_Baseline = 0.15
├── MQ_FBR_Baseline = 0.50
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
python regime/validate_regime.py --data /path/to/XAUUSD_M5.csv
```

## 版本历史

| 版本 | 里程碑 | 说明 |
|------|--------|------|
| v2.2.0 | M5 | Regime Filter + StrategyRegistry + Q-Score优化 |
| v2.1.0 | M3-M4 | Mean Reversion + TrendPullback 策略族 |
| v2.0.0 | M1-M2 | 策略框架 + 风控管道 |
