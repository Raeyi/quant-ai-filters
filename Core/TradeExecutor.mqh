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
        {
            Print("[", source, "] 下单被拒：已有持仓");
            return false;
        }
        
        if(req.direction == TRADE_BUY)
        {
            trade.SetDeviationInPoints(20); // 设置滑点

            bool ok = trade.Buy(req.volume, _Symbol, 0, req.sl, req.tp);

            if(!ok)
            {
                int err = GetLastError();
                Print("[", source, "] 买入失败 手数=", DoubleToString(req.volume, 2),
                      " sl=", DoubleToString(req.sl, _Digits),
                      " tp=", DoubleToString(req.tp, _Digits),
                      " retcode=", trade.ResultRetcode(),
                      " 描述=", trade.ResultRetcodeDescription(),
                      " 备注=", trade.ResultComment(),
                      " err=", err);
                return false;
            }

            Print("[", source, "] 买入已发送 手数=", DoubleToString(req.volume, 2),
                  " sl=", DoubleToString(req.sl, _Digits),
                  " tp=", DoubleToString(req.tp, _Digits),
                  " retcode=", trade.ResultRetcode(),
                  " 订单=", trade.ResultOrder(),
                  " 成交=", trade.ResultDeal(),
                  " 价格=", DoubleToString(trade.ResultPrice(), _Digits));
            return ok;
        }
        else
        {
            trade.SetDeviationInPoints(20); // 设置滑点
            bool ok = trade.Sell(req.volume, _Symbol, 0, req.sl, req.tp);

            if(!ok)
            {
                int err = GetLastError();
                Print("[", source, "] 卖出失败 手数=", DoubleToString(req.volume, 2),
                      " sl=", DoubleToString(req.sl, _Digits),
                      " tp=", DoubleToString(req.tp, _Digits),
                      " retcode=", trade.ResultRetcode(),
                      " 描述=", trade.ResultRetcodeDescription(),
                      " 备注=", trade.ResultComment(),
                      " err=", err);
                return false;
            }

            Print("[", source, "] 卖出已发送 手数=", DoubleToString(req.volume, 2),
                  " sl=", DoubleToString(req.sl, _Digits),
                  " tp=", DoubleToString(req.tp, _Digits),
                  " retcode=", trade.ResultRetcode(),
                  " 订单=", trade.ResultOrder(),
                  " 成交=", trade.ResultDeal(),
                  " 价格=", DoubleToString(trade.ResultPrice(), _Digits));
            return ok;
        }
            
    }

    bool Close()
    {
        if(!PositionSelect(_Symbol))
            return false;

        ulong ticket = PositionGetInteger(POSITION_TICKET);
        double vol = PositionGetDouble(POSITION_VOLUME);
        double price_open = PositionGetDouble(POSITION_PRICE_OPEN);
        double sl = PositionGetDouble(POSITION_SL);
        double tp = PositionGetDouble(POSITION_TP);
        long type = PositionGetInteger(POSITION_TYPE);

        bool ok = trade.PositionClose(ticket);
        if(!ok)
        {
            int err = GetLastError();
            Print("[TradeExecutor] 平仓失败 ticket=", ticket,
                  " 方向=", (type==POSITION_TYPE_BUY ? "BUY" : "SELL"),
                  " 手数=", DoubleToString(vol, 2),
                  " 开仓价=", DoubleToString(price_open, _Digits),
                  " sl=", DoubleToString(sl, _Digits),
                  " tp=", DoubleToString(tp, _Digits),
                  " retcode=", trade.ResultRetcode(),
                  " 描述=", trade.ResultRetcodeDescription(),
                  " 备注=", trade.ResultComment(),
                  " err=", err);
            return false;
        }

        Print("[TradeExecutor] 平仓已发送 ticket=", ticket,
              " 方向=", (type==POSITION_TYPE_BUY ? "BUY" : "SELL"),
              " 手数=", DoubleToString(vol, 2),
              " 开仓价=", DoubleToString(price_open, _Digits),
              " sl=", DoubleToString(sl, _Digits),
              " tp=", DoubleToString(tp, _Digits),
              " retcode=", trade.ResultRetcode());
        return true;
    }

    bool ClosePartial(double volume) // 部分平仓接口，volume 是要平掉的手数
    {
        if(!PositionSelect(_Symbol))
            return false;

        double min_vol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
        double cur_vol = PositionGetDouble(POSITION_VOLUME);
        double price_open = PositionGetDouble(POSITION_PRICE_OPEN);
        double sl = PositionGetDouble(POSITION_SL);
        double tp = PositionGetDouble(POSITION_TP);
        long type = PositionGetInteger(POSITION_TYPE);

        double v = MathMin(volume, cur_vol);
        v = NormalizeVolume_(v);

        if(v < min_vol)
            return false;

        trade.SetDeviationInPoints(20);
        bool ok = trade.PositionClosePartial(_Symbol, v);
        if(!ok)
        {
            int err = GetLastError();
            Print("[TradeExecutor] 部分平仓失败",
                  " 方向=", (type==POSITION_TYPE_BUY ? "BUY" : "SELL"),
                  " 手数=", DoubleToString(v, 2),
                  " 开仓价=", DoubleToString(price_open, _Digits),
                  " sl=", DoubleToString(sl, _Digits),
                  " tp=", DoubleToString(tp, _Digits),
                  " retcode=", trade.ResultRetcode(),
                  " err=", err);
            return false;
        }
        Print("[TradeExecutor] 部分平仓已发送",
              " 方向=", (type==POSITION_TYPE_BUY ? "BUY" : "SELL"),
              " 手数=", DoubleToString(v, 2),
              " 开仓价=", DoubleToString(price_open, _Digits),
              " sl=", DoubleToString(sl, _Digits),
              " tp=", DoubleToString(tp, _Digits),
              " retcode=", trade.ResultRetcode());
        return true;
    }
};

#endif// __TRADE_EXECUTOR_MQH__

