//+------------------------------------------------------------------+
//|                     Strategy_SmartMoney.mqh                      |
//|              Smart Money Concept Strategy (SMC)                  |
//|     跨周期结构交易: HTF BOS/OB + LTF 入场确认                      |
//+------------------------------------------------------------------+

#ifndef __STRATEGY_SMART_MONEY_MQH__
#define __STRATEGY_SMART_MONEY_MQH__

#include "../Core/Strategy.mqh"
#include "../Core/Inputs_All.mqh"

//--- SMC 参数（从 Inputs_All.mqh 引入或在此定义）
input group "SMC 策略参数"
input ENUM_TIMEFRAMES   SMC_HTF = PERIOD_M15;          // 大周期：寻找OB和BOS
input ENUM_TIMEFRAMES   SMC_LTF = PERIOD_M1;           // 小周期：入场确认
input int               SMC_LookbackBOS = 20;          // BOS 结构突破回溯K线数
input double            SMC_MinBodyATR = 1.2;          // 爆发K线实体需大于多少倍ATR
input int               SMC_ZoneExpireBars = 48;       // 区位有效时间 (HTF K线数量)
input int               SMC_ATRPeriod = 14;            // ATR 周期
input double            SMC_SL_ATR_Buffer = 0.5;       // 止损在OB边缘外的ATR缓冲
input double            SMC_TP_RR = 3.5;               // 止盈盈亏比
input double            SMC_PartialPercent = 50.0;     // 部分平仓比例 (%)
input double            SMC_BE_RR_Level = 1.0;         // 达到几倍盈亏比时执行保本
input int               SMC_BE_Plus_Points = 25;       // 保本位偏移点数
input double            SMC_TrailStartATR = 2.0;       // 移动止损触发ATR倍数
input double            SMC_TrailStepATR = 1.0;        // 移动止损距离ATR倍数

//--- Smart Zone 结构体
struct SmartZone
{
    double top;              // 区域顶部
    double bottom;           // 区域底部
    ENUM_ORDER_TYPE type;    // 交易方向
    bool active;             // 是否有效
    datetime setupTime;      // 形成时间
    bool partial_done;       // 是否已执行部分平仓
    double entry_price;      // 入场价（用于RR计算）
    double initial_sl;       // 初始止损（用于RR计算）
};

//+------------------------------------------------------------------+
//| Strategy_SmartMoney - 聪明钱策略                                  |
//+------------------------------------------------------------------+
class Strategy_SmartMoney : public IStrategy
{
private:
    // 指标句柄
    int m_htf_atr_handle;
    int m_ltf_atr_handle;
    
    // 状态
    SmartZone m_current_zone;
    datetime m_last_htf_time;
    ulong m_exit_ticket;
    int m_exit_stage;
    double m_trailing_stop;
    
    // 退出信号
    double m_exit_volume;
    double m_sl_on_exit;

public:
    Strategy_SmartMoney() : 
        m_htf_atr_handle(INVALID_HANDLE),
        m_ltf_atr_handle(INVALID_HANDLE),
        m_last_htf_time(0),
        m_exit_ticket(0),
        m_exit_stage(0),
        m_trailing_stop(0),
        m_exit_volume(0),
        m_sl_on_exit(0)
    {
        m_current_zone.active = false;
    }
    
    ~Strategy_SmartMoney()
    {
        if(m_htf_atr_handle != INVALID_HANDLE)
            IndicatorRelease(m_htf_atr_handle);
        if(m_ltf_atr_handle != INVALID_HANDLE)
            IndicatorRelease(m_ltf_atr_handle);
    }
    
    bool Init() override
    {
        // 初始化 ATR 句柄
        m_htf_atr_handle = iATR(_Symbol, SMC_HTF, SMC_ATRPeriod);
        m_ltf_atr_handle = iATR(_Symbol, SMC_LTF, SMC_ATRPeriod);
        
        if(m_htf_atr_handle == INVALID_HANDLE || m_ltf_atr_handle == INVALID_HANDLE)
        {
            Print("[SmartMoney] ATR 句柄初始化失败");
            return false;
        }
        
        m_current_zone.active = false;
        m_last_htf_time = 0;
        
        Print("[SmartMoney] 策略初始化成功 | HTF=", EnumToString(SMC_HTF), " LTF=", EnumToString(SMC_LTF));
        return true;
    }
    
