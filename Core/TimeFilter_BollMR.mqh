//+------------------------------------------------------------------+
//|                   Core/TimeFilter_BollMR.mqh                      |
//|                   BollMR 策略时间过滤（基于通用接口）               |
//+------------------------------------------------------------------+
#ifndef __TIMEFILTER_BOLLMR_MQH__
#define __TIMEFILTER_BOLLMR_MQH__

#include "TimeFilter.mqh"

//+------------------------------------------------------------------+
//| BollMR 时间过滤（兼容旧接口）                                       |
//+------------------------------------------------------------------+
bool BollMR_TimeFilterOK()
{
    string mode = BollMR_TimeMode;
    StringToLower(mode);

    // custom：使用自定义开始结束时间
    if(mode == "custom")
    {
        datetime currentTime = TimeCurrent();
        MqlDateTime timeStruct;
        TimeToStruct(currentTime, timeStruct);
        int server_hour = timeStruct.hour;
        
        int start_bj = BollMR_StartHour;
        int end_bj = BollMR_EndHour;
        int start_sv = TimeFilter_BeijingToServerHour(start_bj);
        int end_sv = TimeFilter_BeijingToServerHour(end_bj);
        return TimeFilter_InWindow(server_hour, start_sv, end_sv);
    }

    // session：使用通用时段过滤
    return TimeFilter_CheckSession(BollMR_Session, BollMR_UseDST, BollMR_DSTShiftHours);
}

//+------------------------------------------------------------------+
//| 兼容旧函数名                                                       |
//+------------------------------------------------------------------+
int BollMR_NormalizeHour(int hour) { return TimeFilter_NormalizeHour(hour); }
int BollMR_BeijingToServerHour(int bj_hour) { return TimeFilter_BeijingToServerHour(bj_hour); }
bool BollMR_InWindow(int hour, int start, int end) { return TimeFilter_InWindow(hour, start, end); }

#endif // __TIMEFILTER_BOLLMR_MQH__
