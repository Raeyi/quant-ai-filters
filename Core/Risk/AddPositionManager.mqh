//+------------------------------------------------------------------+
//|                Core/Risk/AddPositionManager.mqh                   |
//|           加仓管理器：顺势金字塔加仓                                |
//|     核心原则：市场第二次证明我是对的，我才敢更重                     |
//+------------------------------------------------------------------+

#ifndef __ADD_POSITION_MANAGER_MQH__
#define __ADD_POSITION_MANAGER_MQH__

#property strict

#include "StructuralCooldown.mqh"

//+------------------------------------------------------------------+
//| 加仓状态枚举                                                       |
//+------------------------------------------------------------------+
enum AddPositionState
{
    ADD_STATE_NONE = 0,        // 无加仓
    ADD_STATE_FIRST_DONE = 1,  // 第一次加仓完成
    ADD_STATE_SECOND_DONE = 2  // 第二次加仓完成
};

//+------------------------------------------------------------------+
//| 加仓信号类型                                                       |
//+------------------------------------------------------------------+
enum AddSignalType
{
    ADD_SIGNAL_NONE = 0,
    ADD_SIGNAL_FIRST = 1,      // 第一次加仓信号
    ADD_SIGNAL_SECOND = 2      // 第二次加仓信号
};

//+------------------------------------------------------------------+
//| 加仓请求结构                                                       |
//+------------------------------------------------------------------+
struct AddPositionRequest
{
    double volume;             // 加仓手数
    double sl;                 // 加仓止损
    double price;              // 加仓价格
    string reason;             // 加仓原因
    AddSignalType signalType;  // 信号类型
};

//+------------------------------------------------------------------+
//| 加仓管理器类                                                       |
//| 与账户风控结合，确保总风险不超过上限                                 |
//+------------------------------------------------------------------+
class CAddPositionManager
{
private:
    AddPositionState m_state;
    
    // 主仓信息
    double m_base_lot;              // 主仓手数
    double m_base_entry_price;      // 主仓入场价
    double m_base_entry_atr;        // 主仓入场时ATR
    bool   m_is_long;               // 方向
    
    // 风险追踪
    double m_max_total_risk;        // 最大总风险（R倍数）
    double m_used_risk;             // 已使用风险
    
    // 加仓记录
    double m_add1_lot;              // 第一次加仓手数
    double m_add1_entry_price;      // 第一次加仓入场价
    double m_add1_sl;               // 第一次加仓止损
    double m_add2_lot;              // 第二次加仓手数
    double m_add2_entry_price;      // 第二次加仓入场价
    double m_add2_sl;               // 第二次加仓止损
    
    // 状态追踪
    bool   m_tp1_reached;           // TP1是否达成
    bool   m_pullback_failed_again; // 第二次回撤是否失败
    int    m_pullback_fail_count;   // 回撤失败计数
    
    // 参数
    double m_param_tp1_atr;         // TP1触发ATR倍数
    double m_param_add1_ratio;      // 第一次加仓比例
    double m_param_add2_ratio;      // 第二次加仓比例
    double m_param_add2_profit_atr; // 第二次加仓盈利要求
    int    m_param_max_adds;        // 最大加仓次数
    
    // 外部依赖
    CStructuralCooldown *m_cooldown;  // 冷却器指针
    
public:
    //+--------------------------------------------------------------
    //| 构造函数
    //+--------------------------------------------------------------
    CAddPositionManager()
    {
        // 默认参数
        m_param_tp1_atr = 1.5;
        m_param_add1_ratio = 0.4;      // 40%
        m_param_add2_ratio = 0.25;     // 25%
        m_param_add2_profit_atr = 2.0; // 盈利2 ATR
        m_param_max_adds = 2;
        m_max_total_risk = 2.5;
        
        m_cooldown = NULL;
        Reset();
    }
    
    //+--------------------------------------------------------------
    //| 设置冷却器依赖
    //+--------------------------------------------------------------
    void SetCooldownManager(CStructuralCooldown *cooldown)
    {
        m_cooldown = cooldown;
    }
    
    //+--------------------------------------------------------------
    //| 设置参数
    //+--------------------------------------------------------------
    void SetParams(double tp1ATR, double add1Ratio, double add2Ratio, 
                   double add2ProfitATR, double maxTotalRisk)
    {
        m_param_tp1_atr = tp1ATR;
        m_param_add1_ratio = add1Ratio;
        m_param_add2_ratio = add2Ratio;
        m_param_add2_profit_atr = add2ProfitATR;
        m_max_total_risk = maxTotalRisk;
    }
    
