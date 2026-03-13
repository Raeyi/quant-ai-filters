//+------------------------------------------------------------------+
//|                          Risk/RiskPipeline.mqh                   |
//|                   Risk Pipeline definition                      |
//+------------------------------------------------------------------+
#ifndef __RISK_PIPELINE_MQH__
#define __RISK_PIPELINE_MQH__

#include "../Inputs_All.mqh"
#include "TradeRisk.mqh"
#include "PositionRisk.mqh"
#include "TimeStop.mqh"
#include "Cooldown.mqh"
#include "StructuralCooldown.mqh"
#include "AccountRisk.mqh"
#include "PositionSizer.mqh"
#include "LosingStreakGuard.mqh"
#include "RiskStatus.mqh"
#include "../TradeTypes.mqh"

// 输入参数定义在 Inputs_All.mqh，此文件不再重复声明

class RiskPipeline
{
private:
    AccountRisk  account_risk;
    TradeRisk    trade_risk;
    PositionRisk position_risk;
    TimeStop     time_stop;
    Cooldown     cooldown;
    PositionSizer position_sizer;
    LosingStreakGuard losing_guard;
    CStructuralCooldown m_structural_cooldown;  // 结构冷却器（统一管理）
    bool m_structural_cooldown_enabled;          // 是否启用结构冷却
    bool allow_entry;
    bool in_cooldown;
    string block_reason;
    int gap_skip_bars_remaining;
    datetime last_bar_time;

public:
    void Init()
    {
        account_risk.Init();
        time_stop.Init(position_risk.maxHoldingBars);
        cooldown.Init(CooldownSeconds);

        // 初始化结构冷却器
        m_structural_cooldown_enabled = TP_EnableCooldown;
        if(m_structural_cooldown_enabled)
        {
            m_structural_cooldown.SetParams(TP_FastFailBars, TP_MinMomentumATR,
                                            TP_CooldownBars, TP_StructureUpgradeATR,
                                            2, TP_MaxCooldownBars);
            m_structural_cooldown.Reset();
        }

        allow_entry = true;
        in_cooldown = false;
        block_reason = "";
        gap_skip_bars_remaining = 0;
        last_bar_time = 0;
    }

    // 新K线通知（用于冷却器计时）
    void OnNewBar()
    {
        if(m_structural_cooldown_enabled)
            m_structural_cooldown.OnNewBar();
    }

    // 更新冷却状态（检查是否可以解除）
    void UpdateCooldownState(double currentPrice, double currentATR, double structurePrice = 0.0)
    {
        if(m_structural_cooldown_enabled && m_structural_cooldown.IsActive())
        {
            m_structural_cooldown.CheckCooldownRelease(currentPrice, currentATR, structurePrice, 0);
            m_structural_cooldown.CheckNoMomentum(currentPrice);
        }
    }

    void RefreshStatus()
    {
        bool allow = true;
        bool cooldown_block = false;
        string reason = "";

        if(!account_risk.AllowTrading())
        {
            allow = false;
            reason = "日内亏损超限";
        }

        if(allow && losing_guard.InCooldown())
        {
            allow = false;
            cooldown_block = true;
            reason = "连续止损冷却";
        }

        if(allow && cooldown.InCooldown())
        {
            allow = false;
            cooldown_block = true;
            reason = "交易冷却";
        }

        // 结构冷却检查
        if(allow && m_structural_cooldown_enabled && m_structural_cooldown.IsActive())
        {
            allow = false;
            cooldown_block = true;
            reason = "结构冷却(" + m_structural_cooldown.GetReasonString() + ")";
        }

        if(allow && !position_risk.AllowNewTrade())
        {
            allow = false;
            reason = "已有持仓";
        }

        allow_entry = allow;
        in_cooldown = cooldown_block;
        block_reason = reason;
    }

