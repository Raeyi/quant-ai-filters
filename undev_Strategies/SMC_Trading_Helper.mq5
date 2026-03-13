#property copyright "SMC Trading Helper v2.0"
#property link      "https://www.example.com"
#property version   "1.00"
#property description "SMC Trading Helper - 识别流动性区域、订单区块、FVG和PinBar信号"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots 0

// 输入参数 - 周期设置
input ENUM_TIMEFRAMES HigherTimeframe = PERIOD_H4;  // 高周期（趋势方向）
input ENUM_TIMEFRAMES LowerTimeframe = PERIOD_M15;  // 低周期（入场信号）
input bool   UseMultiTimeframe = true;              // 启用多周期分析
input bool   RangingMode = false;                   // 震荡模式（不过滤方向，双向信号）

// 输入参数 - 通用设置
input int    LookBackPeriod = 200;           // 回看周期
input double SwingPeriod = 5;               // 摆动点周期
input double LiquidityAreaOpacity = 0.2;    // 流动性区域透明度

// 输入参数 - 显示开关
input bool   ShowEntrySignals = true;       // 显示入场信号（关键区域PinBar）
input bool   ShowLiquidityLines = false;    // 显示流动性水平线
input bool   ShowLiquidityZones = false;    // 显示流动性区域矩形
input bool   ShowOrderBlocks = false;       // 显示订单区块
input bool   ShowFVG = false;               // 显示公允价值缺口
input bool   ShowLiquidityGrab = true;      // 显示流动性猎杀（假突破）
input int    MaxSignalsToShow = 5;          // 最大显示入场信号数量

// 输入参数 - 颜色设置
input color  BullishColor = clrLimeGreen;  // 看涨颜色
input color  BearishColor = clrRed;         // 看跌颜色

// 输入参数 - FVG设置
input int    FVG_Period = 3;               // FVG维持周期
input double FVG_Min_Points = 30.0;        // FVG最小点数阈值
input int    FVG_Bars_Extends = 50;        // FVG矩形延伸K线数

// 输入参数 - PinBar设置
input double PinBar_Wick_Ratio = 0.65;     // PinBar影线最小占比 (65%)
input int    PinBar_LookBack = 30;         // PinBar回看K线数

// 输入参数 - 流动性猎杀设置
input double LiquidityGrab_Deviation_Points = 100.0;  // 流动性猎杀检测偏差(点)
input int    LiquidityGrab_LookForward = 5;           // 流动性猎杀前看K线数

// 输入参数 - 订单区块设置
input int    OrderBlock_Width_Bars = 20;   // 订单区块宽度(K线数)
input int    Impulse_Bars_Count = 3;       // 强势推动检测K线数

// 全局变量
int lastProcessedBar = 0;
string objectPrefix = "SMC_";
datetime lastLiquidityCheck = 0;

// HTF 关键区域记录 (像 Hunter_Pro 一样)
double g_htf_Bull_OB_Top = 0, g_htf_Bull_OB_Bot = 0;
double g_htf_Bear_OB_Top = 0, g_htf_Bear_OB_Bot = 0;
double g_htf_Bull_FVG_Top = 0, g_htf_Bull_FVG_Bot = 0;
double g_htf_Bear_FVG_Top = 0, g_htf_Bear_FVG_Bot = 0;

//+------------------------------------------------------------------+
//| 自定义指标初始化函数                                              |
//+------------------------------------------------------------------+
int OnInit()
{
    // 清理旧对象
    ObjectsDeleteAll(0, objectPrefix);
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| 自定义指标去初始化函数                                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // 删除所有图形对象
    ObjectsDeleteAll(0, objectPrefix);
}

//+------------------------------------------------------------------+
//| 主计算函数                                                       |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    if(rates_total < LookBackPeriod) 
        return(0);
        
    // 只在新K线时计算
    if(prev_calculated == rates_total)
        return(rates_total);
    
    // 计算指标
    CalculateIndicators();
    
    return(rates_total);
}

