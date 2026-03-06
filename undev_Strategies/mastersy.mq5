//+------------------------------------------------------------------+
//|                             XAU_MA_EA.mq5                        |
//|                        Copyright 2026,  EA Mastersy              |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "EA Mastersy for wenrui"
#property version   "1.00"
#property description "XAUUSD MA策略EA"

#include <Trade\Trade.mqh>
#include <Charts\Chart.mqh>

CTrade trade;
int    ma_handle = INVALID_HANDLE;
int    macd_handle = INVALID_HANDLE;
datetime last_bar_time = 0;
bool   EA_Enabled = true;

int    consecutive_losses = 0;
datetime last_reset_time = 0;
double  initial_balance = 0.0;
double  min_equity_protection = 0.0;
bool   daily_reset_done = false; 

string PanelPrefix = "XAU_MA_";

input group "=== 美分账户适配 ==="
input bool     InpForceCent    = false;            // 是否强制美分账户

//--- 输入参数
input group "=== 策略参数 ==="
input double   InpBaseLot      = 0.01;                // 基础手数（启动lotsize）
input int      InpMAPeriod     = 144;                  // MA周期
input ENUM_MA_METHOD InpMAMethod = MODE_EMA;          // MA类型（SMA/EMA等）
input int      InpSLPoints     = 300;                 // 止损点数
input int      InpTPPoints     = 300;                 // 止盈点数
input ulong    InpMagicNumber  = 20260227;            // 魔术号

input group "=== 风控参数 ==="
input int      InpMaxConsecutiveLoss = 10;            // 最大允许连续亏损次数(0=不限制)
input bool     InpEnableMinEquityProtection = true;     // 启用最小权益保护
input int      InpDailyResetHour = 0;                     // 每日重置时间


input group "=== 面板设置 ==="
input int      InpPanelX       = 20;                  // 面板X坐标
input int      InpPanelY       = 20;                  // 面板Y坐标

//+------------------------------------------------------------------+
//| 初始化                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(10);
   
   ma_handle = iMA(_Symbol, PERIOD_CURRENT, InpMAPeriod, 0, InpMAMethod, PRICE_CLOSE);
   if(ma_handle == INVALID_HANDLE)
   {
      Print("错误: MA指标句柄创建失败");
      return INIT_FAILED;
   }

   macd_handle = iMACD(_Symbol, _Period, 12, 26, 9, PRICE_CLOSE);
   if(macd_handle == INVALID_HANDLE)
   {
      Print("错误: MACD指标句柄创建失败");
      return INIT_FAILED;
   }

   initial_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   min_equity_protection = 0.0;
   consecutive_losses = 0;
   
   CheckAndResetDaily();
   
   CreatePanel();
   PrintFormat("EA v1.20 启动成功 | 初始余额: %.2f | 基础手数: %.2f | 最大连亏: %d", 
               GetDisplayMoney(initial_balance), InpBaseLot, InpMaxConsecutiveLoss);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| 检查并执行每日重置                                                 |
//+------------------------------------------------------------------+
void CheckAndResetDaily()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   // 检查是否需要重置（每天在指定时间重置）
   if(dt.hour == InpDailyResetHour && !daily_reset_done)
   {
      double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double profit = current_balance - initial_balance;
      
      if(profit > 0)
      {
         min_equity_protection = profit;
         PrintFormat("每日重置: 记录最小权益保护值: %.2f", GetDisplayMoney(min_equity_protection));
      }
      else
      {
         min_equity_protection = 0.0;
         PrintFormat("每日重置: 账户亏损，重置最小权益保护值为0");
      }
      
      consecutive_losses = 0;
      
      last_reset_time = TimeCurrent();
      daily_reset_done = true;
   }
   else if(dt.hour != InpDailyResetHour)
   {
      daily_reset_done = false;
   }
}

