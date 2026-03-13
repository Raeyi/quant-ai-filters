//+------------------------------------------------------------------+
//|             XAUUSD_M5_Grid_Martingale_Pro_v4.1.mq5               |
//|             Copyright 2026, surrayi                              |
//|             M5黄金双向网格马丁 + 新闻 + 仪表盘 + 全风控 v4.1        |
//+------------------------------------------------------------------+
#property copyright "XAUUSD_M5_Grid_Martingale_Pro_v4.1.mq5 Copyright 2026, surrayi"
#property link      "https://github.com/Raeyi"
#property version   "4.10"
#property description "2025-2026黄金 M5优化版"

#include <Trade\Trade.mqh>
#include <Arrays\ArrayLong.mqh>

CTrade trade;
CArrayLong g_ProcessedTickets;

//--- 输入参数
input group "=== 基本设置 ==="
input ulong   MagicNumber         = 20260226; // EA的魔术数字
input bool    AutoStart           = true;    // EA是否在启动时自动启动
input bool    ManageManualTrades  = true;    // 是否管理手动交易
input double  BaseLot             = 0.01;   // 基础手数
input double  LotMultiplier       = 1.45;  // 手数倍数
input int     MaxBuyLevels        = 8;      // 最大买入网格数
input int     MaxSellLevels       = 6;    // 最大卖出网格数
input double  BasketTP            = 100.0;  // 篮子TP
input double  BasketSL            = -500.0;  // 篮子SL
input double  BasketTrailingStart = 60.0; // 篮子开始跟单
input double  TrailingStep        = 25.0; // 跟单步长

input group "=== M5优化参数 ==="
input bool    UseOnlyBuy          = true; // 只允许买入
input bool    UseATRAdaptive      = false; // 是否使用ATR自适应
input int     ATR_Period          = 14; // ATR周期
input double  ATR_Multiplier      = 0.8; // ATR倍数
input int     MinAddIntervalSec   = 180; // 最小加仓间隔
input int     MaxDailyTrades      = 25; // 每日最大交易数
input double  GridStepBuy         = 8.0;   // 买入网格间距
input double  GridStepSell        = 10.0;  // 卖出网格间距（UseOnlyBuy=true时可忽略）

input group "====== Pinbar参数 ======"
input double   PinbarBodyRatio  = 0.3;    // 实体与整根K线比例
input double   PinbarShadowRatio = 2.0;   // 影线与实体比例
input int      MinPinbarSize    = 30;     // 最小Pinbar点数（点）
input bool     UsePinbarEntry   = true;   // 使用Pinbar入场

input group "=== 时间与新闻过滤 ==="
input int     StartHour           = 8; // 交易开始时间
input int     EndHour             = 22; // 交易结束时间
input bool    CloseOnFriday       = true; // 周五强制平仓
input bool    UseNewsFilter       = true; // 是否使用新闻过滤
input int     NewsMinutesBefore   = 45; // 新闻前禁止交易
input int     NewsMinutesAfter    = 30; // 新闻后禁止交易

input group "=== 风控设置 ==="
input double  MaxSpreadUSD        = 0.25; // 最大允许的价差
input double  MinAccountEquity    = 800.0; // 最小账户权益
input double  MaxTotalLots        = 1.5;    // 最大总手数
input double  DailyMaxLossUSD     = -600.0;     // 每日最大亏损
input int     LossCooldownHours   = 6; // 亏损后冷却时间
input bool    UseTrendFilter      = true; // 是否使用趋势过滤
input int     MA_Period           = 50; // 趋势过滤的MA周期
input int     LogLevel           = 2; // 日志级别(0:基础日志, 1:错误, 2:关键操作, 3:详细日志)

input group "=== 智能马丁网格 ==="
input bool   UseDynamicBasketTP   = true;        // 开启动态TP
input bool   UseDynamicGrid     = true;          // 开启ATR动态步长
input bool   UseRSIForFirst     = true;          // 开启RSI首单过滤
input int    RSI_Period         = 14;
input double RSI_BuyLevel       = 35.0;          // RSI <= 此值才开BUY首单（调低到30增加频率）
input double RSI_SellLevel      = 65.0;          // RSI >= 此值才开SELL首单
input bool   UseNewBarForFirst  = true;          // 首单仅在新K线上检查（强烈推荐）

input group "=== Debug 设置 ==="
input bool    EnableDebugMode       = false; // 是否启用调试模式
input bool    ShowDebugInfo         = false; // 是否显示调试信息

