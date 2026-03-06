#GridMartingaleBacktester.py
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import matplotlib.pyplot as plt
from typing import Dict, List, Tuple, Optional, Any
import warnings
import os
import pyarrow as pa
import pyarrow.parquet as pq
warnings.filterwarnings('ignore')

def preprocess_data_to_parquet(data_path: str, output_path: str = None, chunksize: int = 500000):
    """
    预处理数据并保存为Parquet格式
    
    针对您的数据格式：<DATE>, <TIME>, <BID>, <ASK>, <LAST>, <VOLUME>, <FLAGS>
    使用PyArrow逐步写入，避免内存不足
    """
    if output_path is None:
        output_path = data_path.replace('.csv', '.parquet')
    
    if os.path.exists(output_path):
        print(f"Parquet文件已存在: {output_path}")
        return output_path
    
    print(f"开始预处理数据: {data_path}")
    print(f"文件大小: {os.path.getsize(data_path) / (1024**3):.2f} GB")
    
    # 先查看前几行数据，确认格式
    sample_df = pd.read_csv(data_path, sep='\t', nrows=5)
    print(f"数据列结构: {sample_df.columns.tolist()}")
    print(f"前5行数据:")
    print(sample_df)
    
    # 定义优化数据类型
    dtype_dict = {
        '<BID>': 'float32',
        '<ASK>': 'float32', 
        '<LAST>': 'float32',
        '<VOLUME>': 'float32',
        '<FLAGS>': 'int32'
    }
    
    # 创建Parquet写入器
    writer = None
    total_rows = 0
    chunk_count = 0
    
    for chunk in pd.read_csv(
        data_path, 
        sep='\t', 
        dtype=dtype_dict,
        chunksize=chunksize
    ):
        # 合并日期时间
        time_str = chunk['<DATE>'].astype(str) + ' ' + chunk['<TIME>'].astype(str)
        chunk['Time'] = pd.to_datetime(time_str, format='%Y.%m.%d %H:%M:%S.%f', errors='coerce')
        
        # 重命名列
        rename_dict = {
            '<BID>': 'Bid',
            '<ASK>': 'Ask',
            '<LAST>': 'Last',
            '<VOLUME>': 'Volume',
            '<FLAGS>': 'Flags'
        }
        chunk = chunk.rename(columns=rename_dict)
        
        # 创建OHLC列
        chunk['Open'] = chunk['Bid']
        chunk['High'] = chunk['Bid']
        chunk['Low'] = chunk['Bid']
        chunk['Close'] = chunk['Bid']
        chunk['Spread'] = chunk['Ask'] - chunk['Bid']
        
        # 只保留需要的列
        columns_to_keep = ['Time', 'Open', 'High', 'Low', 'Close', 'Spread']
        chunk = chunk[columns_to_keep]
        
        # 转换为PyArrow Table
        table = pa.Table.from_pandas(chunk)
        
        # 写入Parquet
        if writer is None:
            # 第一次写入，创建文件
            writer = pq.ParquetWriter(output_path, table.schema, compression='snappy')
        
        writer.write_table(table)
        
        total_rows += len(chunk)
        chunk_count += 1
        
        if chunk_count % 10 == 0:
            print(f"已处理 {total_rows:,} 行")
        
        # 每处理5个块，清理内存
        if chunk_count % 5 == 0:
            del chunk, table
            import gc
            gc.collect()
    
    # 关闭写入器
    if writer:
        writer.close()
    
    print(f"\n预处理完成!")
    print(f"总行数: {total_rows:,}")
    print(f"Parquet文件大小: {os.path.getsize(output_path) / 1024**3:.2f} GB")
    
    return output_path

class Position:
    """仓位类，模拟MT5的仓位数据结构"""
    def __init__(self, ticket: int, direction: str, open_price: float, volume: float, 
                 open_time: datetime, magic: int = 20260226, symbol: str = "XAUUSD"):
        self.ticket = ticket
        self.direction = direction  # "BUY" 或 "SELL"
        self.open_price = open_price
        self.volume = volume
        self.open_time = open_time
        self.magic = magic
        self.symbol = symbol
        self.swap = 0.0
        self.sl = 0.0
        self.tp = 0.0
        
    def calculate_profit(self, current_bid: float, current_ask: float) -> float:
        """计算仓位浮动盈亏"""
        if self.direction == "BUY":
            price_diff = current_bid - self.open_price
        else:  # SELL
            price_diff = self.open_price - current_ask
        
        # print(f"price_diff: {price_diff}, volume: {self.volume}")
        return price_diff * self.volume * 100.0
    
    def __repr__(self):
        return f"Position(ticket={self.ticket}, dir={self.direction}, price={self.open_price}, vol={self.volume})"

