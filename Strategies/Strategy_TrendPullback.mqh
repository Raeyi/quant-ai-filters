//+------------------------------------------------------------------+
//|              Strategies/Strategy_TrendPullback.mqh               |
//|                Trend Pullback Strategy (M2)                      |
//|     大趋势 + 小级别回撤吃第二段                                    |
//+------------------------------------------------------------------+

#ifndef __STRATEGY_TREND_PULLBACK_MQH__
#define __STRATEGY_TREND_PULLBACK_MQH__

#include "../Core/Strategy.mqh"
#include "../Indicators/ATR.mqh"
#include "../Indicators/MA.mqh"

//+------------------------------------------------------------------+
//| 输入参数                                                          |
//+------------------------------------------------------------------+
input group "TrendPullback.HTF"
input int   TP_EMA50_Period     = 50;      // M15 EMA50 周期
input int   TP_EMA200_Period    = 200;     // M15 EMA200 周期
input bool  TP_UseVWAP_HTF      = true;    // M15 使用 VWAP 辅助判断

input group "TrendPullback.LTF"
input int   TP_EMA20_Period     = 20;      // M5 EMA20 周期
input bool  TP_UseVWAP_LTF      = true;    // M5 使用 VWAP 作为价值区
input double TP_ValueZoneATR    = 0.3;     // 价值区容差 (ATR倍数)
input int   TP_PullbackBars     = 5;       // 回撤确认K线数

input group "TrendPullback.Structure"
input int   TP_Structure_Lookback = 20;    // 结构回看周期
input bool  TP_RequireBreak     = true;    // 要求突破前高/前低

input group "TrendPullback.Risk"
input int   TP_ATR_Period       = 14;      // ATR 周期
input double TP_ATR_SL_Multi    = 1.0;     // 止损 ATR 倍数
input double TP_ATR_TP_Multi    = 1.5;     // 止盈 ATR 倍数

input group "TrendPullback.Timeframe"
input ENUM_TIMEFRAMES TP_HTF    = PERIOD_M15;  // 高时间框架(方向)
input ENUM_TIMEFRAMES TP_LTF    = PERIOD_M5;   // 低时间框架(入场)

//+------------------------------------------------------------------+
//| 趋势状态枚举                                                       |
//+------------------------------------------------------------------+
enum TrendState
{
    TREND_FLAT  = 0,    // 震荡
    TREND_BULL  = 1,    // 上涨趋势
    TREND_BEAR  = -1    // 下跌趋势
};

//+------------------------------------------------------------------+
//| TrendPullback 策略类                                              |
//+------------------------------------------------------------------+
class Strategy_TrendPullback : public IStrategy
{
private:
    // M15 指标句柄
    int m_handle_ema50_htf;    // M15 EMA50
    int m_handle_ema200_htf;   // M15 EMA200
    
    // M5 指标句柄
    int m_handle_ema20_ltf;    // M5 EMA20
    int m_handle_atr;          // ATR
    
    // 缓冲区
    double m_buf_ema50_htf[];
    double m_buf_ema200_htf[];
    double m_buf_ema20_ltf[];
    double m_buf_atr[];
    
    // K线数据
    double m_buf_high[];
    double m_buf_low[];
    double m_buf_close[];
    double m_buf_open[];
    long m_buf_volume[];
    
    // 状态
    TrendState m_trend_state;
    bool m_initialized;
    
    // 结构数据
    double m_recent_high;
    double m_recent_low;
    double m_prev_high;        // 前一根K线高点
    double m_prev_low;         // 前一根K线低点
    
