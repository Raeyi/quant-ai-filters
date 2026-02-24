//+------------------------------------------------------------------+
//|              Strategies/Strategy_TrendPullback.mqh               |
//|                Trend Pullback Strategy (M2)                      |
//|     大趋势 + 小级别回撤吃第二段                                    |
//+------------------------------------------------------------------+

#ifndef __STRATEGY_TREND_PULLBACK_MQH__
#define __STRATEGY_TREND_PULLBACK_MQH__

#include "../Core/Strategy.mqh"
#include "../Core/TimeFilter.mqh"
#include "../Core/TimeFilter_BollMR.mqh"
#include "../Core/Regime/RegimeTypes.mqh"
#include "../Core/Risk/AddPositionManager.mqh"
#include "../Indicators/ATR.mqh"
#include "../Indicators/MA.mqh"
#include "../Core/Risk/AccountRisk.mqh"
#include "../Core/Inputs_All.mqh"

// 输入参数定义在 Inputs_All.mqh，此文件不再重复声明

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

    // 加仓管理器
    CAddPositionManager m_add_manager;
    bool   m_add_signal_pending;     // 是否有待处理的加仓信号
    AddSignalType m_pending_add_type; // 待处理的加仓类型
    double m_pending_add_lot;         // 待处理的加仓手数
    double m_pending_add_price;       // 待处理的加仓价格
    double m_pending_add_sl;          // 待处理的加仓止损
    double m_last_position_volume;    // 上次持仓量（用于检测加仓执行）
    bool   m_was_in_position;         // 上一tick是否有持仓（用于检测平仓）
    
    // ===== v3.1 调试统计 =====
    int m_stat_trend_ok;          // 趋势通过次数
    int m_stat_pullback_ok;       // 回撤通过次数
    int m_stat_pullback_end_ok;   // 回撤结束通过次数
    int m_stat_structure_ok;      // 结构突破通过次数
    int m_stat_total_checks;      // 总检查次数
    datetime m_last_stat_time;    // 上次统计输出时间

