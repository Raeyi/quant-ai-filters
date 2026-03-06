# debug_csv.py
import sys

def debug_csv_file(file_path, n_lines=10):
    """调试CSV文件"""
    print(f"调试文件: {file_path}")
    print("="*50)
    
    try:
        with open(file_path, 'r', encoding='utf-8-sig') as f:
            for i in range(n_lines):
                line = f.readline()
                if not line:
                    break
                print(f"行{i}: {repr(line.strip())}")
    except UnicodeDecodeError:
        # 尝试其他编码
        with open(file_path, 'r', encoding='latin-1') as f:
            for i in range(n_lines):
                line = f.readline()
                if not line:
                    break
                print(f"行{i}: {repr(line.strip())}")

# 使用
debug_csv_file("E:\mt5_test_datas\ECmt5data\XAUUSD_M5_202501020100_202601302350.csv")
debug_csv_file("E:\mt5_test_datas\Doomt5data\XAUUSD.s_M5_202501020100_202601302350.csv")