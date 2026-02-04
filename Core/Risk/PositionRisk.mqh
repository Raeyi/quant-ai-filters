//+------------------------------------------------------------------+
//|                          Risk/PositionRisk.mqh                   |
//|                   Position Risk definition                       |
//+                 仓位风险定义 = 时间 / 规则 / 主动退出               +
//+------------------------------------------------------------------+

#ifndef __RISK_POSITION_RISK_MQH__
#define __RISK_POSITION_RISK_MQH__ 

input int MaxHoldMinutes = 180;   // 最大持仓时间（分钟）

class PositionRisk
{
private:
    datetime entryTime; // 持仓时间

public:
    bool HasPosition()    // 检查是否有持仓
    {
        return PositionSelect(_Symbol);
    }

    bool AllowNewTrade() // 检查是否允许新交易
    {
        // 单仓模式
        if(HasPosition())
        {
            Print("[PositionRisk] Position exists, no new trade");
            return false;
        }
        return true;
    }
    void OnPositionOpened() // 记录持仓时间
    {
        entryTime = TimeCurrent();
    }


    bool ShouldForceClose() // 检查是否需要强制平仓
    {
        if(!HasPosition())
            return false;

        // --- 1️⃣ TimeStop ---
        if(IsTimeExceeded()) // 超过最大持仓时间
        {
            Print("[PositionRisk] TimeStop triggered");
            return true;
        }

        // --- 2️⃣ 未来可扩展 ---
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

        int heldMinutes = int((TimeCurrent() - entryTime) / 60);
        return heldMinutes >= MaxHoldMinutes;
    }
};

#endif// __RISK_POSITION_RISK_MQH__