    // VWAP 计算
    double m_vwap_ltf;         // M5 VWAP
    double m_vwap_htf;         // M15 VWAP

public:
    //+--------------------------------------------------------------
    //| 构造函数
    //+--------------------------------------------------------------
    Strategy_TrendPullback() : 
        m_handle_ema50_htf(INVALID_HANDLE),
        m_handle_ema200_htf(INVALID_HANDLE),
        m_handle_ema20_ltf(INVALID_HANDLE),
        m_handle_atr(INVALID_HANDLE),
        m_trend_state(TREND_FLAT),
        m_initialized(false),
        m_recent_high(0.0),
        m_recent_low(0.0),
        m_prev_high(0.0),
        m_prev_low(0.0),
        m_vwap_ltf(0.0),
        m_vwap_htf(0.0)
    {
        ArraySetAsSeries(m_buf_ema50_htf, true);
        ArraySetAsSeries(m_buf_ema200_htf, true);
        ArraySetAsSeries(m_buf_ema20_ltf, true);
        ArraySetAsSeries(m_buf_atr, true);
        ArraySetAsSeries(m_buf_high, true);
        ArraySetAsSeries(m_buf_low, true);
        ArraySetAsSeries(m_buf_close, true);
        ArraySetAsSeries(m_buf_open, true);
        ArraySetAsSeries(m_buf_volume, true);
    }
    
    //+--------------------------------------------------------------
    //| 析构函数
    //+--------------------------------------------------------------
    ~Strategy_TrendPullback()
    {
        if(m_handle_ema50_htf != INVALID_HANDLE)  IndicatorRelease(m_handle_ema50_htf);
        if(m_handle_ema200_htf != INVALID_HANDLE) IndicatorRelease(m_handle_ema200_htf);
        if(m_handle_ema20_ltf != INVALID_HANDLE)  IndicatorRelease(m_handle_ema20_ltf);
        if(m_handle_atr != INVALID_HANDLE)        IndicatorRelease(m_handle_atr);
    }
    
    //+--------------------------------------------------------------
    //| 初始化指标
    //+--------------------------------------------------------------
    bool Init()
    {
        // M15 EMA50
        m_handle_ema50_htf = iMA(_Symbol, TP_HTF, TP_EMA50_Period, 0, MODE_EMA, PRICE_CLOSE);
        if(m_handle_ema50_htf == INVALID_HANDLE)
        {
            Print("[", Name(), "] Failed to create M15 EMA50 handle");
            return false;
        }
        
        // M15 EMA200
        m_handle_ema200_htf = iMA(_Symbol, TP_HTF, TP_EMA200_Period, 0, MODE_EMA, PRICE_CLOSE);
        if(m_handle_ema200_htf == INVALID_HANDLE)
        {
            Print("[", Name(), "] Failed to create M15 EMA200 handle");
            return false;
        }
        
        // M5 EMA20
        m_handle_ema20_ltf = iMA(_Symbol, TP_LTF, TP_EMA20_Period, 0, MODE_EMA, PRICE_CLOSE);
        if(m_handle_ema20_ltf == INVALID_HANDLE)
        {
            Print("[", Name(), "] Failed to create M5 EMA20 handle");
            return false;
        }
        
        // ATR (使用当前周期)
        m_handle_atr = iATR(_Symbol, _Period, TP_ATR_Period);
        if(m_handle_atr == INVALID_HANDLE)
        {
            Print("[", Name(), "] Failed to create ATR handle");
            return false;
        }
        
        m_initialized = true;
        Print("[", Name(), "] Indicators initialized. HTF=", EnumToString(TP_HTF), 
              " LTF=", EnumToString(TP_LTF));
        return true;
    }
    
