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
        // 检查持仓冲突：同方向可以加仓，不同方向拒绝
        if(PositionSelect(_Symbol))
        {
            long pos_type = PositionGetInteger(POSITION_TYPE);
            bool has_long = (pos_type == POSITION_TYPE_BUY);
            bool has_short = (pos_type == POSITION_TYPE_SELL);
            
            // 方向冲突检查
            if((req.direction == TRADE_BUY && has_short) ||
               (req.direction == TRADE_SELL && has_long))
            {
                Print("[", source, "] 下单被拒：持仓方向冲突");
                return false;
            }
            // 同方向 = 加仓，允许继续
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
              " retcode=", trade.ResultRetcode(),
              " 订单=", trade.ResultOrder(),
              " 成交=", trade.ResultDeal(),
              " 价格=", DoubleToString(trade.ResultPrice(), _Digits));
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
                  " 描述=", trade.ResultRetcodeDescription(),
                  " 备注=", trade.ResultComment(),
                  " err=", err);
            return false;
        }
        Print("[TradeExecutor] 部分平仓已发送",
              " 方向=", (type==POSITION_TYPE_BUY ? "BUY" : "SELL"),
              " 手数=", DoubleToString(v, 2),
              " 开仓价=", DoubleToString(price_open, _Digits),
              " sl=", DoubleToString(sl, _Digits),
              " tp=", DoubleToString(tp, _Digits),
              " retcode=", trade.ResultRetcode(),
              " 订单=", trade.ResultOrder(),
              " 成交=", trade.ResultDeal(),
              " 价格=", DoubleToString(trade.ResultPrice(), _Digits));
        return true;
    }
    
    // 修改止损
    bool ModifySL(double new_sl, string source)
    {
        if(!PositionSelect(_Symbol))
        {
            Print("[", source, "] 修改止损失败：无持仓");
            return false;
        }
        
        ulong ticket = PositionGetInteger(POSITION_TICKET);
        double cur_sl = PositionGetDouble(POSITION_SL);
        double cur_tp = PositionGetDouble(POSITION_TP);
        long type = PositionGetInteger(POSITION_TYPE);
        double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
        
        // 检查新止损是否有效
        if(new_sl <= 0)
        {
            Print("[", source, "] 修改止损失败：无效止损价 ", DoubleToString(new_sl, _Digits));
            return false;
        }
        
        // 检查止损是否朝有利方向移动（保护性止损只能往盈利方向移）
        bool is_buy = (type == POSITION_TYPE_BUY);
        bool is_improving = is_buy ? (new_sl > cur_sl) : (new_sl < cur_sl);
        
        if(!is_improving)
        {
            Print("[", source, "] 修改止损跳过：止损未改善 cur_sl=", 
                  DoubleToString(cur_sl, _Digits), " new_sl=", DoubleToString(new_sl, _Digits));
            return false;
        }
        
        // 检查止损距离限制
        long stops = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
        double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
        double min_dist = stops * point;
        double current_price = is_buy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) 
                                       : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        
        if(is_buy && (current_price - new_sl) < min_dist)
        {
            Print("[", source, "] 修改止损失败：止损距离不足 min_dist=", 
                  DoubleToString(min_dist, _Digits));
            return false;
        }
        else if(!is_buy && (new_sl - current_price) < min_dist)
        {
            Print("[", source, "] 修改止损失败：止损距离不足 min_dist=", 
                  DoubleToString(min_dist, _Digits));
            return false;
        }
        
        // 执行修改
        bool ok = trade.PositionModify(ticket, new_sl, cur_tp);
        if(!ok)
        {
            int err = GetLastError();
            Print("[", source, "] 修改止损失败",
                  " ticket=", ticket,
                  " 方向=", (is_buy ? "BUY" : "SELL"),
                  " 旧SL=", DoubleToString(cur_sl, _Digits),
                  " 新SL=", DoubleToString(new_sl, _Digits),
                  " retcode=", trade.ResultRetcode(),
                  " 描述=", trade.ResultRetcodeDescription(),
                  " err=", err);
            return false;
        }
        
        Print("[", source, "] 修改止损成功",
              " ticket=", ticket,
              " 方向=", (is_buy ? "BUY" : "SELL"),
              " 开仓价=", DoubleToString(open_price, _Digits),
              " 旧SL=", DoubleToString(cur_sl, _Digits),
              " 新SL=", DoubleToString(new_sl, _Digits),
              " 移动=", DoubleToString(MathAbs(new_sl - cur_sl), _Digits), "点");
        return true;
    }
    
    // 修改止盈
    bool ModifyTP(double new_tp, string source)
    {
        if(!PositionSelect(_Symbol))
        {
            Print("[", source, "] 修改止盈失败：无持仓");
            return false;
        }
        
        ulong ticket = PositionGetInteger(POSITION_TICKET);
        double cur_sl = PositionGetDouble(POSITION_SL);
        double cur_tp = PositionGetDouble(POSITION_TP);
        long type = PositionGetInteger(POSITION_TYPE);
        double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
        
        if(new_tp <= 0)
        {
            Print("[", source, "] 修改止盈失败：无效止盈价 ", DoubleToString(new_tp, _Digits));
            return false;
        }
        
        bool is_buy = (type == POSITION_TYPE_BUY);
        
        // 执行修改
        bool ok = trade.PositionModify(ticket, cur_sl, new_tp);
        if(!ok)
        {
            int err = GetLastError();
            Print("[", source, "] 修改止盈失败",
                  " ticket=", ticket,
                  " 方向=", (is_buy ? "BUY" : "SELL"),
                  " 旧TP=", DoubleToString(cur_tp, _Digits),
                  " 新TP=", DoubleToString(new_tp, _Digits),
                  " retcode=", trade.ResultRetcode(),
                  " 描述=", trade.ResultRetcodeDescription(),
                  " err=", err);
            return false;
        }
        
        Print("[", source, "] 修改止盈成功",
              " ticket=", ticket,
              " 方向=", (is_buy ? "BUY" : "SELL"),
              " 旧TP=", DoubleToString(cur_tp, _Digits),
              " 新TP=", DoubleToString(new_tp, _Digits));
        return true;
    }
};

#endif// __TRADE_EXECUTOR_MQH__

