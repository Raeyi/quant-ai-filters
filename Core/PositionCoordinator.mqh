//+------------------------------------------------------------------+
//|                      Core/PositionCoordinator.mqh                |
//|      负责：记录当前 symbol 仓位方向 & 来源策略，做冲突仲裁       |
//|            仓位盈亏追踪（支持多次部分平仓）                       |
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

// 仓位盈亏追踪器
struct PositionTracker
{
   bool      active;           // 是否有活跃追踪
   ulong     open_ticket;      // 开仓时的订单号
   double    entry_price;      // 开仓均价
   double    total_volume;     // 开仓总量
   double    remaining_vol;    // 剩余仓量
   long      direction;        // 方向: POSITION_TYPE_BUY/SELL
   datetime  open_time;        // 开仓时间
   string    source;           // 策略来源
   
   // 累计盈亏
   double    total_profit;     // 累计盈亏
   double    total_swap;       // 累计库存费
   double    total_commission; // 累计手续费
   double    total_net;        // 累计净盈亏
   int       close_count;      // 平仓次数
   
   void Init(double entry, double vol, long dir, string src)
   {
      active = true;
      open_ticket = 0;
      entry_price = entry;
      total_volume = vol;
      remaining_vol = vol;
      direction = dir;
      open_time = TimeCurrent();
      source = src;
      total_profit = 0;
      total_swap = 0;
      total_commission = 0;
      total_net = 0;
      close_count = 0;
   }
   
   void Reset()
   {
      active = false;
      open_ticket = 0;
      entry_price = 0;
      total_volume = 0;
      remaining_vol = 0;
      direction = 0;
      open_time = 0;
      source = "";
      total_profit = 0;
      total_swap = 0;
      total_commission = 0;
      total_net = 0;
      close_count = 0;
   }
   
   void AddCloseResult(double profit, double swap, double comm, double vol)
   {
      total_profit += profit;
      total_swap += swap;
      total_commission += comm;
      total_net += (profit + swap + comm);
      remaining_vol -= vol;
      close_count++;
   }
   
   bool IsFullyClosed() const { return active && remaining_vol <= 0.0001; }
};

class PositionCoordinator
{
private:
   PositionSide current_side;
   string       current_source;   // 哪个策略开的仓
   PositionTracker tracker;       // 仓位盈亏追踪器

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
      Print("[PositionCoordinator] Position exists, rejecting new trade signal. type=", signal.type, " source=", signal.source, " current_side=", current_side);
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

   void PrintState() const
   {
      Print("[PositionCoordinator] State: side=", current_side, " source=", current_source);
   }
   
   // ===== 仓位追踪器接口 =====
   double GetTrackerNetProfit() const { return tracker.total_net; }
   
   // 初始化追踪器（开仓时调用）
   void InitTracker(double entry, double vol, long dir, string src)
   {
      tracker.Init(entry, vol, dir, src);
      tracker.open_ticket = PositionSelect(_Symbol) ? (ulong)PositionGetInteger(POSITION_TICKET) : 0;
      Print("[仓位追踪] 开始追踪 | 方向: ", (dir==POSITION_TYPE_BUY?"BUY":"SELL"),
            " | 入场: ", DoubleToString(tracker.entry_price, _Digits),
            " | 总量: ", DoubleToString(tracker.total_volume, 2),
            " | 来源: ", tracker.source);
   }
   
   // 累加平仓结果
   void AddCloseResult(double profit, double swap, double comm, double vol)
   {
      tracker.AddCloseResult(profit, swap, comm, vol);
   }
   
   // 打印平仓信息
   void PrintCloseResult(double this_profit, double this_vol)
   {
      string dir_str = (tracker.direction == POSITION_TYPE_BUY ? "BUY" : "SELL");
      string profit_sign = (this_profit >= 0 ? "+" : "");
      int elapsed = (int)(TimeCurrent() - tracker.open_time);
      int hours = elapsed / 3600;
      int mins = (elapsed % 3600) / 60;
      
      Print("[平仓#", tracker.close_count, "] ", dir_str,
            " | 本次量: ", DoubleToString(this_vol, 2),
            " | 本次盈亏: ", profit_sign, DoubleToString(this_profit, 2));
      
      if(tracker.IsFullyClosed())
      {
         string net_sign = (tracker.total_net >= 0 ? "+" : "");
         Print("========== [仓位总结] ==========");
         Print("  方向: ", dir_str, " | 来源: ", tracker.source);
         Print("  开仓时间: ", TimeToString(tracker.open_time, TIME_DATE|TIME_MINUTES),
               " | 平仓时间: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES),
               " | 持仓时长: ", hours, "h", mins, "m");
         Print("  入场价: ", DoubleToString(tracker.entry_price, _Digits),
               " | 总仓量: ", DoubleToString(tracker.total_volume, 2));
         Print("  平仓次数: ", tracker.close_count,
               " | 总盈亏: ", net_sign, DoubleToString(tracker.total_profit, 2),
               " | 总库存费: ", DoubleToString(tracker.total_swap, 2),
               " | 总手续费: ", DoubleToString(tracker.total_commission, 2));
         Print("  ========== 净盈亏: ", net_sign, DoubleToString(tracker.total_net, 2), " ==========");
      }
      else
      {
         string net_sign = (tracker.total_net >= 0 ? "+" : "");
         Print("[累计统计] 已平: ", DoubleToString(tracker.total_volume - tracker.remaining_vol, 2),
               "/", DoubleToString(tracker.total_volume, 2),
               " | 累计净盈亏: ", net_sign, DoubleToString(tracker.total_net, 2),
               " | 剩余: ", DoubleToString(tracker.remaining_vol, 2));
      }
   }
   
   // 打印总体总结（完全平仓时）
   void PrintFinalSummary()
   {
      string dir_str = (tracker.direction == POSITION_TYPE_BUY ? "BUY" : "SELL");
      string net_sign = (tracker.total_net >= 0 ? "+" : "");
      Print("========== [仓位总结] ==========");
      Print("  方向: ", dir_str, " | 来源: ", tracker.source);
      Print("  总盈亏: ", net_sign, DoubleToString(tracker.total_net, 2));
   }
   
   void ResetTracker() { tracker.Reset(); }
   bool IsTrackerActive() const { return tracker.active; }
   bool IsTrackerFullyClosed() const { return tracker.IsFullyClosed(); }
};

#endif // __POSITION_COORDINATOR_MQH__
