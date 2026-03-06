//+------------------------------------------------------------------+
//|                                          BollingerRSIPinbarEA.mq5 |
//|                                             Copyright 2026, surra |
//|                                       https://www.metatrader5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, surra"
#property link      "https://www.metatrader5.com"
#property version   "1.00"

//--- 包含文件
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Charts\Chart.mqh>
#include <Canvas\Canvas.mqh>

//--- 输入参数
input group "====== 资金管理 ======"
input double   RiskPerTrade    = 1.0;     // 单笔风险百分比（%）
input double   LotSize         = 0.01;    // 固定手数（如果为0则自动计算）
input bool     UseMoneyManagement = true; // 启用资金管理

input group "====== 布林带参数 ======"
input int      BandsPeriod     = 20;      // 布林带周期
input double   BandsDeviation  = 2.0;     // 标准差倍数
input ENUM_APPLIED_PRICE BandsPrice = PRICE_CLOSE; // 应用价格

input group "====== RSI参数 ======"
input int      RSIPeriod       = 7;       // RSI周期
input int      RSIOverbought   = 65;      // 超买水平
input int      RSIOversold     = 35;      // 超卖水平

input group "====== Pinbar参数 ======"
input double   PinbarBodyRatio  = 0.3;    // 实体与整根K线比例
input double   PinbarShadowRatio = 2.0;   // 影线与实体比例
input int      MinPinbarSize    = 30;     // 最小Pinbar点数（点）

input group "====== 入场条件 ======"
input bool     UseBollingerEntry = true;  // 使用布林带入场
input bool     UseRSIEntry      = true;   // 使用RSI入场
input bool     UsePinbarEntry   = true;   // 使用Pinbar入场
input bool     AllConditionsRequired = true; // 需要所有条件满足

input group "====== 出场策略 ======"
input int      TakeProfitPips1  = 100;     // 第一部分止盈点数
input int      StopLossPips     = 70;     // 初始止损点数
input double   PartialClosePercent = 50.0; // 部分平仓百分比
input bool     UseTrailingStop  = true;   // 使用追踪止损
input int      TrailingStopPips = 50;     // 追踪止损点数
input int      BreakEvenPips    = 35;     // 保本点数
input bool     UseMidBollingerExit = true; // 使用布林中轨出场

input group "====== 过滤条件 ======"
input bool     TradeOnlyHighVolume = true; // 仅在流动性高时段交易
input int      HighVolumeStart  = 20;      // 高流动性开始时间（小时）
input int      HighVolumeEnd    = 24;      // 高流动性结束时间（小时）
input double   MinBollingerWidth = 1.5;    // 最小布林带宽度（点）
input bool     UseATRFilter     = true;   // 使用ATR过滤
input double   ATRMultiplier    = 3;    // ATR倍数
input int      ATRPeriod       = 14;      // ATR周期

//--- 全局变量
CTrade trade;
CPositionInfo positionInfo;
CSymbolInfo symbolInfo;
CAccountInfo accountInfo;

double g_lotSize = 0.0;
datetime g_lastTradeTime = 0;
int g_bollingerHandle = INVALID_HANDLE;
int g_rsiHandle = INVALID_HANDLE;
int g_atrHandle = INVALID_HANDLE;
bool g_positionOpen = false;
double g_entryPrice = 0.0;
double g_stopLoss = 0.0;
double g_takeProfit1 = 0.0;
ENUM_POSITION_TYPE g_positionType = POSITION_TYPE_BUY;
double g_trailingStopLevel = 0.0;
bool g_partialClosed = false;
bool g_tradingEnabled = true;

//--- 面板变量
int panelWidth = 300;
int panelHeight = 400;
string panelName = "BollingerRSI_Panel";
long chartID = 0;