//--- 全局变量
datetime today = 0; 
double   dailyPL = 0.0;
int      dailyTrades = 0;
datetime lastBigLoss = 0;
datetime lastBuyAdd = 0; 
datetime lastSellAdd = 0;
string   prefix = "XAUPro_";
int      ma_handle = INVALID_HANDLE;
static datetime lastBar = 0;
bool isNewBar = false;
double peakProfitBuy = 0;
double peakProfitSell = 0; 
double g_StopLevelUSD = 0.0;
datetime g_LastBreakevenAttempt = 0;
int atr_handle = INVALID_HANDLE;
int rsi_handle = INVALID_HANDLE;

enum ENUM_LOG_LEVEL
{
   LOG_BASE,      // 0: 基础日志
   LOG_ERROR,     // 1: 只记录错误
   LOG_NORMAL,    // 2: 关键操作
   LOG_DETAILED   // 3: 详细日志
};

// 日志频率类型枚举
enum ENUM_LOG_FREQ
{
   LOG_FREQ_TICK,        // 每个tick
   LOG_FREQ_SECOND,      // 按秒频率
   LOG_FREQ_MINUTE,      // 按分钟频率
   LOG_FREQ_BAR,         // 按K线频率
   LOG_FREQ_ONCE_PER_MSG // 每条消息只打印一次
};

// 日志函数
void LogPrint(int level, string msg)
{
   if(LogLevel >= level)
   {
      Print(msg);
   }
}

//+------------------------------------------------------------------+
int OnInit()
{   
    // 初始化交易对象
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(30);
    
    ma_handle = iMA(_Symbol, PERIOD_CURRENT, MA_Period, 0, MODE_EMA, PRICE_CLOSE);
    if(ma_handle == INVALID_HANDLE) LogPrint(LOG_ERROR, "MA handle创建失败，请检查参数");
    atr_handle = iATR(_Symbol, _Period, ATR_Period);
    if(atr_handle == INVALID_HANDLE) LogPrint(LOG_ERROR, "ATR handle创建失败，请检查参数");
    rsi_handle = iRSI(_Symbol, _Period, RSI_Period, PRICE_CLOSE);
    if(rsi_handle == INVALID_HANDLE) LogPrint(LOG_ERROR, "RSI handle创建失败，请检查参数");
    
    CreateDashboard(); 
    CreateDebugButton(); 

    LogPrint(LOG_BASE, "=== XAUUSD M5 Grid Pro v4.1 已启动 ===");
    if(StringFind(_Symbol,"XAU") == -1) Alert("警告：请在XAUUSD图表运行此EA！");

    g_StopLevelUSD = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
    PrintFormat("=== XAUUSD Stops Level: %.2f USD ===", g_StopLevelUSD);

    g_ProcessedTickets.Clear();
    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
    ObjectsDeleteAll(0, prefix);
    if(ma_handle != INVALID_HANDLE) IndicatorRelease(ma_handle);
    if(atr_handle != INVALID_HANDLE) IndicatorRelease(atr_handle);
    if(rsi_handle != INVALID_HANDLE) IndicatorRelease(rsi_handle);
}

void CheckNewBar()
{
   datetime barTime = iTime(_Symbol, _Period, 0);
   if(barTime != lastBar)
   {
      lastBar = barTime;
      isNewBar = true;
   }
   else
   {
      isNewBar = false;
   }
}

bool IsNewBar()
{
   return isNewBar;
}

