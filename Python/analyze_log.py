import re

def analyze_log(file_path):
    open_count = 0
    close_count = 0
    t_profits = []
    total_profit = 0

    # 平仓统计
    close_stats = {
        1: {"count": 0, "profit": 0},
        2: {"count": 0, "profit": 0},
        3: {"count": 0, "profit": 0},
        4: {"count": 0, "profit": 0},
        5: {"count": 0, "profit": 0},
    }

    # 匹配净盈亏
    part_close_pattern = re.compile(r'\[平仓#(\d)\].*?本次盈亏:\s*([+-]?\d*\.?\d+)')
    net_pattern = re.compile(r'Alert: 平仓完成: XAUUSD 净盈亏:\s*([-+]?\d*\.?\d+)')

    with open(file_path, 'r', encoding='utf-16', errors='ignore') as f:
        for line in f:

            # 统计开仓
            if "Alert: 开仓成功" in line:
                open_count += 1

            # 总平仓统计
            match = net_pattern.search(line)
            if match:
                close_count += 1
                tprofit = float(match.group(1))
                t_profits.append(tprofit)

            # 分批平仓统计
            part_match = part_close_pattern.search(line)
            if part_match:

                close_id = int(part_match.group(1))
                pprofit = float(part_match.group(2))

                if close_id in close_stats:
                    close_stats[close_id]["count"] += 1
                    close_stats[close_id]["profit"] += pprofit

    # 统计数据
    total_profit = sum(t_profits)
    avg_profit = total_profit / close_count if close_count > 0 else 0
    win_count = len([p for p in t_profits if p > 0])
    loss_count = len([p for p in t_profits if p < 0])
    max_win = max(t_profits) if t_profits else 0
    max_loss = min(t_profits) if t_profits else 0

    # 输出结果
    print("===== Log统计结果 =====")
    print(f"开仓成功次数: {open_count}")
    print(f"平仓完成次数: {close_count}")
    print(f"盈利次数: {win_count}")
    print(f"亏损次数: {loss_count}")
    print(f"总净盈亏: {total_profit:.2f}")
    print(f"平均每笔盈亏: {avg_profit:.2f}")
    print(f"最大盈利: {max_win:.2f}")
    print(f"最大亏损: {max_loss:.2f}")

    print("\n===== 分批平仓统计 =====")
    for i in range(1, 6):
        count = close_stats[i]["count"]
        profit = close_stats[i]["profit"]
        ave_profit = profit / count if count > 0 else 0

        print(f"[平仓#{i}] 次数: {count} | 总盈亏: {round(profit,2)} | 平均盈亏: {round(ave_profit,2)}")

if __name__ == "__main__":
    log_file = "C:\\Users\\ruiwe\\AppData\\Roaming\\MetaQuotes\\Terminal\\836D60BB116D5AFA0D71F6C186288A1E\\Tester\\Logs\\20260312.log"   # 修改成你的log路径
    analyze_log(log_file)