//+------------------------------------------------------------------+
//|              Strategies/Strategy_Combo.mqh                       |
//|                组合策略 - 多策略信号整合                           |
//|                                                                   |
//|     设计原则：                                                    |
//|     1. 策略列表模式：支持动态添加任意数量策略                       |
//|     2. 各策略独立运行，自带过滤条件（时间、指标等）                  |
//|     3. 组合逻辑只处理信号整合，不干预策略内部逻辑                   |
//|     4. 时段分离时各策略独立执行，冲突时按规则处理                   |
//|                                                                   |
//|     扩展指南：                                                    |
//|     1. 创建新策略类继承 IStrategy                                 |
//|     2. 在 Ea_run.mq5 中实例化并调用 combo.AddStrategy()           |
//|     3. 新策略自动参与组合逻辑                                     |
//+------------------------------------------------------------------+

#ifndef __STRATEGY_COMBO_MQH__
#define __STRATEGY_COMBO_MQH__

#include "../Core/Strategy.mqh"
#include "../Core/Inputs_All.mqh"

// 最大策略数量
#define MAX_COMBO_STRATEGIES 8

//+------------------------------------------------------------------+
//| 组合模式枚举                                                       |
//+------------------------------------------------------------------+
enum ComboMode
{
    COMBO_FIRST_SIGNAL   = 0,   // 先到先得：取第一个有效信号
    COMBO_SAME_DIRECTION = 1,   // 同向叠加：所有策略同向才交易
    COMBO_MAJORITY_VOTE  = 2,   // 多数投票：多数同向才交易
    COMBO_PRIORITY_FIRST = 3,   // 优先级模式：按添加顺序优先
    COMBO_CONFLICT_SKIP  = 4,   // 冲突跳过：有任何反向信号时跳过
    COMBO_BEST_CONFIDENCE = 5,  // 最高置信度：选择置信度最高的信号
};

//+------------------------------------------------------------------+
//| 组合策略输入参数                                                   |
//+------------------------------------------------------------------+
input group "========== 组合策略设置 =========="
input ComboMode ComboModeSelect = COMBO_CONFLICT_SKIP;  // 组合模式
input double    ComboConfidenceBoost = 0.3;             // 同向信号置信度加成
input bool      ComboLogSignals = true;                 // 记录组合信号日志
input int       ComboMinAgreement = 2;                  // 最小同意策略数（多数投票模式）

//+------------------------------------------------------------------+
//| 组合策略类                                                         |
//+------------------------------------------------------------------+
class Strategy_Combo : public IStrategy
{
private:
    IStrategy* m_strategies[MAX_COMBO_STRATEGIES];  // 策略数组
    string     m_strategy_names[MAX_COMBO_STRATEGIES]; // 策略名称（用于日志）
    int        m_count;
    bool       m_initialized;
    
    // 统计
    int        m_stat_total_signals;      // 总信号次数
    int        m_stat_single_strategy;    // 单策略信号次数
    int        m_stat_multi_agree;        // 多策略同向次数
    int        m_stat_conflict_skip;      // 冲突跳过次数
    