//+------------------------------------------------------------------+
void OnTick()
{
    // 每日重置
    if(TimeCurrent() - today >= 86400)
    {
        dailyPL = 0.0;
        dailyTrades = 0;
        today = TimeCurrent() - (TimeCurrent() % 86400);
    }

    if(dailyPL <= DailyMaxLossUSD) {
        CloseAll("每日最大亏损保护");
        lastBigLoss = TimeCurrent();
        UpdateDashboard("🛑 每日亏损保护");
        return;
    }

    // 周五强制平仓（使用MqlDateTime修复）
    if(CloseOnFriday)
    {
        MqlDateTime tm;
        TimeToStruct(TimeCurrent(), tm); // 获取当前时间
        if(tm.day_of_week == 5 && tm.hour >= 20)   // Friday = 5 (Sunday=0), 20:00
        {   
            CloseAll("周五强制平仓");
            return;
        }
    }

    ManageBasket("BUY");
    if(!UseOnlyBuy) ManageBasket("SELL");

    if(AccountInfoDouble(ACCOUNT_EQUITY) < MinAccountEquity && !EnableDebugMode)
    {
        CloseAll("权益保护");
        return;
    }

    if(TimeCurrent() < lastBigLoss + LossCooldownHours*3600) return; // 亏损后冷却

    if(!IsTradingTime()) 
    { 
        UpdateDashboard("⚠️ 非交易时间");
        return; 
    }

    if(UseNewsFilter && IsNearHighImpactNews())
    {
        UpdateDashboard("🛑 新闻过滤中");
        if(IsNewBar())  // 如果是新K线
        {
            LogPrint(LOG_DETAILED, "📰 新闻过滤生效中");
        }
        return;
    }

    double spread = SymbolInfoDouble(_Symbol,SYMBOL_ASK) - SymbolInfoDouble(_Symbol,SYMBOL_BID);
    if(spread > MaxSpreadUSD) 
    {
        if(IsNewBar()) PrintFormat("⚠️ 点差过大: %.3f > %.3f", spread, MaxSpreadUSD);
        return;
    }

    // 手数检查
    double totalLots = GetTotalLots();
    if(totalLots >= MaxTotalLots) 
    {   
        string status = "⚠️ 总手数已达上限" + (string)totalLots + "/" + (string)MaxTotalLots;
        UpdateDashboard(status);
        if(IsNewBar()) PrintFormat("⚠️ 总手数已达上限: %.2f/%.2f", totalLots, MaxTotalLots);
        return;
    }
    // 交易次数检查
    if(dailyTrades >= MaxDailyTrades) 
    {   
        string status = "⚠️ 交易次数已达上限" + (string)dailyTrades + "/" + (string)MaxDailyTrades;
        UpdateDashboard(status);
        if(IsNewBar()) PrintFormat("⚠️ 已达最大日交易次数: %d/%d", dailyTrades, MaxDailyTrades);
        return;
    }

    CheckNewBar();

    if(dailyTrades < MaxDailyTrades && IsNewBar())
    {   
        CheckNewEntry("BUY");
        if(!UseOnlyBuy) CheckNewEntry("SELL");
    }

    UpdateDashboard("");
    
}

//+------------------------------------------------------------------+
bool IsTradingTime()
{
   MqlDateTime tm; TimeToStruct(TimeCurrent(), tm);
   return (tm.hour >= StartHour && tm.hour < EndHour);
}

