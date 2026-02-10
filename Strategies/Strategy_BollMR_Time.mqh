#ifndef __STRATEGY_BOLL_MR_TIME_MQH__
#define __STRATEGY_BOLL_MR_TIME_MQH__

#include "../Indicators/Bollinger.mqh"
#include "../Indicators/ATR.mqh"
#include "../Core/Strategy.mqh"
#include "../Core/Inputs_BollMR.mqh"
#include "../Core/TimeFilter_BollMR.mqh"

// 基线 + 时间过滤（不含趋势/RSI/分层退出）
class Strategy_BollMR_Time : public IStrategy
{
public:
    // 初始化指标（Bollinger/ATR）
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

        Print("[" + Name() + "] indicators initialized successfully");
        return true;
    }

    // 更新指标缓存数据
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

    // 生成交易信号（仅在满足入场或出场条件时返回）
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

    // 策略名称（用于日志/统计）
    string Name() override
    {
        return "Bollinger_MeanReversion_Time";
    }

public:
    // 多头入场：时间过滤 + BB 回归形态 + 波动过滤
    bool LongSignal()
    {
        if(!TimeFilterOK())
            return false;
        if(!VolatilityOK())
            return false;

        return (CloseAt(2) < GetBollLower(2) &&
                CloseAt(1) > GetBollLower(1) &&
                CloseAt(1) <= GetBollMiddle(1));
    }

    // 空头入场：时间过滤 + BB 回归形态 + 波动过滤
    bool ShortSignal()
    {
        if(!TimeFilterOK())
            return false;
        if(!VolatilityOK())
            return false;

        return (CloseAt(2) > GetBollUpper(2) &&
                CloseAt(1) < GetBollUpper(1) &&
                CloseAt(1) >= GetBollMiddle(1));
    }

    // 填充信号字段与止损
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

    // 获取指定 K 线收盘价
    double CloseAt(int shift)
    {
        return iClose(_Symbol, _Period, shift);
    }

    // 波动过滤：当前 ATR 不超过过去均值的倍数
    bool VolatilityOK()
    {
        double atr_now = GetATR(1);
        double atr_avg = GetATRMean(10, 1);
        if(atr_avg <= 0) return false;
        return (atr_now <= atr_avg * BollMR_ATRVolLimit);
    }

    // 出场信号：价格回到中轨
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

    // 时间过滤：基于 MT5 服务器时间 (BollMR_StartHour/BollMR_EndHour)
    bool TimeFilterOK()
    {
        return BollMR_TimeFilterOK();
    }

    // 结构止损：参考布林带上下轨 + ATR
    double CalcStructureSL(ENUM_ORDER_TYPE type, double atr)
    {
        if(type == ORDER_TYPE_BUY)
            return GetBollLower(1) - atr * BollMR_StructATRSL;
        else
            return GetBollUpper(1) + atr * BollMR_StructATRSL;
    }

    // 波动止损：以 ATR 倍数给出止损
    double CalcVolatilitySL(ENUM_ORDER_TYPE type, double entry, double atr)
    {
        if(type == ORDER_TYPE_BUY)
            return entry - atr * BollMR_VolATRSL;
        else
            return entry + atr * BollMR_VolATRSL;
    }

    // 计算最终止损（结构止损与波动止损取更宽者）
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

#endif // __STRATEGY_BOLL_MR_TIME_MQH__