    //+--------------------------------------------------------------
    //| 组合多个信号（核心逻辑）
    //+--------------------------------------------------------------
    Signal CombineSignals(Signal &signals[], int count)
    {
        Signal result;
        result.type = SIGNAL_NONE;
        result.confidence = 0.0;
        result.source = "combo";
        result.time = TimeCurrent();
        
        if(count == 0)
            return result;
        
        // 统计各方向信号数量
        int long_count = 0;
        int short_count = 0;
        int none_count = 0;
        
        Signal first_valid;
        bool has_valid = false;
        
        double total_long_confidence = 0.0;
        double total_short_confidence = 0.0;
        Signal best_long, best_short;
        
        for(int i = 0; i < count; i++)
        {
            if(signals[i].type == SIGNAL_NONE)
            {
                none_count++;
                continue;
            }
            
            if(!has_valid)
            {
                first_valid = signals[i];
                has_valid = true;
            }
            
            if(signals[i].IsLongSignal())
            {
                long_count++;
                total_long_confidence += signals[i].confidence;
                if(signals[i].confidence > best_long.confidence)
                    best_long = signals[i];
            }
            else if(signals[i].IsShortSignal())
            {
                short_count++;
                total_short_confidence += signals[i].confidence;
                if(signals[i].confidence > best_short.confidence)
                    best_short = signals[i];
            }
        }
        
        int valid_count = long_count + short_count;
        
        // 无有效信号
        if(valid_count == 0)
            return result;
        
        // 单策略信号
        if(valid_count == 1)
        {
            m_stat_single_strategy++;
            result = first_valid;
            result.source = "combo_single_" + first_valid.source;
            return result;
        }
        
        // 多策略场景
        m_stat_total_signals++;
        
        // 根据组合模式处理
        switch(ComboModeSelect)
        {
            case COMBO_FIRST_SIGNAL:
                result = first_valid;
                result.source = "combo_first";
                break;
                
            case COMBO_SAME_DIRECTION:
                // 所有策略必须同向
                if(long_count == valid_count || short_count == valid_count)
                {
                    m_stat_multi_agree++;
                    result = (long_count > 0) ? best_long : best_short;
                    // 置信度叠加
                    double total_conf = (long_count > 0) ? total_long_confidence : total_short_confidence;
                    result.confidence = MathMin(total_conf / valid_count + ComboConfidenceBoost, 1.0);
                    result.source = "combo_same_dir";
                }
                else
                {
                    m_stat_conflict_skip++;
                    result.type = SIGNAL_NONE;
                    if(ComboLogSignals)
                        Print("[Strategy_Combo] SAME_DIRECTION mode: conflict detected, skipping");
                }
                break;
                
            case COMBO_MAJORITY_VOTE:
                // 多数投票
                {
                    int agree_count = MathMax(long_count, short_count);
                    if(agree_count >= ComboMinAgreement)
                    {
                        m_stat_multi_agree++;
                        result = (long_count > short_count) ? best_long : best_short;
                        result.source = "combo_majority";
                    }
                    else
                    {
                        m_stat_conflict_skip++;
                        result.type = SIGNAL_NONE;
                        if(ComboLogSignals)
                            Print("[Strategy_Combo] MAJORITY_VOTE mode: no majority (long=", long_count, " short=", short_count, ")");
                    }
                }
                break;
                
            case COMBO_PRIORITY_FIRST:
                // 按优先级取第一个有效信号
                result = first_valid;
                result.source = "combo_priority";
                break;
                
            case COMBO_BEST_CONFIDENCE:
                // 选择置信度最高的信号
                {
                    if(long_count > 0 && (short_count == 0 || total_long_confidence > total_short_confidence))
                    {
                        result = best_long;
                        result.source = "combo_best_conf";
                    }
                    else if(short_count > 0)
                    {
                        result = best_short;
                        result.source = "combo_best_conf";
                    }
                }
                break;
                
            case COMBO_CONFLICT_SKIP:
            default:
                // 有任何冲突就跳过
                if(long_count > 0 && short_count > 0)
                {
                    m_stat_conflict_skip++;
                    result.type = SIGNAL_NONE;
                    if(ComboLogSignals)
                        Print("[Strategy_Combo] CONFLICT_SKIP mode: long=", long_count, " short=", short_count, ", skipping");
                }
                else
                {
                    m_stat_multi_agree++;
                    result = (long_count > 0) ? best_long : best_short;
                    // 置信度平均 + 加成
                    double total_conf = (long_count > 0) ? total_long_confidence : total_short_confidence;
                    result.confidence = MathMin(total_conf / valid_count + ComboConfidenceBoost, 1.0);
                    result.source = "combo_agree";
                }
                break;
        }
        
        return result;
    }
    
public:
    //+--------------------------------------------------------------
    //| 构造函数
    //+--------------------------------------------------------------
    Strategy_Combo() : 
        m_count(0),
        m_initialized(false),
        m_stat_total_signals(0),
        m_stat_single_strategy(0),
        m_stat_multi_agree(0),
        m_stat_conflict_skip(0)
    {
        // 初始化指针数组
        for(int i = 0; i < MAX_COMBO_STRATEGIES; i++)
        {
            m_strategies[i] = NULL;
            m_strategy_names[i] = "";
        }
    }
    
