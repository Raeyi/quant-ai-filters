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

---

## Q-Score 计算

### 当前公式（v2.2.0）

**基于基准值的相对评分**：

```
Q = 0.5 + eff_score + fbr_score

eff_score = w1 × (efficiency / baseline_eff - 1)
fbr_score = w2 × (baseline_fbr - fbr) / baseline_fbr
```

**当前参数**：
- `w1 = w2 = 0.25`（权重）
- `baseline_eff = 0.15`（效率基准）
- `baseline_fbr = 0.50`（假突破率基准）

**设计依据**：

| 设计点 | 说明 | 问题 |
|--------|------|------|
| 基准值 0.5 | 中性起点 | ✅ 合理 |
| 权重 0.25 | 两个因子各贡献 ±0.25 | ⚠️ 未经验证 |
| 基准值来源 | 回测数据观察 | ⚠️ 可能不稳定 |
| 仅 2 维度 | eff + fbr | ⚠️ 信息不足 |
| 线性关系 | 线性贡献 | ⚠️ 可能非线性 |

### 优化路径

**Phase 1: 特征扩展**

新增维度：

| 维度 | 计算方式 | 价值 | 优先级 |
|------|----------|------|--------|
| **adx_score** | ADX / 50 - 1 | 趋势强度 | 高 |
| **atr_ratio** | ATR / MA(ATR, 20) | 波动率异常 | 高 |
| **session_weight** | 按时段调整基准 | 时段差异 | 中 |
| **volume_ratio** | Volume / MA(Volume) | 流动性 | 中 |
| **momentum_persist** | 连续同向K线比例 | 动量持续 | 低 |

**扩展后公式**：

```
Q = w0 + w1×eff_score + w2×fbr_score + w3×adx_score + w4×atr_ratio_score
```

**Phase 2: 权重优化（ML）**

使用监督学习学习最优权重：

```python
# 目标：最大化 Sharpe / 胜率
# 特征：[eff, fbr, adx, atr_ratio, ...]
# 标签：未来 N 根 K 线的胜率/盈亏比
# 模型：线性回归 / XGBoost
```

**Phase 3: 动态基准（RL）**

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
│   ├── regime_param_optimize.py  # M6.2 参数网格搜索
│   ├── data_collector.py         # M6.4 数据收集器
│   └── regime/             # Regime Filter Python 模块
└── docs/
    └── ai_data_schema.md   # M6.5 数据 Schema
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

## M6-M8: AI 增强详细设计

### M6: 参数优化 + 数据收集

#### M6.1 Q-Score 优化

| 任务 | 状态 | 说明 |
|------|------|------|
| M6.1.1 | ✅ | 新公式实现（基准值 + 相对评分） |
| M6.1.2 | ✅ | 阈值调整（Standby: 0.35, Active: 0.45） |
| M6.1.3 | ⏳ | ADX 维度加入 |
| M6.1.4 | ⏳ | ATR_ratio 维度加入 |
| M6.1.5 | ⏳ | Session 权重动态化 |

#### M6.2 参数网格搜索

```bash
# 运行参数优化
cd Python
python regime_param_optimize.py \
  --data "E:/mt5_test_datas/mt5/XAUUSD_M5.csv" \
  --output data/regime_optimize_results.csv
```

#### M6.4 数据收集

```bash
# 收集训练数据
cd Python
python data_collector.py \
  --data "E:/mt5_test_datas/mt5/XAUUSD_M5.csv" \
  --output data/features_train.csv \
  --label
```

**输出字段**：见 `docs/ai_data_schema.md`

#### M6.3 Walk-Forward 验证

```
数据分割：
├── Train: 2024.01 - 2024.06
├── Valid: 2024.07 - 2024.09
└── Test:  2024.10 - 2024.12

滚动窗口：
Window 1: Train[1-6月] → Test[7月]
Window 2: Train[2-7月] → Test[8月]
...
```

---

### M7: ML 参数优化

#### 7.1 特征工程

```python
# 原始特征
raw_features = ['efficiency', 'false_breakout_rate', 'adx', 'atr', 
                'regime_state', 'sub_type', 'hour', 'session']

# 时序特征
lag_features = ['efficiency_lag1', 'efficiency_lag5', 
                'fbr_lag1', 'fbr_lag5']

# 交叉特征
cross_features = ['eff_x_adx', 'fbr_x_volatility']
```

