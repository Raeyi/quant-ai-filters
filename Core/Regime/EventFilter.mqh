//+------------------------------------------------------------------+
//|                    Core/Regime/EventFilter.mqh                    |
//|                    事件过滤器 - 新闻/流动性检测                      |
//+------------------------------------------------------------------+
#ifndef __EVENT_FILTER_MQH__
#define __EVENT_FILTER_MQH__

#include "RegimeTypes.mqh"
#include "../Inputs_All.mqh"

//+------------------------------------------------------------------+
//| 事件类型                                                          |
//+------------------------------------------------------------------+
enum EventType
{
    EVENT_NONE = 0,           // 无事件
    EVENT_NFP = 1,            // 非农就业数据
    EVENT_FOMC = 2,           // 美联储利率决议
    EVENT_CPI = 3,            // 消费者物价指数
    EVENT_GDP = 4,            // GDP 数据
    EVENT_RETAIL_SALES = 5,   // 零售销售
    EVENT_PMI = 6             // PMI 数据
};

//+------------------------------------------------------------------+
//| 事件过滤参数                                                       |
//+------------------------------------------------------------------+
input group "========== Event Filter 设置 =========="
input bool    EF_Enable = true;               // 启用事件过滤
input bool    EF_NewsAvoid = true;            // 启用新闻回避
input int     EF_NewsAvoidMinutes = 30;       // 新闻前后回避分钟数
input bool    EF_SpreadFilter = true;         // 启用点差过滤
input double  EF_MaxSpreadMultiplier = 2.0;   // 最大点差倍数（相对正常点差）
input bool    EF_VolumeFilter = true;         // 启用成交量过滤
input double  EF_MinVolumeRatio = 0.3;        // 最小成交量比例（相对平均）
input double  EF_MaxVolumeRatio = 5.0;        // 最大成交量比例（异常检测）

//+------------------------------------------------------------------+
//| 事件过滤器类                                                       |
//+------------------------------------------------------------------+
class CEventFilter
{
private:
    // 当前事件状态
    EventType m_current_event;
    int m_minutes_to_event;
    bool m_in_avoid_window;
    
    // 流动性状态
    double m_normal_spread;
    double m_current_spread;
    double m_avg_volume;
    double m_current_volume;
    bool m_spread_abnormal;
    bool m_volume_abnormal;
    
    // 点差历史（用于计算正常点差）
    double m_spread_history[20];
    int m_spread_index;
    bool m_spread_initialized;
    
    // 成交量历史
    double m_volume_history[50];
    int m_volume_index;
    bool m_volume_initialized;
    
    // 服务器时间偏移
    int m_server_utc_offset;
    
public:
    //+--------------------------------------------------------------
    //| 构造函数
    //+--------------------------------------------------------------
    CEventFilter() :
        m_current_event(EVENT_NONE),
        m_minutes_to_event(-1),
        m_in_avoid_window(false),
        m_normal_spread(0),
        m_current_spread(0),
        m_avg_volume(0),
        m_current_volume(0),
        m_spread_abnormal(false),
        m_volume_abnormal(false),
        m_spread_index(0),
        m_spread_initialized(false),
        m_volume_index(0),
        m_volume_initialized(false),
        m_server_utc_offset(BollMR_ServerUTCOffset)
    {
        ArrayInitialize(m_spread_history, 0);
        ArrayInitialize(m_volume_history, 0);
    }
    
    //+--------------------------------------------------------------
    //| 更新状态（每个 bar 调用一次）
    //+--------------------------------------------------------------
    void Update(double volume = 0)
    {
        if(!EF_Enable)
        {
            m_in_avoid_window = false;
            m_spread_abnormal = false;
            m_volume_abnormal = false;
            return;
        }
        
        // 1. 检测新闻事件窗口
        DetectNewsWindow();
        
        // 2. 检测点差异常
        UpdateSpreadStatus();
        
        // 3. 检测成交量异常
        UpdateVolumeStatus(volume);
    }
    
