# TODO

## 执行顺序总览

### 支撑层（服务于所有策略）【当前重点】
- [ ] Regime Filter：市场状态过滤 → 策略选择器 → 策略激活

### 策略层（三大策略族并列）
- [x] M1（Mean Reversion）：框架完成 + 参数优化
- [x] M2（Trend Pullback）：框架完成 + 参数优化
- [ ] M3（XAUUSD Alpha）：美盘结构策略【跳过，优先支撑层】

### 评估层
- [ ] M4（回测评估）：统一评估框架

## 已完成

- [x] BollMR 分层出场与回落保护（支持部分平仓信号）
- [x] EA 执行层支持部分平仓（`exit_volume` + `ClosePartial`）
- [x] 定义 EA <-> Python 文件契约（features.csv / signals.csv 字段说明文档）
- [x] 训练样本构建脚本（features + signals -> dataset）
- [x] MT5 vs Python 信号对齐对比脚本
- [x] 用当前数据跑一次快速回测并输出统计
- [x] 一键运行脚本（单命令回测+导出+训练集构建）
- [x] EA 导出 `signals_mt5.csv`（用于对齐验证）
- [x] Python 回测参数可配置（与 MT5 输入对齐）
- [x] 将 MT5 策略参数写入 `config.json` 并作为默认值
- [x] 图形化配置与一键运行（本地 Web 面板）
- [x] Web 面板支持上传 CSV、显示回测图表、下载 MT5 导出文件
- [x] Web 面板支持列出 mt5_root CSV 列表并一键选用
- [x] Web 面板支持导出策略参数为 .set
- [x] Web 面板显示收益/回撤/交易次数图表
- [x] 校验 MT5 与 Python 的 BollMR 信号逐 K 对齐（2026.01.15-2026.01.31，事件信号 1:1 对齐，匹配率 100%）
- [x] 对齐 Python BollMR 与 MQL5 最新逻辑（入场 shift=2/1、中轨过滤、退出阈值、Bollinger 缓冲对齐、缺口冷却）
- [x] 确认 ECMarkets 成本模型参数（点差、手续费、滑点、最小手数、点值）
- [x] 测试"禁止交易"面板显示修复（时间过滤），通过后再合入 EA_1.1.0

## 待办

## 全局规划（策略开发）

- [x] M1 框架完成：Mean Reversion Family 策略族已实现（base/rsi/time/rsi_time/enhanced）
- [ ] M1 参数优化：【暂停】待 M2 完成后统一进行多策略参数优化
- [ ] M2 开发：【当前重点】Trend Pullback Family

## 里程碑 M1: Mean Reversion Family【框架完成，优化暂停】

- [x] 策略族拆分（Mean Reversion Family）
- [x] M1.a BB+ATR（基础回归）
- [x] M1.b BB+RSI（动能过滤）
- [x] M1.c BB+时间过滤（伦敦/美盘窗口）
- [x] M1.d 组合过滤（RSI + 时间窗口）
- [x] M1.e Enhanced 框架（BB+ATR+MA+Time+分层退出）
- [x] Python/MQL5 信号对齐验证
- [x] 参数扫描脚本框架
- [ ] 参数优化【暂停，瓶颈较大，待多策略联调】

## 里程碑 M2: Trend Pullback Family v1【当前重点】

- [ ] 执行顺序：先 M15 方向框架 → 再 M5 回撤入场 → 再小范围优化 → 再过滤/风控叠加
- [x] M2.0 基础设施：
  - [x] Python 策略框架（TrendPullbackStrategy）
  - [x] MQL5 策略模板（Strategy_TrendPullback.mqh）
  - [x] 多周期数据支持（M5 + M15）
- [x] M2.a M15 方向判断：
  - [x] EMA50/EMA200 金叉死叉
  - [x] 趋势状态定义（BULL/BEAR/FLAT）
  - [x] VWAP 辅助趋势确认
- [x] M2.b M5 回撤入场：
  - [x] 回撤到 EMA20/VWAP 价值区
  - [x] 小结构确认（Lower High / Higher Low）
  - [x] K线形态确认（小实体+方向性信号）
  - [x] 回撤深度限制（0.618 ATR）
  - [x] Ask/Bid 正确使用（多头用Ask，空头用Bid）