#### 7.2 标签生成

| 标签类型 | 定义 | 用途 |
|----------|------|------|
| win_rate | 未来 N 根 K 线胜率 | 分类任务 |
| pnl_ratio | 未来盈亏比 | 回归任务 |
| sharpe | 未来收益夏普比 | 回归任务 |

#### 7.3 模型训练

```python
# 特征 → Q-Score 权重
model = XGBRegressor(
    objective='reg:squarederror',
    n_estimators=100,
    max_depth=5,
)

# 训练
model.fit(X_train, y_train)

# 提取特征重要性
importance = model.feature_importances_
```

#### 7.4 参数导出

```python
# 生成 MQL5 代码
def export_to_mql5(weights, baselines):
    code = f"""
    // ML 优化后的参数
    double w_eff = {weights['eff']:.4f};
    double w_fbr = {weights['fbr']:.4f};
    double w_adx = {weights['adx']:.4f};
    double baseline_eff = {baselines['eff']:.4f};
    double baseline_fbr = {baselines['fbr']:.4f};
    """
    return code
```

---

### M8: RL 状态决策

#### 8.1 环境设计

```python
import gym
from gym import spaces

class RegimeTradingEnv(gym.Env):
    def __init__(self, df, initial_balance=10000):
        super().__init__()
        
        # 状态空间
        self.observation_space = spaces.Dict({
            "efficiency": spaces.Box(0, 1, shape=(1,)),
            "false_breakout_rate": spaces.Box(0, 1, shape=(1,)),
            "adx": spaces.Box(0, 100, shape=(1,)),
            "atr_ratio": spaces.Box(0, 3, shape=(1,)),
            "session": spaces.Discrete(4),
            "volatility_state": spaces.Discrete(3),
        })
        
        # 动作空间：调整参数
        self.action_space = spaces.Dict({
            "w_eff": spaces.Box(0.1, 0.4, shape=(1,)),      # 效率权重
            "w_fbr": spaces.Box(0.1, 0.4, shape=(1,)),      # 假突破权重
            "q_standby": spaces.Box(0.25, 0.45, shape=(1,)), # STANDBY 阈值
            "q_active": spaces.Box(0.40, 0.60, shape=(1,)),  # ACTIVE 阈值
        })
    
    def step(self, action):
        # 应用动作，更新参数
        # 运行一步交易
        # 计算奖励
        reward = self._calculate_reward()
        return observation, reward, done, info
    
    def _calculate_reward(self):
        # 奖励函数：夏普比 - 回撤惩罚
        sharpe = self.returns.mean() / (self.returns.std() + 1e-8) * np.sqrt(252)
        dd_penalty = max(0, self.max_drawdown - 0.1) * 10
        return sharpe - dd_penalty
```

#### 8.2 训练流程

```python
from stable_baselines3 import PPO

# 创建环境
env = RegimeTradingEnv(df_train)

# 创建模型
model = PPO(
    "MultiInputPolicy",
    env,
    learning_rate=3e-4,
    n_steps=2048,
    batch_size=64,
    verbose=1,
)

# 训练
model.learn(total_timesteps=100000)

# 保存
model.save("models/rl_regime_policy.zip")
```

#### 8.3 部署架构

```
训练环境 (Python)
    ↓ 训练完成
ONNX 模型导出
    ↓ 
MQL5 推理集成
    ↓
EA 实时推理
```

---

## 参数配置

### Regime Filter 参数

```
Regime Filter 设置:
├── RF_Q_Score_Standby = 0.30  # STANDBY 阈值
├── RF_Q_Score_Active = 0.40   # ACTIVE 阈值
├── RF_Transition_Bars = 3     # 过渡期 K 线数
├── RF_Hysteresis = 0.05       # 滞后阈值
└── RF_Enable_SubType = true   # 启用 Sub-Type

市场质量设置:
├── MQ_Efficiency_Period = 20
├── MQ_Efficiency_Baseline = 0.10
├── MQ_FBR_Baseline = 0.40
```

---

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
| v2.2.0 | M5 | Regime Filter + StrategyRegistry + Q-Score优化 |
| v2.1.0 | M3-M4 | Mean Reversion + TrendPullback 策略族 |
| v2.0.0 | M1-M2 | 策略框架 + 风控管道 |
