# quant-ai-filters

## 概览

- 目标：XAUUSD 小周期策略的可插拔体系（MQL5 实盘 + Python 回测/研究）
- 结构：**Regime 引擎 + 策略选择器 + 策略族 + 风控层**
- 版本：v2.2.0-development

## 系统架构

### Alpha 核心来源

> 市场不奖励"正确的结构"，市场只奖励"结构中被忽略的偏差"

|| Alpha 来源 | 说明 |
||------------|------|
|| **Market Quality Score** | 决定"何时不用策略"，Q<0.5 → STANDBY |
|| **Regime Sub-Type** | 区分"真趋势"vs"情绪脉冲" |
|| **Transition Matrix** | 提前布局下一状态 |
|| **时间 × Regime** | 同一 Regime 不同时段权重不同 |
|| **风险暴露结构** | Sub-Type → 不同止损/仓位参数 |

### Regime 状态机

```
┌─────────────────────────────────────────────────────────────┐
│                   Regime Filter 状态机                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│    Q_score > 0.6 + hysteresis                              │
│    ┌──────────────────────────────────────┐                │
│    │                                      │                │
│    ▼                                      │                │
│ ┌────────┐  Q < 0.5 - hysteresis  ┌───────────┐           │
│ │ ACTIVE │ ──────────────────────▶│  STANDBY  │           │
│ └────────┘                        └───────────┘           │
│    ▲                                      │                │
│    │         ┌─────────────┐              │                │
│    └─────────│ TRANSITION  │◀─────────────┘                │
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

## 代码架构

### 目录结构

```
quant-ai-filters/
├── Ea_run.mq5              # EA 主入口
├── Core/
│   ├── Signal.mqh          # 信号结构体
│   ├── TradeTypes.mqh      # 交易类型枚举
│   ├── TradeExecutor.mqh   # 交易执行器
│   ├── Strategy.mqh        # 策略接口（含 Init/UpdateIndicators/TimeFilterOK）
│   ├── StrategyManager.mqh # 策略调度器
│   ├── StrategyRegistry.mqh # 策略注册表（统一生命周期管理）【新增】
│   ├── PositionCoordinator.mqh # 持仓协调器
│   ├── Inputs_All.mqh      # 统一输入参数
│   ├── Regime/             # Regime Filter 模块【新增】
│   │   ├── RegimeTypes.mqh     # 类型定义 + 辅助函数
│   │   ├── RegimeIndicators.mqh # ADX/ATR 指标
│   │   ├── MarketQuality.mqh   # Q_score 计算
│   │   └── RegimeFilter.mqh    # 主过滤类
│   ├── Risk/               # 风控子模块
│   │   ├── RiskPipeline.mqh    # 风控管道（统一入口）
│   │   ├── StructuralCooldown.mqh # 结构冷却器
│   │   ├── AddPositionManager.mqh # 加仓管理器
│   │   └── ...
│   └── UI/
│       └── StatusPanel.mqh     # 状态面板（含 Regime 显示）
├── Strategies/             # 策略实现
│   ├── Strategy_BollMR_enhanced.mqh
│   ├── Strategy_BollMR_Base.mqh
│   ├── Strategy_TrendPullback.mqh
│   └── Strategy_Combo.mqh
├── Indicators/             # 指标模块
│   ├── Bollinger.mqh
│   └── ATR.mqh
└── Python/                 # Python 回测工具
    └── regime/             # Regime Filter Python 模块【新增】
        ├── regime_indicators.py
        ├── regime_filter.py
        ├── regime_subtype.py
        ├── strategy_selector.py
        ├── transition_matrix.py
        ├── risk_exposure.py
        ├── backtest_with_regime.py
        └── validate_regime.py
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
┌─────────────────────────────────────────────────────────────────┐
│                         Ea_run.mq5                              │
│                      OnTick / OnTimer                           │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                     StrategyRegistry                            │
│  registry.UpdateIndicators() → 统一更新所有策略指标               │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                     CRegimeFilter                               │
│  Update(close, high, low) → Q_score → State (ACTIVE/STANDBY)   │
│  STANDBY 时：拒绝新开仓信号                                       │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                   StrategyManager                               │
│  GetSignal() → Signal                                          │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Signal
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                      RiskPipeline                               │
│  BuildTrade(signal, req)                                       │
│  ├── AccountRisk: 日内亏损限制                                   │
│  ├── LosingStreakGuard: 连续止损冷却                             │
│  ├── StructuralCooldown: 结构冷却                               │
│  ├── PositionSizer: 仓位计算                                    │
│  └── TradeRisk: SL/TP 验证                                      │
└───────────────────────────┬─────────────────────────────────────┘
                            │ TradeRequest
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                     TradeExecutor                               │
│  Execute(req) → MT5 API                                        │
└─────────────────────────────────────────────────────────────────┘
```

### StatusPanel 显示

面板新增 Regime 状态行：
```
Regime: STANDBY [T+V-A] Q=0.42
```
- 状态：ACTIVE / STANDBY / TRANSITION
- Sub-Type：T+V-B / T+V-A / R+N 等
- Q_score：市场质量分数

## 扩展指南

### 新增策略（使用 StrategyRegistry）

```mql5
// 1. 创建策略类（继承 IStrategy）
class Strategy_New : public IStrategy {
public:
    virtual bool Init() override { ... }
    virtual bool UpdateIndicators() override { ... }
    virtual bool TimeFilterOK() override { ... }
    virtual Signal GenerateSignal(Signal &out) override { ... }
};