- [x] M2.c 时间过滤：
  - [x] 复用 BollMR session 机制（asia/europe/us/overlap）
  - [x] 默认美盘+重叠时段（us,overlap）
  - [x] 时段结束时间止盈
- [x] M2.d 四层出场设计：
  - [x] L1 防御止损：结构破坏 + 初始SL
  - [x] L2 最小兑现：+1.5 ATR 部分平仓（30-40%）
  - [x] L3 趋势持有：EMA20/VWAP 未跌破则持有
  - [x] L4 时间止盈：时段结束时平仓
  - [x] Trailing Stop（可选，2.5 ATR）
- [x] 参数分组（input group: HTF/LTF/Structure/Risk/Exit/Timeframe/TimeFilter）
- [x] M2.f 结构冷却器（StructuralCooldown.mqh）：
  - [x] 快速止损检测（N根K线内）
  - [x] 无动量检测（未达+0.5 ATR就反向）
  - [x] 连续Probe失败检测
  - [x] 冷却解除条件：时间+结构升级
  - [x] 二次确认机制
- [x] M2.g 加仓管理器（AddPositionManager.mqh）：
  - [x] 顺势金字塔加仓逻辑
  - [x] TP1达成+第二次回撤失败触发
  - [x] 账户风控集成
  - [x] 总风险上限控制（2.5R）
  - [x] 独立止损管理
- [x] M2.e 扩展：
  - [x] 组合策略（Strategy_Combo.mqh）- 支持 M1+M2 同时运行
  - [x] Python 多策略回测脚本（backtest_combo.py）
  - [x] 参数优化（param_optimize.py）
  - [x] 优化参数同步到 MT5
  - [x] CI/CD Self-Hosted Runner 配置
  - [ ] 成交模型优化（可选，低频策略影响小）

## 里程碑 M3: XAUUSD Alpha（美盘结构策略）

- [ ] 执行顺序：先结构识别 → 再仓位结构 → 最后参数优化
- [ ] M3.0 基础设施：
  - [ ] Python 策略框架（XauusdAlphaStrategy）
  - [ ] MQL5 策略模板（Strategy_XauusdAlpha.mqh）
- [ ] M3.a 结构识别：
  - [ ] A/B/C Regime 分类器（A1/A2/B1/B2/C1/C2 规则）
  - [ ] BreakoutHold 定义与检测
  - [ ] 回撤失败标准
- [ ] M3.b 仓位结构：
  - [ ] 试错仓（Probe）逻辑
  - [ ] 主攻仓（Attack）触发条件
  - [ ] 加仓逻辑与风控边界
- [ ] M3.c 入场/退出：
  - [ ] Entry Gate 条件
  - [ ] Exit/FailSafe 规则
- [ ] M3.d 实盘准备：
  - [ ] 风控开关、交易频次限制
  - [ ] 日志/监控

## 支撑层: Regime Filter（市场状态过滤）【当前重点】

### Alpha 核心来源

> 市场不奖励"正确的结构"，市场只奖励"结构中被忽略的偏差"

| Alpha 来源 | 说明 | 优先级 |
|------------|------|--------|
| **Market Quality Score** | Q<0.5 → STANDBY，解决"何时不用策略" | ⭐⭐⭐ |
| **Regime Sub-Type** | 区分 T+V-A(情绪脉冲) vs T+V-B(真趋势) | ⭐⭐⭐ |
| **Transition Matrix** | 提前布局下一状态 | ⭐⭐ |
| **时间 × Regime** | 同一 Regime 不同时段权重不同 | ⭐⭐ |
| **风险暴露结构** | Sub-Type → 不同止损/仓位参数 | ⭐ |

### 架构设计 v2

```
Layer 1: Base Regime (H1) → T+V/T+L/R+V/R+L
Layer 2: Market Quality Score (M15) → Q_score (0~1)
Layer 3: Regime Sub-Type → T+V-A/T+V-B/R+V-A/R+V-B
Layer 4: Transition Probability → 提前布局
         ↓
Strategy Selector v2 → Sub-Type × Session × Quality → Action
         ↓
Risk Exposure Structure → Sub-Type → SL_mult/TP_mult/Position
```

### 开发阶段

- [ ] Phase 1: Base Regime + Market Quality Score
  - [ ] RegimeIndicators (trend_strength, volatility_state)
  - [ ] MarketQuality (efficiency, false_breakout_rate)
  - [ ] Q_score 计算，Q<0.5 → STANDBY
  - [ ] 历史数据验证 Regime 识别准确率
