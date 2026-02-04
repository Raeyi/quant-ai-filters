#property strict

struct RiskStatus
{
   bool allow_entry;   // 是否允许开仓
   bool in_cooldown;   // 是否处于冷却期
};