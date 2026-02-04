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

struct TradeRequest
{
    TradeDirection direction;
    double volume;
    double sl;
    double tp;
    string source;
};



#endif // __TRADE_TYPES_MQH__