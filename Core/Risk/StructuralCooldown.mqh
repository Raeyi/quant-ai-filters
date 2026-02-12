//+------------------------------------------------------------------+
//|                Core/Risk/StructuralCooldown.mqh                   |
//|           结构冷却器：防止假突破反复收割的反洗机制                    |
//|     唯一使命：阻止同一结构被假突破反复收割                           |
//+------------------------------------------------------------------+

#ifndef __STRUCTURAL_COOLDOWN_MQH__
#define __STRUCTURAL_COOLDOWN_MQH__

#property strict

//+------------------------------------------------------------------+
//| 冷却器状态枚举                                                     |
//+------------------------------------------------------------------+
enum StructuralCooldownState
{
    SC_STATE_IDLE = 0,       // 空闲，可交易
    SC_STATE_COOLDOWN = 1    // 冷却中，禁止入场
};

//+------------------------------------------------------------------+
//| 冷却触发原因                                                       |
//+------------------------------------------------------------------+
enum StructuralCooldownReason
{
    SC_REASON_NONE = 0,
    SC_REASON_FAST_STOP,     // 快速止损（N根K线内被止损）
    SC_REASON_NO_MOMENTUM,   // 无动量（未达+0.5 ATR就反向）
    SC_REASON_DOUBLE_FAIL    // 连续2次Probe失败
};

//+------------------------------------------------------------------+
//| 结构冷却器类                                                       |
//| 核心思想：市场骗过你一次，在给出更高质量证据前不再相信                |
//+------------------------------------------------------------------+
class CStructuralCooldown
{
private:
    StructuralCooldownState m_state;
    StructuralCooldownReason m_reason;
    
    // 时间条件
    datetime m_cooldown_start_time;   // 冷却开始时间
    int m_cooldown_bars_elapsed;      // 已经过的K线数
    int m_cooldown_bars_required;     // 需要的K线数
    
    // 结构条件（用于解除判断）
    double m_failed_price;            // 假突破时的价格
    double m_failed_structure_price;  // 假突破时的结构点价格
    double m_failed_atr;              // 假突破时的ATR
    bool   m_is_long;                 // 假突破方向（true=多头假突破）
    
    // 入场追踪（用于检测快速失败）
    datetime m_entry_time;            // 入场时间
    double m_entry_price;             // 入场价格
    double m_entry_atr;               // 入场时ATR
    bool   m_has_entry;               // 是否有入场记录
    int    m_entry_bars;              // 入场后的K线计数
    
    // Probe失败追踪
    int    m_probe_fail_count;        // Probe失败计数
    int    m_probe_fail_dir;          // 失败方向 (1=多, -1=空)
    datetime m_last_probe_time;       // 上次Probe失败时间
    
    // 二次确认状态
    bool   m_second_chance_ready;     // 是否准备好二次确认
    double m_last_pullback_depth;     // 上次回撤深度（ATR倍数）
    
    // 参数
    int    m_param_fast_fail_bars;       // 快速失败判定K线数
    double m_param_min_momentum_atr;     // 最小动量要求（ATR倍数）
    int    m_param_cooldown_bars;        // 冷却K线数
    double m_param_structure_upgrade_atr;// 结构升级判定（ATR倍数）
    int    m_param_max_probe_fails;      // 最大连续Probe失败次数
    int    m_param_max_cooldown_bars;    // 最大冷却K线数（强制解除）
    
public:
    //+--------------------------------------------------------------
    //| 构造函数
    //+--------------------------------------------------------------
    CStructuralCooldown()
    {
        // 默认参数（M5/XAUUSD优化）
        m_param_fast_fail_bars = 5;
        m_param_min_momentum_atr = 0.5;
        m_param_cooldown_bars = 3;
        m_param_structure_upgrade_atr = 0.5;
        m_param_max_probe_fails = 2;
        m_param_max_cooldown_bars = 10;
        
        Reset();
    }
    
