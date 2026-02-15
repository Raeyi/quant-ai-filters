#ifndef __STATUS_PANEL_MQH__
#define __STATUS_PANEL_MQH__

#property strict

#include "../Risk/RiskPipeline.mqh"
#include "../PositionCoordinator.mqh"

input int   PanelX = 10;                 // 面板 X
input int   PanelY = 10;                 // 面板 Y
input color PanelBorderColor = clrDodgerBlue; // 面板边框
input color PanelBgColor = clrBlack;     // 面板背景
input int   PanelFontSize = 9;           // 字体大小
input int   PanelLineSpacing = 15;       // 行距

class StatusPanel
{
private:
   string prefix;
   int    corner;
   int    x;
   int    y;
   int    line;
   int    panel_width;
   int    panel_height;
   color  panel_border_color;
   color  panel_bg_color;
   int    font_size;

   void CreateBackground()
   {
      string obj = prefix + "BG";
      if(ObjectFind(0, obj) >= 0)
         return;

      ObjectCreate(0, obj, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, obj, OBJPROP_CORNER, corner);
      ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, obj, OBJPROP_XSIZE, panel_width);
      ObjectSetInteger(0, obj, OBJPROP_YSIZE, panel_height);
      ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, panel_bg_color);
      ObjectSetInteger(0, obj, OBJPROP_COLOR, panel_border_color);
      ObjectSetInteger(0, obj, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, obj, OBJPROP_BACK, false);
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
   }

   void CreateLabel(const string name, int dy)
   {
      string obj = prefix + name;
      if(ObjectFind(0, obj) >= 0)
         return;

      ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, obj, OBJPROP_CORNER, corner);
      ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x + 10);
      ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y + dy);
      ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, font_size);
      ObjectSetInteger(0, obj, OBJPROP_COLOR, clrWhite);
      ObjectSetString(0, obj, OBJPROP_FONT, "Microsoft YaHei");
   }

   void SetText(const string name, const string text, color clr = clrWhite)
   {
      ObjectSetString(0, prefix + name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, prefix + name, OBJPROP_COLOR, clr);
   }

   int CountPositions() const
   {
      int count = 0;
      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
      {
         if(PositionGetTicket(i) == 0)
            continue;
         string sym = PositionGetString(POSITION_SYMBOL);
         if(sym == _Symbol)
            count++;
      }
      return count;
   }

   double SumFloatingProfit() const
   {
      double total_profit = 0.0;
      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
      {
         if(PositionGetTicket(i) == 0)
            continue;
         string sym = PositionGetString(POSITION_SYMBOL);
         if(sym == _Symbol)
            total_profit += PositionGetDouble(POSITION_PROFIT);
      }
      return total_profit;
   }

   int CountTodayTrades() const
   {
      datetime day_start = iTime(_Symbol, PERIOD_D1, 0);
      HistorySelect(day_start, TimeCurrent());

      int deals = HistoryDealsTotal();
      int count = 0;
      for(int i = deals - 1; i >= 0; i--)
      {
         ulong deal = HistoryDealGetTicket(i);
         if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol)
            continue;
         long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_IN || entry == DEAL_ENTRY_INOUT)
            count++;
      }
      return count;
   }

   string TFToString(ENUM_TIMEFRAMES tf) const
   {
      switch(tf)
      {
         case PERIOD_M1:  return "M1";
         case PERIOD_M5:  return "M5";
         case PERIOD_M15: return "M15";
         case PERIOD_M30: return "M30";
         case PERIOD_H1:  return "H1";
         case PERIOD_H4:  return "H4";
         case PERIOD_D1:  return "D1";
      }
      return "UNKNOWN";
   }

