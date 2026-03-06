# preprocess_data.py
import pandas as pd
import numpy as np
import os
from datetime import datetime
import pyarrow as pa
import pyarrow.parquet as pq
import warnings
warnings.filterwarnings('ignore')

def preprocess_mt5_data(csv_path, output_parquet_path=None, chunksize=1000000):
    """
    预处理MT5 CSV数据，优化内存使用并转换为Parquet格式
    
    参数:
        csv_path: 原始CSV文件路径
        output_parquet_path: 输出Parquet文件路径
        chunksize: 分块大小
    """
    print(f"开始处理文件: {csv_path}")
    print(f"文件大小: {os.path.getsize(csv_path) / (1024**3):.2f} GB")
    
    if output_parquet_path is None:
        output_parquet_path = csv_path.replace('.csv', '.parquet')
    
    # 第一步：分块读取并优化
    print("\n第一步：分块读取并优化数据类型...")
    
    chunks = []
    total_rows = 0
    
    # 先读取一小部分数据来推断列类型
    sample = pd.read_csv(csv_path, sep='\t', nrows=1000)
    print(f"检测到列: {list(sample.columns)}")
    
    # 优化数据类型
    dtypes = {}
    for col in sample.columns:
        if sample[col].dtype == 'float64':
            dtypes[col] = np.float32
        elif sample[col].dtype == 'int64':
            dtypes[col] = np.int32
        elif col in ['<DATE>', '<TIME>']:
            dtypes[col] = 'object'
        else:
            dtypes[col] = sample[col].dtype
    
    print(f"优化的数据类型: {dtypes}")
    
    # 分块读取
    for i, chunk in enumerate(pd.read_csv(
        csv_path, 
        sep='\t', 
        dtype=dtypes,
        chunksize=chunksize
    )):
        # 合并日期和时间列为datetime
        if '<DATE>' in chunk.columns and '<TIME>' in chunk.columns:
            # 将日期和时间合并
            datetime_str = chunk['<DATE>'].astype(str) + ' ' + chunk['<TIME>'].astype(str)
            chunk['datetime'] = pd.to_datetime(datetime_str, format='%Y.%m.%d %H:%M:%S.%f')
            # 删除原始列
            chunk = chunk.drop(['<DATE>', '<TIME>'], axis=1)
        
        # 重命名列，去掉尖括号
        column_mapping = {}
        for col in chunk.columns:
            if col.startswith('<') and col.endswith('>'):
                new_name = col[1:-1].lower()  # 去掉尖括号并转为小写
                column_mapping[col] = new_name
        if column_mapping:
            chunk = chunk.rename(columns=column_mapping)
        
        chunks.append(chunk)
        total_rows += len(chunk)
        
        if (i + 1) % 10 == 0:
            print(f"已处理 {total_rows:,} 行数据")
    
    # 合并所有块
    print(f"\n合并 {len(chunks)} 个数据块...")
    df = pd.concat(chunks, ignore_index=True)
    
    # 按时间排序
    if 'datetime' in df.columns:
        df = df.sort_values('datetime').reset_index(drop=True)
    
    print(f"\n预处理完成!")
    print(f"总行数: {len(df):,}")
    print(f"总列数: {len(df.columns)}")
    print(f"时间范围: {df['datetime'].min()} 到 {df['datetime'].max()}")
    print(f"内存使用: {df.memory_usage(deep=True).sum() / 1024**3:.2f} GB")
    
    # 第二步：保存为Parquet格式
    print(f"\n保存为Parquet格式: {output_parquet_path}")
    df.to_parquet(output_parquet_path, engine='pyarrow', compression='snappy')
    
    # 验证保存的文件
    print("\n验证保存的文件...")
    parquet_info = pq.read_metadata(output_parquet_path)
    print(f"Parquet文件行数: {parquet_info.num_rows:,}")
    print(f"Parquet文件大小: {os.path.getsize(output_parquet_path) / 1024**3:.2f} GB")
    print(f"压缩率: {(os.path.getsize(csv_path) / os.path.getsize(output_parquet_path)):.2f}x")
    
    return df, output_parquet_path

def load_optimized_data(parquet_path, use_dask=False):
    """
    加载优化后的Parquet数据
    
    参数:
        parquet_path: Parquet文件路径
        use_dask: 是否使用Dask（处理超大文件时）
    """
    if use_dask:
        # 使用Dask处理
        import dask.dataframe as dd
        from dask.diagnostics import ProgressBar
        
        print(f"使用Dask加载数据: {parquet_path}")
        ddf = dd.read_parquet(parquet_path, engine='pyarrow')
        
        print(f"分区数: {ddf.npartitions}")
        print(f"列: {ddf.columns.tolist()}")
        
        with ProgressBar():
            result = ddf.compute()
        
        return result
    else:
        # 使用pandas直接加载
        print(f"使用Pandas加载数据: {parquet_path}")
        df = pd.read_parquet(parquet_path)
        
        print(f"加载完成!")
        print(f"行数: {len(df):,}")
        print(f"内存使用: {df.memory_usage(deep=True).sum() / 1024**3:.2f} GB")
        
        return df

if __name__ == "__main__":
    # 配置文件路径
    csv_path = r"E:\mt5_test_datas\ECmt5data\XAUUSD_202501020100_202602272354.csv"
    parquet_path = csv_path.replace('.csv', '_optimized.parquet')
    
    # 预处理数据
    df, parquet_path = preprocess_mt5_data(csv_path, parquet_path)
    
    # 显示数据前几行
    print("\n数据前5行:")
    print(df.head())
    
    # 显示数据信息
    print("\n数据信息:")
    print(df.info())