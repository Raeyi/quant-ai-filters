//+------------------------------------------------------------------+
//|                          Risk/Cooldown.mqh                       |
//|                   Cooldown definition                            |
//+------------------------------------------------------------------+
#ifndef __RISK_COOLDOWN_MQH__
#define __RISK_COOLDOWN_MQH__

class Cooldown
{
private:
    datetime last_trade_time;
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

    bool CanTrade() const
    {
        if(cooldown_seconds <= 0)
            return true;

        if(last_trade_time == 0)
            return true;

        return (TimeCurrent() - last_trade_time) >= cooldown_seconds;
    }

    int RemainingSeconds() const
    {
        if(cooldown_seconds <= 0 || last_trade_time == 0)
            return 0;

        int remaining = (int)(cooldown_seconds - (TimeCurrent() - last_trade_time));
        return (remaining > 0) ? remaining : 0;
    }

    bool InCooldown() const
    {
        return RemainingSeconds() > 0;
    }

    void OnTrade()
    {
        last_trade_time = TimeCurrent();
    }
};

#endif// __RISK_COOLDOWN_MQH__
