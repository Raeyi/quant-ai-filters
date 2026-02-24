//+------------------------------------------------------------------+
//|                      Core/Risk/PositionSizer.mqh                 |
//|         职责：根据账户风险百分比 + SL 距离 计算交易手数           |
//+------------------------------------------------------------------+
#ifndef __POSITION_SIZER_MQH__
#define __POSITION_SIZER_MQH__

#include "../Signal.mqh"
#include "../TradeTypes.mqh"
#include "../Inputs_All.mqh"

// 输入参数定义在 Inputs_All.mqh，此文件不再重复声明

/*
================================================================================
手数计算公式说明
================================================================================

【基本概念】
- tick_sz (tick_size)     : 最小价格变动单位，如黄金 = 0.01 美元
- contract_size           : 1手合约的标的数量，如黄金 = 100 盎司
- tick_val (tick_value)   : 价格变动1个tick，1手合约的盈亏金额
                            标准公式: tick_val = tick_sz × contract_size
                            黄金标准: 0.01 × 100 = 1.0

【tick_val 的单位】
- 美元账户: tick_val 单位是美元，如 1.0 USD
- 美分账户: tick_val 单位是美分，如 1.0 USC
- 两者数值相同(都是~1.0)，只是单位不同，计算结果一致

【手数计算公式】
1. 风险金额 = 账户净值 × 风险百分比
2. SL点数   = |入场价 - SL价| / tick_sz
3. 每手亏损 = SL点数 × tick_val
4. 手数     = 风险金额 / 每手亏损

【举例】两种账户交易黄金 (结果相同)
美元账户 (equity=50000 USD):
  - 风险金额 = 500 USD, tick_val = 1.0 USD
  - SL=10美元 = 1000点, 每手亏损 = 1000 USD
  - 手数 = 500 / 1000 = 0.50手

美分账户 (equity=50000 USC = 500美元):
  - 风险金额 = 500 USC, tick_val = 1.0 USC
  - SL=10美元 = 1000点, 每手亏损 = 1000 USC
  - 手数 = 500 / 1000 = 0.50手

================================================================================
*/

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
      double contract_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      
      // 黄金标准 tick_val = tick_sz × 100 (contract_size)
      // 美元账户: 1.0 USD, 美分账户: 1.0 USC (单位不同但数值相同)
      double expected_tick_val = tick_sz * 100.0;  // 黄金 contract_size = 100
      
      // 判断 tick_val 是否有效
      // 有效范围: 预期值的 50% ~ 200%
      bool tick_val_valid = (tick_val > 0.0 && 
                             tick_val >= expected_tick_val * 0.5 && 
                             tick_val <= expected_tick_val * 2.0);
      
      if(!tick_val_valid)
      {
         tick_val = expected_tick_val;
         Print("[PositionSizer] tick_val invalid (original=", SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), 
               "), using expected tick_val=", tick_val);
      }

      if(tick_sz <= 0.0)
      {
         Print("[PositionSizer] Invalid tick_sz=", tick_sz);
         return 0.0;
      }

      // 计算手数
      double dist   = MathAbs(price - sl);   // 价格距离（如10美元）
      double points = dist / tick_sz;        // 换算成tick数（如1000点）
      double loss_per_1lot = points * tick_val;  // 每1手最大亏损

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
