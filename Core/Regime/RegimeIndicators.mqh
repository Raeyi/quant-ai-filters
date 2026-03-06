//+------------------------------------------------------------------+
//|                 Core/Regime/RegimeIndicators.mqh                 |
//|                   Regime 指标计算                                  |
//+------------------------------------------------------------------+
#ifndef __REGIME_INDICATORS_MQH__
#define __REGIME_INDICATORS_MQH__

#include "RegimeTypes.mqh"

//+------------------------------------------------------------------+
//| Regime 指标参数                                                    |
//+------------------------------------------------------------------+
input group "========== Regime 指标设置 =========="
input int     Regime_ADX_Period = 14;            // ADX 周期
input double  Regime_ADX_Trend_Threshold = 25.0; // ADX 趋势阈值
input double  Regime_DI_Threshold = 12.0;         // DI差值趋势阈值（10~18）
input double  Regime_DI_ExitThreshold  = 7.5;      // DI差值趋势退出阈值（5~10）
input int     Regime_ATR_Period = 14;            // ATR 周期
input int     Regime_Vol_Lookback = 100;         // 波动率百分位窗口
input double  Regime_Vol_Low_Percentile = 25.0;  // 低波动百分位
input double  Regime_Vol_High_Percentile = 75.0; // 高波动百分位

//+------------------------------------------------------------------+
//| Regime 指标类                                                      |
//+------------------------------------------------------------------+
class CRegimeIndicators
{
private:
    // 指标句柄
    int     m_adx_handle;
    int     m_atr_handle;
    int     m_plus_di_handle;
    int     m_minus_di_handle;
    
    // 指标缓冲区
    double  m_adx_buffer[];
    double  m_atr_buffer[];
    double  m_plus_di_buffer[];
    double  m_minus_di_buffer[];
    
    // 参数
    int     m_adx_period;
    int     m_atr_period;
    int     m_vol_lookback;
    double  m_vol_low_pct;
    double  m_vol_high_pct;
    
    // 计算结果缓存
    double  m_trend_strength;
    double  m_volatility;
    VolatilityState m_vol_state;
    TrendDirection  m_trend_direction;
    
    // 波动率历史 (用于百分位计算)
    double  m_vol_history[];
    int     m_vol_history_count;
    
public:
    //+--------------------------------------------------------------
    //| 构造函数
    //+--------------------------------------------------------------
    CRegimeIndicators() :
        m_adx_handle(INVALID_HANDLE),
        m_atr_handle(INVALID_HANDLE),
        m_plus_di_handle(INVALID_HANDLE),
        m_minus_di_handle(INVALID_HANDLE),
        m_adx_period(14),
        m_atr_period(14),
        m_vol_lookback(200),
        m_vol_low_pct(25.0),
        m_vol_high_pct(75.0),
        m_trend_strength(0.0),
        m_volatility(0.0),
        m_vol_state(VOL_NORMAL),
        m_trend_direction(TREND_NONE),
        m_vol_history_count(0)
    {
        ArraySetAsSeries(m_adx_buffer, true);
        ArraySetAsSeries(m_atr_buffer, true);
        ArraySetAsSeries(m_plus_di_buffer, true);
        ArraySetAsSeries(m_minus_di_buffer, true);
        ArraySetAsSeries(m_vol_history, true);
        ArrayResize(m_vol_history, 200);
    }
    
    //+--------------------------------------------------------------
    //| 析构函数
    //+--------------------------------------------------------------
    ~CRegimeIndicators()
    {
        if(m_adx_handle != INVALID_HANDLE)
            IndicatorRelease(m_adx_handle);
        if(m_atr_handle != INVALID_HANDLE)
            IndicatorRelease(m_atr_handle);
        if(m_plus_di_handle != INVALID_HANDLE)
            IndicatorRelease(m_plus_di_handle);
        if(m_minus_di_handle != INVALID_HANDLE)
            IndicatorRelease(m_minus_di_handle);
    }
    
    //+--------------------------------------------------------------
    //| 初始化
    //+--------------------------------------------------------------
    bool Init(string symbol, ENUM_TIMEFRAMES timeframe)
    {
        m_adx_period = Regime_ADX_Period;
        m_atr_period = Regime_ATR_Period;
        m_vol_lookback = Regime_Vol_Lookback;
        m_vol_low_pct = Regime_Vol_Low_Percentile;
        m_vol_high_pct = Regime_Vol_High_Percentile;
        
        // 创建 ADX 指标
        m_adx_handle = iADX(symbol, timeframe, m_adx_period);
        if(m_adx_handle == INVALID_HANDLE)
        {
            Print("[RegimeIndicators] Failed to create ADX indicator");
            return false;
        }
        
        // 创建 ATR 指标
        m_atr_handle = iATR(symbol, timeframe, m_atr_period);
        if(m_atr_handle == INVALID_HANDLE)
        {
            Print("[RegimeIndicators] Failed to create ATR indicator");
            return false;
        }
        
        // 创建 +DI 和 -DI 指标
        m_plus_di_handle = iADX(symbol, timeframe, m_adx_period);
        m_minus_di_handle = iADX(symbol, timeframe, m_adx_period);
        
        return true;
    }
    
