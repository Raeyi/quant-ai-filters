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
    double NormalizeVolume_(double volume) const // 将交易量规范化为符合当前品种要求的最小单位
    {
        double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
        if(step <= 0.0)
            return volume;

        double normalized = MathFloor(volume / step) * step;
        int digits = 0;
        if(step > 0.0)
            digits = (int)MathRound(-MathLog10(step)); // 用步进推算手数小数位
        return NormalizeDouble(normalized, digits);
    }

public:
    bool Execute(const TradeRequest &req, const string &source)
    {
        if(PositionSelect(_Symbol))
            return false;
        
        if(req.direction == TRADE_BUY)
        {
            trade.SetDeviationInPoints(20); // 设置滑点

            bool ok = trade.Buy(req.volume, _Symbol, 0, req.sl, req.tp);

            if(!ok)
            {
                Print("[" + source + "] Failed to execute Buy order");
                return false;
            }

            return ok;
        }
        else
        {
            trade.SetDeviationInPoints(20); // 设置滑点
            bool ok = trade.Sell(req.volume, _Symbol, 0, req.sl, req.tp);

            if(!ok)
            {
                Print("[" + source + "] Failed to execute Sell order");
                return false;
            }

            return ok;
        }
            
    }

    bool Close()
    {
        if(!PositionSelect(_Symbol))
            return false;

        ulong ticket = PositionGetInteger(POSITION_TICKET);
        return trade.PositionClose(ticket);
    }

    bool ClosePartial(double volume) // 部分平仓接口，volume 是要平掉的手数
    {
        if(!PositionSelect(_Symbol))
            return false;

        double min_vol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
        double cur_vol = PositionGetDouble(POSITION_VOLUME);

        double v = MathMin(volume, cur_vol);
        v = NormalizeVolume_(v);

        if(v < min_vol)
            return false;

        trade.SetDeviationInPoints(20);
        return trade.PositionClosePartial(_Symbol, v);
    }
};

#endif// __TRADE_EXECUTOR_MQH__