    bool UpdateIndicators() override
    {
        // SMC 策略使用跨周期数据，不需要每tick更新
        return true;
    }
    
    string Name() override
    {
        return "SmartMoney";
    }
    
    //+------------------------------------------------------------------+
    //| Tick 级别检查 - 每个 tick 都调用                                  |
    //| 用于 HTF zone 更新、LTF 入场确认、退出信号检测                     |
    //+------------------------------------------------------------------+
    Signal TickCheck()
    {
        Signal signal;
        signal.type = SIGNAL_NONE;
        signal.bypass_regime_filter = true;
        
        // 1. 检查退出信号（优先级最高）
        if(HasExitSignal(signal))
        {
            return signal;
        }
        
        // 2. HTF 新K线时更新 Zone
        datetime current_htf_time = iTime(_Symbol, SMC_HTF, 0);
        if(current_htf_time != m_last_htf_time)
        {
            UpdateHTFZone();
            m_last_htf_time = current_htf_time;
        }
        
        // 3. LTF 入场确认
        if(m_current_zone.active)
        {
            CheckLTFEntry(signal);
        }
        
        return signal;
    }
    
    // SMC 策略不需要 regime 过滤
    // bypass_regime_filter = true 在 TickCheck 中设置
    
    Signal GenerateSignal(Signal &signal) override
    {
        // 复用 TickCheck 的逻辑
        Signal result = TickCheck();
        signal = result;
        return signal;
    }

private:
    //+------------------------------------------------------------------+
    //| HTF Zone 更新 (BOS + OB 检测)                                     |
    //+------------------------------------------------------------------+
    void UpdateHTFZone()
    {
        MqlRates rates[];
        ArraySetAsSeries(rates, true);
        if(CopyRates(_Symbol, SMC_HTF, 0, 50, rates) < 50) return;
        
        double atr[];
        ArraySetAsSeries(atr, true);
        if(CopyBuffer(m_htf_atr_handle, 0, 0, 50, atr) < 50) return;
        
        // 看涨检测（原始逻辑：不看 currentZone.active，允许覆盖旧 zone）
        bool isBull = (rates[1].close > rates[1].open) && 
                      (rates[1].close - rates[1].open > SMC_MinBodyATR * atr[1]);
        
        if(isBull && !m_current_zone.active)
        {
            int hIdx = iHighest(_Symbol, SMC_HTF, MODE_HIGH, SMC_LookbackBOS, 3);
            if(hIdx >= 0 && rates[1].high > rates[hIdx].high)  // BOS
            {
                // 找 OB：BOS前的反向K线
                for(int i = 2; i < 8; i++)
                {
                    if(rates[i].close < rates[i].open)  // 阴线
                    {
                        m_current_zone.top = rates[i].high;
                        m_current_zone.bottom = rates[i].low;
                        m_current_zone.type = ORDER_TYPE_BUY;
                        m_current_zone.active = true;
                        m_current_zone.setupTime = rates[0].time;
                        m_current_zone.partial_done = false;
                        Print("[SmartMoney] 发现看涨 OB 区域: ", 
                              DoubleToString(m_current_zone.top, _Digits), " - ",
                              DoubleToString(m_current_zone.bottom, _Digits));
                        break;
                    }
                }
            }
        }
        
        // 看跌检测
        bool isBear = (rates[1].close < rates[1].open) && 
                      (rates[1].open - rates[1].close > SMC_MinBodyATR * atr[1]);
        
        if(isBear && !m_current_zone.active)
        {
            int lIdx = iLowest(_Symbol, SMC_HTF, MODE_LOW, SMC_LookbackBOS, 3);
            if(lIdx >= 0 && rates[1].low < rates[lIdx].low)  // BOS
            {
                for(int i = 2; i < 8; i++)
                {
                    if(rates[i].close > rates[i].open)  // 阳线
                    {
                        m_current_zone.top = rates[i].high;
                        m_current_zone.bottom = rates[i].low;
                        m_current_zone.type = ORDER_TYPE_SELL;
                        m_current_zone.active = true;
                        m_current_zone.setupTime = rates[0].time;
                        m_current_zone.partial_done = false;
                        Print("[SmartMoney] 发现看跌 OB 区域: ",
                              DoubleToString(m_current_zone.top, _Digits), " - ",
                              DoubleToString(m_current_zone.bottom, _Digits));
                        break;
                    }
                }
            }
        }
    }
    