//+------------------------------------------------------------------+
//| 是否为美分账户                                                    |
//+------------------------------------------------------------------+
bool IsCentAccount()
{
   if(InpForceCent) return true;
   
   string curr = AccountInfoString(ACCOUNT_CURRENCY);
   string upper = curr;
   StringToUpper(upper);
   if(StringFind(upper,"CENT") != -1 || StringFind(upper,"USC") != -1 || 
      StringFind(upper,"CENTS") != -1 || StringFind(upper,"USDC") != -1)
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| 显示金额                                                          |
//+------------------------------------------------------------------+
double GetDisplayMoney(double money)
{
   return IsCentAccount() ? money / 100.0 : money;
}

//+------------------------------------------------------------------+
//| 反初始化                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   DeletePanel();
   if(ma_handle != INVALID_HANDLE) IndicatorRelease(ma_handle);
   if(macd_handle != INVALID_HANDLE) IndicatorRelease(macd_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 检查并执行每日重置
   CheckAndResetDaily();

   if(!EA_Enabled) return;
   
   UpdatePanel(); 

   if(!CheckMinEquityProtection()) return;
   
   // 每根新K线收盘时才检测
   datetime curr_bar_time = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(curr_bar_time == last_bar_time) return;
   last_bar_time = curr_bar_time;
   
   // 有持仓则不操作
   if(HasOpenPosition()) return;
   
   // 获取前一根K线收盘价和MA值
   double ma_buffer[];
   if(CopyBuffer(ma_handle, 0, 1, 1, ma_buffer) != 1) return;
   
   double close_price = iClose(_Symbol, PERIOD_CURRENT, 1);
   
   double lot = GetNextLotSize(); 
   
   if(close_price > ma_buffer[0]) 
   {
      double macd_main[2], macd_signal[2];
      CopyBuffer(macd_handle, MAIN_LINE, 0, 2, macd_main);
      CopyBuffer(macd_handle, SIGNAL_LINE, 0, 2, macd_signal);
      bool macd_golden_cross = (macd_main[0] > macd_signal[0]) && (macd_main[1] <= macd_signal[1]);

      if(macd_golden_cross) // MACD金叉 → 开多
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl  = NormalizeDouble(ask - InpSLPoints * _Point, _Digits);
         double tp  = NormalizeDouble(ask + InpTPPoints * _Point, _Digits);
         trade.Buy(lot, _Symbol, 0.0, sl, tp, "MA多单");
      }

      RecordTradeResult(lot);
   }
   else if(close_price < ma_buffer[0]) // 收盘价 < MA → 开空
   {
      // 获取MACD值（主线和信号线）
      double macd_main[2], macd_signal[2];
      CopyBuffer(macd_handle, MAIN_LINE, 0, 2, macd_main);
      CopyBuffer(macd_handle, SIGNAL_LINE, 0, 2, macd_signal);
      bool macd_dead_cross = (macd_main[0] < macd_signal[0]) && (macd_main[1] >= macd_signal[1]);
      
      // 双重条件都满足才开空单
      if(macd_dead_cross)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl  = NormalizeDouble(bid + InpSLPoints * _Point, _Digits);
         double tp  = NormalizeDouble(bid - InpTPPoints * _Point, _Digits);
         trade.Sell(lot, _Symbol, 0.0, sl, tp, "MA+MACD死叉空单");
      }

      RecordTradeResult(lot);
   }
}

