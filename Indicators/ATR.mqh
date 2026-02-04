//==================================================
// File: Signal.mqh
// Module: Bollinger Reversion AI Filter ATR
//==================================================

#ifndef __ATR_MQH__
#define __ATR_MQH__

// === ATR Indicator Handle ===
int hATR = INVALID_HANDLE;  // ATR 指标句柄
double hBuffer[];          // ATR 数据缓存
int atrBars = 20;           // 缓存大小（更新的根数）

//--------------------------------------------------
bool InitATR(int period)
{
    hATR = iATR(_Symbol, _Period, period);
    if(hATR == INVALID_HANDLE) return false;
    ArraySetAsSeries(hBuffer, true);
    return true;
}

//--------------------------------------------------
double GetATR(int shift)
{
    if(hATR == INVALID_HANDLE) return 0.0;
    if(shift < 0) return 0.0;

    if(ArraySize(hBuffer) <= shift)
        return 0.0;

    return hBuffer[shift];
}

// === 更新 ATR（每 tick / bar 调用）===
bool UpdateATR(int bars)
{
    if(hATR == INVALID_HANDLE)
        return false;

    // 只需要最近 2 根
    int copied = CopyBuffer(
        hATR,
        0,
        0,
        bars,
        hBuffer
    );

    if(copied <= 0)
    {
        Print("ATR CopyBuffer failed, err=", GetLastError());
        return false;
    }

    return true;
}

// get ATR 平均值（用于趋势过滤）
double GetATRMean(int period, int start_shift)
{
    if(hATR == INVALID_HANDLE) return 0.0;
    if(ArraySize(hBuffer) < start_shift + period) return 0.0;

    double sum = 0.0;
    for(int i = start_shift; i < start_shift + period; i++)
        sum += hBuffer[i];

    return sum / period;
}

#endif // __ATR_MQH__