"""
MT5 回测数据分析脚本

用法:
    python analyze_backtest.py --signals "C:\path\to\signals_mt5.csv"
    python analyze_backtest.py --signals "signals.csv" --features "features.csv"
"""

import argparse
from pathlib import Path
from typing import Dict, List, Tuple

import numpy as np
import pandas as pd


def load_signals(filepath: str) -> pd.DataFrame:
    """加载信号数据"""
    df = pd.read_csv(filepath, sep='\t')
    df['time'] = pd.to_datetime(df['time'])
    
    # 解析 regime 列
    if 'regime' in df.columns:
        df['regime_state'] = df['regime'].apply(lambda x: x.split('|')[0] if pd.notna(x) else '')
        df['subtype'] = df['regime'].apply(lambda x: x.split('|')[1] if pd.notna(x) and len(x.split('|')) > 1 else '')
        df['q_score'] = df['regime'].apply(lambda x: float(x.split('|')[2].replace('Q', '')) if pd.notna(x) and len(x.split('|')) > 2 else 0.0)
    
    # 提取小时
    df['hour'] = df['time'].dt.hour
    
    return df


def load_features(filepath: str) -> pd.DataFrame:
    """加载特征数据"""
    df = pd.read_csv(filepath, sep='\t')
    df['time'] = pd.to_datetime(df['time'])
    return df


def analyze_regime_distribution(df: pd.DataFrame) -> Dict:
    """分析 Regime 状态分布"""
    print("\n" + "="*60)
    print("📊 Regime 状态分布")
    print("="*60)
    
    # 整体分布
    state_counts = df['regime_state'].value_counts()
    total = len(df)
    
    print("\n整体分布:")
    for state, count in state_counts.items():
        pct = count / total * 100
        bar = "█" * int(pct / 2)
        print(f"  {state:12s}: {count:6d} ({pct:5.1f}%) {bar}")
    
    return state_counts.to_dict()


def analyze_subtype_distribution(df: pd.DataFrame) -> Dict:
    """分析 SubType 分布"""
    print("\n" + "="*60)
    print("📈 SubType 分布")
    print("="*60)
    
    subtype_counts = df['subtype'].value_counts()
    total = len(df)
    
    subtype_names = {
        'T+V-B': '真趋势 (高质量)',
        'T+V-A': '情绪脉冲 (高波动)',
        'T+N': '温和趋势',
        'R+V-B': '假突破密集',
        'R+V-A': '消息震荡',
        'R+N': '正常震荡',
        'R+L': '低波动震荡',
    }
    
    print("\n分布详情:")
    for subtype, count in subtype_counts.items():
        pct = count / total * 100
        name = subtype_names.get(subtype, subtype)
        bar = "█" * int(pct / 2)
        print(f"  {subtype:6s} ({name:12s}): {count:6d} ({pct:5.1f}%) {bar}")
    
    return subtype_counts.to_dict()


def analyze_entry_conditions(df: pd.DataFrame) -> Dict:
    """分析入场条件（关键！）"""
    print("\n" + "="*60)
    print("🚨 入场条件分析（关键检查）")
    print("="*60)
    
    # 找出入场信号 (source 非空)
    entries = df[df['source'].notna() & (df['source'] != '')].copy()
    
    if len(entries) == 0:
        print("\n⚠️ 未找到入场信号！")
        return {}
    
    total_entries = len(entries)
    
    # 入场时的 Regime 状态
    print(f"\n入场信号总数: {total_entries}")
    print("\n入场时的 Regime 状态:")
    
    entry_states = entries['regime_state'].value_counts()
    for state, count in entry_states.items():
        pct = count / total_entries * 100
        warning = "⚠️ 问题!" if state != 'ACTIVE' and pct > 10 else ""
        print(f"  {state:12s}: {count:4d} ({pct:5.1f}%) {warning}")
    
    # 计算问题比例
    standby_entries = entry_states.get('STANDBY', 0)
    standby_pct = standby_entries / total_entries * 100
    
    if standby_pct > 5:
        print(f"\n❌ 严重问题: {standby_pct:.1f}% 的入场发生在 STANDBY 状态！")
        print("   应该在 STANDBY 时阻止入场。")
    elif standby_pct > 0:
        print(f"\n⚠️ 警告: {standby_pct:.1f}% 的入场发生在 STANDBY 状态")
    else:
        print("\n✅ 正常: 没有 STANDBY 状态入场")
    
    return {
        'total_entries': total_entries,
        'standby_entries': standby_entries,
        'standby_pct': standby_pct,
    }