//+------------------------------------------------------------------+
//| 计算指标                                                         |
//+------------------------------------------------------------------+
void CalculateIndicators()
{
    int ltfLimit = MathMin(Bars(_Symbol, LowerTimeframe), LookBackPeriod);
    int htfLimit = MathMin(Bars(_Symbol, HigherTimeframe), 50);
    
    // 清理旧对象
    ObjectsDeleteAll(0, objectPrefix);
    
    // 重置 HTF 区域
    g_htf_Bull_OB_Top = 0; g_htf_Bull_OB_Bot = 0;
    g_htf_Bear_OB_Top = 0; g_htf_Bear_OB_Bot = 0;
    g_htf_Bull_FVG_Top = 0; g_htf_Bull_FVG_Bot = 0;
    g_htf_Bear_FVG_Top = 0; g_htf_Bear_FVG_Bot = 0;
    
    // 多周期分析：高周期趋势过滤
    bool higherTrendBullish = true;
    bool higherTrendBearish = true;
    
    if(UseMultiTimeframe)
    {
        higherTrendBullish = CheckHigherTimeframeTrend(htfLimit, true);
        higherTrendBearish = CheckHigherTimeframeTrend(htfLimit, false);
    }
    
    // 关键修改：在高周期找 OB/FVG (像 Hunter_Pro 一样)
    if(UseMultiTimeframe)
    {
        FindHTFOrderBlocks(htfLimit);
        FindHTFFairValueGaps(htfLimit);
    }
    
    // 在低周期找流动性和 PinBar 信号
    FindLiquidityZones(ltfLimit);
    
    // 计算并显示入场信号 (低周期 PinBar 刺入高周期区域)
    if(ShowEntrySignals)
        FindPinBarSignals(ltfLimit, higherTrendBullish, higherTrendBearish);
    
    // 删除用户不需要显示的区域对象
    if(!ShowLiquidityZones && !ShowLiquidityLines)
        DeleteObjectsByPrefix(objectPrefix + "LZ_");
    if(!ShowLiquidityGrab)
        DeleteObjectsByPrefix(objectPrefix + "LG_");
    if(!ShowOrderBlocks)
        DeleteObjectsByPrefix(objectPrefix + "OB_");
    if(!ShowFVG)
        DeleteObjectsByPrefix(objectPrefix + "FVG_");
}

//+------------------------------------------------------------------+
//| 删除指定前缀的对象                                                 |
//+------------------------------------------------------------------+
void DeleteObjectsByPrefix(string prefix)
{
    int total = ObjectsTotal(0, 0, -1);
    for(int i = total - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i, 0, -1);
        if(StringFind(name, prefix) == 0)
            ObjectDelete(0, name);
    }
}

//+------------------------------------------------------------------+
//| 检查高周期趋势                                                   |
//+------------------------------------------------------------------+
bool CheckHigherTimeframeTrend(int limit, bool checkBullish)
{
    if(limit < 20) return true;
    
    double ma = 0;
    for(int i = 0; i < 20; i++)
    {
        ma += iClose(_Symbol, HigherTimeframe, i);
    }
    ma /= 20;
    
    double currentPrice = iClose(_Symbol, HigherTimeframe, 0);
    
    if(checkBullish)
        return currentPrice > ma;
    else
        return currentPrice < ma;
}

