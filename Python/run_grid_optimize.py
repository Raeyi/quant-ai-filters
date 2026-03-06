# -*- coding: utf-8 -*-
"""
MT5策略网格参数优化脚本 (GPU加速版)
- 完整对齐MQL5三个策略: BollMR, TrendPullback, DonchianBreakout
- 使用Numba进行GPU/CPU并行加速
- 输出优化结果和相关性与稳定性分析

使用方法:
1. 安装依赖: pip install numpy pandas numba scipy matplotlib
2. 导出MT5数据到 data/ 目录 (或直接连接MT5)
3. 运行优化:
    # 完整优化（包含RF和风控参数）
    python run_grid_optimize.py --strategy bollmr --data data.csv --output results

    # 仅优化核心策略参数（快速模式）
    python run_grid_optimize.py --strategy bollmr --data data.csv --output results --quick

    # 不包含RF过滤参数
    python run_grid_optimize.py --strategy bollmr --data data.csv --output results --no-rf

    # 包含公用风控参数
    python run_grid_optimize.py --strategy bollmr --data data.csv --output results --common-risk

    # 完整优化（包含所有参数）
    python run_grid_optimize.py --strategy donchian --data data.csv --output results --common-risk

4. 查看结果: results/strategy_name_timestamp/

输出文件:
- optimization_results.csv: 所有参数组合的结果
- analysis_report.txt: 分析报告
- best_params.json: 推荐参数
"""

import os
import sys
import json
import random
import argparse
import warnings
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Tuple, Optional
from dataclasses import dataclass, asdict
import itertools

import numpy as np
import pandas as pd
from numba import jit, prange, set_num_threads
from numba import cuda
import matplotlib
matplotlib.use('Agg')  # 非交互式后端
import matplotlib.pyplot as plt
from scipy import stats

# 禁用输出缓冲，实时打印进度
sys.stdout.reconfigure(line_buffering=True) if hasattr(sys.stdout, 'reconfigure') else None

warnings.filterwarnings('ignore')

# 默认参数
DEFAULT_POINT = 0.00001  # 黄金 XAUUSD


# ============================================================
# 技术指标计算 (Numba加速)
# ============================================================

@jit(nopython=True, cache=True)
def calc_sma(data: np.ndarray, period: int) -> np.ndarray:
    """简单移动平均"""
    n = len(data)
    sma = np.full(n, np.nan)
    if n < period:
        return sma
    sma[period - 1] = np.mean(data[:period])
    for i in range(period, n):
        sma[i] = sma[i - 1] + (data[i] - data[i - period]) / period
    return sma


@jit(nopython=True, cache=True)
def calc_ema(data: np.ndarray, period: int) -> np.ndarray:
    """指数移动平均"""
    n = len(data)
    ema = np.full(n, np.nan)
    if n < period:
        return ema
    alpha = 2.0 / (period + 1)
    ema[period - 1] = np.mean(data[:period])
    for i in range(period, n):
        ema[i] = alpha * data[i] + (1 - alpha) * ema[i - 1]
    return ema


@jit(nopython=True, cache=True)
def calc_atr(high: np.ndarray, low: np.ndarray, close: np.ndarray, period: int) -> np.ndarray:
    """ATR计算"""
    n = len(high)
    atr = np.full(n, np.nan)
    if n < period + 1:
        return atr
    
    tr = np.zeros(n)
    for i in range(1, n):
        tr[i] = max(high[i] - low[i],
                   abs(high[i] - close[i - 1]),
                   abs(low[i] - close[i - 1]))
    
    atr[period] = np.mean(tr[1:period + 1])
    alpha = 1.0 / period
    for i in range(period + 1, n):
        atr[i] = atr[i - 1] * (1 - alpha) + tr[i] * alpha
    return atr


@jit(nopython=True, cache=True)
def calc_bollinger(close: np.ndarray, period: int, std_dev: float) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """布林带计算"""
    n = len(close)
    middle = calc_sma(close, period)
    upper = np.full(n, np.nan)
    lower = np.full(n, np.nan)
    
    for i in range(period - 1, n):
        if not np.isnan(middle[i]):
            std = np.std(close[i - period + 1:i + 1])
            upper[i] = middle[i] + std_dev * std
            lower[i] = middle[i] - std_dev * std
    return upper, middle, lower


@jit(nopython=True, cache=True)
def calc_donchian(high: np.ndarray, low: np.ndarray, period: int) -> Tuple[np.ndarray, np.ndarray]:
    """Donchian通道计算"""
    n = len(high)
    upper = np.full(n, np.nan)
    lower = np.full(n, np.nan)
    
    for i in range(period - 1, n):
        upper[i] = np.max(high[i - period + 1:i + 1])
        lower[i] = np.min(low[i - period + 1:i + 1])
    return upper, lower


@jit(nopython=True, cache=True)
def calc_adx(high: np.ndarray, low: np.ndarray, close: np.ndarray, period: int) -> np.ndarray:
    """ADX计算"""
    n = len(high)
    adx = np.full(n, np.nan)
    
    if n < period + 2:
        return adx
    
    plus_dm = np.zeros(n)
    minus_dm = np.zeros(n)
    tr = np.zeros(n)
    
    for i in range(1, n):
        up_move = high[i] - high[i - 1]
        down_move = low[i - 1] - low[i]
        
        plus_dm[i] = up_move if up_move > down_move and up_move > 0 else 0
        minus_dm[i] = down_move if down_move > up_move and down_move > 0 else 0
        tr[i] = max(high[i] - low[i],
                   abs(high[i] - close[i - 1]),
                   abs(low[i] - close[i - 1]))
    
    # EMA平滑
    atr_smooth = np.zeros(n)
    plus_dm_smooth = np.zeros(n)
    minus_dm_smooth = np.zeros(n)
    
    atr_smooth[period] = np.sum(tr[1:period + 1])
    plus_dm_smooth[period] = np.sum(plus_dm[1:period + 1])
    minus_dm_smooth[period] = np.sum(minus_dm[1:period + 1])
    
    alpha = 1.0 / period
    for i in range(period + 1, n):
        atr_smooth[i] = atr_smooth[i - 1] * (1 - alpha) + tr[i] * alpha
        plus_dm_smooth[i] = plus_dm_smooth[i - 1] * (1 - alpha) + plus_dm[i] * alpha
        minus_dm_smooth[i] = minus_dm_smooth[i - 1] * (1 - alpha) + minus_dm[i] * alpha
    
    for i in range(period + 1, n):
        if atr_smooth[i] > 0:
            pdi = 100 * plus_dm_smooth[i] / atr_smooth[i]
            mdi = 100 * minus_dm_smooth[i] / atr_smooth[i]
            if pdi + mdi > 0:
                adx[i] = 100 * abs(pdi - mdi) / (pdi + mdi)
    
    return adx


@jit(nopython=True, cache=True)
def calc_rsi(close: np.ndarray, period: int) -> np.ndarray:
    """计算RSI指标"""
    n = len(close)
    rsi = np.full(n, np.nan)
    
    if n < period + 1:
        return rsi
    
    gains = np.zeros(n)
    losses = np.zeros(n)
    
    for i in range(1, n):
        diff = close[i] - close[i - 1]
        if diff > 0:
            gains[i] = diff
        else:
            losses[i] = -diff
    
    avg_gain = np.mean(gains[1:period + 1])
    avg_loss = np.mean(losses[1:period + 1])
    
    if avg_loss == 0:
        rsi[period] = 100.0
    else:
        rs = avg_gain / avg_loss
        rsi[period] = 100.0 - (100.0 / (1.0 + rs))
    
    for i in range(period + 1, n):
        avg_gain = (avg_gain * (period - 1) + gains[i]) / period
        avg_loss = (avg_loss * (period - 1) + losses[i]) / period
        
        if avg_loss == 0:
            rsi[i] = 100.0
        else:
            rs = avg_gain / avg_loss
            rsi[i] = 100.0 - (100.0 / (1.0 + rs))
    
    return rsi


