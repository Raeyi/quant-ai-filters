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

   // 在每次 OnTick 可以调用一次，和真实仓位同步（防断线/手动平仓）
   void SyncFromTerminal()
   {
      if(!PositionSelect(_Symbol))
      {
         current_side   = POS_NONE;
         current_source = "";
         return;
      }

      long  type = PositionGetInteger(POSITION_TYPE);
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
      // 没有持仓，任何方向都允许
      if(current_side == POS_NONE)
         return true;

      // 已经有仓位 —— 保守版：直接拒绝所有新信号
      // 后续你想做“反手/加仓”，就在这里改策略
      return false;
   }

   // 在开仓成功后调用，记录仓位状态
   void OnPositionOpened(const Signal &signal)
   {
      if(signal.type == SIGNAL_BUY)
         current_side = POS_LONG;
      else if(signal.type == SIGNAL_SELL)
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
};

#endif // __POSITION_COORDINATOR_MQH__