    //+--------------------------------------------------------------
    //| 重置状态
    //+--------------------------------------------------------------
    void Reset()
    {
        m_state = ADD_STATE_NONE;
        m_base_lot = 0.0;
        m_base_entry_price = 0.0;
        m_base_entry_atr = 0.0;
        m_is_long = false;
        m_used_risk = 0.0;
        
        m_add1_lot = 0.0;
        m_add1_entry_price = 0.0;
        m_add1_sl = 0.0;
        m_add2_lot = 0.0;
        m_add2_entry_price = 0.0;
        m_add2_sl = 0.0;
        
        m_tp1_reached = false;
        m_pullback_failed_again = false;
        m_pullback_fail_count = 0;
    }
    
    //+--------------------------------------------------------------
    //| 主仓入场时初始化
    //+--------------------------------------------------------------
    void OnMainEntry(double lot, double price, double atr, bool isLong)
    {
        Reset();
        m_base_lot = lot;
        m_base_entry_price = price;
        m_base_entry_atr = atr;
        m_is_long = isLong;
        m_used_risk = 1.0;  // 主仓 = 1R
        
        Print("[AddPositionManager] Main entry recorded. lot=", lot,
              " price=", price, " atr=", atr, " isLong=", isLong);
    }
    
    //+--------------------------------------------------------------
    //| 更新盈利状态（每根新K线调用）
    //+--------------------------------------------------------------
    void UpdateProfitState(double currentPrice, double currentATR)
    {
        if(m_base_entry_price <= 0 || currentATR <= 0)
            return;
            
        double profitATR = m_is_long ? 
            (currentPrice - m_base_entry_price) / currentATR :
            (m_base_entry_price - currentPrice) / currentATR;
            
        // 检查TP1是否达成
        if(!m_tp1_reached && profitATR >= m_param_tp1_atr)
        {
            m_tp1_reached = true;
            Print("[AddPositionManager] TP1 reached. profit=", profitATR, " ATR");
        }
    }
    
    //+--------------------------------------------------------------
    //| 记录回撤失败（用于触发加仓）
    //+--------------------------------------------------------------
    void RecordPullbackFail()
    {
        m_pullback_fail_count++;
        
        // 第二次回撤失败才标记
        if(m_pullback_fail_count >= 2)
        {
            m_pullback_failed_again = true;
            // 每2次失败打印一次，减少日志噪音
            if(m_pullback_fail_count % 2 == 0)
            {
                Print("[AddPositionManager] Pullback failed again. count=", m_pullback_fail_count);
            }
        }
    }
    
    //+--------------------------------------------------------------
    //| 检查是否允许第一次加仓
        //+--------------------------------------------------------------
    bool CanAddFirst(double currentEquity, double startBalance, double maxDailyLossPercent) const
    {
        // 状态检查
        if(m_state != ADD_STATE_NONE)
            return false;
            
        // 主仓验证
        if(!m_tp1_reached)
            return false;
            
        // 第二次回撤失败
        if(!m_pullback_failed_again)
            return false;
            
        // 冷却器检查
        if(CheckPointer(m_cooldown) == POINTER_DYNAMIC)
            if(m_cooldown.IsActive())
                return false;
            
        // 风险上限
        if(m_used_risk >= m_max_total_risk)
            return false;
            
        // 账户风控检查
        double loss = (startBalance - currentEquity) / startBalance;
        if(loss >= maxDailyLossPercent / 100.0)
            return false;
            
        return true;
    }
    
    //+--------------------------------------------------------------
    //| 检查是否允许第二次加仓
    //+--------------------------------------------------------------
    bool CanAddSecond(double currentPrice, double currentATR,
                      double currentEquity, double startBalance, 
                      double maxDailyLossPercent) const
    {
        // 状态检查
        if(m_state != ADD_STATE_FIRST_DONE)
            return false;
            
        // 盈利要求
        if(m_base_entry_price <= 0 || currentATR <= 0)
            return false;
            
        double profitATR = m_is_long ?
            (currentPrice - m_base_entry_price) / currentATR :
            (m_base_entry_price - currentPrice) / currentATR;
            
        if(profitATR < m_param_add2_profit_atr)
            return false;
            
        // 冷却器检查
        if(CheckPointer(m_cooldown) == POINTER_DYNAMIC)
            if(m_cooldown.IsActive())
                return false;
            
        // 风险上限
        if(m_used_risk >= m_max_total_risk)
            return false;
            
        // 账户风控检查
        double loss = (startBalance - currentEquity) / startBalance;
        if(loss >= maxDailyLossPercent / 100.0)
            return false;
            
        return true;
    }
    
