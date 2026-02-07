# python/data/load_xauusd.py
# 作者: wenrui
# 目的: 加载并清洗 XAUUSD 1分钟历史数据，转换为标准 parquet 格式
# 为什么用 parquet: 压缩好、读取快，适合 vectorbt 回测
# 数据源推荐: HistData.com (免费，质量高) 或 Dukascopy (更高精度 tick，后续升级)

import os
import pandas as pd
from pathlib import Path

# -------------------------- 配置区 --------------------------
DATA_RAW_DIR = Path(__file__).parent / "raw"      # 存放手动下载的 CSV 文件夹
DATA_PROCESSED_DIR = Path(__file__).parent / "processed"  # 输出清洗后 parquet
os.makedirs(DATA_PROCESSED_DIR, exist_ok=True)    # 自动创建文件夹

OUTPUT_FILE = DATA_PROCESSED_DIR / "xauusd_1m_2015_2025.parquet"  # 最终输出文件
# -----------------------------------------------------------

def load_and_clean_histdata_csv(file_path: str) -> pd.DataFrame:
    """
    加载单个 HistData CSV 文件并标准化
    HistData 格式示例: "20230101 000000;1.23456;1.23478;1.23412;1.23434;123"
    我们解析为标准 OHLCV + datetime 索引
    """
    # names 参数直接指定列名（HistData 无表头）
    df = pd.read_csv(
        file_path,
        sep=";",  # HistData 用分号分隔
        names=["datetime", "open", "high", "low", "close", "volume"],
        parse_dates=["datetime"],  # 自动解析时间
    )
    
    # 时区处理：HistData 通常是 GMT/UTC，MT5 也是，保持一致
    df.set_index("datetime", inplace=True)
    
    # 基本清洗：去除无效行、排序
    df = df.dropna()  # 丢弃缺失
    df = df.sort_index()  # 确保时间顺序
    
    print(f"Loaded {file_path}: {len(df)} bars")
    return df

def merge_all_data(start_year: int = 2015, end_year: int = 2025) -> pd.DataFrame:
    """
    合并指定年份的所有 CSV 文件
    你需要手动下载并放到 raw/ 文件夹，文件名如 HISTDATA_COM_ASCII_XAUUSD_M12023.csv
    """
    df_list = []
    for year in range(start_year, end_year + 1):
        # 支持常见文件名格式（可根据你的下载调整）
        possible_files = list(DATA_RAW_DIR.glob(f"*XAUUSD*{year}*.csv"))
        if not possible_files:
            print(f"Warning: No file found for {year}")
            continue
        
        for file in possible_files:
            df_list.append(load_and_clean_histdata_csv(file))
    
    if not df_list:
        raise ValueError("No data files found! Please download CSV to raw/ folder")
    
    full_df = pd.concat(df_list)
    full_df = full_df[~full_df.index.duplicated(keep='first')]  # 去重
    print(f"Merged total: {len(full_df)} bars from {full_df.index[0]} to {full_df.index[-1]}")
    return full_df

if __name__ == "__main__":
    # 主运行：合并并保存 parquet
    data = merge_all_data()
    
    # 保存为 parquet（矢量回测超级快）
    data.to_parquet(OUTPUT_FILE)
    print(f"Saved cleaned data to {OUTPUT_FILE}")
    
    # 验证：打印前几行
    print(data.head())