    //+------------------------------------------------------------------+
    //| LTF 入场确认                                                      |
    //+------------------------------------------------------------------+
    void CheckLTFEntry(Signal &signal)
    {
        // 入场前检查：已有持仓则不入场（原始逻辑）
        if(PositionSelect(_Symbol))
        {
            return;
        }
        
        // 检查 Zone 失效
        datetime currentTime = TimeCurrent();
        if((currentTime - m_current_zone.setupTime) > SMC_HTF * 60 * SMC_ZoneExpireBars)
        {
            m_current_zone.active = false;
            return;
        }
        
        // 获取 LTF 数据
        MqlRates ltf[];
        ArraySetAsSeries(ltf, true);
        if(CopyRates(_Symbol, SMC_LTF, 0, 2, ltf) < 2) return;
        
        double latr[];
        ArraySetAsSeries(latr, true);
        if(CopyBuffer(m_ltf_atr_handle, 0, 0, 2, latr) < 2) return;
        
        // 看涨入场
        if(m_current_zone.type == ORDER_TYPE_BUY)
        {
            // 价格触及 OB 顶部以下 + LTF 前一根收阳（恢复原始逻辑）
            if(ltf[0].low <= m_current_zone.top && 
                ltf[0].low >= m_current_zone.bottom &&
               ltf[1].close > ltf[1].open)
            {
                double sl = m_current_zone.bottom - (latr[1] * SMC_SL_ATR_Buffer);
                double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                double risk = MathAbs(entry - sl);
                double tp = entry + risk * SMC_TP_RR;
                
                FillSignal(signal, SIGNAL_BUY, entry, sl, tp);
                m_current_zone.entry_price = entry;
                m_current_zone.initial_sl = sl;
                
                Print("[SmartMoney] 看涨入场信号 | Entry=", DoubleToString(entry, _Digits),
                      " SL=", DoubleToString(sl, _Digits), " TP=", DoubleToString(tp, _Digits));
                
                m_current_zone.active = false;  // 入场后 Zone 失效
            }
            // 深度打穿失效
            if(ltf[0].low < m_current_zone.bottom - (latr[1] * 2))
            {
                m_current_zone.active = false;
                Print("[SmartMoney] 看涨 OB 深度打穿失效");
            }
        }
        // 看跌入场
        else if(m_current_zone.type == ORDER_TYPE_SELL)
        {
            // 价格触及 OB 底部以上 + LTF 前一根收阴（恢复原始逻辑）
            if(ltf[0].high >= m_current_zone.bottom && 
               ltf[0].high <= m_current_zone.top &&
               ltf[1].close < ltf[1].open)
            {
                double sl = m_current_zone.top + (latr[1] * SMC_SL_ATR_Buffer);
                double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                double risk = MathAbs(entry - sl);
                double tp = entry - risk * SMC_TP_RR;
                
                FillSignal(signal, SIGNAL_SELL, entry, sl, tp);
                m_current_zone.entry_price = entry;
                m_current_zone.initial_sl = sl;
                
                Print("[SmartMoney] 看跌入场信号 | Entry=", DoubleToString(entry, _Digits),
                      " SL=", DoubleToString(sl, _Digits), " TP=", DoubleToString(tp, _Digits));
                
                m_current_zone.active = false;
            }
            if(ltf[0].high > m_current_zone.top + (latr[1] * 2))
            {
                m_current_zone.active = false;
                Print("[SmartMoney] 看跌 OB 深度打穿失效");
            }
        }
    }
    
