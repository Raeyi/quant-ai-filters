# compare_mt5_exported_data.py
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import matplotlib.pyplot as plt
from scipy import stats
import seaborn as sns
import warnings
import os
warnings.filterwarnings('ignore')

class MT5DataComparator:
    def __init__(self, file1, file2, broker1_name="IC Markets", broker2_name="Doo Prime"):
        """
        初始化MT5导出数据对比器
        
        参数：
        file1: 第一个经纪商CSV文件路径
        file2: 第二个经纪商CSV文件路径
        broker1_name: 第一个经纪商名称
        broker2_name: 第二个经纪商名称
        """
        self.file1 = file1
        self.file2 = file2
        self.broker1_name = broker1_name
        self.broker2_name = broker2_name
        self.df1 = None
        self.df2 = None
        self.common_data = None
        
    def load_mt5_export_data(self, file_path):
        """加载MT5导出的CSV数据（制表符分隔，有表头）"""
        print(f"加载文件: {os.path.basename(file_path)}")
        
        try:
            # 使用制表符分隔符，指定列名
            df = pd.read_csv(
                file_path, 
                sep='\t',  # 制表符分隔
                header=0,  # 有表头
                parse_dates={'DateTime': ['<DATE>', '<TIME>']},  # 合并日期时间列
                dayfirst=False,  # 日期格式为年.月.日
                dtype={
                    '<OPEN>': float,
                    '<HIGH>': float,
                    '<LOW>': float,
                    '<CLOSE>': float,
                    '<TICKVOL>': int,
                    '<VOL>': int,
                    '<SPREAD>': int
                }
            )
            
            # 重命名列，去掉尖括号
            df = df.rename(columns={
                '<OPEN>': 'Open',
                '<HIGH>': 'High',
                '<LOW>': 'Low',
                '<CLOSE>': 'Close',
                '<TICKVOL>': 'TickVolume',
                '<VOL>': 'Volume',
                '<SPREAD>': 'Spread'
            })
            
            # 设置DateTime为索引
            df.set_index('DateTime', inplace=True)
            df.sort_index(inplace=True)
            
            print(f"  ✅ 成功加载 {len(df)} 行数据")
            print(f"     时间范围: {df.index.min()} 到 {df.index.max()}")
            print(f"     列: {', '.join(df.columns.tolist())}")
            
            return df
            
        except Exception as e:
            print(f"  ❌ 加载失败: {e}")
            
            # 尝试另一种加载方式
            try:
                print("  尝试备用加载方式...")
                df = pd.read_csv(file_path, sep='\t')
                
                # 检查列名
                print(f"  检测到的列名: {list(df.columns)}")
                
                # 尝试合并日期时间
                if '<DATE>' in df.columns and '<TIME>' in df.columns:
                    df['DateTime'] = pd.to_datetime(
                        df['<DATE>'] + ' ' + df['<TIME>'],
                        format='%Y.%m.%d %H:%M:%S'
                    )
                    df.set_index('DateTime', inplace=True)
                    df.sort_index(inplace=True)
                    
                    # 重命名列
                    rename_dict = {}
                    for col in df.columns:
                        if col.startswith('<') and col.endswith('>'):
                            rename_dict[col] = col.strip('<>')
                    
                    df = df.rename(columns=rename_dict)
                    
                    print(f"  ✅ 备用方式成功加载 {len(df)} 行")
                    return df
                    
            except Exception as e2:
                print(f"  ❌ 备用方式也失败: {e2}")
            
            return None
    
    def load_data(self):
        """加载两个CSV文件"""
        print("正在加载数据...\n")
        
        # 加载第一个文件
        self.df1 = self.load_mt5_export_data(self.file1)
        if self.df1 is None:
            print(f"❌ 无法加载 {self.broker1_name} 数据")
            return False
        
        print()  # 空行
        
        # 加载第二个文件
        self.df2 = self.load_mt5_export_data(self.file2)
        if self.df2 is None:
            print(f"❌ 无法加载 {self.broker2_name} 数据")
            return False
        
        return True
    
    def get_common_time_range(self):
        """获取共同的时间范围"""
        if self.df1 is None or self.df2 is None:
            print("❌ 数据未加载")
            return None, None
        
        start1, end1 = self.df1.index.min(), self.df1.index.max()
        start2, end2 = self.df2.index.min(), self.df2.index.max()
        
        common_start = max(start1, start2)
        common_end = min(end1, end2)
        
        print(f"\n时间范围对比:")
        print(f"{self.broker1_name}: {start1} 到 {end1}")
        print(f"{self.broker2_name}: {start2} 到 {end2}")
        print(f"共同时间范围: {common_start} 到 {common_end}")
        
        # 计算重叠天数
        if common_start < common_end:
            overlap_days = (common_end - common_start).days
            print(f"重叠天数: {overlap_days} 天")
        else:
            print("⚠️  无重叠时间范围")
        
        return common_start, common_end
    
    def align_data(self, tolerance='5min'):
        """
        对齐数据，允许时间戳有微小差异
        
        参数：
        tolerance: 时间容差，如 '5min' 表示允许5分钟内的差异
        """
        if self.df1 is None or self.df2 is None:
            print("❌ 数据未加载")
            return None
        
        print(f"\n对齐数据，时间容差: {tolerance}")
        
        # 获取两个数据集的索引
        index1 = self.df1.index
        index2 = self.df2.index
        
        # 找出最接近的时间匹配
        aligned_data = []
        
        # 为每个时间点找到最接近的匹配
        for idx in index1:
            # 在index2中找最接近的时间
            time_diffs = abs(index2 - idx)
            if len(time_diffs) > 0:
                min_diff = time_diffs.min()
                closest_idx = index2[time_diffs.argmin()]
                
                # 如果时间差在容差范围内，则视为匹配
                if min_diff <= pd.Timedelta(tolerance):
                    aligned_data.append({
                        'DateTime': idx,
                        f'Open_{self.broker1_name}': self.df1.loc[idx, 'Open'],
                        f'High_{self.broker1_name}': self.df1.loc[idx, 'High'],
                        f'Low_{self.broker1_name}': self.df1.loc[idx, 'Low'],
                        f'Close_{self.broker1_name}': self.df1.loc[idx, 'Close'],
                        f'Open_{self.broker2_name}': self.df2.loc[closest_idx, 'Open'],
                        f'High_{self.broker2_name}': self.df2.loc[closest_idx, 'High'],
                        f'Low_{self.broker2_name}': self.df2.loc[closest_idx, 'Low'],
                        f'Close_{self.broker2_name}': self.df2.loc[closest_idx, 'Close'],
                        'Time_Diff_Seconds': min_diff.total_seconds()
                    })
        
        if aligned_data:
            self.common_data = pd.DataFrame(aligned_data)
            self.common_data.set_index('DateTime', inplace=True)
            self.common_data.sort_index(inplace=True)
            
            print(f"✅ 对齐完成，找到 {len(self.common_data)} 个匹配的时间点")
            
            # 分析时间差异
            if 'Time_Diff_Seconds' in self.common_data.columns:
                time_diffs = self.common_data['Time_Diff_Seconds']
                print(f"时间差异统计:")
                print(f"  平均差异: {time_diffs.mean():.1f} 秒")
                print(f"  最大差异: {time_diffs.max():.1f} 秒")
                print(f"  差异为0的数量: {(time_diffs == 0).sum()} 个")
            
            return self.common_data
        else:
            print("❌ 未找到匹配的时间点")
            return None
    
    def analyze_differences(self, price_threshold=0.1):
        """分析数据差异"""
        if self.common_data is None or len(self.common_data) == 0:
            print("❌ 没有共同数据用于分析")
            return
        
        print("\n" + "="*70)
        print("XAUUSD M5历史数据对比分析报告")
        print("="*70)
        
        # 1. 基本统计
        print(f"\n1. 基本统计对比 (基于 {len(self.common_data)} 个匹配点):")
        
        for price_type in ['Open', 'High', 'Low', 'Close']:
            col1 = f'{price_type}_{self.broker1_name}'
            col2 = f'{price_type}_{self.broker2_name}'
            
            if col1 in self.common_data.columns and col2 in self.common_data.columns:
                data1 = self.common_data[col1]
                data2 = self.common_data[col2]
                
                mean1 = data1.mean()
                mean2 = data2.mean()
                mean_diff = mean1 - mean2
                mean_pct_diff = (mean_diff / mean1) * 100
                
                print(f"\n{price_type}价格:")
                print(f"  {self.broker1_name}: ${mean1:.2f}")
                print(f"  {self.broker2_name}: ${mean2:.2f}")
                print(f"  平均差异: ${mean_diff:.4f} ({mean_pct_diff:.4f}%)")
        
        # 2. 详细差异分析
        print(f"\n2. 详细差异分析 (阈值: ${price_threshold}):")
        
        price_stats = {}
        
        for price_type in ['Open', 'High', 'Low', 'Close']:
            col1 = f'{price_type}_{self.broker1_name}'
            col2 = f'{price_type}_{self.broker2_name}'
            
            if col1 in self.common_data.columns and col2 in self.common_data.columns:
                diff = self.common_data[col1] - self.common_data[col2]
                abs_diff = abs(diff)
                
                stats_dict = {
                    'mean': diff.mean(),
                    'std': diff.std(),
                    'max': diff.max(),
                    'min': diff.min(),
                    'abs_mean': abs_diff.mean(),
                    'abs_max': abs_diff.max(),
                    'abs_min': abs_diff.min(),
                    'median': diff.median(),
                    'pct_over_threshold': (abs_diff > price_threshold).mean() * 100,
                    'count_over_threshold': (abs_diff > price_threshold).sum()
                }
                
                price_stats[price_type] = stats_dict
                
                print(f"\n{price_type}价格差异:")
                print(f"  均值: ${stats_dict['mean']:.4f}")
                print(f"  标准差: ${stats_dict['std']:.4f}")
                print(f"  绝对值均值: ${stats_dict['abs_mean']:.4f}")
                print(f"  中位数: ${stats_dict['median']:.4f}")
                print(f"  最大值: ${stats_dict['max']:.4f}")
                print(f"  最小值: ${stats_dict['min']:.4f}")
                print(f"  绝对最大值: ${stats_dict['abs_max']:.4f}")
                print(f"  超过${price_threshold}的比例: {stats_dict['pct_over_threshold']:.2f}% "
                      f"({stats_dict['count_over_threshold']}/{len(diff)})")
        
        # 3. 找出差异最大的时间点
        print(f"\n3. 收盘价差异最大的时间点 (前10个):")
        
        if f'Close_{self.broker1_name}' in self.common_data.columns and f'Close_{self.broker2_name}' in self.common_data.columns:
            close_diff = abs(self.common_data[f'Close_{self.broker1_name}'] - self.common_data[f'Close_{self.broker2_name}'])
            top10 = close_diff.nlargest(10)
            
            if len(top10) > 0:
                for idx, diff_val in top10.items():
                    price1 = self.common_data.loc[idx, f'Close_{self.broker1_name}']
                    price2 = self.common_data.loc[idx, f'Close_{self.broker2_name}']
                    actual_diff = price1 - price2
                    
                    # 获取时间差异
                    time_diff = ""
                    if 'Time_Diff_Seconds' in self.common_data.columns:
                        time_diff = f", 时间差: {self.common_data.loc[idx, 'Time_Diff_Seconds']:.0f}秒"
                    
                    print(f"  {idx}: {self.broker1_name}=${price1:.2f}, "
                          f"{self.broker2_name}=${price2:.2f}, "
                          f"差异=${actual_diff:.4f}{time_diff}")
        
        return price_stats
    
    def generate_visualization(self, output_dir="./comparison_results"):
        """生成可视化图表"""
        if self.common_data is None or len(self.common_data) == 0:
            print("❌ 没有共同数据用于可视化")
            return
        
        os.makedirs(output_dir, exist_ok=True)
        
        # 设置图形样式
        plt.style.use('seaborn-v0_8-darkgrid')
        fig = plt.figure(figsize=(18, 12))
        
        # 1. 价格对比折线图
        ax1 = plt.subplot(3, 3, 1)
        if f'Close_{self.broker1_name}' in self.common_data.columns and f'Close_{self.broker2_name}' in self.common_data.columns:
            # 随机采样100个点显示，避免过密
            sample_size = min(100, len(self.common_data))
            sample_indices = np.random.choice(len(self.common_data), sample_size, replace=False)
            sample_data = self.common_data.iloc[sample_indices].sort_index()
            
            ax1.plot(sample_data.index, sample_data[f'Close_{self.broker1_name}'], 
                    label=self.broker1_name, alpha=0.7, linewidth=1.5, marker='o', markersize=3)
            ax1.plot(sample_data.index, sample_data[f'Close_{self.broker2_name}'], 
                    label=self.broker2_name, alpha=0.7, linewidth=1.5, marker='s', markersize=3)
            ax1.set_title('收盘价对比 (随机采样100点)')
            ax1.set_xlabel('时间')
            ax1.set_ylabel('价格 (美元)')
            ax1.legend(loc='best')
            ax1.grid(True, alpha=0.3)
            plt.setp(ax1.xaxis.get_majorticklabels(), rotation=45, ha='right')
        
        # 2. 价格差异分布直方图
        ax2 = plt.subplot(3, 3, 2)
        if f'Close_{self.broker1_name}' in self.common_data.columns and f'Close_{self.broker2_name}' in self.common_data.columns:
            diff = self.common_data[f'Close_{self.broker1_name}'] - self.common_data[f'Close_{self.broker2_name}']
            
            # 过滤极端值
            q_low = diff.quantile(0.01)
            q_high = diff.quantile(0.99)
            filtered_diff = diff[(diff >= q_low) & (diff <= q_high)]
            
            ax2.hist(filtered_diff, bins=50, alpha=0.7, edgecolor='black', density=True)
            ax2.axvline(x=0, color='red', linestyle='--', linewidth=2, label='零差异')
            
            # 添加均值和标准差线
            mean_diff = diff.mean()
            std_diff = diff.std()
            ax2.axvline(x=mean_diff, color='green', linestyle='-', linewidth=2, 
                       label=f'均值: ${mean_diff:.4f}')
            ax2.axvline(x=mean_diff + std_diff, color='orange', linestyle=':', linewidth=1.5)
            ax2.axvline(x=mean_diff - std_diff, color='orange', linestyle=':', linewidth=1.5)
            ax2.fill_betweenx([0, ax2.get_ylim()[1]], mean_diff - std_diff, mean_diff + std_diff, 
                             alpha=0.2, color='orange', label='±1标准差')
            
            ax2.set_title('收盘价差异分布 (过滤1%极端值)')
            ax2.set_xlabel('价格差异 (美元)')
            ax2.set_ylabel('密度')
            ax2.legend(loc='best')
            ax2.grid(True, alpha=0.3)
        
        # 3. 散点图
        ax3 = plt.subplot(3, 3, 3)
        if f'Close_{self.broker1_name}' in self.common_data.columns and f'Close_{self.broker2_name}' in self.common_data.columns:
            # 采样显示
            sample_size = min(500, len(self.common_data))
            sample_indices = np.random.choice(len(self.common_data), sample_size, replace=False)
            sample_data = self.common_data.iloc[sample_indices]
            
            ax3.scatter(sample_data[f'Close_{self.broker1_name}'], 
                       sample_data[f'Close_{self.broker2_name}'], 
                       alpha=0.5, s=20, c='blue')
            
            # 添加对角线
            min_price = min(sample_data[f'Close_{self.broker1_name}'].min(), 
                           sample_data[f'Close_{self.broker2_name}'].min())
            max_price = max(sample_data[f'Close_{self.broker1_name}'].max(), 
                           sample_data[f'Close_{self.broker2_name}'].max())
            ax3.plot([min_price, max_price], [min_price, max_price], 
                    'r--', alpha=0.7, linewidth=1.5, label='完美一致线')
            
            # 计算相关性
            if len(sample_data) > 1:
                corr = sample_data[f'Close_{self.broker1_name}'].corr(sample_data[f'Close_{self.broker2_name}'])
                ax3.text(0.05, 0.95, f'相关性: {corr:.6f}', 
                        transform=ax3.transAxes, fontsize=10,
                        verticalalignment='top',
                        bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.8))
            
            ax3.set_title('收盘价散点图 (随机采样500点)')
            ax3.set_xlabel(f'{self.broker1_name} 收盘价')
            ax3.set_ylabel(f'{self.broker2_name} 收盘价')
            ax3.legend(loc='best')
            ax3.grid(True, alpha=0.3)
        
        # 4. 差异时间序列
        ax4 = plt.subplot(3, 3, 4)
        if f'Close_{self.broker1_name}' in self.common_data.columns and f'Close_{self.broker2_name}' in self.common_data.columns:
            diff = self.common_data[f'Close_{self.broker1_name}'] - self.common_data[f'Close_{self.broker2_name}']
            
            # 采样显示
            sample_size = min(500, len(diff))
            sample_indices = np.random.choice(len(diff), sample_size, replace=False)
            sample_diff = diff.iloc[sample_indices].sort_index()
            
            ax4.plot(sample_diff.index, sample_diff.values, alpha=0.7, linewidth=1)
            ax4.axhline(y=0, color='red', linestyle='--', linewidth=1.5)
            ax4.axhline(y=diff.mean(), color='green', linestyle='-', linewidth=1.5, 
                       label=f'均值: ${diff.mean():.4f}')
            
            # 添加±2标准差带
            std_val = diff.std()
            ax4.fill_between(sample_diff.index, -2*std_val, 2*std_val, 
                            alpha=0.2, color='gray', label='±2标准差')
            
            ax4.set_title('收盘价差异时间序列 (随机采样500点)')
            ax4.set_xlabel('时间')
            ax4.set_ylabel('价格差异 (美元)')
            ax4.legend(loc='best')
            ax4.grid(True, alpha=0.3)
            plt.setp(ax4.xaxis.get_majorticklabels(), rotation=45, ha='right')
        
        # 5. 四种价格类型的平均差异
        ax5 = plt.subplot(3, 3, 5)
        price_types = ['Open', 'High', 'Low', 'Close']
        mean_diffs = []
        abs_mean_diffs = []
        
        for pt in price_types:
            col1 = f'{pt}_{self.broker1_name}'
            col2 = f'{pt}_{self.broker2_name}'
            
            if col1 in self.common_data.columns and col2 in self.common_data.columns:
                diff = self.common_data[col1] - self.common_data[col2]
                mean_diffs.append(diff.mean())
                abs_mean_diffs.append(abs(diff).mean())
        
        x = np.arange(len(price_types))
        width = 0.35
        
        bars1 = ax5.bar(x - width/2, mean_diffs, width, label='均值差异', alpha=0.7, color='skyblue')
        bars2 = ax5.bar(x + width/2, abs_mean_diffs, width, label='绝对均值差异', alpha=0.7, color='lightcoral')
        
        ax5.set_title('各类价格差异对比')
        ax5.set_ylabel('差异 (美元)')
        ax5.set_xticks(x)
        ax5.set_xticklabels(price_types)
        ax5.legend(loc='best')
        ax5.grid(True, alpha=0.3, axis='y')
        
        # 在柱状图上添加数值
        for bar, val in zip(bars1, mean_diffs):
            height = bar.get_height()
            ax5.text(bar.get_x() + bar.get_width()/2., height + (0.0001 if height >= 0 else -0.001),
                    f'{val:.4f}', ha='center', va='bottom' if height >= 0 else 'top', fontsize=9)
        
        for bar, val in zip(bars2, abs_mean_diffs):
            height = bar.get_height()
            ax5.text(bar.get_x() + bar.get_width()/2., height + 0.0001,
                    f'{val:.4f}', ha='center', va='bottom', fontsize=9)
        
        # 6. 箱线图
        ax6 = plt.subplot(3, 3, 6)
        diff_data = []
        labels = []
        
        for pt in price_types:
            col1 = f'{pt}_{self.broker1_name}'
            col2 = f'{pt}_{self.broker2_name}'
            
            if col1 in self.common_data.columns and col2 in self.common_data.columns:
                diff = self.common_data[col1] - self.common_data[col2]
                # 过滤极端值
                q_low = diff.quantile(0.01)
                q_high = diff.quantile(0.99)
                filtered_diff = diff[(diff >= q_low) & (diff <= q_high)]
                diff_data.append(filtered_diff.values)
                labels.append(pt)
        
        if diff_data:
            box = ax6.boxplot(diff_data, labels=labels, patch_artist=True, showfliers=False)
            
            # 设置箱线图颜色
            colors = ['lightblue', 'lightgreen', 'lightcoral', 'lightsalmon']
            for patch, color in zip(box['boxes'], colors):
                patch.set_facecolor(color)
            
            ax6.axhline(y=0, color='red', linestyle='--', linewidth=1.5)
            ax6.set_title('价格差异箱线图 (过滤1%极端值)')
            ax6.set_ylabel('价格差异 (美元)')
            ax6.grid(True, alpha=0.3, axis='y')
        
        # 7. 时间差异分布
        ax7 = plt.subplot(3, 3, 7)
        if 'Time_Diff_Seconds' in self.common_data.columns:
            time_diffs = self.common_data['Time_Diff_Seconds']
            
            # 转换为分钟
            time_diffs_min = time_diffs / 60
            
            ax7.hist(time_diffs_min, bins=50, alpha=0.7, edgecolor='black')
            ax7.axvline(x=0, color='red', linestyle='--', linewidth=2, label='零差异')
            ax7.axvline(x=time_diffs_min.mean(), color='green', linestyle='-', 
                       linewidth=2, label=f'均值: {time_diffs_min.mean():.2f}分钟')
            
            ax7.set_title('时间匹配差异分布')
            ax7.set_xlabel('时间差异 (分钟)')
            ax7.set_ylabel('频数')
            ax7.legend(loc='best')
            ax7.grid(True, alpha=0.3)
        
        # 8. 累积分布函数
        ax8 = plt.subplot(3, 3, 8)
        if f'Close_{self.broker1_name}' in self.common_data.columns and f'Close_{self.broker2_name}' in self.common_data.columns:
            diff = abs(self.common_data[f'Close_{self.broker1_name}'] - self.common_data[f'Close_{self.broker2_name}'])
            
            # 计算CDF
            sorted_diff = np.sort(diff)
            cdf = np.arange(1, len(sorted_diff) + 1) / len(sorted_diff)
            
            ax8.plot(sorted_diff, cdf, linewidth=2)
            ax8.set_title('价格差异累积分布函数')
            ax8.set_xlabel('绝对价格差异 (美元)')
            ax8.set_ylabel('累积概率')
            ax8.grid(True, alpha=0.3)
            
            # 添加关键阈值线
            thresholds = [0.01, 0.05, 0.1, 0.5]
            for threshold in thresholds:
                pct_below = (diff <= threshold).mean() * 100
                ax8.axvline(x=threshold, color='gray', linestyle=':', alpha=0.7)
                ax8.text(threshold, 0.5, f'{pct_below:.1f}% ≤${threshold}', 
                        rotation=90, fontsize=8, verticalalignment='center')
        
        # 9. 热力图 - 差异随时间变化
        ax9 = plt.subplot(3, 3, 9)
        if f'Close_{self.broker1_name}' in self.common_data.columns and f'Close_{self.broker2_name}' in self.common_data.columns:
            diff = self.common_data[f'Close_{self.broker1_name}'] - self.common_data[f'Close_{self.broker2_name}']
            
            # 创建时间序列热力图数据
            diff_series = diff.resample('D').mean()  # 按日平均
            
            if len(diff_series) > 0:
                # 转换为二维数据
                dates = diff_series.index
                # 这里我们简单显示时间序列
                ax9.plot(dates, diff_series.values, alpha=0.7, linewidth=1)
                ax9.axhline(y=0, color='red', linestyle='--', linewidth=1.5)
                ax9.fill_between(dates, 0, diff_series.values, 
                                where=diff_series.values >= 0, 
                                alpha=0.3, color='green', interpolate=True)
                ax9.fill_between(dates, 0, diff_series.values, 
                                where=diff_series.values < 0, 
                                alpha=0.3, color='red', interpolate=True)
                
                ax9.set_title('收盘价差异日平均值')
                ax9.set_xlabel('日期')
                ax9.set_ylabel('平均差异 (美元)')
                ax9.grid(True, alpha=0.3)
                plt.setp(ax9.xaxis.get_majorticklabels(), rotation=45, ha='right')
        
        plt.suptitle(f'{self.broker1_name} vs {self.broker2_name} - XAUUSD M5数据对比分析', 
                    fontsize=18, fontweight='bold', y=0.98)
        plt.tight_layout(rect=[0, 0.03, 1, 0.95])
        
        # 保存图表
        output_path = os.path.join(output_dir, f'comparison_{self.broker1_name}_vs_{self.broker2_name}.png')
        plt.savefig(output_path, dpi=300, bbox_inches='tight')
        plt.close()
        
        print(f"\n📈 可视化图表已保存到: {output_path}")
        
        # 保存差异数据
        self.save_difference_data(output_dir)
        
        # 生成总结报告
        self.generate_summary_report(output_dir)
    
    def save_difference_data(self, output_dir):
        """保存差异数据到CSV"""
        if self.common_data is None or len(self.common_data) == 0:
            return
        
        # 保存完整对齐数据
        output_path = os.path.join(output_dir, f'aligned_data_{self.broker1_name}_vs_{self.broker2_name}.csv')
        self.common_data.to_csv(output_path)
        
        print(f"📊 对齐数据已保存到: {output_path}")
        
        # 保存显著差异记录
        if f'Close_{self.broker1_name}' in self.common_data.columns and f'Close_{self.broker2_name}' in self.common_data.columns:
            close_diff = abs(self.common_data[f'Close_{self.broker1_name}'] - self.common_data[f'Close_{self.broker2_name}'])
            significant_diffs = self.common_data[close_diff > 0.1]  # 差异大于0.1美元
            
            if len(significant_diffs) > 0:
                sig_path = os.path.join(output_dir, f'significant_differences_{self.broker1_name}_vs_{self.broker2_name}.csv')
                significant_diffs.to_csv(sig_path)
                print(f"📊 显著差异记录已保存到: {sig_path}")
                print(f"    显著差异数量: {len(significant_diffs)} 条")
    
    def generate_summary_report(self, output_dir):
        """生成总结报告"""
        if self.common_data is None or len(self.common_data) == 0:
            return
        
        report_path = os.path.join(output_dir, f'summary_report_{self.broker1_name}_vs_{self.broker2_name}.txt')
        
        with open(report_path, 'w', encoding='utf-8') as f:
            f.write("="*80 + "\n")
            f.write(f"XAUUSD M5历史数据对比分析报告\n")
            f.write(f"对比对象: {self.broker1_name} vs {self.broker2_name}\n")
            f.write(f"生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write("="*80 + "\n\n")
            
            f.write("1. 数据基本信息\n")
            f.write("-"*40 + "\n")
            f.write(f"{self.broker1_name} 原始数据量: {len(self.df1) if self.df1 is not None else 0} 行\n")
            f.write(f"{self.broker2_name} 原始数据量: {len(self.df2) if self.df2 is not None else 0} 行\n")
            f.write(f"匹配数据量: {len(self.common_data)} 行\n\n")
            
            f.write("2. 时间范围\n")
            f.write("-"*40 + "\n")
            if self.df1 is not None:
                f.write(f"{self.broker1_name}: {self.df1.index.min()} 到 {self.df1.index.max()}\n")
            if self.df2 is not None:
                f.write(f"{self.broker2_name}: {self.df2.index.min()} 到 {self.df2.index.max()}\n")
            f.write(f"匹配范围: {self.common_data.index.min()} 到 {self.common_data.index.max()}\n\n")
            
            f.write("3. 价格差异关键统计\n")
            f.write("-"*40 + "\n")
            
            for price_type in ['Open', 'High', 'Low', 'Close']:
                col1 = f'{price_type}_{self.broker1_name}'
                col2 = f'{price_type}_{self.broker2_name}'
                
                if col1 in self.common_data.columns and col2 in self.common_data.columns:
                    diff = self.common_data[col1] - self.common_data[col2]
                    abs_diff = abs(diff)
                    
                    f.write(f"\n{price_type}价格差异:\n")
                    f.write(f"  均值: ${diff.mean():.6f}\n")
                    f.write(f"  标准差: ${diff.std():.6f}\n")
                    f.write(f"  中位数: ${diff.median():.6f}\n")
                    f.write(f"  最大值: ${diff.max():.6f}\n")
                    f.write(f"  最小值: ${diff.min():.6f}\n")
                    f.write(f"  绝对均值: ${abs_diff.mean():.6f}\n")
                    f.write(f"  绝对最大值: ${abs_diff.max():.6f}\n")
                    
                    # 差异分布
                    thresholds = [0.01, 0.05, 0.1, 0.5]
                    for threshold in thresholds:
                        pct_over = (abs_diff > threshold).mean() * 100
                        f.write(f"  差异超过${threshold}: {pct_over:.2f}%\n")
            
            f.write("\n4. 数据质量评估\n")
            f.write("-"*40 + "\n")
            
            if f'Close_{self.broker1_name}' in self.common_data.columns and f'Close_{self.broker2_name}' in self.common_data.columns:
                close_diff = self.common_data[f'Close_{self.broker1_name}'] - self.common_data[f'Close_{self.broker2_name}']
                mean_abs_diff = abs(close_diff).mean()
                
                f.write(f"收盘价平均绝对差异: ${mean_abs_diff:.6f}\n\n")
                
                f.write("评估标准:\n")
                f.write("  < $0.01: 优秀 (数据几乎完全一致)\n")
                f.write("  $0.01-$0.05: 良好 (数据基本一致)\n")
                f.write("  $0.05-$0.10: 中等 (有可察觉差异)\n")
                f.write("  > $0.10: 较差 (差异较大)\n\n")
                
                f.write("评估结果: ")
                if mean_abs_diff < 0.01:
                    f.write("✅ 优秀\n")
                elif mean_abs_diff < 0.05:
                    f.write("⚠️  良好\n")
                elif mean_abs_diff < 0.1:
                    f.write("⚠️  中等\n")
                else:
                    f.write("❌ 较差\n")
            
            f.write("\n5. 对回测影响的建议\n")
            f.write("-"*40 + "\n")
            
            if f'Close_{self.broker1_name}' in self.common_data.columns and f'Close_{self.broker2_name}' in self.common_data.columns:
                close_diff = self.common_data[f'Close_{self.broker1_name}'] - self.common_data[f'Close_{self.broker2_name}']
                mean_abs_diff = abs(close_diff).mean()
                
                if mean_abs_diff < 0.01:
                    f.write("✅ 回测影响: 极小\n")
                    f.write("   可以直接使用任意经纪商数据，回测结果基本一致\n")
                elif mean_abs_diff < 0.05:
                    f.write("⚠️  回测影响: 较小\n")
                    f.write("   建议使用权威数据源，但回测差异在可接受范围内\n")
                elif mean_abs_diff < 0.1:
                    f.write("⚠️  回测影响: 中等\n")
                    f.write("   回测结果可能有明显差异，建议使用权威数据源\n")
                else:
                    f.write("❌ 回测影响: 较大\n")
                    f.write("   回测结果可能显著不同，必须使用权威数据源\n")
                    f.write("   考虑策略对数据质量的敏感性\n")
        
        print(f"📄 总结报告已保存到: {report_path}")

def main():
    """主函数"""
    # 文件路径 - 根据您的实际路径修改
    broker1_file = r"E:\mt5_test_datas\ECmt5data\XAUUSD_M5_202501020100_202601302350.csv"
    broker2_file = r"E:\mt5_test_datas\Doomt5data\XAUUSD.s_M5_202501020100_202601302350.csv"
    
    # 检查文件是否存在
    for file_path, broker_name in [(broker1_file, "IC Markets"), (broker2_file, "Doo Prime")]:
        if not os.path.exists(file_path):
            print(f"❌ 文件不存在: {file_path}")
            print(f"请检查文件路径是否正确")
            return
    
    # 创建对比器
    comparator = MT5DataComparator(
        file1=broker1_file,
        file2=broker2_file,
        broker1_name="IC Markets",
        broker2_name="Doo Prime"
    )
    
    # 加载数据
    if not comparator.load_data():
        print("❌ 数据加载失败")
        return
    
    # 获取共同时间范围
    comparator.get_common_time_range()
    
    # 对齐数据
    common_data = comparator.align_data(tolerance='5min')
    if common_data is None:
        print("❌ 数据对齐失败")
        return
    
    # 分析差异
    price_stats = comparator.analyze_differences(price_threshold=0.1)
    
    # 生成可视化
    comparator.generate_visualization()
    
    print("\n" + "="*70)
    print("✅ 对比分析完成！")
    print("="*70)
    print("\n输出文件保存在: ./comparison_results/ 目录")
    print("1. 可视化图表: comparison_IC_Markets_vs_Doo_Prime.png")
    print("2. 对齐数据: aligned_data_IC_Markets_vs_Doo_Prime.csv")
    print("3. 总结报告: summary_report_IC_Markets_vs_Doo_Prime.txt")
    print("4. 显著差异: significant_differences_IC_Markets_vs_Doo_Prime.csv")
    print("\n建议:")
    print("查看总结报告了解数据质量评估和对回测的影响建议")

if __name__ == "__main__":
    main()