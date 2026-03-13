//+------------------------------------------------------------------+
//|                    Core/Regime/RegimeFilter.mqh                  |
//|                    Regime 过滤器主类                               |
//+------------------------------------------------------------------+
#ifndef __REGIME_FILTER_MQH__
#define __REGIME_FILTER_MQH__

#include "RegimeTypes.mqh"
#include "RegimeIndicators.mqh"
#include "MarketQuality.mqh"
#include "SessionQuality.mqh"  // M7: 时段质量评估
#include "EventFilter.mqh"     // M7: 事件过滤

//+------------------------------------------------------------------+
//| Regime Filter 参数                                                 |
//+------------------------------------------------------------------+
input group "========== Regime Filter 设置 =========="
input double  RF_Q_Score_Standby = 0.30;    // Q_score STANDBY 阈值
input double  RF_Q_Score_Active = 0.40;     // Q_score ACTIVE 阈值
input int     RF_Transition_Bars = 3;       // 过渡期 K 线数
input double  RF_Hysteresis = 0.05;         // 滞后阈值
input bool    RF_Enable_SubType = true;     // 启用 Sub-Type 分类

//+------------------------------------------------------------------+
//| Regime Filter 类                                                   |
//+------------------------------------------------------------------+
class CRegimeFilter
{
private:
    // 组件
    CRegimeIndicators m_indicators;
    CMarketQuality    m_quality;
    CSessionQuality   m_session;  // M7: 时段质量
    CEventFilter      m_event;    // M7: 事件过滤
    
    // 参数
    double  m_q_score_standby;
    double  m_q_score_active;
    int     m_transition_bars;
    double  m_hysteresis;
    bool    m_enable_subtype;
    
    // 状态跟踪
    RegimeState     m_current_state;
    int             m_transition_counter;
    double          m_last_q_score;
    datetime        m_last_subtype_bar_time;  // 上次更新sub_type的K线时间

    // 当前快照
    RegimeSnapshot  m_snapshot;
    
    // 状态转换历史
    int             m_state_history_count;
    
public:
    //+--------------------------------------------------------------
    //| 构造函数
    //+--------------------------------------------------------------
    CRegimeFilter() :
        m_q_score_standby(0.5),
        m_q_score_active(0.6),
        m_transition_bars(3),
        m_hysteresis(0.05),
        m_enable_subtype(true),
        m_current_state(STATE_STANDBY),
        m_transition_counter(0),
        m_last_q_score(0.5),
        m_last_subtype_bar_time(0),
        m_state_history_count(0)
    {
    }
    
    //+--------------------------------------------------------------
    //| 初始化
    //+--------------------------------------------------------------
    bool Init(string symbol, ENUM_TIMEFRAMES timeframe)
    {
        // 加载参数
        m_q_score_standby = RF_Q_Score_Standby;
        m_q_score_active = RF_Q_Score_Active;
        m_transition_bars = RF_Transition_Bars;
        m_hysteresis = RF_Hysteresis;
        m_enable_subtype = RF_Enable_SubType;
        
        // 初始化指标
        if(!m_indicators.Init(symbol, timeframe))
        {
            Print("[RegimeFilter] Failed to initialize indicators");
            return false;
        }
        
        // 初始化质量计算器
        m_quality.Init();
        
        Print("[RegimeFilter] Initialized successfully");
        return true;
    }
    
    //+--------------------------------------------------------------
    //| 更新
    //+--------------------------------------------------------------
    bool Update(double close, double high, double low)
    {
        // 更新指标
        if(!m_indicators.Update())
            return false;
        
        // 获取 ADX 值
        double adx = m_indicators.GetADX();
        
        // 获取K线时间（用于检测新K线）
        datetime bar_time = iTime(_Symbol, _Period, 1);
        
        // 更新质量（传入 ADX 和 K线时间）
        if(!m_quality.Update(close, high, low, adx, bar_time))
            return false;
        
        // M7: 更新时段质量
        m_session.Update();
        
        // M7: 更新事件过滤
        double tick_volume = (double)iVolume(_Symbol, PERIOD_CURRENT, 0);
        m_event.Update(tick_volume);
        
        // 计算 Q_score（基础值）
        double q_score = m_quality.GetQScore();
        
        // M7: 应用时段权重调整 Q_score
        if(SQ_Enable)
        {
            double session_weight = m_session.GetSessionWeight();
            q_score = q_score * session_weight;
            
            // 低流动性时段强制 STANDBY
            if(!m_session.IsTradable())
            {
                m_current_state = STATE_STANDBY;
            }
        }
        
        // M7: 应用事件过滤
        if(EF_Enable && !m_event.IsTradable())
        {
            // 新闻窗口或流动性异常时强制 STANDBY
            m_current_state = STATE_STANDBY;
            q_score = q_score * m_event.GetRiskWeight();
        }
        
        // 更新状态
        UpdateState(q_score);
        
        // 更新快照
        UpdateSnapshot();
        
        return true;
    }
    
