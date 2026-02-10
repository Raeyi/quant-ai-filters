#ifndef __TIMEFILTER_BOLLMR_MQH__
#define __TIMEFILTER_BOLLMR_MQH__

#include "Inputs_BollMR.mqh"

// 将小时归一化到 0-23
int BollMR_NormalizeHour(int hour)
{
    int h = hour % 24;
    if(h < 0) h += 24;
    return h;
}

// 将北京时间转换为服务器时间（MT5）
int BollMR_BeijingToServerHour(int bj_hour)
{
    // 北京时间 UTC+8
    int server_hour = bj_hour - 8 + BollMR_ServerUTCOffset;
    return BollMR_NormalizeHour(server_hour);
}

// 是否在一个时间窗内（支持跨午夜）
bool BollMR_InWindow(int hour, int start_hour, int end_hour)
{
    if(start_hour <= end_hour)
        return (hour >= start_hour && hour < end_hour);
    // 跨午夜
    return (hour >= start_hour || hour < end_hour);
}

// 基于当前服务器时间判断是否在允许交易时间内
bool BollMR_TimeFilterOK()
{
    datetime currentTime = TimeCurrent();
    MqlDateTime timeStruct;
    TimeToStruct(currentTime, timeStruct);
    int server_hour = timeStruct.hour;

    string mode = BollMR_TimeMode;
    StringToLower(mode);

    // custom：使用自定义开始/结束时间（按北京时间填写）
    if(mode == "custom")
    {
        int start_bj = BollMR_StartHour;
        int end_bj   = BollMR_EndHour;
        int start_sv = BollMR_BeijingToServerHour(start_bj);
        int end_sv   = BollMR_BeijingToServerHour(end_bj);
        return BollMR_InWindow(server_hour, start_sv, end_sv);
    }

    // session：按盘面时段（北京时间定义）
    string session = BollMR_Session;
    StringToLower(session);

    // 北京时间窗口定义（冬令时）
    int asia_start = 8,  asia_end = 16;
    int eu_start   = 15, eu_end   = 24;
    int us_start   = 20, us_end   = 4;  // 跨午夜
    int ov_start   = 20, ov_end   = 24;

    // 手动 DST：对欧盘/美盘/重叠时段整体平移
    if(BollMR_UseDST)
    {
        eu_start = BollMR_NormalizeHour(eu_start + BollMR_DSTShiftHours);
        eu_end   = BollMR_NormalizeHour(eu_end   + BollMR_DSTShiftHours);
        us_start = BollMR_NormalizeHour(us_start + BollMR_DSTShiftHours);
        us_end   = BollMR_NormalizeHour(us_end   + BollMR_DSTShiftHours);
        ov_start = BollMR_NormalizeHour(ov_start + BollMR_DSTShiftHours);
        ov_end   = BollMR_NormalizeHour(ov_end   + BollMR_DSTShiftHours);
    }

    if(session == "asia")
    {
        int s = BollMR_BeijingToServerHour(asia_start);
        int e = BollMR_BeijingToServerHour(asia_end);
        return BollMR_InWindow(server_hour, s, e);
    }
    if(session == "europe")
    {
        int s = BollMR_BeijingToServerHour(eu_start);
        int e = BollMR_BeijingToServerHour(eu_end);
        return BollMR_InWindow(server_hour, s, e);
    }
    if(session == "us")
    {
        int s = BollMR_BeijingToServerHour(us_start);
        int e = BollMR_BeijingToServerHour(us_end);
        return BollMR_InWindow(server_hour, s, e);
    }
    if(session == "overlap")
    {
        int s = BollMR_BeijingToServerHour(ov_start);
        int e = BollMR_BeijingToServerHour(ov_end);
        return BollMR_InWindow(server_hour, s, e);
    }
    if(session == "europe+us" || session == "eu+us")
    {
        int es = BollMR_BeijingToServerHour(eu_start);
        int ee = BollMR_BeijingToServerHour(eu_end);
        int us = BollMR_BeijingToServerHour(us_start);
        int ue = BollMR_BeijingToServerHour(us_end);
        return (BollMR_InWindow(server_hour, es, ee) ||
                BollMR_InWindow(server_hour, us, ue));
    }

    // 默认：允许交易
    return true;
}

#endif // __TIMEFILTER_BOLLMR_MQH__