//+------------------------------------------------------------------+
// 检查是否临近重大新闻
//+------------------------------------------------------------------+
bool IsNearHighImpactNews()
{
   MqlCalendarValue values[];
   datetime from = TimeCurrent() - 7200; // 2小时前
   datetime to   = TimeCurrent() + 86400; // 1天后
   int total = CalendarValueHistory(values, from, to); // 获取新闻事件

   if(total == 0) return false;
   for(int i = 0; i < total; i++)
   {
      MqlCalendarEvent ev;
      if(CalendarEventById(values[i].event_id, ev))
      {
         if(ev.importance >= CALENDAR_IMPORTANCE_HIGH)
         {
            long timeDiff = values[i].time - TimeCurrent();
            bool isBefore = (timeDiff > 0) && (timeDiff <= NewsMinutesBefore * 60);
            bool isAfter  = (timeDiff <= 0) && (-timeDiff <= NewsMinutesAfter * 60);
            if(isBefore || isAfter)
            {
                string eventName = ev.name;
                string prevStr = (values[i].prev_value != 0) ? DoubleToString(values[i].prev_value, _Digits) : "";
                string foreStr = (values[i].forecast_value != 0) ? DoubleToString(values[i].forecast_value, _Digits) : "";

                //PrintFormat
                if(IsNewBar()) PrintFormat("新闻事件: %s | 时间: %s | 重要性: %d | 前值: %s | 预测: %s",
                            eventName,
                            TimeToString(values[i].time),
                            ev.importance,
                            prevStr,
                            foreStr);
                return true;
            } 
        }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
// 检查是否需要开仓
//+------------------------------------------------------------------+
double GetTotalLots()
{   
    double lots = 0.0;
    for(int i = PositionsTotal()-1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
            ulong magic = PositionGetInteger(POSITION_MAGIC);
            if(magic == MagicNumber || (ManageManualTrades && magic == 0))
                lots += PositionGetDouble(POSITION_VOLUME);
        }
    }
    return lots;
}

int GetBasketCount(string dir)
{
   bool isBuy = (dir == "BUY");
   int cnt = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(isBuy != (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)) continue;
      ulong magic = PositionGetInteger(POSITION_MAGIC);
      if(magic == MagicNumber || (ManageManualTrades && magic == 0)) cnt++; // 忽略手动交易
   }
   return cnt;
}

//+------------------------------------------------------------------+
// 获取网格极限价格
//+------------------------------------------------------------------+
double GetBasketExtremePrice(string dir)
{
    bool isBuy = (dir == "BUY");
    double extremePrice = 0.0;

    for(int i = PositionsTotal()-1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(isBuy != (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)) continue;

        ulong magic = PositionGetInteger(POSITION_MAGIC);
        if(magic == MagicNumber || (ManageManualTrades && magic == 0))
        {
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            if(openPrice == 0 || (isBuy ? openPrice < extremePrice : openPrice > extremePrice)) extremePrice = openPrice;
        }
    }
   return extremePrice;
}

double GetBasketProfit(string dir)
{
   bool isBuy = (dir == "BUY");
   double profit = 0.0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(isBuy != (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)) continue;
      ulong magic = PositionGetInteger(POSITION_MAGIC);
      if(magic == MagicNumber || (ManageManualTrades && magic == 0))
         profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return profit;
}

//+------------------------------------------------------------------+
// RSI首单过滤条件（加仓永远通过）
//+------------------------------------------------------------------+
bool IsGoodFirstEntry(bool isBuy)
{
    // 如果两个过滤都不使用，直接返回true
    if(!UseRSIForFirst && !UsePinbarEntry) return true;
   
    bool rsiCondition = UseRSIForFirst ? CheckRSICondition(isBuy) : true;
    bool pinbarCondition = UsePinbarEntry ? CheckPinbarCondition(isBuy) : true;
   
    // 综合条件判断
    bool finalCondition = rsiCondition && pinbarCondition;
   
    if(!finalCondition)
    {
        Print("条件不满足: RSI=" + (string)rsiCondition + ", Pinbar=" + (string)pinbarCondition);
    }
   
    return finalCondition;
}

bool CheckRSICondition(bool isBuy)
{
    double rsi[];
    if(CopyBuffer(rsi_handle, 0, 1, 1, rsi) <= 0)
    {
        Print("无法获取RSI值，使用默认条件");
        return true;
    }
   
    Print("前一根K线RSI值: " + (string)rsi[0]);
    return isBuy ? (rsi[0] <= RSI_BuyLevel) : (rsi[0] >= RSI_SellLevel);
}

bool CheckPinbarCondition(bool isBuy)
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
   
    if(CopyRates(_Symbol, PERIOD_CURRENT, 0, 3, rates) < 3)
    {
        Print("无法获取K线数据，使用默认条件");
        return true;
    }

    if(!CheckPinbar(rates[1]))
    {
        Print("前一根K线不是Pinbar");
        return false;
    }
   
    // 计算Pinbar大小（点数）
    double pinbarSize = (rates[1].high - rates[1].low) / _Point;
    if(pinbarSize < MinPinbarSize)
    {
        Print("Pinbar太小: " + (string)pinbarSize + " 点，小于最小要求: " + (string)MinPinbarSize);
        return false;
    }
   
    // 检查Pinbar方向
    bool isBullish = IsBullishPinbar(rates[1]);
    bool isBearish = IsBearishPinbar(rates[1]);
   
    if(isBuy && !isBullish)
    {
        Print("Pinbar方向不匹配: 需要看涨Pinbar");
        return false;
    }
    else if(!isBuy && !isBearish)
    {
        Print("Pinbar方向不匹配: 需要看跌Pinbar");
        return false;
    }
   
    Print("检测到" + (isBuy ? "看涨" : "看跌") + "Pinbar，大小: " + (string)pinbarSize + " 点");
    return true;
}

//+------------------------------------------------------------------+
// 获取网格步长
//+------------------------------------------------------------------+
double GetGridStep(bool isBuy)
{
   if(UseATRAdaptive)
   {
      double atr[];
      if(CopyBuffer(iATR(_Symbol, PERIOD_CURRENT, ATR_Period), 0, 0, 1, atr) > 0)
        return NormalizeDouble(atr[0] * ATR_Multiplier, _Digits); 
   }
   return isBuy ? GridStepBuy : GridStepSell;
}

double NormalizeLot(double lots)
{
   double minv = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxv = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step == 0) step = 0.01;
   lots = MathMax(minv, MathMin(maxv, lots));
   return MathRound(lots / step) * step;
}