# ============================================================
# 回测核心函数 (Numba加速)
# ============================================================

@jit(nopython=True, cache=True)
def backtest_bollmr_numba(
    high: np.ndarray, low: np.ndarray, close: np.ndarray,
    boll_upper: np.ndarray, boll_middle: np.ndarray, boll_lower: np.ndarray,
    atr: np.ndarray, atr_avg: np.ndarray, ma: np.ndarray,
    struct_sl_mult: float, vol_sl_mult: float, vol_limit: float,
    point: float, start_idx: int
) -> Tuple[float, int, float, float, float]:
    """BollMR策略基础回测"""
    n = len(close)
    equity = 10000.0
    max_equity = equity
    trades = 0
    wins = 0
    total_profit = 0.0
    total_loss = 0.0
    max_dd = 0.0
    
    position = 0
    entry_price = 0.0
    sl = 0.0
    
    for idx in range(start_idx, n):
        if position != 0:
            # 止损检查
            if position == 1 and low[idx] <= sl:
                pnl = (sl - entry_price) / point * 100
                equity += pnl
                total_loss += abs(pnl)
                trades += 1
                position = 0
            elif position == -1 and high[idx] >= sl:
                pnl = (entry_price - sl) / point * 100
                equity += pnl
                total_loss += abs(pnl)
                trades += 1
                position = 0
        
        if position == 0:
            if np.isnan(boll_upper[idx]) or np.isnan(atr[idx]):
                continue
            
            vol_ok = atr[idx] <= atr_avg[idx] * vol_limit
            
            # 多头入场
            if vol_ok and close[idx - 1] > boll_lower[idx - 1]:
                struct_sl = boll_lower[idx - 1] - atr[idx] * struct_sl_mult
                vol_sl = close[idx] - atr[idx] * vol_sl_mult
                sl = min(struct_sl, vol_sl)
                position = 1
                entry_price = close[idx]
            
            # 空头入场
            elif vol_ok and close[idx - 1] < boll_upper[idx - 1]:
                struct_sl = boll_upper[idx - 1] + atr[idx] * struct_sl_mult
                vol_sl = close[idx] + atr[idx] * vol_sl_mult
                sl = max(struct_sl, vol_sl)
                position = -1
                entry_price = close[idx]
        
        max_equity = max(max_equity, equity)
        max_dd = max(max_dd, (max_equity - equity) / max_equity * 100)
    
    # 强制平仓
    if position != 0:
        pnl = (close[-1] - entry_price) * position / point * 100
        equity += pnl
        trades += 1
        if pnl > 0:
            wins += 1
            total_profit += pnl
        else:
            total_loss += abs(pnl)
    
    profit_factor = total_profit / total_loss if total_loss > 0 else 0
    win_rate = wins / trades * 100 if trades > 0 else 0
    
    return equity - 10000.0, trades, profit_factor, max_dd, win_rate


