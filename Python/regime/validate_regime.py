"""
Regime Filter 验证脚本

验证 Phase 1 功能：
1. Regime 识别准确性
2. Q_score 分布
3. 与策略信号的关系
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Optional

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.dates as mdates

from regime import (
    RegimeFilter,
    RegimeFilterParams,
    RegimeState,
    RegimeType,
    VolatilityState,
)


def load_data(data_path: str) -> pd.DataFrame:
    """加载数据"""
    # 先读取前几行判断格式
    with open(data_path, "r") as f:
        first_line = f.readline()
    
    # MT5 导出格式检测
    if "<DATE>" in first_line or "\t" in first_line:
        # MT5 History Center 导出格式
        df = pd.read_csv(
            data_path,
            sep="\t",
            skiprows=1,
            names=["date", "time", "open", "high", "low", "close", "tickvol", "vol", "spread"]
        )
        df["datetime"] = pd.to_datetime(df["date"] + " " + df["time"])
        df = df.set_index("datetime")
        df = df.drop(columns=["date", "time"])
    else:
        # 标准 CSV 格式
        df = pd.read_csv(data_path)
        
        # 尝试不同的时间列名
        time_cols = ["time", "datetime", "timestamp", "date"]
        for col in time_cols:
            if col in df.columns:
                df[col] = pd.to_datetime(df[col])
                df = df.set_index(col)
                break
        
        # 列名标准化
        col_map = {
            "OPEN": "open", "HIGH": "high", "LOW": "low", "CLOSE": "close",
            "Open": "open", "High": "high", "Low": "low", "Close": "close"
        }
        df = df.rename(columns=col_map)
    
    df = df.sort_index()
    
    # 确保必要列存在
    required = ["open", "high", "low", "close"]
    for col in required:
        if col not in df.columns:
            raise ValueError(f"Missing required column: {col}")
    
    return df


def analyze_regime_distribution(result: pd.DataFrame) -> dict:
    """分析 Regime 分布"""
    total = len(result)
    
    stats = {
        "total_bars": total,
        "regime_type": {
            "trend": int((result["regime_type"] == RegimeType.TREND).sum()),
            "range": int((result["regime_type"] == RegimeType.RANGE).sum()),
        },
        "volatility_state": {
            "low": int((result["volatility_state"] == VolatilityState.LOW).sum()),
            "normal": int((result["volatility_state"] == VolatilityState.NORMAL).sum()),
            "high": int((result["volatility_state"] == VolatilityState.HIGH).sum()),
        },
        "regime_state": {
            "active": int((result["regime_state"] == RegimeState.ACTIVE).sum()),
            "standby": int((result["regime_state"] == RegimeState.STANDBY).sum()),
            "transition": int((result["regime_state"] == RegimeState.TRANSITION).sum()),
        },
        "q_score": {
            "mean": float(result["q_score"].mean()),
            "std": float(result["q_score"].std()),
            "min": float(result["q_score"].min()),
            "max": float(result["q_score"].max()),
            "median": float(result["q_score"].median()),
        },
        "trend_strength": {
            "mean": float(result["trend_strength"].mean()),
            "std": float(result["trend_strength"].std()),
        },
        "efficiency": {
            "mean": float(result["efficiency"].mean()),
            "std": float(result["efficiency"].std()),
        },
        "false_breakout_rate": {
            "mean": float(result["false_breakout_rate"].mean()),
            "std": float(result["false_breakout_rate"].std()),
        },
    }
    
    # 计算百分比
    stats["regime_type_percent"] = {
        k: round(v / total * 100, 1) for k, v in stats["regime_type"].items()
    }
    stats["volatility_state_percent"] = {
        k: round(v / total * 100, 1) for k, v in stats["volatility_state"].items()
    }
    stats["regime_state_percent"] = {
        k: round(v / total * 100, 1) for k, v in stats["regime_state"].items()
    }
    
    return stats


def plot_regime_overview(
    df: pd.DataFrame,
    result: pd.DataFrame,
    output_path: str
):
    """绘制 Regime 概览图"""
    fig, axes = plt.subplots(5, 1, figsize=(14, 12), sharex=True)
    
    # 限制显示范围（最近1000根K线）
    display_limit = 1000
    if len(df) > display_limit:
        df = df.iloc[-display_limit:]
        result = result.iloc[-display_limit:]
    
    # 1. 价格走势 + Regime 背景
    ax1 = axes[0]
    ax1.plot(df.index, df["close"], "k-", linewidth=0.8, label="Close")
    
    # 为不同 Regime 状态着色
    for state, color in [
        (RegimeState.ACTIVE, "green"),
        (RegimeState.STANDBY, "red"),
        (RegimeState.TRANSITION, "yellow"),
    ]:
        mask = result["regime_state"] == state
        ax1.fill_between(
            df.index, df["low"], df["high"],
            where=mask, alpha=0.3, color=color, label=state.value
        )
    
    ax1.set_ylabel("Price")
    ax1.legend(loc="upper left", fontsize=8)
    ax1.set_title("Price with Regime State")
    
    # 2. Q_score
    ax2 = axes[1]
    ax2.plot(result.index, result["q_score"], "b-", linewidth=0.8)
    ax2.axhline(y=0.5, color="r", linestyle="--", label="Standby Threshold")
    ax2.axhline(y=0.6, color="g", linestyle="--", label="Active Threshold")
    ax2.fill_between(
        result.index, 0, result["q_score"],
        where=result["q_score"] >= 0.5, alpha=0.3, color="green"
    )
    ax2.fill_between(
        result.index, 0, result["q_score"],
        where=result["q_score"] < 0.5, alpha=0.3, color="red"
    )
    ax2.set_ylabel("Q Score")
    ax2.set_ylim(0, 1)
    ax2.legend(loc="upper left", fontsize=8)
    
    # 3. Trend Strength + Efficiency
    ax3 = axes[2]
    ax3.plot(result.index, result["trend_strength"], "b-", linewidth=0.8, label="Trend Strength")
    ax3.plot(result.index, result["efficiency"], "g-", linewidth=0.8, label="Efficiency")
    ax3.set_ylabel("Strength / Efficiency")
    ax3.set_ylim(0, 1)
    ax3.legend(loc="upper left", fontsize=8)
    
    # 4. False Breakout Rate
    ax4 = axes[3]
    ax4.plot(result.index, result["false_breakout_rate"], "r-", linewidth=0.8)
    ax4.axhline(y=0.3, color="orange", linestyle="--", label="Warning Level")
    ax4.set_ylabel("False Breakout Rate")
    ax4.set_ylim(0, 1)
    ax4.legend(loc="upper left", fontsize=8)
    
    # 5. Scale Multiplier
    ax5 = axes[4]
    ax5.plot(result.index, result["scale_multiplier"], "purple", linewidth=0.8)
    ax5.axhline(y=1.0, color="gray", linestyle="--")
    ax5.set_ylabel("Scale Multiplier")
    ax5.set_ylim(0, 1.5)
    
    # X轴格式化
    ax5.xaxis.set_major_formatter(mdates.DateFormatter("%Y-%m-%d %H:%M"))
    ax5.xaxis.set_major_locator(mdates.DayLocator(interval=1))
    plt.xticks(rotation=45)
    
    plt.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches="tight")
    plt.close()
    print(f"Saved regime overview to {output_path}")


def analyze_regime_performance(
    df: pd.DataFrame,
    result: pd.DataFrame
) -> dict:
    """
    分析不同 Regime 下的价格表现
    
    验证 Regime 识别是否有效：
    - TREND 状态下应该有明确方向性
    - RANGE 状态下应该表现为震荡
    """
    # 计算未来N根K线的收益
    returns_5 = df["close"].pct_change(5).shift(-5)
    returns_10 = df["close"].pct_change(10).shift(-10)
    
    performance = {}
    
    for regime in [RegimeType.TREND, RegimeType.RANGE]:
        mask = result["regime_type"] == regime
        
        if mask.sum() == 0:
            continue
        
        # 绝对收益（方向性）
        abs_ret_5 = returns_5[mask].abs().mean()
        abs_ret_10 = returns_10[mask].abs().mean()
        
        # 方向一致性（与趋势方向一致的比例）
        trend_dir = result.loc[mask, "trend_direction"]
        actual_dir = np.sign(df["close"].diff(5).shift(-5).loc[mask])
        direction_match = (trend_dir == actual_dir).mean()
        
        # 波动率
        volatility = (df["high"] - df["low"]) / df["close"]
        avg_vol = volatility[mask].mean()
        
        performance[regime.value] = {
            "count": int(mask.sum()),
            "abs_return_5bar": float(abs_ret_5) if not np.isnan(abs_ret_5) else 0,
            "abs_return_10bar": float(abs_ret_10) if not np.isnan(abs_ret_10) else 0,
            "direction_match_rate": float(direction_match) if not np.isnan(direction_match) else 0,
            "avg_volatility": float(avg_vol),
        }
    
    # 分析 Q_score 分位数下的表现
    q_quantiles = result["q_score"].quantile([0.25, 0.5, 0.75])
    
    for q_level, q_val in [("low", q_quantiles[0.25]), ("mid", q_quantiles[0.5]), ("high", q_quantiles[0.75])]:
        if q_level == "low":
            mask = result["q_score"] <= q_val
        elif q_level == "high":
            mask = result["q_score"] >= q_val
        else:
            continue
        
        abs_ret = returns_5[mask].abs().mean()
        performance[f"q_{q_level}"] = {
            "count": int(mask.sum()),
            "abs_return_5bar": float(abs_ret) if not np.isnan(abs_ret) else 0,
        }
    
    return performance


def main():
    parser = argparse.ArgumentParser(description="Validate Regime Filter")
    parser.add_argument(
        "--data",
        type=str,
        default="data/XAUUSD_M5.csv",
        help="Path to OHLCV data file"
    )
    parser.add_argument(
        "--output",
        type=str,
        default="data/regime_validation",
        help="Output directory"
    )
    parser.add_argument(
        "--config",
        type=str,
        default=None,
        help="Path to config JSON (optional)"
    )
    args = parser.parse_args()
    
    # 加载数据
    print(f"Loading data from {args.data}")
    df = load_data(args.data)
    print(f"Loaded {len(df)} bars from {df.index[0]} to {df.index[-1]}")
    
    # 加载配置
    params = RegimeFilterParams()
    if args.config:
        with open(args.config) as f:
            config = json.load(f)
        # 可以从配置更新参数
        print(f"Loaded config from {args.config}")
    
    # 创建 Regime Filter
    regime_filter = RegimeFilter(params)
    
    # 计算 Regime
    print("Calculating regime indicators...")
    result = regime_filter.calculate(df)
    
    # 创建输出目录
    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # 分析分布
    print("\nAnalyzing regime distribution...")
    stats = analyze_regime_distribution(result)
    
    print("\n=== Regime Distribution ===")
    print(f"Regime Type: {stats['regime_type_percent']}")
    print(f"Volatility State: {stats['volatility_state_percent']}")
    print(f"Regime State: {stats['regime_state_percent']}")
    print(f"\nQ Score: mean={stats['q_score']['mean']:.3f}, std={stats['q_score']['std']:.3f}")
    print(f"Trend Strength: mean={stats['trend_strength']['mean']:.3f}")
    print(f"Efficiency: mean={stats['efficiency']['mean']:.3f}")
    print(f"False Breakout Rate: mean={stats['false_breakout_rate']['mean']:.3f}")
    
    # 分析表现
    print("\nAnalyzing regime performance...")
    performance = analyze_regime_performance(df, result)
    
    print("\n=== Regime Performance ===")
    for regime, metrics in performance.items():
        print(f"\n{regime}:")
        for k, v in metrics.items():
            print(f"  {k}: {v:.4f}" if isinstance(v, float) else f"  {k}: {v}")
    
    # 绘图
    print("\nGenerating plots...")
    plot_path = output_dir / "regime_overview.png"
    plot_regime_overview(df, result, str(plot_path))
    
    # 保存结果
    result_csv = output_dir / "regime_result.csv"
    result.to_csv(result_csv)
    print(f"Saved regime results to {result_csv}")
    
    stats_json = output_dir / "regime_stats.json"
    with open(stats_json, "w") as f:
        json.dump({
            "distribution": stats,
            "performance": performance
        }, f, indent=2, default=str)
    print(f"Saved statistics to {stats_json}")
    
    print("\n=== Validation Complete ===")
    
    return stats, performance


if __name__ == "__main__":
    main()
