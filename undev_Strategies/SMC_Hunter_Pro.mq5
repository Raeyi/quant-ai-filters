//+------------------------------------------------------------------+
//|                                              SMC_Hunter_Pro.mq5  |
//|                                  Copyright 2026, AI Collaborator |
//+------------------------------------------------------------------+
#property copyright "AI Collaborator"
#property link      "https://www.mql5.com"
#property version   "2.00"

//--- 输入参数
input group "=== 时间框架设置 ==="
input ENUM_TIMEFRAMES HTF = PERIOD_H1;       // 高周期 (找OB/FVG/流动性)
input ENUM_TIMEFRAMES LTF = PERIOD_M15;      // 低周期 (找入场Pinbar)

input group "=== SMC 核心参数 ==="
input int Swing_Period = 5;                  // 流动性波段周期 (左右N根K线)
input double FVG_Min_Points = 50.0;          // FVG 最小点数阈值 (Points, 黄金建议50-100)

input group "=== 信号与风控参数 ==="
input double Pinbar_Wick_Ratio = 0.65;       // Pinbar 引线最小占比 (65%)
input double SL_Buffer_Points = 20.0;        // 止损缓冲 (Points, 黄金建议20-30)
input double RR_Ratio = 2.0;                 // 目标盈亏比 (默认 1:2)

//--- 箭头代码常量
#define ARROW_CODE_BULL 233  // 向上箭头
#define ARROW_CODE_BEAR 234  // 向下箭头

//--- 全局变量
double g_point;
double g_pips;
datetime g_lastLTF_Time = 0;

// HTF 关键区域记录
double g_htf_Bull_OB_Top = 0, g_htf_Bull_OB_Bot = 0;
double g_htf_Bear_OB_Top = 0, g_htf_Bear_OB_Bot = 0;

//+------------------------------------------------------------------+
//| 初始化函数
//+------------------------------------------------------------------+
int OnInit()
  {
   g_point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_pips = (SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 5 || SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 3) ? g_point * 10 : g_point;
   
   ObjectsDeleteAll(0, "SMC_"); // 启动时清理图表
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| 卸载函数
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, "SMC_"); // 退出时清理图表
  }

//+------------------------------------------------------------------+
//| 核心 Tick 循环
//+------------------------------------------------------------------+
void OnTick()
  {
   // 1. 仅在 LTF 新K线开盘时执行 (防止重绘和重复报警)
   datetime currentLTF_Time = iTime(_Symbol, LTF, 0);
   if(currentLTF_Time == g_lastLTF_Time) return; 

   // 获取数据 (多拿一些历史数据用于计算波段)
   MqlRates htf[], ltf[];
   ArraySetAsSeries(htf, true);
   ArraySetAsSeries(ltf, true);
   
   if(CopyRates(_Symbol, HTF, 0, 50, htf) < 50 || CopyRates(_Symbol, LTF, 0, 5, ltf) < 5) return;

   // 2. 扫描 HTF 流动性与结构 (简化的波段高低点 BSL/SSL)
   IdentifyLiquidity(htf);

   // 3. 扫描 HTF 订单区块 (OB) 与 FVG
   IdentifyOB_and_FVG(htf);

   // 4. 在 LTF 寻找 Pinbar 确认与报警
   CheckForEntry(ltf, currentLTF_Time);
   
   g_lastLTF_Time = currentLTF_Time; // 更新时间戳
  }

//+------------------------------------------------------------------+
//| 识别流动性池 (Swing Highs / Swing Lows)
//+------------------------------------------------------------------+
void IdentifyLiquidity(MqlRates &htf[])
  {
   // 寻找最近的波段高点 (BSL - 买方流动性) 和波段低点 (SSL - 卖方流动性)
   int p = Swing_Period;
   for(int i = 1; i < 30; i++) // 扫描最近30根K线
     {
      bool isSwingHigh = true;
      bool isSwingLow = true;
      
      for(int j = 1; j <= p; j++)
        {
         if(i-j >= 0 && htf[i].high <= htf[i-j].high) isSwingHigh = false;
         if(i+j < 50 && htf[i].high <= htf[i+j].high) isSwingHigh = false;
         
         if(i-j >= 0 && htf[i].low >= htf[i-j].low) isSwingLow = false;
         if(i+j < 50 && htf[i].low >= htf[i+j].low) isSwingLow = false;
        }
        
      if(isSwingHigh) DrawLine("SMC_BSL", htf[i].time, htf[i].high, clrRed, "BSL (Liquidity)");
      if(isSwingLow)  DrawLine("SMC_SSL", htf[i].time, htf[i].low, clrBlue, "SSL (Liquidity)");
     }
  }

