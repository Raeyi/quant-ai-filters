//+------------------------------------------------------------------+
//|                   Core/StrategyRegistry.mqh                       |
//|                   策略注册表 - 统一管理策略生命周期                   |
//+------------------------------------------------------------------+
#ifndef __STRATEGY_REGISTRY_MQH__
#define __STRATEGY_REGISTRY_MQH__

#include "Strategy.mqh"

// 前向声明
class CRegimeFilter;

// 最大策略数量
#define MAX_REGISTRY_STRATEGIES 16

//+------------------------------------------------------------------+
//| 策略配置结构体                                                      |
//+------------------------------------------------------------------+
struct StrategyConfig
{
    string      name;           // 策略名称标识
    IStrategy*  strategy;       // 策略实例
    bool        is_combo_child; // 是否为组合策略子项
    
    StrategyConfig()
    {
        name = "";
        strategy = NULL;
        is_combo_child = false;
    }
};

//+------------------------------------------------------------------+
//| 策略注册表类                                                        |
//+------------------------------------------------------------------+
class StrategyRegistry
{
private:
    StrategyConfig m_configs[MAX_REGISTRY_STRATEGIES];
    int            m_count;
    IStrategy*     m_primary;           // 主策略（当前激活）
    IStrategy*     m_combo;             // 组合策略实例
    string         m_selected_variant;  // 当前选择的策略变体
    
    //+--------------------------------------------------------------
    //| 查找策略配置
    //+--------------------------------------------------------------
    int FindConfig(const string name) const
    {
        for(int i = 0; i < m_count; i++)
        {
            if(m_configs[i].name == name)
                return i;
        }
        return -1;
    }
    
    //+--------------------------------------------------------------
    //| 检查策略是否有特定接口方法（通过类型转换）
    //| 注意：MQL5 接口不支持虚方法检测，需要策略类实现
    //+--------------------------------------------------------------
    
public:
    //+--------------------------------------------------------------
    //| 构造函数
    //+--------------------------------------------------------------
    StrategyRegistry() : m_count(0), m_primary(NULL), m_combo(NULL)
    {
        for(int i = 0; i < MAX_REGISTRY_STRATEGIES; i++)
        {
            m_configs[i] = StrategyConfig();
        }
    }
    
    //+--------------------------------------------------------------
    //| 注册策略
    //| @param name 策略名称标识（用于选择）
    //| @param strategy 策略实例
    //| @param isComboChild 是否为组合策略子项
    //+--------------------------------------------------------------
    bool Register(const string name, IStrategy* strategy, bool isComboChild = false)
    {
        if(strategy == NULL)
        {
            Print("[StrategyRegistry] Cannot register NULL strategy");
            return false;
        }
        
        if(m_count >= MAX_REGISTRY_STRATEGIES)
        {
            Print("[StrategyRegistry] Max strategy count reached");
            return false;
        }
        
        // 检查是否已注册
        if(FindConfig(name) >= 0)
        {
            Print("[StrategyRegistry] Strategy already registered: ", name);
            return false;
        }
        
        m_configs[m_count].name = name;
        m_configs[m_count].strategy = strategy;
        m_configs[m_count].is_combo_child = isComboChild;
        m_count++;
        
        Print("[StrategyRegistry] Registered: ", name, " (", m_count, "/", MAX_REGISTRY_STRATEGIES, ")");
        return true;
    }
    
    //+--------------------------------------------------------------
    //| 注册组合策略
    //| @param combo 组合策略实例
    //| @param name 组合策略名称标识
    //+--------------------------------------------------------------
    bool RegisterCombo(IStrategy* pcombo, const string name = "combo")
    {
        if(pcombo == NULL)
            return false;
        m_combo = pcombo;
        return Register(name, pcombo, false);
    }
    
    //+--------------------------------------------------------------
    //| 选择策略变体
    //| @param variant 策略变体名称
    //+--------------------------------------------------------------
    bool Select(const string variant)
    {
        m_selected_variant = variant;
        StringToLower(m_selected_variant);
        
        int idx = FindConfig(m_selected_variant);
        if(idx >= 0)
        {
            m_primary = m_configs[idx].strategy;
            Print("[StrategyRegistry] Selected strategy: ", m_selected_variant);
            return true;
        }
        
        // 未找到，尝试默认策略
        Print("[StrategyRegistry] Variant '", variant, "' not found, using default");
        return false;
    }
    