    //+--------------------------------------------------------------
    //| 更新指标数据
    //+--------------------------------------------------------------
    bool UpdateIndicators()
    {
        if(!m_initialized) return false;
        
        int bars_needed = TP_Structure_Lookback + 5;
        
        // 更新 M15 EMA
        if(CopyBuffer(m_handle_ema50_htf, 0, 0, bars_needed, m_buf_ema50_htf) <= 0)
        {
            Print("[", Name(), "] Failed to copy EMA50 HTF");
            return false;
        }
        
        if(CopyBuffer(m_handle_ema200_htf, 0, 0, bars_needed, m_buf_ema200_htf) <= 0)
        {
            Print("[", Name(), "] Failed to copy EMA200 HTF");
            return false;
        }
        
        // 更新 M5 EMA
        if(CopyBuffer(m_handle_ema20_ltf, 0, 0, bars_needed, m_buf_ema20_ltf) <= 0)
        {
            Print("[", Name(), "] Failed to copy EMA20 LTF");
            return false;
        }
        
        // 更新 ATR
        if(CopyBuffer(m_handle_atr, 0, 0, bars_needed, m_buf_atr) <= 0)
        {
            Print("[", Name(), "] Failed to copy ATR");
            return false;
        }
        
        // 更新 K 线数据
        if(CopyHigh(_Symbol, _Period, 0, bars_needed, m_buf_high) <= 0) return false;
        if(CopyLow(_Symbol, _Period, 0, bars_needed, m_buf_low) <= 0) return false;
        if(CopyClose(_Symbol, _Period, 0, bars_needed, m_buf_close) <= 0) return false;
        if(CopyOpen(_Symbol, _Period, 0, bars_needed, m_buf_open) <= 0) return false;
        if(CopyRealVolume(_Symbol, _Period, 0, bars_needed, m_buf_volume) <= 0) return false;
        
        // 更新趋势状态
        UpdateTrendState();
        
        // 更新结构高低点
        UpdateStructure();
        
        // 更新 VWAP
        UpdateVWAP();
        
        return true;
    }
    
    //+--------------------------------------------------------------
    //| 更新趋势状态 (M15 EMA50/EMA200)
    //+--------------------------------------------------------------
    void UpdateTrendState()
    {
        if(ArraySize(m_buf_ema50_htf) < 2 || ArraySize(m_buf_ema200_htf) < 2)
        {
            m_trend_state = TREND_FLAT;
            return;
        }
        
        double ema50_0 = m_buf_ema50_htf[0];
        double ema200_0 = m_buf_ema200_htf[0];
        
        // 趋势判断: EMA50 与 EMA200 关系
        if(ema50_0 > ema200_0)
        {
            m_trend_state = TREND_BULL;
        }
        else if(ema50_0 < ema200_0)
        {
            m_trend_state = TREND_BEAR;
        }
        else
        {
            m_trend_state = TREND_FLAT;
        }
        
        // VWAP 辅助确认 (可选)
        if(TP_UseVWAP_HTF && m_vwap_htf > 0)
        {
            double price = m_buf_close[0];
            // 多头：价格应在 VWAP 上方
            if(m_trend_state == TREND_BULL && price < m_vwap_htf)
            {
                // 价格在 VWAP 下方，趋势减弱
                m_trend_state = TREND_FLAT;
            }
            // 空头：价格应在 VWAP 下方
            if(m_trend_state == TREND_BEAR && price > m_vwap_htf)
            {
                m_trend_state = TREND_FLAT;
            }
        }
    }
    
    //+--------------------------------------------------------------
    //| 更新结构高低点
    //+--------------------------------------------------------------
    void UpdateStructure()
    {
        if(ArraySize(m_buf_high) < TP_Structure_Lookback) return;
        
        // 前一根 K 线的高低点
        m_prev_high = m_buf_high[1];
        m_prev_low = m_buf_low[1];
        
        // 最近结构高低点 (排除当前K线)
        double highs[], lows[];
        ArrayCopy(highs, m_buf_high, 0, 1, TP_Structure_Lookback);
        ArrayCopy(lows, m_buf_low, 0, 1, TP_Structure_Lookback);
        
        m_recent_high = highs[ArrayMaximum(highs)];
        m_recent_low = lows[ArrayMinimum(lows)];
    }
    
