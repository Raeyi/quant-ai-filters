//==================================================
// File: Signal.mqh
// Module: Bollinger Reversion AI Filter Bollinger
//==================================================

#ifndef __BOLLINGER_MQH__
#define __BOLLINGER_MQH__

//--------------------------------------------------
// Handle & buffers
//--------------------------------------------------
int    bollHandle = INVALID_HANDLE; // 指标句柄 
double bollUpper[];                 // 上轨缓冲�?
double bollMiddle[];                // 中轨缓冲�?
double bollLower[];                // 下轨缓冲�?

//--------------------------------------------------
// Init
//--------------------------------------------------
bool InitBollinger(int period, double deviation)
{
    bollHandle = iBands(
        _Symbol,
        _Period,
        period,
        0,
        deviation,
        PRICE_CLOSE
    );

    if(bollHandle == INVALID_HANDLE)
    {
        Print("InitBollinger failed");
        return false;
    }

    ArraySetAsSeries(bollUpper,  true);
    ArraySetAsSeries(bollMiddle, true);
    ArraySetAsSeries(bollLower,  true);

    return true;
}

//--------------------------------------------------
// Update (call ONCE per new bar)
//--------------------------------------------------
bool UpdateBollinger(int bars = 20)
{
    if(bollHandle == INVALID_HANDLE)
        return false;

    ArrayResize(bollUpper,  bars);
    ArrayResize(bollMiddle, bars);
    ArrayResize(bollLower,  bars);

    // IMPORTANT: // IMPORTANT: start_pos = 0 (aligns with shift indices)
    int c1 = CopyBuffer(bollHandle, 0, 0, bars, bollUpper);
    int c2 = CopyBuffer(bollHandle, 1, 0, bars, bollMiddle);
    int c3 = CopyBuffer(bollHandle, 2, 0, bars, bollLower);

    if(c1 <= 0 || c2 <= 0 || c3 <= 0)
    {
        Print("UpdateBollinger failed: ",
              c1, ", ", c2, ", ", c3);
        return false;
    }

    return true;
}

//--------------------------------------------------
// Safe getters (NO Update inside)
//--------------------------------------------------
double GetBollUpper(int shift)
{
    if(shift < 0 || shift >= ArraySize(bollUpper))
        return 0.0;
    return bollUpper[shift];
}

double GetBollMiddle(int shift)
{
    if(shift < 0 || shift >= ArraySize(bollMiddle))
        return 0.0;
    return bollMiddle[shift];
}

double GetBollLower(int shift)
{
    if(shift < 0 || shift >= ArraySize(bollLower))
        return 0.0;
    return bollLower[shift];
}

#endif // __BOLLINGER_MQH__