void CloseAll(string reason)
{
    Print("CloseAll " + reason);
    g_ProcessedTickets.Clear();

    for(int i = PositionsTotal()-1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
            ulong magic = PositionGetInteger(POSITION_MAGIC);
            if(magic == MagicNumber || (ManageManualTrades && magic == 0))
            trade.PositionClose(ticket);
        }
    }
    if(IsNewBar()) LogPrint(LOG_NORMAL, "=== 全部平仓完成 === " + reason);
    if(StringFind(reason, "亏损") != -1 || StringFind(reason, "保护") != -1) lastBigLoss = TimeCurrent();
}

// 篮子管理、保本、部分平仓
void ManageBasket(string dir) {
    if(GetBasketCount(dir) == 0) return; 

    double profit = GetBasketProfit(dir); 

    if(profit >= BasketTP || profit <= BasketSL) 
    { 
        CloseAll(dir + " 固定TP/SL"); 
        return;
    }

    if(profit >= BasketTrailingStart) 
    {
        if(dir == "BUY") {
            if(profit > peakProfitBuy) peakProfitBuy = profit;
            if(peakProfitBuy - profit >= TrailingStep) {
                CloseAll(dir + " 浮动止盈触发");
                peakProfitBuy = 0; 
                return;
            }
        } else {
            if(profit > peakProfitSell) peakProfitSell = profit;
            if(peakProfitSell - profit >= TrailingStep) {
                CloseAll(dir + " 浮动止盈触发");
                peakProfitSell = 0;
                return;
            }
        }
    }

    // if(GetBasketCount(dir) >= 4) MoveToBreakeven(dir);

    if(profit >= BasketTP * 0.6 && GetBasketCount(dir) >= 3) PartialClose(dir, 0.5);
}

// 保本移SL
void MoveToBreakeven(string dir)
{
    if(TimeCurrent() - g_LastBreakevenAttempt < 30) return; 
    g_LastBreakevenAttempt = TimeCurrent();

    bool isBuy = (dir == "BUY");
    double smallProfit = 3;
    double buffer      = g_StopLevelUSD * 10.0 + 0.8;

    double basketProfit = GetBasketProfit(dir);
    int    basketCount  = GetBasketCount(dir);

    for(int i = PositionsTotal()-1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(isBuy != (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)) continue;
        ulong magic = PositionGetInteger(POSITION_MAGIC);
        if(magic != MagicNumber && !(ManageManualTrades && magic == 0)) continue;

        if(g_ProcessedTickets.Search(ticket) >= 0) continue;

        datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);

        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double curTP     = PositionGetDouble(POSITION_TP);
        double newTP     = isBuy ? (openPrice + smallProfit) : (openPrice - smallProfit);
        newTP = NormalizeDouble(newTP, _Digits);

        double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double distance     = MathAbs(newTP - currentPrice);

        if(distance < buffer)
        {
            if(IsNewBar()) PrintFormat("⚠️ %s SL距离不足 %.2f < %.2f，等待下次", dir, distance, buffer);
            continue;
        }

        bool needModify = (curTP == 0) || (isBuy ? newTP > curTP : newTP < curTP);

        if(needModify)
        {
            if(trade.PositionModify(ticket, PositionGetDouble(POSITION_TP), newTP))
            {
                g_ProcessedTickets.Add(ticket);
                PrintFormat("✅ %s 保本移SL成功 Ticket=%I64u 新SL=%.2f", dir, ticket, newTP);
            }
            else
            {
                PrintFormat("❌ %s 保本移SL失败 Ticket=%I64u 新SL=%.2f 错误:%d", dir, ticket, newTP, GetLastError());
            }
        }
    }
}

// 部分平仓（锁利）
void PartialClose(string dir, double ratio)
{
   bool isBuy = (dir == "BUY");
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(isBuy != (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)) continue;
      ulong magic = PositionGetInteger(POSITION_MAGIC);
      if(magic != MagicNumber && !(ManageManualTrades && magic == 0)) continue;

      double vol = PositionGetDouble(POSITION_VOLUME);
      double closeVol = NormalizeLot(vol * ratio);
      if(closeVol > 0.001)
      {
         if(trade.PositionClosePartial(ticket, closeVol))
            PrintFormat("✅ %s 部分平仓 %.2f手", dir, closeVol);
      }
   }
}

