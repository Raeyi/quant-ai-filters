#ifndef __STRATEGY_BOLL_MR_MQH__
#define __STRATEGY_BOLL_MR_MQH__

#include "../Indicators/Bollinger.mqh"
#include "../Indicators/ATR.mqh"
#include "../Core/Strategy.mqh"

class Strategy_BollMR : public IStrategy
{
public:
    bool GenerateSignal(Signal &signal) override
    {
        bool longSig  = LongSignal();
        bool shortSig = ShortSignal();

        // Print("[BollMR] GenerateSignal called. long=", longSig, " short=", shortSig);

        if(longSig)
        {
            FillSignal(signal, SIGNAL_BUY);
            Print("[BollMR] Long signal filled. price=", signal.price,
                " sl=", signal.sl, " tp=", signal.tp);
            return true;
        }
        if(shortSig)
        {
            FillSignal(signal, SIGNAL_SELL);
            Print("[BollMR] Short signal filled. price=", signal.price,
                " sl=", signal.sl, " tp=", signal.tp);
            return true;
        }
        return false;
    }

    string Name() override
    {
        return "Bollinger_MeanReversion";
    }

private:
    bool LongSignal()
    {
        return (CloseAt(1) < GetBollLower(1) &&
                CloseAt(0) > GetBollLower(0) && 
                MiddleUp() && 
                VolatilityOK());
    }

    bool ShortSignal()
    {
        return (CloseAt(1) > GetBollUpper(1) &&
                CloseAt(0) < GetBollUpper(0) && 
                MiddleDown() && 
                VolatilityOK());
    }

    void FillSignal(Signal &s, SignalType type)
    {
        s.type       = type;
        s.source     = Name();
        s.time       = TimeCurrent();
        s.price      = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        s.confidence = 1.0;

        double atr  = GetATR(1);          // 用上一根已收盘 ATR
        double bl1  = GetBollLower(1);    // 上一根下轨
        double bu1  = GetBollUpper(1);    // 上一根上轨
        double mid0 = GetBollMiddle(0);   // 当前中轨（已收盘 bar）

        if(type == SIGNAL_BUY)
        {
            // 结构止损：前一根下轨之下一定距离
            double structure_sl = bl1 - atr * 0.8;
            // 波动止损：进场价下方若干 ATR
            double vol_sl       = s.price - atr * 2.0;
            // 均值回归：取更远的那个（更宽）
            s.sl = MathMin(structure_sl, vol_sl);
            s.tp = mid0;                  // 先以中轨作为目标
        }
        else if(type == SIGNAL_SELL)
        {
            // 结构止损：前一根上轨之上一定距离
            double structure_sl = bu1 + atr * 0.8;
            // 波动止损：进场价上方若干 ATR
            double vol_sl       = s.price + atr * 2.0;
            // 空头：取更远的那个（更宽）
            s.sl = MathMax(structure_sl, vol_sl);
            s.tp = mid0;
        }
        else
        {
            s.sl = 0.0;
            s.tp = 0.0;
        }
    }

    double CloseAt(int shift)
    {
        return iClose(_Symbol, _Period, shift);
    }

    bool MiddleUp()
    {
        return GetBollMiddle(0) >= GetBollMiddle(1);
    }

    bool MiddleDown()
    {
        return GetBollMiddle(0) <= GetBollMiddle(1);
    }

    bool VolatilityOK()
    {
        double atr_now = GetATR(1);
        double atr_avg = GetATRMean(10, 1);
        if(atr_avg <= 0) return false;

        if(atr_now > atr_avg * 1.5)
            return false;

        return true;
    }

    bool ConfirmedReentryLong()
    {
        return (CloseAt(1) < GetBollLower(1) &&
                CloseAt(0) > GetBollLower(0));
    }

    bool ConfirmedReentryShort()
    {
        return (CloseAt(1) > GetBollUpper(1) &&
                CloseAt(0) < GetBollUpper(0));
    }
};


class Strategy_AlwaysBuy : public IStrategy
{
public:
    bool GenerateSignal(Signal &outSignal) override
    {
        outSignal.type       = SIGNAL_BUY;
        outSignal.source     = "AlwaysBuy";
        outSignal.time       = TimeCurrent();
        outSignal.price      = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        outSignal.confidence = 1.0;
        outSignal.sl         = 0;
        outSignal.tp         = 0;

        Print("[AlwaysBuy] Filled signal. price=", outSignal.price);
        return true;
    }

    string Name() override { return "AlwaysBuy"; }
};

#endif // __STRATEGY_BOLL_MR_MQH__