    //+--------------------------------------------------------------
    //| 检测新闻事件窗口
    //| 关键事件时间（UTC 时间）：
    //| - NFP: 每月第一周五 13:30 UTC
    //| - FOMC: 每年8次，约每6周，18:00/19:00 UTC
    //| - CPI: 每月中旬 13:30 UTC
    //+--------------------------------------------------------------
    void DetectNewsWindow()
    {
        if(!EF_NewsAvoid)
        {
            m_in_avoid_window = false;
            m_current_event = EVENT_NONE;
            return;
        }
        
        datetime currentTime = TimeCurrent();
        MqlDateTime dt;
        TimeToStruct(currentTime, dt);
        
        int hour = dt.hour;
        int day_of_week = dt.day_of_week;
        int day = dt.day;
        
        // 转换为 UTC（假设服务器时间为 UTC+2）
        int utc_hour = hour - m_server_utc_offset;
        utc_hour = NormalizeHour(utc_hour);
        
        m_in_avoid_window = false;
        m_current_event = EVENT_NONE;
        m_minutes_to_event = -1;
        
        // === NFP 检测 ===
        // 每月第一周五 13:30 UTC (北京时间 21:30)
        if(day_of_week == 5 && day <= 7)
        {
            if(IsInWindow(utc_hour, dt.min, 13, 30, EF_NewsAvoidMinutes))
            {
                m_current_event = EVENT_NFP;
                m_in_avoid_window = true;
                return;
            }
        }
        
        // === FOMC 检测 ===
        // 每年约8次，典型时间 18:00/19:00 UTC (北京时间 次日2:00/3:00)
        // 简化：检测周三/周四 18:00-21:00 UTC
        if((day_of_week == 3 || day_of_week == 4) && day >= 15 && day <= 31)
        {
            if(IsInWindow(utc_hour, dt.min, 18, 0, EF_NewsAvoidMinutes))
            {
                m_current_event = EVENT_FOMC;
                m_in_avoid_window = true;
                return;
            }
        }
        
        // === CPI 检测 ===
        // 每月中旬（10-15日）13:30 UTC
        if(day >= 10 && day <= 15)
        {
            if(IsInWindow(utc_hour, dt.min, 13, 30, EF_NewsAvoidMinutes))
            {
                m_current_event = EVENT_CPI;
                m_in_avoid_window = true;
                return;
            }
        }
    }
    
    //+--------------------------------------------------------------
    //| 判断是否在时间窗口内
    //+--------------------------------------------------------------
    bool IsInWindow(int current_hour, int current_min, int event_hour, int event_min, int window_minutes)
    {
        int current_total = current_hour * 60 + current_min;
        int event_total = event_hour * 60 + event_min;
        
        // 计算距离事件的分钟数
        int diff = current_total - event_total;
        
        // 在事件前后 window_minutes 分钟内
        if(diff >= -window_minutes && diff <= window_minutes)
        {
            m_minutes_to_event = -diff;  // 正数=事件前，负数=事件后
            return true;
        }
        return false;
    }
    
    //+--------------------------------------------------------------
    //| 更新点差状态
    //+--------------------------------------------------------------
    void UpdateSpreadStatus()
    {
        if(!EF_SpreadFilter)
        {
            m_spread_abnormal = false;
            return;
        }
        
        // 获取当前点差（点数）
        m_current_spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
        
        // 更新历史
        m_spread_history[m_spread_index] = m_current_spread;
        m_spread_index = (m_spread_index + 1) % 20;
        
        // 计算正常点差（中位数）
        if(!m_spread_initialized && m_spread_index == 0)
        {
            m_spread_initialized = true;
        }
        
        if(m_spread_initialized)
        {
            m_normal_spread = CalculateMedian(m_spread_history, 20);
            
            // 检测异常点差
            if(m_normal_spread > 0)
            {
                double ratio = m_current_spread / m_normal_spread;
                m_spread_abnormal = (ratio > EF_MaxSpreadMultiplier);
            }
        }
    }
    
