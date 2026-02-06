#ifndef __STRATEGY_BOLL_MR_MQH__
#define __STRATEGY_BOLL_MR_MQH__

#include "../Indicators/Bollinger.mqh"
#include "../Indicators/ATR.mqh"
#include "../Indicators/MA.mqh"
#include "../Core/Strategy.mqh"

// 交易时间过滤参数(美盘不参与交易)
input int boll_Allowed_transaction_start_time = 2;  // 交易开始时间（小时）
input int boll_Allowed_transaction_end_time   = 20; // 交易结束时间（小时）

input int    BollPeriod       = 20;   // 布林带周期
input double BollDev          = 2.0;  // 布林带标准差
input int    ATRPeriod        = 14;   // ATR 周期
input int ShortestClosingTime = 10; // 最短持仓时间，防止刚开仓立刻被平掉（秒）
input double    StructATRSL        = 0.8;   // 结构止损 ATR 倍数
input double    VolATRSL          = 2.0;  // 波动止损 ATR
input double    BoolMidATRTP         = 0.2;  // 均值回归止盈 ATR 倍数
input double    BoolUplowATRTP         = 0.1;  //  上轨/下轨止盈 ATR 倍数
input int    MAPeriod = 50;              // MA周期
input string boll_entry_mode = "A"; // 入场模式：A / B / C

class Strategy_BollMR : public IStrategy
{
public:
    bool Init()
    {
        // 指标初始化
        if(!InitBollinger(BollPeriod, BollDev))
            {
                Print("[" + Name() + "] Failed to initialize Bollinger indicator");
                return false;
            }

        if(!InitATR(ATRPeriod))
        {
            Print("[" + Name() + "] Failed to initialize ATR indicator");
            return false;
        }

        if(!InitMA(MAPeriod))
        {
            Print("[" + Name() + "] Failed to initialize EMA indicator");
            return false;
        }
        
        Print("[" + Name() + "]  indicators initialized successfully");

        return true;
    }
    
    enum ENUM_TREND_STATE
                {
                    TREND_BULL,      // 明确多头
                    TREND_FLAT,      // 震荡 / 弱多
                    TREND_BEAR       // 空头
                };

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
        bool longSig  = LongSignal(boll_entry_mode);
        bool shortSig = ShortSignal(boll_entry_mode);
        bool exitSig = HasExitSignal();

        if(!PositionSelect(_Symbol)) // 无持仓
        {   
            if(longSig)
            {
                FillSignal(signal, SIGNAL_BUY);

                Print("[BollMR] Long signal filled. price=", signal.price,
                    " sl=", signal.sl, " tp=", signal.tp);

                return signal;
            }
            if(shortSig)
            {
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
            return (CloseAt(1) < GetBollLower(1) &&
                    CloseAt(0) > GetBollLower(0) && 
                    MiddleUp() && 
                    VolatilityOK());
        }
        else if(mode == "B") // 放宽入场条件，允许直接在下轨附近入场（影线回归增强版，更激进，但可能更早捕捉机会）
        {
            if(!LongTrendOK())
                return false;
            bool wick_break = LowAt(1) < GetBollLower(1);   // 影线破下轨

            bool close_recover = CloseAt(0) > GetBollLower(0); // 当前K线收回轨内

            return (
                    wick_break &&
                    close_recover &&
                    MiddleUp() &&
                    VolatilityOK());
        }
        else if(mode == "C")
        {
            ENUM_TREND_STATE trend = GetTrendState();

            // 只要不是明确空头，就允许做回归
            if(trend == TREND_BEAR)
                return false;

            return (
                CloseAt(1) < GetBollLower(1) &&
                CloseAt(0) > GetBollLower(0) &&
                VolatilityOK());
        }
        else
        {
            Print("[BollMR] Invalid entry mode: ", mode);
            return false;
        }
    }

    ENUM_TREND_STATE GetTrendState()
    {
        double ma_now  = GetMA(0);
        double ma_prev = GetMA(1);

        // 明确多头
        if(ma_now > ma_prev && MiddleUp())
            return TREND_BULL;

        // 明确空头
        if(ma_now < ma_prev && MiddleDown())
            return TREND_BEAR;

        // 其余情况视为震荡
        return TREND_FLAT;
    }

