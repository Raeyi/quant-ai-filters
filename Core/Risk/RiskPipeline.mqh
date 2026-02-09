//+------------------------------------------------------------------+
//|                          Risk/RiskPipeline.mqh                   |
//|                   Risk Pipeline definition                      |
//+------------------------------------------------------------------+
#ifndef __RISK_PIPELINE_MQH__
#define __RISK_PIPELINE_MQH__

#include "TradeRisk.mqh"
#include "PositionRisk.mqh"
#include "TimeStop.mqh"
#include "Cooldown.mqh"
#include "AccountRisk.mqh"
#include "PositionSizer.mqh"
#include "LosingStreakGuard.mqh"
#include "RiskStatus.mqh"

input int CooldownSeconds = 60;  // 每次交易后冷却时间（秒）

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
    bool allow_entry;
    bool in_cooldown;
    string block_reason;

public:
    void Init()
    {
        account_risk.Init();
        time_stop.Init(position_risk.maxHoldingBars);
        cooldown.Init(CooldownSeconds);
        allow_entry = true;
        in_cooldown = false;
        block_reason = "";
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

        if(!account_risk.AllowTrading())
        {
            allow_entry = false;
            block_reason = "日内亏损超限";
            return false;
        }

        if(!losing_guard.CanTrade())
        {
            allow_entry = false;
            in_cooldown = true;
            block_reason = "连续止损冷却";
            Print("[RiskPipeline] LosingStreakGuard: in cooldown, skip new trade");
            return false;
        }

        if(!cooldown.CanTrade())
        {
            allow_entry = false;
            in_cooldown = true;
            block_reason = "交易冷却";
            Print("[RiskPipeline] In cooldown, skip new trade");
            return false;
        }

        if(!position_risk.AllowNewTrade())
        {
            allow_entry = false;
            block_reason = "已有持仓";
            return false;
        }

        double lot = position_sizer.ComputeLot(signal);
        if(lot <= 0.0)
        {
            block_reason = "PositionSizer: invalid lot";
            Print("[RiskPipeline] PositionSizer returned 0 lot, skip");
            return false;
        }
        req.volume = lot;

        if(!trade_risk.Validate(signal, req))
        {
            block_reason = "TradeRisk.Validate failed";
            return false;
        }

        req.source = signal.source;
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
            Print("[RiskPipeline] TimeStop.ShouldClose() = true");
            return true;
        }

        if(position_risk.ShouldForceClose())
        {
            Print("[RiskPipeline] PositionRisk.ShouldForceClose() = true");
            return true;
        }

        return false;
    }

    void OnTradeExecuted()
    {
        position_risk.OnPositionOpened();
        cooldown.OnTrade();
    }

    void OnPositionClosed()
    {
        double profit = GetLastClosedProfit_();
        losing_guard.OnTradeClosed(profit);
        cooldown.OnTrade();
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
};

#endif // __RISK_PIPELINE_MQH__