def analyze_entry_hours(df: pd.DataFrame) -> Dict:
    """分析入场时间分布（检测低流动性时段）"""
    print("\n" + "="*60)
    print("🕐 入场时间分布（低流动性检测）")
    print("="*60)
    
    entries = df[df['source'].notna() & (df['source'] != '')].copy()
    
    if len(entries) == 0:
        return {}
    
    # 小时分布
    hour_counts = entries['hour'].value_counts().sort_index()
    
    # 定义时段
    def get_session(hour):
        if 0 <= hour < 6:
            return '低流动性(00-06)'
        elif 6 <= hour < 16:
            return '亚洲时段(06-16)'
        elif 16 <= hour < 20:
            return '欧洲时段(16-20)'
        elif 20 <= hour < 24:
            return '欧美重叠(20-24)'
        else:
            return '其他'
    
    entries['session'] = entries['hour'].apply(get_session)
    session_counts = entries['session'].value_counts()
    
    total = len(entries)
    
    print("\n时段分布:")
    for session, count in session_counts.items():
        pct = count / total * 100
        warning = "⚠️ 问题!" if '低流动性' in session and pct > 5 else ""
        print(f"  {session:18s}: {count:4d} ({pct:5.1f}%) {warning}")
    
    # 低流动性入场
    low_liq_entries = session_counts.get('低流动性(00-06)', 0)
    low_liq_pct = low_liq_entries / total * 100
    
    if low_liq_pct > 5:
        print(f"\n❌ 严重问题: {low_liq_pct:.1f}% 的入场发生在低流动性时段！")
    elif low_liq_pct > 0:
        print(f"\n⚠️ 警告: {low_liq_pct:.1f}% 的入场发生在低流动性时段")
    else:
        print("\n✅ 正常: 没有低流动性时段入场")
    
    return {
        'low_liquidity_entries': low_liq_entries,
        'low_liquidity_pct': low_liq_pct,
    }


def analyze_qscore_distribution(df: pd.DataFrame) -> Dict:
    """分析 Q-Score 分布"""
    print("\n" + "="*60)
    print("📊 Q-Score 分布")
    print("="*60)
    
    q_scores = df['q_score']
    
    print(f"\n统计:")
    print(f"  均值: {q_scores.mean():.3f}")
    print(f"  中位数: {q_scores.median():.3f}")
    print(f"  最小值: {q_scores.min():.3f}")
    print(f"  最大值: {q_scores.max():.3f}")
    print(f"  标准差: {q_scores.std():.3f}")
    
    # 分位数
    print(f"\n分位数:")
    for q in [0.25, 0.5, 0.75, 0.9]:
        val = q_scores.quantile(q)
        print(f"  {int(q*100):2d}%: {val:.3f}")
    
    # Q-Score 分段
    bins = [0, 0.3, 0.4, 0.5, 0.6, 0.7, 1.0]
    labels = ['<0.3', '0.3-0.4', '0.4-0.5', '0.5-0.6', '0.6-0.7', '>0.7']
    df['q_score_bin'] = pd.cut(df['q_score'], bins=bins, labels=labels)
    
    print(f"\n分段分布:")
    bin_counts = df['q_score_bin'].value_counts().sort_index()
    for label, count in bin_counts.items():
        pct = count / len(df) * 100
        bar = "█" * int(pct / 2)
        print(f"  {label}: {count:6d} ({pct:5.1f}%) {bar}")
    
    return {
        'mean': q_scores.mean(),
        'median': q_scores.median(),
        'std': q_scores.std(),
    }


def analyze_signal_sources(df: pd.DataFrame) -> Dict:
    """分析信号来源"""
    print("\n" + "="*60)
    print("📡 信号来源分布")
    print("="*60)
    
    entries = df[df['source'].notna() & (df['source'] != '')].copy()
    
    if len(entries) == 0:
        print("\n未找到入场信号")
        return {}
    
    source_counts = entries['source'].value_counts()
    
    print("\n入场信号来源:")
    for source, count in source_counts.items():
        # 简化显示
        short_source = source.replace('combo_single_', '')
        print(f"  {short_source:30s}: {count:4d}")
    
    return source_counts.to_dict()


