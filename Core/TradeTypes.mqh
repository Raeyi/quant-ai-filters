//+------------------------------------------------------------------+
//|                          Core/TradeTypes.mqh                      |
//|                        Trade types definition                    |
//+                    Trade types for AI filtering                  +
//+------------------------------------------------------------------+

#ifndef __TRADE_TYPES_MQH__
#define __TRADE_TYPES_MQH__

enum TradeDirection
{
    TRADE_BUY,
    TRADE_SELL
};

enum TradeAction
{
    ACTION_OPEN,      // 开仓
    ACTION_MODIFY_SL, // 修改止损
    ACTION_MODIFY_TP  // 修改止盈
};

struct TradeRequest
{
    TradeDirection direction;
    double volume;
    double sl;
    double tp;
    string source;
    
    // 修改止损/止盈专用
    TradeAction action;
    double new_sl;   // 新止损价
    double new_tp;   // 新止盈价
    ulong ticket;    // 仓位票据
    
    TradeRequest()
    {
        direction = TRADE_BUY;
        volume = 0.0;
        sl = 0.0;
        tp = 0.0;
        source = "";
        action = ACTION_OPEN;
        new_sl = 0.0;
        new_tp = 0.0;
        ticket = 0;
    }
};



#endif // __TRADE_TYPES_MQH__