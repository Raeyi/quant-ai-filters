//+------------------------------------------------------------------+
//|                      Core/ConfidenceFilter.mqh                   |
//|    简单示例：按 signal.confidence 阈值过滤                        |
//+------------------------------------------------------------------+
#ifndef __CONFIDENCE_FILTER_MQH__
#define __CONFIDENCE_FILTER_MQH__

#include "IAIFilter.mqh"

input double MIN_CONFIDENCE = 0.5; // 全局参数：AI/策略信心阈值

class ConfidenceFilter : public IAIFilter
{
public:
   virtual bool Filter(const Signal &in, double &score) override
   {
      score = in.confidence;

      if(in.confidence < MIN_CONFIDENCE)
      {
         Print("[ConfidenceFilter] Reject signal from ", in.source,
               ", confidence=", DoubleToString(in.confidence,2));
         return false;
      }

      return true;
   }

   virtual string Name() override
   {
      return "ConfidenceFilter";
   }
};

#endif // __CONFIDENCE_FILTER_MQH__