- [ ] Phase 2: Regime Sub-Type 分类
  - [ ] T+V-A (情绪脉冲): 高波动 + 低效率
  - [ ] T+V-B (真趋势): 高波动 + 高效率 ← 重仓机会
  - [ ] R+V-A (消息震荡): 高反转率
  - [ ] R+V-B (假突破密集): 高假突破率
  - [ ] Sub-Type → scale 映射
- [ ] Phase 3: 策略选择器 + 时间权重
  - [ ] StrategySelector (Sub-Type × Session × Quality)
  - [ ] TIME_REGIME_WEIGHTS 矩阵
  - [ ] 状态机 (ACTIVE/STANDBY/TRANSITION)
  - [ ] 持仓处理规则
- [ ] Phase 4: Transition Matrix 统计
  - [ ] 历史 Regime 转移概率统计
  - [ ] TRANSITION_MATRIX 构建
  - [ ] 提前布局逻辑
- [ ] Phase 5: 风险暴露结构
  - [ ] Sub-Type → SL_mult/TP_mult/Position 映射
  - [ ] 加仓权限控制
- [ ] Phase 6: Python 回测验证
  - [ ] 各 Sub-Type 下策略表现对比
  - [ ] Quality Score 过滤效果验证
  - [ ] 整体收益评估
- [ ] Phase 7: MQL5 实现
  - [ ] Core/Regime/ 模块
  - [ ] 集成到 Ea_run.mq5
  - [ ] 替换现有 Strategy_Combo

### Regime Sub-Type 定义

| Sub-Type | 条件 | scale | SL_mult | 加仓 |
|----------|------|-------|---------|------|
| **T+V-A** | 高波动 + 低效率 | 0.5 | 0.8 | 禁止 |
| **T+V-B** | 高波动 + 高效率 | 1.2 | 1.5 | 允许 |
| **T+L** | 低波动 + 趋势 | 1.0 | 1.0 | 允许 |
| **R+V-A** | 高反转率 | 0 | - | 禁止 |
| **R+V-B** | 高假突破率 | 0 | - | 禁止 |
| **R+L** | 低波动 + 震荡 | 1.0 | 1.0 | 禁止 |

### 时间权重矩阵

```python
TIME_REGIME_WEIGHTS = {
    'T+V': {'asia': 0.6, 'europe': 1.0, 'us': 1.3, 'overlap': 1.2},
    'T+L': {'asia': 0.8, 'europe': 1.0, 'us': 1.1, 'overlap': 1.1},
    'R+L': {'asia': 1.2, 'europe': 1.0, 'us': 0.7, 'overlap': 0.8},
}
```

### 文件结构

```
Core/Regime/
├── RegimeTypes.mqh          # 类型定义（含 Sub-Type）
├── RegimeIndicators.mqh     # 指标计算
├── MarketQuality.mqh        # Market Quality Score
├── RegimeState.mqh          # 置信度模型
├── RegimeDetector.mqh       # H1 主判定
├── SubTypeClassifier.mqh    # Sub-Type 分类
├── TransitionMatrix.mqh     # 转移概率
├── StrategySelector.mqh     # 策略选择器 v2
├── RiskExposure.mqh         # 风险暴露结构
└── RegimeManager.mqh        # 综合管理

Python/regime/
├── __init__.py
├── types.py                 # 类型定义
├── indicators.py            # 基础指标
├── quality.py               # Market Quality Score
├── state.py                 # 置信度模型
├── detector.py              # Regime 检测
├── subtype.py               # Sub-Type 分类
├── transition.py            # Transition Matrix
├── selector.py              # 策略选择器
├── risk_exposure.py         # 风险暴露结构
└── backtest_regime.py       # 回测验证
```

## 里程碑 M4: 回测评估升级

- [ ] 执行顺序：先指标口径统一 → 再批量评估/相关性 → 最后引入更复杂评估维度
- [ ] M4.a 不同 Regime 下胜率/回撤/收益
- [ ] M4.b 策略间相关性矩阵
- [ ] M4.c 连续亏损分布
- [ ] M4.d 参数批量回测与对比（网格/随机）
- [ ] 实现 AI 过滤器流水线（训练/推理）并接入信号流程
- [ ] 增加命令行 `--profile` 支持（可选）