//+------------------------------------------------------------------+
//| 检查最小权益保护                                                 |
//+------------------------------------------------------------------+
bool CheckMinEquityProtection()
{
   if(!InpEnableMinEquityProtection) return true;
   
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double current_profit = current_equity - initial_balance;
   
   if(current_profit <= 0)
   {
      min_equity_protection = 0.0;
   }
   else
   {
      min_equity_protection = current_profit;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| 记录交易结果（更新连亏计数）                                     |
//+------------------------------------------------------------------+
void RecordTradeResult(double lot)
{
   // 延迟一段时间获取交易结果
   Sleep(2000);
   
   // 获取最后关闭的交易
   if(!HistorySelect(TimeCurrent() - 60, TimeCurrent() + 60)) return;
   
   double last_profit = 0;
   for(int i = HistoryDealsTotal()-1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagicNumber &&
         HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol &&
         HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
      {
         last_profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         
         if(last_profit < 0)  // 亏损
         {
            consecutive_losses++;
            PrintFormat("交易亏损: %.2f | 手数: %.2f | 连续亏损次数: %d", 
                       GetDisplayMoney(last_profit), lot, consecutive_losses);
         }
         else  // 盈利
         {
            consecutive_losses = 0;  // 重置连亏计数
            PrintFormat("交易盈利: %.2f | 手数: %.2f | 连亏计数重置", 
                       GetDisplayMoney(last_profit), lot);
         }
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| 是否有持仓                                                        |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && 
         PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| 根据上一笔订单盈亏计算本次手数（首次/盈利=BaseLot，亏损=2*BaseLot） |
//+------------------------------------------------------------------+
double GetNextLotSize()
{
   if(InpMaxConsecutiveLoss > 0 && consecutive_losses >= InpMaxConsecutiveLoss)
   {
      PrintFormat("达到最大连续亏损次数 %d，下一单使用基础手数 %.2f", 
                  InpMaxConsecutiveLoss, InpBaseLot);
      return InpBaseLot;
   }

   double lot = InpBaseLot;
   double last_profit = GetLastClosedProfit();
   double last_volume = GetLastClosedVolume();
   
   if(last_profit < 0 && last_volume > 0) 
        lot = last_volume * 2.0;
   
   // 规范化手数
   double minlot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxlot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lot = MathMax(minlot, MathMin(maxlot, lot));
   lot = MathRound(lot / lotstep) * lotstep;
   
   return lot;
}

//+------------------------------------------------------------------+
//| 获取上一笔平仓手数（用于加倍）                                   |
//+------------------------------------------------------------------+
double GetLastClosedVolume()
{
   if(!HistorySelect(0, TimeCurrent() + 3600)) return 0.0;
   
   for(int i = HistoryDealsTotal()-1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagicNumber &&
         HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol &&
         HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
      {
         return HistoryDealGetDouble(ticket, DEAL_VOLUME);
      }
   }
   return 0.0;
}

//+------------------------------------------------------------------+
//| 获取上一笔平仓订单盈亏                                             |
//+------------------------------------------------------------------+
double GetLastClosedProfit()
{
   if(!HistorySelect(0, TimeCurrent() + 3600)) return 0.0;
   
   for(int i = HistoryDealsTotal()-1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagicNumber &&
         HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol &&
         HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
      {
         return HistoryDealGetDouble(ticket, DEAL_PROFIT);
      }
   }
   return 0.0; 
}

//+------------------------------------------------------------------+
//| 创建面板                                                         |
//+------------------------------------------------------------------+
void CreatePanel()
{
   int x = InpPanelX, y = InpPanelY;
   
   ObjectCreate(0, PanelPrefix+"BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, PanelPrefix+"BG", OBJPROP_XDISTANCE, x-15);
   ObjectSetInteger(0, PanelPrefix+"BG", OBJPROP_YDISTANCE, y-15);
   ObjectSetInteger(0, PanelPrefix+"BG", OBJPROP_XSIZE, 360);
   ObjectSetInteger(0, PanelPrefix+"BG", OBJPROP_YSIZE, 260);
   ObjectSetInteger(0, PanelPrefix+"BG", OBJPROP_BGCOLOR, C'25,25,35');
   ObjectSetInteger(0, PanelPrefix+"BG", OBJPROP_BORDER_TYPE, BORDER_RAISED);
   
   CreateLabel("Title", "XAUUSD MA EA v1.01", x+65, y, clrGold, 13);
   y += 45;
   
   CreateLabel("BalLbl", "账户余额 (USD):", x+25, y, clrWhite);
   CreateLabel("BalVal", "0.00", x+200, y, clrWhite);
   y += 28;
   
   CreateLabel("EqLbl", "账户净值 (USD):", x+25, y, clrWhite);
   CreateLabel("EqVal", "0.00", x+200, y, clrWhite);
   y += 28;
   
   CreateLabel("ProfLbl", "持仓盈亏 (USD):", x+25, y, clrWhite);
   CreateLabel("ProfVal", "0.00", x+200, y, clrLime);
   y += 28;
   
   CreateLabel("StatLbl", "EA状态:", x+25, y, clrWhite);
   CreateLabel("StatVal", "运行", x+200, y, clrLime);
   y += 45;
   
   string btn = PanelPrefix + "CloseBtn";
   ObjectCreate(0, btn, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, btn, OBJPROP_XDISTANCE, x+60);
   ObjectSetInteger(0, btn, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, btn, OBJPROP_XSIZE, 210);
   ObjectSetInteger(0, btn, OBJPROP_YSIZE, 38);
   ObjectSetString(0, btn, OBJPROP_TEXT, "关闭EA并移除");
   ObjectSetInteger(0, btn, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, btn, OBJPROP_BGCOLOR, clrDarkRed);
   ObjectSetInteger(0, btn, OBJPROP_FONTSIZE, 12);
}

//+------------------------------------------------------------------+
//| 创建标签                                                         |
//+------------------------------------------------------------------+
void CreateLabel(string suffix, string text, int x, int y, color clr, int size=10)
{
   string name = PanelPrefix + suffix;
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
}

//+------------------------------------------------------------------+
//| 更新面板                                                         |
//+------------------------------------------------------------------+
void UpdatePanel()
{
   if(!EA_Enabled) return;
   
   double bal = GetDisplayMoney(AccountInfoDouble(ACCOUNT_BALANCE));
   double eq  = GetDisplayMoney(AccountInfoDouble(ACCOUNT_EQUITY));
   
   ObjectSetString(0, PanelPrefix+"BalVal", OBJPROP_TEXT, DoubleToString(bal, 2));
   ObjectSetString(0, PanelPrefix+"EqVal", OBJPROP_TEXT, DoubleToString(eq, 2));

   ObjectSetString(0, PanelPrefix+"InitVal", OBJPROP_TEXT, DoubleToString(GetDisplayMoney(initial_balance), 2));
   ObjectSetString(0, PanelPrefix+"MinEqVal", OBJPROP_TEXT, DoubleToString(GetDisplayMoney(min_equity_protection), 2));
   
   double profit = 0.0;
   if(PositionSelect(_Symbol))
   {
      profit = GetDisplayMoney(PositionGetDouble(POSITION_PROFIT));
   }
   ObjectSetString(0, PanelPrefix+"ProfVal", OBJPROP_TEXT, DoubleToString(profit, 2));
   ObjectSetInteger(0, PanelPrefix+"ProfVal", OBJPROP_COLOR, (profit >= 0) ? clrLime : clrRed);
   
   // 更新连亏信息
   ObjectSetString(0, PanelPrefix+"LossVal", OBJPROP_TEXT, 
                   StringFormat("%d/%d", consecutive_losses, InpMaxConsecutiveLoss));
   
   color loss_color = clrLime;
   if(consecutive_losses > 0 && consecutive_losses < InpMaxConsecutiveLoss)
      loss_color = clrYellow;
   else if(consecutive_losses >= InpMaxConsecutiveLoss)
      loss_color = clrRed;
   
   ObjectSetInteger(0, PanelPrefix+"LossVal", OBJPROP_COLOR, loss_color);
   
   // 更新风控状态
   string status_text = "正常";
   color status_color = clrLime;
   
   if(InpMaxConsecutiveLoss > 0 && consecutive_losses >= InpMaxConsecutiveLoss)
   {
      status_text = "连亏限制(基础手数)";
      status_color = clrOrange;
   }
   
   if(min_equity_protection > 0)
   {
      double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double current_profit = current_equity - initial_balance;
      
      if(current_profit > 0 && current_profit < min_equity_protection)
      {
         status_text = "权益保护中";
         status_color = clrBlue;
      }
   }
   
   ObjectSetString(0, PanelPrefix+"StatusVal", OBJPROP_TEXT, status_text);
   ObjectSetInteger(0, PanelPrefix+"StatusVal", OBJPROP_COLOR, status_color);
   
   ObjectSetString(0, PanelPrefix+"StatVal", OBJPROP_TEXT, EA_Enabled ? "运行" : "停止");
   ObjectSetInteger(0, PanelPrefix+"StatVal", OBJPROP_COLOR, EA_Enabled ? clrLime : clrRed);
}

//+------------------------------------------------------------------+
//| 删除面板                                                         |
//+------------------------------------------------------------------+
void DeletePanel()
{
   ObjectsDeleteAll(0, PanelPrefix);
}

//+------------------------------------------------------------------+
//| 按钮事件                                                         |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == PanelPrefix + "CloseBtn")
   {
      EA_Enabled = false;
      ObjectSetString(0, PanelPrefix+"StatVal", OBJPROP_TEXT, "已关闭");
      ObjectSetInteger(0, PanelPrefix+"StatVal", OBJPROP_COLOR, clrRed);
      ChartRedraw();
      Print("用户点击关闭EA → ExpertRemove()");
      ExpertRemove();
   }
}
//+------------------------------------------------------------------+