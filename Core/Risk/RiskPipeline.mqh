//+------------------------------------------------------------------+
//|                          Risk/RiskPipeline.mqh                       |
//|                   Risk Pipeline definition                            |
//+                 风险管道定义 = 多个风险检查的组合                  +
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
    AccountRisk  account_risk;   // 账户风险
    TradeRisk    trade_risk;     // 单笔交易风险
    PositionRisk position_risk;  // 持仓风险（单仓、时间等）
    TimeStop     time_stop;      // 时间止损（bar 数）
    Cooldown     cooldown;       // 冷却
    PositionSizer position_sizer;  // 手数计算器
    LosingStreakGuard losing_guard; // 连续亏损保护
    bool allow_entry;
    bool in_cooldown;

public:
    void Init()
    {
        account_risk.Init();
        time_stop.Init(position_risk.maxHoldingBars); // 用 PositionRisk 的 maxHoldingBars 初始化 TimeStop
        cooldown.Init(CooldownSeconds);
    }

    // 信号 -> 风控 -> 生成 TradeRequest
    bool BuildTrade(const Signal &signal, TradeRequest &req)
    {
        if(!account_risk.AllowTrading())
            return false;

        // 连续止损冷却判断（优先）
        if(!losing_guard.CanTrade())
        {
            Print("[RiskPipeline] LosingStreakGuard: in cooldown, skip new trade");
            return false;
        }

        if(!cooldown.CanTrade()) // 每次交易后冷却判断
        {
            Print("[RiskPipeline] In cooldown, skip new trade");
            return false;
        }

        if(!position_risk.AllowNewTrade())
            return false;

        // 1) 先由 PositionSizer 算出 volume
        double lot = position_sizer.ComputeLot(signal);
        if(lot <= 0.0)
        {
            Print("[RiskPipeline] PositionSizer returned 0 lot, skip");
            return false;
        }
        req.volume = lot;

        // 2) 再由 TradeRisk 处理方向 + SL/TP 合法性
        if(!trade_risk.Validate(signal, req))
            return false;

        req.source = signal.source;
        return true;
    }

    //  获取当前风险状态
    RiskStatus GetStatus() const
   {
      RiskStatus rs;
      rs.allow_entry = allow_entry;
      rs.in_cooldown = in_cooldown;
      return rs;
   }

    // 是否需要平仓（时间止损 + PositionRisk 自身逻辑）
    bool ShouldClosePosition(const Signal &signal)
    {
        //  策略级退出（主动型）
        if(signal.type == SIGNAL_EXIT)
        {
            Print("[RiskPipeline] " + "[" + signal.source + "] Strategy exit accepted");
            position_risk.OnStrategyExit(); // 可选：用于统计
            return true;
        }

        //  基于 bar 的时间止损
        if(time_stop.ShouldClose())
        {
            Print("[RiskPipeline] TimeStop.ShouldClose() = true");
            return true;
        }

        // PositionRisk 补充的其他条件（当前是 MaxHoldMinutes）
        if(position_risk.ShouldForceClose())
        {
            Print("[RiskPipeline] PositionRisk.ShouldForceClose() = true");
            return true;
        }

        return false;
    }

    // 开仓/下单成功后，由 EA / TradeExecutor 调用
    void OnTradeExecuted()
    {
        // 记录持仓开始时间
        position_risk.OnPositionOpened();
        // 记录冷却开始时间
        cooldown.OnTrade();
    }

    // 平仓后由 EA 调用，内部自动算本次盈亏并更新连亏风控
    void OnPositionClosed()
    {
        double profit = GetLastClosedProfit_();

        // 连续止损风控
        losing_guard.OnTradeClosed(profit);

        // 时间冷却（如果你希望“每次交易后都进入冷却”）
        cooldown.OnTrade();
    }

    private:
    double GetLastClosedProfit_()   // 私有：真正从历史里取最近一笔盈亏
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