    //+--------------------------------------------------------------
    //| 更新状态
    //+--------------------------------------------------------------
    void UpdateState(double q_score)
    {
        m_last_q_score = q_score;
        
        if(m_current_state == STATE_ACTIVE)
        {
            // 从 ACTIVE 转 STANDBY
            if(q_score < m_q_score_standby - m_hysteresis)
            {
                m_transition_counter++;
                if(m_transition_counter >= m_transition_bars)
                {
                    m_current_state = STATE_STANDBY;
                    m_transition_counter = 0;
                }
                else
                {
                    m_current_state = STATE_TRANSITION;
                }
            }
            else
            {
                m_transition_counter = 0;
            }
        }
        else if(m_current_state == STATE_STANDBY)
        {
            // 从 STANDBY 转 ACTIVE
            if(q_score > m_q_score_active + m_hysteresis)
            {
                m_transition_counter++;
                if(m_transition_counter >= m_transition_bars)
                {
                    m_current_state = STATE_ACTIVE;
                    m_transition_counter = 0;
                }
                else
                {
                    m_current_state = STATE_TRANSITION;
                }
            }
            else
            {
                m_transition_counter = 0;
            }
        }
        else // TRANSITION
        {
            if(q_score > m_q_score_active)
            {
                m_transition_counter++;
                if(m_transition_counter >= m_transition_bars)
                {
                    m_current_state = STATE_ACTIVE;
                    m_transition_counter = 0;
                }
            }
            else if(q_score < m_q_score_standby)
            {
                m_transition_counter++;
                if(m_transition_counter >= m_transition_bars)
                {
                    m_current_state = STATE_STANDBY;
                    m_transition_counter = 0;
                }
            }
            else
            {
                m_transition_counter = 0;
            }
        }
    }
    
    //+--------------------------------------------------------------
    //| 更新快照
    //+--------------------------------------------------------------
    void UpdateSnapshot()
    {
        // 基础信息
        m_snapshot.state = m_current_state;
        m_snapshot.regime_type = m_indicators.GetRegimeType();
        m_snapshot.volatility_state = m_indicators.GetVolatilityState();
        m_snapshot.trend_direction = m_indicators.GetTrendDirection();
        m_snapshot.trend_strength = m_indicators.GetTrendStrength();
        
        // 质量信息
        m_snapshot.efficiency = m_quality.GetEfficiency();
        m_snapshot.false_breakout_rate = m_quality.GetFalseBreakoutRate();
        m_snapshot.q_score = m_quality.GetQScore();

        // Sub-Type 分类（只在新K线时更新，保持单根K线内稳定）
        if(m_enable_subtype)
        {
            datetime current_bar_time = iTime(_Symbol, _Period, 1);
            if(current_bar_time != m_last_subtype_bar_time)
            {
                m_snapshot.sub_type = ClassifySubType();
                m_last_subtype_bar_time = current_bar_time;
                ApplySubTypeParams();
            }
        }
    }
    
    //+--------------------------------------------------------------
    //| 分类 Sub-Type
    //+--------------------------------------------------------------
    RegimeSubType ClassifySubType()
    {
        double eff = m_snapshot.efficiency;
        double fbr = m_snapshot.false_breakout_rate;
        double ts = m_snapshot.trend_strength;
        VolatilityState vol = m_snapshot.volatility_state;
        RegimeType regime = m_snapshot.regime_type;
        
        // 趋势类
        if(regime == REGIME_TREND)
        {
            if(vol == VOL_HIGH)
            {
                if(eff < 0.3)
                    return SUBTYPE_TVA_EMOTION;  // 情绪脉冲
                else if(eff > 0.5)
                    return SUBTYPE_TVB_TREND;    // 真趋势
            }
            return SUBTYPE_TN_MILD;  // 温和趋势
        }
        // 震荡类
        else
        {
            if(vol == VOL_HIGH)
            {
                if(fbr > 0.35)
                    return SUBTYPE_RVB_FALSE;    // 假突破密集
                return SUBTYPE_RVA_NEWS;         // 消息震荡
            }
            else if(vol == VOL_LOW)
            {
                return SUBTYPE_RL_LOW;           // 低波动震荡
            }
            return SUBTYPE_RN_NORMAL;            // 正常震荡
        }
    }
    
