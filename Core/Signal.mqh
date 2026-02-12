//+------------------------------------------------------------------+
//|                          Core/Signal.mqh                         |
//|                   Signal structure definition                    |
//+        信号结构体定义 = 交易信号的载体,策略执行后的"结果数据"         +
//+------------------------------------------------------------------+

#ifndef __SIGNAL_MQH__
#define __SIGNAL_MQH__

// 信号类型枚举
enum SignalType
{
    SIGNAL_NONE = 0,
    SIGNAL_BUY,        // 新开多仓
    SIGNAL_SELL,       // 新开空仓
    SIGNAL_EXIT,       // 平仓
    SIGNAL_ADD_LONG,   // 加仓多
    SIGNAL_ADD_SHORT   // 加仓空
};

// 信号结构体定义
struct Signal
{
    SignalType type;   // BUY / SELL / NONE / ADD_LONG / ADD_SHORT
    double confidence;       // 0.0 ~ 1.0
    string source;           // 哪个策略产生的
    datetime time;           // 信号时间
    double price;           // 触发价格
    double     sl;     // = 0 表示未指定
    double     tp;     // = 0 表示未指定

    double     exit_volume; // > 0: partial close volume

    // 结构冷却相关字段（由策略填充）
    double     atr;              // 入场时ATR
    double     structure_price;  // 结构点价格

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
        atr = 0.0;
        structure_price = 0.0;
    }
    
    // 辅助方法：判断是否为加仓信号
    bool IsAddSignal() const
    {
        return (type == SIGNAL_ADD_LONG || type == SIGNAL_ADD_SHORT);
    }
    
    // 辅助方法：判断是否为多头信号
    bool IsLongSignal() const
    {
        return (type == SIGNAL_BUY || type == SIGNAL_ADD_LONG);
    }
    
    // 辅助方法：判断是否为空头信号
    bool IsShortSignal() const
    {
        return (type == SIGNAL_SELL || type == SIGNAL_ADD_SHORT);
    }
};

#endif
