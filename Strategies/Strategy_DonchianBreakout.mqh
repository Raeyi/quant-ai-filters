//+------------------------------------------------------------------+
//|              Strategies/Strategy_DonchianBreakout.mqh            |
//|                   M9: Donchian 突破 + 波动过滤策略                  |
//|          核心思想：美盘高波动时段捕捉趋势突破                        |
//+------------------------------------------------------------------+

#ifndef __STRATEGY_DONCHIAN_BREAKOUT_MQH__
#define __STRATEGY_DONCHIAN_BREAKOUT_MQH__

#include "../Indicators/Donchian.mqh"
#include "../Indicators/ATR.mqh"
#include "../Indicators/MA.mqh"
#include "../Core/Strategy.mqh"
#include "../Core/Regime/RegimeTypes.mqh"
#include "../Core/Inputs_All.mqh"

//+------------------------------------------------------------------+
//| 策略输入参数（需要在 Inputs_All.mqh 中定义）                        |
//+------------------------------------------------------------------+
// M9: Donchian 突破策略参数
input int    Donchian_Period = 20;           // Donchian 通道周期
input int    Donchian_EMA_Fast = 55;         // 快速 EMA 周期
input int    Donchian_EMA_Slow = 144;        // 慢速 EMA 周期
input int    Donchian_ATR_Period = 14;       // ATR 周期
input double Donchian_ATR_SL_Mult = 1.5;     // 止损 ATR 倍数
input double Donchian_ATR_TP_Mult = 2.2;     // 止盈 ATR 倍数
input int    Donchian_ATR_Avg_Period = 30;   // ATR 均值周期（波动扩张判断）
input double Donchian_ATR_Exp_Ratio = 1.0;   // ATR 扩张比例阈值
input bool   Donchian_Enable_Trailing = true;// 启用 Donchian 拖尾止损
input bool   Donchian_LogSignalDetails = true;// 详细日志

// 美盘时段参数（北京时间）
input int    Donchian_US_Start_Hour = 20;    // 美盘开始小时
input int    Donchian_US_Start_Min = 30;     // 美盘开始分钟
input int    Donchian_US_End_Hour = 23;      // 美盘结束小时
input int    Donchian_US_End_Min = 30;       // 美盘结束分钟

// 多时段模式开关
input bool   Donchian_Enable_Euro = false;   // 启用欧盘观察模式
input bool   Donchian_Enable_Asian = false;  // 启用亚盘试错模式

//+------------------------------------------------------------------+
//| 策略类定义                                                         |
//+------------------------------------------------------------------+
class Strategy_DonchianBreakout : public IStrategy
{
private:
    // EMA 句柄（需要两个 EMA）
    int m_ema55_handle;
    int m_ema144_handle;
    double m_ema55_buffer[];
    double m_ema144_buffer[];
    
    // 持仓跟踪
    ulong m_trailing_ticket;
    double m_entry_donchian_low;   // 入场时的 Donchian 下轨（多头拖尾用）
    double m_entry_donchian_high;  // 入场时的 Donchian 上轨（空头拖尾用）
    
public:
    //+------------------------------------------------------------------
    // 构造函数
    //+------------------------------------------------------------------
    Strategy_DonchianBreakout() : IStrategy(),
        m_ema55_handle(INVALID_HANDLE),
        m_ema144_handle(INVALID_HANDLE),
        m_trailing_ticket(0),
        m_entry_donchian_low(0.0),
        m_entry_donchian_high(0.0)
    {
        ArraySetAsSeries(m_ema55_buffer, true);
        ArraySetAsSeries(m_ema144_buffer, true);
    }
    
    //+------------------------------------------------------------------
    // 策略名称
    //+------------------------------------------------------------------
    string Name() override
    {
        return "Donchian_Breakout";
    }
    