    //+--------------------------------------------------------------
    //| 初始化当前策略
    //+--------------------------------------------------------------
    bool Init()
    {
        if(m_primary == NULL)
        {
            Print("[StrategyRegistry] No strategy selected");
            return false;
        }
        
        // 如果是组合策略，需要初始化所有子策略
        if(m_selected_variant == "combo")
        {
            for(int i = 0; i < m_count; i++)
            {
                if(m_configs[i].is_combo_child && m_configs[i].strategy != NULL)
                {
                    if(!m_configs[i].strategy.Init())
                    {
                        Print("[StrategyRegistry] Failed to init child: ", m_configs[i].name);
                        return false;
                    }
                }
            }
        }
        
        // 初始化主策略
        if(!m_primary.Init())
        {
            Print("[StrategyRegistry] Failed to init primary strategy");
            return false;
        }
        
        return true;
    }
    
    //+--------------------------------------------------------------
    //| 更新指标（根据当前策略类型）
    //| @return 是否成功
    //+--------------------------------------------------------------
    bool UpdateIndicators()
    {
        if(m_primary == NULL)
            return false;
        
        if(m_selected_variant == "combo")
        {
            // 组合策略：更新所有子策略指标
            for(int i = 0; i < m_count; i++)
            {
                if(m_configs[i].is_combo_child && m_configs[i].strategy != NULL)
                {
                    if(!m_configs[i].strategy.UpdateIndicators())
                        return false;
                }
            }
            return true;
        }
        
        // 单策略模式
        return m_primary.UpdateIndicators();
    }
    
    //+--------------------------------------------------------------
    //| 时间过滤检查
    //+--------------------------------------------------------------
    bool TimeFilterOK()
    {
        if(m_selected_variant == "combo")
        {
            // combo 模式：任一策略时间过滤通过即可
            for(int i = 0; i < m_count; i++)
            {
                if(m_configs[i].is_combo_child && m_configs[i].strategy != NULL)
                {
                    if(m_configs[i].strategy.TimeFilterOK())
                        return true;
                }
            }
            return false;
        }
        
        return m_primary.TimeFilterOK();
    }
    
    //+--------------------------------------------------------------
    //| 获取当前策略
    //+--------------------------------------------------------------
    IStrategy* GetPrimary() const { return m_primary; }
    
    //+--------------------------------------------------------------
    //| 获取当前变体名称
    //+--------------------------------------------------------------
    string GetVariant() const { return m_selected_variant; }
    
    //+--------------------------------------------------------------
    //| 是否为组合模式
    //+--------------------------------------------------------------
    bool IsComboMode() const { return m_selected_variant == "combo"; }
    
    //+--------------------------------------------------------------
    //| 获取策略数量
    //+--------------------------------------------------------------
    int Count() const { return m_count; }
    
    //+--------------------------------------------------------------
    //| 获取指定名称的策略
    //+--------------------------------------------------------------
    IStrategy* GetStrategy(const string name) const
    {
        int idx = FindConfig(name);
        if(idx >= 0)
            return m_configs[idx].strategy;
        return NULL;
    }
    
    //+--------------------------------------------------------------
    //| 获取指定索引的配置
    //+--------------------------------------------------------------
    bool GetConfig(int index, StrategyConfig &config) const
    {
        if(index < 0 || index >= m_count)
            return false;
        config = m_configs[index];
        return true;
    }
    
    //+--------------------------------------------------------------
    //| M6.3: 为所有策略设置 RegimeFilter（消除策略层趋势判断）
    //+--------------------------------------------------------------
    void SetRegimeFilterForAll(CRegimeFilter* filter)
    {
        for(int i = 0; i < m_count; i++)
        {
            if(m_configs[i].strategy != NULL)
            {
                m_configs[i].strategy.SetRegimeFilter(filter);
            }
        }
        Print("[StrategyRegistry] RegimeFilter injected to all strategies");
    }
};

#endif // __STRATEGY_REGISTRY_MQH__
