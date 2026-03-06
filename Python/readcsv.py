# step1_check_data.py
import pandas as pd
import os

data_path = r"E:\mt5_test_datas\ECmt5data\XAUUSD_202501020100_202602272354.csv"

print(f"文件大小: {os.path.getsize(data_path) / 1024**3:.2f} GB")

# 读取前5行查看结构
df = pd.read_csv(data_path, sep='\t', nrows=5)
print("\n前5行数据:")
print(df)
print("\n列名:")
for i, col in enumerate(df.columns):
    print(f"  {i}. '{col}'")
    
print(f"\n总共 {len(df.columns)} 列")

# 检查每列的前几个值
print("\n各列数据类型和示例:")
for col in df.columns:
    print(f"{col}: {df[col].dtype}, 示例: {df[col].iloc[0]}")