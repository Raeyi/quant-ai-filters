//+------------------------------------------------------------------+
//|                          Core/Strategy.mqh                       |
//|                   Strategy interface definition                  |
//+                    Strategy 的唯一职责 = 产生信号                  +
//+------------------------------------------------------------------+

#ifndef __STRATEGY_MQH__
#define __STRATEGY_MQH__

#include "Signal.mqh"
#include "Regime/RegimeFilter.mqh"  // M6.3: 直接 include 以支持指针成员访问

class IStrategy
{
protected:
    // Regime 过滤器指针（由 EA 层注入）
    CRegimeFilter* m_regime_filter;
    
public:
    // 构造函数
    IStrategy() : m_regime_filter(NULL) {}
    
    // 析构函数
    virtual ~IStrategy() {}
    
    // 每个 tick 是否产生信号
    virtual Signal GenerateSignal(Signal &outSignal) = 0;

    // 策略名称（用于日志 / AI / 投票）
    virtual string Name() = 0;
    
    // ===== 可选方法（子类可覆盖） =====
    
    // 初始化（默认空实现）
    virtual bool Init() { return true; }
    
    // 更新指标（默认空实现）
    virtual bool UpdateIndicators() { return true; }
    
    // 时间过滤检查（默认通过）
    virtual bool TimeFilterOK() { return true; }
    
    // ===== M6.3: Regime 集成接口 =====
    
    // 设置 Regime 过滤器（由 EA 层调用）
    virtual void SetRegimeFilter(CRegimeFilter* filter) { m_regime_filter = filter; }
    
    // 获取 Regime 过滤器
    CRegimeFilter* GetRegimeFilter() const { return m_regime_filter; }
};

#endif