    //+--------------------------------------------------------------
    //| 应用 Sub-Type 参数
    //+--------------------------------------------------------------
    void ApplySubTypeParams()
    {
        switch(m_snapshot.sub_type)
        {   
            // 真趋势
            case SUBTYPE_TVB_TREND:
                m_snapshot.scale_multiplier = 1.2;
                m_snapshot.sl_multiplier = 1.5;
                m_snapshot.tp_multiplier = 2.0;
                m_snapshot.max_positions = 2;
                m_snapshot.risk_level = RISK_MEDIUM;
                break;
            // 情绪脉冲
            case SUBTYPE_TVA_EMOTION:
                m_snapshot.scale_multiplier = 0.6;
                m_snapshot.sl_multiplier = 0.8;
                m_snapshot.tp_multiplier = 1.0;
                m_snapshot.max_positions = 1;
                m_snapshot.risk_level = RISK_HIGH;
                break;
            // 温和趋势
            case SUBTYPE_TN_MILD:
                m_snapshot.scale_multiplier = 0.8;
                m_snapshot.sl_multiplier = 1.2;
                m_snapshot.tp_multiplier = 1.5;
                m_snapshot.max_positions = 2;
                m_snapshot.risk_level = RISK_MEDIUM;
                break;
            // 正常震荡
            case SUBTYPE_RN_NORMAL:
                m_snapshot.scale_multiplier = 1.0;
                m_snapshot.sl_multiplier = 1.0;
                m_snapshot.tp_multiplier = 1.0;
                m_snapshot.max_positions = 2;
                m_snapshot.risk_level = RISK_LOW;
                break;
            // 假突破密集
            case SUBTYPE_RVB_FALSE:
                m_snapshot.scale_multiplier = 0.5;
                m_snapshot.sl_multiplier = 1.2;
                m_snapshot.tp_multiplier = 0.8;
                m_snapshot.max_positions = 1;
                m_snapshot.risk_level = RISK_MEDIUM;
                break;
            // 消息震荡
            case SUBTYPE_RVA_NEWS:
                m_snapshot.scale_multiplier = 0.2;
                m_snapshot.sl_multiplier = 1.5;
                m_snapshot.tp_multiplier = 0.5;
                m_snapshot.max_positions = 1;
                m_snapshot.risk_level = RISK_EXTREME;
                break;
            // 低波动震荡
            case SUBTYPE_RL_LOW:
                m_snapshot.scale_multiplier = 0.3;
                m_snapshot.sl_multiplier = 0.8;
                m_snapshot.tp_multiplier = 0.6;
                m_snapshot.max_positions = 1;
                m_snapshot.risk_level = RISK_LOW;
                break;
            // 未知类型
            default:
                m_snapshot.scale_multiplier = 0.5;
                m_snapshot.sl_multiplier = 1.0;
                m_snapshot.tp_multiplier = 1.0;
                m_snapshot.max_positions = 1;
                m_snapshot.risk_level = RISK_MEDIUM;
                break;
        }
    }
    
    //+--------------------------------------------------------------
    //| 获取快照
    //+--------------------------------------------------------------
    RegimeSnapshot GetSnapshot() const { return m_snapshot; }
    
    //+--------------------------------------------------------------
    //| 获取当前状态
    //+--------------------------------------------------------------
    RegimeState GetState() const { return m_current_state; }
    
    //+--------------------------------------------------------------
    //| 是否可交易
    //+--------------------------------------------------------------
    bool IsTradable() const { return m_current_state == STATE_ACTIVE; }
    
    //+--------------------------------------------------------------
    //| 获取 Q_score
    //+--------------------------------------------------------------
    double GetQScore() const { return m_snapshot.q_score; }
    
    //+--------------------------------------------------------------
    //| 获取趋势方向
    //+--------------------------------------------------------------
    TrendDirection GetTrendDirection() const { return m_snapshot.trend_direction; }
    
    //+--------------------------------------------------------------
    //| 获取波动率状态
    //+--------------------------------------------------------------
    VolatilityState GetVolatilityState() const { return m_snapshot.volatility_state; }
    
    //+--------------------------------------------------------------
    //| M7: 获取时段类型
    //+--------------------------------------------------------------
    ExtendedSessionType GetSessionType() const { return m_session.GetCurrentSession(); }
    
    //+--------------------------------------------------------------
    //| M7: 获取时段权重
    //+--------------------------------------------------------------
    double GetSessionWeight() const { return m_session.GetSessionWeight(); }
    
    //+--------------------------------------------------------------
    //| M7: 是否可交易时段
    //+--------------------------------------------------------------
    bool IsSessionTradable() const { return m_session.IsTradable(); }
    