//+------------------------------------------------------------------+
// 检查是否需要开仓
//+------------------------------------------------------------------+
void CheckNewEntry(string dir)
{   
    bool isBuy = (dir == "BUY");
    int maxLev = isBuy ? MaxBuyLevels : MaxSellLevels;
    int basketCount = GetBasketCount(dir);

    if(basketCount >= maxLev) 
    {
        if(IsNewBar()) PrintFormat("❌ 已达最大层数%d", maxLev);
        return;
    }
    
    datetime lastTime = isBuy ? lastBuyAdd : lastSellAdd;

    int timeSinceLast = (int)(TimeCurrent() - lastTime); 
    if(timeSinceLast < MinAddIntervalSec) 
    {   
        if(IsNewBar())
            PrintFormat("⏰ 加仓冷却中: 距离上次%d秒, 还需%d秒", 
                        timeSinceLast, MinAddIntervalSec - timeSinceLast);
        return;
    }
    double extreme = GetBasketExtremePrice(dir);
    double price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double gStep = GetGridStep(isBuy);
    
    double maValue = 0;
    bool needOpen = false;
    double lot = BaseLot;
    
   
    // 自动开仓
    if(basketCount == 0)
    {   
        if(AutoStart && IsGoodFirstEntry(isBuy)) 
        {
            needOpen = true;
            LogPrint(LOG_NORMAL, "✅ 满足首单条件(RSI过滤通过)");
        }
        else
        {   
            LogPrint(LOG_NORMAL, "❌ RSI条件不满足， 无法开首单");
        }
    }
    else // 加仓逻辑
    {    
        // 价格条件是否满足
        bool priceCondition = false;
        // 检查价格条件
        double priceDiff = MathAbs(price - extreme);

        // 对于BUY篮子，价格下跌到极端价格以下才加仓
        if(isBuy && price <= extreme - gStep) 
        {
            priceCondition = true;
            if(IsNewBar())
                PrintFormat("✅ 价格条件满足: %.2f ≤ %.2f - %.2f", price, extreme, gStep);
        }
        // 对于SELL篮子，价格上涨到极端价格以上才加仓
        else if(!isBuy && price >= extreme + gStep) 
        {
            priceCondition = true;
            if(IsNewBar())
                PrintFormat("✅ 价格条件满足: %.2f ≥ %.2f + %.2f", price, extreme, gStep);
        }
        else
        {   if(IsNewBar())
                PrintFormat("❌ %s价格条件不满足: 价差=%.2f, 需要≥%.2f", 
                        dir, priceDiff, gStep);
        }
        
        if(priceCondition) 
        {
            needOpen = true;
            // 计算手数
            lot = BaseLot * MathPow(LotMultiplier, basketCount);
            if(IsNewBar())
                PrintFormat("计算手数: %.2f * %.2f^%d = %.2f", BaseLot, LotMultiplier, basketCount, lot);
        }
    }

    if(needOpen)
    {    
            // 手数调整
            lot = NormalizeLot(lot);
            double totalLots = GetTotalLots();
            double availableLots = MaxTotalLots - totalLots;
            
            if(IsNewBar())
                PrintFormat("手数调整前: %.4f, 总手数: %.4f, 可用额度: %.4f", 
                            lot, totalLots, availableLots);
            
            if(lot + totalLots > MaxTotalLots) 
            {
                lot = NormalizeLot(availableLots);
                if(IsNewBar())
                    PrintFormat("手数调整为: %.4f (受MaxTotalLots限制)", lot);
            }
            
            if(lot < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) 
            {   
                if(IsNewBar())
                    Print("❌ 手数低于最小交易量");
                return;
            }

            // 趋势过滤检查
            if(UseTrendFilter)
            {
                double ma_buf[];
                if(CopyBuffer(ma_handle, 0, 0, 1, ma_buf) > 0)
                {
                    maValue = ma_buf[0];
                    bool trendCondition = (isBuy && price >= maValue) || (!isBuy && price <= maValue);
                    
                    if(IsNewBar())
                        PrintFormat("MA(%d)=%.2f, 趋势条件: %s", 
                                MA_Period, maValue, trendCondition ? "通过" : "失败");
                    
                    if(!trendCondition) 
                    {   
                        if(IsNewBar())
                            Print("❌ 趋势过滤阻止开仓");
                        return;
                    }
                }
                else
                {   if(IsNewBar())
                        Print("⚠️ 无法获取MA值");
                }
            }

            // 最终开仓
            if(IsNewBar())
                PrintFormat("【准备开仓】方向=%s, 手数=%.2f, 价格=%.2f", dir, lot, price);
            bool res = isBuy ? trade.Buy(lot) : trade.Sell(lot);
            
            if(res)
            {
                if(isBuy) lastBuyAdd = TimeCurrent(); else lastSellAdd = TimeCurrent();
                dailyTrades++;
                if(IsNewBar())
                    PrintFormat("✅ 【%s开仓成功】第%d层 手数%.2f 价格%.2f", 
                                dir, GetBasketCount(dir), lot, price);
            }
            else
            {   if(IsNewBar())
                    PrintFormat("❌ 【开仓失败】错误码: %d", GetLastError());
            }
        }
        else
        {   if(IsNewBar())
                Print("ℹ️ 不满足开仓条件");
        }
}

