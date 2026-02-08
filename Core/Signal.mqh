//+------------------------------------------------------------------+
//|                          Core/Signal.mqh                         |
//|                   Signal structure definition                    |
//+        信号结构体定义 = 交易信号的载体,策略执行后的“结果数据”         +
//+------------------------------------------------------------------+

#ifndef __SIGNAL_MQH__
#define __SIGNAL_MQH__

// 信号类型枚举
enum SignalType
{
    SIGNAL_NONE = 0,
    SIGNAL_BUY,
    SIGNAL_SELL,
    SIGNAL_EXIT
};

// 信号结构体定义
struct Signal
{
    SignalType type;   // BUY / SELL / NONE
    double confidence;       // 0.0 ~ 1.0
    string source;           // 哪个策略产生的
    datetime time;           // 信号时间
    double price;           // 触发价格
    double     sl;     // = 0 表示未指定
    double     tp;     // = 0 表示未指定

    double     exit_volume; // > 0: partial close volume

    Signal()
    {
        type = SIGNAL_NONE;  // 最基本交易方向
        confidence = 0.0;    // 信心指数, 以后 AI / Vote / 风控全靠它
        source = "";        // 信号来源, 方便日志 & 多策略共存
        time = 0;           // 信号时间戳, 防止重复信号 / 回测对齐
        price = 0.0;         // 信号触发时的价格
        sl = 0.0;          // 默认不设定止损
        tp = 0.0;       // 默认不设定止盈

        exit_volume = 0.0;
    }
};

#endif

