//+------------------------------------------------------------------+
//|                          Risk/PositionRisk.mqh                   |
//|                   Position Risk definition                       |
//|                 仓位风险定义 = 时间 / 规则 / 主动退出              |
//+------------------------------------------------------------------+

#ifndef __RISK_POSITION_RISK_MQH__
#define __RISK_POSITION_RISK_MQH__ 

#include "TimeStop.mqh"

input int MaxHoldingBars = 5;   // 最大持仓时间（bar 数）

class PositionRisk
{
private:
    datetime entryTime; // 持仓时间
    TimeStop     time_stop;      // 时间止损（bar 数）
    
public:
    int     maxHoldingBars; // 最大持仓时间（bar 数）

public:
    PositionRisk()
    {
        entryTime       = 0;
        maxHoldingBars  = MaxHoldingBars;
        time_stop.Init(maxHoldingBars);
    }
    bool HasPosition()    // 检查是否有持仓
    {
        return PositionSelect(_Symbol);
    }

    bool AllowNewTrade() // 检查是否允许新交易
    {
        // 单仓模式
        static datetime last_log_bar = 0;
        datetime bar_time = iTime(_Symbol, _Period, 0);
        if(HasPosition())
        {
            if(bar_time != last_log_bar)
            {
                last_log_bar = bar_time;
                Print("[PositionRisk] 已有持仓，禁止新开仓");
            }
            return false;
        }
        return true;
    }
    void OnPositionOpened() // 记录持仓时间
    {
        entryTime = TimeCurrent();
    }

    void OnStrategyExit() // 策略退出时清除持仓时间
    {
        return;
    }

    bool ShouldForceClose() // 检查是否需要强制平仓
    {
        if(!HasPosition())
            return false;

        // --- 1: TimeStop ---
        if(IsTimeExceeded()) // 超过最大持仓时间
        {
            Print("[PositionRisk] TimeStop 触发");
            return true;
        }

        // --- 2: 未来可扩展 ---
        // if(IsSignalInvalid())
        // if(IsAIRiskReject())
        // if(IsDrawdownTooLarge())

        return false;
    }

private:
    bool IsTimeExceeded()
    {
        if(entryTime <= 0)
            return false;

        if(time_stop.ShouldClose())
        {
            return true;
        }

        return false;
    }
};

#endif// __RISK_POSITION_RISK_MQH__