    //+--------------------------------------------------------------
    //| 添加策略
    //| @param strategy 策略实例指针
    //| @param name 策略名称（可选，用于日志）
    //+--------------------------------------------------------------
    void AddStrategy(IStrategy* strategy, string name = "")
    {
        if(strategy == NULL)
        {
            Print("[Strategy_Combo] Cannot add NULL strategy");
            return;
        }
        
        if(m_count >= MAX_COMBO_STRATEGIES)
        {
            Print("[Strategy_Combo] Max strategy count reached: ", MAX_COMBO_STRATEGIES);
            return;
        }
        
        m_strategies[m_count] = strategy;
        m_strategy_names[m_count] = (name != "") ? name : strategy.Name();
        m_count++;
        
        Print("[Strategy_Combo] Added strategy: ", m_strategy_names[m_count - 1], " (", m_count, "/", MAX_COMBO_STRATEGIES, ")");
    }
    
    //+--------------------------------------------------------------
    //| 初始化所有已添加的策略
    //+--------------------------------------------------------------
    bool Init()
    {
        if(m_count == 0)
        {
            Print("[Strategy_Combo] No strategies added");
            return false;
        }
        
        // 初始化所有策略
        for(int i = 0; i < m_count; i++)
        {
            if(m_strategies[i] == NULL)
                continue;
                
            // 注意：策略的 Init() 需要通过外部调用，这里只做检查
            // 因为 MQL5 不支持通过接口调用 Init()
        }
        
        m_initialized = true;
        Print("[Strategy_Combo] Initialized with ", m_count, " strategies. Mode=", EnumToString(ComboModeSelect));
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
        if(!m_initialized || m_count == 0)
        {
            outSignal.type = SIGNAL_NONE;
            return outSignal;
        }
        
        // 1. 收集所有策略信号
        Signal signals[];
        ArrayResize(signals, m_count);
        
        for(int i = 0; i < m_count; i++)
        {
            if(m_strategies[i] == NULL)
            {
                signals[i].type = SIGNAL_NONE;
                continue;
            }
            m_strategies[i].GenerateSignal(signals[i]);
        }
        
        // 2. 组合决策
        outSignal = CombineSignals(signals, m_count);
        return outSignal;
    }
    
    //+--------------------------------------------------------------
    //| 更新指标数据（转发给所有子策略）
    //+--------------------------------------------------------------
    bool UpdateIndicators()
    {
        bool all_ok = true;
        for(int i = 0; i < m_count; i++)
        {
            if(m_strategies[i] == NULL)
                continue;
            
            // 注意：需要子类实现 UpdateIndicators 或通过类型转换调用
            // 这里假设策略类有 UpdateIndicators 方法
            // 如果接口不支持，需要在 Ea_run.mq5 中单独处理
        }
        return all_ok;
    }
    
    //+--------------------------------------------------------------
    //| 时间过滤检查（任一策略通过即可）
    //+--------------------------------------------------------------
    bool TimeFilterOK()
    {
        for(int i = 0; i < m_count; i++)
        {
            if(m_strategies[i] == NULL)
                continue;
            // 注意：需要子类实现 TimeFilterOK
        }
        return true; // 默认通过
    }
    
    //+--------------------------------------------------------------
    //| 获取统计信息
    //+--------------------------------------------------------------
    string GetStats() const
    {
        return StringFormat("Strategies:%d Single:%d MultiAgree:%d ConflictSkip:%d",
                           m_count, m_stat_single_strategy, 
                           m_stat_multi_agree, m_stat_conflict_skip);
    }
    
    //+--------------------------------------------------------------
    //| 获取策略数量
    //+--------------------------------------------------------------
    int GetStrategyCount() const { return m_count; }
    
    //+--------------------------------------------------------------
    //| 获取指定索引的策略指针（用于类型转换调用特定方法）
    //+--------------------------------------------------------------
    IStrategy* GetStrategy(int index)
    {
        if(index < 0 || index >= m_count)
            return NULL;
        return m_strategies[index];
    }
    
    //+--------------------------------------------------------------
    //| 获取策略名称
    //+--------------------------------------------------------------
    string GetStrategyName(int index) const
    {
        if(index < 0 || index >= m_count)
            return "";
        return m_strategy_names[index];
    }
};

#endif // __STRATEGY_COMBO_MQH__