@jit(nopython=True, cache=True)
def backtest_bollmr_enhanced_numba(
    high: np.ndarray, low: np.ndarray, close: np.ndarray,
    boll_upper: np.ndarray, boll_middle: np.ndarray, boll_lower: np.ndarray,
    atr: np.ndarray, atr_avg: np.ndarray, ma: np.ndarray, rsi: np.ndarray,
    struct_sl_mult: float, vol_sl_mult: float, vol_limit: float,
    ma_period: int, slope_abs: int,
    entry_mode: int,
    enable_rsi: bool, rsi_overbought: float, rsi_oversold: float,
    enable_partial: bool, mid_atr_tp1: float, mid_atr_tp2: float,
    partial_ratio1: float, partial_ratio2: float,
    max_holding_bars: int, cooldown_bars: int,
    max_losing_streak: int, cooldown_after_loss: int,
    enable_regime_rf: bool, adx: np.ndarray,
    q_score_standby: float, adx_trend_threshold: float,
    point: float, start_idx: int
) -> Tuple[float, int, float, float, float]:
    """BollMR策略回测核心（增强版）"""
    n = len(close)
    equity = 10000.0
    max_equity = equity
    trades = 0
    wins = 0
    total_profit = 0.0
    total_loss = 0.0
    max_dd = 0.0
    
    position = 0
    entry_price = 0.0
    entry_idx = 0
    sl = 0.0
    remaining_volume = 1.0
    exit_stage = 0
    
    losing_streak = 0
    cooldown_counter = 0
    
    for idx in range(start_idx, n):
        if cooldown_counter > 0:
            cooldown_counter -= 1
            continue
        
        # 出场检查
        if position != 0:
            holding_bars = idx - entry_idx
            
            if position == 1 and low[idx] <= sl:
                pnl = (sl - entry_price) / point * 100 * remaining_volume
                equity += pnl
                total_loss += abs(pnl)
                trades += 1
                losing_streak += 1
                if losing_streak >= max_losing_streak and max_losing_streak > 0:
                    cooldown_counter = cooldown_after_loss
                position = 0
                remaining_volume = 1.0
            elif position == -1 and high[idx] >= sl:
                pnl = (entry_price - sl) / point * 100 * remaining_volume
                equity += pnl
                total_loss += abs(pnl)
                trades += 1
                losing_streak += 1
                if losing_streak >= max_losing_streak and max_losing_streak > 0:
                    cooldown_counter = cooldown_after_loss
                position = 0
                remaining_volume = 1.0
            elif max_holding_bars > 0 and holding_bars >= max_holding_bars:
                pnl = (close[idx] - entry_price) * position / point * 100 * remaining_volume
                equity += pnl
                trades += 1
                if pnl > 0:
                    wins += 1
                    total_profit += pnl
                    losing_streak = 0
                else:
                    total_loss += abs(pnl)
                    losing_streak += 1
                position = 0
                remaining_volume = 1.0
            elif enable_partial and not np.isnan(boll_middle[idx]) and not np.isnan(atr[idx]):
                atr_val = atr[idx]
                mid_ref = boll_middle[idx - 1] if idx > 0 else boll_middle[idx]
                
                if position == 1:
                    if exit_stage == 0 and close[idx] >= mid_ref + atr_val * mid_atr_tp1:
                        exit_vol = remaining_volume * partial_ratio1
                        pnl = (close[idx] - entry_price) / point * 100 * exit_vol
                        equity += pnl
                        if pnl > 0:
                            wins += 1
                            total_profit += pnl
                        else:
                            total_loss += abs(pnl)
                        trades += 1
                        remaining_volume -= exit_vol
                        exit_stage = 1
                    elif exit_stage == 1 and close[idx] >= mid_ref + atr_val * mid_atr_tp2:
                        exit_vol = remaining_volume * partial_ratio2
                        pnl = (close[idx] - entry_price) / point * 100 * exit_vol
                        equity += pnl
                        if pnl > 0:
                            wins += 1
                            total_profit += pnl
                        else:
                            total_loss += abs(pnl)
                        trades += 1
                        remaining_volume -= exit_vol
                        exit_stage = 2
        
        # 入场检查
        if position == 0 and idx >= max(2, ma_period + 1):
            c2, c1 = close[idx - 2], close[idx - 1]
            bl2, bl1 = boll_lower[idx - 2], boll_lower[idx - 1]
            bu2, bu1 = boll_upper[idx - 2], boll_upper[idx - 1]
            bm1 = boll_middle[idx - 1]
            bm2 = boll_middle[idx - 2]
            l2, h2 = low[idx - 2], high[idx - 2]
            
            if (np.isnan(bl2) or np.isnan(bl1) or np.isnan(bu2) or np.isnan(bu1) or
                np.isnan(bm1) or np.isnan(atr[idx]) or np.isnan(atr_avg[idx])):
                continue
            
            vol_ok = atr[idx] <= atr_avg[idx] * vol_limit
            atr_val = atr[idx]
            
            ma0 = ma[idx]
            ma10 = ma[idx - 10] if idx >= 10 else ma[0]
            if ma0 == 0 or ma10 == 0:
                continue
            
            slope = abs(ma0 - ma10) / (10.0 * point)
            trend_long_ok = (ma0 > ma10) and (slope <= slope_abs)
            trend_short_ok = (ma0 < ma10) and (slope <= slope_abs)
            
            rsi_ok_long = True
            rsi_ok_short = True
            if enable_rsi and not np.isnan(rsi[idx]):
                rsi_val = rsi[idx]
                rsi_ok_long = rsi_val <= rsi_oversold
                rsi_ok_short = rsi_val >= rsi_overbought
            
            # Regime Filter
            regime_ok_long = True
            regime_ok_short = True
            if enable_regime_rf and adx[idx] > 0:
                adx_val = adx[idx]
                regime_ok_long = adx_val >= adx_trend_threshold
                regime_ok_short = adx_val >= adx_trend_threshold
            
            middle_up = bm1 >= bm2
            middle_down = bm1 <= bm2
            
            long_signal = False
            short_signal = False
            
            if entry_mode == 0:
                if vol_ok and trend_long_ok and rsi_ok_long and regime_ok_long:
                    long_signal = (c2 < bl2 and c1 > bl1 and c1 <= bm1 and middle_up)
                if vol_ok and trend_short_ok and rsi_ok_short and regime_ok_short:
                    short_signal = (c2 > bu2 and c1 < bu1 and c1 >= bm1 and middle_down)
            elif entry_mode == 1:
                if vol_ok and trend_long_ok and rsi_ok_long and regime_ok_long:
                    wick_break = l2 < bl2
                    close_recover = c1 > bl1
                    long_signal = (wick_break and close_recover and c1 <= bm1 and middle_up)
                if vol_ok and trend_short_ok and rsi_ok_short and regime_ok_short:
                    wick_break = h2 > bu2
                    close_recover = c1 < bu1
                    short_signal = (wick_break and close_recover and c1 >= bm1 and middle_down)
            elif entry_mode == 2:
                if vol_ok and rsi_ok_long and regime_ok_long:
                    long_signal = (c2 < bl2 and c1 > bl1 and c1 <= bm1) and not (ma0 < ma10 and slope > slope_abs)
                if vol_ok and rsi_ok_short and regime_ok_short:
                    short_signal = (c2 > bu2 and c1 < bu1 and c1 >= bm1) and not (ma0 > ma10 and slope > slope_abs)
            
            if long_signal:
                struct_sl = bl1 - atr_val * struct_sl_mult
                vol_sl = close[idx] - atr_val * vol_sl_mult
                sl = min(struct_sl, vol_sl)
                position = 1
                entry_price = close[idx]
                entry_idx = idx
                remaining_volume = 1.0
                exit_stage = 0
            
            elif short_signal:
                struct_sl = bu1 + atr_val * struct_sl_mult
                vol_sl = close[idx] + atr_val * vol_sl_mult
                sl = max(struct_sl, vol_sl)
                position = -1
                entry_price = close[idx]
                entry_idx = idx
                remaining_volume = 1.0
                exit_stage = 0
        
        max_equity = max(max_equity, equity)
        max_dd = max(max_dd, (max_equity - equity) / max_equity * 100)
    
    if position != 0:
        pnl = (close[-1] - entry_price) * position / point * 100 * remaining_volume
        equity += pnl
        trades += 1
        if pnl > 0:
            wins += 1
            total_profit += pnl
    
    profit_factor = total_profit / total_loss if total_loss > 0 else 0
    win_rate = wins / trades * 100 if trades > 0 else 0
    
    return equity - 10000.0, trades, profit_factor, max_dd, win_rate


@jit(nopython=True, cache=True)
def backtest_trendpullback_numba(
    high: np.ndarray, low: np.ndarray, close: np.ndarray,
    ema50: np.ndarray, ema200: np.ndarray, ema20: np.ndarray, atr: np.ndarray,
    sl_mult: float, value_zone_atr: float,
    point: float, start_idx: int
) -> Tuple[float, int, float, float, float]:
    """TrendPullback策略回测"""
    n = len(close)
    equity = 10000.0
    max_equity = equity
    trades = 0
    wins = 0
    total_profit = 0.0
    total_loss = 0.0
    max_dd = 0.0
    
    position = 0
    entry_price = 0.0
    sl = 0.0
    
    for idx in range(start_idx, n):
        if position != 0:
            if position == 1 and low[idx] <= sl:
                pnl = (sl - entry_price) / point * 100
                equity += pnl
                total_loss += abs(pnl) if pnl < 0 else 0
                total_profit += pnl if pnl > 0 else 0
                trades += 1
                if pnl > 0:
                    wins += 1
                position = 0
            elif position == -1 and high[idx] >= sl:
                pnl = (entry_price - sl) / point * 100
                equity += pnl
                total_loss += abs(pnl) if pnl < 0 else 0
                total_profit += pnl if pnl > 0 else 0
                trades += 1
                if pnl > 0:
                    wins += 1
                position = 0
        
        if position == 0:
            if np.isnan(ema50[idx]) or np.isnan(ema200[idx]) or np.isnan(atr[idx]):
                continue
            
            trend_long = ema50[idx] > ema200[idx]
            trend_short = ema50[idx] < ema200[idx]
            
            if trend_long and close[idx] < ema20[idx] + atr[idx] * value_zone_atr:
                sl = close[idx] - atr[idx] * sl_mult
                position = 1
                entry_price = close[idx]
            elif trend_short and close[idx] > ema20[idx] - atr[idx] * value_zone_atr:
                sl = close[idx] + atr[idx] * sl_mult
                position = -1
                entry_price = close[idx]
        
        max_equity = max(max_equity, equity)
        max_dd = max(max_dd, (max_equity - equity) / max_equity * 100)
    
    if position != 0:
        pnl = (close[-1] - entry_price) * position / point * 100
        equity += pnl
        trades += 1
        if pnl > 0:
            wins += 1
            total_profit += pnl
        else:
            total_loss += abs(pnl)
    
    profit_factor = total_profit / total_loss if total_loss > 0 else 0
    win_rate = wins / trades * 100 if trades > 0 else 0
    
    return equity - 10000.0, trades, profit_factor, max_dd, win_rate


