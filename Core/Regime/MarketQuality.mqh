//+------------------------------------------------------------------+
//|                   Core/Regime/MarketQuality.mqh                  |
//|                   市场质量计算                                     |
//+------------------------------------------------------------------+
#ifndef __MARKET_QUALITY_MQH__
#define __MARKET_QUALITY_MQH__

#include "RegimeTypes.mqh"

//+------------------------------------------------------------------+
//| 市场质量参数                                                       |
//+------------------------------------------------------------------+
input group "========== 市场质量设置 =========="
input int     MQ_Efficiency_Period = 20;       // 效率计算窗口
input int     MQ_Breakout_Lookback = 5;        // 突破回看周期
input double  MQ_Breakout_Threshold = 0.3;     // 假突破阈值
input int     MQ_False_Breakout_Window = 30;   // 假突破率窗口
input double  MQ_Q_Score_Threshold = 0.5;      // Q_score 阈值
input double  MQ_Efficiency_Baseline = 0.10;   // 效率基准值（震荡市正常水平）
input double  MQ_FBR_Baseline = 0.40;          // 假突破率基准值（震荡市正常水平）
input double  MQ_ADX_Baseline = 25.0;          // ADX 基准值（趋势分界线）
input double  MQ_Weight_Eff = 0.25;            // 效率权重
input double  MQ_Weight_FBR = 0.25;            // 假突破率权重
input double  MQ_Weight_ADX = 0.20;            // ADX 权重

//+------------------------------------------------------------------+
//| 市场质量类                                                        |
//+------------------------------------------------------------------+
class CMarketQuality
{
private:
    // 参数
    int     m_efficiency_period;
    int     m_breakout_lookback;
    double  m_breakout_threshold;
    int     m_false_breakout_window;
    double  m_q_score_threshold;
    double  m_efficiency_baseline;
    double  m_fbr_baseline;
    double  m_adx_baseline;
    double  m_weight_eff;
    double  m_weight_fbr;
    double  m_weight_adx;
    
    // 计算结果
    double  m_efficiency;
    double  m_false_breakout_rate;
    double  m_adx;
    double  m_q_score;
    bool    m_is_tradable;
    
    // 价格历史 (用于效率计算)
    double  m_close_history[];
    double  m_high_history[];
    double  m_low_history[];
    int     m_history_count;
    datetime m_last_bar_time;  // 记录最后更新的K线时间
    
public:
    //+--------------------------------------------------------------
    //| 构造函数
    //+--------------------------------------------------------------
    CMarketQuality() :
        m_efficiency_period(20),
        m_breakout_lookback(5),
        m_breakout_threshold(0.3),
        m_false_breakout_window(30),
        m_q_score_threshold(0.5),
        m_efficiency_baseline(0.15),
        m_fbr_baseline(0.50),
        m_adx_baseline(25.0),
        m_weight_eff(0.25),
        m_weight_fbr(0.25),
        m_weight_adx(0.20),
        m_efficiency(0.5),
        m_false_breakout_rate(0.0),
        m_adx(25.0),
        m_q_score(0.5),
        m_is_tradable(true),
        m_history_count(0),
        m_last_bar_time(0)
    {
        // 先 Resize，再 SetAsSeries（顺序很重要！）
        ArrayResize(m_close_history, 100);
        ArrayResize(m_high_history, 100);
        ArrayResize(m_low_history, 100);
        ArraySetAsSeries(m_close_history, true);
        ArraySetAsSeries(m_high_history, true);
        ArraySetAsSeries(m_low_history, true);
    }
    
    //+--------------------------------------------------------------
    //| 初始化
    //+--------------------------------------------------------------
    void Init()
    {
        m_efficiency_period = MQ_Efficiency_Period;
        m_breakout_lookback = MQ_Breakout_Lookback;
        m_breakout_threshold = MQ_Breakout_Threshold;
        m_false_breakout_window = MQ_False_Breakout_Window;
        m_q_score_threshold = MQ_Q_Score_Threshold;
        m_efficiency_baseline = MQ_Efficiency_Baseline;
        m_fbr_baseline = MQ_FBR_Baseline;
        m_adx_baseline = MQ_ADX_Baseline;
        m_weight_eff = MQ_Weight_Eff;
        m_weight_fbr = MQ_Weight_FBR;
        m_weight_adx = MQ_Weight_ADX;
        
        // 预填充历史数据（从K线1开始往回）
        PreloadHistory();
    }
    
    //+--------------------------------------------------------------
    //| 预填充历史数据
    //+--------------------------------------------------------------
    void PreloadHistory()
    {
        int bars_needed = (int)ArraySize(m_close_history);
        int available = iBars(_Symbol, _Period);
        
        if(available < bars_needed)
            bars_needed = available;
        
        for(int i = bars_needed - 1; i >= 1; i--)
        {
            double close = iClose(_Symbol, _Period, i);
            double high = iHigh(_Symbol, _Period, i);
            double low = iLow(_Symbol, _Period, i);
            datetime bar_time = iTime(_Symbol, _Period, i);
            
            // 直接填充，不检测重复
            if(m_history_count < ArraySize(m_close_history))
                m_history_count++;
            
            // 移动数据
            for(int j = m_history_count - 1; j > 0; j--)
            {
                m_close_history[j] = m_close_history[j-1];
                m_high_history[j] = m_high_history[j-1];
                m_low_history[j] = m_low_history[j-1];
            }
            m_close_history[0] = close;
            m_high_history[0] = high;
            m_low_history[0] = low;
            m_last_bar_time = bar_time;
        }
        
        Print("[MarketQuality] Preloaded history_count=", m_history_count);
    }
    