    //+--------------------------------------------------------------
    //| 重置所有状态
    //+--------------------------------------------------------------
    void Reset()
    {
        m_state = SC_STATE_IDLE;
        m_reason = SC_REASON_NONE;
        m_cooldown_start_time = 0;
        m_cooldown_bars_elapsed = 0;
        m_cooldown_bars_required = m_param_cooldown_bars;
        m_failed_price = 0.0;
        m_failed_structure_price = 0.0;
        m_failed_atr = 0.0;
        m_is_long = false;
        m_entry_time = 0;
        m_entry_price = 0.0;
        m_entry_atr = 0.0;
        m_has_entry = false;
        m_entry_bars = 0;
        m_probe_fail_count = 0;
        m_probe_fail_dir = 0;
        m_last_probe_time = 0;
        m_second_chance_ready = false;
        m_last_pullback_depth = 0.0;
    }
    
    //+--------------------------------------------------------------
    //| 设置参数
    //+--------------------------------------------------------------
    void SetParams(int fastFailBars, double minMomentumATR, 
                   int cooldownBars, double structureUpgradeATR, int maxProbeFails = 2,
                   int maxCooldownBars = 10)
    {
        m_param_fast_fail_bars = fastFailBars;
        m_param_min_momentum_atr = minMomentumATR;
        m_param_cooldown_bars = cooldownBars;
        m_param_structure_upgrade_atr = structureUpgradeATR;
        m_param_max_probe_fails = maxProbeFails;
        m_param_max_cooldown_bars = maxCooldownBars;
        m_cooldown_bars_required = cooldownBars;
    }
    
    //+--------------------------------------------------------------
    //| 记录入场（用于后续快速失败检测）
    //+--------------------------------------------------------------
    void RecordEntry(double price, double atr, bool isLong, double structurePrice = 0.0)
    {
        m_entry_time = TimeCurrent();
        m_entry_price = price;
        m_entry_atr = atr;
        m_has_entry = true;
        m_entry_bars = 0;
        m_is_long = isLong;
        m_failed_structure_price = structurePrice;
        
        // 入场成功，重置Probe失败计数
        m_probe_fail_count = 0;
        m_second_chance_ready = false;
        
        Print("[StructuralCooldown] Entry recorded. price=", price, 
              " atr=", atr, " isLong=", isLong,
              " structurePrice=", structurePrice);
    }
    
    //+--------------------------------------------------------------
    //| 更新K线计数（每根新K线调用一次）
    //+--------------------------------------------------------------
    void OnNewBar()
    {
        if(m_has_entry)
            m_entry_bars++;
            
        if(m_state == SC_STATE_COOLDOWN)
        {
            m_cooldown_bars_elapsed++;
            Print("[StructuralCooldown] Cooldown bar elapsed: ", 
                  m_cooldown_bars_elapsed, "/", m_cooldown_bars_required);
        }
    }
    
    //+--------------------------------------------------------------
    //| 记录Probe失败（用于连续失败检测）
    //+--------------------------------------------------------------
    void RecordProbeFail(bool isLong)
    {
        int dir = isLong ? 1 : -1;
        
        // 同方向连续失败才累计
        if(m_probe_fail_dir == dir)
        {
            m_probe_fail_count++;
        }
        else
        {
            m_probe_fail_count = 1;
            m_probe_fail_dir = dir;
        }
        m_last_probe_time = TimeCurrent();
        
        Print("[StructuralCooldown] Probe fail recorded. count=", m_probe_fail_count,
              " dir=", isLong ? "LONG" : "SHORT");
        
        // 检查是否触发冷却
        if(m_probe_fail_count >= m_param_max_probe_fails)
        {
            ActivateCooldown(SC_REASON_DOUBLE_FAIL, 0, 0);
        }
    }
    
