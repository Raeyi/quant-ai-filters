# TODO

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
- [x] 测试“禁止交易”面板显示修复（时间过滤），通过后再合入 EA_1.1.0

## 待办

## 里程碑 M1: Mean Reversion Family

- [ ] 策略族拆分（Mean Reversion Family）
- [x] M1.a BB+ATR（基础回归）
- [ ] M1.b BB+RSI（动能过滤）
- [ ] M1.c BB+时间过滤（伦敦/美盘窗口）
- [ ] 提供一份第三方 CSV 样例（列名/时间格式）用于解析验证
- [ ] 增加 Dukascopy/TrueFX 下载与清洗模块

## 里程碑 M2: Trend Pullback Family v1

- [ ] M15 定方向 + M5 回撤入场
- [ ] M2.a M15：EMA50/EMA200 方向
- [ ] M2.b M5：回撤到 EMA20/VWAP + 小结构确认
- [ ] M2.c 统一 SL/TP：ATR 1.0 / 1.5–2.0
- [ ] 扩展成交模型（点差、手续费、滑点、合约大小、手数取整）

## 里程碑 M3: Regime Filter（规则 → ML）

- [ ] M3 Regime Filter（先规则后 ML）
- [ ] M3.a 输出不同策略族权重（不直接下单）
- [ ] M3.b 指标：ATR 变化、假突破频率、回撤吞没速度
- [ ] 构建多策略注册与组合风控层

## 里程碑 M4: 回测评估升级

- [ ] M4 回测评估升级
- [ ] M4.a 不同 Regime 下胜率/回撤/收益
- [ ] M4.b 策略间相关性矩阵
- [ ] M4.c 连续亏损分布
- [ ] 实现 AI 过滤器流水线（训练/推理）并接入信号流程
- [ ] 增加命令行 `--profile` 支持（可选）
