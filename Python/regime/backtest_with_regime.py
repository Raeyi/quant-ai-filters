"""
Regime-Integrated Backtest - 整合 Regime Filter 的回测

Phase 6 功能：
1. 各 Sub-Type 下策略表现对比
2. Quality Score 过滤效果验证
3. 整体收益评估
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.dates as mdates

from regime import (
    RegimeFilter,
    RegimeFilterParams,
    RegimeState,
    RegimeSubType,
    TransitionMatrix,
    StrategySelector,
    RiskExposureManager,
)
from strategies.boll_mean_reversion import BollMeanReversionStrategy, BollMeanReversionParams
from strategies.trend_pullback import TrendPullbackStrategy, TrendPullbackParams


@dataclass
class BacktestResult:
    """回测结果"""
    # 总体统计
    total_trades: int = 0
    winning_trades: int = 0
    losing_trades: int = 0
    total_pnl: float = 0.0
    total_pnl_pct: float = 0.0
    
    # 风险指标
    max_drawdown: float = 0.0
    max_drawdown_pct: float = 0.0
    sharpe_ratio: float = 0.0
    
    # 分 Regime 统计
    by_regime: Dict = field(default_factory=dict)
    by_subtype: Dict = field(default_factory=dict)
    by_session: Dict = field(default_factory=dict)
    
    # 过滤效果
    trades_filtered_by_q: int = 0
    trades_filtered_by_regime: int = 0


class RegimeIntegratedBacktest:
    """整合 Regime Filter 的回测引擎"""
    
    def __init__(
        self,
        regime_params: Optional[RegimeFilterParams] = None,
        use_regime_filter: bool = True,
    ):
        self.regime_filter = RegimeFilter(regime_params)
        self.strategy_selector = StrategySelector()
        self.risk_manager = RiskExposureManager()
        self.use_regime_filter = use_regime_filter
        
        # 策略实例
        self.boll_strategy: Optional[BollMeanReversionStrategy] = None
        self.trend_strategy: Optional[TrendPullbackStrategy] = None
        
        # 结果
        self.regime_result: Optional[pd.DataFrame] = None
        self.trades: List[Dict] = []
        self.equity_curve: List[float] = []
    
    def run(
        self,
        df: pd.DataFrame,
        df_htf: Optional[pd.DataFrame] = None,
        initial_balance: float = 10000.0,
        lot_size: float = 0.01,
        point: float = 0.01,
    ) -> BacktestResult:
        """
        运行回测
        
        Args:
            df: M5 OHLCV 数据
            df_htf: M15 OHLCV 数据 (用于 TrendPullback)
            initial_balance: 初始资金
            lot_size: 固定手数
            point: 点值
            
        Returns:
            BacktestResult
        """
        # 计算 Regime
        print("Calculating regime indicators...")
        self.regime_result = self.regime_filter.calculate(df)
        
        # 初始化策略
        self.boll_strategy = BollMeanReversionStrategy(
            BollMeanReversionParams(logic_mode="enhanced")
        )
        self.trend_strategy = TrendPullbackStrategy(
            TrendPullbackParams()
        )
        
        # 生成策略信号
        print("Generating strategy signals...")
        boll_signals = self.boll_strategy.generate_signals(df)
        trend_signals = self.trend_strategy.generate_signals(df, df_htf)
        
        # 回测循环
        print("Running backtest...")
        balance = initial_balance
        position = 0  # 1=多, -1=空, 0=无
        entry_price = 0.0
        entry_time = None
        entry_sub_type = None
        
        self.trades = []
        self.equity_curve = [initial_balance]
        
        for i, (idx, row) in enumerate(df.iterrows()):
            if i < 50:  # 预热期
                self.equity_curve.append(balance)
                continue
            
            regime_row = self.regime_result.iloc[i]
            
            # 当前 Regime 信息
            regime_state = regime_row.get("regime_state", RegimeState.STANDBY)
            sub_type = regime_row.get("sub_type", RegimeSubType.UNKNOWN)
            q_score = regime_row.get("q_score", 0.5)
            
            # 检查是否可交易
            if self.use_regime_filter and regime_state != RegimeState.ACTIVE:
                # 如果有持仓，平仓
                if position != 0:
                    close_price = row["close"]
                    pnl = self._calculate_pnl(
                        position, entry_price, close_price, lot_size, point
                    )
                    balance += pnl
                    self.trades.append({
                        "entry_time": entry_time,
                        "exit_time": idx,
                        "direction": position,
                        "entry_price": entry_price,
                        "exit_price": close_price,
                        "pnl": pnl,
                        "sub_type": entry_sub_type,
                        "exit_reason": "regime_standby",
                    })
                    position = 0
                
                self.equity_curve.append(balance)
                continue
            
            # 选择策略
            selection = self.strategy_selector.select_strategy(
                sub_type, 
                self.strategy_selector.get_current_session(idx.hour),
                q_score,
                regime_row.get("trend_direction", 0)
            )
            
            # 获取信号
            boll_sig = boll_signals.iloc[i]
            trend_sig = trend_signals.iloc[i] if i < len(trend_signals) else 0
            
            # 根据选择的策略过滤信号
            active_signal = 0
            if selection.primary_strategy == "TrendPullback":
                active_signal = trend_sig if trend_sig != 0 else 0
            elif selection.primary_strategy == "BollMR":
                active_signal = boll_sig if boll_sig != 0 else 0
            
            # 处理持仓
            if position == 0:
                # 无仓位，检查入场信号
                if active_signal != 0:
                    position = 1 if active_signal > 0 else -1
                    entry_price = row["close"]
                    entry_time = idx
                    entry_sub_type = sub_type
            else:
                # 有仓位，检查出场
                should_exit = self._check_exit(
                    position, row, regime_row, entry_price, lot_size, point
                )
                
                if should_exit:
                    close_price = row["close"]
                    pnl = self._calculate_pnl(
                        position, entry_price, close_price, lot_size, point
                    )
                    balance += pnl
                    self.trades.append({
                        "entry_time": entry_time,
                        "exit_time": idx,
                        "direction": position,
                        "entry_price": entry_price,
                        "exit_price": close_price,
                        "pnl": pnl,
                        "sub_type": entry_sub_type,
                        "exit_reason": should_exit,
                    })
                    position = 0
            
            self.equity_curve.append(balance)
        
        # 计算结果
        return self._calculate_results(initial_balance)
    
    def _calculate_pnl(
        self,
        position: int,
        entry_price: float,
        exit_price: float,
        lot_size: float,
        point: float
    ) -> float:
        """计算盈亏"""
        if position > 0:
            return (exit_price - entry_price) / point * lot_size * 100
        else:
            return (entry_price - exit_price) / point * lot_size * 100
    
    def _check_exit(
        self,
        position: int,
        row: pd.Series,
        regime_row: pd.Series,
        entry_price: float,
        lot_size: float,
        point: float
    ) -> str:
        """检查是否应该出场"""
        close = row["close"]
        sub_type = regime_row.get("sub_type", RegimeSubType.UNKNOWN)
        
        # 基于Sub-Type的止损止盈
        # 简化版本，实际应使用ATR
        atr_estimate = (row["high"] - row["low"])
        sl_mult = regime_row.get("sl_multiplier", 1.0)
        tp_mult = regime_row.get("tp_multiplier", 1.0)
        
        if position > 0:
            # 多头止损
            sl_price = entry_price - atr_estimate * sl_mult
            if close <= sl_price:
                return "stop_loss"
            
            # 多头止盈
            tp_price = entry_price + atr_estimate * tp_mult
            if close >= tp_price:
                return "take_profit"
        else:
            # 空头止损
            sl_price = entry_price + atr_estimate * sl_mult
            if close >= sl_price:
                return "stop_loss"
            
            # 空头止盈
            tp_price = entry_price - atr_estimate * tp_mult
            if close <= tp_price:
                return "take_profit"
        
        return ""
    
    def _calculate_results(self, initial_balance: float) -> BacktestResult:
        """计算回测结果"""
        result = BacktestResult()
        
        if not self.trades:
            return result
        
        trades_df = pd.DataFrame(self.trades)
        
        # 总体统计
        result.total_trades = len(trades_df)
        result.winning_trades = int((trades_df["pnl"] > 0).sum())
        result.losing_trades = int((trades_df["pnl"] <= 0).sum())
        result.total_pnl = trades_df["pnl"].sum()
        result.total_pnl_pct = result.total_pnl / initial_balance * 100
        
        # 最大回撤
        equity = pd.Series(self.equity_curve)
        peak = equity.expanding().max()
        drawdown = (equity - peak) / peak * 100
        result.max_drawdown_pct = drawdown.min()
        
        # Sharpe Ratio
        if len(trades_df) > 1:
            returns = trades_df["pnl"] / initial_balance * 100
            if returns.std() > 0:
                result.sharpe_ratio = returns.mean() / returns.std() * np.sqrt(252)
        
        # 按 Sub-Type 分组
        for sub_type in trades_df["sub_type"].unique():
            if sub_type:
                subset = trades_df[trades_df["sub_type"] == sub_type]
                result.by_subtype[str(sub_type)] = {
                    "count": len(subset),
                    "win_rate": (subset["pnl"] > 0).mean() * 100,
                    "total_pnl": subset["pnl"].sum(),
                    "avg_pnl": subset["pnl"].mean(),
                }
        
        return result
    
    def plot_results(
        self,
        df: pd.DataFrame,
        output_path: str
    ):
        """绘制回测结果"""
        fig, axes = plt.subplots(3, 1, figsize=(14, 10), sharex=True)
        
        # 限制显示范围
        display_limit = 1000
        if len(df) > display_limit:
            df_plot = df.iloc[-display_limit:]
            regime_plot = self.regime_result.iloc[-display_limit:]
            equity_plot = self.equity_curve[-display_limit:]
        else:
            df_plot = df
            regime_plot = self.regime_result
            equity_plot = self.equity_curve
        
        # 1. 价格 + Regime 背景
        ax1 = axes[0]
        ax1.plot(df_plot.index, df_plot["close"], "k-", linewidth=0.8)
        
        for state in [RegimeState.ACTIVE, RegimeState.STANDBY]:
            mask = regime_plot["regime_state"] == state
            color = "green" if state == RegimeState.ACTIVE else "red"
            ax1.fill_between(
                df_plot.index, df_plot["low"], df_plot["high"],
                where=mask, alpha=0.2, color=color, label=state.value
            )
        
        ax1.set_ylabel("Price")
        ax1.legend(loc="upper left", fontsize=8)
        ax1.set_title("Price with Regime State")
        
        # 2. 资金曲线
        ax2 = axes[1]
        ax2.plot(df_plot.index, equity_plot, "b-", linewidth=1)
        ax2.fill_between(
            df_plot.index, equity_plot[0], equity_plot,
            alpha=0.3, color="blue"
        )
        ax2.set_ylabel("Equity")
        ax2.set_title("Equity Curve")
        
        # 3. Q Score
        ax3 = axes[2]
        ax3.plot(regime_plot.index, regime_plot["q_score"], "g-", linewidth=0.8)
        ax3.axhline(y=0.5, color="r", linestyle="--", label="Standby Threshold")
        ax3.set_ylabel("Q Score")
        ax3.set_ylim(0, 1)
        ax3.legend(loc="upper left", fontsize=8)
        
        plt.tight_layout()
        plt.savefig(output_path, dpi=150, bbox_inches="tight")
        plt.close()
        print(f"Saved backtest results to {output_path}")


def main():
    parser = argparse.ArgumentParser(description="Regime-Integrated Backtest")
    parser.add_argument(
        "--data",
        type=str,
        default="E:/mt5_test_datas/mt5/XAUUSD_M5_202506020100_202601302350.csv",
        help="Path to M5 OHLCV data"
    )
    parser.add_argument(
        "--output",
        type=str,
        default="data/regime_backtest",
        help="Output directory"
    )
    parser.add_argument(
        "--no-regime",
        action="store_true",
        help="Disable regime filter for comparison"
    )
    args = parser.parse_args()
    
    # 加载数据
    print(f"Loading data from {args.data}")
    
    with open(args.data, "r") as f:
        first_line = f.readline()
    
    if "<DATE>" in first_line or "\t" in first_line:
        df = pd.read_csv(
            args.data,
            sep="\t",
            skiprows=1,
            names=["date", "time", "open", "high", "low", "close", "tickvol", "vol", "spread"]
        )
        df["datetime"] = pd.to_datetime(df["date"] + " " + df["time"])
        df = df.set_index("datetime").drop(columns=["date", "time"])
    else:
        df = pd.read_csv(args.data, parse_dates=["time"]).set_index("time")
    
    df = df.sort_index()
    print(f"Loaded {len(df)} bars")
    
    # 创建输出目录
    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # 运行回测
    backtest = RegimeIntegratedBacktest(
        use_regime_filter=not args.no_regime
    )
    
    result = backtest.run(df)
    
    # 打印结果
    print("\n=== Backtest Results ===")
    print(f"Total Trades: {result.total_trades}")
    print(f"Win Rate: {result.winning_trades / max(result.total_trades, 1) * 100:.1f}%")
    print(f"Total PnL: ${result.total_pnl:.2f} ({result.total_pnl_pct:.2f}%)")
    print(f"Max Drawdown: {result.max_drawdown_pct:.2f}%")
    print(f"Sharpe Ratio: {result.sharpe_ratio:.2f}")
    
    print("\n=== By Sub-Type ===")
    for st, stats in result.by_subtype.items():
        print(f"{st}: {stats['count']} trades, {stats['win_rate']:.1f}% win, ${stats['total_pnl']:.2f}")
    
    # 绘图
    plot_path = output_dir / "backtest_result.png"
    backtest.plot_results(df, str(plot_path))
    
    # 保存结果
    result_json = output_dir / "backtest_result.json"
    with open(result_json, "w") as f:
        json.dump({
            "total_trades": result.total_trades,
            "win_rate": result.winning_trades / max(result.total_trades, 1) * 100,
            "total_pnl": result.total_pnl,
            "total_pnl_pct": result.total_pnl_pct,
            "max_drawdown_pct": result.max_drawdown_pct,
            "sharpe_ratio": result.sharpe_ratio,
            "by_subtype": result.by_subtype,
        }, f, indent=2, default=str)
    print(f"Saved results to {result_json}")
    
    return result


if __name__ == "__main__":
    main()
