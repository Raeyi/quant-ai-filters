//+------------------------------------------------------------------+
//|                          Core/Strategy.mqh                       |
//|                   Strategy interface definition                  |
//+                    Strategy 的唯一职责 = 产生信号                  +
//+------------------------------------------------------------------+

#ifndef __STRATEGY_MQH__
#define __STRATEGY_MQH__

#include "Signal.mqh"

class IStrategy
{
public:
    // 析构函数
    virtual ~IStrategy() {}

    // 每个 tick 是否产生信号
    virtual bool GenerateSignal(Signal &outSignal) = 0;

    // 策略名称（用于日志 / AI / 投票）
    virtual string Name() = 0;
};

#endif
