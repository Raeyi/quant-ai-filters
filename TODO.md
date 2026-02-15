# TODO

## 执行顺序总览

### 支撑层【完成】
- [x] Regime Filter：市场状态过滤 → 策略选择器 → 策略激活

### 策略层
- [x] M1（Mean Reversion）：框架完成 + 参数优化
- [x] M2（Trend Pullback）：框架完成 + 参数优化
- [ ] M3（XAUUSD Alpha）：美盘结构策略【跳过，优先支撑层】

### 评估层
- [ ] M4（回测评估）：统一评估框架

---

## 支撑层: Regime Filter【完成】

### Python 模块 (`Python/regime/`)

| 模块 | 状态 | 说明 |
|------|------|------|
| `regime_indicators.py` | ✅ | ADX/ATR 计算，RegimeType/VolatilityState 枚举 |
| `market_quality.py` | ✅ | Efficiency ratio, False breakout rate, Q_score |
| `regime_filter.py` | ✅ | 主过滤类，状态机 (ACTIVE/STANDBY/TRANSITION) |
| `regime_subtype.py` | ✅ | Sub-Type 分类器 (8 种细分类型) |
| `strategy_selector.py` | ✅ | StrategySelector + TIME_REGIME_WEIGHTS 矩阵 |
| `transition_matrix.py` | ✅ | 历史 Regime 转移概率统计 |
| `risk_exposure.py` | ✅ | SL/TP/Position 调整映射 |
| `backtest_with_regime.py` | ✅ | RegimeIntegratedBacktest 验证框架 |
| `validate_regime.py` | ✅ | 验证脚本，支持 MT5 History Center 格式 |

### MQL5 模块 (`Core/Regime/`)

| 模块 | 状态 | 说明 |
|------|------|------|
| `RegimeTypes.mqh` | ✅ | 枚举定义 + 辅助函数 (RegimeStateToString 等) |
| `RegimeIndicators.mqh` | ✅ | ADX/ATR 指标计算 |
| `MarketQuality.mqh` | ✅ | Efficiency, False breakout rate, Q_score |
| `RegimeFilter.mqh` | ✅ | 主过滤类，状态机 + Sub-Type 分类 |

### 集成状态

| 步骤 | 状态 | 说明 |
|------|------|------|
| Ea_run.mq5 引入 RegimeFilter | ✅ | 作为信号前置过滤器 |
| StatusPanel 显示 Regime 状态 | ✅ | 显示 state/subtype/Q_score |
| 信号文件导出 Regime 列 | ✅ | signals_mt5.csv 增加 regime 列 |
| StrategyRegistry 重构 | ✅ | 统一策略生命周期管理 |

---

## 架构重构【完成】

### StrategyRegistry

**目的**：消除 Ea_run.mq5 中的硬编码策略选择逻辑

**新增文件**：`Core/StrategyRegistry.mqh`

**核心功能**：
- `Register(name, strategy)` - 注册策略
- `Select(variant)` - 选择策略变体
- `Init()` - 统一初始化
- `UpdateIndicators()` - 统一指标更新
- `TimeFilterOK()` - 统一时间过滤

**代码对比**：
```mql5
// 之前：~40行重复 if-else
if(g_boll_variant == "base") boll_base.UpdateIndicators();
else if(g_boll_variant == "rsi") boll_rsi.UpdateIndicators();
// ...

// 之后：1行
registry.UpdateIndicators();
```

### IStrategy 接口扩展

新增可选方法（有默认实现）：
- `Init()` - 初始化
- `UpdateIndicators()` - 指标更新
- `TimeFilterOK()` - 时间过滤检查

### 辅助函数

`RegimeTypes.mqh` 新增：
- `RegimeStateToString(RegimeState)` - 状态枚举转字符串
- `RegimeSubTypeToString(RegimeSubType)` - Sub-Type 枚举转字符串
- `VolatilityStateToString(VolatilityState)` - 波动率枚举转字符串

---

## 里程碑 M1: Mean Reversion Family【完成】

- [x] 策略族拆分（Mean Reversion Family）
- [x] M1.a BB+ATR（基础回归）
- [x] M1.b BB+RSI（动能过滤）
- [x] M1.c BB+时间过滤（伦敦/美盘窗口）
- [x] M1.d 组合过滤（RSI + 时间窗口）
- [x] M1.e Enhanced 框架（BB+ATR+MA+Time+分层退出）
- [x] Python/MQL5 信号对齐验证
- [x] 参数扫描脚本框架

---

## 里程碑 M2: Trend Pullback Family【完成】

- [x] M2.0 基础设施
- [x] M2.a M15 方向判断（EMA50/EMA200 + VWAP）
- [x] M2.b M5 回撤入场（价值区 + 结构确认）
- [x] M2.c 时间过滤（复用 BollMR session）
- [x] M2.d 四层出场设计（L1-L4）
- [x] M2.f 结构冷却器（StructuralCooldown.mqh）
- [x] M2.g 加仓管理器（AddPositionManager.mqh）
- [x] M2.e 组合策略集成

---

## 里程碑 M3: XAUUSD Alpha【跳过】

- [ ] M3.0 基础设施
- [ ] M3.a 结构识别
- [ ] M3.b 仓位结构
- [ ] M3.c 入场/退出
- [ ] M3.d 实盘准备

---

## 里程碑 M4: 回测评估升级

- [ ] M4.a 不同 Regime 下胜率/回撤/收益
- [ ] M4.b 策略间相关性矩阵
- [ ] M4.c 连续亏损分布
- [ ] M4.d 参数批量回测与对比

---

## 已完成（历史记录）

- [x] BollMR 分层出场与回落保护
- [x] EA 执行层支持部分平仓
- [x] EA <-> Python 文件契约
- [x] MT5 vs Python 信号对齐验证
- [x] Web 面板各项功能
- [x] Regime Filter 完整实现（Python + MQL5）
- [x] StrategyRegistry 统一策略管理
- [x] Ea_run.mq5 代码重构（减少约100行）
