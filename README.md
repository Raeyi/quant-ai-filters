# quant-ai-filters

**AI 过滤型量化 多策略交易系统**（Hybrid MQL5 + Python）

这是一个专注于 XAUUSD（黄金）量化交易的个人职业化项目，目标：构建稳定盈利的多策略组合系统，最终积累可审计业绩，走向个人资管/创业。

### 项目概述

- **核心理念**：可插拔多策略 + AI/ML 信号过滤 + 严格风控
- **MQL5 部分**：实盘执行 EA（MT5 平台），支持多策略并行、模块化设计。
- **Python 部分**：高保真回测、策略研究、AI/ML/RL 集成（使用 vectorbt、pandas、LightGBM 等）。
- **主战场**：XAUUSD（黄金），分钟/小时级策略（均值回归、动量、波动率突破）。
- **长期目标**：6-12 个月实现自动化正收益系统 → 18-24 个月积累审计业绩 → 私募/资管。

### 项目结构

- `/Core`, `/Indicators`, `/Strategies`：MQL5 模块（实盘执行）
- `/python/`：Python 研究模块
  - `data/`：数据获取与清洗
  - `indicators/` / `strategies/`：与 MQL5 对齐的迁移版本
  - `ai_filters/`：未来 AI 过滤层
  - `core/`：回测引擎与风控
  - `backtest.py`：主回测脚本

### 安装与运行

#### MQL5 部分

1. 打开 MetaTrader 5 → 文件 → 打开数据文件夹 → MQL5 → Experts
2. 复制本项目文件
3. 编译 `Ea_run.mq5` → 挂载到 XAUUSD 图表

#### Python 部分（回测与研究）

```bash
cd python
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt
# 示例运行回测
python backtest.py