    //+------------------------------------------------------------------+
    //| 退出信号检测                                                      |
    //+------------------------------------------------------------------+
    bool HasExitSignal(Signal &signal)
    {
        if(!PositionSelect(_Symbol))
        {
            m_exit_ticket = 0;
            m_exit_stage = 0;
            m_trailing_stop = 0;
            m_current_zone.partial_done = false;
            return false;
        }
        
        ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
        double current_volume = PositionGetDouble(POSITION_VOLUME);
        double entry = PositionGetDouble(POSITION_PRICE_OPEN);
        double sl = PositionGetDouble(POSITION_SL);
        double current = PositionGetDouble(POSITION_PRICE_CURRENT);
        long type = PositionGetInteger(POSITION_TYPE);
        
        // 新仓位初始化
        if(ticket != m_exit_ticket)
        {
            m_exit_ticket = ticket;
            m_exit_stage = 0;
            m_trailing_stop = 0;
            m_current_zone.partial_done = false;
        }
        
        // 获取 LTF ATR
        double latr[];
        ArraySetAsSeries(latr, true);
        if(CopyBuffer(m_ltf_atr_handle, 0, 0, 1, latr) < 1) return false;
        
        // RR 计算
        double initialRisk = MathAbs(entry - (m_current_zone.initial_sl > 0 ? m_current_zone.initial_sl : sl));
        if(initialRisk <= 0) return false;
        
        double currentProfit = (type == POSITION_TYPE_BUY) ? (current - entry) : (entry - current);
        double currentRR = currentProfit / initialRisk;
        
        // 1. RR 达到触发 → 部分平仓 + 保本
        if(currentRR >= SMC_BE_RR_Level && !m_current_zone.partial_done)
        {
            double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            double closeLot = NormalizeDouble(current_volume * (SMC_PartialPercent / 100.0), 2);
            
            if(closeLot >= minLot && current_volume > minLot)
            {
                m_exit_volume = closeLot;
                m_current_zone.partial_done = true;
                
                // 保本位
                double beLevel = (type == POSITION_TYPE_BUY) ? 
                    (entry + SMC_BE_Plus_Points * _Point) : 
                    (entry - SMC_BE_Plus_Points * _Point);
                m_sl_on_exit = beLevel;
                
                signal.type = SIGNAL_EXIT;
                signal.exit_volume = m_exit_volume;
                signal.sl_on_exit = m_sl_on_exit;
                signal.source = Name();
                signal.confidence = 0.80;  // 退出信号高置信度
                signal.bypass_regime_filter = true;
                
                Print("[SmartMoney] RR=", DoubleToString(currentRR, 2), 
                      " 触发部分平仓 ", DoubleToString(m_exit_volume, 2), " 手 | 保本位=",
                      DoubleToString(beLevel, _Digits));
                
                return true;
            }
        }
        
        // 2. 移动止损
        if(SMC_TrailStartATR > 0)
        {
            double triggerDist = latr[0] * SMC_TrailStartATR;
            double stepDist = latr[0] * SMC_TrailStepATR;
            
            if(type == POSITION_TYPE_BUY && currentProfit > triggerDist)
            {
                double newSL = NormalizeDouble(current - stepDist, _Digits);
                if(newSL > m_trailing_stop + _Point * 20)
                {
                    m_trailing_stop = newSL;
                }
                // 触发移动止损平仓
                if(current <= m_trailing_stop && m_trailing_stop > 0)
                {
                    signal.type = SIGNAL_EXIT;
                    signal.exit_volume = current_volume;
                    signal.source = Name();
                    signal.confidence = 0.90;  // 移动止损触发，高置信度
                    signal.bypass_regime_filter = true;
                    Print("[SmartMoney] 移动止损触发全平 | 价格=", DoubleToString(current, _Digits));
                    return true;
                }
            }
            else if(type == POSITION_TYPE_SELL && currentProfit > triggerDist)
            {
                double newSL = NormalizeDouble(current + stepDist, _Digits);
                if(m_trailing_stop == 0 || newSL < m_trailing_stop - _Point * 20)
                {
                    m_trailing_stop = newSL;
                }
                if(current >= m_trailing_stop && m_trailing_stop > 0)
                {
                    signal.type = SIGNAL_EXIT;
                    signal.exit_volume = current_volume;
                    signal.source = Name();
                    signal.confidence = 0.90;  // 移动止损触发，高置信度
                    signal.bypass_regime_filter = true;
                    Print("[SmartMoney] 移动止损触发全平 | 价格=", DoubleToString(current, _Digits));
                    return true;
                }
            }
        }
        
        return false;
    }
    
    //+------------------------------------------------------------------+
    //| 填充信号结构                                                      |
    //+------------------------------------------------------------------+
    void FillSignal(Signal &signal, SignalType type, double price = 0, double sl = 0, double tp = 0)
    {
        signal.type = type;
        signal.source = Name();
        signal.time = TimeCurrent();
        signal.price = (price > 0) ? price : SymbolInfoDouble(_Symbol, SYMBOL_BID);
        signal.sl = sl;
        signal.tp = tp;
        signal.confidence = 0.75;  // BOS + OB + LTF 确认组合，中等偏高置信度
        signal.bypass_regime_filter = true;  // SMC 不受 regime 过滤
    }
};

#endif // __STRATEGY_SMART_MONEY_MQH__
