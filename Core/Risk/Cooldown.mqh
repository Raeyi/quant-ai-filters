//+------------------------------------------------------------------+
//|                          Risk/Cooldown.mqh                       |
//|                   Cooldown definition                            |
//+                 冷却时间定义 = 持仓时间限制（防过度交易）            +
//+------------------------------------------------------------------+

#ifndef __RISK_COOLDOWN_MQH__
#define __RISK_COOLDOWN_MQH__

class Cooldown
{
private:
    datetime last_trade_time; // 上次交易时间
    int      cooldown_seconds;

public:
    Cooldown()
    {
        last_trade_time  = 0;
        cooldown_seconds = 0;
    }

    void Init(int seconds)
    {
        cooldown_seconds = seconds;
    }

    bool CanTrade()
    {
        if(cooldown_seconds <= 0)
            return true;

        if(last_trade_time == 0)
            return true;

        return (TimeCurrent() - last_trade_time) >= cooldown_seconds;
    }

    void OnTrade()
    {
        last_trade_time = TimeCurrent();
    }
};


#endif// __RISK_COOLDOWN_MQH__