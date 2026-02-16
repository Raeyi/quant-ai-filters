#ifndef __STRATEGY_BOLL_MR_ENHANCED_MQH__
#define __STRATEGY_BOLL_MR_ENHANCED_MQH__

#include "../Indicators/Bollinger.mqh"
#include "../Indicators/ATR.mqh"
#include "../Indicators/MA.mqh"
#include "../Core/Strategy.mqh"
#include "../Core/TimeFilter_BollMR.mqh"
#include "../Core/Regime/RegimeTypes.mqh"
#include "../Core/Inputs_all.mqh"

class Strategy_BollMR : public IStrategy
{
private:
    ulong  exit_ticket;
    double exit_entry_volume;
    int    exit_stage;

public:
    bool Init()
    {
        // 指标初始化
        if(!InitBollinger(BollMR_BollPeriod, BollMR_BollDev))
            {
                Print("[" + Name() + "] Failed to initialize Bollinger indicator");
                return false;
            }

        if(!InitATR(BollMR_ATRPeriod))
        {
            Print("[" + Name() + "] Failed to initialize ATR indicator");
            return false;
        }

        if(!InitMA(BollMR_MAPeriod))
        {
            Print("[" + Name() + "] Failed to initialize EMA indicator");
            return false;
        }

        Print("[" + Name() + "]  indicators initialized successfully");

        exit_ticket = 0;
        exit_entry_volume = 0.0;
        exit_stage = 0;

        return true;
    }

    // 更新指标数据
    bool UpdateIndicators()
    {          
        // 更新EMA数据，只需要最近的20根K线
        if(!UpdateMA(20))
        {
            Print("[" + Name() + "] Failed to update EMA");
            return false;
        }
        
        // 每个 bar 更新指标缓存（这一步是之前缺失的关键）
        if(!UpdateBollinger())
        {
            Print("[" + Name() + "] Failed to update Bollinger");
            return false;
        }

        if(!UpdateATR(50))   // 取最近 50 根，足够你用 shift 0/1 和平均
        {
            Print("[" + Name() + "] Failed to update ATR");
            return false;
        }
        
        return true;
    }

    Signal GenerateSignal(Signal &signal) override
    {
        bool longSig  = LongSignal(BollMR_EntryMode);
        bool shortSig = ShortSignal(BollMR_EntryMode);
        double exit_volume = 0.0;
        bool exitSig = HasExitSignal(exit_volume);

        if(!PositionSelect(_Symbol)) // 无持仓
        {   
            if(longSig)
            {
                LogSignalDetails("BUY", BollMR_EntryMode);
                FillSignal(signal, SIGNAL_BUY);

                Print("[BollMR] Long signal filled. price=", signal.price,
                    " sl=", signal.sl, " tp=", signal.tp);

                return signal;
            }
            if(shortSig)
            {
                LogSignalDetails("SELL", BollMR_EntryMode);
                FillSignal(signal, SIGNAL_SELL);
                Print("[BollMR] Short signal filled. price=", signal.price,
                    " sl=", signal.sl, " tp=", signal.tp);
                return signal;
            }
        }
        else // 有持仓
        {
            if(exitSig)
            {   
                Print("[BollMR] Exit signal triggered.");
                signal.type = SIGNAL_EXIT;
                signal.exit_volume = exit_volume;
                FillSignal(signal, SIGNAL_EXIT);

                Print("[BollMR] Exit signal filled. price=", signal.price,
                    " sl=", signal.sl, " tp=", signal.tp);

                return signal;
            }
        }

        signal.type = SIGNAL_NONE;
        return signal;
    }

    string Name() override
    {
        return "Bollinger_MeanReversion";
    }

public:
    bool LongSignal(string mode)
    {   
        if(!TimeFilterOK())
            return false;

        if(mode == "A") // 严格确认回归（基准版）
        {
            if(!LongTrendOK())
                return false;
            return (CloseAt(2) < GetBollLower(2) &&
                    CloseAt(1) > GetBollLower(1) && 
                    CloseAt(1) <= GetBollMiddle(1) &&
                    MiddleUpClosed() && 
                    VolatilityOK());
        }
        else if(mode == "B") // 放宽入场条件，允许直接在下轨附近入场（影线回归增强版，更激进，但可能更早捕捉机会）
        {
            if(!LongTrendOK())
                return false;
            bool wick_break = LowAt(2) < GetBollLower(2);   // 影线破下轨

            bool close_recover = CloseAt(1) > GetBollLower(1); // 当前K线收回轨内

            return (
                    wick_break &&
                    close_recover &&
                    CloseAt(1) <= GetBollMiddle(1) &&
                    MiddleUpClosed() &&
                    VolatilityOK());
        }
        else if(mode == "C")
        {
            TrendDirection trend = GetTrendState();

            // 只要不是明确空头，就允许做回归
            if(trend == TREND_BEAR)
                return false;

            return (
                CloseAt(2) < GetBollLower(2) &&
                CloseAt(1) > GetBollLower(1) &&
                CloseAt(1) <= GetBollMiddle(1) &&
                VolatilityOK());
        }
        else
        {
            Print("[BollMR] Invalid entry mode: ", mode);
            return false;
        }
    }