    //+--------------------------------------------------------------
    //| 计算 VWAP (简化版，基于当日数据)
    //+--------------------------------------------------------------
    void UpdateVWAP()
    {
        // M5 VWAP (最近20根)
        double sum_vp = 0.0;
        double sum_v = 0.0;
        int vwap_bars = MathMin(20, ArraySize(m_buf_close) - 1);
        
        for(int i = 1; i <= vwap_bars; i++)
        {
            double typical = (m_buf_high[i] + m_buf_low[i] + m_buf_close[i]) / 3.0;
            double vol = m_buf_volume[i];
            sum_vp += typical * vol;
            sum_v += vol;
        }
        
        m_vwap_ltf = (sum_v > 0) ? sum_vp / sum_v : 0.0;
        
        // M15 VWAP (使用 M15 数据计算)
        double h_htf[], l_htf[], c_htf[];
        long v_htf[];
        ArraySetAsSeries(h_htf, true);
        ArraySetAsSeries(l_htf, true);
        ArraySetAsSeries(c_htf, true);
        ArraySetAsSeries(v_htf, true);
        
        if(CopyHigh(_Symbol, TP_HTF, 0, 20, h_htf) > 0 &&
           CopyLow(_Symbol, TP_HTF, 0, 20, l_htf) > 0 &&
           CopyClose(_Symbol, TP_HTF, 0, 20, c_htf) > 0 &&
           CopyRealVolume(_Symbol, TP_HTF, 0, 20, v_htf) > 0)
        {
            sum_vp = 0.0;
            sum_v = 0.0;
            for(int i = 1; i <= MathMin(20, ArraySize(c_htf) - 1); i++)
            {
                double typical = (h_htf[i] + l_htf[i] + c_htf[i]) / 3.0;
                double vol = v_htf[i];
                sum_vp += typical * vol;
                sum_v += vol;
            }
            m_vwap_htf = (sum_v > 0) ? sum_vp / sum_v : 0.0;
        }
    }
    
    //+--------------------------------------------------------------
    //| 获取趋势状态
    //+--------------------------------------------------------------
    TrendState GetTrendState() const { return m_trend_state; }
    
    //+--------------------------------------------------------------
    //| 判断是否在价值区 (EMA20 或 VWAP 附近)
    //+--------------------------------------------------------------
    bool IsInValueZone(double price, double atr, bool forLong)
    {
        double ema20 = m_buf_ema20_ltf[1];
        double tolerance = atr * TP_ValueZoneATR;
        
        // EMA20 价值区
        bool near_ema20 = MathAbs(price - ema20) <= tolerance;
        
        // VWAP 价值区
        bool near_vwap = false;
        if(TP_UseVWAP_LTF && m_vwap_ltf > 0)
        {
            near_vwap = MathAbs(price - m_vwap_ltf) <= tolerance;
        }
        
        // 价值区判断
        if(forLong)
        {
            // 多头：价格回撤到 EMA20 或 VWAP 附近
            return (price <= ema20 + tolerance) && (near_ema20 || near_vwap);
        }
        else
        {
            // 空头：价格反弹到 EMA20 或 VWAP 附近
            return (price >= ema20 - tolerance) && (near_ema20 || near_vwap);
        }
    }
    