    //+--------------------------------------------------------------
    //| 更新指标数据
    //+--------------------------------------------------------------
    bool Update()
    {
        // 复制 ADX 数据
        if(CopyBuffer(m_adx_handle, 0, 0, 3, m_adx_buffer) < 3)
            return false;
        
        // 复制 ATR 数据
        if(CopyBuffer(m_atr_handle, 0, 0, 3, m_atr_buffer) < 3)
            return false;
        
        // 复制 +DI 和 -DI
        if(CopyBuffer(m_plus_di_handle, 1, 0, 3, m_plus_di_buffer) < 3)
            return false;
        if(CopyBuffer(m_minus_di_handle, 2, 0, 3, m_minus_di_buffer) < 3)
            return false;
        
        // 计算趋势强度
        m_trend_strength = CalculateTrendStrength(m_adx_buffer[0]);
        
        // 计算波动率状态
        UpdateVolatilityHistory(m_atr_buffer[0]);
        m_volatility = m_atr_buffer[0];
        m_vol_state = ClassifyVolatility();
        
        // 计算趋势方向
        double di_diff = m_plus_di_buffer[0] - m_minus_di_buffer[0];
        TrendDirection prev_direction = m_trend_direction;

        if(prev_direction == TREND_BULL)
        {
            // 已经在BULL，只有明显走弱才退出
            if(di_diff < Regime_DI_ExitThreshold || m_trend_strength < 0.30)
                m_trend_direction = TREND_NONE;
            else
                m_trend_direction = TREND_BULL;
        }
        else if(prev_direction == TREND_BEAR)
        {
            if(di_diff > -Regime_DI_ExitThreshold || m_trend_strength < 0.30)
                m_trend_direction = TREND_NONE;
            else
                m_trend_direction = TREND_BEAR;
        }
        else // 当前是 NONE
        {
            // 只有足够强的信号才进入趋势
            if(m_trend_strength > 0.35 && di_diff > Regime_DI_Threshold)
                m_trend_direction = TREND_BULL;
            else if(m_trend_strength > 0.35 && di_diff < -Regime_DI_Threshold)
                m_trend_direction = TREND_BEAR;
            else
                m_trend_direction = TREND_NONE;
        }
            
        return true;
    }
    
    //+--------------------------------------------------------------
    //| 计算趋势强度
    //+--------------------------------------------------------------
    double CalculateTrendStrength(double adx)
    {
        // 分段线性映射 ADX 到 [0, 1]
        if(adx < 20)
            return adx / 100.0;  // 0 ~ 0.2
        else if(adx < 25)
            return 0.2 + (adx - 20) * 0.04;  // 0.2 ~ 0.4
        else if(adx < 40)
            return 0.4 + (adx - 25) * 0.02;  // 0.4 ~ 0.7
        else
            return MathMin(0.7 + (adx - 40) * 0.01, 1.0);  // 0.7 ~ 1.0
    }
    
    //+--------------------------------------------------------------
    //| 更新波动率历史
    //+--------------------------------------------------------------
    void UpdateVolatilityHistory(double atr)
    {
        // 添加到历史数组
        if(m_vol_history_count < ArraySize(m_vol_history))
            m_vol_history_count++;
        
        // 移动数据
        for(int i = m_vol_history_count - 1; i > 0; i--)
        {
            m_vol_history[i] = m_vol_history[i-1];
        }
        m_vol_history[0] = atr;
    }
    
    //+--------------------------------------------------------------
    //| 分类波动率状态
    //+--------------------------------------------------------------
    VolatilityState ClassifyVolatility()
    {
        if(m_vol_history_count < 50)
            return VOL_NORMAL;
        
        // 计算当前 ATR 的百分位
        int count = MathMin(m_vol_history_count, m_vol_lookback);
        int lower_count = 0;
        
        for(int i = 0; i < count; i++)
        {
            if(m_vol_history[i] < m_volatility)
                lower_count++;
        }
        
        double percentile = (double)lower_count / count * 100.0;
        
        if(percentile < m_vol_low_pct)
            return VOL_LOW;
        else if(percentile > m_vol_high_pct)
            return VOL_HIGH;
        else
            return VOL_NORMAL;
    }
    
    //+--------------------------------------------------------------
    //| 获取趋势强度
    //+--------------------------------------------------------------
    double GetTrendStrength() const { return m_trend_strength; }
    
    //+--------------------------------------------------------------
    //| 获取波动率
    //+--------------------------------------------------------------
    double GetVolatility() const { return m_volatility; }
    
    //+--------------------------------------------------------------
    //| 获取波动率状态
    //+--------------------------------------------------------------
    VolatilityState GetVolatilityState() const { return m_vol_state; }
    
    //+--------------------------------------------------------------
    //| 获取趋势方向
    //+--------------------------------------------------------------
    TrendDirection GetTrendDirection() const { return m_trend_direction; }
    
    //+--------------------------------------------------------------
    //| 获取 ADX 值
    //+--------------------------------------------------------------
    double GetADX() const { return m_adx_buffer[0]; }
    
    //+--------------------------------------------------------------
    //| 判断市场状态类型
    //+--------------------------------------------------------------
    RegimeType GetRegimeType() const
    {
        return (m_trend_strength > 0.4) ? REGIME_TREND : REGIME_RANGE;
    }
};

#endif // __REGIME_INDICATORS_MQH__