public:
    //+--------------------------------------------------------------
    //| 构造函数
    //+--------------------------------------------------------------
    Strategy_TrendPullback() : 
        m_handle_ema50_htf(INVALID_HANDLE),     // M15 EMA50
        m_handle_ema200_htf(INVALID_HANDLE),    // M15 EMA200
        m_handle_ema20_ltf(INVALID_HANDLE),     // M5 EMA20
        m_handle_atr(INVALID_HANDLE),           // ATR 指标句柄
        m_initialized(false),                   // 是否已初始化
        m_recent_high(0.0),                     // 最近波段高点
        m_recent_low(0.0),                      // 最近波段低点
        m_swing_high(0.0),                      // 多头回撤过程中的 Upper High
        m_swing_low(0.0),                       // 空头回撤过程中的 Lower Low
        m_pullback_lh(0.0),                     // 多头回撤过程中的 Lower High
        m_pullback_hl(0.0),                     // 空头回撤过程中的 Higher Low
        m_vwap_ltf(0.0),                        // M5 VWAP
        m_vwap_htf(0.0),                        // M15 VWAP
        m_entry_price(0.0),                     // 入场价格
        m_initial_sl(0.0),                      // 初始止损
        m_atr_at_entry(0.0),                    // 入场时ATR
        m_partial1_done(false),                 // 第一层部分平仓是否完成
        m_entry_time(0),                        // 入场时间
        m_entry_session(""),                    // 入场时段
        m_add_signal_pending(false),            // 是否有待处理的加仓信号
        m_pending_add_type(ADD_SIGNAL_NONE),    // 待处理的加仓类型
        m_pending_add_lot(0.0),                 // 待处理的加仓手数
        m_pending_add_price(0.0),               // 待处理的加仓价格
        m_pending_add_sl(0.0),                  // 待处理的加仓止损
        m_last_position_volume(0.0),            // 上次持仓量
        m_was_in_position(false),               // 上一tick是否有持仓
        m_stat_trend_ok(0),                     // 趋势通过次数
        m_stat_pullback_ok(0),                  // 回撤通过次数
        m_stat_pullback_end_ok(0),              // 回撤结束通过次数
        m_stat_structure_ok(0),                 // 结构突破通过次数
        m_stat_total_checks(0),                 // 总检查次数
        m_last_stat_time(0)                     // 上次统计输出时间
    {
        ArraySetAsSeries(m_buf_ema50_htf, true);            // M15 EMA50
        ArraySetAsSeries(m_buf_ema200_htf, true);           // M15 EMA200
        ArraySetAsSeries(m_buf_ema20_ltf, true);            // M5 EMA20
        ArraySetAsSeries(m_buf_atr, true);                  // ATR
        ArraySetAsSeries(m_buf_high, true);                 // K线数据
        ArraySetAsSeries(m_buf_low, true);                  // K线数据
        ArraySetAsSeries(m_buf_close, true);                // K线数据
        ArraySetAsSeries(m_buf_open, true);                 // K线数据
        ArraySetAsSeries(m_buf_volume, true);               // K线数据
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

        // 初始化加仓管理器
        if(TP_EnableAddPosition)
        {
            m_add_manager.SetParams(TP_PartialExit1_ATR, TP_Add1_Ratio,
                                    TP_Add2_Ratio, TP_Add2_ProfitATR, TP_MaxTotalRisk);
            m_add_manager.Reset();
        }
        
        Print("[", Name(), "] Indicators initialized. HTF=", EnumToString(TP_HTF), 
              " LTF=", EnumToString(TP_LTF),
              " Cooldown=", TP_EnableCooldown ? "ON" : "OFF",
              " AddPos=", TP_EnableAddPosition ? "ON" : "OFF");
        return true;
    }
    
    //+--------------------------------------------------------------
    //| 时间过滤：供外部面板查询
    //| 如果 TP_TimeFilterEntry=false 则始终返回 true
    //+--------------------------------------------------------------
    bool TimeFilterOK()
    {
        if(!TP_TimeFilterEntry) return true;
        return TimeFilter_CheckSession(TP_Session, BollMR_UseDST, BollMR_DSTShiftHours);
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
        
        // 更新 VWAP
        UpdateVWAP_HTF();
        
        // M6.3: 趋势状态由 RegimeFilter 提供，不再在此处计算
        // 原 UpdateTrendState() 已删除，使用 m_regime_filter->GetTrendDirection()
        
        // 更新结构高低点
        UpdateStructure();
        
        // 更新 VWAP
        UpdateVWAP();
        
        return true;
    }

    bool IsSameTradingDay(datetime t1, datetime t2)
    {
        MqlDateTime d1, d2;
        TimeToStruct(t1, d1);
        TimeToStruct(t2, d2);

        return (d1.year == d2.year &&
                d1.mon  == d2.mon  &&
                d1.day  == d2.day);
    }
    
    //+--------------------------------------------------------------
    //| 更新 VWAP
    //+--------------------------------------------------------------
    void UpdateVWAP_HTF()
    {
        double sum_pv = 0.0;
        double sum_vol = 0.0;

        int bars = Bars(_Symbol, TP_HTF);

        // 限制回溯数量，防止太慢
        int lookback = MathMin(bars, 200);

        for(int i = 0; i < lookback; i++)
        {
            datetime t = iTime(_Symbol, TP_HTF, i);

            // 只算当日 / 当前 session
            if(!IsSameTradingDay(t, TimeCurrent()))
                break;

            double close = iClose(_Symbol, TP_HTF, i);
            double vol   = (double)iVolume(_Symbol, TP_HTF, i); // tick volume

            sum_pv  += close * vol;
            sum_vol += vol;
        }

        if(sum_vol > 0)
            m_vwap_htf = sum_pv / sum_vol;
        else
            m_vwap_htf = 0.0;

        // Print("VWAP HTF = ", m_vwap_htf); // 调试用
    }
    
    // M6.3: UpdateTrendState() 已删除
    // 趋势状态由 RegimeFilter 统一提供，通过 m_regime_filter->GetTrendDirection() 获取
    
    //+--------------------------------------------------------------
    //| 更新结构高低点
    //| 关键改进：跟踪回撤结构点 (Lower High / Higher Low)
    //+--------------------------------------------------------------
    void UpdateStructure()
    {
        if(ArraySize(m_buf_high) < TP_Structure_Lookback) return;       // 至少需要 2 个 K 线
        
        // 最近波段高低点 (排除当前K线)
        double highs[], lows[];
        ArrayCopy(highs, m_buf_high, 0, 1, TP_Structure_Lookback);
        ArrayCopy(lows, m_buf_low, 0, 1, TP_Structure_Lookback);
        
        m_recent_high = highs[ArrayMaximum(highs)];                     // 最近波段最高点
        m_recent_low = lows[ArrayMinimum(lows)];                        // 最近波段最低点
        
        // 趋势起点结构（突破目标）
        m_swing_high = m_recent_high;                                   // 多头：最近波段最高点
        m_swing_low = m_recent_low;                                     // 空头：最近波段最低点
        
        // M6.3: 使用 RegimeFilter 的趋势方向
        TrendDirection trend = GetTrendState();
        
        // 回撤结构点跟踪
        // 多头：寻找回撤过程中的 Lower High
        // 空头：寻找回撤过程中的 Higher Low
        if(trend == TREND_BULL)
        {
            // 找到最近的波段高点后，寻找回撤形成的 Lower High
            m_pullback_lh = FindPullbackLowerHigh();
        }
        else if(trend == TREND_BEAR)
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
            double vol = (double)m_buf_volume[i];
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
                double vol = (double)v_htf[i];
                sum_vp += typical * vol;
                sum_v += vol;
            }
            m_vwap_htf = (sum_v > 0) ? sum_vp / sum_v : 0.0;
        }
    }
    
    //+--------------------------------------------------------------
    //| 获取趋势状态（M6.3: 从 RegimeFilter 获取）
    //+--------------------------------------------------------------
    TrendDirection GetTrendState() const 
    { 
        if(m_regime_filter != NULL)
            return m_regime_filter.GetTrendDirection();
        return TREND_NONE;  // 降级：无 RegimeFilter 时返回震荡
    }
    
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
            // 多头：价格回撤到 EMA20 或 VWAP 下方附近（价值区买点）
            return (price <= ema20 + tolerance) && (price >= ema20 - tolerance) && (near_ema20 || near_vwap);
        }
        else
        {
            // 空头：价格反弹到 EMA20 或 VWAP 上方附近（价值区卖点）
            return (price >= ema20 - tolerance) && (price <= ema20 + tolerance) && (near_ema20 || near_vwap);
        }
    }
    
    //+--------------------------------------------------------------
    //| 回撤结束确认 (v3.1 改进版)
    //| 核心逻辑：价格不再创新低/高 + 动能衰竭
    //| K线形态作为加分项，非硬性条件
    //+--------------------------------------------------------------
    bool IsPullbackEnded(bool forLong)
    {
        if(ArraySize(m_buf_close) < 8) return false;
        
        // ===== 第一层：软确认（必须满足）=====
        // 价格不再创新低（多头）或不再创新高（空头）
        bool momentum_weak = PullbackMomentumWeak(forLong);
        
        // ===== 第二层：K线形态（加分项）=====
        // 作为加分项而非硬性条件
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
        
        // 计算平均实体大小 (使用干净的历史片段 i=3到7)
        double avg_body = 0.0;
        int count = 0;
        for(int i = 3; i <= 7; i++)
        {
            avg_body += MathAbs(m_buf_close[i] - m_buf_open[i]);
            count++;
        }
        avg_body /= count;
        
        bool pattern_bonus = false;  // K线形态加分
        
        if(forLong)
        {
            // 多头止跌形态:
            bool bullish_engulf = (close1 > open1) &&
                                  (open1 <= low2) &&
                                  (close1 >= high2);
            
            bool small_body = (avg_body > 0) && (body1 < avg_body * 0.5);
            double lower_wick = MathMin(open1, close1) - low1;
            bool hammer_like = lower_wick > body1 * 1.5 && lower_wick > 0;
            
            pattern_bonus = bullish_engulf || (small_body && hammer_like);
        }
        else
        {
            // 空头止涨形态:
            bool bearish_engulf = (close1 < open1) &&
                                  (open1 >= high2) &&
                                  (close1 <= low2);
            
            bool small_body = (avg_body > 0) && (body1 < avg_body * 0.5);
            double upper_wick = high1 - MathMax(open1, close1);
            bool shooting_star = upper_wick > body1 * 1.5 && upper_wick > 0;
            
            pattern_bonus = bearish_engulf || (small_body && shooting_star);
        }
        
        // v3.1: 只要动量衰竭即可，K线形态作为加分
        // 如果有K线形态确认，则降低后续过滤条件
        return momentum_weak || pattern_bonus;
    }
    
    //+--------------------------------------------------------------
    //| 动量衰竭检测 (v3.1 新增)
    //| 核心：价格不再创新低/高
    //+--------------------------------------------------------------
    bool PullbackMomentumWeak(bool forLong)
    {
        if(ArraySize(m_buf_low) < 3 || ArraySize(m_buf_high) < 3)
            return false;
        
        if(forLong)
        {
            // 多头：检查是否不再创新低
            // [1] 的低点 >= [2] 的低点（止跌信号）
            // 或 [2] 的低点 >= [3] 的低点（止跌信号）
            return m_buf_low[1] >= m_buf_low[2] ||
                   m_buf_low[2] >= m_buf_low[3];
        }
        else
        {
            // 空头：检查是否不再创新高
            // [1] 的高点 <= [2] 的高点（止涨信号）
            // 或 [2] 的高点 <= [3] 的高点（止涨信号）
            return m_buf_high[1] <= m_buf_high[2] ||
                   m_buf_high[2] <= m_buf_high[3];

        }
    }
    
    //+--------------------------------------------------------------
    //| 小结构突破确认 (v3.2 改进版)
    //| v3.2: 修改逻辑 - 回撤策略不需要等待突破
    //| 原因：等待突破 = 错过入场点
    //| 新逻辑：回撤结束信号已足够，直接允许入场
    //+--------------------------------------------------------------
    bool IsStructureBreak(bool forLong)
    {
        // v3.2: 如果不需要突破确认，直接返回 true
        if(!TP_RequireBreak) return true;
        
        // v3.2 新逻辑：回撤策略不等待结构突破
        // 理由：
        // 1. 我们已经在价值区（EMA20/VWAP附近）
        // 2. 我们已经有回撤结束信号（止跌/止涨）
        // 3. 等待突破意味着错过最佳入场点
        // 
        // 改为：检查价格是否"开始反弹"即可
        // 多头：当前K线收盘价 > 开盘价（阳线）或 收盘价 > 前一根收盘价
        // 空头：当前K线收盘价 < 开盘价（阴线）或 收盘价 < 前一根收盘价
        
        double close1 = m_buf_close[1];
        double open1 = m_buf_open[1];
        double close2 = m_buf_close[2];
        
        if(forLong)
        {
            // 多头：开始反弹信号
            // 条件：阳线 OR 收盘价高于前一根
            bool is_bullish_candle = (close1 > open1);
            bool is_higher_close = (close1 > close2);
            
            return is_bullish_candle || is_higher_close;
        }
        else
        {
            // 空头：开始回落信号
            // 条件：阴线 OR 收盘价低于前一根
            bool is_bearish_candle = (close1 < open1);
            bool is_lower_close = (close1 < close2);
            
            return is_bearish_candle || is_lower_close;
        }
    }
    
    //+--------------------------------------------------------------
    //| 检查 Sub-Type 是否适合趋势回撤策略
    //| 适合：TVB_TREND(强趋势), TN_MILD(温和趋势)
    //| 不适合：RN_NORMAL/RL_LOW(震荡), RVA_NEWS(消息), RVB_FALSE(假突破), TVA_EMOTION(情绪)
    //+--------------------------------------------------------------
    bool IsSubTypeSuitable()
    {
        if(m_regime_filter == NULL)
            return true;  // 无 RF 时允许通过
        
        RegimeSubType sub_type = m_regime_filter.GetSubType();
        
        switch(sub_type)
        {
            case SUBTYPE_TVB_TREND:    // 强趋势 - 最佳
            case SUBTYPE_TN_MILD:      // 温和趋势 - 可以
                return true;
            
            case SUBTYPE_RN_NORMAL:    // 正常震荡 - 无趋势
            case SUBTYPE_RL_LOW:       // 低波动 - 无趋势
            case SUBTYPE_RVA_NEWS:     // 消息震荡 - 不稳定
            case SUBTYPE_RVB_FALSE:    // 假突破密集 - 假突破多
            case SUBTYPE_TVA_EMOTION:  // 情绪脉冲 - 不稳定
                return false;
            
            default:
                return true;  // 未知类型允许通过
        }
    }
    
    //+--------------------------------------------------------------
    //| 多头入场信号 (v3.1 带调试统计)
    //+--------------------------------------------------------------
    bool LongSignal()
    {
        m_stat_total_checks++;

        // 0.0 Sub-Type 过滤（趋势策略只在趋势类 Sub-Type 下交易）
        if(!IsSubTypeSuitable())
            return false;

        // 0.1 时间过滤
        if(TP_TimeFilterEntry && !TimeFilter_CheckSession(TP_Session, BollMR_UseDST, BollMR_DSTShiftHours))
        {
            // Print("[DEBUG] Long blocked by time filter");
            return false;
        }

        // 1. M6.3: 趋势由 RegimeFilter 提供
        TrendDirection trend = GetTrendState();
        if(trend != TREND_BULL)
        {
            // Print("[DEBUG] Long blocked: not BULL, state=", EnumToString(trend));
            return false;
        }
        
        // ===== 第1层通过：趋势OK =====
        m_stat_trend_ok++;

        // 2. ATR 有效
        if(ArraySize(m_buf_atr) < 2 || m_buf_atr[1] <= 0)
        {
            // Print("[DEBUG] Long blocked: ATR invalid");
            return false;
        }

        double atr = m_buf_atr[1];
        double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

        // 3. 回撤深度限制 (防止回撤太深变成反转)
        if(m_swing_high > 0)
        {
            double pullback_depth = m_swing_high - bid;
            if(pullback_depth > atr * TP_PullbackDepthATR)
            {
                // Print("[DEBUG] Long blocked: pullback too deep");
                return false;  // 回撤太深，不符合"回撤吃第二段"逻辑
            }
        }

        // 4. 价格回撤到价值区 (EMA20/VWAP)
        if(!IsInValueZone(bid, atr, true))
        {
            // Print("[DEBUG] Long blocked: not in value zone");
            return false;
        }
        
        // ===== 第2层通过：回撤OK =====
        m_stat_pullback_ok++;

        // 5. 回撤结束确认 (v3.1: 软确认)
        if(!IsPullbackEnded(true))
        {
            // Print("[DEBUG] Long blocked: pullback not ended");
            return false;
        }
        
        // ===== 第3层通过：回撤结束OK =====
        m_stat_pullback_end_ok++;

        // 6. 小结构突破确认 (v3.1: 收线价)
        if(!IsStructureBreak(true))
        {
            // Print("[DEBUG] Long blocked: structure not broken");
            return false;
        }
        
        // ===== 第4层通过：结构突破OK =====
        m_stat_structure_ok++;
        
        // Print("[DEBUG] Long signal PASSED all filters!"); // 减少日志噪音

        return true;
    }

    //+--------------------------------------------------------------
    //| 空头入场信号 (v3.1 带调试统计)
    //+--------------------------------------------------------------
    bool ShortSignal()
    {
        m_stat_total_checks++;

        // 0.0 Sub-Type 过滤（趋势策略只在趋势类 Sub-Type 下交易）
        if(!IsSubTypeSuitable())
            return false;

        // 0.1 时间过滤
        if(TP_TimeFilterEntry && !TimeFilter_CheckSession(TP_Session, BollMR_UseDST, BollMR_DSTShiftHours))
            return false;

        // 1. M6.3: 趋势由 RegimeFilter 提供
        TrendDirection trend = GetTrendState();
        if(trend != TREND_BEAR)
            return false;
        
        // ===== 第1层通过：趋势OK =====
        m_stat_trend_ok++;

        // 2. ATR 有效
        if(ArraySize(m_buf_atr) < 2 || m_buf_atr[1] <= 0)
            return false;

        double atr = m_buf_atr[1];
        double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

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
        
        // ===== 第2层通过：回撤OK =====
        m_stat_pullback_ok++;

        // 5. 回撤结束确认 (v3.1: 软确认)
        if(!IsPullbackEnded(false))
            return false;
        
        // ===== 第3层通过：回撤结束OK =====
        m_stat_pullback_end_ok++;

        // 6. 小结构突破确认 (v3.1: 收线价)
        if(!IsStructureBreak(false))
            return false;
        
        // ===== 第4层通过：结构突破OK =====
        m_stat_structure_ok++;

        return true;
    }

    //+--------------------------------------------------------------
    //| 获取当前时段名称（使用通用接口）
    //+--------------------------------------------------------------
    string GetCurrentSession()
    {
        return TimeFilter_GetCurrentSession();
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

        // M6.3: 趋势反转检测使用 RegimeFilter
        TrendDirection trend = GetTrendState();
        if(trend == TREND_BEAR)
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

        // M6.3: 趋势反转检测使用 RegimeFilter
        TrendDirection trend = GetTrendState();
        if(trend == TREND_BULL)
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
        bool isLong = (type == SIGNAL_BUY);
        double structurePrice = isLong ? m_pullback_lh : m_pullback_hl;

        if(isLong)
        {
            sl = s.price - atr * TP_ATR_SL_Multi;
        }
        else
        {
            sl = s.price + atr * TP_ATR_SL_Multi;
        }

        // 确保 SL 符合最小距离要求
        double min_dist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
        if(isLong)
            sl = MathMin(sl, s.price - min_dist);
        else
            sl = MathMax(sl, s.price + min_dist);

        s.sl = NormalizeDouble(sl, _Digits);

        // 填充结构冷却所需信息（由 RiskPipeline 使用）
        s.atr = atr;
        s.structure_price = structurePrice;

        // 记录入场信息（用于出场逻辑）
        m_entry_price = s.price;
        m_initial_sl = s.sl;
        m_atr_at_entry = atr;
        m_entry_time = (int)TimeCurrent();
        ResetEntryState();

        // 初始化加仓管理器
        if(TP_EnableAddPosition)
        {
            // 使用 PositionSizer 相同的逻辑计算手数
            double equity = AccountInfoDouble(ACCOUNT_EQUITY);
            double risk_amount = equity * InpRiskPercent / 100.0;
            double tick_val = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
            double tick_sz = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
            double dist = MathAbs(s.price - s.sl);
            double points = dist / tick_sz;
            double loss_per_1lot = points * tick_val;
            
            double lot = 0.0;
            if(loss_per_1lot > 0)
            {
                lot = risk_amount / loss_per_1lot;
                double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
                double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
                double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
                if(lot_step > 0)
                    lot = MathFloor(lot / lot_step) * lot_step;
                lot = MathMax(minLot, MathMin(maxLot, lot));
            }
            
            m_add_manager.OnMainEntry(lot, s.price, atr, isLong);
        }

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
        
        // ===== v3.1: 每10根K线输出一次状态 =====
        // datetime current_time = iTime(_Symbol, _Period, 0);
        // static int bar_counter = 0;
        // bar_counter++;
        // bool should_output_stats = (bar_counter % 10 == 0);
        // if(should_output_stats)
        // {
        //     Print("[", Name(), "] ===== 过滤统计 =====");
        //     Print("  总检查: ", m_stat_total_checks);
        //     Print("  L1 趋势OK: ", m_stat_trend_ok, 
        //           " (", DoubleToString(100.0 * m_stat_trend_ok / MathMax(1, m_stat_total_checks), 1), "%)");
        //     Print("  L2 回撤OK: ", m_stat_pullback_ok,
        //           " (", DoubleToString(100.0 * m_stat_pullback_ok / MathMax(1, m_stat_trend_ok), 1), "%)");
        //     Print("  L3 回撤结束OK: ", m_stat_pullback_end_ok,
        //           " (", DoubleToString(100.0 * m_stat_pullback_end_ok / MathMax(1, m_stat_pullback_ok), 1), "%)");
        //     Print("  L4 结构突破OK: ", m_stat_structure_ok,
        //           " (", DoubleToString(100.0 * m_stat_structure_ok / MathMax(1, m_stat_pullback_end_ok), 1), "%)");
        //     Print("  当前趋势: ", EnumToString(m_trend_state));
        //     Print("  冷却器: ", (m_cooldown.IsActive() ? "ON" : "OFF"));
        // }
        
        // 检测平仓事件（用于冷却器快速失败检测）
        bool has_position = PositionSelect(_Symbol);
        double current_volume = has_position ? PositionGetDouble(POSITION_VOLUME) : 0.0;
        // Print("[", Name(), "] GenerateSignal: has_position=", has_position, " current_volume=", current_volume); // 减少日志噪音

        // 检测加仓是否执行成功（持仓量增加）
        if(m_add_signal_pending && has_position && current_volume > m_last_position_volume)
        {
            double volume_increase = current_volume - m_last_position_volume;
            // 检查增加的手数是否接近预期的加仓手数
            if(MathAbs(volume_increase - m_pending_add_lot) < 0.01 ||
               volume_increase >= m_pending_add_lot * 0.8)  // 允许一定误差
            {
                // 确认加仓执行
                m_add_manager.ConfirmAddExecution(m_pending_add_type, m_pending_add_lot, m_pending_add_price, m_pending_add_sl);
                Print("[", Name(), "] Add position confirmed. type=",
                      (m_pending_add_type == ADD_SIGNAL_FIRST ? "FIRST" : "SECOND"),
                      " lot=", m_pending_add_lot, " price=", m_pending_add_price);
                m_add_signal_pending = false;
                m_pending_add_type = ADD_SIGNAL_NONE;
            }
        }

        // 更新上次持仓量
        m_last_position_volume = current_volume;

        if(m_was_in_position && !has_position)
        {
            // 刚刚平仓
            OnPositionClosed();
        }
        m_was_in_position = has_position;

        bool longSig = LongSignal();
        bool shortSig = ShortSignal();
        bool exitSig = HasExitSignal();
        
        // M6.3: 获取趋势状态用于日志
        TrendDirection trend = GetTrendState();
        
        if(!has_position)  // 无持仓
        {
            if(longSig)
            {
                LogSignalDetails("BUY");
                FillSignal(signal, SIGNAL_BUY);
                Print("[", Name(), "] Long signal filled. price=", signal.price,
                      " sl=", signal.sl, " tp=", signal.tp);
                return signal;
            }
            if(shortSig)
            {
                LogSignalDetails("SELL");
                FillSignal(signal, SIGNAL_SELL);
                Print("[", Name(), "] Short signal filled. price=", signal.price,
                      " sl=", signal.sl, " tp=", signal.tp);
                return signal;
            }
        }
        else  // 有持仓
        {
            if(exitSig)
            {
                signal.type = SIGNAL_EXIT;
                FillSignal(signal, SIGNAL_EXIT);
                Print("[", Name(), "] Exit signal. trend=", EnumToString(trend));
                return signal;
            }
            
            // 加仓逻辑（有持仓时）
            if(TP_EnableAddPosition && !exitSig && !m_add_signal_pending)
            {
                AddPositionRequest addReq;
                AddSignalType addSignal = CheckAddSignal(addReq);
                if(addSignal != ADD_SIGNAL_NONE && addReq.volume > 0)
                {
                    // 设置加仓信号
                    bool isLong = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
                    signal.type = isLong ? SIGNAL_ADD_LONG : SIGNAL_ADD_SHORT;
                    signal.price = addReq.price;
                    signal.sl = addReq.sl;
                    signal.tp = 0;  // 加仓不设TP
                    signal.exit_volume = addReq.volume;  // 加仓手数
                    signal.confidence = 0.8;  // 加仓信号置信度
                    signal.source = Name();   // 设置来源
                    signal.time = TimeCurrent();

                    // 设置待处理状态（用于下次确认执行）
                    m_add_signal_pending = true;
                    m_pending_add_type = addSignal;
                    m_pending_add_lot = addReq.volume;
                    m_pending_add_price = addReq.price;
                    m_pending_add_sl = addReq.sl;
                    signal.time = TimeCurrent();
                    
                    Print("[", Name(), "] Add position signal. type=", 
                          (addSignal == ADD_SIGNAL_FIRST ? "FIRST" : "SECOND"),
                          " volume=", DoubleToString(addReq.volume, 2),
                          " price=", addReq.price,
                          " sl=", addReq.sl);
                    return signal;
                }
            }
            
            // 回撤失败记录：信号条件满足但无法加仓
            // 这表示市场又给出了一个好的入场点，但我们错过了
            if(TP_EnableAddPosition && (longSig || shortSig))
            {
                m_add_manager.RecordPullbackFail();
                // Print("[", Name(), "] Pullback entry missed. Recording pullback fail for add-position logic."); // 减少日志噪音
            }
        }
        
        signal.type = SIGNAL_NONE;
        return signal;
    }
    
    //+--------------------------------------------------------------
    //| 检测加仓信号（返回加仓请求详情）
    //+--------------------------------------------------------------
    AddSignalType CheckAddSignal(AddPositionRequest &addReq)
    {
        addReq.signalType = ADD_SIGNAL_NONE;
        addReq.volume = 0;
        
        if(!TP_EnableAddPosition || !PositionSelect(_Symbol))
            return ADD_SIGNAL_NONE;
            
        double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double atr = (ArraySize(m_buf_atr) >= 2) ? m_buf_atr[1] : 0;
        double price = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? bid : ask;
        
        // 获取账户风控参数
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double maxDailyLoss = MAX_DAILY_LOSS_PERCENT;
        
        // 获取加仓信号
        AddSignalType signalType = m_add_manager.GetAddSignal(price, atr, equity, balance, maxDailyLoss);
        
        if(signalType != ADD_SIGNAL_NONE)
        {
            // 计算加仓止损：使用 ATR 计算，与主仓类似
            bool isLong = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
            double sl;
            if(isLong)
                sl = price - atr * TP_ATR_SL_Multi;  // 多头：止损在入场价下方
            else
                sl = price + atr * TP_ATR_SL_Multi;  // 空头：止损在入场价上方
            
            // 构建加仓请求
            if(!m_add_manager.BuildAddRequest(addReq, signalType, price, sl))
            {
                return ADD_SIGNAL_NONE;
            }
        }
        
        return signalType;
    }
    
    //+--------------------------------------------------------------
    //| 仓位关闭回调（由EA层调用或自行检测）
    //+--------------------------------------------------------------
    void OnPositionClosed()
    {
        Print("[", Name(), "] Position closed event detected.");

        // 重置加仓管理器
        if(TP_EnableAddPosition)
        {
            m_add_manager.Reset();
            // 清除待处理的加仓状态
            m_add_signal_pending = false;
            m_pending_add_type = ADD_SIGNAL_NONE;
            m_pending_add_lot = 0.0;
            m_pending_add_price = 0.0;
            m_pending_add_sl = 0.0;
            m_last_position_volume = 0.0;
        }
    }

    //+--------------------------------------------------------------
    //| 获取最后平仓盈亏
    //+--------------------------------------------------------------
    double GetLastClosedProfit()
    {
        HistorySelect(0, TimeCurrent());
        int deals = HistoryDealsTotal();
        for(int i = deals - 1; i >= 0; i--)
        {
            ulong deal = HistoryDealGetTicket(i);
            if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol)
                continue;
            long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
            if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
                return HistoryDealGetDouble(deal, DEAL_PROFIT);
        }
        return 0.0;
    }
    
    //+--------------------------------------------------------------
    //| 获取最后平仓价格
    //+--------------------------------------------------------------
    double GetLastClosedPrice()
    {
        HistorySelect(0, TimeCurrent());
        int deals = HistoryDealsTotal();
        for(int i = deals - 1; i >= 0; i--)
        {
            ulong deal = HistoryDealGetTicket(i);
            if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol)
                continue;
            long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
            if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
                return HistoryDealGetDouble(deal, DEAL_PRICE);
        }
        return 0.0;
    }

    //+--------------------------------------------------------------
    //| 获取当前结构点价格（供 RiskPipeline 冷却解除判断使用）
    //| 返回：多头返回 pullback_lh，空头返回 pullback_hl
    //| M6.3: 使用 RegimeFilter 的趋势方向
    //+--------------------------------------------------------------
    double GetCurrentStructurePrice() const
    {
        TrendDirection trend = GetTrendState();
        if(trend == TREND_BULL)
            return m_pullback_lh;
        else if(trend == TREND_BEAR)
            return m_pullback_hl;
        return 0.0;
    }

    //+--------------------------------------------------------------
    //| 获取当前ATR
    //+--------------------------------------------------------------
    double GetCurrentATR() const
    {
        return (ArraySize(m_buf_atr) >= 2) ? m_buf_atr[1] : 0;
    }

    //+--------------------------------------------------------------
    //| 策略名称
    //+--------------------------------------------------------------
    string Name() override
    {
        return "TrendPullback";
    }

    //+--------------------------------------------------------------
    //| 日志输出
    //+--------------------------------------------------------------
    void LogSignalDetails(const string direction)
    {
        if(!TP_LogSignalDetails)
            return;
        
        MqlDateTime ts;
        TimeToStruct(TimeCurrent(), ts);
        
        double atr = (ArraySize(m_buf_atr) >= 2) ? m_buf_atr[1] : 0.0;
        double ema20 = (ArraySize(m_buf_ema20_ltf) >= 2) ? m_buf_ema20_ltf[1] : 0.0;
        TrendDirection trend = GetTrendState();
        
        Print("[TrendPullback] Signal ", direction,
              " time=", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
              " trend=", EnumToString(trend),
              " price=", DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits),
              " atr=", DoubleToString(atr, _Digits),
              " ema20=", DoubleToString(ema20, _Digits),
              " vwap=", DoubleToString(m_vwap_ltf, _Digits),
              " swing_high=", DoubleToString(m_swing_high, _Digits),
              " swing_low=", DoubleToString(m_swing_low, _Digits),
              " pullback_lh=", DoubleToString(m_pullback_lh, _Digits),
              " pullback_hl=", DoubleToString(m_pullback_hl, _Digits),
              " hour=", ts.hour);
    }
};

#endif // __STRATEGY_TREND_PULLBACK_MQH__
