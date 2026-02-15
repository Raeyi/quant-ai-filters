# AI 数据文件说明

本文件说明用于回测与 AI 训练的数据字段规范。

---

## 1. features_train.csv（M6.4 数据收集器输出）

### 用途
ML/RL 训练的特征数据集，包含每根K线的完整特征和交易结果标签。

### 字段说明

#### 时间特征
| 字段 | 类型 | 说明 |
|------|------|------|
| `time` | str | ISO格式时间戳 |
| `hour` | int | 小时 (0-23) |
| `day_of_week` | int | 星期 (0=周一, 6=周日) |
| `session` | int | 交易时段 (0=亚洲, 1=欧洲, 2=美国, 3=重叠) |

#### 价格特征
| 字段 | 类型 | 说明 |
|------|------|------|
| `open` | float | 开盘价 |
| `high` | float | 最高价 |
| `low` | float | 最低价 |
| `close` | float | 收盘价 |

#### 技术指标
| 字段 | 类型 | 说明 |
|------|------|------|
| `atr` | float | ATR值 |
| `adx` | float | ADX值 |
| `rsi` | float | RSI值 |

#### 市场质量
| 字段 | 类型 | 说明 |
|------|------|------|
| `efficiency` | float | 市场效率 (0-1) |
| `false_breakout_rate` | float | 假突破率 (0-1) |
| `q_score` | float | 综合质量分数 (0-1) |

#### Regime 状态
| 字段 | 类型 | 值域 | 说明 |
|------|------|------|------|
| `regime_state` | int | 0,1,2 | 0=ACTIVE, 1=STANDBY, 2=TRANSITION |
| `regime_type` | int | 0,1 | 0=RANGE, 1=TREND |
| `sub_type` | int | 0-7 | 市场细分类型 |
| `trend_direction` | int | -1,0,1 | 趋势方向 |
| `volatility_state` | int | 0,1,2 | 0=LOW, 1=NORMAL, 2=HIGH |

#### Sub-Type 编码
| 值 | 类型 | 说明 |
|----|------|------|
| 0 | T+V-B | 趋势+波动-偏差（高质量趋势）|
| 1 | T+V-A | 趋势+波动+偏差（偏差趋势）|
| 2 | R+N | 震荡+中性（标准震荡）|
| 3 | R+V-H | 震荡+高波动（风险震荡）|
| 4 | R+V-L | 震荡+低波动（平静震荡）|
| 5 | R+D | 震荡+漂移（有偏差震荡）|
| 6 | CHOP | 无序震荡（极度危险）|
| 7 | UNKNOWN | 未知状态 |

#### 策略信号
| 字段 | 类型 | 值域 | 说明 |
|------|------|------|------|
| `boll_signal` | int | -1,0,1 | BollMR策略信号 |
| `trend_signal` | int | -1,0,1 | TrendPullback策略信号 |
| `final_signal` | int | -1,0,1 | 最终信号（经Regime过滤）|

#### 风险参数
| 字段 | 类型 | 说明 |
|------|------|------|
| `position_size` | float | 建议仓位大小 |
| `sl_mult` | float | 止损ATR乘数 |
| `tp_mult` | float | 止盈ATR乘数 |

#### 结果标签（`--label` 参数生成）
| 字段 | 类型 | 说明 |
|------|------|------|
| `pnl` | float | 交易盈亏（点数）|
| `holding_bars` | int | 持仓K线数 |
| `win` | bool | 是否盈利 |
| `labeled` | bool | 是否已标注 |

---

## 2. regime_optimize_results.csv（M6.2 参数优化输出）

### 字段说明
| 字段 | 类型 | 说明 |
|------|------|------|
| `eff_baseline` | float | 效率基准值 |
| `fbr_baseline` | float | 假突破率基准值 |
| `q_standby` | float | STANDBY阈值 |
| `q_active` | float | ACTIVE阈值 |
| `signals` | int | 信号数量 |
| `trades` | int | 交易笔数 |
| `total_return` | float | 总收益率(%) |
| `max_drawdown` | float | 最大回撤(%) |
| `sharpe` | float | Sharpe比率 |
| `win_rate` | float | 胜率(%) |
| `active_pct` | float | ACTIVE状态占比(%) |
| `active_bars` | int | ACTIVE状态K线数 |

---

## 3. features.csv（EA导出）

EA 在 MT5 中导出的特征文件。

| 字段 | 说明 |
|------|------|
| `time` | 时间戳 |
| `close` | 收盘价 |
| `boll_u` | 布林上轨 |
| `boll_l` | 布林下轨 |
| `atr` | ATR值 |

---

## 4. signals.csv（回测信号导出）

| 字段 | 说明 |
|------|------|
| `time` | 时间戳 |
| `signal` | 信号方向 (1=多, -1=空, 0=无) |
| `confidence` | 信号置信度 (0-1) |
