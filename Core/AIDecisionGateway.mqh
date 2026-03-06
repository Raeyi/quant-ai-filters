//+------------------------------------------------------------------+
//|                       Core/AIDecisionGateway.mqh                 |
//+------------------------------------------------------------------+
#ifndef __AI_DECISION_GATEWAY_MQH__
#define __AI_DECISION_GATEWAY_MQH__

#include "IAIFilter.mqh"

#define MAX_FILTERS 8

class AIDecisionGateway
{
private:
   IAIFilter* filters[MAX_FILTERS];
   int        count;

public:
   AIDecisionGateway() : count(0)
   {
      // 同上，可以不强制初始化指针数组
   }

   void AddFilter(IAIFilter* filter)
   {
      if(filter == NULL)
         return;
      if(count >= MAX_FILTERS)
      {
         Print("[AIDecisionGateway] Max filter count reached: ", MAX_FILTERS);
         return;
      }
      filters[count++] = filter;
   }

   bool Pass(const Signal &in, double &final_score)
   {
      final_score = 1.0;

      for(int i = 0; i < count; i++)
      {
         if(filters[i] == NULL)
            continue;

         double score = 1.0;
         // 这里用 '.' 调用
         if(!filters[i].Filter(in, score))
         {
            Print("[AIDecisionGateway] Filter ", filters[i].Name(),
                  " rejected signal from ", in.source);
            return false;
         }

         if(score < final_score)
            final_score = score;
      }

      return true;
   }

   void PrintState(Signal &signal) const
    {
      Print("[EA] AIDecisionGateway rejected signal from ", signal.source);
    }
};

#endif // __AI_DECISION_GATEWAY_MQH__