//--- 结构体定义
struct SSignal {
   bool buySignal;
   bool sellSignal;
   double bollingerUpper;
   double bollingerLower;
   double bollingerMiddle;
   double rsiValue;
   bool isPinbar;
   double atrValue;
   double pinbarSize;
};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {

    // 打印平台规格信息
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
    
    Print("=== XAUUSD 平台规格 ===");
    Print("1点(point)价值: ", point);
    Print("最小止损水平(Stops Level): ", stopsLevel, " 点");
    Print("最小报价单位(Tick Size): ", tickSize);
    Print("每点价值(Tick Value): ", tickValue);
    Print("当前点差(Spread): ", spread, " 点");
    Print("建议最小止损距离: ", MathMax(150, stopsLevel + 50), " 点");
    Print("=========================");
    
    // 如果stopsLevel显示为0，很可能是您需要查询不同的属性名
    if(stopsLevel == 0) {
        // 尝试其他可能的属性名
        stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
        Print("使用FREEZE_LEVEL作为最小距离: ", stopsLevel, " 点");
    }

    // 设置图表属性
    chartID = ChartID();
    ChartSetInteger(chartID, CHART_EVENT_MOUSE_MOVE, true);
    
    // 初始化指标句柄
    g_bollingerHandle = iBands(_Symbol, PERIOD_M1, BandsPeriod, 0, BandsDeviation, BandsPrice);
    g_rsiHandle = iRSI(_Symbol, PERIOD_M1, RSIPeriod, PRICE_CLOSE);
    g_atrHandle = iATR(_Symbol, PERIOD_M1, ATRPeriod);
    
    if(g_bollingerHandle == INVALID_HANDLE || g_rsiHandle == INVALID_HANDLE) {
        Print("指标初始化失败!");
        return INIT_FAILED;
    }
    
    // 设置交易参数
    trade.SetDeviationInPoints(10);
    trade.SetAsyncMode(false);
    
    // 初始化符号信息
    symbolInfo.Name(_Symbol);
    
    // 创建控制面板
    if(!CreateControlPanel()) {
        Print("控制面板创建失败!");
        return INIT_FAILED;
    }

        // 显示交易设置
    ShowTradingSettings();
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   // 删除指标句柄
   if(g_bollingerHandle != INVALID_HANDLE) IndicatorRelease(g_bollingerHandle);
   if(g_rsiHandle != INVALID_HANDLE) IndicatorRelease(g_rsiHandle);
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   
   // 删除面板对象
   DeleteControlPanel();
   
   // 删除图形对象
   ObjectsDeleteAll(chartID, panelName, 0, OBJ_RECTANGLE_LABEL);
   ObjectsDeleteAll(chartID, panelName, 0, OBJ_LABEL);
   ObjectsDeleteAll(chartID, panelName, 0, OBJ_BUTTON);
   ObjectsDeleteAll(chartID, panelName, 0, OBJ_EDIT);
}