@jit(nopython=True, cache=True)
def backtest_donchian_numba(
    high: np.ndarray, low: np.ndarray, close: np.ndarray,
    donchian_upper: np.ndarray, donchian_lower: np.ndarray,
    donchian_trail_upper: np.ndarray, donchian_trail_lower: np.ndarray,
    ema_fast: np.ndarray, ema_slow: np.ndarray,
    atr: np.ndarray, atr_avg: np.ndarray, adx: np.ndarray,
    sl_mult: float, tp_mult: float, exp_ratio: float,
    enable_partial: bool, partial1_rr: float, partial1_ratio: float,
    partial2_rr: float, partial2_ratio: float,
    enable_be: bool, be_trigger_rr: float, be_offset_atr: float,
    enable_adx: bool, adx_entry: float, adx_exit: float,
    enable_trailing: bool,
    point: float, start_idx: int
) -> Tuple[float, int, float, float, float]:
    """Donchian策略回测核心"""
    n = len(close)
    equity = 10000.0
    max_equity = equity
    trades = 0
    wins = 0
    total_profit = 0.0
    total_loss = 0.0
    max_dd = 0.0
    
    position = 0
    entry_price = 0.0
    entry_idx = 0
    sl = 0.0
    initial_sl = 0.0
    remaining_volume = 1.0
    highest_profit = 0.0
    be_triggered = False
    
    for idx in range(start_idx, n):
        if position != 0:
            # 拖尾止损更新
            if enable_trailing and position == 1 and not np.isnan(donchian_trail_lower[idx]):
                new_sl = donchian_trail_lower[idx]
                if new_sl > sl:
                    sl = new_sl
            elif enable_trailing and position == -1 and not np.isnan(donchian_trail_upper[idx]):
                new_sl = donchian_trail_upper[idx]
                if new_sl < sl:
                    sl = new_sl
            
            # 止损检查
            if position == 1 and low[idx] <= sl:
                pnl = (sl - entry_price) / point * 100 * remaining_volume
                equity += pnl
                trades += 1
                if pnl > 0:
                    wins += 1
                    total_profit += pnl
                else:
                    total_loss += abs(pnl)
                position = 0
                remaining_volume = 1.0
            elif position == -1 and high[idx] >= sl:
                pnl = (entry_price - sl) / point * 100 * remaining_volume
                equity += pnl
                trades += 1
                if pnl > 0:
                    wins += 1
                    total_profit += pnl
                else:
                    total_loss += abs(pnl)
                position = 0
                remaining_volume = 1.0
            else:
                # 分批出场和保本止损
                risk = abs(entry_price - initial_sl)
                current_profit = (close[idx] - entry_price) * position
                
                # 保本止损
                if enable_be and not be_triggered and current_profit >= risk * be_trigger_rr:
                    if position == 1:
                        sl = entry_price + atr[idx] * be_offset_atr
                    else:
                        sl = entry_price - atr[idx] * be_offset_atr
                    be_triggered = True
                
                # 分批出场
                if enable_partial:
                    rr = current_profit / risk if risk > 0 else 0
                    if rr >= partial1_rr and remaining_volume > 0.5:
                        exit_vol = remaining_volume * partial1_ratio
                        pnl = (close[idx] - entry_price) * position / point * 100 * exit_vol
                        equity += pnl
                        trades += 1
                        if pnl > 0:
                            wins += 1
                            total_profit += pnl
                        else:
                            total_loss += abs(pnl)
                        remaining_volume -= exit_vol
        
        # 入场检查
        if position == 0 and idx >= 6:
            du = donchian_upper[idx]
            dl = donchian_lower[idx]
            ef = ema_fast[idx]
            es = ema_slow[idx]
            ef_prev5 = ema_fast[idx - 5]
            at = atr[idx]
            aa = atr_avg[idx]
            c1 = close[idx - 1]
            
            if (not np.isnan(du) and not np.isnan(dl) and
                not np.isnan(ef) and not np.isnan(es) and
                not np.isnan(ef_prev5) and
                not np.isnan(at) and not np.isnan(aa)):
                
                vol_expand = at >= aa * exp_ratio
                
                adx_ok = True
                if enable_adx and not np.isnan(adx[idx]):
                    adx_ok = adx[idx] > adx_entry
                
                if vol_expand and adx_ok:
                    is_bullish = (c1 > ef and c1 > es and ef > es and ef > ef_prev5)
                    is_bearish = (c1 < ef and c1 < es and ef < es and ef < ef_prev5)
                    
                    if is_bullish and c1 > du:
                        sl = close[idx] - at * sl_mult
                        position = 1
                        entry_price = close[idx]
                        entry_idx = idx
                        initial_sl = sl
                        remaining_volume = 1.0
                        be_triggered = False
                    elif is_bearish and c1 < dl:
                        sl = close[idx] + at * sl_mult
                        position = -1
                        entry_price = close[idx]
                        entry_idx = idx
                        initial_sl = sl
                        remaining_volume = 1.0
                        be_triggered = False
        
        max_equity = max(max_equity, equity)
        max_dd = max(max_dd, (max_equity - equity) / max_equity * 100)
    
    if position != 0:
        pnl = (close[-1] - entry_price) * position / point * 100 * remaining_volume
        equity += pnl
        trades += 1
        if pnl > 0:
            wins += 1
            total_profit += pnl
        else:
            total_loss += abs(pnl)
    
    profit_factor = total_profit / total_loss if total_loss > 0 else 0
    win_rate = wins / trades * 100 if trades > 0 else 0
    
    return equity - 10000.0, trades, profit_factor, max_dd, win_rate


# ============================================================
# 参数网格定义
# ============================================================

def get_param_grid_common_risk() -> Dict[str, List]:
    """公用风控参数网格"""
    return {
        'MaxHoldingBars': [0, 5],
        'CooldownBars': [0, 2],
        'MaxLosingStreak': [0, 3],
        'CooldownBarsAfterLoss': [5],
    }


def get_param_grid_regime_rf() -> Dict[str, List]:
    """L3: Regime Filter 参数网格"""
    return {
        'RF_Q_Score_Standby': [0.30, 0.20, 0.35, 0.40],
        'Regime_ADX_Period': [14, 10, 18],
        'Regime_ADX_Trend_Threshold': [25.0, 22.5, 27.5, 30.0],
        'Regime_DI_Threshold': [3.0, 2.0, 4.0, 5.0],
        'Regime_Vol_Low_Percentile': [25.0, 20.0, 30.0],
        'Regime_Vol_High_Percentile': [75.0, 70.0, 80.0],
        'MQ_Weight_Eff': [0.25, 0.20, 0.30],
        'MQ_Weight_FBR': [0.25, 0.20, 0.30],
        'MQ_Weight_ADX': [0.20, 0.15, 0.25],
        'MQ_Efficiency_Baseline': [0.10, 0.15, 0.20],
        'MQ_FBR_Baseline': [0.40, 0.35, 0.45],
        'MQ_ADX_Baseline': [25.0, 22.5, 27.5],
    }


def get_param_grid_position_risk() -> Dict[str, List]:
    """L4: 仓位风控参数网格"""
    return {
        'InpRiskPercent': [1.0, 1.5, 2.0, 2.5],
        'MaxHoldingBars_Risk': [0, 5, 10, 15, 20],
        'MaxLosingStreak_Risk': [0, 2, 3, 4],
        'CooldownBarsAfterLoss_Risk': [3, 5, 7],
        'MAX_DAILY_LOSS_PERCENT': [5.0, 10.0, 15.0, 20.0],
    }


