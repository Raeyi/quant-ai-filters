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
    
    // 计算结果
    double  m_efficiency;
    double  m_false_breakout_rate;
    double  m_q_score;
    bool    m_is_tradable;
    
    // 价格历史 (用于效率计算)
    double  m_close_history[];
    double  m_high_history[];
    double  m_low_history[];
    int     m_history_count;
    
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
        m_efficiency(0.5),
        m_false_breakout_rate(0.0),
        m_q_score(0.5),
        m_is_tradable(true),
        m_history_count(0)
    {
        ArraySetAsSeries(m_close_history, true);
        ArraySetAsSeries(m_high_history, true);
        ArraySetAsSeries(m_low_history, true);
        ArrayResize(m_close_history, 100);
        ArrayResize(m_high_history, 100);
        ArrayResize(m_low_history, 100);
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
    }
    
    //+--------------------------------------------------------------
    //| 更新价格数据
    //+--------------------------------------------------------------
    void UpdatePrices(double close, double high, double low)
    {
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
        double net_change = MathAbs(m_close_history[0] - m_close_history[m_efficiency_period - 1]);
        
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
    bool Update(double close, double high, double low)
    {
        // 更新价格历史
        UpdatePrices(close, high, low);
        
        // 计算效率
        m_efficiency = CalculateEfficiency();
        
        // 计算假突破率
        m_false_breakout_rate = CalculateFalseBreakoutRate();
        
        // 计算 Q_score
        // Q = 0.4 * efficiency + 0.3 * (1 - false_breakout_rate) + 0.3 * 0.5
        m_q_score = 0.4 * m_efficiency + 
                    0.3 * (1.0 - m_false_breakout_rate) + 
                    0.3 * 0.5;
        
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
    //| 获取 Q_score
    //+--------------------------------------------------------------
    double GetQScore() const { return m_q_score; }
    
    //+--------------------------------------------------------------
    //| 是否可交易
    //+--------------------------------------------------------------
    bool IsTradable() const { return m_is_tradable; }
};

#endif // __MARKET_QUALITY_MQH__
