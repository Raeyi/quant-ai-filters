# Web 信号对比面板

该页面用于对比 MT5 实盘/模拟信号与回测信号，支持 JSON/CSV 两种格式。

## 使用方式
1. 进入 `web` 目录后启动静态服务：
   ```bash
   python -m http.server 8000
   ```
2. 浏览器打开 `http://localhost:8000`。
3. 分别上传 MT5 与回测的信号文件。
4. 选择匹配键与对比字段，点击 **开始对比**。

## 数据格式

### JSON
```json
[
  {
    "time": "2024-01-01 10:00",
    "symbol": "XAUUSD",
    "type": "BUY",
    "price": 2000.5,
    "sl": 1990.0,
    "tp": 2020.0,
    "source": "BollMR",
    "timeframe": "M5"
  }
]
```

### CSV
```
time,symbol,type,price,sl,tp,source,timeframe
2024-01-01 10:00,XAUUSD,BUY,2000.5,1990,2020,BollMR,M5
```

## 说明
- 匹配键建议至少包含 `time`、`symbol`、`type`。
- 价格容差可用于忽略轻微滑点差异。