    //+------------------------------------------------------------------
    // 初始化
    //+------------------------------------------------------------------
    bool Init() override
    {
        // 初始化 Donchian 通道
        if(!InitDonchian(Donchian_Period))
        {
            Print("[", Name(), "] Failed to initialize Donchian indicator");
            return false;
        }
        
        // 初始化 ATR
        if(!InitATR(Donchian_ATR_Period))
        {
            Print("[", Name(), "] Failed to initialize ATR indicator");
            return false;
        }
        
        // 初始化 EMA55
        m_ema55_handle = iMA(_Symbol, _Period, Donchian_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
        if(m_ema55_handle == INVALID_HANDLE)
        {
            Print("[", Name(), "] Failed to initialize EMA55");
            return false;
        }
        
        // 初始化 EMA144
        m_ema144_handle = iMA(_Symbol, _Period, Donchian_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
        if(m_ema144_handle == INVALID_HANDLE)
        {
            Print("[", Name(), "] Failed to initialize EMA144");
            return false;
        }
        
        Print("[", Name(), "] Indicators initialized successfully");
        return true;
    }
    
    //+------------------------------------------------------------------
    // 更新指标
    //+------------------------------------------------------------------
    bool UpdateIndicators() override
    {
        // 更新 Donchian 通道
        if(!UpdateDonchian(Donchian_Period, 100))
        {
            Print("[", Name(), "] Failed to update Donchian");
            return false;
        }
        
        // 更新 ATR
        if(!UpdateATR(Donchian_ATR_Avg_Period + 10))
        {
            Print("[", Name(), "] Failed to update ATR");
            return false;
        }
        
        // 更新 EMA55
        int copied = CopyBuffer(m_ema55_handle, 0, 0, 50, m_ema55_buffer);
        if(copied <= 0)
        {
            Print("[", Name(), "] Failed to update EMA55");
            return false;
        }
        
        // 更新 EMA144
        copied = CopyBuffer(m_ema144_handle, 0, 0, 50, m_ema144_buffer);
        if(copied <= 0)
        {
            Print("[", Name(), "] Failed to update EMA144");
            return false;
        }
        
        return true;
    }
    
    //+------------------------------------------------------------------
    // 生成信号
    //+------------------------------------------------------------------
    Signal GenerateSignal(Signal &signal) override
    {
        // 检查是否有持仓
        if(PositionSelect(_Symbol))
        {
            // 有持仓，检查出场信号
            return GenerateExitSignal(signal);
        }
        else
        {
            // 无持仓，检查入场信号
            return GenerateEntrySignal(signal);
        }
    }
    
private:
    //+------------------------------------------------------------------
    // 时间过滤：美盘时段（北京时间 20:30-23:30）
    //+------------------------------------------------------------------
    bool TimeFilterOK()
    {
        // 获取服务器时间并转换为北京时间
        // 假设服务器时间是 UTC+2 或 UTC+3，需要调整
        datetime server_time = TimeCurrent();
        MqlDateTime dt;
        TimeToStruct(server_time, dt);
        
        int hour = dt.hour;
        int min = dt.min;
        
        // 转换为北京时间（假设服务器是 UTC+2）
        // 北京时间 = UTC+8 = 服务器时间 + 6
        int beijing_hour = (hour + 6) % 24;
        
        // 美盘时段检查（20:30 - 23:30 北京时间）
        int time_value = beijing_hour * 100 + min;
        int start_time = Donchian_US_Start_Hour * 100 + Donchian_US_Start_Min;
        int end_time = Donchian_US_End_Hour * 100 + Donchian_US_End_Min;
        
        // 美盘模式
        if(time_value >= start_time && time_value <= end_time)
            return true;
        
        // 欧盘模式（可选）
        if(Donchian_Enable_Euro)
        {
            // 15:00 - 20:30 北京时间
            if(time_value >= 1500 && time_value < start_time)
                return true;
        }
        
        // 亚盘模式（可选）
        if(Donchian_Enable_Asian)
        {
            // 其他时段
            if(time_value < 1500 || time_value > end_time)
                return true;
        }
        
        return false;
    }
    
    //+------------------------------------------------------------------
    // Sub-Type 过滤
    // Donchian 策略适合趋势类型：TVB_TREND, TN_MILD
    //+------------------------------------------------------------------
    bool IsSubTypeSuitable()
    {
        if(m_regime_filter == NULL)
            return true;
        
        RegimeSubType sub_type = m_regime_filter.GetSubType();
        
        switch(sub_type)
        {
            case SUBTYPE_TVB_TREND:    // 真趋势 - 最佳
            case SUBTYPE_TN_MILD:      // 温和趋势 - 可以
                return true;
            
            case SUBTYPE_TVA_EMOTION:  // 情绪脉冲 - 波动剧烈但不可靠
            case SUBTYPE_RN_NORMAL:    // 震荡 - 无趋势
            case SUBTYPE_RL_LOW:       // 低波动 - 动能不足
            case SUBTYPE_RVB_FALSE:    // 假突破密集 - 风险高
            case SUBTYPE_RVA_NEWS:     // 消息震荡 - 不可预测
                return false;
            
            default:
                return true;
        }
    }
    
    //+------------------------------------------------------------------
    // EMA 方向确认
    // 多头：价格 > EMA55 > EMA144 且 EMA55 斜率向上
    // 空头：价格 < EMA55 < EMA144 且 EMA55 斜率向下
    //+------------------------------------------------------------------
    bool IsBullishTrend()
    {
        if(ArraySize(m_ema55_buffer) < 5 || ArraySize(m_ema144_buffer) < 5)
            return false;
        
        double price = iClose(_Symbol, _Period, 1);  // 已收盘 K 线
        double ema55 = m_ema55_buffer[1];
        double ema144 = m_ema144_buffer[1];
        double ema55_prev = m_ema55_buffer[5];  // 5根前的 EMA55
        
        // 价格在 EMA 之上
        bool price_above = (price > ema55 && price > ema144);
        
        // EMA 多头排列
        bool ema_aligned = (ema55 > ema144);
        
        // EMA55 斜率向上
        bool slope_up = (ema55 > ema55_prev);
        
        return (price_above && ema_aligned && slope_up);
    }
    
    bool IsBearishTrend()
    {
        if(ArraySize(m_ema55_buffer) < 5 || ArraySize(m_ema144_buffer) < 5)
            return false;
        
        double price = iClose(_Symbol, _Period, 1);
        double ema55 = m_ema55_buffer[1];
        double ema144 = m_ema144_buffer[1];
        double ema55_prev = m_ema55_buffer[5];
        
        // 价格在 EMA 之下
        bool price_below = (price < ema55 && price < ema144);
        
        // EMA 空头排列
        bool ema_aligned = (ema55 < ema144);
        
        // EMA55 斜率向下
        bool slope_down = (ema55 < ema55_prev);
        
        return (price_below && ema_aligned && slope_down);
    }
    
    //+------------------------------------------------------------------
    // ATR 扩张过滤
    // 当前 ATR > ATR 均值 × 扩张比例
    //+------------------------------------------------------------------
    bool IsVolatilityExpanding()
    {
        double atr_now = GetATR(1);
        double atr_avg = GetATRMean(Donchian_ATR_Avg_Period, 1);
        
        if(atr_avg <= 0) return false;
        
        // ATR 扩张比例检查
        return (atr_now >= atr_avg * Donchian_ATR_Exp_Ratio);
    }
    
    //+------------------------------------------------------------------
    // 入场信号生成
    //+------------------------------------------------------------------
    Signal GenerateEntrySignal(Signal &signal)
    {
        // 时间过滤
        if(!TimeFilterOK())
        {
            signal.type = SIGNAL_NONE;
            return signal;
        }
        
        // Sub-Type 过滤
        if(!IsSubTypeSuitable())
        {
            signal.type = SIGNAL_NONE;
            return signal;
        }
        
        // 波动率扩张检查
        if(!IsVolatilityExpanding())
        {
            signal.type = SIGNAL_NONE;
            return signal;
        }
        
        double close = iClose(_Symbol, _Period, 1);
        double donchian_high = GetDonchianHigh(1);
        double donchian_low = GetDonchianLow(1);
        
        // 多头突破信号
        if(close > donchian_high && IsBullishTrend())
        {
            LogSignalDetails("BUY");
            FillSignal(signal, SIGNAL_BUY);
            Print("[Donchian] Long signal filled. price=", signal.price,
                  " sl=", signal.sl, " tp=", signal.tp,
                  " donchian_high=", donchian_high);
            return signal;
        }
        
        // 空头突破信号
        if(close < donchian_low && IsBearishTrend())
        {
            LogSignalDetails("SELL");
            FillSignal(signal, SIGNAL_SELL);
            Print("[Donchian] Short signal filled. price=", signal.price,
                  " sl=", signal.sl, " tp=", signal.tp,
                  " donchian_low=", donchian_low);
            return signal;
        }
        
        signal.type = SIGNAL_NONE;
        return signal;
    }
    
    //+------------------------------------------------------------------
    // 出场信号生成
    //+------------------------------------------------------------------
    Signal GenerateExitSignal(Signal &signal)
    {
        if(!PositionSelect(_Symbol))
        {
            signal.type = SIGNAL_NONE;
            return signal;
        }
        
        ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
        ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        double current_price = SymbolInfoDouble(_Symbol, pos_type == POSITION_TYPE_BUY ? SYMBOL_BID : SYMBOL_ASK);
        
        // 更新拖尾止损跟踪
        if(ticket != m_trailing_ticket)
        {
            m_trailing_ticket = ticket;
            // 初始化拖尾基准
            if(pos_type == POSITION_TYPE_BUY)
                m_entry_donchian_low = GetDonchianLow(1);
            else
                m_entry_donchian_high = GetDonchianHigh(1);
        }
        
        // Donchian 拖尾止损
        if(Donchian_Enable_Trailing)
        {
            if(pos_type == POSITION_TYPE_BUY)
            {
                // 多头：价格跌破 Donchian 下轨则出场
                double donchian_low = GetDonchianLow(1);
                if(current_price < donchian_low)
                {
                    Print("[Donchian] Trailing stop triggered for LONG. price=", current_price,
                          " donchian_low=", donchian_low);
                    signal.type = SIGNAL_EXIT;
                    signal.exit_volume = 0.0;  // 全平
                    FillSignal(signal, SIGNAL_EXIT);
                    return signal;
                }
            }
            else if(pos_type == POSITION_TYPE_SELL)
            {
                // 空头：价格突破 Donchian 上轨则出场
                double donchian_high = GetDonchianHigh(1);
                if(current_price > donchian_high)
                {
                    Print("[Donchian] Trailing stop triggered for SHORT. price=", current_price,
                          " donchian_high=", donchian_high);
                    signal.type = SIGNAL_EXIT;
                    signal.exit_volume = 0.0;
                    FillSignal(signal, SIGNAL_EXIT);
                    return signal;
                }
            }
        }
        
        // 时间出场：超过美盘时段则平仓
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        int beijing_hour = (dt.hour + 6) % 24;
        int time_value = beijing_hour * 100 + dt.min;
        int end_time = Donchian_US_End_Hour * 100 + Donchian_US_End_Min;
        
        if(time_value > end_time && !Donchian_Enable_Asian)
        {
            Print("[Donchian] Time-based exit. hour=", beijing_hour);
            signal.type = SIGNAL_EXIT;
            signal.exit_volume = 0.0;
            FillSignal(signal, SIGNAL_EXIT);
            return signal;
        }
        
        signal.type = SIGNAL_NONE;
        return signal;
    }
    
    //+------------------------------------------------------------------
    // 填充信号结构
    //+------------------------------------------------------------------
    void FillSignal(Signal &s, SignalType type)
    {
        s.type = type;
        s.source = Name();
        s.time = TimeCurrent();
        s.confidence = 1.0;
        
        if(type == SIGNAL_EXIT)
        {
            s.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            return;
        }
        
        s.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double atr = GetATR(1);
        
        if(type == SIGNAL_BUY)
        {
            // 止损：入场价 - ATR × 系数
            s.sl = NormalizeDouble(s.price - atr * Donchian_ATR_SL_Mult, _Digits);
            // 止盈：入场价 + ATR × 系数
            s.tp = NormalizeDouble(s.price + atr * Donchian_ATR_TP_Mult, _Digits);
            
            // 记录入场时的 Donchian 下轨用于拖尾
            m_entry_donchian_low = GetDonchianLow(1);
        }
        else if(type == SIGNAL_SELL)
        {
            s.sl = NormalizeDouble(s.price + atr * Donchian_ATR_SL_Mult, _Digits);
            s.tp = NormalizeDouble(s.price - atr * Donchian_ATR_TP_Mult, _Digits);
            
            m_entry_donchian_high = GetDonchianHigh(1);
        }
    }
    
    //+------------------------------------------------------------------
    // 日志输出
    //+------------------------------------------------------------------
    void LogSignalDetails(const string direction)
    {
        if(!Donchian_LogSignalDetails)
            return;
        
        MqlDateTime ts;
        TimeToStruct(TimeCurrent(), ts);
        
        double close = iClose(_Symbol, _Period, 1);
        double donchian_high = GetDonchianHigh(1);
        double donchian_low = GetDonchianLow(1);
        double atr = GetATR(1);
        double ema55 = m_ema55_buffer[1];
        double ema144 = m_ema144_buffer[1];
        
        Print("[Donchian] Signal ", direction,
              " time=", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
              " close=", DoubleToString(close, _Digits),
              " donchian_high=", DoubleToString(donchian_high, _Digits),
              " donchian_low=", DoubleToString(donchian_low, _Digits),
              " atr=", DoubleToString(atr, _Digits),
              " ema55=", DoubleToString(ema55, _Digits),
              " ema144=", DoubleToString(ema144, _Digits),
              " hour=", ts.hour);
    }
};

#endif // __STRATEGY_DONCHIAN_BREAKOUT_MQH__