def analyze_signal_direction(df: pd.DataFrame) -> Dict:
    """分析信号方向"""
    print("\n" + "="*60)
    print("📈 信号方向分布")
    print("="*60)
    
    signal_counts = df['signal'].value_counts()
    
    total = len(df)
    print("\n信号分布:")
    for sig, count in signal_counts.items():
        direction = '做多' if sig == 1 else ('做空' if sig == -1 else '无')
        pct = count / total * 100
        bar = "█" * int(pct / 2)
        print(f"  {sig:3d} ({direction}): {count:6d} ({pct:5.1f}%) {bar}")
    
    return signal_counts.to_dict()


def generate_diagnosis_report(df: pd.DataFrame) -> None:
    """生成诊断报告"""
    print("\n" + "="*60)
    print("📋 诊断报告")
    print("="*60)
    
    entries = df[df['source'].notna() & (df['source'] != '')].copy()
    
    if len(entries) == 0:
        print("\n未找到入场信号，无法诊断")
        return
    
    total_entries = len(entries)
    
    # 检查项
    checks = []
    
    # 1. STANDBY 入场检查
    standby_entries = len(entries[entries['regime_state'] == 'STANDBY'])
    standby_pct = standby_entries / total_entries * 100
    checks.append({
        'name': 'STANDBY 入场比例',
        'value': f'{standby_pct:.1f}%',
        'expected': '< 5%',
        'status': '✅' if standby_pct < 5 else ('⚠️' if standby_pct < 20 else '❌'),
    })
    
    # 2. 低流动性时段入场
    low_liq = len(entries[(entries['hour'] >= 0) & (entries['hour'] < 6)])
    low_liq_pct = low_liq / total_entries * 100
    checks.append({
        'name': '低流动性时段入场',
        'value': f'{low_liq_pct:.1f}%',
        'expected': '0%',
        'status': '✅' if low_liq_pct == 0 else '❌',
    })
    
    # 3. ACTIVE 入场比例
    active_entries = len(entries[entries['regime_state'] == 'ACTIVE'])
    active_pct = active_entries / total_entries * 100
    checks.append({
        'name': 'ACTIVE 入场比例',
        'value': f'{active_pct:.1f}%',
        'expected': '> 80%',
        'status': '✅' if active_pct > 80 else ('⚠️' if active_pct > 50 else '❌'),
    })
    
    # 4. 高 Q-Score 入场
    high_q = len(entries[entries['q_score'] > 0.5])
    high_q_pct = high_q / total_entries * 100
    checks.append({
        'name': '高 Q-Score (>0.5) 入场',
        'value': f'{high_q_pct:.1f}%',
        'expected': '> 50%',
        'status': '✅' if high_q_pct > 50 else '⚠️',
    })
    
    print("\n检查结果:")
    print(f"  {'检查项':<25s} {'实际值':<10s} {'期望值':<10s} {'状态':<5s}")
    print("  " + "-"*55)
    for check in checks:
        print(f"  {check['name']:<25s} {check['value']:<10s} {check['expected']:<10s} {check['status']:<5s}")
    
    # 总体评估
    passed = sum(1 for c in checks if c['status'] == '✅')
    total = len(checks)
    
    print(f"\n总体评估: {passed}/{total} 项通过")
    
    if passed == total:
        print("✅ 回测数据正常，可以进行下一步优化")
    elif passed >= total * 0.75:
        print("⚠️ 部分指标异常，建议检查后优化")
    else:
        print("❌ 多项指标异常，需要修复问题后重新回测")


def main():
    parser = argparse.ArgumentParser(description='MT5 回测数据分析')
    parser.add_argument('--signals', required=True, help='信号文件路径')
    parser.add_argument('--features', default=None, help='特征文件路径 (可选)')
    args = parser.parse_args()
    
    print("\n" + "="*60)
    print("📊 MT5 回测数据分析工具")
    print("="*60)
    print(f"\n信号文件: {args.signals}")
    
    # 加载数据
    df = load_signals(args.signals)
    print(f"加载记录数: {len(df)}")
    
    # 分析
    analyze_regime_distribution(df)
    analyze_subtype_distribution(df)
    analyze_signal_direction(df)
    analyze_signal_sources(df)
    analyze_entry_conditions(df)
    analyze_entry_hours(df)
    analyze_qscore_distribution(df)
    
    # 诊断
    generate_diagnosis_report(df)
    
    print("\n" + "="*60)
    print("分析完成！")
    print("="*60)


if __name__ == '__main__':
    main()