    //+--------------------------------------------------------------
    //| 回撤结束确认 (K线形态)
    //| 多头: 小实体 + 阳线反包
    //| 空头: 小实体 + 阴线反包
    //+--------------------------------------------------------------
    bool IsPullbackEnded(bool forLong)
    {
        if(ArraySize(m_buf_close) < 5) return false;
        
        double open1 = m_buf_open[1];
        double close1 = m_buf_close[1];
        double high1 = m_buf_high[1];
        double low1 = m_buf_low[1];
        
        double open2 = m_buf_open[2];
        double close2 = m_buf_close[2];
        double high2 = m_buf_high[2];
        double low2 = m_buf_low[2];
        
        double body1 = MathAbs(close1 - open1);
        double body2 = MathAbs(close2 - open2);
        double range1 = high1 - low1;
        
        if(range1 <= 0) return false;
        
        // 计算平均实体大小 (最近5根)
        double avg_body = 0.0;
        for(int i = 1; i <= 5; i++)
            avg_body += MathAbs(m_buf_close[i] - m_buf_open[i]);
        avg_body /= 5.0;
        
        if(forLong)
        {
            // 多头止跌结构:
            // 1. 小实体：实体 < 平均实体的一半
            bool small_body = body1 < avg_body * 0.5;
            
            // 2. 阳线反包：当前阳线完全包含前一根K线
            bool bullish_engulf = (close1 > open1) &&  // 当前是阳线
                                  (open1 <= low2) &&   // 开盘低于前一根低点
                                  (close1 >= high2);   // 收盘高于前一根高点
            
            // 3. 下影线确认
            double lower_wick = MathMin(open1, close1) - low1;
            bool hammer_like = lower_wick > body1 * 1.5;
            
            return small_body || bullish_engulf || hammer_like;
        }
        else
        {
            // 空头止涨结构:
            // 1. 小实体：实体 < 平均实体的一半
            bool small_body = body1 < avg_body * 0.5;
            
            // 2. 阴线反包：当前阴线完全包含前一根K线
            bool bearish_engulf = (close1 < open1) &&  // 当前是阴线
                                  (open1 >= high2) &&   // 开盘高于前一根高点
                                  (close1 <= low2);     // 收盘低于前一根低点
            
            // 3. 上影线确认
            double upper_wick = high1 - MathMax(open1, close1);
            bool shooting_star = upper_wick > body1 * 1.5;
            
            return small_body || bearish_engulf || shooting_star;
        }
    }
    
    //+--------------------------------------------------------------
    //| 小结构突破确认
    //| 多头: 突破前一根高点
    //| 空头: 突破前一根低点
    //+--------------------------------------------------------------
    bool IsStructureBreak(bool forLong)
    {
        if(!TP_RequireBreak) return true;
        
        double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        
        if(forLong)
        {
            // 多头：当前价格突破前一根高点
            return bid > m_prev_high;
        }
        else
        {
            // 空头：当前价格跌破前一根低点
            return bid < m_prev_low;
        }
    }
    
    //+--------------------------------------------------------------
    //| 多头入场信号
    //+--------------------------------------------------------------
    bool LongSignal()
    {
        // 1. M15 上涨趋势
        if(m_trend_state != TREND_BULL)
            return false;
        
        // 2. ATR 有效
        if(ArraySize(m_buf_atr) < 2 || m_buf_atr[1] <= 0)
            return false;
        
        double atr = m_buf_atr[1];
        double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        
        // 3. 价格回撤到价值区 (EMA20/VWAP)
        if(!IsInValueZone(bid, atr, true))
            return false;
        
        // 4. 回撤结束确认 (K线形态)
        if(!IsPullbackEnded(true))
            return false;
        
        // 5. 小结构突破确认
        if(!IsStructureBreak(true))
            return false;
        
        return true;
    }
    
    //+--------------------------------------------------------------
    //| 空头入场信号
    //+--------------------------------------------------------------
    bool ShortSignal()
    {
        // 1. M15 下跌趋势
        if(m_trend_state != TREND_BEAR)
            return false;
        
        // 2. ATR 有效
        if(ArraySize(m_buf_atr) < 2 || m_buf_atr[1] <= 0)
            return false;
        
        double atr = m_buf_atr[1];
        double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        
        // 3. 价格反弹到价值区 (EMA20/VWAP)
        if(!IsInValueZone(bid, atr, false))
            return false;
        
        // 4. 回撤结束确认 (K线形态)
        if(!IsPullbackEnded(false))
            return false;
        
        // 5. 小结构突破确认
        if(!IsStructureBreak(false))
            return false;
        
        return true;
    }
    
