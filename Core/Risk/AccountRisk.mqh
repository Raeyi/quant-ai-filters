//+------------------------------------------------------------------+
//|                          Risk/AccountRisk.mqh                       |
//|                   Account Risk definition                            |
//+                 账户风险定义 = 账户级别限制（防爆仓）            +
//+------------------------------------------------------------------+

#ifndef __RISK_ACCOUNT_RISK_MQH__
#define __RISK_ACCOUNT_RISK_MQH__

input double MAX_DAILY_LOSS_PERCENT = 5.0; // 最大日亏损百分比

class AccountRisk
{
private:
    double maxDailyLoss;  // 最大日亏损比例
    double startBalance; // 日初余额
    datetime dayStart;  // 日初时间

public:
    void Init()
    {
        maxDailyLoss = MAX_DAILY_LOSS_PERCENT / 100.0;
        startBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        dayStart = iTime(_Symbol, PERIOD_D1, 0);
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
            Print("[AccountRisk] Daily loss limit reached: ",
                  DoubleToString(loss*100,2), "%");
            return false;
        }

        return true;
    }
};

#endif// __RISK_ACCOUNT_RISK_MQH__