    // M6.3: 趋势状态优先从 RegimeFilter 获取，降级时使用 MA 判断
    TrendDirection GetTrendState()
    {
        // 优先使用 RegimeFilter
        if(m_regime_filter != NULL)
            return m_regime_filter.GetTrendDirection();
        
        // 降级：使用 MA 判断
        double ma_now  = GetMA(0);
        double ma_prev = GetMA(1);

        // 明确多头
        if(ma_now > ma_prev && MiddleUp())
            return TREND_BULL;

        // 明确空头
        if(ma_now < ma_prev && MiddleDown())
            return TREND_BEAR;

        // 其余情况视为震荡
        return TREND_NONE;
    }

    bool ShortSignal(string mode)
    {
        if(!TimeFilterOK())
            return false;

        if(mode == "A") // 严格确认回归（基准版）
        {
            if(!ShortTrendOK())
                return false;
            return (CloseAt(2) > GetBollUpper(2) && // 前2根K线收盘在上轨外
                    CloseAt(1) < GetBollUpper(1) && // 前1根K线收盘回到轨内
                    CloseAt(1) >= GetBollMiddle(1) &&
                    MiddleDownClosed() && 
                    VolatilityOK());
        }
        else if(mode == "B") // 放宽入场条件，允许直接在上轨附近入场（影线回归增强版，更激进，但可能更早捕捉机会）
        {
            bool wick_break = HighAt(2) > GetBollUpper(2);   // 前2根k线影线破上轨

            bool close_recover = CloseAt(1) < GetBollUpper(1); // 前1根K线收回轨内

            return (
                    wick_break &&
                    close_recover &&
                    CloseAt(1) >= GetBollMiddle(1) &&
                    MiddleDownClosed() &&
                    VolatilityOK());
        }
        else if(mode == "C")
        {
            TrendDirection trend = GetTrendState();

            // 只要不是明确多头，就允许做回归
            if(trend == TREND_BULL)
                return false;

            return (
                CloseAt(2) > GetBollUpper(2) && // 前2根K线收盘在上轨外
                CloseAt(1) < GetBollUpper(1) && // 前1根K线收盘回到轨内
                CloseAt(1) >= GetBollMiddle(1) &&
                VolatilityOK()); // 波动率过滤
        }
        else
        {
            Print("[BollMR] Invalid entry mode: ", mode);
            return false;
        }
    }

    void FillSignal(Signal &s, SignalType type)
    {
        s.type       = type;
        s.source     = Name();
        s.time       = TimeCurrent();
        s.price      = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        s.confidence = 1.0;

        if(type == SIGNAL_EXIT)
        {
            return;
        }

        double atr  = GetATR(1);          // 用上一根已收盘 ATR
        double bl1  = GetBollLower(1);    // 上一根下轨
        double bu1  = GetBollUpper(1);    // 上一根上轨
        double mid0 = GetBollMiddle(0);   // 当前中轨（已收盘 bar）

        if(type == SIGNAL_BUY)
        {
            double sl;
            CalcSL(ORDER_TYPE_BUY, s.price, atr, sl);
            if(sl >= s.price)
                {
                    Print("[" + Name() + "] BUY SL invalid logic, skip");
                    return;
                }
            s.sl = sl;
        }
        else if(type == SIGNAL_SELL)
        {
            double sl;
            CalcSL(ORDER_TYPE_SELL, s.price, atr, sl);
            if(sl <= s.price)
                {
                    Print("[" + Name() + "] SELL SL invalid logic, skip");
                    return;
                }
            s.sl = sl;
        }
        else
        {
            s.sl = 0.0;
            s.tp = 0.0;
        }
    }

    double LowAt(int shift) // 取当前 K 线的下影线价格
    {
        return iLow(_Symbol, _Period, shift);
    }

    double HighAt(int shift) // 取当前 K 线的上影线价格
    {
        return iHigh(_Symbol, _Period, shift);
    }
    double CloseAt(int shift) // 取当前 K 线的收盘价
    {
        return iClose(_Symbol, _Period, shift);
    }

    bool MiddleUp() // 中轨向上（当前 K 线的中轨高于上一根 K 线的中轨）
    {
        return GetBollMiddle(0) >= GetBollMiddle(1);
    }

