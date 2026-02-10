#ifndef __RSI_MQH__
#define __RSI_MQH__

// === RSI Indicator Handle ===
int g_RSIHandle = INVALID_HANDLE; // RSI 指标句柄
double g_RSIBuffer[];             // RSI 缓冲区
bool g_RSIArraySeries = false;    // 缓冲区是否已设为时间序列

//--------------------------------------------------
// 初始化 RSI 指标（创建句柄 + 设置缓冲区）
bool InitRSI(int period, ENUM_APPLIED_PRICE price = PRICE_CLOSE)
{
    if(g_RSIHandle != INVALID_HANDLE)
        IndicatorRelease(g_RSIHandle);

    g_RSIHandle = iRSI(_Symbol, _Period, period, price);
    if(g_RSIHandle == INVALID_HANDLE)
    {
        Print("Failed to create RSI handle. Error: ", GetLastError());
        return false;
    }

    if(!g_RSIArraySeries)
    {
        ArraySetAsSeries(g_RSIBuffer, true);
        g_RSIArraySeries = true;
    }
    return true;
}

//--------------------------------------------------
// 更新 RSI 缓冲区数据
bool UpdateRSI(int bars)
{
    if(g_RSIHandle == INVALID_HANDLE)
        return false;

    int copied = CopyBuffer(g_RSIHandle, 0, 0, bars, g_RSIBuffer);
    if(copied <= 0)
    {
        Print("RSI CopyBuffer failed, err=", GetLastError());
        return false;
    }
    return true;
}

//--------------------------------------------------
// 获取指定 shift 的 RSI 值（0=当前，1=上一根已收盘）
double GetRSI(int shift)
{
    if(g_RSIHandle == INVALID_HANDLE) return 0.0;
    if(shift < 0) return 0.0;
    if(ArraySize(g_RSIBuffer) <= shift)
        return 0.0;
    return g_RSIBuffer[shift];
}

#endif // __RSI_MQH__
