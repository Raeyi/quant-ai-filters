# TODO

## 路线图

```
Phase 1: 基础架构 ✅
├── M1: 策略框架           → v2.0.0
└── M2: 风控管道           → v2.1.0

Phase 2: 策略开发 ✅
├── M3: Mean Reversion     → v2.1.0
└── M4: Trend Pullback     → v2.1.0

Phase 3: Regime 引擎 ✅
└── M5: Regime Filter      → v2.2.0

Phase 4: 架构重构 ✅
├── M6: 架构清理           → v2.3.0
├── M7: XAUUSD 职业化过滤   → v2.4.0 ← 当前
└── M8: AI 参数优化         → v2.5.0

Phase 5: 策略扩展 ⏳
└── M9: XAUUSD Alpha        → v2.6.0
```

---

## M6: 架构清理【已完成】✅

### 6.1 架构诊断
- [x] M6.1.1 分析双重过滤问题
- [x] M6.1.2 识别重复代码（时间过滤、趋势判断、波动率）
- [x] M6.1.3 设计新架构方案

### 6.2 代码清理
- [x] M6.2.1 删除 TrendPullback 中重复的时间过滤代码
- [x] M6.2.2 创建统一的 TimeFilter.mqh 接口
- [x] M6.2.3 统一趋势枚举到 RegimeTypes.mqh

### 6.3 架构重构
- [x] M6.3.1 RegimeFilter 集成到主循环
- [x] M6.3.2 策略层移除趋势判断逻辑（~50行删除）
- [x] M6.3.3 策略层波动率判断确认无重复
- [x] M6.3.4 编译验证通过

---

## M7: XAUUSD 职业化过滤【已完成】✅

### 7.1 架构设计
- [x] M7.1.1 分析现有 TimeFilter 与 M7 的关系（结论：整合到 RegimeFilter）
- [x] M7.1.2 设计 SessionQuality 类（时段质量评估）

### 7.2 时段质量实现
- [x] M7.2.1 黄金活跃时段识别（伦敦/纽约开盘后）
- [x] M7.2.2 低流动性时段检测（亚洲深夜）
- [x] M7.2.3 时段权重集成到 Q-Score

### 7.3 事件过滤
- [x] M7.3.1 新闻事件时间窗口（NFP/FOMC 前后30分钟）
- [x] M7.3.2 流动性检测（点差/成交量）

---

## M8: AI 参数优化【进行中】

### 8.1 参数网格搜索

- [x] M8.1.1 regime_param_optimize.py 实现
- [x] M8.1.2 多时间框架验证（M5 有效，M15/H1 需独立策略参数）
- [ ] M8.1.3 Walk-Forward 验证

### 8.2 数据收集

- [x] M8.2.1 data_collector.py 实现
- [x] M8.2.2 特征 Schema 定义
- [ ] M8.2.3 多品种数据收集

### 8.3 ML 参数优化

- [ ] M8.3.1 特征工程
- [ ] M8.3.2 模型训练
- [ ] M8.3.3 参数导出

---

## M9: XAUUSD Alpha【待开始】

- [ ] M9.1 黄金特性策略
- [ ] M9.2 结构识别
- [ ] M9.3 仓位结构
- [ ] M9.4 入场/退出
- [ ] M9.5 实盘准备

---

## 已完成

### M5: Regime Filter (v2.2.0)

- [x] Regime Filter 完整实现（Python + MQL5）
- [x] StrategyRegistry 统一策略管理
- [x] Ea_run.mq5 代码重构
- [x] Q-Score 公式优化
- [x] StatusPanel Regime 状态显示

### M3-M4: 策略族 (v2.1.0)

- [x] M3 Mean Reversion 策略族
- [x] M4 Trend Pullback 策略族
- [x] 结构冷却器 + 加仓管理器
- [x] MT5 vs Python 信号对齐验证

### M1-M2: 基础架构 (v2.0.0)

- [x] 策略框架 + 风控管道
- [x] EA 执行层支持部分平仓
- [x] Web 面板
