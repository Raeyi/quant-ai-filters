//+------------------------------------------------------------------+
//|                    Core/Risk/LosingStreakGuard.mqh               |
//|   连续亏损统计与冷却控制                                         |
//+------------------------------------------------------------------+
#ifndef __LOSING_STREAK_GUARD_MQH__
#define __LOSING_STREAK_GUARD_MQH__

input int MaxLosingStreak   = 3;   // 连续亏损次数阈值
input int CooldownBarsAfter = 5;   // 触发后冷却的 bar 数

class LosingStreakGuard
{
private:
   int      losing_streak;
   datetime cooldown_until_bar_time;

public:
   LosingStreakGuard()
   {
      losing_streak           = 0;
      cooldown_until_bar_time = 0;
   }

   void OnTradeClosed(double profit)
   {
      if(profit < 0.0)
         losing_streak++;
      else if(profit > 0.0)
         losing_streak = 0;

      if(losing_streak >= MaxLosingStreak)
      {
         datetime endBarTime = iTime(_Symbol, _Period, CooldownBarsAfter);
         cooldown_until_bar_time = endBarTime;
         PrintFormat("[LosingStreakGuard] Losing streak %d reached, cooldown %d bars until %s",
                     losing_streak, CooldownBarsAfter,
                     TimeToString(cooldown_until_bar_time, TIME_DATE|TIME_SECONDS));
         losing_streak = 0;
      }
   }

   bool CanTrade() const
   {
      if(cooldown_until_bar_time == 0)
         return true;

      datetime curBarTime = iTime(_Symbol, _Period, 0);
      if(curBarTime >= cooldown_until_bar_time)
         return true;

      return false;
   }

   int GetLosingStreak() const
   {
      return losing_streak;
   }

   datetime GetCooldownUntil() const
   {
      return cooldown_until_bar_time;
   }

   bool InCooldown() const
   {
      if(cooldown_until_bar_time == 0)
         return false;
      datetime curBarTime = iTime(_Symbol, _Period, 0);
      return curBarTime < cooldown_until_bar_time;
   }
};

#endif // __LOSING_STREAK_GUARD_MQH__
