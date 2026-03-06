# -*- coding: utf-8 -*-
"""
MT5 优化结果XML分析脚本 v3
支持自动检测参数列，分析最优参数
"""

import argparse
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Dict, List, Tuple, Optional
from datetime import datetime
import pandas as pd
import numpy as np

# 设置stdout编码
if sys.platform == 'win32':
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

# 已知的非参数列（指标列）
METRIC_COLUMNS = [
    'Pass', 'Result', 'Profit', 'Expected Payoff', 'Profit Factor',
    'Recovery Factor', 'Sharpe Ratio', 'Custom', 'Equity DD %', 'Trades'
]


def parse_optimization_xml(filepath: str) -> Tuple[pd.DataFrame, dict]:
    """解析MT5优化结果XML文件，返回数据和元信息"""
    tree = ET.parse(filepath)
    root = tree.getroot()
    
    # 提取元信息
    meta = {}
    doc_props = root.find('.//{urn:schemas-microsoft-com:office:office}DocumentProperties')
    if doc_props is not None:
        for child in doc_props:
            tag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
            meta[tag] = child.text
    
    # 找到Worksheet
    ns = {'ss': 'urn:schemas-microsoft-com:office:spreadsheet'}
    worksheet = root.find('.//ss:Worksheet', ns)
    if worksheet is None:
        raise ValueError("找不到 Worksheet 元素")
    table = worksheet.find('ss:Table', ns)
    if table is None:
        raise ValueError("找不到 Table 元素")
    
    rows = table.findall('ss:Row', ns)
    if len(rows) < 2:
        raise ValueError("XML 文件没有数据行")
    
    # 第一行是表头
    header_row = rows[0]
    headers = []
    for cell in header_row.findall('ss:Cell', ns):
        data = cell.find('ss:Data', ns)
        if data is not None:
            headers.append(data.text)
        else:
            headers.append('')
    
    # 解析数据行
    data_list = []
    for row in rows[1:]:
        values = {}
        cells = row.findall('ss:Cell', ns)
        
        # 处理可能缺失的单元格（MT5 XML 可能跳过空单元格）
        cell_index = 0
        for i, header in enumerate(headers):
            if cell_index < len(cells):
                cell = cells[cell_index]
                # 检查是否有 Index 属性（表示跳过的列）
                index_attr = cell.get('{urn:schemas-microsoft-com:office:spreadsheet}Index')
                if index_attr:
                    expected_index = int(index_attr) - 1  # Excel 索引从1开始
                    if expected_index > i:
                        # 填充缺失的列
                        values[header] = None
                        continue
                
                data = cell.find('ss:Data', ns)
                if data is not None:
                    val = data.text
                    try:
                        if '.' in str(val):
                            values[header] = float(val)
                        else:
                            values[header] = int(val)
                    except (ValueError, TypeError):
                        values[header] = val
                else:
                    values[header] = None
                cell_index += 1
            else:
                values[header] = None
        
        data_list.append(values)
    
    df = pd.DataFrame(data_list)
    return df, meta


def detect_param_columns(df: pd.DataFrame) -> List[str]:
    """自动检测参数列（排除已知的指标列）"""
    param_cols = []
    for col in df.columns:
        if col is None:
            continue
        col_str = str(col)
        # 排除已知的指标列
        if col_str in METRIC_COLUMNS:
            continue
        # 参数列通常以这些前缀开头
        if (col_str.startswith('Inp') or 
            col_str.startswith('BollMR') or 
            col_str.startswith('TrendPB') or 
            col_str.startswith('Donchian') or 
            col_str.startswith('RF_') or
            col_str.startswith('Regime_') or
            col_str.startswith('MQ_') or
            col_str.startswith('Use')):
            param_cols.append(col_str)
    
    # 如果没找到特定前缀的，就取所有非指标列
    if not param_cols:
        param_cols = [c for c in df.columns if c not in METRIC_COLUMNS and c is not None]
    
    return param_cols