// 2. 在 Ea_run.mq5 中注册（OnInit）
Strategy_New new_strategy;

// 注册策略
registry.Register("new_strategy", &new_strategy);

// 如果是组合策略的子策略
registry.Register("new_strategy_child", &new_strategy, true);
combo.AddStrategy(&new_strategy, "NewStrategy");

// 3. 选择策略变体
registry.Select("new_strategy");  // 或在参数中选择
```

**无需修改 OnTick 中的指标更新逻辑**，`registry.UpdateIndicators()` 会自动处理。

### 新增 Regime Sub-Type

在 `RegimeFilter.mqh` 的 `ClassifySubType()` 中添加新分类规则：

```mql5
RegimeSubType ClassifySubType() {
    // 添加新的判断条件
    if (new_condition)
        return SUBTYPE_NEW_TYPE;
    // ...
}
```

### 新增风控模块

1. 在 `Core/Risk/` 下创建新模块
2. 在 `RiskPipeline` 中集成
3. 在 `BuildTrade()` 中添加检查逻辑

## Regime Filter 参数

```
Regime Filter 设置:
├── RF_Q_Score_Standby = 0.5    # STANDBY 阈值
├── RF_Q_Score_Active = 0.6     # ACTIVE 阈值
├── RF_Transition_Bars = 3      # 过渡期 K 线数
├── RF_Hysteresis = 0.05        # 滞后阈值（防止频繁切换）
└── RF_Enable_SubType = true    # 启用 Sub-Type 分类
```

## 策略族

### M1: Mean Reversion Family

| 策略 | 说明 |
|------|------|
| `Strategy_BollMR_Base` | BB + ATR 基线 |
| `Strategy_BollMR_RSI` | + RSI 过滤 |
| `Strategy_BollMR_Time` | + 时间过滤 |
| `Strategy_BollMR_RSI_Time` | + RSI + 时间过滤 |
| `Strategy_BollMR_enhanced` | 时间 + 趋势 + 分层退出 |

### M2: Trend Pullback Family

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

## 快速开始

### MQL5

1. MT5 数据目录 → `MQL5/Experts` 放入项目
2. 编译 `Ea_run.mq5`
3. 图表加载 EA，调整参数：
   - `BollMRVariant`: 选择策略变体
   - Regime Filter 参数（可选）

### Python 回测

```bash
cd Python
python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt

# Regime 验证
python regime/validate_regime.py --data /path/to/XAUUSD_M5.csv
```

## 信号文件格式

`signals_mt5.csv` 输出：
```
time,signal,event,source,regime
2025.01.30 15:00:00,1,1,BollMR,ACTIVE||Q0.72
2025.01.30 15:05:00,0,,,STANDBY|T+V-A|Q0.42
```

regime 列格式：`状态|Sub-Type|Q_score`

## 参数优化关键发现

基于 XAUUSD M5 数据参数扫描：

| 参数 | 优化值 | 说明 |
|------|--------|------|
| boll_dev | 2.5 | 更宽布林带过滤假信号 |
| atr_vol_limit | 1.2 | 更严格波动率过滤 |
| boll_period | 15-20 | 最佳范围 |
| atr_period | 10 | 较短周期反应更快 |

## Web UI

```bash
scripts\start_web_ui.cmd
# 浏览器打开 http://127.0.0.1:8787
```

功能：
- 修改配置参数
- 上传 CSV 运行回测
- 查看回测结果
- 导出策略参数

## 版本历史

### v2.2.0-development
- 新增 Regime Filter（Python + MQL5）
- 新增 StrategyRegistry 统一策略管理
- 重构 Ea_run.mq5（减少约100行硬编码）
- StatusPanel 新增 Regime 状态显示
- 信号文件新增 regime 列

### v2.1.x
- M1/M2 策略族完整实现
- 风控管道完善
- 结构冷却器 + 加仓管理器