    //+--------------------------------------------------------------
    //| 更新成交量状态
    //+--------------------------------------------------------------
    void UpdateVolumeStatus(double volume)
    {
        if(!EF_VolumeFilter || volume <= 0)
        {
            m_volume_abnormal = false;
            return;
        }
        
        m_current_volume = volume;
        
        // 更新历史
        m_volume_history[m_volume_index] = volume;
        m_volume_index = (m_volume_index + 1) % 50;
        
        // 初始化完成
        if(!m_volume_initialized && m_volume_index == 0)
        {
            m_volume_initialized = true;
        }
        
        if(m_volume_initialized)
        {
            m_avg_volume = CalculateMean(m_volume_history, 50);
            
            // 检测异常成交量
            if(m_avg_volume > 0)
            {
                double ratio = m_current_volume / m_avg_volume;
                
                // 过低或过高都是异常
                m_volume_abnormal = (ratio < EF_MinVolumeRatio || ratio > EF_MaxVolumeRatio);
            }
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
    //| 工具函数：计算中位数
    //+--------------------------------------------------------------
    double CalculateMedian(double& arr[], int size)
    {
        double sorted[];
        ArrayCopy(sorted, arr, 0, 0, size);
        ArraySort(sorted);
        
        if(size % 2 == 0)
            return (sorted[size/2 - 1] + sorted[size/2]) / 2.0;
        else
            return sorted[size/2];
    }
    
    //+--------------------------------------------------------------
    //| 工具函数：计算均值
    //+--------------------------------------------------------------
    double CalculateMean(double& arr[], int size)
    {
        double sum = 0;
        int count = 0;
        
        for(int i = 0; i < size; i++)
        {
            if(arr[i] > 0)
            {
                sum += arr[i];
                count++;
            }
        }
        
        return (count > 0) ? sum / count : 0;
    }
    
    //+--------------------------------------------------------------
    //| 是否在新闻回避窗口
    //+--------------------------------------------------------------
    bool IsInNewsWindow() const { return m_in_avoid_window; }
    
    //+--------------------------------------------------------------
    //| 是否有流动性异常
    //+--------------------------------------------------------------
    bool HasLiquidityIssue() const { return m_spread_abnormal || m_volume_abnormal; }
    
    //+--------------------------------------------------------------
    //| 是否可以交易
    //+--------------------------------------------------------------
    bool IsTradable() const
    {
        if(!EF_Enable) return true;
        
        // 新闻回避窗口
        if(m_in_avoid_window) return false;
        
        // 点差异常
        if(m_spread_abnormal) return false;
        
        // 成交量异常
        if(m_volume_abnormal) return false;
        
        return true;
    }
    
    //+--------------------------------------------------------------
    //| 获取风险权重（事件期间降低风险）
    //+--------------------------------------------------------------
    double GetRiskWeight() const
    {
        if(!EF_Enable) return 1.0;
        
        double weight = 1.0;
        
        // 新闻窗口期间
        if(m_in_avoid_window)
        {
            weight *= 0.0;  // 完全回避
        }
        
        // 点差扩大期间
        if(m_spread_abnormal)
        {
            weight *= 0.5;
        }
        
        return weight;
    }
    
    //+--------------------------------------------------------------
    //| 获取当前事件
    //+--------------------------------------------------------------
    EventType GetCurrentEvent() const { return m_current_event; }
    
    //+--------------------------------------------------------------
    //| 获取当前点差
    //+--------------------------------------------------------------
    double GetCurrentSpread() const { return m_current_spread; }
    
    //+--------------------------------------------------------------
    //| 获取正常点差
    //+--------------------------------------------------------------
    double GetNormalSpread() const { return m_normal_spread; }
    
    //+--------------------------------------------------------------
    //| 获取事件名称
    //+--------------------------------------------------------------
    string GetEventName() const
    {
        switch(m_current_event)
        {
            case EVENT_NFP: return "NFP";
            case EVENT_FOMC: return "FOMC";
            case EVENT_CPI: return "CPI";
            case EVENT_GDP: return "GDP";
            case EVENT_RETAIL_SALES: return "RETAIL";
            case EVENT_PMI: return "PMI";
            default: return "NONE";
        }
    }
    
    //+--------------------------------------------------------------
    //| 打印状态
    //+--------------------------------------------------------------
    void PrintState() const
    {
        Print("[EventFilter] Event=", GetEventName(),
              " InWindow=", m_in_avoid_window ? "YES" : "NO",
              " Spread=", DoubleToString(m_current_spread, 1), "/", DoubleToString(m_normal_spread, 1),
              " SpreadAbnormal=", m_spread_abnormal ? "YES" : "NO",
              " Tradable=", IsTradable() ? "YES" : "NO");
    }
};

#endif // __EVENT_FILTER_MQH__
