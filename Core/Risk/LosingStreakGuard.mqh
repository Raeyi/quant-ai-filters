//+------------------------------------------------------------------+
//|                    Core/Risk/LosingStreakGuard.mqh               |
//|   职责：统计连续亏损次数，触发“按N次止损 → 冷却若干bar”           |
//+------------------------------------------------------------------+
#ifndef __LOSING_STREAK_GUARD_MQH__
#define __LOSING_STREAK_GUARD_MQH__

input int MaxLosingStreak   = 3;   // 连续亏损次数阈值
input int CooldownBarsAfter = 5;   // 达到连续亏损触发后冷却的bar数

class LosingStreakGuard
{
private:
   int      losing_streak;     // 当前连续亏损次数
   datetime cooldown_until_bar_time; // 冷却结束那根bar的时间（bar 的 open time）

public:
   LosingStreakGuard()
   {
      losing_streak          = 0;
      cooldown_until_bar_time = 0;
   }

   // 每次平仓后调用，profit = 本次平仓盈亏（可以是净利润）
   void OnTradeClosed(double profit)
   {
      if(profit < 0.0)
         losing_streak++;
      else if(profit > 0.0)
         losing_streak = 0;  // 有盈利就清零连亏

      // 触发冷却
      if(losing_streak >= MaxLosingStreak)
      {
         // 从当前bar开始，往后 N 根bar 冷却
         datetime curBarTime = iTime(_Symbol, _Period, 0);
         int      bars_to_add = CooldownBarsAfter;
         // 计算“第 N 根之后”的 bar 时间
         datetime endBarTime  = iTime(_Symbol, _Period, bars_to_add);

         cooldown_until_bar_time = endBarTime;
         PrintFormat("[LosingStreakGuard] Losing streak %d reached, cooldown %d bars until %s",
                     losing_streak, CooldownBarsAfter,
                     TimeToString(cooldown_until_bar_time, TIME_DATE|TIME_SECONDS));

         // 冷却后可以选择清零，或者保留 streak 看你风格
         losing_streak = 0;
      }
   }

   // 在建仓前调用
   bool CanTrade() const
   {
      if(cooldown_until_bar_time == 0)
         return true;

      datetime curBarTime = iTime(_Symbol, _Period, 0);

      // 当前bar的时间 >= 冷却结束bar时间 → 冷却完毕
      if(curBarTime >= cooldown_until_bar_time)
         return true;

      // 仍在冷却期
      return false;
   }
};

#endif // __LOSING_STREAK_GUARD_MQH__