    bool ShortSignal(string mode)
    {
        if(!TimeFilterOK())
            return false;

        if(mode == "A") // 严格确认回归（基准版）
        {
            if(!ShortTrendOK())
                return false;
            return (CloseAt(1) > GetBollUpper(1) &&
                    CloseAt(0) < GetBollUpper(0) && 
                    MiddleDown() && 
                    VolatilityOK());
        }
        else if(mode == "B") // 放宽入场条件，允许直接在上轨附近入场（影线回归增强版，更激进，但可能更早捕捉机会）
        {
            bool wick_break = HighAt(1) > GetBollUpper(1);   // 影线破上轨

            bool close_recover = CloseAt(0) < GetBollUpper(0); // 当前K线收回轨内

            return (
                    wick_break &&
                    close_recover &&
                    MiddleDown() &&
                    VolatilityOK());
        }
        else if(mode == "C")
        {
            ENUM_TREND_STATE trend = GetTrendState();

            // 只要不是明确多头，就允许做回归
            if(trend == TREND_BULL)
                return false;

            return (
                CloseAt(1) > GetBollUpper(1) &&
                CloseAt(0) < GetBollUpper(0) &&
                VolatilityOK());
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
        return (CloseAt(1) < GetBollLower(1) &&
                CloseAt(0) > GetBollLower(0));
    }

    bool ConfirmedReentryShort() // 确认回归空头：先出现上轨外 K 线，然后再回到轨内
    {
        return (CloseAt(1) > GetBollUpper(1) &&
                CloseAt(0) < GetBollUpper(0));
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
        if(slope_abs > 100)   // 斜率太大 → 强趋势，先不 MR
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
        if(slope_abs > 100)   // 斜率太大 → 强趋势，先不 MR
            return false;

        return true;
    }

    bool TimeFilterOK()
    {
        datetime currentTime = TimeCurrent();
        MqlDateTime timeStruct;
        TimeToStruct(currentTime, timeStruct);
        int hour = timeStruct.hour;
        // Print("[BollMR] Current server hour (UTC+?): ", hour); // 更新注释提醒
        // 处理通常情况 (例如 8:00 - 22:00)
        if(boll_Allowed_transaction_start_time <= boll_Allowed_transaction_end_time)
        {
            // 时段在同一天内
            if(hour < boll_Allowed_transaction_start_time || hour >= boll_Allowed_transaction_end_time)
                return false;
        }
        else
        {
            // 时段跨午夜 (例如 22:00 - 次日 4:00)
            // 此时，如果 hour 小于开始时间 且 大于等于结束时间，才返回 false
            if(hour < boll_Allowed_transaction_start_time && hour >= boll_Allowed_transaction_end_time)
                return false;
        }
        // Print("[BollMR] Time filter passed. Current hour: ", hour);
        return true;
    }

    //--------------------------------------------------
    // 计算结构止损价格
    double CalcStructureSL(ENUM_ORDER_TYPE type, double atr)
    {
        if(type == ORDER_TYPE_BUY)
            return GetBollLower(1) - atr * StructATRSL;
        else
            return GetBollUpper(1) + atr * StructATRSL;
    }

    //--------------------------------------------------
    // 计算波动止损价格
    double CalcVolatilitySL(ENUM_ORDER_TYPE type, double entry, double atr)
    {
        if(type == ORDER_TYPE_BUY)
            return entry - atr * VolATRSL;
        else
            return entry + atr * VolATRSL;
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
    bool HasExitSignal()
    {
        if(!PositionSelect(_Symbol)) // 无持仓
            return false;

        // 防止刚开仓立刻被平掉
        datetime open_time =
            (datetime)PositionGetInteger(POSITION_TIME);

        if(TimeCurrent() - open_time < ShortestClosingTime)
            return false;

        ENUM_POSITION_TYPE type =
                (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

        double middle_now  = GetBollMiddle(0);                     //  当前 K 线的中轨
        double middle_prev = GetBollMiddle(1);                    // 上一根 K 线的中轨
        double bid_now  = SymbolInfoDouble(_Symbol, SYMBOL_BID); // 最新价
        double bid_prev = iClose(_Symbol, _Period, 1);          // 前一根 K 线收盘价
        if(type == POSITION_TYPE_BUY)
        {  
            // 从下往上穿越中轨
            if(!ReversionFailed())
            {
                if(bid_prev < middle_prev && bid_now >= middle_now &&
                        fabs(bid_now - middle_now) < GetATR(1) * BoolMidATRTP)
                {
                    Print("Checking Buy exit: bid_prev=", DoubleToString(bid_prev, _Digits),
                    ", bid_now=", DoubleToString(bid_now, _Digits),
                    ", middle_prev=", DoubleToString(middle_prev, _Digits),
                    ", middle_now=", DoubleToString(middle_now, _Digits));
                    return true;
                }
                else
                {
                    if(bid_now >= GetBollUpper(1) - GetATR(1) * BoolUplowATRTP)
                    {
                        return true;
                    }
                }
            }
            
        }

        if(type == POSITION_TYPE_SELL)
        {
            // 从上往下穿越中轨
            if(!ReversionFailed())
            {
                if(bid_prev > middle_prev && bid_now <= middle_now &&
                        fabs(bid_now - middle_now) < GetATR(1) * BoolMidATRTP)
                {
                    Print("Checking Sell exit: bid_prev=", DoubleToString(bid_prev, _Digits),
                    ", bid_now=", DoubleToString(bid_now, _Digits),
                    ", middle_prev=", DoubleToString(middle_prev, _Digits),
                    ", middle_now=", DoubleToString(middle_now, _Digits));
                    return true;
                }
                else
                {
                    if(bid_now <= GetBollLower(1) + GetATR(1) * BoolUplowATRTP)
                    {
                        return true;
                    }
                }
            }
        }
        return false;
    }
    };

#endif // __STRATEGY_BOLL_MR_MQH__