    bool BuildTrade(const Signal &signal, TradeRequest &req)
    {
        allow_entry = true;
        in_cooldown = false;
        block_reason = "";
        // Print("[RiskPipeline] BuildTrade called, signal type=", signal.type, " source=", signal.source); // 减少日志噪音

        // 账户风险检查（加仓和新仓都需要）
        if(!account_risk.AllowTrading())
        {
            allow_entry = false;
            block_reason = "日内亏损超限";
            // 每分钟最多打印一次账户风险拒绝日志
            static datetime last_account_risk_log = 0;
            datetime current_time = TimeCurrent();
            if(current_time - last_account_risk_log >= 60)
            {
                last_account_risk_log = current_time;
                Print("[RiskPipeline] AccountRisk rejected trading");
            }
            return false;
        }

        // 连亏冷却检查
        if(!losing_guard.CanTrade())
        {
            allow_entry = false;
            in_cooldown = true;
            block_reason = "连续止损冷却";
            // 每分钟最多打印一次连亏冷却日志
            static datetime last_losing_guard_log = 0;
            datetime current_time = TimeCurrent();
            if(current_time - last_losing_guard_log >= 60)
            {
                last_losing_guard_log = current_time;
                Print("[RiskPipeline] LosingStreakGuard: in cooldown, skip new trade");
            }
            return false;
        }

        // 交易冷却检查（加仓信号跳过此检查）
        if(!signal.IsAddSignal() && !cooldown.CanTrade())
        {
            allow_entry = false;
            in_cooldown = true;
            block_reason = "交易冷却";
            // 每分钟最多打印一次交易冷却日志
            static datetime last_cooldown_log = 0;
            datetime current_time = TimeCurrent();
            if(current_time - last_cooldown_log >= 60)
            {
                last_cooldown_log = current_time;
                Print("[RiskPipeline] In cooldown, skip new trade");
            }
            return false;
        }

        // 结构冷却检查（加仓信号跳过此检查）
        if(m_structural_cooldown_enabled && !signal.IsAddSignal())
        {
            // 检查是否在冷却中
            if(m_structural_cooldown.IsActive())
            {
                allow_entry = false;
                in_cooldown = true;
                block_reason = "结构冷却(" + m_structural_cooldown.GetReasonString() + ")";
                return false;
            }

            // 二次确认检查（冷却解除后首次入场需要更高质量信号）
            if(m_structural_cooldown.NeedsSecondChance())
            {
                double price = signal.IsLongSignal() ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                      : SymbolInfoDouble(_Symbol, SYMBOL_BID);
                if(!m_structural_cooldown.CanSecondChanceEntry(price, signal.atr, signal.structure_price))
                {
                    allow_entry = false;
                    block_reason = "结构冷却二次确认未通过";
                    Print("[RiskPipeline] Second chance entry rejected for ", signal.source);
                    return false;
                }
            }
        }

        // 仓位检查（支持加仓信号）
        // Print("[RiskPipeline] BuildTrade signal type=", signal.type, " isAdd=", signal.IsAddSignal(), " source=", signal.source); // 减少日志噪音
        if(!position_risk.AllowNewTrade(signal))
        {
            allow_entry = false;
            block_reason = "已有持仓";
            // Print("[RiskPipeline] PositionRisk.AllowNewTrade rejected signal type=", signal.type, " isAdd=", signal.IsAddSignal()); // 减少日志噪音
            return false;
        }

        // 仓位计算（加仓使用信号中的 exit_volume，新仓使用 PositionSizer）
        double lot;
        // Print("[RiskPipeline] signal.IsAddSignal()=", signal.IsAddSignal(), " exit_volume=", signal.exit_volume); // 减少日志噪音
        if(signal.IsAddSignal() && signal.exit_volume > 0)
        {
            // 加仓：使用信号中指定的手数
            lot = signal.exit_volume;
        }
        else
        {
            // 新仓：使用 PositionSizer 计算
            lot = position_sizer.ComputeLot(signal);
            if(lot <= 0.0)
            {
                block_reason = "PositionSizer: invalid lot";
                // 每分钟最多打印一次PositionSizer拒绝日志
                static datetime last_position_sizer_log = 0;
                datetime current_time = TimeCurrent();
                if(current_time - last_position_sizer_log >= 60)
                {
                    last_position_sizer_log = current_time;
                    Print("[RiskPipeline] PositionSizer returned 0 lot, skip");
                }
                return false;
            }
        }
        req.volume = lot;

        if(!trade_risk.Validate(signal, req))
        {
            block_reason = "TradeRisk.Validate failed";
            // 每分钟最多打印一次TradeRisk验证失败日志
            static datetime last_trade_risk_log = 0;
            datetime current_time = TimeCurrent();
            if(current_time - last_trade_risk_log >= 60)
            {
                last_trade_risk_log = current_time;
                Print("[RiskPipeline] TradeRisk.Validate failed for signal type=", signal.type, " source=", signal.source);
            }
            return false;
        }

        req.source = signal.source;
        
        // 设置交易方向
        if(signal.type == SIGNAL_BUY || signal.type == SIGNAL_ADD_LONG)
            req.direction = TRADE_BUY;
        else if(signal.type == SIGNAL_SELL || signal.type == SIGNAL_ADD_SHORT)
            req.direction = TRADE_SELL;
        
        return true;
    }