class XAUUSDGridMartingaleBacktester:
    """XAUUSD M5网格马丁策略回测器"""
    
    def __init__(self, data_path: str, initial_balance: float = 10000.0, enable_backtest_range: bool = False, 
                backtest_start: str = None, backtest_end: str = None, use_parquet: bool = True):
        """
        初始化回测器
        
        Args:
            data_path: CSV数据文件路径
            initial_balance: 初始资金
            enable_backtest_range: 是否启用回测时间范围控制
            backtest_start: 回测开始时间 (格式: "YYYY-MM-DD HH:MM:SS" 或 "YYYY.MM.DD HH:MM")
            backtest_end: 回测结束时间
            use_parquet: 是否使用Parquet格式（更快更省内存）
        """
        
        # 策略参数 (与MQL5代码对应)
        self.params = {
            # 基本设置
            "MagicNumber": 20260226,
            "AutoStart": True,
            "ManageManualTrades": True,
            "BaseLot": 0.01,
            "LotMultiplier": 2,
            "MaxBuyLevels": 13,
            "MaxSellLevels": 11,
            "BasketTP": 140.0,  # 篮子TP
            "BasketSL": -850.0,  # 篮子SL
            "BasketTrailingStart": 70,  # 篮子开始跟单
            "TrailingStep": 19.0,  # 跟单步长
            
            # M5优化参数
            "UseOnlyBuy": False,  # 只允许买入
            "UseATRAdaptive": True,  # 是否使用ATR自适应
            "ATR_Period": 14,  # ATR周期
            "ATR_Multiplier": 0.2,  # ATR倍数
            "MinAddIntervalSec": 180,  # 最小加仓间隔
            "MaxDailyTrades": 500,  # 每日最大交易数
            "GridStepBuy": 7.0,  # 买入网格间距
            "GridStepSell": 10.0,  # 卖出网格间距
            
            # 时间与新闻过滤
            "StartHour": 8,  # 交易开始时间
            "EndHour": 22,  # 交易结束时间
            "CloseOnFriday": True,  # 周五强制平仓
            "UseNewsFilter": False,  # Python回测中忽略新闻过滤
            
            # 风控设置
            "MaxSpreadUSD": 0.5,  # 最大允许的价差
            "MinAccountEquity": 7000.0,  # 最小账户权益
            "MaxTotalLots": 3.8,  # 最大总手数
            "DailyMaxLossUSD": -500.0,  # 每日最大亏损
            "LossCooldownHours": 1,  # 亏损后冷却时间
            "UseTrendFilter": False,  # 是否使用趋势过滤
            "MA_Period": 50,  # 趋势过滤的MA周期

            # 回测时间范围控制
            "EnableBacktestRange": enable_backtest_range,
            "BacktestStartTime": backtest_start,
            "BacktestEndTime": backtest_end,
        }

        # 加载数据
        if use_parquet and data_path.endswith('.parquet'):
            print(f"使用Parquet格式: {data_path}")
            self.data = self.load_parquet_data(data_path, enable_backtest_range, backtest_start, backtest_end)
        elif use_parquet and data_path.endswith('.csv'):
            # 先检查文件大小
            file_size_gb = os.path.getsize(data_path) / (1024**3)
            print(f"CSV文件大小: {file_size_gb:.2f} GB")
            
            if file_size_gb > 1.0:  # 大于1GB
                print("文件较大，建议使用Parquet格式...")
                parquet_path = data_path.replace('.csv', '.parquet')
                if not os.path.exists(parquet_path):
                    print("未找到Parquet文件，开始预处理...")
                    parquet_path = preprocess_data_to_parquet(data_path, parquet_path)
                print(f"使用Parquet格式: {parquet_path}")
                self.data = self.load_parquet_data(parquet_path, enable_backtest_range, backtest_start, backtest_end)
            else:
                # 小文件可以直接加载
                print("文件较小，直接加载CSV...")
                self.data = self.load_data_with_range(data_path, enable_backtest_range, backtest_start, backtest_end)
        else:
            # 使用原始CSV
            self.data = self.load_data_with_range(data_path, enable_backtest_range, backtest_start, backtest_end)


        self.initial_balance = initial_balance
        self.balance = initial_balance
        self.equity = initial_balance
        self.positions: List[Position] = []
        self.closed_positions: List[Dict] = []
        self.ticket_counter = 1
        
        # 状态变量
        self.today = None
        self.dailyPL = 0.0
        self.dailyTrades = 0
        self.lastBigLoss = None
        self.lastBuyAdd = None
        self.lastSellAdd = None
        self.peakProfitBuy = 0.0
        self.peakProfitSell = 0.0
        
        # 回测结果
        self.equity_history = []
        self.balance_history = []
        self.trades_history = []
        self.signals_history = []

    def load_parquet_data(self, parquet_path: str, enable_range: bool, 
                     start_str: str, end_str: str) -> pd.DataFrame:
        """加载Parquet格式数据"""
        print(f"加载Parquet数据: {parquet_path}")
        
        # 先读取元数据获取行数
        import pyarrow.parquet as pq
        parquet_file = pq.ParquetFile(parquet_path)
        num_rows = parquet_file.metadata.num_rows
        print(f"总行数: {num_rows:,}")
        
        # 如果启用了时间范围过滤，我们需要分块读取
        if enable_range and start_str and end_str:
            try:
                # 转换时间格式
                try:
                    start_time = pd.to_datetime(start_str, format='%Y.%m.%d %H:%M')
                except:
                    start_time = pd.to_datetime(start_str)
                
                try:
                    end_time = pd.to_datetime(end_str, format='%Y.%m.%d %H:%M')
                except:
                    end_time = pd.to_datetime(end_str)
                
                print(f"时间范围过滤: {start_time} 到 {end_time}")
                
                # 由于Parquet文件有分区，我们可以尝试使用过滤器
                # 但为了简单起见，我们先全量加载然后过滤
                df = pd.read_parquet(parquet_path)
                original_count = len(df)
                df = df[(df['Time'] >= start_time) & (df['Time'] <= end_time)]
                
                print(f"过滤: {original_count:,} -> {len(df):,} 行")
                print(f"过滤比例: {len(df)/original_count*100:.1f}%")
                
            except Exception as e:
                print(f"时间范围过滤错误: {e}")
                df = pd.read_parquet(parquet_path)
        else:
            df = pd.read_parquet(parquet_path)
        
        # 按时间排序
        df = df.sort_values('Time').reset_index(drop=True)
        
        # 计算技术指标
        ma_period = self.params.get('MA_Period', 50)
        atr_period = self.params.get('ATR_Period', 14)
        
        print("计算技术指标...")
        
        # 计算MA
        df['MA'] = df['Close'].rolling(window=ma_period, min_periods=1).mean()
        
        # 计算ATR
        high_low = df['High'] - df['Low']
        high_close_prev = abs(df['High'] - df['Close'].shift(1))
        low_close_prev = abs(df['Low'] - df['Close'].shift(1))
        df['TR'] = np.maximum(high_low, np.maximum(high_close_prev, low_close_prev))
        df['ATR'] = df['TR'].rolling(window=atr_period, min_periods=1).mean()
        
        # 删除中间列
        df = df.drop(['TR'], axis=1, errors='ignore')
        
        print(f"数据加载完成，共 {len(df)} 行")
        print(f"时间范围: {df['Time'].min()} 到 {df['Time'].max()}")
        print(f"内存使用: {df.memory_usage(deep=True).sum() / 1024**3:.2f} GB")
        
        return df
        
    def load_data_with_range(self, data_path: str, enable_range: bool, 
                        start_str: str, end_str: str) -> pd.DataFrame:
        """加载MT5导出的CSV数据（针对OHLC数据）"""
        print(f"加载数据: {data_path}")
        
        # 先读取前几行检查数据结构
        sample_df = pd.read_csv(data_path, sep='\t', nrows=5)
        print(f"数据列结构: {sample_df.columns.tolist()}")
        
        # 检查是否是OHLC数据
        has_ohlc = all(col in sample_df.columns for col in ['<OPEN>', '<HIGH>', '<LOW>', '<CLOSE>'])
        
        if not has_ohlc:
            print("警告: 数据可能不是OHLC格式，尝试按tick数据处理...")
            # 如果数据是tick格式，应该使用preprocess_data_to_parquet处理
            # 但这里我们尝试继续处理
            pass
        
        # 定义数据类型 - 更通用
        dtype_dict = {}
        for col in sample_df.columns:
            if col in ['<OPEN>', '<HIGH>', '<LOW>', '<CLOSE>', '<BID>', '<ASK>', '<LAST>']:
                dtype_dict[col] = 'float32'
            elif col in ['<TICKVOL>', '<VOL>', '<VOLUME>', '<FLAGS>']:
                dtype_dict[col] = 'int32'
            elif col == '<SPREAD>':
                dtype_dict[col] = 'int16'
        
        # 读取完整数据
        print(f"读取完整CSV文件...")
        df = pd.read_csv(data_path, sep='\t', dtype=dtype_dict)
        
        # 合并日期时间
        time_str = df['<DATE>'].astype(str) + ' ' + df['<TIME>'].astype(str)
        
        # 尝试不同的时间格式
        try:
            df['Time'] = pd.to_datetime(time_str, format='%Y.%m.%d %H:%M:%S.%f')
            print("✓ 使用格式: %Y.%m.%d %H:%M:%S.%f")
        except ValueError as e:
            try:
                df['Time'] = pd.to_datetime(time_str, format='%Y.%m.%d %H:%M:%S')
                print("✓ 使用格式: %Y.%m.%d %H:%M:%S")
            except ValueError as e2:
                df['Time'] = pd.to_datetime(time_str, format='mixed')
                print("✓ 使用格式: mixed (自动推断)")
        
        # 检查时间解析结果
        print(f"时间解析结果:")
        print(f"  样本: {df['Time'].iloc[0]}")
        print(f"  是否有空值: {df['Time'].isnull().sum()}")
        
        # 创建重命名字典 - 只重命名实际存在的列
        rename_dict = {}
        column_mapping = {
            '<OPEN>': 'Open',
            '<HIGH>': 'High', 
            '<LOW>': 'Low',
            '<CLOSE>': 'Close',
            '<TICKVOL>': 'TickVol',
            '<VOL>': 'Vol',
            '<SPREAD>': 'Spread',
            '<BID>': 'Bid',
            '<ASK>': 'Ask',
            '<LAST>': 'Last',
            '<VOLUME>': 'Volume',
            '<FLAGS>': 'Flags'
        }
        
        for orig_col, new_col in column_mapping.items():
            if orig_col in df.columns:
                rename_dict[orig_col] = new_col
        
        # 重命名列
        if rename_dict:
            df = df.rename(columns=rename_dict)
        
        # 删除原始日期时间列
        if '<DATE>' in df.columns:
            df = df.drop(['<DATE>'], axis=1)
        if '<TIME>' in df.columns:
            df = df.drop(['<TIME>'], axis=1)
        
        # 如果是tick数据，需要创建OHLC列
        if 'Close' not in df.columns:
            if 'Bid' in df.columns:
                df['Open'] = df['Bid']
                df['High'] = df['Bid']
                df['Low'] = df['Bid']
                df['Close'] = df['Bid']
                
                if 'Ask' in df.columns:
                    df['Spread'] = df['Ask'] - df['Bid']
            elif 'Last' in df.columns:
                df['Open'] = df['Last']
                df['High'] = df['Last']
                df['Low'] = df['Last']
                df['Close'] = df['Last']
        
        # 确保有必要的列
        required_columns = ['Open', 'High', 'Low', 'Close']
        for col in required_columns:
            if col not in df.columns:
                print(f"警告: 缺少必要的列 {col}")
                # 尝试使用第一列数值数据
                numeric_cols = df.select_dtypes(include=[np.number]).columns
                if len(numeric_cols) > 0:
                    df[col] = df[numeric_cols[0]]
                else:
                    raise ValueError(f"无法创建必要的列 {col}")
        
        if 'Spread' not in df.columns:
            df['Spread'] = 0.1  # 默认点差
        
        # 排序并重置索引
        df = df.sort_values('Time').reset_index(drop=True)
        
        # 如果启用了时间范围控制
        if enable_range:
            # 将字符串时间转换为datetime
            try:
                # 尝试不同的时间格式
                try:
                    start_time = pd.to_datetime(start_str, format='%Y.%m.%d %H:%M')
                except:
                    try:
                        start_time = pd.to_datetime(start_str, format='%Y-%m-%d %H:%M:%S')
                    except:
                        start_time = pd.to_datetime(start_str)
                
                try:
                    end_time = pd.to_datetime(end_str, format='%Y.%m.%d %H:%M')
                except:
                    try:
                        end_time = pd.to_datetime(end_str, format='%Y-%m-%d %H:%M:%S')
                    except:
                        end_time = pd.to_datetime(end_str)
                
                # 过滤数据
                original_count = len(df)
                df = df[(df['Time'] >= start_time) & (df['Time'] <= end_time)]
                filtered_count = len(df)
                
                print(f"时间范围过滤: {start_time} 到 {end_time}")
                print(f"原始数据: {original_count} 行, 过滤后: {filtered_count} 行")
                print(f"过滤比例: {filtered_count/original_count*100:.1f}%")
                
                if filtered_count == 0:
                    print("⚠️ 警告: 过滤后没有数据！请检查时间范围设置")
                
            except Exception as e:
                print(f"⚠️ 时间范围解析错误: {e}")
                print("将使用全部数据")
        
        # 计算技术指标
        ma_period = self.params.get('MA_Period', 50)
        atr_period = self.params.get('ATR_Period', 14)
        
        df['MA'] = df['Close'].rolling(window=ma_period, min_periods=1).mean()
        
        # 计算ATR
        high_low = df['High'] - df['Low']
        high_close_prev = abs(df['High'] - df['Close'].shift(1))
        low_close_prev = abs(df['Low'] - df['Close'].shift(1))
        df['TR'] = np.maximum(high_low, np.maximum(high_close_prev, low_close_prev))
        df['ATR'] = df['TR'].rolling(window=atr_period, min_periods=1).mean()
        
        # 删除中间列
        df = df.drop(['TR'], axis=1, errors='ignore')
        
        print(f"\n数据加载完成，共 {len(df)} 行")
        print(f"时间范围: {df['Time'].min()} 到 {df['Time'].max()}")
        print(f"内存使用: {df.memory_usage(deep=True).sum() / 1024**3:.2f} GB")
        
        return df

    def get_backtest_dates(self) -> pd.DatetimeIndex:
        """获取回测的日期范围"""
        if self.params['EnableBacktestRange']:
            try:
                start_date = pd.to_datetime(self.params['BacktestStartTime'])
                end_date = pd.to_datetime(self.params['BacktestEndTime'])
                return pd.date_range(start=start_date, end=end_date, freq='D')
            except:
                pass
    
        # 如果没有指定范围，返回数据中的所有日期
        return self.data['Time'].dt.date.unique()

    def get_weekly_summary(self) -> pd.DataFrame:
        """获取每周的统计摘要"""
        if self.data.empty:
            return pd.DataFrame()
        
        # 添加周数
        weekly_data = self.data.copy()
        weekly_data['Week'] = weekly_data['Time'].dt.isocalendar().week
        weekly_data['Year'] = weekly_data['Time'].dt.isocalendar().year
        weekly_data['YearWeek'] = weekly_data['Year'].astype(str) + '-W' + weekly_data['Week'].astype(str).str.zfill(2)
        
        # 按周分组
        weekly_stats = weekly_data.groupby('YearWeek').agg({
            'Open': 'first',
            'High': 'max',
            'Low': 'min',
            'Close': 'last',
            'Time': 'count'  # 每周K线数量
        }).rename(columns={'Time': 'Bars'})
        
        # 计算周涨跌幅
        weekly_stats['WeeklyChange'] = (weekly_stats['Close'] - weekly_stats['Open']) / weekly_stats['Open'] * 100
        
        return weekly_stats
    
    def get_basket_count(self, direction: str) -> int:
        """获取指定方向的仓位数量"""
        return len([p for p in self.positions if p.direction == direction])
    
    def get_basket_profit(self, direction: str, current_bid: float, current_ask: float) -> float:
        """获取指定方向篮子的总盈亏"""
        profit = 0.0
        for pos in self.positions:
            if pos.direction == direction:
                profit += pos.calculate_profit(current_bid, current_ask) + pos.swap
        return profit
    
    def get_basket_extreme_price(self, direction: str) -> float:
        """获取网格极限价格"""
        positions = [p for p in self.positions if p.direction == direction]
        if not positions:
            return 0.0
        
        if direction == "BUY":
            return min(p.open_price for p in positions)
        else:  # SELL
            return max(p.open_price for p in positions)
    
    def get_total_lots(self) -> float:
        """获取总手数"""
        return sum(p.volume for p in self.positions)
    
    def close_all(self, reason: str, current_time: datetime, 
                  current_bid: float, current_ask: float):
        """平仓所有仓位"""
        if not self.positions:
            return
        
        print(f"{current_time}: CloseAll - {reason}, 当前权益: {self.balance:.2f}, 当前仓位手数: {self.get_total_lots():.2f}, 当前篮子盈亏: {self.get_basket_profit('BUY', current_bid, current_ask):.2f}, {self.get_basket_profit('SELL', current_bid, current_ask):.2f}")

        # 平仓所有仓位
        for pos in self.positions[:]:  # 使用副本迭代
            profit = pos.calculate_profit(current_bid, current_ask)
            self.balance += profit
            self.closed_positions.append({
                'ticket': pos.ticket,
                'direction': pos.direction,
                'open_price': pos.open_price,
                'close_price': current_bid if pos.direction == "BUY" else current_ask,
                'volume': pos.volume,
                'profit': profit,
                'open_time': pos.open_time,
                'close_time': current_time,
                'reason': reason
            })
            self.positions.remove(pos)

        print(f"{current_time}: CloseAll - {reason}, 当前权益: {self.balance:.2f}, 当前仓位手数: {self.get_total_lots():.2f}")

        # 重置峰值利润
        self.peakProfitBuy = 0.0
        self.peakProfitSell = 0.0
        
        # 如果是亏损相关，记录最后大亏损时间
        if "亏损" in reason or "保护" in reason:
            self.lastBigLoss = current_time
    
    def manage_basket(self, direction: str, current_time: datetime, 
                      current_bid: float, current_ask: float):
        """管理篮子（TP/SL，浮动止盈等）"""
        if self.get_basket_count(direction) == 0:
            return
        
        profit = self.get_basket_profit(direction, current_bid, current_ask)
        # 添加调试信息
        # print(f"{current_time}: {direction}篮子利润 = {profit:.2f}, TP={self.params['BasketTP']}, SL={self.params['BasketSL']}, 当前权益={self.balance:.2f}, 当前仓位手数={self.get_total_lots():.2f}, 当前篮子盈亏={self.get_basket_profit('BUY', current_bid, current_ask):.2f}, {self.get_basket_profit('SELL', current_bid, current_ask):.2f}")
        
        # 固定止盈/止损
        if profit >= self.params['BasketTP'] or profit <= self.params['BasketSL']:
            print(f"{current_time}: 触发! {direction}篮子利润: {profit:.2f} >= {self.params['BasketTP']} 或 <= {self.params['BasketSL']}")
            reason = f"{direction} 固定TP/SL (利润: {profit:.2f})"
            self.close_all(reason, current_time, current_bid, current_ask)
            return
        
        # 浮动止盈
        if profit >= self.params['BasketTrailingStart']:
            if direction == "BUY":
                if profit > self.peakProfitBuy:
                    self.peakProfitBuy = profit
                if self.peakProfitBuy - profit >= self.params['TrailingStep']:
                    reason = f"{direction} 浮动止盈触发 (峰值: {self.peakProfitBuy:.2f}, 当前: {profit:.2f})"
                    self.close_all(reason, current_time, current_bid, current_ask)
                    self.peakProfitBuy = 0.0
                    return
            else:  # SELL
                if profit > self.peakProfitSell:
                    self.peakProfitSell = profit
                if self.peakProfitSell - profit >= self.params['TrailingStep']:
                    reason = f"{direction} 浮动止盈触发 (峰值: {self.peakProfitSell:.2f}, 当前: {profit:.2f})"
                    self.close_all(reason, current_time, current_bid, current_ask)
                    self.peakProfitSell = 0.0
                    return
        
        # 盈利60%部分平仓锁利
        if profit >= self.params['BasketTP'] * 0.6 and self.get_basket_count(direction) >= 3:
            self.partial_close(direction, 0.5, current_time, current_bid, current_ask)
    
    def partial_close(self, direction: str, ratio: float, current_time: datetime,
                      current_bid: float, current_ask: float):
        """部分平仓（锁利）"""
        positions = [p for p in self.positions if p.direction == direction]
        
        for pos in positions:
            close_volume = pos.volume * ratio
            if close_volume > 0.001:
                profit = (pos.calculate_profit(current_bid, current_ask) + pos.swap) * ratio
                self.balance += profit
                
                # 记录平仓
                self.closed_positions.append({
                    'ticket': pos.ticket,
                    'direction': pos.direction,
                    'open_price': pos.open_price,
                    'close_price': current_bid if pos.direction == "BUY" else current_ask,
                    'volume': close_volume,
                    'profit': profit,
                    'open_time': pos.open_time,
                    'close_time': current_time,
                    'reason': f"部分平仓锁利 {ratio*100}%"
                })
                
                # 更新仓位手数
                pos.volume -= close_volume
                if pos.volume <= 0.001:
                    self.positions.remove(pos)
                
                print(f"{current_time}: {direction} 部分平仓 {close_volume:.2f}手, 锁定利润: {profit:.2f}")
    
    def get_grid_step(self, is_buy: bool, atr_value: float = None) -> float:
        """获取网格步长"""
        if self.params['UseATRAdaptive'] and atr_value is not None:
            return atr_value * self.params['ATR_Multiplier']
        return self.params['GridStepBuy'] if is_buy else self.params['GridStepSell']
    
    def normalize_lot(self, lot: float) -> float:
        """规范化手数"""
        min_lot = 0.01
        max_lot = 100.0
        step = 0.01
        lot = max(min_lot, min(max_lot, lot))
        return round(lot / step) * step
    
    def is_trading_time(self, current_time: datetime) -> bool:
        """检查是否是交易时间"""
        hour = current_time.hour
        return self.params['StartHour'] <= hour < self.params['EndHour']
    
    def check_new_entry(self, direction: str, current_time: datetime, 
                        current_price: float, atr_value: float, 
                        ma_value: float, is_new_bar: bool = False):
        """检查是否需要开仓"""
        is_buy = (direction == "BUY")
        max_levels = self.params['MaxBuyLevels'] if is_buy else self.params['MaxSellLevels']
        basket_count = self.get_basket_count(direction)
        
        # 检查最大层数
        if basket_count >= max_levels:
            if is_new_bar:
                print(f"{current_time}: ❌ {direction} 已达最大层数 {max_levels}")
            return
        
        # 检查加仓间隔
        last_time = self.lastBuyAdd if is_buy else self.lastSellAdd
        if last_time is not None:  # 检查是否为 None
            time_since_last = (current_time - last_time).total_seconds()
            if time_since_last < self.params['MinAddIntervalSec']:
                if is_new_bar:
                    print(f"{current_time}: ⏰ {direction} 加仓冷却中")
                return
        
        # 获取极端价格
        extreme_price = self.get_basket_extreme_price(direction)
        
        # 获取网格步长
        grid_step = self.get_grid_step(is_buy, atr_value)
        
        need_open = False
        lot = self.params['BaseLot']
        
        # 自动开仓（首单）
        if basket_count == 0:
            if self.params['AutoStart']:
                need_open = True
                if is_new_bar:
                    print(f"{current_time}: ✅ {direction} 满足首单条件")
            else:
                if is_new_bar:
                    print(f"{current_time}: ❌ {direction} AutoStart=false, 无法开首单")
        else:
            # 加仓逻辑
            price_condition = False
            price_diff = abs(current_price - extreme_price)
            
            if is_buy and current_price <= extreme_price - grid_step:
                price_condition = True
            elif not is_buy and current_price >= extreme_price + grid_step:
                price_condition = True
            
            if price_condition:
                need_open = True
                # 计算手数（马丁加仓）
                lot = self.params['BaseLot'] * (self.params['LotMultiplier'] ** basket_count)
                if is_new_bar:
                    print(f"{current_time}: {direction} 计算手数: {lot:.2f}")
        
        if need_open:
            # 手数调整
            lot = self.normalize_lot(lot)
            total_lots = self.get_total_lots()
            available_lots = self.params['MaxTotalLots'] - total_lots
            
            if lot + total_lots > self.params['MaxTotalLots']:
                lot = self.normalize_lot(available_lots)
            
            if lot < 0.01:  # 最小交易量
                if is_new_bar:
                    print(f"{current_time}: ❌ {direction} 手数低于最小交易量")
                return
            
            # 趋势过滤
            if self.params['UseTrendFilter'] and ma_value is not None:
                trend_condition = (is_buy and current_price >= ma_value) or (not is_buy and current_price <= ma_value)
                if not trend_condition:
                    if is_new_bar:
                        print(f"{current_time}: ❌ {direction} 趋势过滤阻止开仓")
                    return
            
            # 开仓
            open_price = current_price
            position = Position(
                ticket=self.ticket_counter,
                direction=direction,
                open_price=open_price,
                volume=lot,
                open_time=current_time
            )
            
            self.positions.append(position)
            self.ticket_counter += 1
            
            # 更新状态
            if is_buy:
                self.lastBuyAdd = current_time
            else:
                self.lastSellAdd = current_time
            
            self.dailyTrades += 1
            
            if is_new_bar:
                print(f"{current_time}: ✅ {direction} 开仓成功 第{basket_count+1}层 手数{lot:.2f} 价格{open_price:.2f}")
            
            # 记录交易
            self.signals_history.append({
                'time': current_time,
                'direction': direction,
                'price': open_price,
                'volume': lot,
                'action': 'open',
                'basket_count': basket_count + 1
            })
    
    def run_backtest(self):
        """运行回测"""
        print("=" * 50)
        print("开始回测 XAUUSD M5 网格马丁策略")
        print("=" * 50)

        # 添加内存监控
        import psutil
        import os
        process = psutil.Process(os.getpid())
        initial_memory = process.memory_info().rss / 1024**3
        print(f"初始内存: {initial_memory:.2f} GB")
        
        # 重置状态
        self.positions = []
        self.closed_positions = []
        self.equity_history = []
        self.balance_history = []
        self.signals_history = []

        # 初始化每日数据
        self.today = None
        self.dailyPL = 0.0
        self.dailyTrades = 0
        self.lastBigLoss = None
        self.lastBuyAdd = None
        self.lastSellAdd = None
        self.peakProfitBuy = 0.0
        self.peakProfitSell = 0.0
        
        prev_date = None
        bar_counter = 0

        # 检查数据大小
        print(f"回测数据行数: {len(self.data):,}")
        print(f"预计内存占用: {self.data.memory_usage(deep=True).sum() / 1024**3:.2f} GB")

        # 添加调试：打印初始状态
        print(f"初始权益: {self.equity}")
        print(f"最小权益保护: {self.params['MinAccountEquity']}")

        # 分批处理大型数据
        if len(self.data) > 1000000:  # 超过100万行
            print("数据较大，启用分批处理...")
            batch_size = 100000
            num_batches = len(self.data) // batch_size + 1

            for batch_num in range(num_batches):
                start_idx = batch_num * batch_size
                end_idx = min((batch_num + 1) * batch_size, len(self.data))
                batch_data = self.data.iloc[start_idx:end_idx]
                
                print(f"\n处理批次 {batch_num+1}/{num_batches}: 行 {start_idx:,}-{end_idx:,}")

                for idx, row in batch_data.iterrows():
                    current_time = row['Time']
                    current_bid = row['Close']  # 使用收盘价作为Bid
                    current_ask = row['Close'] + 0.1  # 简单模拟Ask（加固定点差）
                
                    # 检查新的一天
                    current_date = current_time.date()
                    if prev_date is None or current_date != prev_date:
                        # 新的一天，重置每日数据
                        self.dailyPL = 0.0
                        self.dailyTrades = 0
                        self.today = current_time
                        prev_date = current_date
                    
                    # 检查是否是"新K线"（这里我们每5个tick模拟一个新K线）
                    is_new_bar = (bar_counter % 5 == 0)

                    # 周五强制平仓
                    if self.params['CloseOnFriday'] and current_time.weekday() == 4 and current_time.hour >= 20:
                        self.close_all("周五强制平仓", current_time, current_bid, current_ask)
                        continue
                    
                    # 管理篮子
                    self.manage_basket("BUY", current_time, current_bid, current_ask)
                    if not self.params['UseOnlyBuy']:
                        self.manage_basket("SELL", current_time, current_bid, current_ask)

                    # 权益保护
                    if self.equity < self.params['MinAccountEquity']:
                        print(f"\n{current_time}: 触发权益保护!")
                        print(f"  当前权益: {self.equity}")
                        print(f"  最小要求: {self.params['MinAccountEquity']}")
                        print(f"  持仓数量: {len(self.positions)}")
                        print(f"  总手数: {self.get_total_lots()}")
            
                        # 打印每个仓位的盈亏
                        for pos in self.positions:
                            profit = pos.calculate_profit(current_bid, current_ask)
                            print(f"  仓位 #{pos.ticket} {pos.direction} {pos.volume}手 "
                                f"开仓价 {pos.open_price:.2f} 当前价 {current_bid:.2f} "
                                f"盈亏: {profit:.2f}")
                    
                        self.close_all("权益保护", current_time, current_bid, current_ask)
                        return
                    
                    # 亏损后冷却
                    if self.lastBigLoss is not None:
                        if (current_time - self.lastBigLoss).total_seconds() < self.params['LossCooldownHours'] * 3600:
                            continue
                    
                    # 交易时间检查
                    if not self.is_trading_time(current_time):
                        continue
                    
                    # 点差检查（简化）
                    spread = 0.1  # 固定点差
                    if spread > self.params['MaxSpreadUSD']:
                        continue
                    
                    # 手数检查
                    total_lots = self.get_total_lots()
                    if total_lots >= self.params['MaxTotalLots']:
                        continue
                    
                    # 交易次数检查
                    if self.dailyTrades >= self.params['MaxDailyTrades']:
                        continue
                    
                    # 检查新开仓
                    if self.dailyTrades < self.params['MaxDailyTrades']:
                        self.check_new_entry("BUY", current_time, current_bid, 
                                        row.get('ATR'), row.get('MA'), is_new_bar)
                        if not self.params['UseOnlyBuy']:
                            self.check_new_entry("SELL", current_time, current_ask,
                                            row.get('ATR'), row.get('MA'), is_new_bar)
                    
                    # 更新权益
                    total_profit = 0.0
                    for pos in self.positions:
                        total_profit += pos.calculate_profit(current_bid, current_ask)
                    self.equity = self.balance + total_profit
                    
                    # 记录历史
                    self.equity_history.append({
                        'time': current_time,
                        'equity': self.equity,
                        'balance': self.balance,
                        'positions': len(self.positions),
                        'total_lots': total_lots
                    })
                    
                    bar_counter += 1

                # 每处理完一个批次，清理内存
                import gc
                del batch_data
                gc.collect()
                
                current_memory = process.memory_info().rss / 1024**3
                print(f"批次 {batch_num+1} 完成，当前内存: {current_memory:.2f} GB")
        else:

            for idx, row in self.data.iterrows():
                current_time = row['Time']
                current_bid = row['Close']  # 使用收盘价作为Bid
                current_ask = row['Close'] + 0.1  # 简单模拟Ask（加固定点差）
                
                # 检查新的一天
                current_date = current_time.date()
                if prev_date is None or current_date != prev_date:
                    # 新的一天，重置每日数据
                    self.dailyPL = 0.0
                    self.dailyTrades = 0
                    self.today = current_time
                    prev_date = current_date
                
                # 检查是否是"新K线"（这里我们每5个tick模拟一个新K线）
                is_new_bar = (bar_counter % 5 == 0)

                # 周五强制平仓
                if self.params['CloseOnFriday'] and current_time.weekday() == 4 and current_time.hour >= 20:
                    self.close_all("周五强制平仓", current_time, current_bid, current_ask)
                    continue
                
                # 管理篮子
                self.manage_basket("BUY", current_time, current_bid, current_ask)
                if not self.params['UseOnlyBuy']:
                    self.manage_basket("SELL", current_time, current_bid, current_ask)

                # 权益保护
                if self.equity < self.params['MinAccountEquity']:
                    print(f"\n{current_time}: 触发权益保护!")
                    print(f"  当前权益: {self.equity}")
                    print(f"  最小要求: {self.params['MinAccountEquity']}")
                    print(f"  持仓数量: {len(self.positions)}")
                    print(f"  总手数: {self.get_total_lots()}")
        
                    # 打印每个仓位的盈亏
                    for pos in self.positions:
                        profit = pos.calculate_profit(current_bid, current_ask)
                        print(f"  仓位 #{pos.ticket} {pos.direction} {pos.volume}手 "
                            f"开仓价 {pos.open_price:.2f} 当前价 {current_bid:.2f} "
                            f"盈亏: {profit:.2f}")
                
                    self.close_all("权益保护", current_time, current_bid, current_ask)
                    return
                
                # 亏损后冷却
                if self.lastBigLoss is not None:
                    if (current_time - self.lastBigLoss).total_seconds() < self.params['LossCooldownHours'] * 3600:
                        continue
                
                # 交易时间检查
                if not self.is_trading_time(current_time):
                    continue
                
                # 点差检查（简化）
                spread = 0.1  # 固定点差
                if spread > self.params['MaxSpreadUSD']:
                    continue
                
                # 手数检查
                total_lots = self.get_total_lots()
                if total_lots >= self.params['MaxTotalLots']:
                    continue
                
                # 交易次数检查
                if self.dailyTrades >= self.params['MaxDailyTrades']:
                    continue
                
                # 检查新开仓
                if self.dailyTrades < self.params['MaxDailyTrades']:
                    self.check_new_entry("BUY", current_time, current_bid, 
                                    row.get('ATR'), row.get('MA'), is_new_bar)
                    if not self.params['UseOnlyBuy']:
                        self.check_new_entry("SELL", current_time, current_ask,
                                        row.get('ATR'), row.get('MA'), is_new_bar)
                
                # 更新权益
                total_profit = 0.0
                for pos in self.positions:
                    total_profit += pos.calculate_profit(current_bid, current_ask)
                self.equity = self.balance + total_profit
                
                # 记录历史
                self.equity_history.append({
                    'time': current_time,
                    'equity': self.equity,
                    'balance': self.balance,
                    'positions': len(self.positions),
                    'total_lots': total_lots
                })
                
                bar_counter += 1
        
        # 回测结束，平掉所有仓位
        if self.positions:
            last_row = self.data.iloc[-1]
            self.close_all("回测结束", last_row['Time'], last_row['Close'], last_row['Close'] + 0.1)
        
        final_memory = process.memory_info().rss / 1024**3
        print(f"\n最终内存: {final_memory:.2f} GB")
        print(f"内存增加: {final_memory - initial_memory:.2f} GB")
        
        print("\n" + "=" * 50)
        print("回测完成!")
        print("=" * 50)
    
    def calculate_metrics(self) -> Dict[str, Any]:
        """计算回测指标"""
        if not self.closed_positions:
            return {"error": "没有交易记录"}
        
        trades_df = pd.DataFrame(self.closed_positions)
        equity_df = pd.DataFrame(self.equity_history)
        
        # 基本指标
        total_trades = len(trades_df)
        winning_trades = len(trades_df[trades_df['profit'] > 0])
        losing_trades = len(trades_df[trades_df['profit'] < 0])
        
        total_profit = trades_df['profit'].sum()
        max_profit = trades_df['profit'].max()
        max_loss = trades_df['profit'].min()
        
        avg_profit = trades_df['profit'].mean()
        avg_win = trades_df[trades_df['profit'] > 0]['profit'].mean() if winning_trades > 0 else 0
        avg_loss = trades_df[trades_df['profit'] < 0]['profit'].mean() if losing_trades > 0 else 0
        
        win_rate = winning_trades / total_trades if total_trades > 0 else 0
        profit_factor = abs(avg_win * winning_trades) / abs(avg_loss * losing_trades) if losing_trades > 0 else float('inf')
        
        # 回撤计算
        equity_series = equity_df.set_index('time')['equity']
        running_max = equity_series.expanding().max()
        drawdown = (equity_series - running_max) / running_max * 100
        max_drawdown = drawdown.min()
        
        # 夏普比率（简化）
        daily_returns = equity_series.pct_change().dropna()
        sharpe_ratio = daily_returns.mean() / daily_returns.std() * np.sqrt(252) if len(daily_returns) > 0 and daily_returns.std() > 0 else 0
        
        metrics = {
            'initial_balance': self.initial_balance,
            'final_balance': self.balance,
            'total_profit': total_profit,
            'total_return_pct': (self.balance - self.initial_balance) / self.initial_balance * 100,
            'total_trades': total_trades,
            'winning_trades': winning_trades,
            'losing_trades': losing_trades,
            'win_rate_pct': win_rate * 100,
            'max_profit': max_profit,
            'max_loss': max_loss,
            'avg_profit': avg_profit,
            'avg_win': avg_win,
            'avg_loss': avg_loss,
            'profit_factor': profit_factor,
            'max_drawdown_pct': max_drawdown,
            'sharpe_ratio': sharpe_ratio,
            'max_consecutive_wins': self._calculate_max_consecutive(trades_df['profit'] > 0),
            'max_consecutive_losses': self._calculate_max_consecutive(trades_df['profit'] < 0),
        }
        
        return metrics
    
    def _calculate_max_consecutive(self, series: pd.Series) -> int:
        """计算最大连续次数"""
        if len(series) == 0:
            return 0
        
        max_consecutive = 0
        current = 0
        
        for val in series:
            if val:
                current += 1
                max_consecutive = max(max_consecutive, current)
            else:
                current = 0
        
        return max_consecutive
    
    def plot_results(self):
        """绘制回测结果图"""
        if not self.equity_history:
            print("没有回测数据可绘制")
            return
        
        equity_df = pd.DataFrame(self.equity_history)
        equity_df.set_index('time', inplace=True)
        
        trades_df = pd.DataFrame(self.closed_positions) if self.closed_positions else None
        
        fig, axes = plt.subplots(3, 1, figsize=(15, 12))
        
        # 1. 权益曲线
        ax1 = axes[0]
        ax1.plot(equity_df.index, equity_df['equity'], label='Equity', linewidth=2, color='blue')
        ax1.plot(equity_df.index, equity_df['balance'], label='Balance', linewidth=1, color='green', alpha=0.7)
        ax1.axhline(y=self.initial_balance, color='red', linestyle='--', alpha=0.5, label='初始资金')
        ax1.set_title('账户权益曲线', fontsize=14, fontweight='bold')
        ax1.set_ylabel('金额 (USD)')
        ax1.legend()
        ax1.grid(True, alpha=0.3)
        
        # 2. 持仓数量
        ax2 = axes[1]
        ax2.plot(equity_df.index, equity_df['positions'], label='持仓数量', linewidth=2, color='orange')
        ax2.plot(equity_df.index, equity_df['total_lots'], label='总手数', linewidth=1, color='purple', alpha=0.7)
        ax2.set_title('持仓情况', fontsize=14, fontweight='bold')
        ax2.set_ylabel('数量/手数')
        ax2.legend()
        ax2.grid(True, alpha=0.3)
        
        # 3. 价格与交易信号
        ax3 = axes[2]
        price_data = self.data.set_index('Time')['Close']
        ax3.plot(price_data.index, price_data, label='XAUUSD价格', linewidth=1, color='black', alpha=0.7)
        
        # 标记交易信号
        if self.signals_history:
            signals_df = pd.DataFrame(self.signals_history)
            buy_signals = signals_df[signals_df['direction'] == 'BUY']
            sell_signals = signals_df[signals_df['direction'] == 'SELL']
            
            if not buy_signals.empty:
                ax3.scatter(buy_signals['time'], price_data.reindex(buy_signals['time']), 
                          color='green', marker='^', s=50, label='买入信号', alpha=0.7)
            if not sell_signals.empty:
                ax3.scatter(sell_signals['time'], price_data.reindex(sell_signals['time']), 
                          color='red', marker='v', s=50, label='卖出信号', alpha=0.7)
        
        ax3.set_title('价格与交易信号', fontsize=14, fontweight='bold')
        ax3.set_ylabel('价格 (USD)')
        ax3.legend()
        ax3.grid(True, alpha=0.3)
        
        plt.tight_layout()
        plt.show()
    
    def print_report(self):
        """打印回测报告"""
        metrics = self.calculate_metrics()
        
        print("\n" + "=" * 60)
        print("XAUUSD M5 网格马丁策略回测报告")
        print("=" * 60)
        
        # 添加时间范围信息
        if self.params['EnableBacktestRange']:
            print(f"回测时间范围: {self.params['BacktestStartTime']} 到 {self.params['BacktestEndTime']}")
        
        print(f"数据范围: {self.data['Time'].min()} 到 {self.data['Time'].max()}")
        print(f"总K线数量: {len(self.data)}")
        
        if 'error' in metrics:
            print(f"错误: {metrics['error']}")
            return

        print(f"\n📊 资金表现:")
        print(f"   初始资金: ${metrics['initial_balance']:,.2f}")
        print(f"   最终资金: ${metrics['final_balance']:,.2f}")
        print(f"   总盈利: ${metrics['total_profit']:,.2f}")
        print(f"   总收益率: {metrics['total_return_pct']:.2f}%")
        
        print(f"\n📈 交易统计:")
        print(f"   总交易次数: {metrics['total_trades']}")
        print(f"   盈利交易: {metrics['winning_trades']} ({metrics['win_rate_pct']:.1f}%)")
        print(f"   亏损交易: {metrics['losing_trades']} ({100 - metrics['win_rate_pct']:.1f}%)")
        
        print(f"\n💰 盈亏分析:")
        print(f"   最大单笔盈利: ${metrics['max_profit']:,.2f}")
        print(f"   最大单笔亏损: ${metrics['max_loss']:,.2f}")
        print(f"   平均盈利: ${metrics['avg_profit']:,.2f}")
        print(f"   平均盈利(胜): ${metrics['avg_win']:,.2f}")
        print(f"   平均亏损(负): ${metrics['avg_loss']:,.2f}")
        print(f"   盈利因子: {metrics['profit_factor']:.2f}")
        
        print(f"\n⚠️ 风险指标:")
        print(f"   最大回撤: {metrics['max_drawdown_pct']:.2f}%")
        print(f"   夏普比率: {metrics['sharpe_ratio']:.2f}")
        print(f"   最大连续盈利: {metrics['max_consecutive_wins']}")
        print(f"   最大连续亏损: {metrics['max_consecutive_losses']}")
        
        print(f"\n⚙️ 策略参数:")
        for key, value in self.params.items():
            if isinstance(value, bool):
                print(f"   {key}: {'是' if value else '否'}")
            else:
                print(f"   {key}: {value}")
        
        print("\n" + "=" * 60)
    
    def save_results(self, output_path: str = "backtest_results.xlsx"):
        """保存回测结果到Excel文件"""
        with pd.ExcelWriter(output_path, engine='openpyxl') as writer:
            # 保存权益历史
            equity_df = pd.DataFrame(self.equity_history)
            equity_df.to_excel(writer, sheet_name='Equity History', index=False)
            
            # 保存交易记录
            if self.closed_positions:
                trades_df = pd.DataFrame(self.closed_positions)
                trades_df.to_excel(writer, sheet_name='Trades', index=False)
            
            # 保存信号记录
            if self.signals_history:
                signals_df = pd.DataFrame(self.signals_history)
                signals_df.to_excel(writer, sheet_name='Signals', index=False)
            
            # 保存策略参数
            params_df = pd.DataFrame(list(self.params.items()), columns=['Parameter', 'Value'])
            params_df.to_excel(writer, sheet_name='Parameters', index=False)
            
            # 保存回测指标
            metrics = self.calculate_metrics()
            metrics_df = pd.DataFrame(list(metrics.items()), columns=['Metric', 'Value'])
            metrics_df.to_excel(writer, sheet_name='Metrics', index=False)
        
        print(f"回测结果已保存到: {output_path}")

    def run_multiple_periods_backtest(self, periods: list):
        """
        批量回测多个时间段
        
        Args:
            periods: 时间段列表，每个元素是(start, end, name)的元组
        """
        print("="*60)
        print("批量多时间段回测")
        print("="*60)
        
        results = {}
        
        for i, (start_time, end_time, period_name) in enumerate(periods):
            print(f"\n回测阶段 {i+1}/{len(periods)}: {period_name}")
            print(f"时间范围: {start_time} 到 {end_time}")
            
            # 创建新的回测器实例
            period_backtester = XAUUSDGridMartingaleBacktester(
                data_path=self.data_path,
                initial_balance=self.initial_balance,
                enable_backtest_range=True,
                backtest_start=start_time,
                backtest_end=end_time
            )
            
            # 运行回测
            period_backtester.run_backtest()
            
            # 获取结果
            metrics = period_backtester.calculate_metrics()
            results[period_name] = {
                'metrics': metrics,
                'start': start_time,
                'end': end_time
            }
            
            print(f"{period_name} 回测完成")
        
        # 分析比较结果
        self.compare_multiple_periods(results)
        
        return results

    def compare_multiple_periods(self, results: dict):
        """比较多个时间段的回测结果"""
        print("\n" + "="*60)
        print("多时间段回测结果比较")
        print("="*60)
        
        comparison_data = []
        
        for period_name, data in results.items():
            metrics = data['metrics']
            
            if 'error' in metrics:
                continue
                
            comparison_data.append({
                '时间段': period_name,
                '开始时间': data['start'],
                '结束时间': data['end'],
                '总盈利': metrics.get('total_profit', 0),
                '总收益率%': metrics.get('total_return_pct', 0),
                '胜率%': metrics.get('win_rate_pct', 0),
                '最大回撤%': metrics.get('max_drawdown_pct', 0),
                '夏普比率': metrics.get('sharpe_ratio', 0),
                '盈利因子': metrics.get('profit_factor', 0),
                '总交易次数': metrics.get('total_trades', 0)
            })
        
        if comparison_data:
            comparison_df = pd.DataFrame(comparison_data)
            print(comparison_df.to_string(index=False))
            
            # 保存比较结果
            comparison_df.to_csv('multiple_periods_comparison.csv', index=False, encoding='utf-8-sig')
            print(f"\n💾 比较结果已保存到: multiple_periods_comparison.csv")
        else:
            print("没有有效的结果可比较")

# 使用示例
if __name__ == "__main__":

    # 数据文件路径
    csv_path = "E:\mt5_test_datas\ECmt5data\XAUUSD_202501020100_202602272354.csv"
    # csv_path = "E:\mt5_test_datas\ECmt5data\XAUUSD_M1_202501020100_202602272354.csv"
    parquet_path = csv_path.replace('.csv', '.parquet')
    
    # 初始化回测器
    backtester = XAUUSDGridMartingaleBacktester(
        data_path=csv_path,
        initial_balance=20000,
        enable_backtest_range=True,
        backtest_start="2025-09-01 00:00:00",
        backtest_end="2025-09-05 23:59:00",
        use_parquet=True  # 启用Parquet格式
    )
    
    # 运行回测
    backtester.run_backtest()
    
    # 打印报告
    backtester.print_report()
    
    # 绘制图表
    backtester.plot_results()
    
    # 保存结果
    backtester.save_results("xau_grid_backtest_with_range.xlsx")