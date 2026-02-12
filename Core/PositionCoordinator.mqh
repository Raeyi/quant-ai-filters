//+------------------------------------------------------------------+
//|                      Core/PositionCoordinator.mqh                |
//|      只负责：记录当前 symbol 仓位方向 & 来源策略，做冲突仲裁       |
//+------------------------------------------------------------------+
#ifndef __POSITION_COORDINATOR_MQH__
#define __POSITION_COORDINATOR_MQH__

#include "Signal.mqh"

enum PositionSide
{
   POS_NONE = 0,
   POS_LONG,
   POS_SHORT
};

class PositionCoordinator
{
private:
   PositionSide current_side;
   string       current_source;   // 哪个策略开的仓

public:
   PositionCoordinator()
   {
      current_side  = POS_NONE;
      current_source = "";
   }

   bool HasPosition()    // 检查是否有持仓
    {
        return PositionSelect(_Symbol);
    }

   // 在每次 OnTick 可以调用一次，和真实仓位同步（防断线/手动平仓）
   void SyncFromTerminal()
   {
      if(!HasPosition()) // 无持仓
      {
         current_side   = POS_NONE;
         current_source = "";
         return;
      }

      long  type = PositionGetInteger(POSITION_TYPE); // 获取仓位类型
      if(type == POSITION_TYPE_BUY)
         current_side = POS_LONG;
      else if(type == POSITION_TYPE_SELL)
         current_side = POS_SHORT;
      else
         current_side = POS_NONE;

      // source 可以存在 position comment / magic 等，这里先不强依赖
   }

   // 新信号到来时，检查是否允许这个信号介入
   bool AllowSignal(const Signal &signal)
   {
      // 对于SIGNAL_NONE（type=0）不打印日志，减少噪音
      if(signal.type == SIGNAL_NONE)
      {
         return false;
      }
      
      // 没有持仓，允许新开仓信号
      if(current_side == POS_NONE)
      {
         Print("[PositionCoordinator] No position, allowing signal. type=", signal.type, " source=", signal.source);
         return true;
      }

      // 加仓信号：检查方向是否一致
      if(signal.type == SIGNAL_ADD_LONG && current_side == POS_LONG)
      {
         Print("[PositionCoordinator] Add long signal allowed. type=", signal.type, " source=", signal.source);
         return true;
      }
      if(signal.type == SIGNAL_ADD_SHORT && current_side == POS_SHORT)
      {
         Print("[PositionCoordinator] Add short signal allowed. type=", signal.type, " source=", signal.source);
         return true;
      }

      // 新开仓信号：已有仓位时拒绝
      // 每分钟最多打印一次拒绝日志
      static datetime last_reject_log = 0;
      datetime current_time = TimeCurrent();
      if(current_time - last_reject_log >= 60)
      {
         last_reject_log = current_time;
         Print("[PositionCoordinator] Position exists, rejecting new trade signal. type=", signal.type, " source=", signal.source, " current_side=", current_side);
      }
      return false;
   }

   // 在开仓成功后调用，记录仓位状态
   void OnPositionOpened(const Signal &signal)
   {
      if(signal.type == SIGNAL_BUY || signal.type == SIGNAL_ADD_LONG)
         current_side = POS_LONG;
      else if(signal.type == SIGNAL_SELL || signal.type == SIGNAL_ADD_SHORT)
         current_side = POS_SHORT;
      else
         current_side = POS_NONE;

      current_source = signal.source;
   }

   // 在平仓成功后调用
   void OnPositionClosed()
   {
      current_side   = POS_NONE;
      current_source = "";
   }

   // ===== 新增：给 UI 用 =====
   bool IsLong() const
   {
      if(!PositionSelect(_Symbol))
         return false;

      long type = PositionGetInteger(POSITION_TYPE);
      return type == POSITION_TYPE_BUY;
   }

   double Volume() const
   {
      if(!PositionSelect(_Symbol))
         return 0.0;

      return PositionGetDouble(POSITION_VOLUME);
   }

   double FloatingProfit() const
   {
      if(!PositionSelect(_Symbol))
         return 0.0;

      return PositionGetDouble(POSITION_PROFIT);
   }
};

#endif // __POSITION_COORDINATOR_MQH__
