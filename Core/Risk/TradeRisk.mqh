//+------------------------------------------------------------------+
//|                          Risk/TradeRisk.mqh                      |
//+------------------------------------------------------------------+
#ifndef __RISK_TRADE_RISK_MQH__
#define __RISK_TRADE_RISK_MQH__

#include "../Signal.mqh"
#include "../TradeExecutor.mqh"
#include "../../Indicators/ATR.mqh"

class TradeRisk
{
public:
    bool Validate(const Signal &signal, TradeRequest &req)
    {
        // 对于SIGNAL_NONE（type=0）不打印日志，减少噪音
        if(signal.type != SIGNAL_NONE)
        {
            Print("[TradeRisk] Validate signal type=", signal.type, " source=", signal.source);
        }
        // 方向（支持加仓信号）
        if(signal.type == SIGNAL_BUY || signal.type == SIGNAL_ADD_LONG)
            req.direction = TRADE_BUY;
        else if(signal.type == SIGNAL_SELL || signal.type == SIGNAL_ADD_SHORT)
            req.direction = TRADE_SELL;
        else
            return false;

        // volume 不在这里设，由 PositionSizer 决定
        // req.volume 由外部填好后再传进来

        // SL / TP 来自策略
        req.sl = signal.sl;
        req.tp = signal.tp;

        double price = signal.price;

        // ---- 最小止损距离保护 ----
        long   stops     = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
        double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
        double min_dist  = stops * point;

        if(req.sl > 0 && price > 0 && min_dist > 0)
        {
            if(req.direction == TRADE_BUY)
            {
                if((price - req.sl) < min_dist)
                    req.sl = price - min_dist;
            }
            else // SELL
            {
                if((req.sl - price) < min_dist)
                    req.sl = price + min_dist;
            }
        }

        if(req.sl > 0)
            req.sl = NormalizeDouble(req.sl, _Digits);
        if(req.tp > 0)
            req.tp = NormalizeDouble(req.tp, _Digits);

        return true;
    }
};

#endif // __RISK_TRADE_RISK_MQH__