def get_param_grid_bollmr(include_rf: bool = True, include_risk: bool = True) -> Dict[str, List]:
    """BollMR参数网格"""
    grid = {
        'BollMR_BollPeriod': [16],
        'BollMR_BollDev': [1.75],
        'BollMR_ATRPeriod': [15],
        'BollMR_StructATRSL': [1.1],
        'BollMR_VolATRSL': [1.875],
        'BollMR_ATRVolLimit': [2.25],
        'BollMR_MAPeriod': [40],
        'BollMR_Slope_Abs': [400],
        'BollMR_EntryMode': ['C'],
    }
    
    if include_rf:
        grid.update({
            'BollMR_EnableRSI': [False],
            'BollMR_RSIPeriod': [14],
            'BollMR_RSIOverbought': [70],
            'BollMR_RSIOversold': [30],
        })
    
    if include_risk:
        grid.update({
            'BollMR_EnablePartial': [True],
            'BollMR_MidATRTP': [0.4],
            'BollMR_MidATRTP2': [0.7],
            'BollMR_PartialExit1': [0.2],
            'BollMR_PartialExit2': [0.15],
        })
    
    return grid


def get_param_grid_trendpullback(include_rf: bool = True, include_risk: bool = True) -> Dict[str, List]:
    """TrendPullback参数网格"""
    return {
        'TP_EMA50_Period': [50],
        'TP_EMA200_Period': [200],
        'TP_EMA20_Period': [20],
        'TP_ATR_Period': [14],
        'TP_ATR_SL_Multi': [1.5, 1.8],
        'TP_ValueZoneATR': [0.5],
        'TP_PullbackBars': [5],
        'TP_Structure_Lookback': [20],
        'TP_PullbackDepthATR': [0.5],
    }


def get_param_grid_donchian(include_rf: bool = True, include_risk: bool = True) -> Dict[str, List]:
    """Donchian参数网格"""
    return {
        'Donchian_Period': [20],
        'Donchian_EMA_Fast': [55],
        'Donchian_EMA_Slow': [144],
        'Donchian_ATR_Period': [14],
        'Donchian_ATR_SL_Mult': [1.5, 2.0],
        'Donchian_ATR_TP_Mult': [2.2, 2.5],
        'Donchian_ATR_Avg_Period': [30],
        'Donchian_ATR_Exp_Ratio': [1.0],
        'Donchian_EnablePartial': [True],
        'Donchian_Partial1_RR': [1.0],
        'Donchian_Partial1_Ratio': [0.5],
        'Donchian_Partial2_RR': [2.0],
        'Donchian_Partial2_Ratio': [0.3],
        'Donchian_Enable_BE': [True],
        'Donchian_BE_TriggerRR': [1.0],
        'Donchian_BE_OffsetATR': [0.1],
        'Donchian_Enable_ADX': [False],
        'Donchian_ADX_Period': [14],
        'Donchian_ADX_Entry': [25.0],
        'Donchian_ADX_Exit': [20.0],
        'Donchian_Enable_Trailing': [True],
    }


# ============================================================
# 网格优化器
# ============================================================

