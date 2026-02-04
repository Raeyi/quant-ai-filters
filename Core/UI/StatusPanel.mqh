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

   void CreateLabel(const string name, int dy)
   {
      string obj = prefix + name;
      if(ObjectFind(0, obj) >= 0)
         return;

      ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, obj, OBJPROP_CORNER, corner);
      ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y + dy);
      ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 10);
      ObjectSetInteger(0, obj, OBJPROP_COLOR, clrWhite);
      ObjectSetString(0, obj, OBJPROP_FONT, "Microsoft YaHei");
   }

   void SetText(const string name, const string text)
   {
      ObjectSetString(0, prefix + name, OBJPROP_TEXT, text);
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
      corner = CORNER_LEFT_UPPER;
      x      = 10;
      y      = 10;
      line   = 16;
   }

   void Init()
   {
      int i = 0;
      CreateLabel("TITLE",      line * i++); i++;
      CreateLabel("SYMBOL",     line * i++);
      CreateLabel("TIMEFRAME",  line * i++);
      CreateLabel("TIME",       line * i++); i++;
      CreateLabel("BALANCE",    line * i++);
      CreateLabel("EQUITY",     line * i++);
      CreateLabel("TODAY_PNL",  line * i++); i++;
      CreateLabel("RISK",       line * i++);
      CreateLabel("COOLDOWN",   line * i++); i++;
      CreateLabel("POSITION",   line * i++);
      CreateLabel("VOLUME",     line * i++);
      CreateLabel("FLOAT_PNL",  line * i++);
   }

   void Update(RiskPipeline& rp,
               PositionCoordinator& pc)
   {
      // ===== 标题 =====
      SetText("TITLE", "━━━━━━━━ 交易系统状态 ━━━━━━━━");

      // ===== 基本信息 =====
      SetText("SYMBOL",    "品种：" + _Symbol);
      SetText("TIMEFRAME", "周期：" + TFToString(_Period));
      SetText("TIME",      "时间：" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));

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
      SetText("RISK", "风险状态：" + string(rs.allow_entry ? "允许交易" : "禁止交易"));
      SetText("COOLDOWN", "冷却状态：" + string(rs.in_cooldown ? "是" : "否"));

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
   }
};

#endif // __STATUS_PANEL_MQH__
