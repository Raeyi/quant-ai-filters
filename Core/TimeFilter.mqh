//+------------------------------------------------------------------+
//|                   Core/TimeFilter.mqh                             |
//|                   通用时间过滤接口                                  |
//+------------------------------------------------------------------+
#ifndef __TIMEFILTER_MQH__
#define __TIMEFILTER_MQH__

#include "Inputs_All.mqh"

//+------------------------------------------------------------------+
//| 将小时归一化到 0-23                                                |
//+------------------------------------------------------------------+
int TimeFilter_NormalizeHour(int hour)
{
    int h = hour % 24;
    if(h < 0) h += 24;
    return h;
}

//+------------------------------------------------------------------+
//| 将北京时间转换为服务器时间                                          |
//+------------------------------------------------------------------+
int TimeFilter_BeijingToServerHour(int bj_hour)
{
    // 北京时间 UTC+8
    int server_hour = bj_hour - 8 + BollMR_ServerUTCOffset;
    return TimeFilter_NormalizeHour(server_hour);
}

//+------------------------------------------------------------------+
//| 是否在一个时间窗口内（支持跨午夜）                                   |
//+------------------------------------------------------------------+
bool TimeFilter_InWindow(int hour, int start_hour, int end_hour)
{
    // start == end 视为全天允许
    if(start_hour == end_hour)
        return true;

    if(start_hour <= end_hour)
        return (hour >= start_hour && hour < end_hour);

    // 跨午夜
    return (hour >= start_hour || hour < end_hour);
}

//+------------------------------------------------------------------+
//| 时段定义结构体                                                     |
//+------------------------------------------------------------------+
struct SessionTimes
{
    int start;    // 开始时间（北京时间）
    int end;      // 结束时间（北京时间）
};

//+------------------------------------------------------------------+
//| 获取时段时间定义                                                    |
//+------------------------------------------------------------------+
void GetSessionTimes(string session_name, SessionTimes &times)
{
    // 默认值
    times.start = 0;
    times.end = 24;
    
    StringTrimLeft(session_name);
    StringTrimRight(session_name);
    StringToLower(session_name);
    
    // 北京时间窗口定义（冬令时基准）
    if(session_name == "asia")
    {
        times.start = 8;
        times.end = 16;
    }
    else if(session_name == "europe")
    {
        times.start = 15;
        times.end = 24;
    }
    else if(session_name == "us")
    {
        times.start = 20;
        times.end = 4;  // 跨午夜
    }
    else if(session_name == "overlap")
    {
        times.start = 20;
        times.end = 24;
    }
}

//+------------------------------------------------------------------+
//| 通用时间过滤函数                                                   |
//| @param sessions 时段字符串，逗号分隔，如 "europe,us,overlap"        |
//| @param useDST 是否使用 DST 平移                                    |
//| @param dstShift DST 平移小时数                                     |
//| @return true = 在允许时段内                                         |
//+------------------------------------------------------------------+
bool TimeFilter_CheckSession(string sessions, bool useDST = false, int dstShift = 0)
{
    datetime currentTime = TimeCurrent();
    MqlDateTime timeStruct;
    TimeToStruct(currentTime, timeStruct);
    int server_hour = timeStruct.hour;

    StringToLower(sessions);

    // 解析时段列表
    string list[];
    int cnt = StringSplit(sessions, ',', list);
    if(cnt <= 0)
    {
        ArrayResize(list, 1);
        list[0] = sessions;
        cnt = 1;
    }

    bool matched_any = false;
    
    for(int i = 0; i < cnt; i++)
    {
        string session = list[i];
        StringTrimLeft(session);
        StringTrimRight(session);
        if(session == "")
            continue;

        matched_any = true;
        
        SessionTimes times;
        GetSessionTimes(session, times);
        
        // DST 平移
        int start = times.start;
        int end = times.end;
        if(useDST && session != "asia")
        {
            start = TimeFilter_NormalizeHour(start + dstShift);
            end = TimeFilter_NormalizeHour(end + dstShift);
        }
        
        // 转换为服务器时间
        int start_sv = TimeFilter_BeijingToServerHour(start);
        int end_sv = TimeFilter_BeijingToServerHour(end);
        
        if(TimeFilter_InWindow(server_hour, start_sv, end_sv))
            return true;
    }

    // 如果未匹配任何有效时段标签，则放行
    if(!matched_any)
        return true;

    return false;
}

//+------------------------------------------------------------------+
//| 获取当前时段名称                                                   |
//+------------------------------------------------------------------+
string TimeFilter_GetCurrentSession()
{
    datetime currentTime = TimeCurrent();
    MqlDateTime timeStruct;
    TimeToStruct(currentTime, timeStruct);
    int server_hour = timeStruct.hour;
    
    // 北京时间窗口定义
    int asia_s = TimeFilter_BeijingToServerHour(8);
    int asia_e = TimeFilter_BeijingToServerHour(16);
    int eu_s = TimeFilter_BeijingToServerHour(15);
    int eu_e = TimeFilter_BeijingToServerHour(24);
    int us_s = TimeFilter_BeijingToServerHour(20);
    int us_e = TimeFilter_BeijingToServerHour(4);
    int ov_s = TimeFilter_BeijingToServerHour(20);
    int ov_e = TimeFilter_BeijingToServerHour(24);
    
    // 检查重叠时段
    if(TimeFilter_InWindow(server_hour, ov_s, ov_e))
        return "OVERLAP";
    if(TimeFilter_InWindow(server_hour, us_s, us_e))
        return "US";
    if(TimeFilter_InWindow(server_hour, eu_s, eu_e))
        return "EUROPE";
    if(TimeFilter_InWindow(server_hour, asia_s, asia_e))
        return "ASIA";
    
    return "OTHER";
}

//+------------------------------------------------------------------+
//| 获取时段权重（用于 Q-Score 调整）                                   |
//+------------------------------------------------------------------+
double TimeFilter_GetSessionWeight()
{
    string session = TimeFilter_GetCurrentSession();
    
    if(session == "OVERLAP") return 1.5;   // 最佳时段
    if(session == "US") return 1.2;        // 美盘
    if(session == "EUROPE") return 1.0;    // 欧盘
    if(session == "ASIA") return 0.7;      // 亚盘
    return 0.3;                             // 低流动性时段
}

#endif // __TIMEFILTER_MQH__
