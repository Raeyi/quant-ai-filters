# TODO

## 执行顺序总览

### 策略层（三大策略族并列）
- [ ] M1（Mean Reversion）：框架完成，参数优化【暂停，待多策略联调】
- [ ] M2（Trend Pullback）：【当前重点】先 M15 方向框架 → 再 M5 回撤入场 → 再小范围优化
- [ ] M3（XAUUSD Alpha）：美盘结构策略，结构识别 → 仓位结构 → 参数优化

### 支撑层（服务于策略）
- [ ] Regime Filter：市场状态过滤，规则 → ML 打分 → 策略组合与风控
- [ ] M4（回测评估）：统一评估框架，指标口径统一 → 批量评估/相关性 → 复杂评估维度

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
- [ ] M2.0 基础设施：
  - [ ] Python 策略框架（TrendPullbackStrategy）
  - [ ] MQL5 策略模板（Strategy_TrendPullback.mqh）
  - [ ] 多周期数据支持（M5 + M15）
- [ ] M2.a M15 方向判断：
  - [ ] EMA50/EMA200 金叉死叉
  - [ ] 趋势状态定义（BULL/BEAR/FLAT）
- [ ] M2.b M5 回撤入场：
  - [ ] 回撤到 EMA20/VWAP
  - [ ] 小结构确认（前高/前低突破）
  - [ ] 入场信号触发
- [ ] M2.c 统一 SL/TP：
  - [ ] ATR 1.0 止损
  - [ ] ATR 1.5-2.0 止盈
- [ ] M2.d 扩展：
  - [ ] 成交模型优化
  - [ ] 与 M1 策略组合测试

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

## 支撑层: Regime Filter（市场状态过滤）

- [ ] 执行顺序：先规则过滤验证 → 再 ML 打分/权重 → 最后接入策略组合与风控
- [ ] 输出不同策略族权重（不直接下单）
- [ ] 指标：ATR 变化、假突破频率、回撤吞没速度
- [ ] 构建多策略注册与组合风控层

## 里程碑 M4: 回测评估升级

- [ ] 执行顺序：先指标口径统一 → 再批量评估/相关性 → 最后引入更复杂评估维度
- [ ] M4.a 不同 Regime 下胜率/回撤/收益
- [ ] M4.b 策略间相关性矩阵
- [ ] M4.c 连续亏损分布
- [ ] M4.d 参数批量回测与对比（网格/随机）
- [ ] 实现 AI 过滤器流水线（训练/推理）并接入信号流程
- [ ] 增加命令行 `--profile` 支持（可选）