    RiskStatus GetStatus() const
    {
        RiskStatus rs;
        rs.allow_entry = allow_entry;
        rs.in_cooldown = in_cooldown;
        return rs;
    }

    bool IsEntryAllowed() const
    {
        return allow_entry;
    }

    bool IsInCooldown() const
    {
        return in_cooldown;
    }

    string GetBlockReason() const
    {
        return block_reason;
    }

    int GetConsecutiveLosses() const
    {
        return losing_guard.GetLosingStreak();
    }
    
    // 验证修改止损请求
    bool ValidateModifySL(const Signal &signal, TradeRequest &req)
    {
        block_reason = "";
        
        // 必须有持仓
        if(!PositionSelect(_Symbol))
        {
            block_reason = "无持仓";
            return false;
        }
        
        // 验证新止损价
        if(signal.new_sl <= 0)
        {
            block_reason = "无效止损价";
            return false;
        }
        
        long pos_type = PositionGetInteger(POSITION_TYPE);
        double cur_sl = PositionGetDouble(POSITION_SL);
        double cur_tp = PositionGetDouble(POSITION_TP);
        bool is_buy = (pos_type == POSITION_TYPE_BUY);
        
        // 止损只能朝有利方向移动（保护性止损规则）
        bool is_improving = is_buy ? (signal.new_sl > cur_sl) : (signal.new_sl < cur_sl);
        if(!is_improving && cur_sl > 0)  // cur_sl=0 表示之前没有止损
        {
            block_reason = "止损未改善（保护性止损规则）";
            Print("[RiskPipeline] 修改止损被拒：", block_reason,
                  " cur_sl=", DoubleToString(cur_sl, _Digits),
                  " new_sl=", DoubleToString(signal.new_sl, _Digits));
            return false;
        }
        
        // 检查止损距离限制
        long stops = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
        double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
        double min_dist = stops * point;
        double current_price = is_buy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) 
                                       : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        
        if(is_buy && (current_price - signal.new_sl) < min_dist)
        {
            block_reason = "止损距离不足";
            Print("[RiskPipeline] 修改止损被拒：", block_reason);
            return false;
        }
        else if(!is_buy && (signal.new_sl - current_price) < min_dist)
        {
            block_reason = "止损距离不足";
            Print("[RiskPipeline] 修改止损被拒：", block_reason);
            return false;
        }
        
        // 检查止损不能穿过当前价格
        if(is_buy && signal.new_sl >= current_price)
        {
            block_reason = "止损价高于当前价格";
            return false;
        }
        else if(!is_buy && signal.new_sl <= current_price)
        {
            block_reason = "止损价低于当前价格";
            return false;
        }
        
        // 构建请求
        req.action = ACTION_MODIFY_SL;
        req.new_sl = NormalizeDouble(signal.new_sl, _Digits);
        req.ticket = PositionGetInteger(POSITION_TICKET);
        req.source = signal.source;
        
