//+------------------------------------------------------------------+
//|              Strategies/Strategy_TrendPullback.mqh               |
//|                Trend Pullback Strategy (M2)                      |
//|     大趋势 + 小级别回撤吃第二段                                    |
//+------------------------------------------------------------------+

#ifndef __STRATEGY_TREND_PULLBACK_MQH__
#define __STRATEGY_TREND_PULLBACK_MQH__

#include "../Core/Strategy.mqh"
#include "../Core/TimeFilter_BollMR.mqh"
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
input bool  TP_RequireBreak     = true;    // 要求突破回撤结构点
input double TP_PullbackDepthATR = 0.618;  // 回撤深度上限 (ATR倍数)

input group "TrendPullback.Risk"
input int   TP_ATR_Period       = 14;      // ATR 周期
input double TP_ATR_SL_Multi    = 1.0;     // 初始止损 ATR 倍数

input group "TrendPullback.Exit"
input double TP_PartialExit1_ATR  = 1.5;   // 第一层部分平仓触发 (ATR倍数)
input double TP_PartialExit1_Ratio = 0.35; // 第一层平仓比例 (30-40%)
input double TP_BE_OffsetATR      = -0.2;  // 保本止损偏移 (ATR倍数，负数表示保本下方)
input double TP_TrailATR_Multi    = 2.5;   // Trailing Stop ATR倍数
input bool  TP_EnableTrailing     = true;  // 启用 Trailing Stop

input group "TrendPullback.Timeframe"
input ENUM_TIMEFRAMES TP_HTF    = PERIOD_M15;  // 高时间框架(方向)
input ENUM_TIMEFRAMES TP_LTF    = PERIOD_M5;   // 低时间框架(入场)