public:
   StatusPanel()
   {
      prefix = "STATUS_PANEL_";
      corner = CORNER_LEFT_UPPER;
      x      = 10;
      y      = 10;
      line   = 15;
      panel_width  = 320;
      panel_height = 330;  // 增加高度以容纳Regime和冷却状态行
      panel_border_color = clrDodgerBlue;
      panel_bg_color = clrBlack;
      font_size = 9;
   }

   void Init()
   {
      x = PanelX;
      y = PanelY;
      line = PanelLineSpacing;
      panel_border_color = PanelBorderColor;
      panel_bg_color = PanelBgColor;
      font_size = PanelFontSize;

      CreateBackground();
      int i = 0;
      CreateLabel("TITLE",        line * i++); i++;
      CreateLabel("TIME",         line * i++);
      CreateLabel("SYMBOL",       line * i++);
      CreateLabel("TIMEFRAME",    line * i++);
      CreateLabel("EA_STATE",     line * i++);
      i++; // 在基础信息和账户信息之间留空行
      CreateLabel("BALANCE",      line * i++); i++;
      CreateLabel("TODAY_PNL",    line * i++);
      CreateLabel("FLOAT_PNL",    line * i++);
      CreateLabel("POSITION_CNT", line * i++);
      CreateLabel("TODAY_TRADES", line * i++);
      CreateLabel("CONSEC_LOSS",  line * i++); i++;
      CreateLabel("REGIME_STATE", line * i++);  // Regime 状态
      CreateLabel("NO_TRADE",     line * i++);
      CreateLabel("TIME_FILTER",  line * i++);
      CreateLabel("COOLDOWN",     line * i++);  // 结构冷却器状态
      CreateLabel("STATUS",       line * i++);
      CreateLabel("RISK_STATUS",  line * i++);
   }

   void Update(RiskPipeline& rp,
               PositionCoordinator& pc,
               bool ea_disabled,
               const string ea_reason,
               bool time_allowed,
               const string time_reason,
               bool structural_cooldown_active = false,
               string structural_cooldown_reason = "",
               int structural_cooldown_remaining = 0,
               string regime_state_str = "ACTIVE",
               string regime_subtype_str = "",
               double regime_q_score = 0.5)
   {
      rp.RefreshStatus();

      SetText("TITLE", "=== 交易系统 ===", clrDodgerBlue);
      SetText("TIME",   "时间(MT5): " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
      SetText("SYMBOL", "品种: " + _Symbol);
      SetText("TIMEFRAME", "周期: " + TFToString(_Period));
      string ea_state = ea_disabled ? "禁用" : "运行";
      if(ea_disabled && ea_reason != "")
         ea_state += " (" + ea_reason + ")";
      SetText("EA_STATE", "EA状态: " + ea_state, ea_disabled ? clrOrange : clrLime);

      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
      SetText("BALANCE", "账户余额: $" + DoubleToString(balance, 2), clrLime);

      static double day_start_balance = 0;
      static datetime last_day = 0;
      datetime now_day = iTime(_Symbol, PERIOD_D1, 0);
      if(now_day != last_day)
      {
         day_start_balance = balance;
         last_day = now_day;
      }

      double today_pnl = balance - day_start_balance;
      color today_color = (today_pnl >= 0.0) ? clrLime : clrRed;
      SetText("TODAY_PNL", "当日盈亏: $" + DoubleToString(today_pnl, 2), today_color);

      double float_pnl = SumFloatingProfit();
      color float_color = (float_pnl >= 0.0) ? clrLime : clrRed;
      SetText("FLOAT_PNL", "浮动盈亏: $" + DoubleToString(float_pnl, 2), float_color);

      int pos_count = CountPositions();
      bool has_pos = pc.HasPosition();
      SetText("POSITION_CNT", "持仓订单数: " + IntegerToString(pos_count));
      SetText("TODAY_TRADES", "当日交易数: " + IntegerToString(CountTodayTrades()));
      int consec_losses = rp.GetConsecutiveLosses();
      SetText("CONSEC_LOSS", "连续止损数: " + IntegerToString(consec_losses),
              consec_losses > 0 ? clrOrange : clrWhite);

      // Regime 状态显示
      string regime_text = "Regime: " + regime_state_str;
      if(regime_subtype_str != "")
         regime_text += " [" + regime_subtype_str + "]";
      regime_text += " Q=" + DoubleToString(regime_q_score, 2);
      color regime_color = (regime_state_str == "ACTIVE") ? clrLime : 
                          (regime_state_str == "STANDBY") ? clrOrange : clrYellow;
      SetText("REGIME_STATE", regime_text, regime_color);

      bool allow_entry_time = rp.IsEntryAllowed() && time_allowed && (regime_state_str == "ACTIVE");
      string no_trade_text = "禁止交易: " + string(allow_entry_time ? "否" : "是");
      if(!allow_entry_time)
      {
         string reason = rp.GetBlockReason();
         if(!time_allowed)
         {
            if(time_reason != "")
               reason = time_reason;
            else
               reason = "交易时间限制";
         }
         if(reason != "")
            no_trade_text += " (" + reason + ")";
      }
      SetText("NO_TRADE", no_trade_text, allow_entry_time ? clrLime : clrRed);

      string time_filter_text = "时间窗口: " + string(time_allowed ? "允许" : "限制");
      if(!time_allowed && time_reason != "")
         time_filter_text += " (" + time_reason + ")";
      SetText("TIME_FILTER", time_filter_text, time_allowed ? clrLime : clrOrange);

      // 结构冷却器状态显示
      string cooldown_text = "结构冷却: " + string(structural_cooldown_active ? "冷却中" : "正常");
      if(structural_cooldown_active)
      {
         cooldown_text += " (" + structural_cooldown_reason;
         if(structural_cooldown_remaining > 0)
            cooldown_text += " 剩余" + IntegerToString(structural_cooldown_remaining) + "根K线";
         cooldown_text += ")";
      }
      SetText("COOLDOWN", cooldown_text, structural_cooldown_active ? clrOrange : clrLime);

      string status = "等待信号";
      color status_color = clrWhite;
      if(has_pos)
         status = "持仓中(" + IntegerToString(pos_count) + ")";
      if(!allow_entry_time)
      {
         status = "交易受限";
         status_color = clrOrange;
      }
      SetText("STATUS", "状态: " + status, status_color);

      string risk_status = "正常";
      color risk_color = clrLime;
      if(!allow_entry_time)
      {
         if(!time_allowed)
         {
            risk_status = "交易时间限制";
            risk_color = clrOrange;
         }
         else if(rp.IsInCooldown())
         {
            risk_status = "冷却中";
            risk_color = clrOrange;
         }
         else
         {
            risk_status = "限制交易";
            risk_color = clrRed;
         }
      }
      SetText("RISK_STATUS", "风险状态: " + risk_status, risk_color);
   }
};

#endif // __STATUS_PANEL_MQH__