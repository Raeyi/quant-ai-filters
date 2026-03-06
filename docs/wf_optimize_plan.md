# MT5 Combo 策略 Walk-Forward 优化计划

## 一、优化范围

### 1.1 策略组成
- **BollMR**: 布林带均值回归策略
- **TrendPullback**: 趋势回调策略
- **Regime Filter**: 市场状态过滤器 (全局共享)
- **风控模块**: RiskPipeline (全局共享)

### 1.2 待优化参数

#### 阶段1: 策略参数 (独立优化)

| 模块 | 参数 | 范围 | 说明 |
|------|------|------|------|
| **BollMR** | BollPeriod | 16-24 | 布林周期 |
| | BollDev | 1.6-2.4 | 标准差倍数 |
| | MAPeriod | 40-80 | MA周期 |
| | ATRPeriod | 10-18 | ATR周期 |
| | EntryMode | A/B/C | 入场模式 |
| | MaxHoldingBars | 3-10 | 最大持仓K线 |
| **TrendPullback** | EMA50 | 40-80 | 短期EMA |
| | EMA200 | 150-250 | 长期EMA |
| | PullbackDepthATR | 0.3-0.7 | 回调深度 |
| | ATR_SL_Multi | 1.0-2.5 | 止损倍数 |
| | Add1_Ratio | 0.3-0.5 | 加仓比例 |
| | MaxTotalRisk | 2.0-3.5 | 最大风险 |

#### 阶段2: Regime Filter 参数 (策略参数固定后优化)

| 参数 | 默认值 | 范围 | 说明 |
|------|--------|------|------|
| RF_Q_Score_Standby | 0.30 | 0.25-0.40 | STANDBY阈值 |
| RF_Q_Score_Active | 0.40 | 0.35-0.50 | ACTIVE阈值 |
| MQ_Efficiency_Baseline | 0.12 | 0.08-0.16 | 效率基准 |
| MQ_FBR_Baseline | 0.35 | 0.25-0.45 | 假突破率基准 |
| MQ_ADX_Baseline | 25.0 | 20-35 | ADX基准 |

#### 阶段3: 风控参数 (最后优化)

| 参数 | 默认值 | 范围 | 说明 |
|------|--------|------|------|
| InpRiskPercent | 1.0 | 0.5-2.0 | 单笔风险% |
| MaxLosingStreak | 3 | 2-5 | 最大连亏次数 |
| MAX_DAILY_LOSS_PERCENT | 5.0 | 3-7 | 日亏损限制% |
| CooldownBarsAfter | 5 | 3-10 | 冷却K线数 |

---

## 二、优化顺序 (重要!)

```
┌─────────────────────────────────────────────────────────────┐
│ 阶段1: 策略参数 WF 优化 (当前)                               │
│ ├── BollMR W1/W2 优化 → 得到最优策略参数                     │
│ └── TP W1/W2 优化     → 得到最优策略参数                     │
│     └── RF/风控参数: 使用固定经验值                          │
├─────────────────────────────────────────────────────────────┤
│ 阶段2: RF 参数优化 (策略参数固定)                            │
│ └── 使用 MT5 原生优化器                                      │
│     └── 固定已确定的最优策略参数                              │
│     └── 只优化 RF 阈值                                       │
├─────────────────────────────────────────────────────────────┤
│ 阶段3: 风控参数优化 (策略+RF固定)                            │
│ └── 最后调整风险参数                                         │
├─────────────────────────────────────────────────────────────┤
│ 阶段4: 联合验证                                              │
│ └── 三策略 + RF + 风控 整体回测                              │
└─────────────────────────────────────────────────────────────┘
```

**为什么这个顺序？**
1. RF 是**全局过滤器**，影响所有策略
2. 如果策略参数不稳定，RF 优化结果会漂移
3. 先让策略参数"稳定"，再调全局参数
4. 风控是最后防线，应在策略表现确定后调整

---

## 三、Walk-Forward 验证设计 (Rolling Window)

### 3.1 滚动窗口方案

