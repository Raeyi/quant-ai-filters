# MT5 回测数据分析指南 (v2.4.0+)

## 快速开始

### 方法 1: Python 分析（推荐）

```bash
cd Python
python analyze_backtest.py --signals "C:\Users\ruiwe\AppData\Roaming\MetaQuotes\Terminal\Common\Files\signals_mt5.csv"
python analyze_backtest.py --signals "signals.csv" --features "features.csv"  # 包含扩展特征分析
```

### 方法 2: PowerShell 快速分析

```powershell
cd scripts
.\analyze_backtest.ps1 -SignalsFile "C:\Users\ruiwe\AppData\Roaming\MetaQuotes\Terminal\Common\Files\signals_mt5.csv"
```

---

## 数据文件说明

### signals_mt5.csv

| 列名 | 说明 | 示例 |
|------|------|------|
| time | 时间戳 | 2025.01.02 12:35:00 |
| signal | 持仓方向 (-1/0/1) | -1 (做空), 1 (做多), 0 (无) |
| event | 当前 bar 事件 | -1, 1, 或空 |
| source | 信号来源策略 | combo_single_TrendPullback |
| regime | Regime 状态 | ACTIVE\|T+N\|Q0.63 |

### regime 列解析

格式: `STATE|SUBTYPE|Q-SCORE`

```
STATE: STANDBY / ACTIVE / TRANSITION
SUBTYPE: T+V-B / T+V-A / T+N / R+V-B / R+V-A / R+N / R+L
Q-SCORE: 0.0 - 1.0
```

### features.csv (扩展格式 v2.4.0+)

features.csv 现在包含 **25+ 列**，专为 ML/RL 训练设计：

| 类别 | 列名 | 说明 |
|------|------|------|
| **时间特征** | time | 时间戳 |
| | hour | 小时 (0-23) |
| | day_of_week | 星期几 (0=周日) |
| | session | 交易时段 (0=Asia, 1=Europe, 2=US, 3=Overlap) |
| **价格特征** | open, high, low, close | OHLC 价格 |
| | price_change | 价格变化 (close - prev_close) |
| | price_range | 价格范围 (high - low) |
| **技术指标** | atr | ATR 值 |
| | adx | ADX 趋势强度 |
| | rsi | RSI 指标 |
| | boll_upper, boll_lower, boll_mid | 布林带轨道 |
| | boll_width | 布林带宽度 (归一化) |
| | boll_position | 价格在布林带中的位置 (0-1) |
| **市场质量** | efficiency | 市场效率 |
| | false_breakout_rate | 假突破率 |
| | q_score | 综合质量分数 |
| **Regime 状态** | regime_state | 状态 (0=ACTIVE, 1=STANDBY, 2=TRANSITION) |
| | regime_type | 市场类型 (0=RANGE, 1=TREND) |
| | sub_type | SubType 编码 (0-6) |
| | trend_direction | 趋势方向 (-1, 0, 1) |
| | volatility_state | 波动率状态 (0=LOW, 1=NORMAL, 2=HIGH) |
| **策略信号** | final_signal | 最终信号 (-1, 0, 1) |
| | position_size | 仓位大小 |

### SubType 编码对照表

| 编码 | 代码 | 描述 | 特点 |
|------|------|------|------|
| 0 | T+V-B | 真趋势 (高质量) | 趋势强+高波动+好质量 |
| 1 | T+V-A | 情绪脉冲 (高波动) | 趋势强+高波动+差质量 |
| 2 | T+N | 温和趋势 | 趋势强+正常波动 |
| 3 | R+V-B | 假突破密集 | 震荡+高波动+差质量 |
| 4 | R+V-A | 消息震荡 | 震荡+高波动+好质量 |
| 5 | R+N | 正常震荡 | 震荡+正常波动 |
| 6 | R+L | 低波动震荡 | 震荡+低波动 |

---

## 手动分析步骤

### 1. 检查 STANDBY 入场比例（最关键）

```powershell
# 加载数据
$data = Import-Csv "signals_mt5.csv" -Delimiter "`t"

# 找出入场信号
$entries = $data | Where-Object { $_.source -and $_.source -ne '' }