        Print("[RiskPipeline] 修改止损验证通过: new_sl=", DoubleToString(req.new_sl, _Digits));
        return true;
    }
    
    // 验证修改止盈请求
    bool ValidateModifyTP(const Signal &signal, TradeRequest &req)
    {
        block_reason = "";
        
        if(!PositionSelect(_Symbol))
        {
            block_reason = "无持仓";
            return false;
        }
        
        if(signal.new_tp <= 0)
        {
            block_reason = "无效止盈价";
            return false;
        }
        
        long pos_type = PositionGetInteger(POSITION_TYPE);
        double cur_sl = PositionGetDouble(POSITION_SL);
        bool is_buy = (pos_type == POSITION_TYPE_BUY);
        double current_price = is_buy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) 
                                       : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        
        // 止盈必须在合理位置
        if(is_buy && signal.new_tp <= current_price)
        {
            block_reason = "止盈价低于当前价格";
            return false;
        }
        else if(!is_buy && signal.new_tp >= current_price)
        {
            block_reason = "止盈价高于当前价格";
            return false;
        }
        
        req.action = ACTION_MODIFY_TP;
        req.new_tp = NormalizeDouble(signal.new_tp, _Digits);
        req.ticket = PositionGetInteger(POSITION_TICKET);
        req.source = signal.source;
        
        Print("[RiskPipeline] 修改止盈验证通过: new_tp=", DoubleToString(req.new_tp, _Digits));
        return true;
    }

    bool ShouldClosePosition(const Signal &signal)
    {
        if(signal.type == SIGNAL_EXIT)
        {
            Print("[RiskPipeline] " + "[" + signal.source + "] Strategy exit accepted");
            position_risk.OnStrategyExit();
            return true;
        }

        if(time_stop.ShouldClose())
        {
            static datetime last_time_stop_log = 0;
            datetime current_time = TimeCurrent();
            if(current_time - last_time_stop_log >= 60) // 每分钟最多打印一次
            {
                last_time_stop_log = current_time;
                Print("[RiskPipeline] TimeStop.ShouldClose() = true");
            }
            return true;
        }

        if(position_risk.ShouldForceClose())
        {
            static datetime last_force_close_log = 0;
            datetime current_time = TimeCurrent();
            if(current_time - last_force_close_log >= 60) // 每分钟最多打印一次
            {
                last_force_close_log = current_time;
                Print("[RiskPipeline] PositionRisk.ShouldForceClose() = true");
            }
            return true;
        }

        return false;
    }

    void OnTradeExecuted()
    {
        position_risk.OnPositionOpened();
        cooldown.OnTrade();
    }

    // 交易执行后回调（带信号信息，用于结构冷却器）
    void OnTradeExecuted(const Signal &signal)
    {
        position_risk.OnPositionOpened();
        cooldown.OnTrade();

        // 记录入场信息到结构冷却器
        if(m_structural_cooldown_enabled && signal.atr > 0)
        {
            bool isLong = signal.IsLongSignal();
            m_structural_cooldown.RecordEntry(signal.price, signal.atr, isLong, signal.structure_price);

            // 确认二次入场
            if(m_structural_cooldown.NeedsSecondChance())
                m_structural_cooldown.ConfirmSecondChanceEntry();
        }
    }

    void OnPositionClosed()
    {
        double profit = GetLastClosedProfit_();
        losing_guard.OnTradeClosed(profit);
        cooldown.OnTrade();

        // 结构冷却器：检测快速失败
        if(m_structural_cooldown_enabled)
        {
            bool isLoss = (profit < 0);
            double exitPrice = GetLastClosedPrice_();
            m_structural_cooldown.CheckFastFail(exitPrice, isLoss);
            m_structural_cooldown.ClearEntryRecord();
        }
    }

    // ===== 结构冷却状态查询 =====
    bool IsStructuralCooldownActive() const
    {
        return m_structural_cooldown_enabled && m_structural_cooldown.IsActive();
    }

    string GetStructuralCooldownReason() const
    {
        if(!m_structural_cooldown_enabled || !m_structural_cooldown.IsActive())
            return "";
        return m_structural_cooldown.GetReasonString();
    }

    int GetStructuralCooldownRemaining() const
    {
        if(!m_structural_cooldown_enabled || !m_structural_cooldown.IsActive())
            return 0;
        return m_structural_cooldown.GetRemainingBars();
    }

    // ===== 缺口检查 =====
    // 缺口检测 + 冷却
    bool IsCheckGapOk()
    {   
        // 获取当前 K 线时间并检测缺口
        datetime bar_time = iTime(_Symbol, _Period, 0);
        if(last_bar_time > 0)
        {
            int period_sec = PeriodSeconds(_Period);
            if(period_sec > 0 && (bar_time - last_bar_time) > (int)(period_sec * 1.5))
            {
                gap_skip_bars_remaining = GapCooldownBars;
                // Print("[EA] Gap detected. Skip next ", gap_skip_bars_remaining, " bars.");
            }
        }
        last_bar_time = bar_time;

        if(gap_skip_bars_remaining > 0)
        {
            gap_skip_bars_remaining--;
            // Print("[EA] Gap cooldown active. Remaining bars: ", gap_skip_bars_remaining);
            return false;
        }

        return true;
    }
    

private:
    double GetLastClosedProfit_()
    {
        HistorySelect(0, TimeCurrent());

        int deals = HistoryDealsTotal();
        for(int i = deals - 1; i >= 0; i--)
        {
            ulong deal = HistoryDealGetTicket(i);
            if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol)
                continue;

            long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
            if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
                return HistoryDealGetDouble(deal, DEAL_PROFIT);
        }
        return 0.0;
    }

    double GetLastClosedPrice_()
    {
        HistorySelect(0, TimeCurrent());

        int deals = HistoryDealsTotal();
        for(int i = deals - 1; i >= 0; i--)
        {
            ulong deal = HistoryDealGetTicket(i);
            if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol)
                continue;

            long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
            if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
                return HistoryDealGetDouble(deal, DEAL_PRICE);
        }
        return 0.0;
    }
};

#endif // __RISK_PIPELINE_MQH__