//+------------------------------------------------------------------+
//| 检查Pinbar形态                                                   |
//+------------------------------------------------------------------+
bool CheckPinbar(MqlRates &rate) {
   double bodySize = MathAbs(rate.close - rate.open);
   double totalRange = rate.high - rate.low;
   
   if(totalRange == 0) return false;
   
   // 检查实体比例
   double bodyRatio = bodySize / totalRange;
   if(bodyRatio > PinbarBodyRatio) return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| 检查看涨Pinbar                                                  |
//+------------------------------------------------------------------+
bool IsBullishPinbar(MqlRates &rate) {
   if(rate.close <= rate.open) return false; // 必须是阳线
   
   double bodySize = rate.close - rate.open;
   double lowerShadow = rate.open - rate.low;
   double upperShadow = rate.high - rate.close;
   
   // 检查下影线长度
   if(lowerShadow > bodySize * PinbarShadowRatio && upperShadow < bodySize) {
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| 检查看跌Pinbar                                                  |
//+------------------------------------------------------------------+
bool IsBearishPinbar(MqlRates &rate) {
   if(rate.close >= rate.open) return false; // 必须是阴线
   
   double bodySize = rate.open - rate.close;
   double upperShadow = rate.high - rate.open;
   double lowerShadow = rate.close - rate.low;
   
   // 检查上影线长度
   if(upperShadow > bodySize * PinbarShadowRatio && lowerShadow < bodySize) {
      return true;
   }
   
   return false;
}

// ==================== 【全新中文仪表盘 v3.2】 ====================
void CreateDashboard()
{
   ObjectsDeleteAll(0, prefix);
   
   // 背景面板（更大、更美观）
   ObjectCreate(0, prefix+"bg", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, prefix+"bg", OBJPROP_XDISTANCE, 8);
   ObjectSetInteger(0, prefix+"bg", OBJPROP_YDISTANCE, 8);
   ObjectSetInteger(0, prefix+"bg", OBJPROP_XSIZE, 360);
   ObjectSetInteger(0, prefix+"bg", OBJPROP_YSIZE, 330);
   ObjectSetInteger(0, prefix+"bg", OBJPROP_BGCOLOR, C'12,22,48');
   ObjectSetInteger(0, prefix+"bg", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, prefix+"bg", OBJPROP_COLOR, clrGold);
   ObjectSetInteger(0, prefix+"bg", OBJPROP_WIDTH, 2);

   // 创建6个中文标签
   string names[] = {"Title","BuyLabel","SellLabel","TotalLabel","EquityLabel","TradeCountLabel","PositionSizeLabel","StatusLabel", "RiskLabel"};
   string initTexts[] = {
      "=== XAUUSD M5 网格马丁 Pro v3.2 ===",
      "买入篮子: 等待开仓",
      "卖出篮子: 已关闭",
      "总盈亏: 0.0 USD",
      "账户权益: 0 USD",
      "今日交易次数: 0 次",
      "当前持仓手数: 0.0 手",
      "EA状态: 关闭",
      "风控状态: ✅ 正常"
   };
   int y = 18;
   for(int i = 0; i < 9; i++)
   {
      string objName = prefix + names[i];
      ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, 18);
      ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 10);
      ObjectSetString(0, objName, OBJPROP_FONT, "微软雅黑");   // 完美支持中文
      ObjectSetString(0, objName, OBJPROP_TEXT, initTexts[i]);
    //   ObjectSetInteger(0, objName, OBJPROP_COLOR, clrWhite);
      y += 33;
   }
   
   // 标题特别美化
   ObjectSetInteger(0, prefix+"Title", OBJPROP_COLOR, clrGold);
   ObjectSetInteger(0, prefix+"Title", OBJPROP_FONTSIZE, 11);
}

void UpdateDashboard(string statusMsg)
{
   int buyCnt   = GetBasketCount("BUY");
   int sellCnt  = UseOnlyBuy ? 0 : GetBasketCount("SELL");
   double buyPL = GetBasketProfit("BUY");
   double sellPL= UseOnlyBuy ? 0 : GetBasketProfit("SELL");
   double totalPL = buyPL + sellPL;
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double lots = GetTotalLots();
   string status = (statusMsg == "") ? " ✅ 正常" : statusMsg;
//    Print("lots: ", lots);
//    Print("风控状态: ", status);


   color plColor = (totalPL >= 0) ? clrLime : clrRed;
   color riskColor = (status == "") ? clrLime : clrYellow;

   // 实时中文更新
   ObjectSetString(0, prefix+"BuyLabel",  OBJPROP_TEXT, StringFormat("买入篮子: %d/%d   盈亏 %.1f USD", buyCnt, MaxBuyLevels, buyPL));
   ObjectSetString(0, prefix+"SellLabel", OBJPROP_TEXT, StringFormat("卖出篮子: %d/%d   盈亏 %.1f USD", sellCnt, MaxSellLevels, sellPL));
   ObjectSetString(0, prefix+"TotalLabel",OBJPROP_TEXT, StringFormat("总盈亏: %.1f USD", totalPL));
   ObjectSetString(0, prefix+"EquityLabel",OBJPROP_TEXT,StringFormat("账户权益: %.0f USD", equity));
   ObjectSetString(0, prefix+"TradeCountLabel",OBJPROP_TEXT,StringFormat("今日交易次数: %d 次", dailyTrades));
   ObjectSetString(0, prefix+"PositionSizeLabel",OBJPROP_TEXT,StringFormat("当前持仓手数: %.2f 手", lots));
   ObjectSetString(0, prefix+"StatusLabel",OBJPROP_TEXT,StringFormat("EA状态: %s", "正常运行"));
   ObjectSetString(0, prefix+"RiskLabel", OBJPROP_TEXT, StringFormat("风控状态: %s",  status));
   
   // 颜色动态
   ObjectSetInteger(0, prefix+"BuyLabel", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, prefix+"SellLabel", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, prefix+"TotalLabel", OBJPROP_COLOR, plColor); 
   ObjectSetInteger(0, prefix+"EquityLabel", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, prefix+"TradeCountLabel", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, prefix+"PositionSizeLabel", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, prefix+"StatusLabel", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, prefix+"RiskLabel", OBJPROP_COLOR, riskColor);
   ObjectSetInteger(0, prefix+"Title", OBJPROP_COLOR, clrGold);

   ChartRedraw(); 
}

// 在OnChartEvent中添加
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == prefix+"DebugBtn")
   {
      PrintCurrentSettings();
      CheckNewEntry("BUY");
      CheckNewEntry("SELL");
   }
}