# 检查入场时的 Regime 状态
$entries | ForEach-Object { $_.regime.Split('|')[0] } | Group-Object
```

**期望结果**: STANDBY 入场 < 5%

### 2. 检查低流动性时段入场

```powershell
# 入场时间分布
$entries | ForEach-Object { 
    [int]$_.time.Split(' ')[1].Split(':')[0] 
} | Group-Object | Sort-Object Name
```

**期望结果**: 00:00-06:00 (北京时间) 无入场

### 3. 检查 Q-Score 分布

```powershell
# Q-Score 统计
$data | ForEach-Object { 
    [double]$_.regime.Split('|')[2].Replace('Q', '') 
} | Measure-Object -Min -Max -Average
```

**期望结果**: 均值 > 0.4，入场时 Q-Score > 0.5

### 4. 检查信号来源分布

```powershell
$entries | Group-Object source | Sort-Object Count -Descending
```

### 5. 分析扩展特征 (ML/RL 准备)

```python
import pandas as pd

# 加载特征数据
df = pd.read_csv('features.csv', sep='\t')

# 查看特征统计
print(df.describe())

# 查看 Regime 状态分布
print(df['regime_state'].value_counts())

# 查看技术指标相关性
print(df[['atr', 'adx', 'rsi', 'q_score']].corr())
```

---

## 诊断清单

| 检查项 | 正常值 | 异常处理 |
|--------|--------|----------|
| STANDBY 入场比例 | < 5% | 检查 Regime Filter 是否生效 |
| 低流动性时段入场 | 0% | 检查 SessionQuality 是否生效 |
| ACTIVE 入场比例 | > 80% | 检查信号过滤逻辑 |
| Q-Score 均值 | > 0.4 | 调整 Q-Score 参数 |
| 入场时 Q-Score > 0.5 | > 50% | 提高入场阈值 |
| 特征完整性 | 25+ 列 | 重新运行 EA 生成数据 |

---

## ML/RL 数据准备

### 特征数据质量检查

```python
# 检查缺失值
print(df.isnull().sum())

# 检查特征分布
import matplotlib.pyplot as plt
df[['q_score', 'efficiency', 'rsi']].hist(bins=50, figsize=(12, 4))
plt.show()

# 检查类别平衡
print(f"ACTIVE: {(df['regime_state'] == 0).sum()}")
print(f"STANDBY: {(df['regime_state'] == 1).sum()}")
```

### 为 RL 训练准备数据

```python
# 创建状态空间
state_cols = ['q_score', 'efficiency', 'adx', 'rsi', 'boll_position',
              'regime_type', 'trend_direction', 'volatility_state']

# 创建动作空间标签
df['action'] = df['final_signal']  # -1, 0, 1

# 计算奖励 (需要结合 signals_mt5.csv 的交易结果)
# 简化版：使用下一根 K 线的价格变化
df['reward'] = df['price_change'].shift(-1) * df['final_signal']
```

---

## 常见问题及解决方案

### 问题 1: STANDBY 状态仍有入场

**原因**: 信号过滤逻辑未正确执行

**解决**:
1. 检查 `Ea_run.mq5` 中 Regime Filter 过滤代码
2. 确保信号被过滤时 `source` 被清空

### 问题 2: 低流动性时段有入场

**原因**: SessionQuality 未正确集成

**解决**:
1. 检查 `SQ_Enable = true`
2. 检查时间偏移参数 `BollMR_ServerUTCOffset`

### 问题 3: 真趋势(T+V-B)占比极低

**原因**: 策略在高波动趋势行情中表现不佳

**解决**:
1. 优化 TrendPullback 策略参数
2. 调整 SubType 分类逻辑

### 问题 4: 特征数据不完整

**原因**: 使用旧版 EA 或特征导出未正确配置

**解决**:
1. 确保使用 v2.4.0+ 版本
2. 检查 features.csv 是否有 25+ 列

---

## 优化方向

1. **参数优化**: 使用 Python `regime_param_optimize.py` 优化 Q-Score 参数
2. **策略优化**: 根据信号来源分布，优化表现不佳的策略
3. **时段优化**: 根据 M7 的时段权重，进一步调整交易时段
4. **ML/RL 训练**: 使用扩展特征进行强化学习训练