    //+--------------------------------------------------------------
    //| 更新价格数据
    //+--------------------------------------------------------------
    void UpdatePrices(double close, double high, double low, datetime bar_time)
    {
        // 用时间戳检测新K线，避免重复添加
        if(bar_time == m_last_bar_time)
            return;
        
        m_last_bar_time = bar_time;
        
        // 添加到历史数组
        if(m_history_count < ArraySize(m_close_history))
            m_history_count++;
        
        // 移动数据
        for(int i = m_history_count - 1; i > 0; i--)
        {
            m_close_history[i] = m_close_history[i-1];
            m_high_history[i] = m_high_history[i-1];
            m_low_history[i] = m_low_history[i-1];
        }
        m_close_history[0] = close;
        m_high_history[0] = high;
        m_low_history[0] = low;
    }
    
    //+--------------------------------------------------------------
    //| 计算市场效率
    //+--------------------------------------------------------------
    double CalculateEfficiency()
    {
        if(m_history_count < m_efficiency_period)
            return 0.5;
        
        // 净变动
        double close0 = m_close_history[0];
        double closeN = m_close_history[m_efficiency_period - 1];
        double net_change = MathAbs(close0 - closeN);
        
        // 总波幅
        double total_range = 0.0;
        for(int i = 0; i < m_efficiency_period; i++)
        {
            total_range += m_high_history[i] - m_low_history[i];
        }
        
        if(total_range < 0.0001)
            return 0.5;
        
        return MathMin(net_change / total_range, 1.0);
    }
    
    //+--------------------------------------------------------------
    //| 计算假突破率
    //+--------------------------------------------------------------
    double CalculateFalseBreakoutRate()
    {
        if(m_history_count < m_breakout_lookback + 5)
            return 0.0;
        
        int total_breakouts = 0;
        int false_breakouts = 0;
        
        int lookback = MathMin(m_false_breakout_window, m_history_count - m_breakout_lookback - 1);
        
        for(int i = 1; i < lookback; i++)
        {
            // 计算前期高低点
            double prev_high = m_high_history[i + 1];
            double prev_low = m_low_history[i + 1];
            
            for(int j = 2; j <= m_breakout_lookback; j++)
            {
                if(m_high_history[i + j] > prev_high)
                    prev_high = m_high_history[i + j];
                if(m_low_history[i + j] < prev_low)
                    prev_low = m_low_history[i + j];
            }
            
            // 检测突破
            bool breakout_up = m_high_history[i] > prev_high;
            bool breakout_down = m_low_history[i] < prev_low;
            
            if(breakout_up || breakout_down)
            {
                total_breakouts++;
                
                // 检测假突破
                if(breakout_up && m_close_history[i] < prev_high)
                    false_breakouts++;
                if(breakout_down && m_close_history[i] > prev_low)
                    false_breakouts++;
            }
        }
        
        if(total_breakouts == 0)
            return 0.0;
        
        return (double)false_breakouts / total_breakouts;
    }
    
    //+--------------------------------------------------------------
    //| 更新计算
    //+--------------------------------------------------------------
    bool Update(double close, double high, double low, double adx = 25.0, datetime bar_time = 0)
    {
        // 更新价格历史（用时间戳检测新K线）
        UpdatePrices(close, high, low, bar_time);
        
        // 计算效率
        m_efficiency = CalculateEfficiency();
        
        // 计算假突破率
        m_false_breakout_rate = CalculateFalseBreakoutRate();
        
        // 存储 ADX
        m_adx = adx;
        
        // 计算 Q_score（新公式：eff + fbr + adx 三维度）
        // Q = 0.5 + 效率贡献 + 假突破惩罚 + ADX贡献
        double eff_score = m_weight_eff * (m_efficiency / m_efficiency_baseline - 1.0);
        double fbr_score = m_weight_fbr * (m_fbr_baseline - m_false_breakout_rate) / m_fbr_baseline;
        
        // ADX 贡献：高于基准（趋势市）加分，低于基准（震荡市）不加分不减分
        // 归一化：ADX 25 → 0, ADX 40 → 0.6, ADX 50 → 1.0
        double adx_normalized = MathMax(0.0, (m_adx - m_adx_baseline) / 25.0);
        adx_normalized = MathMin(1.0, adx_normalized);
        double adx_score = m_weight_adx * adx_normalized;
        
        m_q_score = MathMax(0.1, MathMin(0.9, 0.5 + eff_score + fbr_score + adx_score));
        
        // 判断是否可交易
        m_is_tradable = (m_q_score >= m_q_score_threshold);
        
        return true;
    }
    
    //+--------------------------------------------------------------
    //| 获取效率
    //+--------------------------------------------------------------
    double GetEfficiency() const { return m_efficiency; }
    
    //+--------------------------------------------------------------
    //| 获取假突破率
    //+--------------------------------------------------------------
    double GetFalseBreakoutRate() const { return m_false_breakout_rate; }
    
    //+--------------------------------------------------------------
    //| 获取 ADX
    //+--------------------------------------------------------------
    double GetADX() const { return m_adx; }
    
    //+--------------------------------------------------------------
    //| 获取 Q_score
    //+--------------------------------------------------------------
    double GetQScore() const { return m_q_score; }
    
    //+--------------------------------------------------------------
    //| 是否可交易
    //+--------------------------------------------------------------
    bool IsTradable() const { return m_is_tradable; }
};

#endif // __MARKET_QUALITY_MQH__
