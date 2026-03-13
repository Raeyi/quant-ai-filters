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
    double m_trailing_protect;
    double protect_ATR_multiplier;
    double trailingATR;
    double m_entry_price;       // 持久保存入场价
    double m_sl_on_exit;        // 部分平仓时同步修改止损

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
        m_entry_price = 0.0;
        m_sl_on_exit = 0.0;

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
                signal.sl_on_exit = m_sl_on_exit;  // 传递止损修改请求
                FillSignal(signal, SIGNAL_EXIT);

                Print("[BollMR] Exit signal filled. price=", signal.price,
                    " sl=", signal.sl, " tp=", signal.tp,
                    " sl_on_exit=", DoubleToString(m_sl_on_exit, _Digits));

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
    // 检查 Sub-Type 是否适合布林带回归策略
    // 适合：RN_NORMAL(正常震荡), RL_LOW(低波动), TN_MILD(温和趋势)
    // 不适合：TVB_TREND(强趋势), TVA_EMOTION(情绪脉冲), RVB_FALSE(假突破), RVA_NEWS(消息震荡)
    bool IsSubTypeSuitable()
    {
        if(m_regime_filter == NULL)
            return true;  // 无 RF 时允许通过
            
        RegimeSubType sub_type = m_regime_filter.GetSubType();
        
        switch(sub_type)
        {
            case SUBTYPE_RN_NORMAL:    // 正常震荡 - 最佳
            case SUBTYPE_RL_LOW:       // 低波动 - 谨慎
            case SUBTYPE_RVA_NEWS:     // 消息震荡 - 可以
            case SUBTYPE_RVB_FALSE:    // 假突破密集 - 信号不可靠
                return true;
            case SUBTYPE_TN_MILD:      // 温和趋势 - 可以
            case SUBTYPE_TVB_TREND:    // 强趋势 - 容易逆势
            case SUBTYPE_TVA_EMOTION:  // 情绪脉冲 - 波动剧烈
                return false;
            
            default:
                return true;  // 未知类型允许通过
        }
    }

    void ApplySubTypeParams()
    {
        RegimeSubType sub_type = m_regime_filter.GetSubType();
        
        switch(sub_type)
        {
            case SUBTYPE_RN_NORMAL: 
            case SUBTYPE_RL_LOW:
                protect_ATR_multiplier = 0.6; 
                trailingATR          = 2.5;
                break;
                
            case SUBTYPE_RVA_NEWS: 
                protect_ATR_multiplier = 0.45;
                trailingATR          = 1.8; 
                break;
                
            case SUBTYPE_TN_MILD:
                protect_ATR_multiplier = 0.5;
                trailingATR          = 2.0;
                break;
                
            default:
                protect_ATR_multiplier = 0.5;
                trailingATR          = 2.0;
        }
    }
    
    bool LongSignal(string mode)
    {   
        if(!TimeFilterOK())
            return false;
        
        // Sub-Type 过滤
        if(!IsSubTypeSuitable())
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
            // if(!LongTrendOK())
            //     return false;
            bool wick_break = LowAt(2) < GetBollLower(2);   // 影线破下轨

            bool close_recover = CloseAt(1) > GetBollLower(1); // 当前K线收回轨内

            bool bullish_body = CloseAt(1) > OpenAt(1); 

            bool deep_enough  = CloseAt(1) <= GetBollMiddle(1);

            return (
                    wick_break &&
                    close_recover &&
                    bullish_body &&
                    deep_enough &&
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
                LowAt(2) < GetBollLower(2) &&
                CloseAt(1) > GetBollLower(1) &&
                CloseAt(1) <= GetBollMiddle(1) &&
                MiddleUpClosed() &&
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
        
        // Sub-Type 过滤
        if(!IsSubTypeSuitable())
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
            // if(!ShortTrendOK())
            //     return false;

            bool wick_break = HighAt(2) > GetBollUpper(2);   // 前2根k线影线破上轨

            bool close_recover = CloseAt(1) < GetBollUpper(1); // 前1根K线收回轨内
            
            bool bearish_body = CloseAt(1) < OpenAt(1); 

            bool deep_enough  = CloseAt(1) >= GetBollMiddle(1);

            return (
                    wick_break &&
                    close_recover &&
                    bearish_body &&
                    deep_enough &&
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
                HighAt(2) > GetBollUpper(2) && // 前2根K线收盘在上轨外
                CloseAt(1) < GetBollUpper(1) && // 前1根K线收盘回到轨内
                CloseAt(1) >= GetBollMiddle(1) &&
                MiddleDownClosed() &&
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

    double OpenAt(int shift) // 取当前 K 线的开盘价
    {
        return iOpen(_Symbol, _Period, shift);
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
    ApplySubTypeParams();   // 你的动态参数保持

    exit_volume = 0.0;
    m_sl_on_exit = 0.0;  // 每次重置

    if(!PositionSelect(_Symbol))
    {
        exit_ticket = 0;
        exit_entry_volume = 0.0;
        exit_stage = 0;
        m_trailing_protect = 0.0;
        m_entry_price = 0.0;
        return false;
    }

    ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
    double current_volume = PositionGetDouble(POSITION_VOLUME);  // 当前实际仓位

    if(ticket != exit_ticket)
    {
        exit_ticket = ticket;
        exit_entry_volume = current_volume;
        m_entry_price = PositionGetDouble(POSITION_PRICE_OPEN);  // ← 持久保存入场价
        exit_stage = 0;
        m_trailing_protect = 0.0;
        PrintFormat("[BollMR Exit] 新仓位初始化 | Ticket=%I64u | Entry=%.5f | Vol=%.2f", ticket, m_entry_price, current_volume);
    }
    else
    {
        // 同一仓位，更新实际仓位（部分平仓后会变小）
        exit_entry_volume = current_volume;
    }

    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    double middle_ref = GetBollMiddle(1);
    double bid_now    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double bid_prev   = iClose(_Symbol, _Period, 1);
    double atr        = GetATR(1);

    // ====================== BUY 单 ======================
    if(type == POSITION_TYPE_BUY)
    {
        double level1_low  = middle_ref - atr * BollMR_MidATRTP;   // 中轨下方保本触发点
        double level1_up   = middle_ref + atr * BollMR_MidATRTP;   // 中轨上方部分止盈
        double level2      = middle_ref + atr * BollMR_MidATRTP2;

        // 1. 第一次抵达中轨下方 → 设置保本（真正生效！）
        if(exit_stage == 0 && bid_now >= level1_low)
        {
            double new_protect = m_entry_price - atr * protect_ATR_multiplier; 
            m_trailing_protect = MathMax(m_trailing_protect, new_protect);   // ← 保本保护生效
            exit_volume = exit_entry_volume * BollMR_PartialExit1;
            double current_sl = PositionGetDouble(POSITION_SL);
            m_sl_on_exit = current_sl + atr * 0.3;
            exit_stage = 1;
            PrintFormat("[BollMR buy Exit] BUY 抵达中轨下方 → 部分平仓 %.5f 手 | 平仓价格=%.5f | protect=%.5f | SL %.5f → %.5f (+%.5f) | stage→1", 
                        exit_volume, bid_now, m_trailing_protect, current_sl, m_sl_on_exit, atr * 0.05);
            return true;
        }

        // 2. 保护位检查（从stage=1开始保护，stage=4后不再重复触发）
        if(exit_stage >= 1 && exit_stage < 4 && bid_now < m_trailing_protect)
        {
            exit_volume = exit_entry_volume;
            exit_stage = 4;
            PrintFormat("[BollMR buy Exit] BUY 保护位触发全平 %.5f 手 | 平仓价格=%.5f | protect=%.5f | stage→4", exit_volume, bid_now, m_trailing_protect);
            return true;
        }

        // 3. 动能强 → 部分止盈
        if(exit_stage == 1 && bid_now >= level1_up)
        {
            double new_protect = middle_ref - atr * protect_ATR_multiplier;
            m_trailing_protect = MathMax(m_trailing_protect, new_protect);
            // exit_volume = exit_entry_volume * BollMR_PartialExit1;
            exit_stage = 2;
            PrintFormat("[BollMR buy Exit] BUY level1 部分平仓 %.5f 手 | 平仓价格=%.5f | protect=%.5f | stage→2", exit_volume, bid_now, m_trailing_protect);
            return false;
        }
        if(exit_stage == 2 && bid_now >= level2)
        {
            double new_protect = middle_ref;
            m_trailing_protect = MathMax(m_trailing_protect, new_protect);
            exit_volume = exit_entry_volume * BollMR_PartialExit2;
            exit_stage = 3;
            PrintFormat("[BollMR buy Exit] BUY level2 部分平仓 %.5f 手 | 平仓价格=%.5f | protect=%.5f | stage→3", exit_volume, bid_now, m_trailing_protect);
            return true;
        }

        // 4. 上轨突破 → 追踪止损（吃肉）
        if(bid_now >= GetBollUpper(0) && exit_stage < 5)
        {
            double new_protect = bid_now - atr * trailingATR;
            m_trailing_protect = MathMax(m_trailing_protect, new_protect);
            exit_volume = exit_entry_volume;
            exit_stage = 5;
            PrintFormat("[BollMR buy Exit] BUY 上轨突破！追踪模式部分平仓 %.5f 手 | 平仓价格=%.5f | protect=%.5f | stage→5", exit_volume, bid_now, m_trailing_protect);
            return true;
        }

        if(exit_stage == 5)
        {
            double new_protect = bid_now - atr * trailingATR;
            if(new_protect > m_trailing_protect + atr * BollMR_TrailingStep)
                m_trailing_protect = new_protect;

            if(bid_now <= m_trailing_protect)
            {
                exit_volume = exit_entry_volume;
                exit_stage = 4;
                PrintFormat("[BollMR buy Exit] BUY 追踪止损全平 %.5f 手 | 平仓价格=%.5f", exit_volume, bid_now);
                return true;
            }
            return false;
        }
    }

    // ====================== SELL 单（完全对称） ======================
    if(type == POSITION_TYPE_SELL)
    {
        double level1_high = middle_ref + atr * BollMR_MidATRTP;   // 中轨上方保本触发点
        double level1_down = middle_ref - atr * BollMR_MidATRTP;   // 中轨下方部分止盈
        double level2      = middle_ref - atr * BollMR_MidATRTP2;

        if(exit_stage == 0 && bid_now <= level1_high)
        {
           double new_protect = m_entry_price + atr * protect_ATR_multiplier; 
           if(m_trailing_protect == 0.0)
                m_trailing_protect = new_protect;
            else
                m_trailing_protect = MathMin(m_trailing_protect, new_protect);
            exit_volume = exit_entry_volume * BollMR_PartialExit1;
            double current_sl = PositionGetDouble(POSITION_SL);
            m_sl_on_exit = current_sl - atr * 0.3;
            exit_stage = 1;
            PrintFormat("[BollMR sell Exit] SELL 抵达中轨上方 → 部分平仓 %.5f 手 | 平仓价格=%.5f | protect=%.5f | SL %.5f → %.5f (-%.5f) | stage→1", 
                        exit_volume, bid_now, m_trailing_protect, current_sl, m_sl_on_exit, atr * 0.05);
            return true;
        }


        // 保护位检查（stage=4后不再重复触发）
        if(exit_stage >= 1 && exit_stage < 4 && bid_now > m_trailing_protect)
        {
            exit_volume = exit_entry_volume;
            exit_stage = 4;
            PrintFormat("[BollMR sell Exit] SELL 保护位触发全平 %.5f 手 | 平仓价格=%.5f | protect=%.5f", exit_volume, bid_now, m_trailing_protect);
            return true;
        }

        if(exit_stage == 1 && bid_now <= level1_down)
        {
            double new_protect = middle_ref + atr * protect_ATR_multiplier;
            m_trailing_protect = MathMin(m_trailing_protect, new_protect);
            // exit_volume = exit_entry_volume * BollMR_PartialExit1;
            exit_stage = 2;
            PrintFormat("[BollMR sell Exit] SELL level1 部分平仓 %.5f 手 | 平仓价格=%.5f | protect=%.5f | stage→2", exit_volume, bid_now, m_trailing_protect);
            return false;
        }
        if(exit_stage == 2 && bid_now <= level2)
        {
            double new_protect = middle_ref;
            m_trailing_protect = MathMin(m_trailing_protect, new_protect);
            exit_volume = exit_entry_volume * BollMR_PartialExit2;
            exit_stage = 3;
            PrintFormat("[BollMR sell Exit] SELL level2 部分平仓 %.5f 手 | 平仓价格=%.5f | protect=%.5f | stage→3", exit_volume, bid_now, m_trailing_protect);
            return true;
        }

        if(bid_now <= GetBollLower(0) && exit_stage < 5)
        {
            double new_protect = bid_now + atr * trailingATR;
            m_trailing_protect = MathMin(m_trailing_protect, new_protect);
            exit_volume = exit_entry_volume;
            exit_stage = 5;
            PrintFormat("[BollMR sell Exit] SELL 下轨突破！追踪模式部分平仓 %.5f 手 | 平仓价格=%.5f | protect=%.5f | stage→5", exit_volume, bid_now, m_trailing_protect);
            return false;
        }

        if(exit_stage == 5)
        {
            double new_protect = bid_now + atr * trailingATR;
            if(new_protect < m_trailing_protect - atr * BollMR_TrailingStep)
                m_trailing_protect = new_protect;

            if(bid_now >= m_trailing_protect)
            {
                exit_volume = exit_entry_volume;
                exit_stage = 4;
                PrintFormat("[BollMR sell Exit] SELL 追踪止损全平 %.5f 手 | 平仓价格=%.5f", exit_volume, bid_now);
                return true;
            }
            return false;
        }
    }

    // ====================== 极端高波动保护 ======================
    if(ReversionFailed() && exit_stage >= 1)
    {
        if(GetATR(1) > GetATRMean(10, 1) * 2.0)
        {
            exit_volume = exit_entry_volume;
            exit_stage = 4;
            PrintFormat("[BollMR Exit] 极端ATR爆炸全平 %.5f 手 | ATR倍数=%.2f", exit_volume, GetATR(1)/GetATRMean(10,1));
            return true;
        }
    }

    return false;
}
};

#endif // __STRATEGY_BOLL_MR_ENHANCED_MQH__