```
时间线: 2025.01 - 2025.12 (12个月)

Window 1:
├── 训练: 2025.01 - 2025.03 (3个月)
├── 测试: 2025.04 (1个月)
└── 状态: ✅ BollMR W1 完成

Window 2:
├── 训练: 2025.04 - 2025.06 (3个月) ← 滚动
├── 测试: 2025.07 (1个月)
└── 状态: 🔄 待执行

Window 3:
├── 训练: 2025.07 - 2025.09 (3个月) ← 滚动
├── 测试: 2025.10 (1个月)
└── 状态: ⏳ 待执行

Window 4:
├── 训练: 2025.10 - 2025.12 (3个月) ← 滚动
├── 测试: 2026.01 (1个月)
└── 状态: ⏳ 待执行
```

### 3.2 验证指标

| 指标 | 阈值 | 说明 |
|------|------|------|
| 测试集 Sharpe | > 0 | 正收益 |
| 训练/测试衰减 | < 50% | 不过拟合 |
| 参数稳定性 | > 70% | 相邻窗口参数相似 |

---

## 四、四季度网格优化计划

> **核心思路**: 四个季度分别优化 → 找稳定参数中间值 → RF/风控识别市场状态

### 4.1 市场特征

| 季度 | 时间 | 市场特征 | 适合策略 |
|------|------|---------|---------|
| Q1 | 1-3月 | 震荡 | BollMR |
| Q2 | 4-6月 | 震荡 | BollMR |
| Q3 | 7-9月 | 过渡→趋势 | TP |
| Q4 | 10-12月 | 趋势 | TP |

### 4.2 配置文件

| 季度 | BollMR 配置 | TP 配置 |
|------|------------|--------|
| Q1 (1-3月) | `quant_q1_bollmr_optimize.set` | `quant_q1_tp_optimize.set` |
| Q2 (4-6月) | `quant_q2_bollmr_optimize.set` | `quant_q2_tp_optimize.set` |
| Q3 (7-9月) | `quant_q3_bollmr_optimize.set` | `quant_q3_tp_optimize.set` |
| Q4 (10-12月) | `quant_q4_bollmr_optimize.set` | `quant_q4_tp_optimize.set` |

### 4.3 优化参数网格

**BollMR (震荡策略)**:
| 参数 | 范围 | 步长 |
|------|------|------|
| BollPeriod | 14-24 | 2 |
| BollDev | 1.4-2.4 | 0.2 |
| ATRPeriod | 8-20 | 2 |
| MAPeriod | 40-100 | 10 |
| MaxHoldingBars | 3-12 | 2 |

**TP (趋势策略)**:
| 参数 | 范围 | 步长 |
|------|------|------|
| EMA50 | 40-100 | 10 |
| EMA200 | 150-300 | 25 |
| PullbackDepthATR | 0.3-0.8 | 0.1 |
| ATR_Period | 8-20 | 2 |
| ATR_SL_Multi | 1.0-2.5 | 0.5 |
| TrailATR_Multi | 1.5-4.0 | 0.5 |
| Add1_Ratio | 0.2-0.6 | 0.1 |
| MaxTotalRisk | 2.0-5.0 | 0.5 |

### 4.4 优化流程

```
┌─────────────────────────────────────────────────────────────┐
│ 阶段1: 四季度网格优化 (共8次优化)                            │
│ ├── Q1: BollMR + TP (1-3月)                                │
│ ├── Q2: BollMR + TP (4-6月)                                │
│ ├── Q3: BollMR + TP (7-9月)                                │
│ └── Q4: BollMR + TP (10-12月)                              │
├─────────────────────────────────────────────────────────────┤
│ 阶段2: 参数稳定性分析                                        │
│ ├── 分析各季度最优参数                                      │
│ └── 计算稳定参数中间值                                      │
├─────────────────────────────────────────────────────────────┤
│ 阶段3: RF 参数优化                                          │
│ ├── 目标: 识别震荡 vs 趋势市场                              │
│ └── 优化 Q_Score_Standby/Active 等阈值                     │
├─────────────────────────────────────────────────────────────┤
│ 阶段4: 风控参数优化                                         │
│ └── 最后调整风险参数                                        │
├─────────────────────────────────────────────────────────────┤
│ 阶段5: 实盘运行                                             │
│ ├── RF 识别震荡 → 启用 BollMR                               │
│ └── RF 识别趋势 → 启用 TP                                   │
└─────────────────────────────────────────────────────────────┘
```