def analyze_quarter(df: pd.DataFrame, q_name: str, param_cols: List[str], 
                    top_n: int = 20, min_profit: float = 0, min_trades: int = 10) -> Dict:
    """分析单个优化结果"""
    print(f"\n{'='*60}")
    print(f"[{q_name}] 优化结果分析")
    print(f"{'='*60}")
    
    print(f"总记录: {len(df)}")
    print(f"参数列: {param_cols}")
    
    # 筛选有效结果
    valid = df.copy()
    
    # 检查必要的列
    required_cols = ['Profit', 'Sharpe Ratio', 'Trades']
    for col in required_cols:
        if col not in valid.columns:
            print(f"警告: 缺少列 '{col}'")
            return {'quarter': q_name, 'valid_count': 0, 'error': f'Missing column: {col}'}
    
    # 过滤条件
    valid = valid[(valid['Profit'] > min_profit) & 
                  (valid['Sharpe Ratio'] > 0) &
                  (valid['Trades'] >= min_trades)].copy()
    
    print(f"有效记录 (Profit>{min_profit}, Sharpe>0, Trades>={min_trades}): {len(valid)}")
    
    if len(valid) == 0:
        print("无有效结果!")
        return {'quarter': q_name, 'valid_count': 0}
    
    # 按收益排序
    sorted_df = valid.sort_values('Profit', ascending=False)
    
    # 动态计算列宽
    param_width = max(len(c) for c in param_cols) if param_cols else 10
    param_width = max(param_width, 10)
    
    print(f"\n前{min(top_n, len(sorted_df))}名:")
    header = f"{'排名':<4} {'收益':>12} {'Sharpe':>8} {'PF':>6} {'DD%':>7} {'Trades':>6}"
    for c in param_cols:
        header += f" {c:>{len(c)}}"
    print(header)
    print("-" * (50 + sum(len(c) for c in param_cols) + len(param_cols)))
    
    top_results = []
    for i, (idx, row) in enumerate(sorted_df.head(top_n).iterrows()):
        params = [f"{row[c]}" for c in param_cols]
        line = f"{i+1:<4} ${row['Profit']:>10.2f} {row['Sharpe Ratio']:>8.2f} {row['Profit Factor']:>6.2f} {row['Equity DD %']:>7.2f} {int(row['Trades']):>6}"
        for j, c in enumerate(param_cols):
            line += f" {params[j]:>{len(c)}}"
        print(line)
        
        top_results.append({
            'rank': i + 1,
            'profit': row['Profit'],
            'sharpe': row['Sharpe Ratio'],
            'profit_factor': row['Profit Factor'],
            'dd_pct': row['Equity DD %'],
            'trades': row['Trades'],
            **{col: row[col] for col in param_cols}
        })
    
    # 参数分布统计
    print(f"\n参数分布 (前{top_n}名):")
    param_stats = {}
    for col in param_cols:
        vals = sorted_df.head(top_n)[col].dropna()
        if len(vals) == 0:
            continue
        
        # 判断是否为整数类型参数
        is_int = all(float(v).is_integer() for v in vals if pd.notna(v))
        
        param_stats[col] = {
            'min': vals.min(),
            'max': vals.max(),
            'mean': vals.mean(),
            'median': vals.median(),
            'mode': vals.mode().iloc[0] if len(vals.mode()) > 0 else vals.median(),
            'is_int': is_int,
            'unique_count': vals.nunique(),
        }
        
        if is_int:
            print(f"  {col}: min={int(param_stats[col]['min'])}, max={int(param_stats[col]['max'])}, "
                  f"mean={param_stats[col]['mean']:.1f}, median={int(param_stats[col]['median'])}, "
                  f"mode={int(param_stats[col]['mode'])}, unique={param_stats[col]['unique_count']}")
        else:
            print(f"  {col}: min={param_stats[col]['min']:.2f}, max={param_stats[col]['max']:.2f}, "
                  f"mean={param_stats[col]['mean']:.2f}, median={param_stats[col]['median']:.2f}, "
                  f"mode={param_stats[col]['mode']:.2f}, unique={param_stats[col]['unique_count']}")
    
    return {
        'quarter': q_name,
        'valid_count': len(valid),
        'top_results': top_results,
        'param_stats': param_stats,
    }


def find_middle_params(quarter_results: List[Dict], param_cols: List[str]) -> Dict:
    """找出参数中间值（适用于单文件或多季度分析）"""
    print(f"\n{'='*60}")
    print("[参数中间值计算]")
    print(f"{'='*60}")
    
    middle_params = {}
    
    for col in param_cols:
        # 收集各结果的中位数和众数
        medians = []
        modes = []
        means = []
        is_int = True
        
        for qr in quarter_results:
            if 'param_stats' in qr and col in qr['param_stats']:
                stats = qr['param_stats'][col]
                medians.append(stats['median'])
                modes.append(stats['mode'])
                means.append(stats['mean'])
                if not stats.get('is_int', True):
                    is_int = False
        
        if len(medians) > 0:
            # 取各结果中位数的中位数作为推荐值
            middle = np.median(medians)
            # 取众数的众数
            if modes:
                mode_val = max(set(modes), key=modes.count)
            else:
                mode_val = middle
            # 取均值的均值
            mean_val = np.mean(means)
            
            # 推荐值：优先用众数，其次中位数
            if is_int:
                recommended = int(round(middle))
            else:
                recommended = round(middle, 2)
            
            middle_params[col] = {
                'median_of_medians': middle,
                'mode_of_modes': mode_val,
                'mean_of_means': mean_val,
                'recommended': recommended,
                'is_int': is_int,
            }
            
            if is_int:
                print(f"\n{col}:")
                print(f"  中位数: {[int(m) for m in medians]}")
                print(f"  众数: {[int(m) for m in modes]}")
                print(f"  -> 推荐值: {recommended}")
            else:
                print(f"\n{col}:")
                print(f"  中位数: {[round(m, 2) for m in medians]}")
                print(f"  众数: {[round(m, 2) for m in modes]}")
                print(f"  -> 推荐值: {recommended}")
    
    return middle_params