//+------------------------------------------------------------------+
//| 在高周期查找订单区块 (像 Hunter_Pro)                              |
//+------------------------------------------------------------------+
void FindHTFOrderBlocks(int limit)
{
    double minFVGSize = FVG_Min_Points * GetPoint();
    
    // 从近向远扫描，找到最近的有效OB
    for(int i = 2; i < MathMin(limit, 20); i++)
    {
        // --- 看涨 FVG 判断 (第 i 根的高点 < 第 i-2 根的低点)
        double fvgSizeBull = iLow(_Symbol, HigherTimeframe, i-2) - iHigh(_Symbol, HigherTimeframe, i);
        if(fvgSizeBull > minFVGSize)
        {
            // 往前回溯寻找产生动能前的最后一根阴线 (看涨OB)
            for(int j = i+1; j < i+5 && j < limit; j++)
            {
                if(iClose(_Symbol, HigherTimeframe, j) < iOpen(_Symbol, HigherTimeframe, j)) // 阴线
                {
                    g_htf_Bull_OB_Top = iHigh(_Symbol, HigherTimeframe, j);
                    g_htf_Bull_OB_Bot = iLow(_Symbol, HigherTimeframe, j);
                    
                    // 可视化显示
                    if(ShowOrderBlocks)
                    {
                        string name = objectPrefix + "OB_Bull_HTF";
                        CreateRectangle(name, 
                            iTime(_Symbol, HigherTimeframe, j),
                            iTime(_Symbol, HigherTimeframe, 0) + PeriodSeconds(HigherTimeframe) * 20,
                            g_htf_Bull_OB_Top, g_htf_Bull_OB_Bot,
                            clrDarkSeaGreen, 0.3, "Bull OB (HTF)");
                    }
                    break;
                }
            }
            break; // 只取最近的一个
        }
    }
    
    // --- 看跌 FVG 判断 (第 i 根的低点 > 第 i-2 根的高点)
    for(int i = 2; i < MathMin(limit, 20); i++)
    {
        double fvgSizeBear = iLow(_Symbol, HigherTimeframe, i) - iHigh(_Symbol, HigherTimeframe, i-2);
        if(fvgSizeBear > minFVGSize)
        {
            // 往前回溯寻找产生动能前的最后一根阳线 (看跌OB)
            for(int j = i+1; j < i+5 && j < limit; j++)
            {
                if(iClose(_Symbol, HigherTimeframe, j) > iOpen(_Symbol, HigherTimeframe, j)) // 阳线
                {
                    g_htf_Bear_OB_Top = iHigh(_Symbol, HigherTimeframe, j);
                    g_htf_Bear_OB_Bot = iLow(_Symbol, HigherTimeframe, j);
                    
                    // 可视化显示
                    if(ShowOrderBlocks)
                    {
                        string name = objectPrefix + "OB_Bear_HTF";
                        CreateRectangle(name,
                            iTime(_Symbol, HigherTimeframe, j),
                            iTime(_Symbol, HigherTimeframe, 0) + PeriodSeconds(HigherTimeframe) * 20,
                            g_htf_Bear_OB_Top, g_htf_Bear_OB_Bot,
                            clrIndianRed, 0.3, "Bear OB (HTF)");
                    }
                    break;
                }
            }
            break; // 只取最近的一个
        }
    }
}