### 4.5 当前进度

| 优化任务 | 配置文件 | 状态 |
|---------|---------|------|
| Q1 BollMR | `quant_q1_bollmr_optimize.set` | 📝 待运行 |
| Q1 TP | `quant_q1_tp_optimize.set` | 📝 待运行 |
| Q2 BollMR | `quant_q2_bollmr_optimize.set` | 📝 待运行 |
| Q2 TP | `quant_q2_tp_optimize.set` | 📝 待运行 |
| Q3 BollMR | `quant_q3_bollmr_optimize.set` | 📝 待运行 |
| Q3 TP | `quant_q3_tp_optimize.set` | 📝 待运行 |
| Q4 BollMR | `quant_q4_bollmr_optimize.set` | 📝 待运行 |
| Q4 TP | `quant_q4_tp_optimize.set` | 📝 待运行 |

---

## 五、早期 WF 测试结果 (参考)

### 5.1 BollMR 优化 (震荡市场策略)

| 窗口 | 配置文件 | 状态 | 结果 |
|------|---------|------|------|
| W1 Train | `config/quant_wf_bollmr_train_w1.set` | ✅ 完成 | Sharpe=5.52 |
| W1 Test | `config/quant_wf_bollmr_test_w1.set` | ✅ 完成 | 59 trades, Sharpe=5.52 |
| W1 Result | `config/quant_wf_bollmr_result_w1.set` | ✅ 完成 | 最优参数已保存 |
| W2 Train | `config/quant_wf_bollmr_train_w2.set` | ✅ 完成 | Sharpe=50.02, Profit=796 |
| W2 Result | `config/quant_wf_bollmr_result_w2.set` | ✅ 完成 | 最优参数已保存 |
| W2 Test | `config/quant_wf_bollmr_test_w2.set` | ✅ 完成 | Sharpe=1.31, Profit=11 |

**W1 最优参数 (1-3月)**:
- BollPeriod=20, BollDev=1.6, ATRPeriod=10
- MAPeriod=80, MaxHoldingBars=5, EntryMode=C

**W2 最优参数 (4-6月)**:
- BollPeriod=18, BollDev=1.8, ATRPeriod=18
- MAPeriod=60, MaxHoldingBars=9, EntryMode=C

### 5.2 TrendPullback 优化 (趋势市场策略)

> **重要**: TP 策略适合趋势市场，需使用下半年数据优化

| 窗口 | 时间段 | 配置文件 | 状态 |
|------|--------|---------|------|
| W1 Train | 2025.07-09 | `config/quant_wf_tp_train_trend_w1.set` | 📝 待运行 |
| W1 Test | 2025.10 | 待创建 | ⏳ |
| W2 Train | 2025.10-12 | `config/quant_wf_tp_train_trend_w2.set` | 📝 待运行 |
| W2 Test | 2026.01 | 待创建 | ⏳ |

**早期测试 (1-6月震荡期)**:
- W1 Train (1-3月): Sharpe=15.09, 但测试期失败
- W2 Train (4-6月): 全部亏损，Sharpe=-0.60~-5.00
- **结论**: TP 不适合震荡市场，需用趋势期数据重新优化

---

## 五、Session 时间设计

| 策略 | Session | 时间 (北京) | 原因 |
|------|---------|------------|------|
| BollMR | custom | 2:00-20:00 | 非美盘，避免假突破 |
| TrendPullback | europe,us,overlap | 14:00-次日4:00 | 趋势行情活跃时段 |

---

## 六、后续优化配置文件 (待创建)

| 阶段 | 文件 | 用途 |
|------|------|------|
| RF 优化 | `config/quant_wf_regime_train.set` | MT5 原生优化 RF 参数 |
| 风控优化 | `config/quant_wf_risk_train.set` | MT5 原生优化风控参数 |
| 最终配置 | `config/quant_combo_final.set` | 联合验证最终参数 |

---

## 七、注意事项

1. **Python vs MT5 差距**: Python 回测结果仅供参考，最终以 MT5 为准
2. **RF 共享**: 所有策略共用同一套 RF 参数，不能分别优化
3. **时间过滤**: BollMR 使用 custom 模式避开美盘
4. **遗传算法**: 大参数空间使用遗传算法优化，减少计算时间
