//+------------------------------------------------------------------+
//|                          Core/IAIFilter.mqh                      |
//|    AI Filter 接口：任何 AI/ML/RL 过滤器，只要实现 Filter 即可        |
//+------------------------------------------------------------------+
#ifndef __IAI_FILTER_MQH__
#define __IAI_FILTER_MQH__

#include "Signal.mqh"

class IAIFilter
{
public:
   virtual ~IAIFilter() {}

   // 返回 true = 信号通过；false = 拒绝
   // score：可以返回一个 0~1 的打分（以后用来排序/加权）
   virtual bool Filter(const Signal &in, double &score) = 0;

   virtual string Name() = 0;
};

#endif // __IAI_FILTER_MQH__
