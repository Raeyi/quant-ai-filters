# TODO

## 执行顺序总览

### 支撑层【当前重点】
- [ ] Regime Filter：市场状态过滤 → 策略选择器 → 策略激活

### 策略层
- [x] M1（Mean Reversion）：框架完成 + 参数优化
- [x] M2（Trend Pullback）：框架完成 + 参数优化
- [ ] M3（XAUUSD Alpha）：美盘结构策略【跳过，优先支撑层】

### 评估层
- [ ] M4（回测评估）：统一评估框架

---

## 支撑层: Regime Filter【当前重点】

- [ ] Phase 1: Base Regime + Market Quality Score
  - [ ] RegimeIndicators (trend_strength, volatility_state)
  - [ ] MarketQuality (efficiency, false_breakout_rate)
  - [ ] Q_score 计算，Q<0.5 → STANDBY
  - [ ] 历史数据验证 Regime 识别准确率
- [ ] Phase 2: Regime Sub-Type 分类
  - [ ] T+V-A (情绪脉冲): 高波动 + 低效率
  - [ ] T+V-B (真趋势): 高波动 + 高效率
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
  - [x] Ask/Bid 正确使用
- [x] M2.c 时间过滤：
  - [x] 复用 BollMR session 机制
  - [x] 默认美盘+重叠时段
  - [x] 时段结束时间止盈
- [x] M2.d 四层出场设计：
  - [x] L1 防御止损
  - [x] L2 最小兑现
  - [x] L3 趋势持有
  - [x] L4 时间止盈
  - [x] Trailing Stop（可选）
- [x] M2.f 结构冷却器（StructuralCooldown.mqh）
- [x] M2.g 加仓管理器（AddPositionManager.mqh）
- [x] M2.e 扩展：
  - [x] 组合策略（Strategy_Combo.mqh）
  - [x] Python 多策略回测脚本（backtest_combo.py）
  - [x] 参数优化（param_optimize.py）
  - [x] 优化参数同步到 MT5
  - [x] CI/CD 配置
- [ ] 成交模型优化（可选，低频策略影响小）

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
- [ ] AI 过滤器流水线
- [ ] 命令行 `--profile` 支持（可选）

---

## 已完成（历史记录）

- [x] BollMR 分层出场与回落保护
- [x] EA 执行层支持部分平仓
- [x] EA <-> Python 文件契约
- [x] 训练样本构建脚本
- [x] MT5 vs Python 信号对齐对比脚本
- [x] 一键运行脚本
- [x] EA 导出 signals_mt5.csv
- [x] Python 回测参数可配置
- [x] MT5 策略参数写入 config.json
- [x] 图形化配置与一键运行（Web 面板）
- [x] Web 面板各项功能
- [x] MT5 与 Python 信号逐 K 对齐验证
- [x] ECMarkets 成本模型参数确认
