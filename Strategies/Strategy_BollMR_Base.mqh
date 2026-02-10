#ifndef __STRATEGY_BOLL_MR_BASE_MQH__
#define __STRATEGY_BOLL_MR_BASE_MQH__

#include "../Indicators/Bollinger.mqh"
#include "../Indicators/ATR.mqh"
#include "../Core/Strategy.mqh"

// 基线版：BB + ATR（不含时间/趋势/分层退出）
input int    BollPeriod_Base  = 20;   // 布林带周期
input double BollDev_Base     = 2.0;  // 布林带标准差
input int    ATRPeriod_Base   = 14;   // ATR 周期

input double StructATRSL_Base = 0.8;  // 结构止损 ATR 倍数
input double VolATRSL_Base    = 2.0;  // 波动止损 ATR 倍数
input double ATRVolLimit_Base = 1.5;  // ATR 过滤倍数

class Strategy_BollMR_Base : public IStrategy
{
public:
    bool Init()
    {
        if(!InitBollinger(BollPeriod_Base, BollDev_Base))
        {
            Print("[" + Name() + "] Failed to initialize Bollinger");
            return false;
        }

        if(!InitATR(ATRPeriod_Base))
        {
            Print("[" + Name() + "] Failed to initialize ATR");
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

        return true;
    }

    Signal GenerateSignal(Signal &signal) override
    {
        bool longSig  = LongSignal();
        bool shortSig = ShortSignal();
        bool exitSig  = HasExitSignal();

        if(!PositionSelect(_Symbol)) // 无持仓
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
        return "Bollinger_MeanReversion_Base";
    }

public:
    bool LongSignal()
    {
        if(!VolatilityOK())
            return false;

        return (CloseAt(2) < GetBollLower(2) &&
                CloseAt(1) > GetBollLower(1) &&
                CloseAt(1) <= GetBollMiddle(1));
    }

    bool ShortSignal()
    {
        if(!VolatilityOK())
            return false;

        return (CloseAt(2) > GetBollUpper(2) &&
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

        double atr = GetATR(1); // 上一根已收盘 ATR
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
        return (atr_now <= atr_avg * ATRVolLimit_Base);
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

    //--------------------------------------------------
    // 计算结构止损价格
    double CalcStructureSL(ENUM_ORDER_TYPE type, double atr)
    {
        if(type == ORDER_TYPE_BUY)
            return GetBollLower(1) - atr * StructATRSL_Base;
        else
            return GetBollUpper(1) + atr * StructATRSL_Base;
    }

    //--------------------------------------------------
    // 计算波动止损价格
    double CalcVolatilitySL(ENUM_ORDER_TYPE type, double entry, double atr)
    {
        if(type == ORDER_TYPE_BUY)
            return entry - atr * VolATRSL_Base;
        else
            return entry + atr * VolATRSL_Base;
    }

    //--------------------------------------------------
    // 计算止损价格
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

#endif // __STRATEGY_BOLL_MR_BASE_MQH__