    bool MiddleDown() // 中轨向下（当前 K 线的中轨低于上一根 K 线的中轨）
    {
        return GetBollMiddle(0) <= GetBollMiddle(1);
    }

    bool MiddleUpClosed() // 中轨向上（已收盘K线：1 vs 2）
    {
        return GetBollMiddle(1) >= GetBollMiddle(2);
    }

    bool MiddleDownClosed() // 中轨向下（已收盘K线：1 vs 2）
    {
        return GetBollMiddle(1) <= GetBollMiddle(2); // 已收盘K线：1 vs 2
    }

    bool VolatilityOK() // 波动率过滤：当前 ATR 不超过过去 10 根 ATR 平均的 1.5 倍
    {
        double atr_now = GetATR(1);
        double atr_avg = GetATRMean(10, 1);
        if(atr_avg <= 0) return false;

        if(atr_now > atr_avg * 1.5)
            return false;

        return true;
    }

    bool ConfirmedReentryLong() // 确认回归多头：先出现下轨外 K 线，然后再回到轨内
    {
        return (CloseAt(2) < GetBollLower(2) &&
                CloseAt(1) > GetBollLower(1));
    }

    bool ConfirmedReentryShort() // 确认回归空头：先出现上轨外 K 线，然后再回到轨内
    {
        return (CloseAt(2) > GetBollUpper(2) &&
                CloseAt(1) < GetBollUpper(1));
    }

    void LogSignalDetails(const string direction, const string mode)
    {
        if(!BollMR_LogSignalDetails)
            return;

        int h = 0;
        MqlDateTime ts;
        TimeToStruct(TimeCurrent(), ts);
        h = ts.hour;

        double c2 = CloseAt(2);
        double c1 = CloseAt(1);
        double l2 = LowAt(2);
        double h2 = HighAt(2);
        double bl2 = GetBollLower(2);
        double bl1 = GetBollLower(1);
        double bu2 = GetBollUpper(2);
        double bu1 = GetBollUpper(1);
        double mid2 = GetBollMiddle(2);
        double mid1 = GetBollMiddle(1);
        double atr1 = GetATR(1);

        Print("[BollMR] Signal ", direction,
              " mode=", mode,
              " time_now=", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
              " bar2=", TimeToString(iTime(_Symbol, _Period, 2), TIME_DATE|TIME_SECONDS),
              " bar1=", TimeToString(iTime(_Symbol, _Period, 1), TIME_DATE|TIME_SECONDS),
              " c2=", DoubleToString(c2, _Digits),
              " c1=", DoubleToString(c1, _Digits),
              " l2=", DoubleToString(l2, _Digits),
              " h2=", DoubleToString(h2, _Digits),
              " bl2=", DoubleToString(bl2, _Digits),
              " bl1=", DoubleToString(bl1, _Digits),
              " bu2=", DoubleToString(bu2, _Digits),
              " bu1=", DoubleToString(bu1, _Digits),
              " mid2=", DoubleToString(mid2, _Digits),
              " mid1=", DoubleToString(mid1, _Digits),
              " atr1=", DoubleToString(atr1, _Digits),
              " hour=", IntegerToString(h));
    }

    bool LongTrendOK() // 长期趋势过滤：H1 均线向上且斜率不大（排除明显的单边趋势）
    {
        double ma0  = GetMA(0);
        double ma10 = GetMA(10);

        // Print("[BollMR] LongTrendOK: ma0=", ma0, ", ma10=", ma10);

        if(ma0 == 0 || ma10 == 0)
            return false;

        double diff = ma0 - ma10;
        double slope_abs = MathAbs(diff) / (10.0 * SymbolInfoDouble(_Symbol, SYMBOL_POINT));

        if(diff < 0)          // H1 均线在明显向下 → 不做多
            return false;
        if(slope_abs > BollMR_Slope_Abs)   // 斜率太大 → 强趋势，先不 MR
            return false;

        return true;
    }

    bool ShortTrendOK()
    {      
        double ma0  = GetMA(0);
        double ma10 = GetMA(10);

        if(ma0 == 0 || ma10 == 0)
            return false;

        double diff = ma0 - ma10;
        double slope_abs = MathAbs(diff) / (10.0 * SymbolInfoDouble(_Symbol, SYMBOL_POINT));

        if(diff > 0)          // H1 均线在明显向上 → 不做空
            return false;
        if(BollMR_Slope_Abs)   // 斜率太大 → 强趋势，先不 MR
            return false;

        return true;
    }

    bool TimeFilterOK()
    {
        return BollMR_TimeFilterOK();
    }