class GridOptimizer:
    """网格参数优化器"""
    
    def __init__(self, strategy: str, data: pd.DataFrame,
                 output_dir: str = 'results',
                 include_rf: bool = True,
                 include_risk: bool = True,
                 include_common_risk: bool = False,
                 include_regime_rf: bool = False,
                 include_position_risk: bool = False):
        self.strategy = strategy.lower()
        self.data = data
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.include_rf = include_rf
        self.include_risk = include_risk
        self.include_common_risk = include_common_risk
        self.include_regime_rf = include_regime_rf
        self.include_position_risk = include_position_risk
        
        self.high = data['high'].values.astype(np.float64)
        self.low = data['low'].values.astype(np.float64)
        self.close = data['close'].values.astype(np.float64)
        self.point = DEFAULT_POINT
        
        self.timestamps = None
        if hasattr(data, 'index') and isinstance(data.index, pd.DatetimeIndex):
            self.timestamps = data.index
        
        self._setup_param_grid()
        self.results = []
    
    def _setup_param_grid(self):
        """设置参数网格"""
        if self.strategy == 'bollmr':
            self.param_grid = get_param_grid_bollmr(
                include_rf=self.include_rf,
                include_risk=self.include_risk
            )
        elif self.strategy == 'trendpullback':
            self.param_grid = get_param_grid_trendpullback(
                include_rf=self.include_rf,
                include_risk=self.include_risk
            )
        elif self.strategy == 'donchian':
            self.param_grid = get_param_grid_donchian(
                include_rf=self.include_rf,
                include_risk=self.include_risk
            )
        else:
            raise ValueError(f"未知策略: {self.strategy}")
        
        if self.include_common_risk:
            common_grid = get_param_grid_common_risk()
            self.param_grid.update(common_grid)
        
        if self.include_regime_rf:
            regime_rf_grid = get_param_grid_regime_rf()
            self.param_grid.update(regime_rf_grid)
        
        if self.include_position_risk:
            position_risk_grid = get_param_grid_position_risk()
            self.param_grid.update(position_risk_grid)
        
        total_combos = 1
        for k, v in self.param_grid.items():
            total_combos *= len(v)
        print(f"参数网格: {len(self.param_grid)}个参数, {total_combos:,}个组合", flush=True)
        if self.include_rf:
            print("  - 包含RF过滤参数", flush=True)
        if self.include_risk:
            print("  - 包含策略风控参数", flush=True)
        if self.include_common_risk:
            print("  - 包含公用风控参数", flush=True)
        if self.include_regime_rf:
            print("  - 包含L3 Regime Filter参数", flush=True)
        if self.include_position_risk:
            print("  - 包含L4仓位风控参数", flush=True)
    
    def _generate_combinations(self, max_combinations: int = 100000) -> List[Dict]:
        """生成参数组合"""
        keys = list(self.param_grid.keys())
        values = [self.param_grid[k] for k in keys]
        
        total_combos = 1
        for v in values:
            total_combos *= len(v)
        
        combinations = []
        
        if total_combos <= max_combinations:
            for combo in itertools.product(*values):
                combinations.append(dict(zip(keys, combo)))
        else:
            print(f"  组合数过多({total_combos:,})，使用随机采样 {max_combinations:,} 个")
            for _ in range(max_combinations):
                combo = [random.choice(v) for v in values]
                combinations.append(dict(zip(keys, combo)))
        
        return combinations
    
    def run(self, max_combinations: int = 50000) -> pd.DataFrame:
        """运行网格优化"""
        combinations = self._generate_combinations(max_combinations)
        total = len(combinations)
        
        print(f"\n{'='*70}", flush=True)
        print(f"[{self.strategy.upper()}] 开始网格优化", flush=True)
        print(f"{'='*70}", flush=True)
        print(f"参数组合总数: {total}", flush=True)
        print(f"参数网格: {self.param_grid}", flush=True)
        
        if self.strategy == 'bollmr':
            run_func = self._run_single_bollmr
        elif self.strategy == 'trendpullback':
            run_func = self._run_single_trendpullback
        else:
            run_func = self._run_single_donchian
        
        results = []
        for i, params in enumerate(combinations):
            result = run_func(params)
            results.append(result)
            
            if (i + 1) % 100 == 0 or i == total - 1:
                print(f"进度: {i + 1}/{total} ({100*(i+1)/total:.1f}%)", flush=True)
        
        self.results_df = pd.DataFrame(results)
        return self.results_df
    
    def save_results(self, filename: str = None):
        """保存结果"""
        if filename is None:
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            filename = f"{self.strategy}_optimization_{timestamp}.csv"
        
        filepath = self.output_dir / filename
        self.results_df.to_csv(filepath, index=False)
        print(f"结果已保存: {filepath}")
        return filepath
    
    def _run_single_bollmr(self, params: Dict) -> Dict:
        """单次BollMR回测"""
        period = params['BollMR_BollPeriod']
        std_dev = params['BollMR_BollDev']
        atr_period = params['BollMR_ATRPeriod']
        
        boll_upper, boll_middle, boll_lower = calc_bollinger(
            self.close, period, std_dev)
        atr = calc_atr(self.high, self.low, self.close, atr_period)
        atr_avg = calc_sma(atr, 10)
        
        ma_period = params.get('BollMR_MAPeriod', 50)
        ma = calc_ema(self.close, ma_period)
        
        enable_rsi = params.get('BollMR_EnableRSI', False)
        if enable_rsi:
            rsi_period = params.get('BollMR_RSIPeriod', 14)
            rsi = calc_rsi(self.close, rsi_period)
        else:
            rsi = np.full(len(self.close), np.nan)
        
        enable_regime_rf = self.include_regime_rf
        if enable_regime_rf:
            adx_period = params.get('Regime_ADX_Period', 14)
            adx = calc_adx(self.high, self.low, self.close, adx_period)
            adx = np.where(np.isnan(adx), 0, adx)
        else:
            adx = np.zeros(len(self.close))
        
        entry_mode_str = params.get('BollMR_EntryMode', 'A')
        entry_mode = {'A': 0, 'B': 1, 'C': 2}.get(entry_mode_str, 0)
        
        use_enhanced = (
            self.include_rf or
            self.include_risk or
            self.include_common_risk or
            self.include_regime_rf or
            self.include_position_risk or
            enable_rsi or
            params.get('BollMR_EnablePartial', False) or
            params.get('MaxHoldingBars', 0) > 0
        )
        
        if use_enhanced:
            profit, trades, pf, dd, wr = backtest_bollmr_enhanced_numba(
                self.high, self.low, self.close,
                boll_upper, boll_middle, boll_lower,
                atr, atr_avg, ma, rsi,
                params['BollMR_StructATRSL'],
                params['BollMR_VolATRSL'],
                params['BollMR_ATRVolLimit'],
                ma_period,
                params.get('BollMR_Slope_Abs', 150),
                entry_mode,
                enable_rsi,
                params.get('BollMR_RSIOverbought', 70.0),
                params.get('BollMR_RSIOversold', 30.0),
                params.get('BollMR_EnablePartial', False),
                params.get('BollMR_MidATRTP', 0.2),
                params.get('BollMR_MidATRTP2', 0.5),
                params.get('BollMR_PartialExit1', 0.5),
                params.get('BollMR_PartialExit2', 0.25),
                params.get('MaxHoldingBars', 0),
                params.get('CooldownBars', 0),
                params.get('MaxLosingStreak', 0),
                params.get('CooldownBarsAfterLoss', 0),
                enable_regime_rf,
                adx,
                params.get('RF_Q_Score_Standby', 0.3),
                params.get('Regime_ADX_Trend_Threshold', 25.0),
                self.point, 200
            )
        else:
            profit, trades, pf, dd, wr = backtest_bollmr_numba(
                self.high, self.low, self.close,
                boll_upper, boll_middle, boll_lower,
                atr, atr_avg, ma,
                params['BollMR_StructATRSL'],
                params['BollMR_VolATRSL'],
                params['BollMR_ATRVolLimit'],
                self.point, 200
            )
        
        return {**params, 'profit': profit, 'trades': trades,
                'profit_factor': pf, 'max_dd': dd, 'win_rate': wr}
    
    def _run_single_trendpullback(self, params: Dict) -> Dict:
        """单次TrendPullback回测"""
        ema50 = calc_ema(self.close, params['TP_EMA50_Period'])
        ema200 = calc_ema(self.close, params['TP_EMA200_Period'])
        ema20 = calc_ema(self.close, params['TP_EMA20_Period'])
        atr = calc_atr(self.high, self.low, self.close, params['TP_ATR_Period'])
        
        profit, trades, pf, dd, wr = backtest_trendpullback_numba(
            self.high, self.low, self.close,
            ema50, ema200, ema20, atr,
            params['TP_ATR_SL_Multi'],
            params['TP_ValueZoneATR'],
            self.point, 250
        )
        
        return {**params, 'profit': profit, 'trades': trades,
                'profit_factor': pf, 'max_dd': dd, 'win_rate': wr}
    
    def _run_single_donchian(self, params: Dict) -> Dict:
        """单次Donchian回测"""
        period = params['Donchian_Period']
        trail_period = params.get('Donchian_Period_Trail', 55)
        
        donchian_upper, donchian_lower = calc_donchian(
            self.high, self.low, period)
        donchian_trail_upper, donchian_trail_lower = calc_donchian(
            self.high, self.low, trail_period)
        
        ema_fast = calc_ema(self.close, params['Donchian_EMA_Fast'])
        ema_slow = calc_ema(self.close, params['Donchian_EMA_Slow'])
        atr = calc_atr(self.high, self.low, self.close, params['Donchian_ATR_Period'])
        atr_avg = calc_sma(atr, params.get('Donchian_ATR_Avg_Period', 30))
        
        enable_adx = params.get('Donchian_Enable_ADX', False)
        if enable_adx:
            adx_period = params.get('Donchian_ADX_Period', 14)
            adx = calc_adx(self.high, self.low, self.close, adx_period)
        else:
            adx = np.full(len(self.close), np.nan)
        
        profit, trades, pf, dd, wr = backtest_donchian_numba(
            self.high, self.low, self.close,
            donchian_upper, donchian_lower,
            donchian_trail_upper, donchian_trail_lower,
            ema_fast, ema_slow,
            atr, atr_avg, adx,
            params['Donchian_ATR_SL_Mult'],
            params['Donchian_ATR_TP_Mult'],
            params.get('Donchian_ATR_Exp_Ratio', 1.0),
            params.get('Donchian_EnablePartial', False),
            params.get('Donchian_Partial1_RR', 1.0),
            params.get('Donchian_Partial1_Ratio', 0.5),
            params.get('Donchian_Partial2_RR', 2.0),
            params.get('Donchian_Partial2_Ratio', 0.3),
            params.get('Donchian_Enable_BE', False),
            params.get('Donchian_BE_TriggerRR', 1.0),
            params.get('Donchian_BE_OffsetATR', 0.1),
            enable_adx,
            params.get('Donchian_ADX_Entry', 25.0),
            params.get('Donchian_ADX_Exit', 20.0),
            params.get('Donchian_Enable_Trailing', False),
            self.point, 250
        )
        
        return {**params, 'profit': profit, 'trades': trades,
                'profit_factor': pf, 'max_dd': dd, 'win_rate': wr}


# ============================================================
# 分析模块
# ============================================================