// ==================== 【系统诊断】 ====================
void PrintCurrentSettings()
{

    UpdateDashboard("诊断中");
    Print("=== 当前参数设置 ===");
    Print("是否只允许买入: ", UseOnlyBuy);
    Print("是否使用ATR自适应: ", UseATRAdaptive);
    Print("买入网格间距: ", GridStepBuy);
    Print("卖出网格间距: ", GridStepSell);
    Print("ATR倍数: ", ATR_Multiplier);
    
    if(UseATRAdaptive)
    {
        double atr[];
        if(CopyBuffer(iATR(_Symbol, PERIOD_CURRENT, ATR_Period), 0, 0, 1, atr) > 0)
        {
            double calculatedStep = atr[0] * ATR_Multiplier;
            Print("当前ATR值: ", atr[0]);
            Print("计算出的网格间距: ", calculatedStep);
        }
    }
    
    Print("买入篮子数: ", GetBasketCount("BUY"), "/", MaxBuyLevels);
    Print("卖出篮子数: ", GetBasketCount("SELL"), "/", MaxSellLevels);
    Print("买入极端价格: ", GetBasketExtremePrice("BUY"));
    Print("卖出极端价格: ", GetBasketExtremePrice("SELL"));
    Print("当前Bid价: ", SymbolInfoDouble(_Symbol, SYMBOL_BID));
    Print("当前Ask价: ", SymbolInfoDouble(_Symbol, SYMBOL_ASK));
    Print("当前点差: ", SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID));
}
void CreateDebugButton()
{
   ObjectCreate(0, prefix+"DebugBtn", OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, prefix+"DebugBtn", OBJPROP_XDISTANCE, 280);
   ObjectSetInteger(0, prefix+"DebugBtn", OBJPROP_YDISTANCE, 280);
   ObjectSetInteger(0, prefix+"DebugBtn", OBJPROP_XSIZE, 50);
   ObjectSetInteger(0, prefix+"DebugBtn", OBJPROP_YSIZE, 20);
   ObjectSetString(0, prefix+"DebugBtn", OBJPROP_TEXT, "调试");
   ObjectSetInteger(0, prefix+"DebugBtn", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, prefix+"DebugBtn", OBJPROP_BGCOLOR, clrBlue);
}