    //+--------------------------------------------------------------
    //| 出场信号
    //| 1. 趋势反转: M15 EMA50/200 反转
    //| 2. 结构破坏: 跌破/突破关键结构
    //+--------------------------------------------------------------
    bool HasExitSignal()
    {
        if(!PositionSelect(_Symbol))
            return false;
        
        ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        
        if(type == POSITION_TYPE_BUY)
        {
            // 多头出场:
            // 1. 趋势反转 (M15 转为空头)
            if(m_trend_state == TREND_BEAR)
                return true;
            
            // 2. 结构破坏 (跌破最近低点)
            if(bid < m_recent_low)
                return true;
        }
        else if(type == POSITION_TYPE_SELL)
        {
            // 空头出场:
            // 1. 趋势反转 (M15 转为多头)
            if(m_trend_state == TREND_BULL)
                return true;
            
            // 2. 结构破坏 (突破最近高点)
            if(bid > m_recent_high)
                return true;
        }
        
        return false;
    }
    
    //+--------------------------------------------------------------
    //| 填充信号
    //+--------------------------------------------------------------
    void FillSignal(Signal &s, SignalType type)
    {
        s.type = type;
        s.source = Name();
        s.time = TimeCurrent();
        s.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        s.confidence = 1.0;
        s.tp = 0.0;
        
        if(type == SIGNAL_EXIT)
            return;
        
        // 计算 SL/TP
        double atr = m_buf_atr[1];
        double sl = 0.0;
        
        if(type == SIGNAL_BUY)
        {
            sl = s.price - atr * TP_ATR_SL_Multi;
            s.tp = s.price + atr * TP_ATR_TP_Multi;
        }
        else
        {
            sl = s.price + atr * TP_ATR_SL_Multi;
            s.tp = s.price - atr * TP_ATR_TP_Multi;
        }
        
        // 确保 SL 符合最小距离要求
        double min_dist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
        if(type == SIGNAL_BUY)
            sl = MathMin(sl, s.price - min_dist);
        else
            sl = MathMax(sl, s.price + min_dist);
        
        s.sl = NormalizeDouble(sl, _Digits);
        s.tp = NormalizeDouble(s.tp, _Digits);
    }
    
    //+--------------------------------------------------------------
    //| 生成信号 (IStrategy 接口)
    //+--------------------------------------------------------------
    Signal GenerateSignal(Signal &signal) override
    {
        bool longSig = LongSignal();
        bool shortSig = ShortSignal();
        bool exitSig = HasExitSignal();
        
        if(!PositionSelect(_Symbol))  // 无持仓
        {
            if(longSig)
            {
                FillSignal(signal, SIGNAL_BUY);
                Print("[", Name(), "] Long signal. trend=", EnumToString(m_trend_state),
                      " price=", signal.price, " sl=", signal.sl, " tp=", signal.tp,
                      " ema20=", DoubleToString(m_buf_ema20_ltf[1], _Digits),
                      " vwap=", DoubleToString(m_vwap_ltf, _Digits));
                return signal;
            }
            if(shortSig)
            {
                FillSignal(signal, SIGNAL_SELL);
                Print("[", Name(), "] Short signal. trend=", EnumToString(m_trend_state),
                      " price=", signal.price, " sl=", signal.sl, " tp=", signal.tp,
                      " ema20=", DoubleToString(m_buf_ema20_ltf[1], _Digits),
                      " vwap=", DoubleToString(m_vwap_ltf, _Digits));
                return signal;
            }
        }
        else  // 有持仓
        {
            if(exitSig)
            {
                signal.type = SIGNAL_EXIT;
                FillSignal(signal, SIGNAL_EXIT);
                Print("[", Name(), "] Exit signal. trend=", EnumToString(m_trend_state));
                return signal;
            }
        }
        
        signal.type = SIGNAL_NONE;
        return signal;
    }
    
    //+--------------------------------------------------------------
    //| 策略名称
    //+--------------------------------------------------------------
    string Name() override
    {
        return "TrendPullback";
    }
};

#endif // __STRATEGY_TREND_PULLBACK_MQH__
