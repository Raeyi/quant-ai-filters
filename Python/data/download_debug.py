# dukascopy_downloader_fixed.py
import requests
import pandas as pd
from pathlib import Path
import logging
from datetime import datetime, timedelta
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class DukascopyDownloader:
    def __init__(self, symbol="XAUUSD", data_dir="data"):
        self.symbol = symbol
        self.base_url = "https://datafeed.dukascopy.com/datafeed"   # 正确域名
        self.out_dir = Path(data_dir) / symbol
        self.out_dir.mkdir(parents=True, exist_ok=True)
        
    def download_day(self, year, month, day):
        """下载单日数据（已修正月份为0-based）"""
        date_str = f"{year}-{month:02d}-{day:02d}"
        logger.info(f"下载 {self.symbol} {date_str} 数据")
        
        # Dukascopy 月份 0-based → month-1
        month_idx = month - 1
        
        # 尝试下载每个小时的数据
        for hour in range(24):
            url = f"{self.base_url}/{self.symbol}/{year}/{month_idx:02d}/{day:02d}/{hour:02d}h_ticks.bi5"
            file_path = self.out_dir / f"{date_str}_{hour:02d}.bi5"
            
            if file_path.exists() and file_path.stat().st_size > 500:
                logger.info(f"  小时 {hour:02d}: 已存在有效文件，跳过")
                continue
            
            try:
                response = requests.get(url, timeout=15)
                if response.status_code == 200 and len(response.content) > 500:
                    with open(file_path, 'wb') as f:
                        f.write(response.content)
                    logger.info(f"  小时 {hour:02d}: 下载成功 ({len(response.content)/1024:.1f} KB)")
                else:
                    logger.warning(f"  小时 {hour:02d}: 无数据 (code={response.status_code}, size={len(response.content)})")
            except Exception as e:
                logger.error(f"  小时 {hour:02d}: 下载异常 - {e}")
            time.sleep(0.2)  # 防限流，建议 0.2-0.5s

# 使用示例（先测试单天）
if __name__ == "__main__":
    downloader = DukascopyDownloader("XAUUSD")
    downloader.download_day(2024, 1, 2)   # 测试 2024-01-02（1月 → month_idx=0）