    //+--------------------------------------------------------------
    //| 激活冷却
    //+--------------------------------------------------------------
    void ActivateCooldown(StructuralCooldownReason reason, 
                          double currentPrice, double currentATR)
    {
        if(m_state == SC_STATE_COOLDOWN)
            return;  // 已经在冷却中
            
        m_state = SC_STATE_COOLDOWN;
        m_reason = reason;
        m_cooldown_start_time = TimeCurrent();
        m_cooldown_bars_elapsed = 0;
        m_failed_price = currentPrice > 0 ? currentPrice : m_entry_price;
        m_failed_atr = currentATR > 0 ? currentATR : m_entry_atr;
        
        string reasonStr = "";
        switch(reason)
        {
            case SC_REASON_FAST_STOP:   reasonStr = "FastStop"; break;
            case SC_REASON_NO_MOMENTUM: reasonStr = "NoMomentum"; break;
            case SC_REASON_DOUBLE_FAIL: reasonStr = "DoubleFail"; break;
            default: reasonStr = "Unknown"; break;
        }
        
        Print("[StructuralCooldown] ACTIVATED. reason=", reasonStr,
              " failed_price=", m_failed_price,
              " cooldown_bars=", m_cooldown_bars_required);
    }
    
    //+--------------------------------------------------------------
    //| 检测快速失败（在仓位平仓后调用）
    //| 返回true表示触发了冷却
    //+--------------------------------------------------------------
    bool CheckFastFail(double exitPrice, bool isLoss)
    {
        if(!m_has_entry || m_entry_atr <= 0)
            return false;
            
        // 条件1：入场后N根K线内被止损
        if(isLoss && m_entry_bars <= m_param_fast_fail_bars)
        {
            ActivateCooldown(SC_REASON_FAST_STOP, exitPrice, m_entry_atr);
            return true;
        }
        
        return false;
    }
    
    //+--------------------------------------------------------------
    //| 检测无动量（每根K线调用）
    //| 当前价格相对入场反向，且未达到最小动量
        //+--------------------------------------------------------------
    bool CheckNoMomentum(double currentPrice)
    {
        if(!m_has_entry || m_entry_atr <= 0 || m_state == SC_STATE_COOLDOWN)
            return false;
            
        double profit = m_is_long ? (currentPrice - m_entry_price) 
                                   : (m_entry_price - currentPrice);
        double profitATR = profit / m_entry_atr;
        
        // 反向且未达最小动量
        if(profitATR < 0 && MathAbs(profitATR) > 0.5)  // 反向超过0.5 ATR
        {
            ActivateCooldown(SC_REASON_NO_MOMENTUM, currentPrice, m_entry_atr);
            return true;
        }
        
        return false;
    }
    
    //+--------------------------------------------------------------
    //| 检查是否可以解除冷却
    //| 需要：时间条件 + 结构条件
    //+--------------------------------------------------------------
    bool CheckCooldownRelease(double currentPrice, double currentATR,
                               double newStructurePrice = 0.0,
                               double newPullbackDepth = 0.0)
    {
        if(m_state != SC_STATE_COOLDOWN)
            return true;  // 不在冷却中
            
        // 时间条件未满足
        if(m_cooldown_bars_elapsed < m_cooldown_bars_required)
            return false;
        
        // 条件A：结构升级（新Pullback结构）
        // 新结构点比失败点更优
        if(newStructurePrice > 0 && m_failed_structure_price > 0)
        {
            if(m_is_long && newStructurePrice > m_failed_structure_price)
            {
                // 多头：新高点更高
                ReleaseCooldown();
                Print("[StructuralCooldown] Released: Structure upgrade (higher high)");
                return true;
            }
            if(!m_is_long && newStructurePrice < m_failed_structure_price && newStructurePrice > 0)
            {
                // 空头：新低点更低
                ReleaseCooldown();
                Print("[StructuralCooldown] Released: Structure upgrade (lower low)");
                return true;
            }
        }
        
        // 条件B：回撤更浅
        if(newPullbackDepth > 0 && m_last_pullback_depth > 0)
        {
            if(newPullbackDepth < m_last_pullback_depth)
            {
                ReleaseCooldown();
                Print("[StructuralCooldown] Released: Shallower pullback");
                return true;
            }
        }
        
        // 条件C：价格拉开 ≥ 0.3 ATR（脱离假突破区域）
        if(currentATR > 0 && m_failed_price > 0)
        {
            double distance = MathAbs(currentPrice - m_failed_price);
            if(distance >= currentATR * 0.3)
            {
                ReleaseCooldown();
                Print("[StructuralCooldown] Released: Price escaped fake zone");
                return true;
            }
        }
        
        // 条件D：最大冷却时间（防止永久冷却）
        if(m_cooldown_bars_elapsed >= m_param_max_cooldown_bars)
        {
            ReleaseCooldown();
            Print("[StructuralCooldown] Released: Max cooldown time reached (", m_param_max_cooldown_bars, " bars)");
            return true;
        }
        
        return false;  // 继续冷却
    }
    
