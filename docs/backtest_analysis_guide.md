# MT5 回测数据分析指南

## 快速开始

### 方法 1: Python 分析（推荐）

```bash
cd Python
python analyze_backtest.py --signals "C:\Users\ruiwe\AppData\Roaming\MetaQuotes\Terminal\Common\Files\signals_mt5.csv"
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

### features.csv

| 列名 | 说明 |
|------|------|
| time | 时间戳 |
| close | 收盘价 |
| boll_u | 布林带上轨 |
| boll_l | 布林带下轨 |
| atr | ATR 值 |

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

---

## 诊断清单

| 检查项 | 正常值 | 异常处理 |
|--------|--------|----------|
| STANDBY 入场比例 | < 5% | 检查 Regime Filter 是否生效 |
| 低流动性时段入场 | 0% | 检查 SessionQuality 是否生效 |
| ACTIVE 入场比例 | > 80% | 检查信号过滤逻辑 |
| Q-Score 均值 | > 0.4 | 调整 Q-Score 参数 |
| 入场时 Q-Score > 0.5 | > 50% | 提高入场阈值 |

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

---

## 优化方向

1. **参数优化**: 使用 Python `regime_param_optimize.py` 优化 Q-Score 参数
2. **策略优化**: 根据信号来源分布，优化表现不佳的策略
3. **时段优化**: 根据 M7 的时段权重，进一步调整交易时段