//+------------------------------------------------------------------+
//| 识别伴随 FVG 的有效订单区块 (Order Block)
//+------------------------------------------------------------------+
void IdentifyOB_and_FVG(MqlRates &htf[])
  {
   // 我们从近向远扫描，找到最近的一个有效OB
   for(int i = 2; i < 20; i++)
     {
      // --- 看涨 FVG 判断 (第 i 根的高点 < 第 i-2 根的低点)
      double fvgSizeBull = htf[i-2].low - htf[i].high;
      if(fvgSizeBull > FVG_Min_Points * g_point)
        {
         // 往前回溯寻找产生动能前的最后一根阴线 (看涨OB)
         for(int j = i+1; j < i+5; j++)
           {
            if(htf[j].close < htf[j].open) // 是一根阴线
              {
               g_htf_Bull_OB_Top = htf[j].high;
               g_htf_Bull_OB_Bot = htf[j].low;
               DrawZone("SMC_Bull_OB", htf[j].time, g_htf_Bull_OB_Top, htf[0].time, g_htf_Bull_OB_Bot, clrDarkSeaGreen);
               break; // 找到就退出内循环
              }
           }
        }
        
      // --- 看跌 FVG 判断 (第 i 根的低点 > 第 i-2 根的高点)
      double fvgSizeBear = htf[i].low - htf[i-2].high;
      if(fvgSizeBear > FVG_Min_Points * g_point)
        {
         // 往前回溯寻找产生动能前的最后一根阳线 (看跌OB)
         for(int j = i+1; j < i+5; j++)
           {
            if(htf[j].close > htf[j].open) // 是一根阳线
              {
               g_htf_Bear_OB_Top = htf[j].high;
               g_htf_Bear_OB_Bot = htf[j].low;
               DrawZone("SMC_Bear_OB", htf[j].time, g_htf_Bear_OB_Top, htf[0].time, g_htf_Bear_OB_Bot, clrIndianRed);
               break; // 找到就退出内循环
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| 检查低周期入场信号 (Pinbar) 并计算止损止盈
//+------------------------------------------------------------------+
void CheckForEntry(MqlRates &ltf[], datetime alertTime)
  {
   double open = ltf[1].open;   // 取刚收盘的K线 (Index 1)
   double close = ltf[1].close;
   double high = ltf[1].high;
   double low = ltf[1].low;
   datetime signalTime = ltf[1].time;
   
   double range = high - low;
   if(range == 0) return;
   
   double bodyTop = MathMax(open, close);
   double bodyBot = MathMin(open, close);
   
   // 判断是否为 Pinbar
   bool isBullPinbar = ((bodyBot - low) / range) >= Pinbar_Wick_Ratio;
   bool isBearPinbar = ((high - bodyTop) / range) >= Pinbar_Wick_Ratio;

   // 检查看涨机会：看涨Pinbar的低点刺入或处于看涨OB区域内
   if(isBullPinbar && low <= g_htf_Bull_OB_Top && low >= g_htf_Bull_OB_Bot)
     {
      double entryPrice = close; // 市价入场参考价
      double stopLoss = low - (SL_Buffer_Points * g_point);
      double risk = entryPrice - stopLoss;
      double takeProfit = entryPrice + (risk * RR_Ratio);
      
      // 在图表上标记入场信号
      DrawEntrySignal(signalTime, low, true, entryPrice, stopLoss, takeProfit);
      
      string msg = StringFormat("SMC 猎手: 多头机会 [%s]\nLTF 出现看涨 Pinbar 踩中 HTF 订单区块!\n入场参考: %.5f\n建议止损: %.5f\n参考止盈(1:%.1f): %.5f", 
                                _Symbol, entryPrice, stopLoss, RR_Ratio, takeProfit);
      Alert(msg);
      Print(msg);
     }
     
   // 检查看跌机会：看跌Pinbar的高点刺入或处于看跌OB区域内
   if(isBearPinbar && high >= g_htf_Bear_OB_Bot && high <= g_htf_Bear_OB_Top)
     {
      double entryPrice = close;
      double stopLoss = high + (SL_Buffer_Points * g_point);
      double risk = stopLoss - entryPrice;
      double takeProfit = entryPrice - (risk * RR_Ratio);
      
      // 在图表上标记入场信号
      DrawEntrySignal(signalTime, high, false, entryPrice, stopLoss, takeProfit);
      
      string msg = StringFormat("SMC 猎手: 空头机会 [%s]\nLTF 出现看跌 Pinbar 踩中 HTF 订单区块!\n入场参考: %.5f\n建议止损: %.5f\n参考止盈(1:%.1f): %.5f", 
                                _Symbol, entryPrice, stopLoss, RR_Ratio, takeProfit);
      Alert(msg);
      Print(msg);
     }
  }

//+------------------------------------------------------------------+
//| 在图表上绘制入场信号标记
//+------------------------------------------------------------------+
void DrawEntrySignal(datetime time, double price, bool isBullish, double entry, double sl, double tp)
  {
   string signalType = isBullish ? "BULL" : "BEAR";
   string baseName = "SMC_Signal_" + signalType + "_" + TimeToString(time);
   
   // 清除旧的信号标记（保留最近10个）
   CleanOldSignals(signalType);
   
   // 1. 绘制箭头标记
   string arrowName = baseName + "_Arrow";
   ObjectCreate(0, arrowName, OBJ_ARROW, 0, time, price);
   ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, isBullish ? ARROW_CODE_BULL : ARROW_CODE_BEAR);
   ObjectSetInteger(0, arrowName, OBJPROP_COLOR, isBullish ? clrLime : clrRed);
   ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 3);
   ObjectSetInteger(0, arrowName, OBJPROP_ANCHOR, isBullish ? ANCHOR_TOP : ANCHOR_BOTTOM);
   
   // 2. 绘制标签文字
   string labelName = baseName + "_Label";
   double labelPrice = isBullish ? price - (50 * g_point) : price + (50 * g_point);
   ObjectCreate(0, labelName, OBJ_TEXT, 0, time, labelPrice);
   ObjectSetString(0, labelName, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, labelName, OBJPROP_COLOR, isBullish ? clrLime : clrRed);
   ObjectSetString(0, labelName, OBJPROP_TEXT, isBullish ? "Bullish PinBar" : "Bearish PinBar");
   
   // 3. 绘制止损线 (虚线)
   string slName = baseName + "_SL";
   ObjectCreate(0, slName, OBJ_HLINE, 0, 0, sl);
   ObjectSetInteger(0, slName, OBJPROP_COLOR, clrOrange);
   ObjectSetInteger(0, slName, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, slName, OBJPROP_WIDTH, 1);
   ObjectSetString(0, slName, OBJPROP_TEXT, "SL: " + DoubleToString(sl, _Digits));
   
   // 4. 绘制止盈线 (虚线)
   string tpName = baseName + "_TP";
   ObjectCreate(0, tpName, OBJ_HLINE, 0, 0, tp);
   ObjectSetInteger(0, tpName, OBJPROP_COLOR, clrAqua);
   ObjectSetInteger(0, tpName, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, tpName, OBJPROP_WIDTH, 1);
   ObjectSetString(0, tpName, OBJPROP_TEXT, "TP: " + DoubleToString(tp, _Digits));
   
   // 5. 绘制入场参考线
   string entryName = baseName + "_Entry";
   ObjectCreate(0, entryName, OBJ_HLINE, 0, 0, entry);
   ObjectSetInteger(0, entryName, OBJPROP_COLOR, isBullish ? clrLime : clrRed);
   ObjectSetInteger(0, entryName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, entryName, OBJPROP_WIDTH, 2);
   ObjectSetString(0, entryName, OBJPROP_TEXT, "Entry: " + DoubleToString(entry, _Digits));
  }

//+------------------------------------------------------------------+
//| 清理旧的信号标记（保留最近10个）
//+------------------------------------------------------------------+
void CleanOldSignals(string signalType)
  {
   string prefix = "SMC_Signal_" + signalType + "_";
   int total = ObjectsTotal(0, 0, OBJ_ARROW);
   int count = 0;
   
   // 从后往前遍历，删除旧的信号
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, 0, OBJ_ARROW);
      if(StringFind(name, prefix) == 0)
        {
         count++;
         if(count > 10) // 超过10个就删除
           {
            // 删除相关的所有对象（箭头、标签、线）
            string baseName = StringSubstr(name, 0, StringFind(name, "_Arrow"));
            ObjectDelete(0, baseName + "_Arrow");
            ObjectDelete(0, baseName + "_Label");
            ObjectDelete(0, baseName + "_SL");
            ObjectDelete(0, baseName + "_TP");
            ObjectDelete(0, baseName + "_Entry");
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| 辅助绘图：绘制矩形区域 (自动管理对象)
//+------------------------------------------------------------------+
void DrawZone(string name, datetime t1, double p1, datetime t2, double p2, color clr)
  {
   // 仅保留最近的一个区域，删除旧的同名对象
   ObjectDelete(0, name); 
   ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
  }

//+------------------------------------------------------------------+
//| 辅助绘图：绘制水平线 (标记流动性)
//+------------------------------------------------------------------+
void DrawLine(string prefix, datetime t, double price, color clr, string text)
  {
   string name = prefix + "_" + TimeToString(t);
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
     }
  }
//+------------------------------------------------------------------+