    //+--------------------------------------------------------------
    //| M7: 是否在新闻窗口
    //+--------------------------------------------------------------
    bool IsInNewsWindow() const { return m_event.IsInNewsWindow(); }
    
    //+--------------------------------------------------------------
    //| M7: 是否有流动性问题
    //+--------------------------------------------------------------
    bool HasLiquidityIssue() const { return m_event.HasLiquidityIssue(); }
    
    //+--------------------------------------------------------------
    //| M7: 获取当前事件
    //+--------------------------------------------------------------
    EventType GetCurrentEvent() const { return m_event.GetCurrentEvent(); }
    
    //+--------------------------------------------------------------
    //| 获取 Sub-Type
    //+--------------------------------------------------------------
    RegimeSubType GetSubType() const { return m_snapshot.sub_type; }
    
    //+--------------------------------------------------------------
    //| 获取止损乘数
    //+--------------------------------------------------------------
    double GetSLMultiplier() const { return m_snapshot.sl_multiplier; }
    
    //+--------------------------------------------------------------
    //| 获取止盈乘数
    //+--------------------------------------------------------------
    double GetTPMultiplier() const { return m_snapshot.tp_multiplier; }
    
    //+--------------------------------------------------------------
    //| 获取仓位缩放因子
    //+--------------------------------------------------------------
    double GetScaleMultiplier() const { return m_snapshot.scale_multiplier; }
    
    //+--------------------------------------------------------------
    //| 获取最大持仓数
    //+--------------------------------------------------------------
    int GetMaxPositions() const { return m_snapshot.max_positions; }
    
    //+--------------------------------------------------------------
    //| 获取风险等级
    //+--------------------------------------------------------------
    RiskLevel GetRiskLevel() const { return m_snapshot.risk_level; }
    
    //+--------------------------------------------------------------
    //| 获取 ADX 值
    //+--------------------------------------------------------------
    double GetADX() const { return m_indicators.GetADX(); }
    
    //+--------------------------------------------------------------
    //| 获取市场效率
    //+--------------------------------------------------------------
    double GetEfficiency() const { return m_snapshot.efficiency; }
    
    //+--------------------------------------------------------------
    //| 获取假突破率
    //+--------------------------------------------------------------
    double GetFalseBreakoutRate() const { return m_snapshot.false_breakout_rate; }
    
    //+--------------------------------------------------------------
    //| 获取市场类型
    //+--------------------------------------------------------------
    RegimeType GetRegimeType() const { return m_snapshot.regime_type; }
    
    //+--------------------------------------------------------------
    //| 获取趋势强度
    //+--------------------------------------------------------------
    double GetTrendStrength() const { return m_snapshot.trend_strength; }
    
    //+--------------------------------------------------------------
    //| 打印状态
    //+--------------------------------------------------------------
    void PrintState()
    {
        string state_str = "";
        switch(m_current_state)
        {
            case STATE_ACTIVE: state_str = "ACTIVE"; break;
            case STATE_STANDBY: state_str = "STANDBY"; break;
            case STATE_TRANSITION: state_str = "TRANSITION"; break;
        }
        
        string subtype_str = "";
        switch(m_snapshot.sub_type)
        {
            case SUBTYPE_TVB_TREND: subtype_str = "T+V-B"; break;
            case SUBTYPE_TVA_EMOTION: subtype_str = "T+V-A"; break;
            case SUBTYPE_TN_MILD: subtype_str = "T+N"; break;
            case SUBTYPE_RN_NORMAL: subtype_str = "R+N"; break;
            case SUBTYPE_RVB_FALSE: subtype_str = "R+V-B"; break;
            case SUBTYPE_RVA_NEWS: subtype_str = "R+V-A"; break;
            case SUBTYPE_RL_LOW: subtype_str = "R+L"; break;
            default: subtype_str = "UNKNOWN"; break;
        }
        
        // ::Print(StringFormat(
        //     "[RegimeFilter] State=%s SubType=%s Q=%.2f Trend=%.2f Vol=%s SL=%.1f TP=%.1f Scale=%.1f",
        //     state_str, subtype_str, m_snapshot.q_score, m_snapshot.trend_strength,
        //     (m_snapshot.volatility_state == VOL_HIGH ? "HIGH" : 
        //      m_snapshot.volatility_state == VOL_LOW ? "LOW" : "NORMAL"),
        //     m_snapshot.sl_multiplier, m_snapshot.tp_multiplier, m_snapshot.scale_multiplier
        // ));
    }
};

#endif // __REGIME_FILTER_MQH__