    //+--------------------------------------------------------------
    //| 解除冷却
    //+--------------------------------------------------------------
    void ReleaseCooldown()
    {
        m_state = SC_STATE_IDLE;
        m_second_chance_ready = true;  // 准备好二次确认
        m_has_entry = false;
        m_entry_bars = 0;
        
        Print("[StructuralCooldown] RELEASED. Second chance ready.");
    }
    
    //+--------------------------------------------------------------
    //| 二次确认检查（入场时调用）
    //| 只有"更高质量"的入场才允许
    //+--------------------------------------------------------------
    bool CanSecondChanceEntry(double currentPrice, double currentATR,
                               double structurePrice = 0.0)
    {
        if(!m_second_chance_ready)
            return true;  // 不需要二次确认
            
        // 方案1：突破点更优
        if(structurePrice > 0 && m_failed_structure_price > 0)
        {
            if(m_is_long && structurePrice > m_failed_structure_price)
                return true;
            if(!m_is_long && structurePrice < m_failed_structure_price)
                return true;
        }
        
        // 方案2：价格已经远离失败点
        if(currentATR > 0 && m_failed_price > 0)
        {
            double distance = MathAbs(currentPrice - m_failed_price);
            if(distance >= currentATR * 0.3)
                return true;
        }
        
        return false;  // 质量不够，拒绝入场
    }
    
    //+--------------------------------------------------------------
    //| 确认入场后，重置二次确认状态
    //+--------------------------------------------------------------
    void ConfirmSecondChanceEntry()
    {
        m_second_chance_ready = false;
        m_probe_fail_count = 0;
    }
    
    //+--------------------------------------------------------------
    //| 状态查询
    //+--------------------------------------------------------------
    bool IsActive() const { return m_state == SC_STATE_COOLDOWN; }
    bool IsIdle() const { return m_state == SC_STATE_IDLE; }
    bool NeedsSecondChance() const { return m_second_chance_ready; }
    StructuralCooldownState GetState() const { return m_state; }
    StructuralCooldownReason GetReason() const { return m_reason; }
    int GetElapsedBars() const { return m_cooldown_bars_elapsed; }
    int GetRequiredBars() const { return m_cooldown_bars_required; }
    int GetRemainingBars() const 
    { 
        return MathMax(0, m_cooldown_bars_required - m_cooldown_bars_elapsed); 
    }
    
    string GetReasonString() const
    {
        switch(m_reason)
        {
            case SC_REASON_FAST_STOP:   return "快速止损";
            case SC_REASON_NO_MOMENTUM: return "无动量";
            case SC_REASON_DOUBLE_FAIL: return "连续失败";
            default: return "";
        }
    }
    
    //+--------------------------------------------------------------
    //| 记录回撤深度（用于后续比较）
    //+--------------------------------------------------------------
    void RecordPullbackDepth(double depthATR)
    {
        m_last_pullback_depth = depthATR;
    }
    
    //+--------------------------------------------------------------
    //| 清除入场记录（正常出场后调用）
    //+--------------------------------------------------------------
    void ClearEntryRecord()
    {
        m_has_entry = false;
        m_entry_bars = 0;
        // 注意：不清除冷却状态，冷却仍然有效
    }
};

#endif // __STRUCTURAL_COOLDOWN_MQH__
