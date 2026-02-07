//+------------------------------------------------------------------+
//| StatusPanel.mqh                                                  |
//| 中文交易状态面板（用户视角）                                      |
//+------------------------------------------------------------------+
#ifndef __STATUS_PANEL_MQH__
#define __STATUS_PANEL_MQH__

#property strict

#include "../Risk/RiskPipeline.mqh"
#include "../PositionCoordinator.mqh"

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
   string bg_name;

   void CreateBackground()
   {
      if(ObjectFind(0, bg_name) >= 0)
         return;

      ObjectCreate(0, bg_name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bg_name, OBJPROP_CORNER, corner);
      ObjectSetInteger(0, bg_name, OBJPROP_XDISTANCE, x - 5);
      ObjectSetInteger(0, bg_name, OBJPROP_YDISTANCE, y - 5);
      ObjectSetInteger(0, bg_name, OBJPROP_XSIZE, panel_width);
      ObjectSetInteger(0, bg_name, OBJPROP_YSIZE, panel_height);
      ObjectSetInteger(0, bg_name, OBJPROP_COLOR, clrDimGray);
      ObjectSetInteger(0, bg_name, OBJPROP_BGCOLOR, clrBlack);
      ObjectSetInteger(0, bg_name, OBJPROP_BACK, true);
   }

   void CreateLabel(const string name, int dy, color text_color, int font_size)
   {
      string obj = prefix + name;
      if(ObjectFind(0, obj) >= 0)
         return;

      ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, obj, OBJPROP_CORNER, corner);
      ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y + dy);
      ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, font_size);
      ObjectSetInteger(0, obj, OBJPROP_COLOR, text_color);
      ObjectSetString(0, obj, OBJPROP_FONT, "Microsoft YaHei");
   }

   void SetText(const string name, const string text)
   {
      ObjectSetString(0, prefix + name, OBJPROP_TEXT, text);
   }

   void SetColor(const string name, color text_color)
   {
      ObjectSetInteger(0, prefix + name, OBJPROP_COLOR, text_color);
   }

   string TFToString(ENUM_TIMEFRAMES tf)
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
      return "未知";
   }

public:
   StatusPanel()
   {
      prefix = "STATUS_PANEL_";
      bg_name = "STATUS_PANEL_BG";
      corner = CORNER_LEFT_UPPER;
      x      = 10;
      y      = 10;
      line   = 16;
      panel_width = 270;
      panel_height = 320;
   }

   void Init()
   {
      int i = 0;
      CreateBackground();
      CreateLabel("TITLE",        line * i++, clrAqua, 11); i++;
      CreateLabel("TIME",         line * i++, clrWhite, 10);
      CreateLabel("SYMBOL",       line * i++, clrWhite, 10);
      CreateLabel("TIMEFRAME",    line * i++, clrWhite, 10); i++;
      CreateLabel("BALANCE",      line * i++, clrWhite, 10);
      CreateLabel("EQUITY",       line * i++, clrWhite, 10);
      CreateLabel("TODAY_PNL",    line * i++, clrWhite, 10);
      CreateLabel("FLOAT_PNL",    line * i++, clrWhite, 10); i++;
      CreateLabel("POSITION",     line * i++, clrWhite, 10);
      CreateLabel("VOLUME",       line * i++, clrWhite, 10); i++;
      CreateLabel("RISK",         line * i++, clrWhite, 10);
      CreateLabel("COOLDOWN",     line * i++, clrWhite, 10);
      CreateLabel("ALLOW_ENTRY",  line * i++, clrWhite, 10);
   }

   void Update(RiskPipeline& rp,
               PositionCoordinator& pc)
   {
      // ===== 标题 =====
      SetText("TITLE", "=== 交易系统状态面板 ===");

      // ===== 基本信息 =====
      SetText("TIME",      "时间：" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
      SetText("SYMBOL",    "品种：" + _Symbol);
      SetText("TIMEFRAME", "周期：" + TFToString(_Period));

      // ===== 账户 =====
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity  = AccountInfoDouble(ACCOUNT_EQUITY);

      SetText("BALANCE", "账户余额：" + DoubleToString(balance, 2));
      SetText("EQUITY",  "账户净值：" + DoubleToString(equity, 2));

      // 当日盈亏（简单版：净值 - 今日起始余额）
      static double day_start_equity = 0;
      static datetime last_day = 0;
      datetime now_day = (datetime)(TimeCurrent() / 86400);

      if(now_day != last_day)
      {
         day_start_equity = equity;
         last_day = now_day;
      }

      double today_pnl = equity - day_start_equity;
      SetText("TODAY_PNL", "当日盈亏：" + DoubleToString(today_pnl, 2));

      // ===== 风控状态 =====
      RiskStatus rs = rp.GetStatus();
      string risk_text = rs.allow_entry ? "允许交易" : "禁止交易";
      string cooldown_text = rs.in_cooldown ? "是" : "否";
      SetText("RISK", "风险状态：" + risk_text);
      SetText("COOLDOWN", "冷却状态：" + cooldown_text);
      SetText("ALLOW_ENTRY", "允许开仓：" + risk_text);
      SetColor("RISK", rs.allow_entry ? clrLime : clrTomato);
      SetColor("ALLOW_ENTRY", rs.allow_entry ? clrLime : clrTomato);
      SetColor("COOLDOWN", rs.in_cooldown ? clrOrange : clrLime);

      // ===== 持仓状态 =====
      if(pc.HasPosition())
      {
         string dir = pc.IsLong() ? "多单" : "空单";
         SetText("POSITION", "持仓状态：" + dir);
         SetText("VOLUME",   "持仓手数：" + DoubleToString(pc.Volume(), 2));
         SetText("FLOAT_PNL","浮动盈亏：" + DoubleToString(pc.FloatingProfit(), 2));
      }
      else
      {
         SetText("POSITION", "持仓状态：无");
         SetText("VOLUME",   "持仓手数：0");
         SetText("FLOAT_PNL","浮动盈亏：0");
      }

      SetColor("FLOAT_PNL", pc.FloatingProfit() >= 0.0 ? clrLime : clrTomato);
      SetColor("TODAY_PNL", today_pnl >= 0.0 ? clrLime : clrTomato);
   }
};

#endif // __STATUS_PANEL_MQH__