//+------------------------------------------------------------------+
//| 在高周期查找 FVG                                                  |
//+------------------------------------------------------------------+
void FindHTFFairValueGaps(int limit)
{
    double minSize = FVG_Min_Points * GetPoint();
    
    for(int i = 2; i < MathMin(limit, 20); i++)
    {
        double high0 = iHigh(_Symbol, HigherTimeframe, i-1);
        double low0 = iLow(_Symbol, HigherTimeframe, i-1);
        double high1 = iHigh(_Symbol, HigherTimeframe, i+1);
        double low1 = iLow(_Symbol, HigherTimeframe, i+1);
        
        // 看涨FVG
        if(low0 > high1)
        {
            double fvgSize = low0 - high1;
            if(fvgSize >= minSize)
            {
                g_htf_Bull_FVG_Top = low0;
                g_htf_Bull_FVG_Bot = high1;
                
                if(ShowFVG)
                {
                    string name = objectPrefix + "FVG_Bull_HTF";
                    CreateRectangle(name,
                        iTime(_Symbol, HigherTimeframe, i+1),
                        iTime(_Symbol, HigherTimeframe, 0) + PeriodSeconds(HigherTimeframe) * 30,
                        g_htf_Bull_FVG_Top, g_htf_Bull_FVG_Bot,
                        clrLimeGreen, 0.15, "Bull FVG (HTF)");
                }
                break;
            }
        }
        
        // 看跌FVG
        if(high0 < low1)
        {
            double fvgSize = low1 - high0;
            if(fvgSize >= minSize)
            {
                g_htf_Bear_FVG_Top = low1;
                g_htf_Bear_FVG_Bot = high0;
                
                if(ShowFVG)
                {
                    string name = objectPrefix + "FVG_Bear_HTF";
                    CreateRectangle(name,
                        iTime(_Symbol, HigherTimeframe, i+1),
                        iTime(_Symbol, HigherTimeframe, 0) + PeriodSeconds(HigherTimeframe) * 30,
                        g_htf_Bear_FVG_Top, g_htf_Bear_FVG_Bot,
                        clrRed, 0.15, "Bear FVG (HTF)");
                }
                break;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| 查找流动性区域                                                    |
//+------------------------------------------------------------------+
void FindLiquidityZones(int limit)
{
    ENUM_TIMEFRAMES tf = UseMultiTimeframe ? LowerTimeframe : _Period;
    
    // 查找摆动高点和低点
    for(int i = limit-1; i >= (int)SwingPeriod; i--)
    {
        // 查找摆动高点
        if(IsSwingHigh(i, (int)SwingPeriod, tf))
        {
            double highPrice = iHigh(_Symbol, tf, i);
            string name = objectPrefix + "LZ_High_" + IntegerToString(i);
            
            // 创建流动性区域对象（用于PinBar判断）
            CreateLiquidityRectangle(
                name + "_Zone",
                iTime(_Symbol, tf, i+1),
                iTime(_Symbol, tf, i-1),
                highPrice + 5*GetPoint(),
                highPrice - 10*GetPoint(),
                BearishColor,
                LiquidityAreaOpacity,
                "Liquidity High"
            );
            
            // 检查是否为假突破
            CheckForLiquidityGrab(i, highPrice, true, tf);
        }
        
        // 查找摆动低点
        if(IsSwingLow(i, (int)SwingPeriod, tf))
        {
            double lowPrice = iLow(_Symbol, tf, i);
            string name = objectPrefix + "LZ_Low_" + IntegerToString(i);
            
            // 创建流动性区域对象（用于PinBar判断）
            CreateLiquidityRectangle(
                name + "_Zone",
                iTime(_Symbol, tf, i+1),
                iTime(_Symbol, tf, i-1),
                lowPrice + 10*GetPoint(),
                lowPrice - 5*GetPoint(),
                BullishColor,
                LiquidityAreaOpacity,
                "Liquidity Low"
            );
            
            // 检查是否为假突破
            CheckForLiquidityGrab(i, lowPrice, false, tf);
        }
    }
}

//+------------------------------------------------------------------+
//| 检查流动性猎杀（假突破）                                          |
//+------------------------------------------------------------------+
void CheckForLiquidityGrab(int barIndex, double levelPrice, bool isHigh, ENUM_TIMEFRAMES tf)
{
    double maxDeviation = LiquidityGrab_Deviation_Points * GetPoint();
    
    for(int j = 1; j <= LiquidityGrab_LookForward; j++)
    {
        int futureBar = barIndex - j;
        if(futureBar < 0) break;
        
        if(isHigh)
        {
            // 检查高点之上的突破
            if(iHigh(_Symbol, tf, futureBar) > levelPrice + maxDeviation)
            {
                // 检查是否收盘回到下方（假突破）
                if(iClose(_Symbol, tf, futureBar) < levelPrice)
                {
                    string name = objectPrefix + "LG_High_" + IntegerToString(barIndex);
                    CreateRectangle(
                        name,
                        iTime(_Symbol, tf, futureBar),
                        iTime(_Symbol, tf, barIndex),
                        iHigh(_Symbol, tf, futureBar),
                        levelPrice,
                        clrRed,
                        0.1,
                        "Liquidity Grab"
                    );
                    break;
                }
            }
        }
        else
        {
            // 检查低点之下的突破
            if(iLow(_Symbol, tf, futureBar) < levelPrice - maxDeviation)
            {
                // 检查是否收盘回到上方（假突破）
                if(iClose(_Symbol, tf, futureBar) > levelPrice)
                {
                    string name = objectPrefix + "LG_Low_" + IntegerToString(barIndex);
                    CreateRectangle(
                        name,
                        iTime(_Symbol, tf, futureBar),
                        iTime(_Symbol, tf, barIndex),
                        levelPrice,
                        iLow(_Symbol, tf, futureBar),
                        clrLimeGreen,
                        0.1,
                        "Liquidity Grab"
                    );
                    break;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| 查找订单区块                                                      |
//+------------------------------------------------------------------+
void FindOrderBlocks(int limit)
{
    ENUM_TIMEFRAMES tf = UseMultiTimeframe ? LowerTimeframe : _Period;
    
    for(int i = limit-1; i >= (int)SwingPeriod + Impulse_Bars_Count; i--)
    {
        // 查找强势推动行情
        if(IsStrongImpulse(i, Impulse_Bars_Count, tf))
        {
            // 查找推动行情前的最后一根反向K线
            int obBar = FindOrderBlockBar(i, 10, tf);
            
            if(obBar > 0 && obBar < i)
            {
                // 检查是否是看涨订单区块
                if(iClose(_Symbol, tf, i) > iOpen(_Symbol, tf, i) &&  // 当前是阳线
                   iClose(_Symbol, tf, obBar) < iOpen(_Symbol, tf, obBar))  // 订单区块是阴线
                {
                    CreateOrderBlockRectangle(obBar, true, tf);
                }
                // 检查是否是看跌订单区块
                else if(iClose(_Symbol, tf, i) < iOpen(_Symbol, tf, i) &&  // 当前是阴线
                       iClose(_Symbol, tf, obBar) > iOpen(_Symbol, tf, obBar))  // 订单区块是阳线
                {
                    CreateOrderBlockRectangle(obBar, false, tf);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| 查找订单区块K线                                                   |
//+------------------------------------------------------------------+
int FindOrderBlockBar(int startBar, int lookback, ENUM_TIMEFRAMES tf)
{
    int endBar = MathMax(0, startBar - lookback);
    double startClose = iClose(_Symbol, tf, startBar);
    double startOpen = iOpen(_Symbol, tf, startBar);
    bool isBullish = startClose > startOpen;
    
    for(int i = startBar-1; i >= endBar; i--)
    {
        double close = iClose(_Symbol, tf, i);
        double open = iOpen(_Symbol, tf, i);
        
        // 查找反向K线
        if((isBullish && close < open) || (!isBullish && close > open))
        {
            // 检查后续是否有强势推动
            int nextBars = MathMin(Impulse_Bars_Count, i - endBar);
            double move = 0;
            
            for(int j = 1; j <= nextBars; j++)
            {
                if(i-j >= 0)
                {
                    if(isBullish)
                        move += iClose(_Symbol, tf, i-j) - iOpen(_Symbol, tf, i-j);
                    else
                        move += iOpen(_Symbol, tf, i-j) - iClose(_Symbol, tf, i-j);
                }
            }
            
            // 推动幅度至少是平均K线实体的3倍
            if(MathAbs(move) > 3 * AverageBody(20, tf))
            {
                return i;
            }
        }
    }
    
    return -1;
}

//+------------------------------------------------------------------+
//| 创建订单区块矩形                                                   |
//+------------------------------------------------------------------+
void CreateOrderBlockRectangle(int barIndex, bool isBullish, ENUM_TIMEFRAMES tf)
{
    string name = objectPrefix + "OB_" + (isBullish ? "Bull_" : "Bear_") + IntegerToString(barIndex);
    
    double high = iHigh(_Symbol, tf, barIndex);
    double low = iLow(_Symbol, tf, barIndex);
    
    color obColor = isBullish ? BullishColor : BearishColor;
    string text = isBullish ? "Bull OB" : "Bear OB";
    
    // 使用K线数计算延伸宽度
    datetime startTime = iTime(_Symbol, tf, barIndex);
    datetime endTime = startTime + PeriodSeconds(tf) * OrderBlock_Width_Bars;
    
    CreateRectangle(
        name,
        startTime,
        endTime,
        high,
        low,
        obColor,
        0.3,
        text
    );
}

//+------------------------------------------------------------------+
//| 查找公允价值缺口(FVG)                                             |
//+------------------------------------------------------------------+
void FindFairValueGaps(int limit, bool higherTrendBullish, bool higherTrendBearish)
{
    ENUM_TIMEFRAMES tf = UseMultiTimeframe ? LowerTimeframe : _Period;
    double minSize = FVG_Min_Points * GetPoint();
    
    for(int i = limit-1; i >= 2; i--)
    {
        double high1 = iHigh(_Symbol, tf, i+1);
        double low1 = iLow(_Symbol, tf, i+1);
        double high2 = iHigh(_Symbol, tf, i);
        double low2 = iLow(_Symbol, tf, i);
        double high0 = iHigh(_Symbol, tf, i-1);
        double low0 = iLow(_Symbol, tf, i-1);
        
        // 看涨FVG: 当前K线最低价 > 前一根K线最高价
        if(low0 > high1)
        {
            double fvgSize = low0 - high1;
            if(fvgSize >= minSize)
            {
                string name = objectPrefix + "FVG_Bull_" + IntegerToString(i);
                datetime startTime = iTime(_Symbol, tf, i+1);
                datetime endTime = startTime + PeriodSeconds(tf) * FVG_Bars_Extends;
                
                CreateRectangle(
                    name,
                    startTime,
                    endTime,
                    low0,
                    high1,
                    clrLimeGreen,
                    0.15,
                    "Bull FVG"
                );
            }
        }
        
        // 看跌FVG: 当前K线最高价 < 前一根K线最低价
        if(high0 < low1)
        {
            double fvgSize = low1 - high0;
            if(fvgSize >= minSize)
            {
                string name = objectPrefix + "FVG_Bear_" + IntegerToString(i);
                datetime startTime = iTime(_Symbol, tf, i+1);
                datetime endTime = startTime + PeriodSeconds(tf) * FVG_Bars_Extends;
                
                CreateRectangle(
                    name,
                    startTime,
                    endTime,
                    low1,
                    high0,
                    clrRed,
                    0.15,
                    "Bear FVG"
                );
            }
        }
    }
}

//+------------------------------------------------------------------+
//| 查找PinBar信号                                                    |
//+------------------------------------------------------------------+
void FindPinBarSignals(int limit, bool higherTrendBullish, bool higherTrendBearish)
{
    ENUM_TIMEFRAMES tf = UseMultiTimeframe ? LowerTimeframe : _Period;
    int signalCount = 0;
    
    for(int i = MathMin(limit-1, PinBar_LookBack); i >= 1; i--)
    {
        if(signalCount >= MaxSignalsToShow) break;
        
        double open = iOpen(_Symbol, tf, i);
        double close = iClose(_Symbol, tf, i);
        double high = iHigh(_Symbol, tf, i);
        double low = iLow(_Symbol, tf, i);
        double range = high - low;
        
        if(range == 0) continue;
        
        double bodyTop = MathMax(open, close);
        double bodyBot = MathMin(open, close);
        
        // 使用影线占比判断 PinBar (像 Hunter_Pro)
        bool isBullPinBar = ((bodyBot - low) / range) >= PinBar_Wick_Ratio;
        bool isBearPinBar = ((high - bodyTop) / range) >= PinBar_Wick_Ratio;
        
        // 检查是否刺入高周期关键区域
        bool inBullishZone = false;
        bool inBearishZone = false;
        
        if(UseMultiTimeframe)
        {
            // 看涨信号：低点刺入看涨OB或FVG区域
            if(g_htf_Bull_OB_Top > 0 && low <= g_htf_Bull_OB_Top && low >= g_htf_Bull_OB_Bot)
                inBullishZone = true;
            if(g_htf_Bull_FVG_Top > 0 && low <= g_htf_Bull_FVG_Top && low >= g_htf_Bull_FVG_Bot)
                inBullishZone = true;
            
            // 看跌信号：高点刺入看跌OB或FVG区域
            if(g_htf_Bear_OB_Top > 0 && high >= g_htf_Bear_OB_Bot && high <= g_htf_Bear_OB_Top)
                inBearishZone = true;
            if(g_htf_Bear_FVG_Top > 0 && high >= g_htf_Bear_FVG_Bot && high <= g_htf_Bear_FVG_Top)
                inBearishZone = true;
        }
        else
        {
            // 非多周期模式：检查低周期区域
            inBullishZone = IsPinBarInKeyArea(i, tf);
            inBearishZone = inBullishZone;
        }
        
        // 看涨信号
        if(isBullPinBar && inBullishZone)
        {
            bool showSignal = RangingMode || !UseMultiTimeframe || higherTrendBullish;
            if(showSignal)
            {
                DisplayEntrySignal(i, tf, true);
                signalCount++;
            }
        }
        
        // 看跌信号
        if(isBearPinBar && inBearishZone)
        {
            bool showSignal = RangingMode || !UseMultiTimeframe || higherTrendBearish;
            if(showSignal)
            {
                DisplayEntrySignal(i, tf, false);
                signalCount++;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| 判断PinBar是否在关键区域 (用于非多周期模式)                        |
//+------------------------------------------------------------------+
bool IsPinBarInKeyArea(int barIndex, ENUM_TIMEFRAMES tf)
{
    double high = iHigh(_Symbol, tf, barIndex);
    double low = iLow(_Symbol, tf, barIndex);
    
    // 获取所有图形对象
    int total = ObjectsTotal(0, 0, -1);
    
    for(int i = 0; i < total; i++)
    {
        string name = ObjectName(0, i, 0, -1);
        
        if(StringFind(name, objectPrefix) == 0)
        {
            // 检查是否为订单区块或流动性区域
            if(StringFind(name, "OB_") > 0 || StringFind(name, "LZ_") > 0 || StringFind(name, "FVG_") > 0)
            {
                int objType = (int)ObjectGetInteger(0, name, OBJPROP_TYPE);
                
                if(objType == OBJ_RECTANGLE)
                {
                    double price1 = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
                    double price2 = ObjectGetDouble(0, name, OBJPROP_PRICE, 1);
                    double top = MathMax(price1, price2);
                    double bottom = MathMin(price1, price2);
                    
                    // 检查PinBar影线是否刺入区域（比收盘价更合理）
                    if(low <= top && low >= bottom)  // 低点刺入
                        return true;
                    if(high <= top && high >= bottom)  // 高点刺入
                        return true;
                }
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| 显示入场信号                                                      |
//+------------------------------------------------------------------+
void DisplayEntrySignal(int barIndex, ENUM_TIMEFRAMES tf, bool isBullish)
{
    string name = objectPrefix + "ENTRY_" + IntegerToString(barIndex);
    double high = iHigh(_Symbol, tf, barIndex);
    double low = iLow(_Symbol, tf, barIndex);
    double close = iClose(_Symbol, tf, barIndex);
    
    // 计算入场价和止损价
    double entryPrice, stopLoss;
    string signalText;
    
    if(isBullish)
    {
        // 看涨：入场价为收盘价，止损为低点下方
        entryPrice = close;
        stopLoss = low - 20 * GetPoint();
        signalText = "LONG";
    }
    else
    {
        // 看跌：入场价为收盘价，止损为高点上方
        entryPrice = close;
        stopLoss = high + 20 * GetPoint();
        signalText = "SHORT";
    }
    
    // 绘制醒目的入场箭头（大号）
    double arrowPrice = isBullish ? low - 15*GetPoint() : high + 15*GetPoint();
    CreateArrow(
        name + "_Arrow",
        iTime(_Symbol, tf, barIndex),
        arrowPrice,
        isBullish ? 233 : 234,
        isBullish ? clrLimeGreen : clrRed,
        3,  // 更大的箭头
        signalText
    );
    
    // 绘制信号标签
    CreateTextLabel(
        name + "_Label",
        iTime(_Symbol, tf, barIndex),
        arrowPrice + (isBullish ? -20*GetPoint() : 20*GetPoint()),
        signalText + " Entry: " + DoubleToString(entryPrice, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
        isBullish ? clrLimeGreen : clrRed,
        10  // 更大的字体
    );
    
    // 绘制止损水平线
    CreateHorizontalLine(
        name + "_SL",
        iTime(_Symbol, tf, barIndex),
        stopLoss,
        isBullish ? clrDodgerBlue : clrOrange,
        STYLE_DASH,
        2,
        "SL: " + DoubleToString(stopLoss, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS))
    );
}

//+------------------------------------------------------------------+
//| 辅助函数：判断摆动高点                                            |
//+------------------------------------------------------------------+
bool IsSwingHigh(int barIndex, int period, ENUM_TIMEFRAMES tf)
{
    double high = iHigh(_Symbol, tf, barIndex);
    
    for(int i = 1; i <= period; i++)
    {
        if(iHigh(_Symbol, tf, barIndex + i) >= high ||
           iHigh(_Symbol, tf, barIndex - i) >= high)
            return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| 辅助函数：判断摆动低点                                            |
//+------------------------------------------------------------------+
bool IsSwingLow(int barIndex, int period, ENUM_TIMEFRAMES tf)
{
    double low = iLow(_Symbol, tf, barIndex);
    
    for(int i = 1; i <= period; i++)
    {
        if(iLow(_Symbol, tf, barIndex + i) <= low ||
           iLow(_Symbol, tf, barIndex - i) <= low)
            return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| 辅助函数：判断强势推动行情                                         |
//+------------------------------------------------------------------+
bool IsStrongImpulse(int startBar, int barsCount, ENUM_TIMEFRAMES tf)
{
    if(startBar < barsCount) return false;
    
    double totalMove = 0;
    int direction = 0;
    
    for(int i = 0; i < barsCount; i++)
    {
        int bar = startBar - i;
        if(bar < 0) break;
        
        double body = MathAbs(iClose(_Symbol, tf, bar) - iOpen(_Symbol, tf, bar));
        
        if(i == 0)
        {
            direction = iClose(_Symbol, tf, bar) > iOpen(_Symbol, tf, bar) ? 1 : -1;
        }
        else
        {
            int currentDir = iClose(_Symbol, tf, bar) > iOpen(_Symbol, tf, bar) ? 1 : -1;
            if(currentDir != direction) return false;
        }
        
        totalMove += body;
    }
    
    double avgBody = AverageBody(20, tf);
    return (totalMove / barsCount > avgBody * 1.5);
}

//+------------------------------------------------------------------+
//| 辅助函数：计算平均K线实体大小                                      |
//+------------------------------------------------------------------+
double AverageBody(int period, ENUM_TIMEFRAMES tf)
{
    double sum = 0;
    int count = MathMin(Bars(_Symbol, tf), period);
    
    if(count == 0) return 0;
    
    for(int i = 0; i < count; i++)
    {
        sum += MathAbs(iClose(_Symbol, tf, i) - iOpen(_Symbol, tf, i));
    }
    
    return sum / count;
}

//+------------------------------------------------------------------+
//| 辅助函数：创建矩形                                                 |
//+------------------------------------------------------------------+
void CreateRectangle(string name, datetime time1, datetime time2, double price1, double price2, 
                     color clr, double opacity, string text)
{
    if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
    
    ObjectCreate(0, name, OBJ_RECTANGLE, 0, time1, price1, time2, price2);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, name, OBJPROP_BACK, true);
    ObjectSetInteger(0, name, OBJPROP_FILL, true);
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);
    ObjectSetDouble(0, name, OBJPROP_LEVELVALUE, 0, opacity);
    
    if(text != "")
    {
        ObjectSetString(0, name, OBJPROP_TEXT, text);
    }
}

//+------------------------------------------------------------------+
//| 辅助函数：创建流动性区域矩形                                       |
//+------------------------------------------------------------------+
void CreateLiquidityRectangle(string name, datetime time1, datetime time2, double top, double bottom, 
                             color clr, double opacity, string text)
{
    CreateRectangle(name, time1, time2, top, bottom, clr, opacity, text);
}

//+------------------------------------------------------------------+
//| 辅助函数：创建水平线                                               |
//+------------------------------------------------------------------+
void CreateHorizontalLine(string name, datetime time, double price, color clr, ENUM_LINE_STYLE style, 
                          int width, string text)
{
    if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
    
    ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_STYLE, style);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
    ObjectSetInteger(0, name, OBJPROP_BACK, true);
    
    if(text != "")
    {
        ObjectSetString(0, name, OBJPROP_TEXT, "  " + text);
    }
}

//+------------------------------------------------------------------+
//| 辅助函数：创建箭头                                                 |
//+------------------------------------------------------------------+
void CreateArrow(string name, datetime time, double price, int arrowCode, color clr, int width, string text)
{
    if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
    
    ObjectCreate(0, name, OBJ_ARROW, 0, time, price);
    ObjectSetInteger(0, name, OBJPROP_ARROWCODE, arrowCode);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
    ObjectSetInteger(0, name, OBJPROP_BACK, false);
    
    if(text != "")
    {
        ObjectSetString(0, name, OBJPROP_TEXT, text);
    }
}

//+------------------------------------------------------------------+
//| 辅助函数：创建文字标签                                             |
//+------------------------------------------------------------------+
void CreateTextLabel(string name, datetime time, double price, string text, color clr, int fontSize)
{
    if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
    
    ObjectCreate(0, name, OBJ_TEXT, 0, time, price);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
    ObjectSetInteger(0, name, OBJPROP_BACK, false);
}

//+------------------------------------------------------------------+
//| 辅助函数：获取点值                                                 |
//+------------------------------------------------------------------+
double GetPoint()
{
    return SymbolInfoDouble(_Symbol, SYMBOL_POINT);
}