//+------------------------------------------------------------------+
//| 创建控制面板                                                     |
//+------------------------------------------------------------------+
bool CreateControlPanel() {
   // 创建面板背景
   if(!ObjectCreate(chartID, panelName + "_Background", OBJ_RECTANGLE_LABEL, 0, 0, 0)) {
      Print("创建面板背景失败!");
      return false;
   }
   
   ObjectSetInteger(chartID, panelName + "_Background", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(chartID, panelName + "_Background", OBJPROP_YDISTANCE, 20);
   ObjectSetInteger(chartID, panelName + "_Background", OBJPROP_XSIZE, panelWidth);
   ObjectSetInteger(chartID, panelName + "_Background", OBJPROP_YSIZE, panelHeight);
   ObjectSetInteger(chartID, panelName + "_Background", OBJPROP_BGCOLOR, clrBlack);
   ObjectSetInteger(chartID, panelName + "_Background", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(chartID, panelName + "_Background", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(chartID, panelName + "_Background", OBJPROP_COLOR, clrGray);
   ObjectSetInteger(chartID, panelName + "_Background", OBJPROP_BACK, true);
   ObjectSetInteger(chartID, panelName + "_Background", OBJPROP_SELECTABLE, false);
   ObjectSetInteger(chartID, panelName + "_Background", OBJPROP_HIDDEN, true);
   ObjectSetInteger(chartID, panelName + "_Background", OBJPROP_ZORDER, 0);
   
   // 创建标题
   CreateLabel("Title", 20, 30, "=== BollingerRSI EA ===", clrGold, 10, "Arial Bold");
   
   int yPos = 60;
   
   // 创建账户信息标签
   CreateLabel("BalanceLabel", 20, yPos, "余额:", clrDodgerBlue, 8);
   CreateEdit("BalanceValue", 100, yPos-2, 120, 20, DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2), clrWhiteSmoke, true);
   yPos += 25;
   
   CreateLabel("EquityLabel", 20, yPos, "净值:", clrDodgerBlue, 8);
   CreateEdit("EquityValue", 100, yPos-2, 120, 20, DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2), clrWhiteSmoke, true);
   yPos += 25;
   
   CreateLabel("SignalLabel", 20, yPos, "信号:", clrGold, 8);
   CreateEdit("SignalValue", 100, yPos-2, 120, 20, "等待信号", clrWhiteSmoke, true);
   yPos += 25;
   
   CreateLabel("PositionLabel", 20, yPos, "持仓:", clrGold, 8);
   CreateEdit("PositionValue", 100, yPos-2, 120, 20, "无", clrWhiteSmoke, true);
   yPos += 40;
   
   // 创建交易统计
   CreateLabel("StatsLabel", 20, yPos, "交易统计:", clrLime, 8);
   yPos += 20;
   
   CreateLabel("TradesLabel", 20, yPos, "交易次数:", clrWhite, 8);
   CreateEdit("TradesValue", 100, yPos-2, 80, 20, "0", clrWhiteSmoke, true);
   yPos += 25;
   
   CreateLabel("WinRateLabel", 20, yPos, "胜率:", clrWhite, 8);
   CreateEdit("WinRateValue", 100, yPos-2, 80, 20, "0%", clrWhiteSmoke, true);
   yPos += 25;
   
   CreateLabel("ProfitLabel", 20, yPos, "总盈利:", clrWhite, 8);
   CreateEdit("ProfitValue", 100, yPos-2, 80, 20, "0.00", clrWhiteSmoke, true);
   yPos += 40;
   
   // 创建按钮
   CreateButton("TradeButton", 20, yPos, 120, 30, "启动交易", clrGreen, clrWhite);
   CreateButton("CloseAllButton", 150, yPos, 120, 30, "平所有仓", clrRed, clrWhite);
   yPos += 40;
   
   // 状态指示器
   CreateLabel("StatusLabel", 20, yPos, "状态:", clrWhite, 8);
   CreateLabel("StatusIndicator", 100, yPos, "●", clrRed, 12);
   CreateLabel("StatusText", 120, yPos, "交易暂停", clrWhite, 8);
   
   return true;
}

//+------------------------------------------------------------------+
//| 创建标签                                                         |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, color clr, int fontSize = 8, string font = "Arial") {
   string fullName = panelName + "_" + name;
   
   if(!ObjectCreate(chartID, fullName, OBJ_LABEL, 0, 0, 0)) {
      Print("创建标签失败: ", fullName);
      return;
   }
   
   ObjectSetInteger(chartID, fullName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(chartID, fullName, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(chartID, fullName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetString(chartID, fullName, OBJPROP_TEXT, text);
   ObjectSetInteger(chartID, fullName, OBJPROP_COLOR, clr);
   ObjectSetInteger(chartID, fullName, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(chartID, fullName, OBJPROP_FONT, font);
   ObjectSetInteger(chartID, fullName, OBJPROP_BACK, false);
   ObjectSetInteger(chartID, fullName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(chartID, fullName, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| 创建编辑框                                                       |
//+------------------------------------------------------------------+
void CreateEdit(string name, int x, int y, int width, int height, string text, color bgColor, bool readOnly = true) {
   string fullName = panelName + "_" + name;
   
   if(!ObjectCreate(chartID, fullName, OBJ_EDIT, 0, 0, 0)) {
      Print("创建编辑框失败: ", fullName);
      return;
   }
   
   ObjectSetInteger(chartID, fullName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(chartID, fullName, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(chartID, fullName, OBJPROP_XSIZE, width);
   ObjectSetInteger(chartID, fullName, OBJPROP_YSIZE, height);
   ObjectSetInteger(chartID, fullName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetString(chartID, fullName, OBJPROP_TEXT, text);
   ObjectSetInteger(chartID, fullName, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(chartID, fullName, OBJPROP_BORDER_COLOR, clrGray);
   ObjectSetInteger(chartID, fullName, OBJPROP_READONLY, readOnly);
   ObjectSetInteger(chartID, fullName, OBJPROP_ALIGN, ALIGN_CENTER);
   ObjectSetInteger(chartID, fullName, OBJPROP_BACK, false);
   ObjectSetInteger(chartID, fullName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(chartID, fullName, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| 创建按钮                                                         |
//+------------------------------------------------------------------+
void CreateButton(string name, int x, int y, int width, int height, string text, color bgColor, color textColor) {
   string fullName = panelName + "_" + name;
   
   if(!ObjectCreate(chartID, fullName, OBJ_BUTTON, 0, 0, 0)) {
      Print("创建按钮失败: ", fullName);
      return;
   }
   
   ObjectSetInteger(chartID, fullName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(chartID, fullName, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(chartID, fullName, OBJPROP_XSIZE, width);
   ObjectSetInteger(chartID, fullName, OBJPROP_YSIZE, height);
   ObjectSetInteger(chartID, fullName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetString(chartID, fullName, OBJPROP_TEXT, text);
   ObjectSetInteger(chartID, fullName, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(chartID, fullName, OBJPROP_COLOR, textColor);
   ObjectSetInteger(chartID, fullName, OBJPROP_BORDER_COLOR, clrGray);
   ObjectSetInteger(chartID, fullName, OBJPROP_BACK, false);
   ObjectSetInteger(chartID, fullName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(chartID, fullName, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| 删除控制面板                                                     |
//+------------------------------------------------------------------+
void DeleteControlPanel() {
   // 删除所有面板相关对象
   ObjectsDeleteAll(chartID, panelName, 0, OBJ_RECTANGLE_LABEL);
   ObjectsDeleteAll(chartID, panelName, 0, OBJ_LABEL);
   ObjectsDeleteAll(chartID, panelName, 0, OBJ_BUTTON);
   ObjectsDeleteAll(chartID, panelName, 0, OBJ_EDIT);
}

//+------------------------------------------------------------------+
//| 更新控制面板                                                     |
//+------------------------------------------------------------------+
void UpdateControlPanel() {
   // 更新账户信息
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   ObjectSetString(chartID, panelName + "_BalanceValue", OBJPROP_TEXT, DoubleToString(balance, 2));
   ObjectSetString(chartID, panelName + "_EquityValue", OBJPROP_TEXT, DoubleToString(equity, 2));
   
   // 获取当前信号
   SSignal signal = GetCurrentSignal();
   string signalText = "无信号";
   color signalColor = clrWhiteSmoke;
   
   if(signal.buySignal) {
      signalText = "买入信号";
      signalColor = clrLime;
   } else if(signal.sellSignal) {
      signalText = "卖出信号";
      signalColor = clrRed;
   }
   
   ObjectSetString(chartID, panelName + "_SignalValue", OBJPROP_TEXT, signalText);
   ObjectSetInteger(chartID, panelName + "_SignalValue", OBJPROP_BGCOLOR, signalColor);
   
   // 更新持仓信息
   if(positionInfo.Select(_Symbol)) {
      double profit = positionInfo.Profit();
      string posType = positionInfo.PositionType() == POSITION_TYPE_BUY ? "买入" : "卖出";
      ObjectSetString(chartID, panelName + "_PositionValue", OBJPROP_TEXT, 
                     posType + " | 利润: " + DoubleToString(profit, 2));
      
      if(profit >= 0) {
         ObjectSetInteger(chartID, panelName + "_PositionValue", OBJPROP_BGCOLOR, clrLime);
      } else {
         ObjectSetInteger(chartID, panelName + "_PositionValue", OBJPROP_BGCOLOR, clrRed);
      }
   } else {
      ObjectSetString(chartID, panelName + "_PositionValue", OBJPROP_TEXT, "无持仓");
      ObjectSetInteger(chartID, panelName + "_PositionValue", OBJPROP_BGCOLOR, clrWhiteSmoke);
   }
   
   // 更新状态指示器
   if(g_tradingEnabled) {
      ObjectSetInteger(chartID, panelName + "_StatusIndicator", OBJPROP_COLOR, clrLime);
      ObjectSetString(chartID, panelName + "_StatusText", OBJPROP_TEXT, "交易进行中");
   } else {
      ObjectSetInteger(chartID, panelName + "_StatusIndicator", OBJPROP_COLOR, clrRed);
      ObjectSetString(chartID, panelName + "_StatusText", OBJPROP_TEXT, "交易暂停");
   }
   
   // 更新按钮文本
   ObjectSetString(chartID, panelName + "_TradeButton", OBJPROP_TEXT, g_tradingEnabled ? "暂停交易" : "启动交易");
   ObjectSetInteger(chartID, panelName + "_TradeButton", OBJPROP_BGCOLOR, g_tradingEnabled ? clrOrange : clrGreen);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
   // 更新面板
   UpdateControlPanel();
   
   // 检查是否允许交易
   if(!g_tradingEnabled || !CheckTradingConditions()) return;
   
   // 获取当前信号
   SSignal signal = GetCurrentSignal();
   
   // 检查是否已有持仓
   if(positionInfo.Select(_Symbol)) {
      ManagePosition(signal);
   } else {
      // 检查入场信号
      CheckEntrySignal(signal);
   }
}

//+------------------------------------------------------------------+
//| 检查交易条件                                                     |
//+------------------------------------------------------------------+
bool CheckTradingConditions() {
   // 检查时间过滤
   if(TradeOnlyHighVolume) {
      MqlDateTime dt;
      TimeCurrent(dt);
      int current_hour = dt.hour;
      
      if(current_hour < HighVolumeStart || current_hour >= HighVolumeEnd) {
         return false;
      }
   }
   
   // 检查布林带宽度
   if(MinBollingerWidth > 0) {
      double bollingerUpper[], bollingerLower[];
      ArraySetAsSeries(bollingerUpper, true);
      ArraySetAsSeries(bollingerLower, true);
      
      if(CopyBuffer(g_bollingerHandle, 1, 0, 2, bollingerUpper) < 2 ||
         CopyBuffer(g_bollingerHandle, 2, 0, 2, bollingerLower) < 2) {
         return false;
      }
      
      double bollingerWidth = (bollingerUpper[0] - bollingerLower[0]) / _Point;
      if(bollingerWidth < MinBollingerWidth) {
         return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| 获取当前信号                                                     |
//+------------------------------------------------------------------+
SSignal GetCurrentSignal() {
   SSignal signal = {};
   
   // 获取布林带数据
   double bollingerUpper[], bollingerMiddle[], bollingerLower[];
   ArraySetAsSeries(bollingerUpper, true);
   ArraySetAsSeries(bollingerMiddle, true);
   ArraySetAsSeries(bollingerLower, true);
   
   if(CopyBuffer(g_bollingerHandle, 1, 0, 3, bollingerUpper) < 3 ||
      CopyBuffer(g_bollingerHandle, 0, 0, 3, bollingerMiddle) < 3 ||
      CopyBuffer(g_bollingerHandle, 2, 0, 3, bollingerLower) < 3) {
      return signal;
   }
   
   signal.bollingerUpper = bollingerUpper[0];
   signal.bollingerMiddle = bollingerMiddle[0];
   signal.bollingerLower = bollingerLower[0];
   
   // 获取RSI数据
   double rsi[];
   ArraySetAsSeries(rsi, true);
   if(CopyBuffer(g_rsiHandle, 0, 0, 3, rsi) < 3) {
      return signal;
   }
   signal.rsiValue = rsi[0];
   
   // 获取ATR数据
   if(UseATRFilter) {
      double atr[];
      ArraySetAsSeries(atr, true);
      if(CopyBuffer(g_atrHandle, 0, 0, 3, atr) >= 3) {
         signal.atrValue = atr[0];
      }
   }
   
   // 获取价格数据
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   if(CopyRates(_Symbol, PERIOD_M1, 0, 3, rates) < 3) {
      return signal;
   }
   
   // 检查Pinbar
   signal.isPinbar = CheckPinbar(rates[1]);
   signal.pinbarSize = (rates[1].high - rates[1].low) / _Point;
   
   // 计算入场信号
   bool bollingerBuySignal = false;
   bool bollingerSellSignal = false;
   bool rsiBuySignal = false;
   bool rsiSellSignal = false;
   bool pinbarBuySignal = false;
   bool pinbarSellSignal = false;
   
   // 布林带信号
   if(UseBollingerEntry) {
      // 价格接近下轨（考虑一定容差）
      if(rates[1].low <= bollingerLower[1] + 5 * _Point) {
         bollingerBuySignal = true;
      }
      // 价格接近上轨
      if(rates[1].high >= bollingerUpper[1] - 5 * _Point) {
         bollingerSellSignal = true;
      }
   }
   
   // RSI信号
   if(UseRSIEntry) {
      if(rsi[1] <= RSIOversold) {
         rsiBuySignal = true;
      }
      if(rsi[1] >= RSIOverbought) {
         rsiSellSignal = true;
      }
   }
   
   // Pinbar信号
   if(UsePinbarEntry && signal.isPinbar && signal.pinbarSize >= MinPinbarSize) {
      pinbarBuySignal = IsBullishPinbar(rates[1]);
      pinbarSellSignal = IsBearishPinbar(rates[1]);
   }
   
   // 综合信号
   if(AllConditionsRequired) {
      // 需要所有条件满足
      signal.buySignal = bollingerBuySignal && rsiBuySignal && pinbarBuySignal;
      signal.sellSignal = bollingerSellSignal && rsiSellSignal && pinbarSellSignal;
   } else {
      // 至少一个条件满足
      signal.buySignal = (bollingerBuySignal || rsiBuySignal || pinbarBuySignal);
      signal.sellSignal = (bollingerSellSignal || rsiSellSignal || pinbarSellSignal);
   }
   
   return signal;
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

//+------------------------------------------------------------------+
//| 检查入场信号                                                     |
//+------------------------------------------------------------------+
void CheckEntrySignal(SSignal &signal) {
    // 防止频繁交易
    if(TimeCurrent() - g_lastTradeTime < 60) return; // 至少间隔1分钟
    
    // 计算手数
    double lot = CalculateLotSize();
    if(lot <= 0) return;
    
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
    
    if(signal.buySignal) {
        // 计算止损止盈
        double sl = bid - StopLossPips * point;
        double tp1 = bid + TakeProfitPips1 * point;
        
        // 使用ATR调整止损
        if(UseATRFilter && signal.atrValue > 0) {
            sl = bid - signal.atrValue * ATRMultiplier;
            tp1 = bid + signal.atrValue * ATRMultiplier;
        }

        // 验证止损止盈有效性
        if(!ValidateStopLossTakeProfit(bid, sl, tp1, ORDER_TYPE_BUY)) {
            Print("止损止盈验证失败，放弃交易");
            return;
        }
        
        // 避免止损设置过近
        double minStopDistance = spread * 2 * point;
        if(bid - sl < minStopDistance) {
            sl = bid - minStopDistance;
        }

        // 确保止损有最小距离
        double minDistance = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
        if(minDistance == 0) minDistance = 50 * point; // 黄金最小50点
        
        if(bid - sl < minDistance) {
            sl = bid - minDistance;
            Print("止损距离调整为最小要求: ", DoubleToString(minDistance/point, 0), "点");
        }
        Print("计算的止损价格: ", sl, "，止盈价格: ", tp1, "，买入入场价格: ", bid);
        
        // 执行买入
        if(trade.Buy(lot, _Symbol, bid, sl - 50 * point, tp1, "Bollinger+RSI+Pinbar买入")) {
            g_positionOpen = true;
            g_entryPrice = bid;
            g_stopLoss = sl;
            g_takeProfit1 = tp1;
            g_positionType = POSITION_TYPE_BUY;
            g_lastTradeTime = TimeCurrent();
            g_partialClosed = false;
            Print("买入订单已执行，价格: ", bid, " 手数: ", lot, " 止损: ", sl, " 止盈: ", tp1);
        } else {
            Print("买入订单失败，错误码: ", trade.ResultRetcode(), " 描述: ", trade.ResultRetcodeDescription());
        }
        
    } else if(signal.sellSignal) {
        // 计算止损止盈
        double sl = ask + StopLossPips * point;
        double tp1 = ask - TakeProfitPips1 * point;
        
        // 使用ATR调整止损
        if(UseATRFilter && signal.atrValue > 0) {
            sl = ask + signal.atrValue * ATRMultiplier;
            tp1 = ask - signal.atrValue * ATRMultiplier;
        }

        // 验证止损止盈有效性
        if(!ValidateStopLossTakeProfit(ask, sl, tp1, ORDER_TYPE_SELL)) {
            Print("止损止盈验证失败，放弃交易");
            return;
        }
        
        // 避免止损设置过近
        double minStopDistance = spread * 2 * point;
        if(sl - ask < minStopDistance) {
            sl = ask + minStopDistance;
        }

        // 确保止损有最小距离
        double minDistance = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
        if(minDistance == 0) minDistance = 50 * point; // 黄金最小50点
        
        if(sl - bid < minDistance) {
            sl = bid + minDistance;
            Print("止损距离调整为最小要求: ", DoubleToString(minDistance/point, 0), "点");
        }

        Print("计算的止损价格: ", sl, "，止盈价格: ", tp1, "，卖出入场价格: ", ask);
        
        // 执行卖出
        if(trade.Sell(lot, _Symbol, ask, sl + 50 * point, tp1, "Bollinger+RSI+Pinbar卖出")) {
            g_positionOpen = true;
            g_entryPrice = ask;
            g_stopLoss = sl;
            g_takeProfit1 = tp1;
            g_positionType = POSITION_TYPE_SELL;
            g_lastTradeTime = TimeCurrent();
            g_partialClosed = false;
            Print("卖出订单已执行，价格: ", ask, " 手数: ", lot, " 止损: ", sl, " 止盈: ", tp1);
        } else {
            Print("卖出订单失败，错误码: ", trade.ResultRetcode(), " 描述: ", trade.ResultRetcodeDescription());
        }
    }
}

//+------------------------------------------------------------------+
//| 验证止损止盈价格的有效性                                         |
//+------------------------------------------------------------------+
bool ValidateStopLossTakeProfit(double entryPrice, double &sl, double &tp, 
                                ENUM_ORDER_TYPE orderType) {
   // 获取符号信息
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * point;
   
   // 获取经纪商的最小止损距离
   double minStopDistance = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
   if(minStopDistance == 0) {
      minStopDistance = 20 * point; // 默认20点
   }
   
   // 增加安全距离，考虑滑点和点差
   double safetyDistance = minStopDistance + spread + (10 * point);
   
   // 验证止损
   if(orderType == ORDER_TYPE_BUY) {
      // 买入订单：止损必须在入场价下方
      if(sl >= bid) {
         Print("错误：买入止损必须低于入场价");
         return false;
      }
      
      // 检查最小距离
      double distanceToSL = bid - sl;
      if(distanceToSL < safetyDistance) {
         Print("警告：止损距离太近(", DoubleToString(distanceToSL/_Point, 0), 
               "点)，调整到最小距离(", DoubleToString(safetyDistance/_Point, 0), "点)");
         sl = bid - safetyDistance;
      }
      
      // 验证止盈（如果设置了）
      if(tp > 0 && tp <= bid) {
         Print("错误：买入止盈必须高于入场价");
         tp = 0; // 移除无效止盈
      }
      
   } else if(orderType == ORDER_TYPE_SELL) {
      // 卖出订单：止损必须在入场价上方
      if(sl <= ask) {
         Print("错误：卖出止损必须高于入场价");
         return false;
      }
      
      // 检查最小距离
      double distanceToSL = sl - ask;
      if(distanceToSL < safetyDistance) {
         Print("警告：止损距离太近(", DoubleToString(distanceToSL/_Point, 0), 
               "点)，调整到最小距离(", DoubleToString(safetyDistance/_Point, 0), "点)");
         sl = ask + safetyDistance;
      }
      
      // 验证止盈（如果设置了）
      if(tp > 0 && tp >= ask) {
         Print("错误：卖出止盈必须低于入场价");
         tp = 0; // 移除无效止盈
      }
   }
   
   // 确保价格规范化
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   sl = NormalizeDouble(MathFloor(sl/tickSize)*tickSize, _Digits);
   if(tp > 0) {
      tp = NormalizeDouble(MathFloor(tp/tickSize)*tickSize, _Digits);
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| 管理持仓                                                         |
//+------------------------------------------------------------------+
void ManagePosition(SSignal &signal) {
   if(!positionInfo.Select(_Symbol)) return;
   
   ulong ticket = positionInfo.Ticket();
   if(ticket <= 0) return;
   
   double currentPrice = positionInfo.PriceCurrent();
   double openPrice = positionInfo.PriceOpen();
   double profit = positionInfo.Profit();
   double volume = positionInfo.Volume();
   ENUM_POSITION_TYPE posType = positionInfo.PositionType();
   double currentSL = positionInfo.StopLoss();
   double currentTP = positionInfo.TakeProfit();
   
   // 检查是否达到部分平仓条件
   if(!g_partialClosed && PartialClosePercent > 0) {
      if(ShouldPartialClose(posType, currentPrice, openPrice)) {
         PartialClosePosition(ticket, volume);
         g_partialClosed = true;
         return;
      }
   }
   
   // 追踪止损
   if(UseTrailingStop && g_partialClosed) {
       ApplyTrailingStop(ticket, posType, currentPrice, openPrice, currentSL);
   }
   
   // 检查保本
   if(BreakEvenPips > 0 && !g_partialClosed) {
       ApplyBreakEven(ticket, posType, currentPrice, openPrice, currentSL);
   }
   
   // 检查布林中轨出场
   if(UseMidBollingerExit) {
       CheckMidBollingerExit(ticket, posType, signal.bollingerMiddle, currentPrice);
   }
}

//+------------------------------------------------------------------+
//| 检查是否应该部分平仓                                             |
//+------------------------------------------------------------------+
bool ShouldPartialClose(ENUM_POSITION_TYPE posType, double currentPrice, double openPrice) {
   double profitInPips = 0;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(posType == POSITION_TYPE_BUY) {
      profitInPips = (currentPrice - openPrice) / point;
   } else if(posType == POSITION_TYPE_SELL) {
      profitInPips = (openPrice - currentPrice) / point;
   }
   
   // 如果达到第一目标
   if(profitInPips >= TakeProfitPips1) {
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| 部分平仓                                                         |
//+------------------------------------------------------------------+
void PartialClosePosition(ulong ticket, double totalVolume) {
   double closeVolume = NormalizeDouble(totalVolume * (PartialClosePercent / 100.0), 2);
   
   if(trade.PositionClosePartial(ticket, closeVolume)) {
      Print("部分平仓成功，平仓手数: ", closeVolume);
      
      // 移动剩余仓位的止损到入场价（保本）
      if(BreakEvenPips > 0) {
         if(trade.PositionModify(ticket, g_entryPrice, 0)) {
            Print("移动止损到入场价: ", g_entryPrice);
         }
      }
   } else {
      Print("部分平仓失败，错误码: ", trade.ResultRetcode(), " 描述: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| 应用追踪止损                                                     |
//+------------------------------------------------------------------+
void ApplyTrailingStop(ulong ticket, ENUM_POSITION_TYPE posType, double currentPrice, double openPrice, double currentSL) {
   double newStopLoss = 0;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(posType == POSITION_TYPE_BUY) {
      double potentialStop = currentPrice - TrailingStopPips * point;
      
      if(potentialStop > currentSL && potentialStop > openPrice) {
         newStopLoss = potentialStop;
      }
   } else if(posType == POSITION_TYPE_SELL) {
      double potentialStop = currentPrice + TrailingStopPips * point;
      
      if(potentialStop < currentSL && potentialStop < openPrice) {
         newStopLoss = potentialStop;
      }
   }
   
   if(newStopLoss > 0) {
      double takeProfit = 0; // 保持原止盈
      if(trade.PositionModify(ticket, newStopLoss, takeProfit)) {
         Print("更新追踪止损: ", newStopLoss);
      }
   }
}

//+------------------------------------------------------------------+
//| 应用保本                                                         |
//+------------------------------------------------------------------+
void ApplyBreakEven(ulong ticket, ENUM_POSITION_TYPE posType, double currentPrice, double openPrice, double currentSL) {
   double profitInPips = 0;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(posType == POSITION_TYPE_BUY) {
      profitInPips = (currentPrice - openPrice) / point;
      if(profitInPips >= BreakEvenPips && currentSL < openPrice) {
         if(trade.PositionModify(ticket, openPrice, 0)) {
            Print("移动止损到保本价: ", openPrice);
         }
      }
   } else if(posType == POSITION_TYPE_SELL) {
      profitInPips = (openPrice - currentPrice) / point;
      if(profitInPips >= BreakEvenPips && currentSL > openPrice) {
         if(trade.PositionModify(ticket, openPrice, 0)) {
            Print("移动止损到保本价: ", openPrice);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 检查布林中轨出场                                                 |
//+------------------------------------------------------------------+
void CheckMidBollingerExit(ulong ticket, ENUM_POSITION_TYPE posType, double bollingerMiddle, double currentPrice) {
   if(bollingerMiddle <= 0) return;
   
   bool shouldClose = false;
   
   if(posType == POSITION_TYPE_BUY) {
      // 多头在价格跌破中轨时出场
      if(currentPrice < bollingerMiddle) {
         shouldClose = true;
      }
   } else if(posType == POSITION_TYPE_SELL) {
      // 空头在价格涨破中轨时出场
      if(currentPrice > bollingerMiddle) {
         shouldClose = true;
      }
   }
   
   if(shouldClose) {
      if(trade.PositionClose(ticket)) {
         Print("布林中轨出场触发，平仓");
         g_positionOpen = false;
      }
   }
}

//+------------------------------------------------------------------+
//| 计算手数                                                         |
//+------------------------------------------------------------------+
double CalculateLotSize() {
   if(LotSize > 0) return NormalizeDouble(LotSize, 2);
   
   if(!UseMoneyManagement) return 0.01;
   
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * (RiskPerTrade / 100.0);
   
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(tickSize == 0 || point == 0 || tickValue == 0) return 0.01;
   
   double stopLossPoints = StopLossPips;
   if(stopLossPoints <= 0) stopLossPoints = 30;
   
   // 计算手数
   double moneyPerLot = (stopLossPoints * point * tickValue) / tickSize;
   if(moneyPerLot == 0) return 0.01;
   
   double lots = riskAmount / moneyPerLot;
   
   // 规范化手数
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lots = MathMax(lots, minLot);
   lots = MathMin(lots, maxLot);
   lots = NormalizeDouble(lots, 2);
   lots = MathRound(lots / lotStep) * lotStep;
   
   return lots;
}

//+------------------------------------------------------------------+
//| 显示交易设置信息                                                 |
//+------------------------------------------------------------------+
void ShowTradingSettings() {
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   
   Print("=== 交易符号信息 ===");
   Print("符号: ", _Symbol);
   Print("点值: ", point);
   Print("最小报价单位: ", tickSize);
   Print("小数位数: ", _Digits);
   Print("最小止损水平: ", stopsLevel, " 点");
   Print("当前点差: ", spread, " 点");
   Print("建议最小止损距离: ", MathMax(15, stopsLevel + 5), " 点");
   Print("=== EA设置 ===");
   Print("设置止损点数: ", StopLossPips, " 点");
   Print("设置止盈点数: ", TakeProfitPips1, " 点");
   Print("=== 计算示例 ===");
   Print("买入价: 1800.00");
   Print("设置止损: ", 1800.00 - StopLossPips * point);
   Print("设置止盈: ", 1800.00 + TakeProfitPips1 * point);
}

//+------------------------------------------------------------------+
//| 图表事件处理                                                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   // 处理按钮点击事件
   if(id == CHARTEVENT_OBJECT_CLICK) {
      if(sparam == panelName + "_TradeButton") {
         g_tradingEnabled = !g_tradingEnabled;
         Print("交易状态切换: ", g_tradingEnabled ? "启动" : "暂停");
         UpdateControlPanel();
      } else if(sparam == panelName + "_CloseAllButton") {
         CloseAllPositions();
      }
   }
}

//+------------------------------------------------------------------+
//| 关闭所有持仓                                                     |
//+------------------------------------------------------------------+
void CloseAllPositions() {
   int total = PositionsTotal();
   for(int i = total-1; i >= 0; i--) {
      if(positionInfo.SelectByIndex(i)) {
         if(positionInfo.Symbol() == _Symbol) {
            ulong ticket = positionInfo.Ticket();
            if(trade.PositionClose(ticket)) {
               Print("平仓成功，订单号: ", ticket);
            } else {
               Print("平仓失败，订单号: ", ticket, " 错误码: ", trade.ResultRetcode());
            }
         }
      }
   }
   g_positionOpen = false;
   Print("所有持仓关闭完成");
}

//+------------------------------------------------------------------+
//| 交易事件处理                                                     |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result) {
   // 处理交易事件
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD) {
      ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE);
      
      if(dealType == DEAL_TYPE_BUY || dealType == DEAL_TYPE_SELL) {
         double price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
         double volume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
         Print("交易执行: ", EnumToString(dealType), 
               " 价格: ", price, 
               " 量: ", volume);
      }
   }
}