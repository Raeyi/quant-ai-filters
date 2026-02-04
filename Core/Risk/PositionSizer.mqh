//+------------------------------------------------------------------+
//|                      Core/Risk/PositionSizer.mqh                 |
//|         职责：根据账户风险百分比 + SL 距离 计算交易手数           |
//+------------------------------------------------------------------+
#ifndef __POSITION_SIZER_MQH__
#define __POSITION_SIZER_MQH__

#include "../Signal.mqh"
#include "../TradeTypes.mqh"

input double InpRiskPercent = 1.0; // 每单风险占权益百分比

class PositionSizer
{
public:
   // 计算手数：根据 signal.price / signal.sl 和风险百分比
   double ComputeLot(const Signal &signal)
   {
      if(signal.sl <= 0.0 || signal.price <= 0.0)
      {
         Print("[PositionSizer] Invalid signal price/sl");
         return 0.0;
      }

      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double risk_amount = equity * InpRiskPercent / 100.0;
      if(risk_amount <= 0.0)
         return 0.0;

      double price    = signal.price;
      double sl       = signal.sl;
      double tick_val = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_sz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

      if(tick_val <= 0.0 || tick_sz <= 0.0)
      {
         Print("[PositionSizer] Invalid tick value/size");
         return 0.0;
      }

      double dist   = MathAbs(price - sl);   // 价格距离
      double points = dist / tick_sz;        // 换算成最小跳动数
      double loss_per_1lot = points * tick_val;

      if(loss_per_1lot <= 0.0)
         return 0.0;

      double lot = risk_amount / loss_per_1lot;

      // 和品种规则对齐
      double min_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double max_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

      if(lot_step > 0)
         lot = MathFloor(lot / lot_step) * lot_step;

      if(lot < min_lot)
      {
         Print("[PositionSizer] Computed lot <", min_lot, ", skip");
         return 0.0;
      }
      if(lot > max_lot)
         lot = max_lot;

      return lot;
   }
};

#endif // __POSITION_SIZER_MQH__
