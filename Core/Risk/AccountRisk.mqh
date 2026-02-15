//+------------------------------------------------------------------+
//|                          Risk/AccountRisk.mqh                    |
//|                   Account Risk definition                        |
//+                 账户风险定义 = 账户级别限制（防爆仓）             +
//+------------------------------------------------------------------+

#ifndef __RISK_ACCOUNT_RISK_MQH__
#define __RISK_ACCOUNT_RISK_MQH__

// 输入参数定义在 Inputs_All.mqh，此文件不再重复声明
#include "../Inputs_All.mqh"

class AccountRisk
{
private:
    double maxDailyLoss;  // 最大日亏损比例
    double startBalance; // 日初余额
    datetime dayStart;  // 日初时间
    bool m_limit_warned; // 是否已警告过日亏损限制

public:
    AccountRisk() : m_limit_warned(false) {}

    void Init()
    {
        maxDailyLoss = MAX_DAILY_LOSS_PERCENT / 100.0;
        startBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        dayStart = iTime(_Symbol, PERIOD_D1, 0);
        m_limit_warned = false;  // 新的一天重置警告状态
    }

    bool AllowTrading()
    {
        // 跨天重置
        datetime curDay = iTime(_Symbol, PERIOD_D1, 0);
        if(curDay != dayStart)
            Init();

        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        double loss   = (startBalance - equity) / startBalance;

        if(loss >= maxDailyLoss)
        {
            // 只在首次触发时打印警告
            if(!m_limit_warned)
            {
                m_limit_warned = true;
                Print("[AccountRisk] Daily loss limit reached: ",
                      DoubleToString(loss*100,2), "%");
            }
            return false;
        }

        return true;
    }
};

#endif// __RISK_ACCOUNT_RISK_MQH__