    //+--------------------------------------------------------------
    //| 获取加仓信号
    //+--------------------------------------------------------------
    AddSignalType GetAddSignal(double currentPrice, double currentATR,
                               double currentEquity, double startBalance,
                               double maxDailyLossPercent)
    {
        // 先更新盈利状态
        UpdateProfitState(currentPrice, currentATR);
        
        // 检查第一次加仓
        if(CanAddFirst(currentEquity, startBalance, maxDailyLossPercent))
            return ADD_SIGNAL_FIRST;
            
        // 检查第二次加仓
        if(CanAddSecond(currentPrice, currentATR, currentEquity, startBalance, maxDailyLossPercent))
            return ADD_SIGNAL_SECOND;
            
        return ADD_SIGNAL_NONE;
    }
    
    //+--------------------------------------------------------------
    //| 构建加仓请求
    //+--------------------------------------------------------------
    bool BuildAddRequest(AddPositionRequest &req, AddSignalType signalType,
                         double currentPrice, double pullbackStructurePrice)
    {
        if(signalType == ADD_SIGNAL_NONE)
            return false;
            
        double ratio = (signalType == ADD_SIGNAL_FIRST) ? 
                       m_param_add1_ratio : m_param_add2_ratio;
        
        req.volume = NormalizeDouble(m_base_lot * ratio, 2);
        req.price = currentPrice;
        req.signalType = signalType;
        
        // 计算止损：使用最近回撤结构点
        // 不与主仓共用SL
        if(signalType == ADD_SIGNAL_FIRST)
        {
            req.sl = pullbackStructurePrice;
            req.reason = "第二次回撤失败加仓";
        }
        else
        {
            req.sl = pullbackStructurePrice;
            req.reason = "强势延续加仓";
        }
        
        // 验证手数
        double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
        if(req.volume < minLot)
        {
            Print("[AddPositionManager] Add lot too small: ", req.volume, " < ", minLot);
            return false;
        }
        
        return true;
    }
    
    //+--------------------------------------------------------------
    //| 确认加仓执行
    //+--------------------------------------------------------------
    void ConfirmAddExecution(AddSignalType signalType, double lot, double price, double sl)
    {
        if(signalType == ADD_SIGNAL_FIRST)
        {
            m_state = ADD_STATE_FIRST_DONE;
            m_add1_lot = lot;
            m_add1_entry_price = price;
            m_add1_sl = sl;
            m_used_risk += m_param_add1_ratio;
            
            Print("[AddPositionManager] First add confirmed. lot=", lot,
                  " price=", price, " sl=", sl, " used_risk=", m_used_risk);
        }
        else if(signalType == ADD_SIGNAL_SECOND)
        {
            m_state = ADD_STATE_SECOND_DONE;
            m_add2_lot = lot;
            m_add2_entry_price = price;
            m_add2_sl = sl;
            m_used_risk += m_param_add2_ratio;
            
            Print("[AddPositionManager] Second add confirmed. lot=", lot,
                  " price=", price, " sl=", sl, " used_risk=", m_used_risk);
        }
    }
    
    //+--------------------------------------------------------------
    //| 获取加仓止损（独立于主仓）
    //+--------------------------------------------------------------
    double GetAddSL(AddSignalType signalType) const
    {
        if(signalType == ADD_SIGNAL_FIRST)
            return m_add1_sl;
        if(signalType == ADD_SIGNAL_SECOND)
            return m_add2_sl;
        return 0.0;
    }
    
    //+--------------------------------------------------------------
    //| 状态查询
    //+--------------------------------------------------------------
    AddPositionState GetState() const { return m_state; }
    bool HasAddedFirst() const { return m_state >= ADD_STATE_FIRST_DONE; }
    bool HasAddedSecond() const { return m_state >= ADD_STATE_SECOND_DONE; }
    bool IsTP1Reached() const { return m_tp1_reached; }
    double GetUsedRisk() const { return m_used_risk; }
    double GetRemainingRisk() const { return m_max_total_risk - m_used_risk; }
    double GetTotalAddLot() const { return m_add1_lot + m_add2_lot; }
};

#endif // __ADD_POSITION_MANAGER_MQH__
