//+------------------------------------------------------------------+
//|                    Core/Regime/SessionQuality.mqh                 |
//|                    时段质量评估 - XAUUSD 职业化过滤                 |
//+------------------------------------------------------------------+
#ifndef __SESSION_QUALITY_MQH__
#define __SESSION_QUALITY_MQH__

#include "RegimeTypes.mqh"
#include "../Inputs_All.mqh"

//+------------------------------------------------------------------+
//| 扩展时段类型（内部使用）                                            |
//+------------------------------------------------------------------+
enum ExtendedSessionType
{
    EXT_SESSION_LOW_LIQUIDITY = 0,  // 低流动性（亚洲深夜）
    EXT_SESSION_ASIA = 1,           // 亚洲时段
    EXT_SESSION_EUROPE_PRE = 2,     // 欧盘前夕
    EXT_SESSION_EUROPE = 3,         // 欧洲时段
    EXT_SESSION_OVERLAP = 4,        // 欧美重叠（最佳）
    EXT_SESSION_US = 5,             // 美盘
    EXT_SESSION_US_LATE = 6         // 美盘尾盘
};

//+------------------------------------------------------------------+
//| 时段质量参数                                                       |
//+------------------------------------------------------------------+
input group "========== Session Quality 设置 =========="
input bool    SQ_Enable = true;              // 启用时段质量评估
input double  SQ_LowLiquidityPenalty = 0.3;  // 低流动性惩罚系数
input double  SQ_OverlapBonus = 1.3;         // 重叠时段加成

//+------------------------------------------------------------------+
//| 时段质量评估类                                                     |
//+------------------------------------------------------------------+
class CSessionQuality
{
private:
    ExtendedSessionType m_current_session;
    double m_session_weight;
    
    // 服务器时间偏移
    int m_server_utc_offset;
    
public:
    //+--------------------------------------------------------------
    //| 构造函数
    //+--------------------------------------------------------------
    CSessionQuality() : 
        m_current_session(EXT_SESSION_LOW_LIQUIDITY),
        m_session_weight(1.0),
        m_server_utc_offset(BollMR_ServerUTCOffset)
    {}
    
    //+--------------------------------------------------------------
    //| 更新时段状态（每个 bar 调用一次）
    //+--------------------------------------------------------------
    void Update()
    {
        m_current_session = DetectSession();
        m_session_weight = CalculateSessionWeight();
    }
    
    //+--------------------------------------------------------------
    //| 检测当前时段类型
    //+--------------------------------------------------------------
    ExtendedSessionType DetectSession()
    {
        datetime currentTime = TimeCurrent();
        MqlDateTime dt;
        TimeToStruct(currentTime, dt);
        
        int hour = dt.hour;
        int day_of_week = dt.day_of_week;
        
        // 周末不交易
        if(day_of_week == 0 || day_of_week == 6)
            return EXT_SESSION_LOW_LIQUIDITY;
        
        // 北京时间转换
        int beijing_hour = hour + (8 - m_server_utc_offset);
        beijing_hour = NormalizeHour(beijing_hour);
        
        // === 时段划分（北京时间）===
        // 低流动性: 00:00-06:00 (亚洲深夜)
        // 亚洲时段: 08:00-15:00
        // 欧盘前夕: 15:00-16:00
        // 欧洲时段: 16:00-20:00
        // 欧美重叠: 20:00-24:00 (最佳)
        // 美盘:     21:00-04:00
        // 美盘尾盘: 03:00-05:00
        
        // 低流动性时段（亚洲深夜）
        if(beijing_hour >= 0 && beijing_hour < 6)
            return EXT_SESSION_LOW_LIQUIDITY;
        
        // 亚洲时段
        if(beijing_hour >= 8 && beijing_hour < 15)
            return EXT_SESSION_ASIA;
        
        // 欧盘前夕
        if(beijing_hour >= 15 && beijing_hour < 16)
            return EXT_SESSION_EUROPE_PRE;
        
        // 欧美重叠（最佳时段）
        if(beijing_hour >= 20 && beijing_hour < 24)
            return EXT_SESSION_OVERLAP;
        
        // 欧洲时段
        if(beijing_hour >= 16 && beijing_hour < 20)
            return EXT_SESSION_EUROPE;
        
        // 美盘尾盘
        if(beijing_hour >= 3 && beijing_hour < 5)
            return EXT_SESSION_US_LATE;
        
        // 美盘
        if((beijing_hour >= 21 && beijing_hour < 24) || 
           (beijing_hour >= 0 && beijing_hour < 3))
            return EXT_SESSION_US;
        
        return EXT_SESSION_LOW_LIQUIDITY;
    }
    
    //+--------------------------------------------------------------
    //| 计算时段权重
    //+--------------------------------------------------------------
    double CalculateSessionWeight()
    {
        switch(m_current_session)
        {
            case EXT_SESSION_OVERLAP:
                return SQ_OverlapBonus;           // 最佳时段
            case EXT_SESSION_US:
                return 1.2;                       // 美盘活跃
            case EXT_SESSION_EUROPE:
                return 1.0;                       // 欧盘基准
            case EXT_SESSION_ASIA:
                return 0.8;                       // 亚盘较弱
            case EXT_SESSION_EUROPE_PRE:
                return 0.7;                       // 欧盘前夕观望
            case EXT_SESSION_US_LATE:
                return 0.5;                       // 尾盘风险高
            case EXT_SESSION_LOW_LIQUIDITY:
                return SQ_LowLiquidityPenalty;    // 低流动性惩罚
            default:
                return 1.0;
        }
    }
    
    //+--------------------------------------------------------------
    //| 工具函数：归一化小时
    //+--------------------------------------------------------------
    int NormalizeHour(int hour)
    {
        int h = hour % 24;
        if(h < 0) h += 24;
        return h;
    }
    
    //+--------------------------------------------------------------
    //| 获取当前时段
    //+--------------------------------------------------------------
    ExtendedSessionType GetCurrentSession() const { return m_current_session; }
    
    //+--------------------------------------------------------------
    //| 获取时段权重
    //+--------------------------------------------------------------
    double GetSessionWeight() const { return m_session_weight; }
    
    //+--------------------------------------------------------------
    //| 是否适合交易
    //+--------------------------------------------------------------
    bool IsTradable() const
    {
        // 低流动性时段不交易
        return m_current_session != EXT_SESSION_LOW_LIQUIDITY;
    }
    
    //+--------------------------------------------------------------
    //| 获取时段名称
    //+--------------------------------------------------------------
    string GetSessionName() const
    {
        switch(m_current_session)
        {
            case EXT_SESSION_LOW_LIQUIDITY: return "LOW_LIQ";
            case EXT_SESSION_ASIA: return "ASIA";
            case EXT_SESSION_EUROPE_PRE: return "EU_PRE";
            case EXT_SESSION_EUROPE: return "EUROPE";
            case EXT_SESSION_OVERLAP: return "OVERLAP";
            case EXT_SESSION_US: return "US";
            case EXT_SESSION_US_LATE: return "US_LATE";
            default: return "UNKNOWN";
        }
    }
    
    //+--------------------------------------------------------------
    //| 打印状态
    //+--------------------------------------------------------------
    void PrintState() const
    {
        Print("[SessionQuality] Session=", GetSessionName(), 
              " Weight=", DoubleToString(m_session_weight, 2),
              " Tradable=", IsTradable() ? "YES" : "NO");
    }
};

#endif // __SESSION_QUALITY_MQH__
