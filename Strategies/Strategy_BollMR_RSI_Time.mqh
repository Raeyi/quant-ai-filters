#ifndef __STRATEGY_BOLL_MR_RSI_TIME_MQH__
#define __STRATEGY_BOLL_MR_RSI_TIME_MQH__

#include "../Indicators/Bollinger.mqh"
#include "../Indicators/ATR.mqh"
#include "../Indicators/RSI.mqh"
#include "../Core/Strategy.mqh"
#include "../Core/Inputs_BollMR.mqh"
#include "../Core/TimeFilter_BollMR.mqh"

// Base + RSI + Time filter (no trend / no layered exits)
class Strategy_BollMR_RSI_Time : public IStrategy
{
public:
    bool Init()
    {
        if(!InitBollinger(BollMR_BollPeriod, BollMR_BollDev))
        {
            Print("[" + Name() + "] Failed to initialize Bollinger");
            return false;
        }
        if(!InitATR(BollMR_ATRPeriod))
        {
            Print("[" + Name() + "] Failed to initialize ATR");
            return false;
        }
        if(!InitRSI(BollMR_RSIPeriod))
        {
            Print("[" + Name() + "] Failed to initialize RSI");
            return false;
        }
        Print("[" + Name() + "] indicators initialized successfully");
        return true;
    }

    bool UpdateIndicators()
    {
        if(!UpdateBollinger())
        {
            Print("[" + Name() + "] Failed to update Bollinger");
            return false;
        }
        if(!UpdateATR(50))
        {
            Print("[" + Name() + "] Failed to update ATR");
            return false;
        }
        if(!UpdateRSI(50))
        {
            Print("[" + Name() + "] Failed to update RSI");
            return false;
        }
        return true;
    }

    Signal GenerateSignal(Signal &signal) override
    {
        bool longSig  = LongSignal();
        bool shortSig = ShortSignal();
        bool exitSig  = HasExitSignal();

        if(!PositionSelect(_Symbol))
        {
            if(longSig)
            {
                FillSignal(signal, SIGNAL_BUY);
                Print("[" + Name() + "] Long signal filled. price=", signal.price,
                      " sl=", signal.sl);
                return signal;
            }
            if(shortSig)
            {
                FillSignal(signal, SIGNAL_SELL);
                Print("[" + Name() + "] Short signal filled. price=", signal.price,
                      " sl=", signal.sl);
                return signal;
            }
        }
        else
        {
            if(exitSig)
            {
                signal.type = SIGNAL_EXIT;
                FillSignal(signal, SIGNAL_EXIT);
                Print("[" + Name() + "] Exit signal filled.");
                return signal;
            }
        }

        signal.type = SIGNAL_NONE;
        return signal;
    }

    string Name() override
    {
        return "Bollinger_MeanReversion_RSI_Time";
    }

public:
    bool LongSignal()
    {
        if(!TimeFilterOK())
            return false;
        if(!VolatilityOK())
            return false;

        double rsi = GetRSI(1);
        if(rsi <= 0.0)
            return false;

        return (rsi <= BollMR_RSIOversold &&
                CloseAt(2) < GetBollLower(2) &&
                CloseAt(1) > GetBollLower(1) &&
                CloseAt(1) <= GetBollMiddle(1));
    }

    bool ShortSignal()
    {
        if(!TimeFilterOK())
            return false;
        if(!VolatilityOK())
            return false;

        double rsi = GetRSI(1);
        if(rsi <= 0.0)
            return false;

        return (rsi >= BollMR_RSIOverbought &&
                CloseAt(2) > GetBollUpper(2) &&
                CloseAt(1) < GetBollUpper(1) &&
                CloseAt(1) >= GetBollMiddle(1));
    }

    void FillSignal(Signal &s, SignalType type)
    {
        s.type       = type;
        s.source     = Name();
        s.time       = TimeCurrent();
        s.price      = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        s.confidence = 1.0;
        s.tp         = 0.0;

        if(type == SIGNAL_EXIT)
            return;

        double atr = GetATR(1);
        double sl  = 0.0;
        CalcSL((type == SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
               s.price, atr, sl);
        s.sl = sl;
    }

    double CloseAt(int shift)
    {
        return iClose(_Symbol, _Period, shift);
    }

    bool VolatilityOK()
    {
        double atr_now = GetATR(1);
        double atr_avg = GetATRMean(10, 1);
        if(atr_avg <= 0) return false;
        return (atr_now <= atr_avg * BollMR_ATRVolLimit);
    }

    bool HasExitSignal()
    {
        if(!PositionSelect(_Symbol))
            return false;

        ENUM_POSITION_TYPE type =
            (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

        double middle_ref = GetBollMiddle(1);
        double bid_now = SymbolInfoDouble(_Symbol, SYMBOL_BID);

        if(type == POSITION_TYPE_BUY)
            return (bid_now >= middle_ref);
        if(type == POSITION_TYPE_SELL)
            return (bid_now <= middle_ref);

        return false;
    }

    bool TimeFilterOK()
    {
        return BollMR_TimeFilterOK();
    }

    double CalcStructureSL(ENUM_ORDER_TYPE type, double atr)
    {
        if(type == ORDER_TYPE_BUY)
            return GetBollLower(1) - atr * BollMR_StructATRSL;
        else
            return GetBollUpper(1) + atr * BollMR_StructATRSL;
    }

    double CalcVolatilitySL(ENUM_ORDER_TYPE type, double entry, double atr)
    {
        if(type == ORDER_TYPE_BUY)
            return entry - atr * BollMR_VolATRSL;
        else
            return entry + atr * BollMR_VolATRSL;
    }

    void CalcSL(ENUM_ORDER_TYPE type, double entry, double atr, double &sl)
    {
        double min_dist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

        double structure_sl = CalcStructureSL(type, atr);
        double vol_sl       = CalcVolatilitySL(type, entry, atr);

        if(type == ORDER_TYPE_BUY)
            sl = MathMin(structure_sl, vol_sl);
        else
            sl = MathMax(structure_sl, vol_sl);

        if(type == ORDER_TYPE_BUY)
            sl = MathMin(sl, entry - min_dist);
        else
            sl = MathMax(sl, entry + min_dist);

        sl = NormalizeDouble(sl, _Digits);
    }
};

#endif // __STRATEGY_BOLL_MR_RSI_TIME_MQH__
