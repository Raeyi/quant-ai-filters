//+------------------------------------------------------------------+
//|                          Core/RiskGuard.mqh                      |
//|                        Risk Guard definition                     |
//+------------------------------------------------------------------+
#ifndef __RISK_GUARD_MQH__
#define __RISK_GUARD_MQH__

#include "../TradeTypes.mqh"
#include "../Signal.mqh"
#include "../../Indicators/ATR.mqh"
#include "PositionSizer.mqh" 

class RiskGuard
{
private:
    PositionSizer sizer;       // 统一仓位管理

public:
    bool BuildTrade(const Signal &signal, TradeRequest &req)
    {
        // === 方向 ===
        if(signal.type == SIGNAL_BUY)
            req.direction = TRADE_BUY;
        else if(signal.type == SIGNAL_SELL)
            req.direction = TRADE_SELL;
        else
            return false;

        // === 手数：用 PositionSizer 计算 ===
        double lot = sizer.ComputeLot(signal);
        if(lot <= 0.0)
        {
            Print("[RiskGuard] PositionSizer returned 0 lot, skip");
            return false;
        }
        req.volume = lot;

        double price = signal.price;
        double atr   = GetATR(1);   // 用上一根 ATR 更稳

        // === SL 处理：策略优先，否则用 ATR 兜底 ===
        if(signal.sl > 0)
            req.sl = signal.sl;
        else
            req.sl = (req.direction == TRADE_BUY
                      ? price - atr * 1.5
                      : price + atr * 1.5);
        
        // === TP 处理：策略优先，否则用 ATR 兜底 ===
        if(signal.tp > 0)
            req.tp = signal.tp;
        else
            req.tp = (req.direction == TRADE_BUY
                      ? price + atr * 2.0
                      : price - atr * 2.0);

        // === 最小止损距离校验 ===
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

        req.source = signal.source;
        return true;
    }
};

#endif // __RISK_GUARD_MQH__
