//+------------------------------------------------------------------+
//|              Strategies/Strategy_Combo.mqh                       |
//|                组合策略 - 多策略信号整合                           |
//|     M1 (BollMR) + M2 (TrendPullback) 组合运行                     |
//|                                                                   |
//|     设计原则：                                                    |
//|     1. 各策略独立运行，自带过滤条件（时间、指标等）                  |
//|     2. 组合逻辑只处理信号整合，不干预策略内部逻辑                   |
//|     3. 时段分离时各策略独立执行，冲突时按规则处理                   |
//+------------------------------------------------------------------+

#ifndef __STRATEGY_COMBO_MQH__
#define __STRATEGY_COMBO_MQH__

#include "../Core/Strategy.mqh"
#include "../Core/Inputs_All.mqh"
#include "Strategy_BollMR_enhanced.mqh"
#include "Strategy_TrendPullback.mqh"

//+------------------------------------------------------------------+
//| 组合模式枚举                                                       |
//+------------------------------------------------------------------+
enum ComboMode
{
    COMBO_FIRST_SIGNAL   = 0,   // 先到先得（非冲突时）
    COMBO_SAME_DIRECTION = 1,   // 同向叠加：两策略同向才交易
    COMBO_PRIORITY_BOLL  = 2,   // 优先级：BollMR 优先
    COMBO_PRIORITY_TP    = 3,   // 优先级：TrendPullback 优先
    COMBO_CONFLICT_SKIP  = 4,   // 冲突跳过：反向信号时跳过
};

//+------------------------------------------------------------------+
//| 组合策略输入参数                                                   |
//+------------------------------------------------------------------+
input group "========== 组合策略设置 =========="
input ComboMode ComboModeSelect = COMBO_CONFLICT_SKIP;  // 组合模式
input double    ComboConfidenceBoost = 0.3;             // 同向信号置信度加成
input bool      ComboLogSignals = true;                 // 记录组合信号日志

//+------------------------------------------------------------------+
//| 组合策略类                                                         |
//+------------------------------------------------------------------+
class Strategy_Combo : public IStrategy
{
private:
    Strategy_BollMR     m_boll;           // M1: BollMR 策略
    Strategy_TrendPullback m_tp;          // M2: TrendPullback 策略
    
    bool     m_initialized;
    
    // 统计
    int      m_stat_boll_only;     // 只有 BollMR 信号次数
    int      m_stat_tp_only;       // 只有 TP 信号次数
    int      m_stat_same_dir;      // 同向信号次数
    int      m_stat_conflict;      // 冲突信号次数
    int      m_stat_conflict_resolved;  // 冲突解决次数
    
public:
    //+--------------------------------------------------------------
    //| 构造函数
    //+--------------------------------------------------------------
    Strategy_Combo() : 
        m_initialized(false),
        m_stat_boll_only(0),
        m_stat_tp_only(0),
        m_stat_same_dir(0),
        m_stat_conflict(0),
        m_stat_conflict_resolved(0)
    {
    }
    
    //+--------------------------------------------------------------
    //| 初始化
    //+--------------------------------------------------------------
    bool Init()
    {
        // 初始化 BollMR
        if(!m_boll.Init())
        {
            Print("[Strategy_Combo] Failed to initialize BollMR strategy");
            return false;
        }
        
        // 初始化 TrendPullback
        if(!m_tp.Init())
        {
            Print("[Strategy_Combo] Failed to initialize TrendPullback strategy");
            return false;
        }
        
        m_initialized = true;
        Print("[Strategy_Combo] Initialized. Mode=", EnumToString(ComboModeSelect));
        return true;
    }
    
    //+--------------------------------------------------------------
    //| 策略名称
    //+--------------------------------------------------------------
    virtual string Name() override
    {
        return "Combo";
    }
    