def analyze_results(results_df: pd.DataFrame, strategy: str, output_dir: str):
    """分析优化结果"""
    print(f"\n{'='*70}")
    print(f"[{strategy.upper()}] 优化结果分析")
    print(f"{'='*70}")
    
    # 基础统计
    total = len(results_df)
    profitable = len(results_df[results_df['profit'] > 0])
    print(f"\n总组合数: {total}")
    print(f"盈利组合: {profitable} ({profitable/total*100:.1f}%)")
    
    # Top 20
    print(f"\n{'='*70}")
    print("Top 20 参数组合")
    print(f"{'='*70}")
    
    top20 = results_df.nlargest(20, 'profit')
    display_cols = ['profit', 'trades', 'profit_factor', 'max_dd', 'win_rate']
    print(top20[display_cols].to_string())
    
    # 相关性分析
    print(f"\n{'='*70}")
    print("[相关性分析] 参数 vs 结果指标")
    print(f"{'='*70}")
    
    all_param_cols = [c for c in results_df.columns 
                      if c.startswith('BollMR_') or 
                      c.startswith('TP_') or 
                      c.startswith('Donchian_') or
                      c.startswith('Max') or
                      c.startswith('Cooldown') or
                      c.startswith('RF_') or
                      c.startswith('Regime_') or
                      c.startswith('MQ_') or
                      c.startswith('InpRisk')]
    
    numeric_param_cols = []
    for col in all_param_cols:
        if col in results_df.columns:
            if results_df[col].dtype in ['int64', 'float64', 'int32', 'float32', 'int', 'float']:
                numeric_param_cols.append(col)
    
    corr_results = []
    for param in numeric_param_cols:
        valid = results_df[results_df[param].notna()]
        if len(valid) < 10:
            continue
        
        try:
            p_corr, _ = stats.pearsonr(valid[param].astype(float), valid['profit'].astype(float))
            pf_corr, _ = stats.pearsonr(valid[param].astype(float), valid['profit_factor'].astype(float))
            dd_corr, _ = stats.pearsonr(valid[param].astype(float), valid['max_dd'].astype(float))
            wr_corr, _ = stats.pearsonr(valid[param].astype(float), valid['win_rate'].astype(float))
        except:
            continue
        
        corr_results.append({
            'param': param,
            'profit_corr': p_corr,
            'profit_factor_corr': pf_corr,
            'max_dd_corr': dd_corr,
            'win_rate_corr': wr_corr
        })
    
    corr_df = pd.DataFrame(corr_results)
    
    print(f"\n{'参数':<30} {'Profit':>10} {'PF':>10} {'DD':>10} {'WinRate':>10}")
    print("-" * 75)
    for _, row in corr_df.iterrows():
        param = row['param']
        p_corr = row.get('profit_corr', np.nan)
        pf_corr = row.get('profit_factor_corr', np.nan)
        dd_corr = row.get('max_dd_corr', np.nan)
        wr_corr = row.get('win_rate_corr', np.nan)
        
        def fmt(c):
            if pd.isna(c):
                return '    -    '
            return f'{c:+.3f}'
        
        print(f"{param:<30} {fmt(p_corr):>10} {fmt(pf_corr):>10} {fmt(dd_corr):>10} {fmt(wr_corr):>10}")
    
    # 稳定性分析
    print(f"\n{'='*70}")
    print("[稳定性分析]")
    print(f"{'='*70}")
    
    stability_results = []
    top_n = min(50, len(results_df))
    
    for param in numeric_param_cols:
        valid = results_df[(results_df['profit'] > 0) & (results_df[param].notna())].copy()
        if len(valid) < 20:
            continue
        
        top_df = valid.nlargest(top_n, 'profit')
        
        try:
            param_std = (top_df[param] - top_df[param].mean()) / (top_df[param].std() + 1e-9)
            target_std = (top_df['profit'] - top_df['profit'].mean()) / (top_df['profit'].std() + 1e-9)
            slope, _, r_value, _, _ = stats.linregress(param_std.astype(float), target_std.astype(float))
            sensitivity = abs(slope)
            
            best_idx = top_df['profit'].idxmax()
            best_param = top_df.loc[best_idx, param]
            best_profit = top_df['profit'].max()
            param_range = top_df[param].max() - top_df[param].min()
            
            if param_range > 0:
                local_mask = abs(top_df[param] - best_param) <= param_range * 0.1
                local_df = top_df[local_mask]
                local_var = local_df['profit'].var() / (best_profit ** 2 + 1e-9) if len(local_df) > 1 else np.nan
            else:
                local_var = np.nan
            
            x = top_df[param].values.astype(float)
            y = top_df['profit'].values.astype(float)
            x_norm = (x - x.mean()) / (x.std() + 1e-9)
            coeffs = np.polyfit(x_norm, y, 2)
            curvature = abs(2 * coeffs[0]) / (y.max() - y.min() + 1e-9)
        except:
            continue
        
        sens_norm = min(sensitivity / 2.0, 1.0)
        var_norm = min(local_var * 100, 1.0) if not np.isnan(local_var) else 0
        curv_norm = min(curvature, 1.0) if not np.isnan(curvature) else 0
        stability = 1 - (0.4 * sens_norm + 0.3 * var_norm + 0.3 * curv_norm)
        
        stability_results.append({
            'param': param,
            'stability_score': stability,
            'sensitivity': sensitivity,
            'local_variance': local_var,
            'curvature': curvature
        })
    
    stability_df = pd.DataFrame(stability_results)
    
    if len(stability_df) > 0:
        stability_df = stability_df.sort_values('stability_score', ascending=False)
        
        print(f"\n{'参数':<30} {'稳定性':>6} {'等级':>4} {'敏感度':>8} {'曲率':>8}")
        print("-" * 60)
        for _, row in stability_df.iterrows():
            score = row['stability_score']
            level = '高' if score >= 0.7 else ('中' if score >= 0.4 else '低')
            sens = row['sensitivity']
            curv = row['curvature']
            
            def fmt(v):
                if pd.isna(v):
                    return '  -  '
                return f'{v:.3f}'
            
            print(f"{row['param']:<30} {fmt(score):>6} {level:>4} {fmt(sens):>8} {fmt(curv):>8}")
    else:
        print("  (无足够数据计算稳定性)")
    
    # 推荐参数
    print(f"\n{'='*70}")
    print("[推荐参数] Top 50 中位数")
    print(f"{'='*70}")
    
    best_params = {}
    top50 = results_df.nlargest(50, 'profit')
    
    for param in all_param_cols:
        if param in top50.columns:
            if top50[param].dtype in ['int64', 'float64', 'int32', 'float32']:
                median_val = top50[param].median()
            else:
                median_val = top50[param].mode().iloc[0] if len(top50[param].mode()) > 0 else top50[param].iloc[0]
            best_params[param] = median_val
            
            if len(stability_df) > 0 and 'param' in stability_df.columns:
                stab_row = stability_df[stability_df['param'] == param]
                stab = stab_row['stability_score'].values[0] if len(stab_row) > 0 else np.nan
            else:
                stab = np.nan
            stab_str = f"{stab:.2f}" if not np.isnan(stab) else "N/A"
            
            print(f"{param}={median_val} (稳定性: {stab_str})")
    
    # 保存结果
    output_path = Path(output_dir)
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    
    def convert_to_native(obj):
        if isinstance(obj, dict):
            return {k: convert_to_native(v) for k, v in obj.items()}
        elif isinstance(obj, (np.integer, np.int64, np.int32)):
            return int(obj)
        elif isinstance(obj, (np.floating, np.float64, np.float32)):
            return float(obj)
        elif isinstance(obj, (np.bool_, bool)):
            return bool(obj)
        elif isinstance(obj, np.ndarray):
            return obj.tolist()
        return obj
    
    best_params_native = convert_to_native(best_params)
    with open(output_path / f'{strategy}_best_params_{timestamp}.json', 'w') as f:
        json.dump(best_params_native, f, indent=2)
    
    with open(output_path / f'{strategy}_analysis_{timestamp}.txt', 'w', encoding='utf-8') as f:
        f.write(f"策略: {strategy.upper()}\n")
        f.write(f"时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        f.write("推荐参数:\n")
        for k, v in best_params.items():
            f.write(f"  {k}={v}\n")
    
    # 保存 MT5 .set 文件
    set_filename = f'{strategy}_best_params_{timestamp}.set'
    with open(output_path / set_filename, 'w', encoding='utf-8') as f:
        f.write(f"; MT5 参数配置文件\n")
        f.write(f"; 策略: {strategy.upper()}\n")
        f.write(f"; 时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"; 由 run_grid_optimize.py 自动生成\n\n")
        
        param_groups = {
            '策略核心': [],
            'RF过滤': [],
            'Regime Filter': [],
            '市场质量': [],
            '风控参数': [],
            '其他': []
        }
        
        for k, v in best_params.items():
            if k.startswith('BollMR_') and 'RSI' not in k and 'Partial' not in k:
                param_groups['策略核心'].append((k, v))
            elif k.startswith('BollMR_') and 'RSI' in k:
                param_groups['RF过滤'].append((k, v))
            elif k.startswith('BollMR_') and 'Partial' in k:
                param_groups['策略核心'].append((k, v))
            elif k.startswith('RF_'):
                param_groups['Regime Filter'].append((k, v))
            elif k.startswith('Regime_'):
                param_groups['Regime Filter'].append((k, v))
            elif k.startswith('MQ_'):
                param_groups['市场质量'].append((k, v))
            elif k.startswith('Max') or k.startswith('Cooldown') or k.startswith('InpRisk'):
                param_groups['风控参数'].append((k, v))
            else:
                param_groups['其他'].append((k, v))
        
        for group_name, params in param_groups.items():
            if params:
                f.write(f";--- {group_name} ---\n")
                for k, v in params:
                    if isinstance(v, bool):
                        v = 'true' if v else 'false'
                    f.write(f"{k}={v}\n")
                f.write("\n")
    
    print(f"\n已生成 .set 文件: {output_path / set_filename}")
    
    return {
        'correlation': corr_df,
        'stability': stability_df,
        'best_params': best_params,
        'top20': top20
    }


# ============================================================
# 数据加载
# ============================================================

def load_data(filepath: str) -> pd.DataFrame:
    """加载历史数据"""
    df = pd.read_csv(filepath, sep='\t')
    
    col_map = {
        'Open': 'open', 'High': 'high', 'Low': 'low',
        'Close': 'close', 'Volume': 'volume', 'Time': 'time',
        'open': 'open', 'high': 'high', 'low': 'low',
        'close': 'close', 'volume': 'volume', 'time': 'time',
        '<OPEN>': 'open', '<HIGH>': 'high', '<LOW>': 'low',
        '<CLOSE>': 'close', '<VOL>': 'volume', '<TICKVOL>': 'tickvol',
        '<DATE>': 'date', '<TIME>': 'time', '<SPREAD>': 'spread',
        '<open>': 'open', '<high>': 'high', '<low>': 'low',
        '<close>': 'close', '<vol>': 'volume', '<tickvol>': 'tickvol',
        '<date>': 'date', '<time>': 'time', '<spread>': 'spread',
    }
    
    df = df.rename(columns=col_map)
    
    if 'date' in df.columns and 'time' in df.columns:
        df['datetime'] = pd.to_datetime(df['date'].astype(str) + ' ' + df['time'].astype(str))
        df = df.set_index('datetime')
    elif 'time' in df.columns:
        df['datetime'] = pd.to_datetime(df['time'])
        df = df.set_index('datetime')
    
    required = ['open', 'high', 'low', 'close']
    for col in required:
        if col not in df.columns:
            raise ValueError(f"缺少必要列: {col}")
    
    print(f"数据量: {len(df)} 根K线, 时间范围: {df.index[0]} ~ {df.index[-1]}")
    return df


# ============================================================
# 主函数
# ============================================================

def main():
    parser = argparse.ArgumentParser(description='策略网格参数优化 - 支持RF过滤和风控参数')
    parser.add_argument('--strategy', type=str, required=True,
                        choices=['bollmr', 'trendpullback', 'donchian'],
                        help='策略类型')
    parser.add_argument('--data', type=str, required=True, help='数据文件路径')
    parser.add_argument('--output', type=str, default='results', help='输出目录')
    parser.add_argument('--threads', type=int, default=4, help='Numba线程数')
    
    parser.add_argument('--no-rf', action='store_true',
                        help='不包含RF过滤参数')
    parser.add_argument('--no-risk', action='store_true',
                        help='不包含策略风控参数')
    parser.add_argument('--common-risk', action='store_true',
                        help='包含公用风控参数')
    
    parser.add_argument('--regime-rf', action='store_true',
                        help='包含L3 Regime Filter参数')
    parser.add_argument('--position-risk', action='store_true',
                        help='包含L4仓位风控参数')
    
    parser.add_argument('--quick', action='store_true',
                        help='快速模式：仅优化核心参数')
    
    parser.add_argument('--max-combos', type=int, default=50000,
                        help='最大组合数')
    parser.add_argument('--seed', type=int, default=42,
                        help='随机种子')
    
    parser.add_argument('--analyze-only', type=str, default=None,
                        help='直接分析已存在的CSV文件')
    parser.add_argument('--skip-if-exists', action='store_true',
                        help='如果输出目录已有结果文件，直接分析')
    
    args = parser.parse_args()
    
    random.seed(args.seed)
    np.random.seed(args.seed)
    set_num_threads(args.threads)
    
    # 分析模式
    if args.analyze_only:
        csv_path = Path(args.analyze_only)
        if not csv_path.exists():
            print(f"错误: 文件不存在 - {csv_path}")
            return
        print(f"加载已有结果: {csv_path}")
        results_df = pd.read_csv(csv_path)
        analysis = analyze_results(results_df, args.strategy, args.output)
        print(f"\n分析完成!")
        return
    
    # 检查已有结果
    output_dir = Path(args.output)
    if args.skip_if_exists and output_dir.exists():
        existing_files = list(output_dir.glob(f'{args.strategy}_optimization_*.csv'))
        if existing_files:
            latest_file = max(existing_files, key=lambda f: f.stat().st_mtime)
            print(f"发现已有结果文件: {latest_file}")
            print("跳过优化，直接分析...")
            results_df = pd.read_csv(latest_file)
            analysis = analyze_results(results_df, args.strategy, args.output)
            print(f"\n分析完成!")
            return
    
    print(f"加载数据: {args.data}")
    df = load_data(args.data)
    
    include_rf = not args.no_rf and not args.quick
    include_risk = not args.no_risk and not args.quick
    include_common_risk = args.common_risk
    include_regime_rf = args.regime_rf
    include_position_risk = args.position_risk
    
    optimizer = GridOptimizer(
        args.strategy, df, args.output,
        include_rf=include_rf,
        include_risk=include_risk,
        include_common_risk=include_common_risk,
        include_regime_rf=include_regime_rf,
        include_position_risk=include_position_risk
    )
    results_df = optimizer.run(max_combinations=args.max_combos)
    
    optimizer.save_results()
    
    analysis = analyze_results(results_df, args.strategy, args.output)
    
    print(f"\n{'='*70}")
    print("优化完成!")
    print(f"{'='*70}")


if __name__ == '__main__':
    main()
