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

Phase 4: AI 增强 🔄
├── M6: 参数优化 + 数据收集  → v2.3.0 ← 当前
├── M7: ML 参数优化         → v2.3.0
└── M8: RL 状态决策         → v2.4.0

Phase 5: 策略扩展 ⏳
└── M9: XAUUSD Alpha        → v2.5.0
```

---

## M6: 参数优化 + 数据收集【进行中】

- [ ] M6.1 Q-Score 阈值调优
- [ ] M6.2 参数网格搜索
- [ ] M6.3 Walk-Forward 验证
- [ ] M6.4 数据收集器实现
- [ ] M6.5 数据 Schema 定义

## M7: ML 参数优化【待开始】

- [ ] M7.1 特征工程
- [ ] M7.2 标签生成（胜率/盈亏比）
- [ ] M7.3 模型训练（XGBoost / LightGBM）
- [ ] M7.4 特征重要性分析（SHAP）
- [ ] M7.5 参数导出到 MQL5

## M8: RL 状态决策【待开始】

- [ ] M8.1 环境封装（gym）
- [ ] M8.2 PPO 训练（Stable-Baselines3）
- [ ] M8.3 策略评估
- [ ] M8.4 模型导出（ONNX）

## M9: XAUUSD Alpha【待开始】

- [ ] M9.1 基础设施
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