    //--------------------------------------------------
    // 计算结构止损价格
    double CalcStructureSL(ENUM_ORDER_TYPE type, double atr)
    {
        if(type == ORDER_TYPE_BUY)
            return GetBollLower(1) - atr * BollMR_StructATRSL;
        else
            return GetBollUpper(1) + atr * BollMR_StructATRSL;
    }

    //--------------------------------------------------
    // 计算波动止损价格
    double CalcVolatilitySL(ENUM_ORDER_TYPE type, double entry, double atr)
    {
        if(type == ORDER_TYPE_BUY)
            return entry - atr * BollMR_VolATRSL;
        else
            return entry + atr * BollMR_VolATRSL;
    }

    //--------------------------------------------------
    // 计算止损价格
    void CalcSL(
        ENUM_ORDER_TYPE type,
        double entry,
        double atr,
        double &sl
    )
    {
    double min_dist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

        double structure_sl = CalcStructureSL(type, atr);
        double vol_sl       = CalcVolatilitySL(type, entry, atr);

        // 均值回归：必须选更宽的
        if(type == ORDER_TYPE_BUY)
            sl = MathMin(structure_sl, vol_sl);
        else
            sl = MathMax(structure_sl, vol_sl);

        // 最小止损距离保护
        if(type == ORDER_TYPE_BUY)
            sl = MathMin(sl, entry - min_dist);
        else
            sl = MathMax(sl, entry + min_dist);

        sl = NormalizeDouble(sl, _Digits);
    }

    //--------------------------------------------------
    // 判断均值回归是否失败（用于辅助风控）
    bool ReversionFailed()
    {
        double atr_now = GetATR(1);
        double atr_avg = GetATRMean(10, 1);

        return atr_now > atr_avg * 1.4;
    }

public:
    bool HasExitSignal(double &exit_volume)
    {
        exit_volume = 0.0;

        if(!PositionSelect(_Symbol)) // 无持仓
        {
            exit_ticket = 0;
            exit_entry_volume = 0.0;
            exit_stage = 0;
            return false;
        }

        ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
        if(ticket != exit_ticket)
        {
            exit_ticket = ticket;
            exit_entry_volume = PositionGetDouble(POSITION_VOLUME);
            exit_stage = 0;
        }
        // 防止刚开仓立刻被平掉
        datetime open_time =
            (datetime)PositionGetInteger(POSITION_TIME);

        if(TimeCurrent() - open_time < BollMR_ShortestClosingTime)
            return false;

        ENUM_POSITION_TYPE type =
                (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

        double middle_ref  = GetBollMiddle(1);                    // 上一根已收盘 K 线中轨（固定阈值）
        double bid_now  = SymbolInfoDouble(_Symbol, SYMBOL_BID); // 最新价
        double bid_prev = iClose(_Symbol, _Period, 1);          // 前一根 K 线收盘价
        double atr = GetATR(1);

        if(type == POSITION_TYPE_BUY)
        {  
            if(!ReversionFailed())
            {
                // 回落保护：用已收盘中轨作为固定阈值，避免当前中轨抖动
                if(bid_prev >= middle_ref && bid_now < middle_ref)
                {
                    return true;
                }

                double level1 = middle_ref + atr * BollMR_MidATRTP;
                double level2 = middle_ref + atr * BollMR_MidATRTP2;

                if(exit_stage == 0 && bid_now >= level1)
                {
                    exit_volume = exit_entry_volume * BollMR_PartialExit1;
                    exit_stage = 1;
                    return true;
                }

                if(exit_stage == 1 && bid_now >= level2)
                {
                    exit_volume = exit_entry_volume * BollMR_PartialExit2;
                    exit_stage = 2;
                    return true;
                }

                if(bid_now >= GetBollUpper(1))
                {
                    exit_stage = 3;
                    return true;
                }
            }
        }

        if(type == POSITION_TYPE_SELL)
        {
            if(!ReversionFailed())
            {
                // 回落保护：用已收盘中轨作为固定阈值，避免当前中轨抖动
                if(bid_prev <= middle_ref && bid_now > middle_ref)
                {
                    return true;
                }

                double level1 = middle_ref - atr * BollMR_MidATRTP;
                double level2 = middle_ref - atr * BollMR_MidATRTP2;

                if(exit_stage == 0 && bid_now <= level1)
                {
                    exit_volume = exit_entry_volume * BollMR_PartialExit1;
                    exit_stage = 1;
                    return true;
                }

                if(exit_stage == 1 && bid_now <= level2)
                {
                    exit_volume = exit_entry_volume * BollMR_PartialExit2;
                    exit_stage = 2;
                    return true;
                }

                if(bid_now <= GetBollLower(1))
                {
                    exit_stage = 3;
                    return true;
                }
            }
        }
        return false;
    }
};

#endif // __STRATEGY_BOLL_MR_ENHANCED_MQH__








