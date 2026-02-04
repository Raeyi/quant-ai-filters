//+------------------------------------------------------------------+
//|                          Core/StrategyManager.mqh                |
//+------------------------------------------------------------------+
#ifndef __STRATEGY_MANAGER_MQH__
#define __STRATEGY_MANAGER_MQH__

#include "Strategy.mqh"

#define MAX_STRATEGIES 8

class StrategyManager
{
private:
   IStrategy* strategies[MAX_STRATEGIES];
   int        count;

public:
   StrategyManager() : count(0)
   {
      // ArrayInitialize 对类指针数组用处不大，可以不调
      // ArrayInitialize(strategies, NULL);
   }

   void Add(IStrategy* strategy)
   {
      if(strategy == NULL)
         return;

      if(count >= MAX_STRATEGIES)
      {
         Print("[StrategyManager] Max strategy count reached: ", MAX_STRATEGIES);
         return;
      }

      strategies[count++] = strategy;
   }

   Signal StrategyManager::GetSignal()
   {
      // Print("[StrategyManager] GetSignal called. count=", count);
      for(int i = 0; i < count; i++)
      {
         if(strategies[i] == NULL)
            continue;
         
         Signal sig;
         sig = strategies[i].GenerateSignal(sig);
         
          if(sig.type != SIGNAL_NONE)
         {
               Print("[StrategyManager] Signal from strategy ", sig.source,
                     " type=", sig.type);
               return sig;
         }
      }
      return Signal(); // NONE
   }
};

#endif // __STRATEGY_MANAGER_MQH__
