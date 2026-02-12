//+------------------------------------------------------------------+
//|                          Risk/PositionRisk.mqh                   |
//|                   Position Risk definition                       |
//|                 仓位风险定义 = 时间 / 规则 / 主动退出              |
//+------------------------------------------------------------------+

#ifndef __RISK_POSITION_RISK_MQH__
#define __RISK_POSITION_RISK_MQH__ 

#include "TimeStop.mqh"
#include "../Signal.mqh"
#include "../Inputs_All.mqh"

// 输入参数定义在 Inputs_All.mqh，此文件不再重复声明

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

    // 无参数版本（兼容旧调用）
    bool AllowNewTrade()
    {
        Signal empty;
        return AllowNewTrade(empty);
    }
    
    // 检查是否允许新交易（支持加仓信号）
    bool AllowNewTrade(const Signal &signal)
    {
        // 加仓信号：允许（后续由 AddPositionManager 控制）
        if(signal.IsAddSignal())
        {
            // Print("[PositionRisk] Add signal allowed. type=", signal.type); // 减少日志噪音
            return true;
        }
        
        // 新开仓：单仓模式
        if(HasPosition())
        {
            // 对于SIGNAL_NONE（type=0）不打印日志，减少噪音
            if(signal.type != SIGNAL_NONE)
            {
                static datetime last_log_time = 0;
                datetime current_time = TimeCurrent();
                if(current_time - last_log_time >= 60) // 每分钟最多打印一次
                {
                    last_log_time = current_time;
                    Print("[PositionRisk] 已有持仓，禁止新开仓. signal type=", signal.type);
                }
            }
            return false;
        }
        // Print("[PositionRisk] No position, new trade allowed. signal type=", signal.type); // 减少日志噪音
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
