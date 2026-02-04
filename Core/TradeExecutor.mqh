//+------------------------------------------------------------------+
//|                          Core/TradeExecutor.mqh                |
//|                        Trade executor definition               |
//+                    Trade executor 的唯一职责 = 执行交易          +
//+------------------------------------------------------------------+

#ifndef __TRADE_EXECUTOR_MQH__
#define __TRADE_EXECUTOR_MQH__  

#include <Trade/Trade.mqh>
#include "TradeTypes.mqh"

class TradeExecutor
{
private:
    CTrade trade;

public:
    bool Execute(const TradeRequest &req)
    {
        if(PositionSelect(_Symbol))
            return false;

        if(req.direction == TRADE_BUY)
            return trade.Buy(req.volume, _Symbol, 0, req.sl, req.tp);
        else
            return trade.Sell(req.volume, _Symbol, 0, req.sl, req.tp);
    }

    bool Close()
    {
        if(!PositionSelect(_Symbol))
            return false;

        ulong ticket = PositionGetInteger(POSITION_TICKET);
        return trade.PositionClose(ticket);
    }
};

#endif// __TRADE_EXECUTOR_MQH__