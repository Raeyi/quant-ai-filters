# python/indicators/bollinger.py
# 作者: wenrui
# 目的: 计算布林带指标（与 MQL5 iBands 完全一致）
# 原理回顾:
# - 中轨: 简单移动平均 (SMA)
# - 上轨: 中轨 + K * 标准差
# - 下轨: 中轨 - K * 标准差
# - 标准差: 滚动标准差 (std)，默认 close 价格
# 这是一个经典均值回归指标：价格触上轨超买、下轨超卖

import pandas as pd
import numpy as np

def bollinger_bands(
    data: pd.DataFrame,          # 输入: 标准 OHLCV DataFrame (index=datetime, columns包括 'close')
    period: int = 20,            # 周期，默认20
    std_mult: float = 2.0        # 倍数，默认2σ
) -> pd.DataFrame:
    """
    返回包含 mid, upper, lower 三列的 DataFrame
    与 MQL5 iBands(MODE_SMA, period, std_mult, PRICE_CLOSE) 对齐
    """
    # 确保有 close 列
    if 'close' not in data.columns:
        raise ValueError("Data must have 'close' column")
    
    close = data['close']
    
    # 中轨: 滚动均值
    mid = close.rolling(window=period).mean()
    
    # 滚动标准差
    std = close.rolling(window=period).std()
    
    # 上轨 / 下轨
    upper = mid + std_mult * std
    lower = mid - std_mult * std
    
    # 合并结果，返回新 DataFrame（与原 data 对齐）
    bb = pd.DataFrame({
        'bb_mid': mid,
        'bb_upper': upper,
        'bb_lower': lower
    })
    
    return bb  # NaN 行在前面（period-1 行），回测时会自动处理

# 示例测试（你可以单独运行这个文件验证）
if __name__ == "__main__":
    # 假设你已加载数据
    from data.load_xauusd import load_processed_data  # 后续我们会加这个函数
    # df = load_processed_data()  # 取消注释运行
    # bb = bollinger_bands(df)
    # print(bb.tail(10))
    print("Bollinger indicator ready!")