    //+--------------------------------------------------------------
    //| 生成信号
    //+--------------------------------------------------------------
    virtual Signal GenerateSignal(Signal &outSignal) override
    {
        if(!m_initialized)
        {
            outSignal.type = SIGNAL_NONE;
            return outSignal;
        }
        
        // 1. 分别调用两个策略（各自内部有完整过滤逻辑）
        Signal sig_boll, sig_tp;
        m_boll.GenerateSignal(sig_boll);
        m_tp.GenerateSignal(sig_tp);
        
        // 2. 组合决策
        Signal result;
        result.type = SIGNAL_NONE;
        result.confidence = 0.0;
        result.source = "combo";
        result.time = TimeCurrent();
        
        bool boll_has_signal = (sig_boll.type != SIGNAL_NONE);
        bool tp_has_signal = (sig_tp.type != SIGNAL_NONE);
        
        // 场景1: 都无信号
        if(!boll_has_signal && !tp_has_signal)
        {
            outSignal = result;
            return outSignal;
        }
        
        // 场景2: 只有 BollMR 有信号
        if(boll_has_signal && !tp_has_signal)
        {
            m_stat_boll_only++;
            result = sig_boll;
            result.source = "combo_boll_only";
            outSignal = result;
            return outSignal;
        }
        
        // 场景3: 只有 TrendPullback 有信号
        if(!boll_has_signal && tp_has_signal)
        {
            m_stat_tp_only++;
            result = sig_tp;
            result.source = "combo_tp_only";
            outSignal = result;
            return outSignal;
        }
        
        // 场景4: 两策略都有信号
        m_stat_same_dir++;
        
        bool same_direction = false;
        
        // 判断方向是否一致
        if(sig_boll.IsLongSignal() && sig_tp.IsLongSignal())
            same_direction = true;
        else if(sig_boll.IsShortSignal() && sig_tp.IsShortSignal())
            same_direction = true;
        
        if(same_direction)
        {
            // 同向 → 放大置信度
            result = sig_boll;
            result.confidence = MathMin(sig_boll.confidence + sig_tp.confidence * ComboConfidenceBoost, 1.0);
            result.source = "combo_same_dir";
            
            if(ComboLogSignals)
            {
                Print("[Strategy_Combo] Same direction signal: ", 
                      sig_boll.IsLongSignal() ? "LONG" : "SHORT",
                      " boll_conf=", DoubleToString(sig_boll.confidence, 2),
                      " tp_conf=", DoubleToString(sig_tp.confidence, 2),
                      " combined=", DoubleToString(result.confidence, 2));
            }
        }
        else
        {
            // 反向 → 冲突处理
            m_stat_conflict++;
            
            switch(ComboModeSelect)
            {
                case COMBO_FIRST_SIGNAL:
                    // 先到先得（这里按顺序选 BollMR）
                    result = sig_boll;
                    result.source = "combo_conflict_first";
                    m_stat_conflict_resolved++;
                    break;
                    
                case COMBO_PRIORITY_BOLL:
                    // BollMR 优先
                    result = sig_boll;
                    result.source = "combo_conflict_boll";
                    m_stat_conflict_resolved++;
                    break;
                    
                case COMBO_PRIORITY_TP:
                    // TrendPullback 优先
                    result = sig_tp;
                    result.source = "combo_conflict_tp";
                    m_stat_conflict_resolved++;
                    break;
                    
                case COMBO_CONFLICT_SKIP:
                default:
                    // 冲突时跳过
                    result.type = SIGNAL_NONE;
                    result.source = "combo_conflict_skip";
                    if(ComboLogSignals)
                    {
                        Print("[Strategy_Combo] Conflict detected, skipping. ",
                              "boll=", (sig_boll.IsLongSignal() ? "LONG" : "SHORT"),
                              " tp=", (sig_tp.IsLongSignal() ? "LONG" : "SHORT"));
                    }
                    break;
            }
        }
        
        outSignal = result;
        return outSignal;
    }
    
    //+--------------------------------------------------------------
    //| 新K线通知（转发给子策略）
    //+--------------------------------------------------------------
    void OnNewBar()
    {
        m_boll.OnNewBar();
        m_tp.OnNewBar();
    }
    
    //+--------------------------------------------------------------
    //| 时间过滤检查（转发给子策略）
    //+--------------------------------------------------------------
    bool TimeFilterOK()
    {
        // 任一策略时间过滤通过即可
        return m_boll.TimeFilterOK() || m_tp.TimeFilterOK();
    }
    
    //+--------------------------------------------------------------
    //| 获取统计信息
    //+--------------------------------------------------------------
    string GetStats() const
    {
        return StringFormat("BollMR:%d TP:%d SameDir:%d Conflict:%d Resolved:%d",
                           m_stat_boll_only, m_stat_tp_only, 
                           m_stat_same_dir, m_stat_conflict, m_stat_conflict_resolved);
    }
    
    //+--------------------------------------------------------------
    //| 获取 BollMR 策略引用（用于面板更新等）
    //+--------------------------------------------------------------
    Strategy_BollMR& GetBollMR() { return m_boll; }
    
    //+--------------------------------------------------------------
    //| 获取 TrendPullback 策略引用
    //+--------------------------------------------------------------
    Strategy_TrendPullback& GetTrendPullback() { return m_tp; }
    
    //+--------------------------------------------------------------
    //| 更新指标数据（转发给子策略）
    //+--------------------------------------------------------------
    bool UpdateIndicators()
    {
        bool boll_ok = m_boll.UpdateIndicators();
        bool tp_ok = m_tp.UpdateIndicators();
        return boll_ok && tp_ok;
    }
};

#endif // __STRATEGY_COMBO_MQH__
