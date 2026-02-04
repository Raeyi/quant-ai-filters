//==================================================
// File: MA.mqh
// Module: Moving Average Indicator Wrapper
// Description: 封装了各种类型的移动平均线指标
//==================================================

#ifndef __MA_MQH__
#define __MA_MQH__

// === 全局函数版本（保持与ATR类似的接口）===
int g_MAHandle = INVALID_HANDLE;
double g_MABuffer[];
bool g_MAArraySeries = false;

//--------------------------------------------------
// 初始化MA指标（全局版本）
// period: MA周期
// method: 计算方法（MODE_SMA, MODE_EMA, MODE_SMMA, MODE_LWMA）
// price: 应用价格（PRICE_CLOSE, PRICE_OPEN等）
//--------------------------------------------------
bool InitMA(int period, 
            int shift = 0, 
            ENUM_MA_METHOD method = MODE_EMA, 
            ENUM_APPLIED_PRICE price = PRICE_CLOSE)
{
    if(g_MAHandle != INVALID_HANDLE)
    {
        IndicatorRelease(g_MAHandle);
    }
    
    g_MAHandle = iMA(_Symbol, _Period, period, shift, method, price);
    
    if(g_MAHandle == INVALID_HANDLE)
    {
        Print("Failed to create MA handle. Error: ", GetLastError());
        return false;
    }
    
    if(!g_MAArraySeries)
    {
        ArraySetAsSeries(g_MABuffer, true);
        g_MAArraySeries = true;
    }
    
    return true;
}

//--------------------------------------------------
// 更新MA数据
// bars: 需要更新的K线数量
//--------------------------------------------------
bool UpdateMA(int bars = 100)
{
    if(g_MAHandle == INVALID_HANDLE)
        return false;
    
    int copied = CopyBuffer(g_MAHandle, 0, 0, bars, g_MABuffer);
    if(copied <= 0)
    {
        Print("MA CopyBuffer failed, err=", GetLastError());
        return false;
    }
    
    return true;
}

//--------------------------------------------------
// 获取指定位置的MA值
// shift: 偏移量（0=当前，1=前一根，以此类推）
//--------------------------------------------------
double GetMA(int shift)
{
    if(g_MAHandle == INVALID_HANDLE) return 0.0;
    if(shift < 0) return 0.0;
    
    if(ArraySize(g_MABuffer) <= shift)
        return 0.0;
    
    return g_MABuffer[shift];
}

//--------------------------------------------------
// 获取当前MA值
//--------------------------------------------------
double GetMACurrent()
{
    return GetMA(0);
}

//--------------------------------------------------
// 获取MA平均值
// period: 计算平均值的周期
// startShift: 起始偏移
//--------------------------------------------------
double GetMAMean(int period, int startShift)
{
    if(g_MAHandle == INVALID_HANDLE) return 0.0;
    if(ArraySize(g_MABuffer) < startShift + period) return 0.0;
    
    double sum = 0.0;
    for(int i = startShift; i < startShift + period; i++)
        sum += g_MABuffer[i];
    
    return sum / period;
}

//--------------------------------------------------
// 获取MA斜率（当前相对于前n根的变化率）
// lookback: 回看周期
//--------------------------------------------------
double GetMASlope(int lookback = 10)
{
    if(ArraySize(g_MABuffer) < lookback + 1)
        return 0.0;
    
    double current = GetMA(0);
    double past = GetMA(lookback);
    
    if(past == 0) return 0.0;
    
    // 转换为点数的变化
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    if(point <= 0) point = 0.00001;
    
    return (current - past) / (lookback * point);
}

//--------------------------------------------------
// 判断MA是否向上
// lookback: 回看周期
//--------------------------------------------------
bool IsMAUp(int lookback = 2)
{
    if(ArraySize(g_MABuffer) < lookback + 1)
        return false;
    
    for(int i = 0; i < lookback; i++)
    {
        if(GetMA(i) < GetMA(i + 1))
            return false;
    }
    return true;
}

//--------------------------------------------------
// 判断MA是否向下
// lookback: 回看周期
//--------------------------------------------------
bool IsMADown(int lookback = 2)
{
    if(ArraySize(g_MABuffer) < lookback + 1)
        return false;
    
    for(int i = 0; i < lookback; i++)
    {
        if(GetMA(i) > GetMA(i + 1))
            return false;
    }
    return true;
}

#endif // __MA_MQH__