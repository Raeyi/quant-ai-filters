//+------------------------------------------------------------------+
//|                          Risk/TimeStop.mqh                       |
//|                   Time Stop definition                           |
//+                 时间止损定义 = 持仓时间限制                        +
//+------------------------------------------------------------------+

#ifndef __RISK_TIME_STOP_MQH__
#define __RISK_TIME_STOP_MQH__

class TimeStop
{
private:
    int max_bars; // 最大持仓时间（bar 数）

public:
    TimeStop()
    {
        max_bars = 0;
    }

    void Init(int bars)
    {
        max_bars = bars;
    }

    bool ShouldClose()
    {
        if(max_bars <= 0)
            return false;

        if(!PositionSelect(_Symbol))
            return false;

        datetime open_time  = (datetime)PositionGetInteger(POSITION_TIME);
        int      held_sec   = (int)(TimeCurrent() - open_time);
        int      limit_sec  = max_bars * PeriodSeconds(_Period);

        return held_sec >= limit_sec;
    }
};


#endif// __RISK_TIME_STOP_MQH__