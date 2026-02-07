# python/data/download_dukascopy_xauusd_fixed.py
# 修正版：月份使用 0-indexed (month-1)
# 先测试单月：改 START/END 为 2024-01-01 到 2024-01-31

import os
import requests
import lzma
import struct
import pandas as pd
from datetime import datetime, timedelta
from tqdm import tqdm
from concurrent.futures import ThreadPoolExecutor, as_completed
import logging

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.FileHandler("dukascopy_download.log"), logging.StreamHandler()]
)
logger = logging.getLogger(__name__)

SYMBOL = "XAUUSD"
START_DATE = datetime(2024, 1, 1)   # 先测试 2024 年 1 月
END_DATE   = datetime(2024, 1, 31)
RAW_DIR = os.path.join(os.path.dirname(__file__), "raw_dukascopy")
PROCESSED_DIR = os.path.join(os.path.dirname(__file__), "processed")
OUTPUT_FILE = os.path.join(PROCESSED_DIR, "xauusd_1m_2024_01.parquet")

os.makedirs(RAW_DIR, exist_ok=True)
os.makedirs(PROCESSED_DIR, exist_ok=True)

def get_date_range(start, end):
    dates = []
    current = start
    while current <= end:
        if current.weekday() < 5:  # 周一到周五
            dates.append(current)
        current += timedelta(days=1)
    return dates

def download_hour_file(year, month_idx, day, hour, retries=3):  # month_idx 是 0-11
    url = f"https://data.dukascopy.com/datafeed/{SYMBOL}/{year}/{month_idx:02d}/{day:02d}/{hour:02d}h_ticks.bi5"
    file_path = os.path.join(RAW_DIR, f"{year}-{month_idx+1:02d}-{day:02d}-{hour:02d}h.bi5")  # 保存时用 1-12 方便阅读
    
    if os.path.exists(file_path) and os.path.getsize(file_path) > 500:
        logger.info(f"跳过已存在有效文件: {file_path}")
        return file_path
    
    for attempt in range(retries):
        try:
            logger.info(f"下载 {url} (尝试 {attempt+1}/{retries})")
            r = requests.get(url, timeout=45)
            logger.info(f"响应: code={r.status_code}, size={len(r.content)/1024:.1f} KB")
            
            if r.status_code == 200 and len(r.content) > 500:
                with open(file_path, 'wb') as f:
                    f.write(r.content)
                logger.info(f"下载成功: {file_path}")
                return file_path
            else:
                logger.warning(f"无效: code={r.status_code}, size={len(r.content)}")
        except Exception as e:
            logger.error(f"异常: {str(e)}")
    
    return None

def parse_bi5_to_ticks(file_path, base_time_ms):
    ticks = []
    try:
        with open(file_path, 'rb') as f:
            data = lzma.decompress(f.read())
        
        offset = 0
        while offset + 20 <= len(data):
            delta_ms, ask_int, bid_int, ask_vol, bid_vol = struct.unpack_from('>iifff', data, offset)
            timestamp_ms = base_time_ms + delta_ms
            price = (ask_int + bid_int) / 2000.0  # XAUUSD 价格整数部分 * 1000，所以 /1000 但 ask+bid 平均 /2 再 /1000 → /2000
            vol = ask_vol + bid_vol
            ticks.append((timestamp_ms, price, vol))
            offset += 20
        
        logger.info(f"解析 {file_path}: {len(ticks)} ticks")
    except Exception as e:
        logger.error(f"解析失败 {file_path}: {str(e)}")
    return ticks

def process_day(date: datetime):
    year = date.year
    month_idx = date.month - 1  # 0-based for URL
    day = date.day
    base_time_ms = int(datetime(year, date.month, day).timestamp() * 1000)
    logger.info(f"处理 {date.date()} (URL month: {month_idx:02d})")
    
    all_ticks = []
    
    with ThreadPoolExecutor(max_workers=8) as executor:
        futures = [executor.submit(download_hour_file, year, month_idx, day, h) for h in range(24)]
        for future in tqdm(as_completed(futures), total=24, desc=f"{date.date()}"):
            file_path = future.result()
            if file_path:
                ticks = parse_bi5_to_ticks(file_path, base_time_ms)
                all_ticks.extend(ticks)
    
    if not all_ticks:
        logger.warning(f"当天无 tick 数据")
        return None
    
    df = pd.DataFrame(all_ticks, columns=['timestamp_ms', 'price', 'volume'])
    df['datetime'] = pd.to_datetime(df['timestamp_ms'], unit='ms', utc=True, errors='coerce')
    df = df.dropna(subset=['datetime'])
    df.set_index('datetime', inplace=True)
    
    ohlc = df['price'].resample('1min').ohlc()
    vol = df['volume'].resample('1min').sum()
    day_df = pd.concat([ohlc, vol], axis=1)
    day_df.columns = ['open', 'high', 'low', 'close', 'volume']
    logger.info(f"聚合完成: {len(day_df)} 根 1min K线")
    return day_df.dropna()

if __name__ == "__main__":
    dates = get_date_range(START_DATE, END_DATE)
    logger.info(f"处理 {len(dates)} 天")
    
    all_data = []
    for date in tqdm(dates):
        day_df = process_day(date)
        if day_df is not None and not day_df.empty:
            all_data.append(day_df)
    
    if all_data:
        full_df = pd.concat(all_data).sort_index()
        full_df.to_parquet(OUTPUT_FILE)
        logger.info(f"保存成功: {OUTPUT_FILE}")
        logger.info(f"总行数: {len(full_df)}, 时间: {full_df.index.min()} → {full_df.index.max()}")
        print(full_df.head(10))
    else:
        logger.critical("无有效数据！检查 log")