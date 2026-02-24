//==================================================
// File: Donchian.mqh
// Module: Donchian Channel Indicator
// Description: 唐奇安通道指标，用于趋势突破策略
//==================================================

#ifndef __DONCHIAN_MQH__
#define __DONCHIAN_MQH__

// === Donchian 通道指标句柄和缓存 ===
int hDonchianHigh = INVALID_HANDLE;  // 最高价通道句柄
int hDonchianLow = INVALID_HANDLE;   // 最低价通道句柄
double g_DonchianHighBuffer[];       // 上轨缓存
double g_DonchianLowBuffer[];        // 下轨缓存
double g_DonchianMiddleBuffer[];     // 中轨缓存
bool g_DonchianArraySeries = false;

//--------------------------------------------------
// 初始化 Donchian 通道指标
// period: 通道周期（默认20）
//--------------------------------------------------
bool InitDonchian(int period)
{
    // 使用 iHighest/iLowest 封装
    // 上轨 = 过去 period 根 K 线的最高价
    // 下轨 = 过去 period 根 K 线的最低价
    
    if(!g_DonchianArraySeries)
    {
        ArraySetAsSeries(g_DonchianHighBuffer, true);
        ArraySetAsSeries(g_DonchianLowBuffer, true);
        ArraySetAsSeries(g_DonchianMiddleBuffer, true);
        g_DonchianArraySeries = true;
    }
    
    // 预分配缓存大小
    ArrayResize(g_DonchianHighBuffer, 200);
    ArrayResize(g_DonchianLowBuffer, 200);
    ArrayResize(g_DonchianMiddleBuffer, 200);
    
    return true;
}

//--------------------------------------------------
// 更新 Donchian 通道数据
// period: 通道周期
// bars: 需要计算的K线数量
//--------------------------------------------------
bool UpdateDonchian(int period, int bars = 100)
{
    if(bars < period + 1)
        bars = period + 1;
    
    // 直接计算 Donchian 通道
    for(int i = 0; i < bars && i < 200; i++)
    {
        double highest = 0;
        double lowest = DBL_MAX;
        
        // 计算从 i+1 到 i+period 的最高最低价
        for(int j = i + 1; j <= i + period; j++)
        {
            double high = iHigh(_Symbol, _Period, j);
            double low = iLow(_Symbol, _Period, j);
            
            if(high > highest) highest = high;
            if(low < lowest) lowest = low;
        }
        
        if(i < ArraySize(g_DonchianHighBuffer))
        {
            g_DonchianHighBuffer[i] = highest;
            g_DonchianLowBuffer[i] = lowest;
            g_DonchianMiddleBuffer[i] = (highest + lowest) / 2.0;
        }
    }
    
    return true;
}

//--------------------------------------------------
// 获取 Donchian 上轨
// shift: K线偏移（0=当前，1=前一根）
//--------------------------------------------------
double GetDonchianHigh(int shift)
{
    if(shift < 0) return 0.0;
    if(ArraySize(g_DonchianHighBuffer) <= shift) return 0.0;
    return g_DonchianHighBuffer[shift];
}

//--------------------------------------------------
// 获取 Donchian 下轨
// shift: K线偏移
//--------------------------------------------------
double GetDonchianLow(int shift)
{
    if(shift < 0) return 0.0;
    if(ArraySize(g_DonchianLowBuffer) <= shift) return 0.0;
    return g_DonchianLowBuffer[shift];
}

//--------------------------------------------------
// 获取 Donchian 中轨
// shift: K线偏移
//--------------------------------------------------
double GetDonchianMiddle(int shift)
{
    if(shift < 0) return 0.0;
    if(ArraySize(g_DonchianMiddleBuffer) <= shift) return 0.0;
    return g_DonchianMiddleBuffer[shift];
}

//--------------------------------------------------
// 获取通道宽度
// shift: K线偏移
//--------------------------------------------------
double GetDonchianWidth(int shift)
{
    return GetDonchianHigh(shift) - GetDonchianLow(shift);
}

//--------------------------------------------------
// 判断价格是否突破上轨
// shift: K线偏移
// 返回：收盘价 > 上轨
//--------------------------------------------------
bool IsBreakoutHigh(int shift)
{
    double close = iClose(_Symbol, _Period, shift);
    double upper = GetDonchianHigh(shift);
    return (close > upper);
}

//--------------------------------------------------
// 判断价格是否突破下轨
// shift: K线偏移
// 返回：收盘价 < 下轨
//--------------------------------------------------
bool IsBreakoutLow(int shift)
{
    double close = iClose(_Symbol, _Period, shift);
    double lower = GetDonchianLow(shift);
    return (close < lower);
}

#endif // __DONCHIAN_MQH__