def generate_set_file(middle_params: Dict, output_path: str = None):
    """生成 .set 配置文件"""
    lines = []
    for col, vals in middle_params.items():
        v = vals['recommended']
        lines.append(f"{col}={v}||{v} {v} {v}||")
    
    if output_path:
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write('\n'.join(lines))
        print(f"\n.set 文件已保存: {output_path}")
    
    return lines


def main():
    parser = argparse.ArgumentParser(description='分析MT5优化结果XML')
    parser.add_argument('--xml', required=False, help='XML文件路径（单文件模式）')
    parser.add_argument('--q1', required=False, help='Q1 XML路径（兼容旧参数）')
    parser.add_argument('--top', type=int, default=20, help='显示前N个结果')
    parser.add_argument('--min-profit', type=float, default=0, help='最小利润过滤')
    parser.add_argument('--min-trades', type=int, default=10, help='最小交易次数过滤')
    parser.add_argument('--output', type=str, default=None, help='输出 .set 文件路径')
    args = parser.parse_args()
    
    # 兼容 --q1 参数
    xml_path = args.xml or args.q1
    if not xml_path:
        parser.error("请提供 --xml 参数")
    
    print("\n" + "="*70)
    print("[MT5 优化结果分析]")
    print("="*70)
    
    # 解析XML
    print(f"\n解析: {xml_path}")
    try:
        df, meta = parse_optimization_xml(xml_path)
    except Exception as e:
        print(f"解析错误: {e}")
        return
    
    # 打印元信息
    if meta.get('Title'):
        print(f"策略: {meta['Title']}")
    if meta.get('Deposit'):
        print(f"初始资金: {meta['Deposit']}")
    if meta.get('Leverage'):
        print(f"杠杆: {meta['Leverage']}")
    
    # 自动检测参数列
    param_cols = detect_param_columns(df)
    
    if not param_cols:
        print("警告: 未检测到参数列，显示所有非指标列")
        param_cols = [c for c in df.columns if c not in METRIC_COLUMNS]
    
    print(f"\n检测到参数列 ({len(param_cols)}个): {param_cols}")
    
    # 分析结果
    result = analyze_quarter(df, 'All', param_cols, args.top, args.min_profit, args.min_trades)
    
    if result['valid_count'] == 0:
        print("\n无有效结果，请检查过滤条件")
        return
    
    # 计算推荐参数
    middle_params = find_middle_params([result], param_cols)
    
    # 输出推荐参数
    print(f"\n{'='*60}")
    print("[推荐参数]")
    print(f"{'='*60}")
    
    print("\nSET格式:")
    for col, vals in middle_params.items():
        v = vals['recommended']
        print(f"{col}={v}||{v} {v} {v}||")
    
    # 生成 .set 文件
    # if args.output:
    #     generate_set_file(middle_params, args.output)
    # else:
    #     # 自动生成文件名
    #     timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    #     strategy_name = meta.get('Title', 'unknown').split()[0] if meta.get('Title') else 'params'
    #     auto_output = f"{strategy_name}_optimized_{timestamp}.set"
    #     generate_set_file(middle_params, auto_output)
    
    # 参数汇总表
    print(f"\n{'='*60}")
    print("[参数汇总]")
    print(f"{'='*60}")
    print(f"{'参数':<30} {'推荐值':>10} {'最小值':>10} {'最大值':>10} {'均值':>10}")
    print("-" * 75)
    for col in param_cols:
        if col in middle_params:
            vals = middle_params[col]
            stats = result['param_stats'].get(col, {})
            v = vals['recommended']
            min_v = stats.get('min', '-')
            max_v = stats.get('max', '-')
            mean_v = stats.get('mean', '-')
            
            if vals.get('is_int', True):
                print(f"{col:<30} {v:>10} {int(min_v):>10} {int(max_v):>10} {mean_v:>10.1f}")
            else:
                print(f"{col:<30} {v:>10} {min_v:>10.2f} {max_v:>10.2f} {mean_v:>10.2f}")


if __name__ == '__main__':
    main()
