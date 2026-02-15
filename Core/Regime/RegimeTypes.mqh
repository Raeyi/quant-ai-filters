//+------------------------------------------------------------------+
//|                   Core/Regime/RegimeTypes.mqh                    |
//|                   Regime Filter 类型定义                          |
//+------------------------------------------------------------------+
#ifndef __REGIME_TYPES_MQH__
#define __REGIME_TYPES_MQH__

//+------------------------------------------------------------------+
//| 波动率状态枚举                                                      |
//+------------------------------------------------------------------+
enum VolatilityState
{
    VOL_LOW = 0,      // 低波动
    VOL_NORMAL = 1,   // 正常波动
    VOL_HIGH = 2      // 高波动
};

//+------------------------------------------------------------------+
//| 市场状态类型枚举                                                    |
//+------------------------------------------------------------------+
enum RegimeType
{
    REGIME_RANGE = 0,    // 震荡
    REGIME_TREND = 1     // 趋势
};

//+------------------------------------------------------------------+
//| Regime 细分类型枚举                                                 |
//+------------------------------------------------------------------+
enum RegimeSubType
{
    SUBTYPE_UNKNOWN = 0,        // 未知
    SUBTYPE_TVA_EMOTION = 1,    // T+V-A: 情绪脉冲
    SUBTYPE_TVB_TREND = 2,      // T+V-B: 真趋势
    SUBTYPE_TN_MILD = 3,        // T+N: 温和趋势
    SUBTYPE_RVA_NEWS = 4,       // R+V-A: 消息震荡
    SUBTYPE_RVB_FALSE = 5,      // R+V-B: 假突破密集
    SUBTYPE_RN_NORMAL = 6,      // R+N: 正常震荡
    SUBTYPE_RL_LOW = 7          // R+L: 低波动震荡
};

//+------------------------------------------------------------------+
//| Regime 状态枚举                                                    |
//+------------------------------------------------------------------+
enum RegimeState
{
    STATE_ACTIVE = 0,      // 可交易
    STATE_STANDBY = 1,     // 观望
    STATE_TRANSITION = 2   // 过渡中
};

//+------------------------------------------------------------------+
//| 交易时段枚举                                                       |
//+------------------------------------------------------------------+
enum TradingSession
{
    SESSION_ASIAN = 0,     // 亚盘
    SESSION_EUROPEAN = 1,  // 欧盘
    SESSION_OVERLAP = 2,   // 欧美重叠
    SESSION_US = 3,        // 美盘
    SESSION_LATE_US = 4    // 美盘尾段
};

//+------------------------------------------------------------------+
//| 风险等级枚举                                                       |
//+------------------------------------------------------------------+
enum RiskLevel
{
    RISK_LOW = 0,      // 低风险
    RISK_MEDIUM = 1,   // 中等风险
    RISK_HIGH = 2,     // 高风险
    RISK_EXTREME = 3   // 极端风险
};

//+------------------------------------------------------------------+
//| Regime 快照结构体                                                   |
//+------------------------------------------------------------------+
struct RegimeSnapshot
{
    // 状态
    RegimeState     state;              // Regime 状态
    RegimeType      regime_type;        // 市场状态类型
    VolatilityState volatility_state;   // 波动率状态
    RegimeSubType   sub_type;           // Sub-Type
    int             trend_direction;    // 趋势方向 (1=多, -1=空, 0=无)
    
    // 指标
    double          trend_strength;     // 趋势强度 [0, 1]
    double          efficiency;         // 市场效率
    double          false_breakout_rate;// 假突破率
    double          q_score;            // 综合质量分数
    
    // 建议
    double          scale_multiplier;   // 仓位缩放因子
    double          sl_multiplier;      // 止损乘数
    double          tp_multiplier;      // 止盈乘数
    int             max_positions;      // 最大持仓数
    RiskLevel       risk_level;         // 风险等级
    
    // 构造函数
    RegimeSnapshot()
    {
        state = STATE_STANDBY;
        regime_type = REGIME_RANGE;
        volatility_state = VOL_NORMAL;
        sub_type = SUBTYPE_UNKNOWN;
        trend_direction = 0;
        trend_strength = 0.0;
        efficiency = 0.5;
        false_breakout_rate = 0.0;
        q_score = 0.5;
        scale_multiplier = 1.0;
        sl_multiplier = 1.0;
        tp_multiplier = 1.0;
        max_positions = 1;
        risk_level = RISK_MEDIUM;
    }
};

//+------------------------------------------------------------------+
//| 策略选择结果结构体                                                   |
//+------------------------------------------------------------------+
struct StrategySelection
{
    string          primary_strategy;      // 主要策略
    double          scale;                 // 仓位缩放
    double          confidence;            // 置信度
    string          reason;                // 原因
    
    // 参数调整
    double          sl_atr_mult;           // 止损 ATR 乘数
    double          tp_atr_mult;           // 止盈 ATR 乘数
    int             confirm_bars;          // 确认 K 线数
    
    StrategySelection()
    {
        primary_strategy = "";
        scale = 0.0;
        confidence = 0.0;
        reason = "";
        sl_atr_mult = 1.0;
        tp_atr_mult = 1.5;
        confirm_bars = 2;
    }
};

//+------------------------------------------------------------------+
//| 风险调整结果结构体                                                   |
//+------------------------------------------------------------------+
struct RiskAdjustment
{
    double          position_size;         // 建议仓位大小
    double          sl_multiplier;         // 止损乘数
    double          tp_multiplier;         // 止盈乘数
    
    bool            allow_new_position;    // 是否允许新仓位
    bool            allow_add_position;    // 是否允许加仓
    int             max_positions;         // 最大持仓数
    
    RiskLevel       risk_level;            // 风险等级
    string          reason;                // 原因
    
    RiskAdjustment()
    {
        position_size = 0.01;
        sl_multiplier = 1.0;
        tp_multiplier = 1.0;
        allow_new_position = true;
        allow_add_position = false;
        max_positions = 1;
        risk_level = RISK_MEDIUM;
        reason = "";
    }
};

//+------------------------------------------------------------------+
//| 辅助函数：枚举转字符串                                              |
//+------------------------------------------------------------------+
string RegimeStateToString(RegimeState state)
{
    switch(state)
    {
        case STATE_ACTIVE:    return "ACTIVE";
        case STATE_STANDBY:   return "STANDBY";
        case STATE_TRANSITION: return "TRANSITION";
    }
    return "UNKNOWN";
}

string RegimeSubTypeToString(RegimeSubType subtype)
{
    switch(subtype)
    {
        case SUBTYPE_TVB_TREND:   return "T+V-B";
        case SUBTYPE_TVA_EMOTION: return "T+V-A";
        case SUBTYPE_TN_MILD:     return "T+N";
        case SUBTYPE_RN_NORMAL:   return "R+N";
        case SUBTYPE_RVB_FALSE:   return "R+V-B";
        case SUBTYPE_RVA_NEWS:    return "R+V-A";
        case SUBTYPE_RL_LOW:      return "R+L";
    }
    return "";
}

string VolatilityStateToString(VolatilityState vol)
{
    switch(vol)
    {
        case VOL_HIGH:   return "HIGH";
        case VOL_NORMAL: return "NORMAL";
        case VOL_LOW:    return "LOW";
    }
    return "UNKNOWN";
}

#endif // __REGIME_TYPES_MQH__