input group "TrendPullback.TimeFilter"
input string TP_Session          = "us,overlap"; // 交易时段: asia, europe, us, overlap, europe+us
input bool   TP_TimeFilterEntry  = true;         // 入场时间过滤
input bool   TP_TimeExitEndSession = true;       // 时段结束时平仓

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
    double m_recent_high;       // 最近波段高点
    double m_recent_low;        // 最近波段低点
    double m_swing_high;        // 趋势起点的高点（多头突破目标）
    double m_swing_low;         // 趋势起点的低点（空头突破目标）
    double m_pullback_lh;       // 回撤过程中的 Lower High（多头）
    double m_pullback_hl;       // 回撤过程中的 Higher Low（空头）
    
    // VWAP 计算
    double m_vwap_ltf;         // M5 VWAP
    double m_vwap_htf;         // M15 VWAP

    // 出场状态跟踪
    double m_entry_price;        // 入场价格
    double m_initial_sl;         // 初始止损
    double m_atr_at_entry;       // 入场时ATR
    bool   m_partial1_done;      // 第一层部分平仓是否完成
    int    m_entry_time;         // 入场时间
    string m_entry_session;      // 入场时段

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
        m_swing_high(0.0),
        m_swing_low(0.0),
        m_pullback_lh(0.0),
        m_pullback_hl(0.0),
        m_vwap_ltf(0.0),
        m_vwap_htf(0.0),
        m_entry_price(0.0),
        m_initial_sl(0.0),
        m_atr_at_entry(0.0),
        m_partial1_done(false),
        m_entry_time(0),
        m_entry_session("")
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
    //| 关键改进：跟踪回撤结构点 (Lower High / Higher Low)
    //+--------------------------------------------------------------
    void UpdateStructure()
    {
        if(ArraySize(m_buf_high) < TP_Structure_Lookback) return;
        
        // 最近波段高低点 (排除当前K线)
        double highs[], lows[];
        ArrayCopy(highs, m_buf_high, 0, 1, TP_Structure_Lookback);
        ArrayCopy(lows, m_buf_low, 0, 1, TP_Structure_Lookback);
        
        m_recent_high = highs[ArrayMaximum(highs)];
        m_recent_low = lows[ArrayMinimum(lows)];
        
        // 趋势起点结构（突破目标）
        m_swing_high = m_recent_high;
        m_swing_low = m_recent_low;
        
        // 回撤结构点跟踪
        // 多头：寻找回撤过程中的 Lower High
        // 空头：寻找回撤过程中的 Higher Low
        if(m_trend_state == TREND_BULL)
        {
            // 找到最近的波段高点后，寻找回撤形成的 Lower High
            m_pullback_lh = FindPullbackLowerHigh();
        }
        else if(m_trend_state == TREND_BEAR)
        {
            // 找到最近的波段低点后，寻找回撤形成的 Higher Low
            m_pullback_hl = FindPullbackHigherLow();
        }
    }
    
    //+--------------------------------------------------------------
    //| 寻找回撤过程中的 Lower High（多头场景）
    //| 即：从高点回落后，反弹但未超过前高的点
    //+--------------------------------------------------------------
    double FindPullbackLowerHigh()
    {
        // 找最高点位置
        int swing_high_idx = 0;
        double max_high = m_buf_high[1];
        for(int i = 1; i < TP_Structure_Lookback && i < ArraySize(m_buf_high); i++)
        {
            if(m_buf_high[i] > max_high)
            {
                max_high = m_buf_high[i];
                swing_high_idx = i;
            }
        }
        
        // 在最高点之后寻找 Lower High
        double lower_high = 0.0;
        for(int i = swing_high_idx - 1; i >= 1; i--)
        {
            // Lower High: 高点低于前一个高点
            if(m_buf_high[i] < max_high && m_buf_high[i] > lower_high)
            {
                lower_high = m_buf_high[i];
            }
        }
        
        return (lower_high > 0) ? lower_high : m_buf_high[1];
    }
    
    //+--------------------------------------------------------------
    //| 寻找回撤过程中的 Higher Low（空头场景）
    //| 即：从低点反弹后，回落但未跌破前低的点
    //+--------------------------------------------------------------
    double FindPullbackHigherLow()
    {
        // 找最低点位置
        int swing_low_idx = 0;
        double min_low = m_buf_low[1];
        for(int i = 1; i < TP_Structure_Lookback && i < ArraySize(m_buf_low); i++)
        {
            if(m_buf_low[i] < min_low)
            {
                min_low = m_buf_low[i];
                swing_low_idx = i;
            }
        }
        
        // 在最低点之后寻找 Higher Low
        double higher_low = DBL_MAX;
        for(int i = swing_low_idx - 1; i >= 1; i--)
        {
            // Higher Low: 低点高于前一个低点
            if(m_buf_low[i] > min_low && m_buf_low[i] < higher_low)
            {
                higher_low = m_buf_low[i];
            }
        }
        
        return (higher_low < DBL_MAX) ? higher_low : m_buf_low[1];
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
    //| 改进：小实体必须配合方向性信号
    //| 改进：平均实体使用干净的历史片段
    //+--------------------------------------------------------------
    bool IsPullbackEnded(bool forLong)
    {
        if(ArraySize(m_buf_close) < 8) return false;
        
        double open1 = m_buf_open[1];
        double close1 = m_buf_close[1];
        double high1 = m_buf_high[1];
        double low1 = m_buf_low[1];
        
        double open2 = m_buf_open[2];
        double close2 = m_buf_close[2];
        double high2 = m_buf_high[2];
        double low2 = m_buf_low[2];
        
        double body1 = MathAbs(close1 - open1);
        double range1 = high1 - low1;
        
        if(range1 <= 0) return false;
        
        // 计算平均实体大小 (使用干净的历史片段 i=3到7，避免回撤K线污染)
        double avg_body = 0.0;
        int count = 0;
        for(int i = 3; i <= 7; i++)
        {
            avg_body += MathAbs(m_buf_close[i] - m_buf_open[i]);
            count++;
        }
        avg_body /= count;
        
        if(avg_body <= 0) return false;
        
        if(forLong)
        {
            // 多头止跌结构:
            // 1. 阳线反包（强烈信号，单独成立）
            bool bullish_engulf = (close1 > open1) &&  // 当前是阳线
                                  (open1 <= low2) &&   // 开盘低于前一根低点
                                  (close1 >= high2);   // 收盘高于前一根高点
            
            // 2. 小实体 + 下影线确认（需要配合）
            bool small_body = body1 < avg_body * 0.5;
            double lower_wick = MathMin(open1, close1) - low1;
            bool hammer_like = lower_wick > body1 * 1.5 && lower_wick > 0;
            
            // 改进：小实体必须配合方向性信号
            return bullish_engulf || (small_body && hammer_like);
        }
        else
        {
            // 空头止涨结构:
            // 1. 阴线反包（强烈信号，单独成立）
            bool bearish_engulf = (close1 < open1) &&  // 当前是阴线
                                  (open1 >= high2) &&   // 开盘高于前一根高点
                                  (close1 <= low2);     // 收盘低于前一根低点
            
            // 2. 小实体 + 上影线确认（需要配合）
            bool small_body = body1 < avg_body * 0.5;
            double upper_wick = high1 - MathMax(open1, close1);
            bool shooting_star = upper_wick > body1 * 1.5 && upper_wick > 0;
            
            // 改进：小实体必须配合方向性信号
            return bearish_engulf || (small_body && shooting_star);
        }
    }
    
    //+--------------------------------------------------------------
    //| 小结构突破确认
    //| 改进1：多头用Ask，空头用Bid（真实成交价）
    //| 改进2：突破回撤结构点（Lower High / Higher Low）
    //+--------------------------------------------------------------
    bool IsStructureBreak(bool forLong)
    {
        if(!TP_RequireBreak) return true;
        
        double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        
        if(forLong)
        {
            // 多头：Ask 突破回撤 Lower High
            // 使用 Ask 因为买入时用 Ask 成交
            double target = (m_pullback_lh > 0) ? m_pullback_lh : m_buf_high[1];
            return ask > target;
        }
        else
        {
            // 空头：Bid 跌破回撤 Higher Low
            // 使用 Bid 因为卖出时用 Bid 成交
            double target = (m_pullback_hl > 0 && m_pullback_hl < DBL_MAX) ? m_pullback_hl : m_buf_low[1];
            return bid < target;
        }
    }
    
    //+--------------------------------------------------------------
    //| 多头入场信号
    //+--------------------------------------------------------------
    bool LongSignal()
    {
        // 0. 时间过滤
        if(TP_TimeFilterEntry && !IsInSession())
            return false;

        // 1. M15 上涨趋势
        if(m_trend_state != TREND_BULL)
            return false;

        // 2. ATR 有效
        if(ArraySize(m_buf_atr) < 2 || m_buf_atr[1] <= 0)
            return false;

        double atr = m_buf_atr[1];
        double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

        // 3. 回撤深度限制 (防止回撤太深变成反转)
        if(m_swing_high > 0)
        {
            double pullback_depth = m_swing_high - bid;
            if(pullback_depth > atr * TP_PullbackDepthATR)
                return false;  // 回撤太深，不符合"回撤吃第二段"逻辑
        }

        // 4. 价格回撤到价值区 (EMA20/VWAP)
        if(!IsInValueZone(bid, atr, true))
            return false;

        // 5. 回撤结束确认 (K线形态)
        if(!IsPullbackEnded(true))
            return false;

        // 6. 小结构突破确认
        if(!IsStructureBreak(true))
            return false;

        return true;
    }

    //+--------------------------------------------------------------
    //| 空头入场信号
    //+--------------------------------------------------------------
    bool ShortSignal()
    {
        // 0. 时间过滤
        if(TP_TimeFilterEntry && !IsInSession())
            return false;

        // 1. M15 下跌趋势
        if(m_trend_state != TREND_BEAR)
            return false;

        // 2. ATR 有效
        if(ArraySize(m_buf_atr) < 2 || m_buf_atr[1] <= 0)
            return false;

        double atr = m_buf_atr[1];
        double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

        // 3. 回撤深度限制 (防止反弹太深变成反转)
        if(m_swing_low > 0 && m_swing_low < DBL_MAX)
        {
            double pullback_depth = bid - m_swing_low;
            if(pullback_depth > atr * TP_PullbackDepthATR)
                return false;  // 反弹太深，不符合"回撤吃第二段"逻辑
        }

        // 4. 价格反弹到价值区 (EMA20/VWAP)
        if(!IsInValueZone(bid, atr, false))
            return false;

        // 5. 回撤结束确认 (K线形态)
        if(!IsPullbackEnded(false))
            return false;

        // 6. 小结构突破确认
        if(!IsStructureBreak(false))
            return false;

        return true;
    }

    //+--------------------------------------------------------------
    //| 时间过滤：判断当前是否在允许交易时段
    //| 独立实现，不依赖 BollMR input 变量
    //+--------------------------------------------------------------
    bool IsInSession()
    {
        datetime currentTime = TimeCurrent();
        MqlDateTime timeStruct;
        TimeToStruct(currentTime, timeStruct);
        int server_hour = timeStruct.hour;

        string sessions = TP_Session;
        StringToLower(sessions);

        // 北京时间窗口定义（冬令时）
        int asia_start = 8,  asia_end = 16;
        int eu_start   = 15, eu_end   = 24;
        int us_start   = 20, us_end   = 4;  // 跨午夜
        int ov_start   = 20, ov_end   = 24;

        // DST 平移
        if(BollMR_UseDST)
        {
            eu_start = NormalizeHour(eu_start + BollMR_DSTShiftHours);
            eu_end   = NormalizeHour(eu_end   + BollMR_DSTShiftHours);
            us_start = NormalizeHour(us_start + BollMR_DSTShiftHours);
            us_end   = NormalizeHour(us_end   + BollMR_DSTShiftHours);
            ov_start = NormalizeHour(ov_start + BollMR_DSTShiftHours);
            ov_end   = NormalizeHour(ov_end   + BollMR_DSTShiftHours);
        }

        // 转换为服务器时间
        int asia_s = BeijingToServerHour(asia_start);
        int asia_e = BeijingToServerHour(asia_end);
        int eu_s   = BeijingToServerHour(eu_start);
        int eu_e   = BeijingToServerHour(eu_end);
        int us_s   = BeijingToServerHour(us_start);
        int us_e   = BeijingToServerHour(us_end);
        int ov_s   = BeijingToServerHour(ov_start);
        int ov_e   = BeijingToServerHour(ov_end);

        string list[];
        int cnt = StringSplit(sessions, ',', list);
        if(cnt <= 0)
        {
            ArrayResize(list, 1);
            list[0] = sessions;
            cnt = 1;
        }

        for(int i = 0; i < cnt; i++)
        {
            string s = list[i];
            StringTrimLeft(s);
            StringTrimRight(s);
            if(s == "") continue;

            if(s == "asia" && InWindow(server_hour, asia_s, asia_e))
                return true;
            if(s == "europe" && InWindow(server_hour, eu_s, eu_e))
                return true;
            if(s == "us" && InWindow(server_hour, us_s, us_e))
                return true;
            if(s == "overlap" && InWindow(server_hour, ov_s, ov_e))
                return true;
            if((s == "europe+us" || s == "eu+us") &&
               (InWindow(server_hour, eu_s, eu_e) || InWindow(server_hour, us_s, us_e)))
                return true;
        }

        return false;
    }

    // 辅助函数：小时归一化
    int NormalizeHour(int hour)
    {
        int h = hour % 24;
        if(h < 0) h += 24;
        return h;
    }

    // 辅助函数：北京时间转服务器时间
    int BeijingToServerHour(int bj_hour)
    {
        int server_hour = bj_hour - 8 + BollMR_ServerUTCOffset;
        return NormalizeHour(server_hour);
    }

    // 辅助函数：判断是否在时间窗口内
    bool InWindow(int hour, int start, int end)
    {
        if(start == end) return true;
        if(start <= end) return (hour >= start && hour < end);
        return (hour >= start || hour < end);  // 跨午夜
    }

    //+--------------------------------------------------------------
    //| 获取当前时段名称
    //+--------------------------------------------------------------
    string GetCurrentSession()
    {
        datetime currentTime = TimeCurrent();
        MqlDateTime timeStruct;
        TimeToStruct(currentTime, timeStruct);
        int server_hour = timeStruct.hour;

        // 定义时段（同上）
        int asia_start = 8,  asia_end = 16;
        int eu_start   = 15, eu_end   = 24;
        int us_start   = 20, us_end   = 4;
        int ov_start   = 20, ov_end   = 24;

        if(BollMR_UseDST)
        {
            eu_start = NormalizeHour(eu_start + BollMR_DSTShiftHours);
            eu_end   = NormalizeHour(eu_end   + BollMR_DSTShiftHours);
            us_start = NormalizeHour(us_start + BollMR_DSTShiftHours);
            us_end   = NormalizeHour(us_end   + BollMR_DSTShiftHours);
            ov_start = NormalizeHour(ov_start + BollMR_DSTShiftHours);
            ov_end   = NormalizeHour(ov_end   + BollMR_DSTShiftHours);
        }

        int asia_s = BeijingToServerHour(asia_start);
        int asia_e = BeijingToServerHour(asia_end);
        int eu_s   = BeijingToServerHour(eu_start);
        int eu_e   = BeijingToServerHour(eu_end);
        int us_s   = BeijingToServerHour(us_start);
        int us_e   = BeijingToServerHour(us_end);

        if(InWindow(server_hour, asia_s, asia_e)) return "asia";
        if(InWindow(server_hour, us_s, us_e)) return "us";
        if(InWindow(server_hour, eu_s, eu_e)) return "europe";
        return "other";
    }
    
    //+--------------------------------------------------------------
    //| 四层出场逻辑
    //| 核心：先活下来 → 再吃趋势 → 再放飞
    //+--------------------------------------------------------------
    bool HasExitSignal()
    {
        if(!PositionSelect(_Symbol))
            return false;

        ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double atr = (ArraySize(m_buf_atr) >= 2) ? m_buf_atr[1] : 0;

        // 多头出场
        if(type == POSITION_TYPE_BUY)
        {
            return HasLongExitSignal(bid, ask, atr);
        }
        // 空头出场
        else if(type == POSITION_TYPE_SELL)
        {
            return HasShortExitSignal(bid, ask, atr);
        }

        return false;
    }

    //+--------------------------------------------------------------
    //| 多头出场信号（四层结构）
    //+--------------------------------------------------------------
    bool HasLongExitSignal(double bid, double ask, double atr)
    {
        // === 第一层：防御止损（硬SL）===
        // 触发条件：结构破坏 或 初始SL触及
        if(bid < m_recent_low)  // 结构破坏
        {
            Print("[", Name(), "] L1 Exit: Structure break. bid=", bid, " < recent_low=", m_recent_low);
            return true;
        }
        if(m_initial_sl > 0 && bid <= m_initial_sl)  // 初始止损触及
        {
            Print("[", Name(), "] L1 Exit: Initial SL hit. bid=", bid, " <= sl=", m_initial_sl);
            return true;
        }

        // === 第二层：最小兑现（部分平仓）===
        // 触发条件：盈利达到 +1.5 ATR
        if(!m_partial1_done && m_entry_price > 0 && atr > 0)
        {
            double profit_atr = (bid - m_entry_price) / atr;
            if(profit_atr >= TP_PartialExit1_ATR)
            {
                // 这里返回部分平仓信号（需要 EA 层处理）
                // 简化处理：先返回 true，让 EA 全平
                // 后续可以扩展 Signal 类型支持部分平仓
                Print("[", Name(), "] L2 Exit: Partial exit triggered. profit=", profit_atr, " ATR");
                m_partial1_done = true;
                // 不直接出场，而是标记需要部分平仓
                // 目前简化为继续持有
            }
        }

        // === 第三层：趋势持有 ===
        // 条件：EMA20/VWAP 未被有效跌破 + 回撤不破结构
        // 如果跌破价值区，考虑出场
        double ema20 = (ArraySize(m_buf_ema20_ltf) >= 2) ? m_buf_ema20_ltf[1] : 0;
        bool ema20_broken = (ema20 > 0 && bid < ema20 - atr * 0.3);  // 实体跌破 EMA20

        // VWAP 确认
        bool vwap_broken = (TP_UseVWAP_LTF && m_vwap_ltf > 0 && bid < m_vwap_ltf - atr * 0.2);

        // 趋势反转
        if(m_trend_state == TREND_BEAR)
        {
            Print("[", Name(), "] L3 Exit: Trend reversal to BEAR");
            return true;
        }

        // EMA/VWAP 实体跌破
        if(ema20_broken && vwap_broken)
        {
            Print("[", Name(), "] L3 Exit: EMA20 and VWAP broken. bid=", bid,
                  " ema20=", ema20, " vwap=", m_vwap_ltf);
            return true;
        }

        // === 第四层：时间止盈 ===
        // 时段结束时平仓
        if(TP_TimeExitEndSession && m_entry_session != "" && m_entry_session != GetCurrentSession())
        {
            Print("[", Name(), "] L4 Exit: Session ended. entry=", m_entry_session,
                  " current=", GetCurrentSession());
            return true;
        }

        // === Trailing Stop (可选) ===
        if(TP_EnableTrailing && m_entry_price > 0 && atr > 0)
        {
            double trail_stop = bid - atr * TP_TrailATR_Multi;
            if(trail_stop > m_initial_sl)
            {
                // 更新止损到更高位置
                m_initial_sl = trail_stop;
            }
        }

        return false;
    }

    //+--------------------------------------------------------------
    //| 空头出场信号（四层结构）
    //+--------------------------------------------------------------
    bool HasShortExitSignal(double bid, double ask, double atr)
    {
        // === 第一层：防御止损（硬SL）===
        if(ask > m_recent_high)  // 结构破坏
        {
            Print("[", Name(), "] L1 Exit: Structure break. ask=", ask, " > recent_high=", m_recent_high);
            return true;
        }
        if(m_initial_sl > 0 && ask >= m_initial_sl)  // 初始止损触及
        {
            Print("[", Name(), "] L1 Exit: Initial SL hit. ask=", ask, " >= sl=", m_initial_sl);
            return true;
        }

        // === 第二层：最小兑现（部分平仓）===
        if(!m_partial1_done && m_entry_price > 0 && atr > 0)
        {
            double profit_atr = (m_entry_price - ask) / atr;
            if(profit_atr >= TP_PartialExit1_ATR)
            {
                Print("[", Name(), "] L2 Exit: Partial exit triggered. profit=", profit_atr, " ATR");
                m_partial1_done = true;
            }
        }

        // === 第三层：趋势持有 ===
        double ema20 = (ArraySize(m_buf_ema20_ltf) >= 2) ? m_buf_ema20_ltf[1] : 0;
        bool ema20_broken = (ema20 > 0 && ask > ema20 + atr * 0.3);

        bool vwap_broken = (TP_UseVWAP_LTF && m_vwap_ltf > 0 && ask > m_vwap_ltf + atr * 0.2);

        if(m_trend_state == TREND_BULL)
        {
            Print("[", Name(), "] L3 Exit: Trend reversal to BULL");
            return true;
        }

        if(ema20_broken && vwap_broken)
        {
            Print("[", Name(), "] L3 Exit: EMA20 and VWAP broken. ask=", ask,
                  " ema20=", ema20, " vwap=", m_vwap_ltf);
            return true;
        }

        // === 第四层：时间止盈 ===
        if(TP_TimeExitEndSession && m_entry_session != "" && m_entry_session != GetCurrentSession())
        {
            Print("[", Name(), "] L4 Exit: Session ended. entry=", m_entry_session,
                  " current=", GetCurrentSession());
            return true;
        }

        // === Trailing Stop ===
        if(TP_EnableTrailing && m_entry_price > 0 && atr > 0)
        {
            double trail_stop = ask + atr * TP_TrailATR_Multi;
            if(trail_stop < m_initial_sl || m_initial_sl <= 0)
            {
                m_initial_sl = trail_stop;
            }
        }

        return false;
    }

    //+--------------------------------------------------------------
    //| 重置入场状态（新仓位时调用）
    //+--------------------------------------------------------------
    void ResetEntryState()
    {
        m_partial1_done = false;
        m_entry_session = GetCurrentSession();
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

        // 计算 SL
        double atr = m_buf_atr[1];
        double sl = 0.0;

        if(type == SIGNAL_BUY)
        {
            sl = s.price - atr * TP_ATR_SL_Multi;
        }
        else
        {
            sl = s.price + atr * TP_ATR_SL_Multi;
        }

        // 确保 SL 符合最小距离要求
        double min_dist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
        if(type == SIGNAL_BUY)
            sl = MathMin(sl, s.price - min_dist);
        else
            sl = MathMax(sl, s.price + min_dist);

        s.sl = NormalizeDouble(sl, _Digits);

        // 记录入场信息（用于出场逻辑）
        m_entry_price = s.price;
        m_initial_sl = s.sl;
        m_atr_at_entry = atr;
        m_entry_time = (int)TimeCurrent();
        ResetEntryState();

        Print("[", Name(), "] Entry recorded. price=", m_entry_price,
              " sl=", m_initial_sl, " atr=", m_atr_at_entry,
              " session=", m_entry_session);
    }
    
    //+--------------------------------------------------------------
    //| 生成信号 (IStrategy 接口)
    //+--------------------------------------------------------------
    Signal GenerateSignal(Signal &signal) override
    {
        // 注意：UpdateIndicators() 由 Ea_run.mq5::OnTick() 调用
        // 这里直接使用已更新的数据进行信号判断

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
