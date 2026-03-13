//+------------------------------------------------------------------+
//|                                     SmartMoney_MTF_Pro_V6.mq5    |
//|                                  跨周期 SMC: M15(BOS+OB) + M1(Entry) |
//+------------------------------------------------------------------+
#property copyright "surra"
#property version   "6.00"
#property strict

#include <Trade\Trade.mqh>

#define MAX_ZONES 5

//--- 输入参数
input group "周期设置"
input ENUM_TIMEFRAMES InpHTF = PERIOD_M15;     // 大周期：寻找OB和FVG
input ENUM_TIMEFRAMES InpLTF = PERIOD_M1;      // 小周期：寻找确认信号

input group "SMC 核心参数"
input int      InpLookbackBOS = 20;            // BOS 结构突破回溯K线数
input double   InpMinBodyATR = 1.2;            // 爆发K线实体需大于多少倍ATR
input double   InpMinGapPoints = 50.0;         // 最小FVG缺口点数
input int      InpZoneExpireBars = 48;         // 区位有效时间 (HTF K线数量)
input int      InpAtrPeriod = 14;              // ATR 周期

input group "风险管理"
input double   InpLotSize = 0.02;              // 建议至少0.02以便分批平仓
input double   InpTP_RR = 3.5;                 // 最终止盈盈亏比
input double   InpSL_ATR_Buffer = 0.5;         // 止损在OB边缘外的ATR缓冲

input group "分批平仓与保本 (新)"
input bool     InpUsePartialClose = true;      // 是否开启分批平仓
input double   InpPartialClosePercent = 50.0;  // 平仓比例 (%)
input double   InpBE_RR_Level = 1.0;           // 达到几倍盈亏比时执行保本
input int      InpBE_Plus_Points = 25;         // 保本位往利润方向多挪多少点(抵消手续费)

input group "移动止损"
input bool     InpUseTrailing = true;          // 是否开启移动止损
input double   InpTrailStartATR = 2.0;         // 盈利达到多少倍ATR开启
input double   InpTrailStepATR = 1.0;          // 跟随距离(ATR)

input group "风控与通用"
input int      InpMaxSpread = 50;              // 最大点差 (黄金建议50)
input int      InpMaxTradesDay = 3;            // 每日最大交易次数
input double   InpMaxLossDay = 300.0;          // 每日最大亏损额
input int      InpMagic = 20260311;
input string   InpComment = "SMC_MTF_V6";

input group "面板设置"
input bool     InpShowPanel = true;            // 显示状态面板
input int      InpPanelX = 10;                 // 面板 X 坐标
input int      InpPanelY = 30;                 // 面板 Y 坐标
input color    InpPanelBgColor = clrBlack;     // 面板背景色
input color    InpPanelBorderColor = clrDodgerBlue; // 面板边框色
input int      InpPanelFontSize = 9;           // 面板字体大小

//--- 结构体定义
struct SmartZone {
    double top;
    double bottom;
    double fvgGap;
    ENUM_ORDER_TYPE type;
    bool active;
    datetime setupTime;
};

//--- 全局变量
CTrade      trade;
int         htfAtrHandle;
int         ltfAtrHandle;
datetime    lastHTFTime;
SmartZone   zones[MAX_ZONES];

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
int OnInit() {
    htfAtrHandle = iATR(_Symbol, InpHTF, InpAtrPeriod);
    ltfAtrHandle = iATR(_Symbol, InpLTF, InpAtrPeriod);
    if(htfAtrHandle == INVALID_HANDLE || ltfAtrHandle == INVALID_HANDLE) {
        Print("ATR句柄初始化失败");
        return INIT_FAILED;
    }
    
    trade.SetExpertMagicNumber(InpMagic);
    
    // 初始化区位数组
    for(int i = 0; i < MAX_ZONES; i++) {
        zones[i].active = false;
    }
    
    // 初始化面板（先删除旧对象再创建）
    if(InpShowPanel) {
        PanelDelete();
        PanelInit();
    }
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Deinit                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    // 清理面板
    if(InpShowPanel) {
        PanelDelete();
    }
}

//+------------------------------------------------------------------+
//| 主逻辑                                                            |
//+------------------------------------------------------------------+
void OnTick() {

    // 1. 实时管理：移动止损、分批平仓、保本
    HandlePositionManagement();

    // 2. 检测大周期 (HTF) 新信号，生成或更新区位
    datetime currentHTFTime = iTime(_Symbol, InpHTF, 0);
    if(currentHTFTime != lastHTFTime) {
        UpdateHTFZones();
        lastHTFTime = currentHTFTime;
    }

    // 3. 小周期入场确认
    if(HasActiveZone()) CheckLTFEntries();
    
    // 4. 更新面板
    if(InpShowPanel) {
        PanelUpdate();
    }
}

//+------------------------------------------------------------------+
//| 仓位管理：分批平仓 + 保本 + 移动止损                                |
//+------------------------------------------------------------------+
void HandlePositionManagement() {
    for(int i = PositionsTotal()-1; i >= 0; i--) {
        if(PositionGetTicket(i) && PositionGetInteger(POSITION_MAGIC) == InpMagic) {
            ulong ticket = PositionGetTicket(i);
            double entry = PositionGetDouble(POSITION_PRICE_OPEN);
            double sl = PositionGetDouble(POSITION_SL);
            double tp = PositionGetDouble(POSITION_TP);
            double current = PositionGetDouble(POSITION_PRICE_CURRENT);
            double volume = PositionGetDouble(POSITION_VOLUME);
            long type = PositionGetInteger(POSITION_TYPE);

            // 获取小周期ATR用于计算移动止损
            double ltfAtr[];
            ArraySetAsSeries(ltfAtr, true);
            CopyBuffer(ltfAtrHandle, 0, 0, 1, ltfAtr);

            // --- A. 分批平仓与移动保本 ---
            double initialRisk = MathAbs(entry - sl);
            if(initialRisk > 0 && sl != 0) {
                double currentProfit = (type == POSITION_TYPE_BUY) ? (current - entry) : (entry - current);
                double currentRR = currentProfit / initialRisk;

                // 达到触发倍数 且 仓位还是初始大小（表示尚未分批平仓）
                if(currentRR >= InpBE_RR_Level && volume >= InpLotSize) {
                    // 1. 执行分批平仓 (如果手数够分)
                    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
                    double closeLot = NormalizeDouble(volume * (InpPartialClosePercent / 100.0), 2);
                    
                    if(InpUsePartialClose && volume > minLot && closeLot >= minLot) {
                        trade.PositionClosePartial(ticket, closeLot);
                    }

                    // 2. 移动止损至保本位 (Entry + 偏移)
                    double beLevel = (type == POSITION_TYPE_BUY) ? (entry + InpBE_Plus_Points * _Point) : (entry - InpBE_Plus_Points * _Point);
                    
                    // 只有当新止损位更优时才修改
                    if((type == POSITION_TYPE_BUY && beLevel > sl) || (type == POSITION_TYPE_SELL && (beLevel < sl || sl == 0))) {
                        trade.PositionModify(ticket, NormalizeDouble(beLevel, _Digits), tp);
                        Print("执行保本修改: Ticket #", ticket);
                    }
                }
            }

            // --- B. 移动止损 (Trailing Stop) ---
            if(InpUseTrailing) {
                double triggerDist = ltfAtr[0] * InpTrailStartATR;
                double stepDist = ltfAtr[0] * InpTrailStepATR;
                
                if(type == POSITION_TYPE_BUY && (current - entry) > triggerDist) {
                    double newSL = NormalizeDouble(current - stepDist, _Digits);
                    if(newSL > sl + _Point * 20) trade.PositionModify(ticket, newSL, tp);
                }
                else if(type == POSITION_TYPE_SELL && (entry - current) > triggerDist) {
                    double newSL = NormalizeDouble(current + stepDist, _Digits);
                    if(newSL < sl - _Point * 20 || sl == 0) trade.PositionModify(ticket, newSL, tp);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| HTF 信号扫描 (BOS + FVG + OB)                                     |
//+------------------------------------------------------------------+
void UpdateHTFZones() {
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if(CopyRates(_Symbol, InpHTF, 0, 50, rates) < 50) return;

    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(htfAtrHandle, 0, 0, 50, atr) < 50) return;

    // --- A. 判定看涨信号 (Bullish) ---
    // 1. 严格 FVG 缺口计算: Bar 2 的高点 到 Bar 0 的低点
    double bullGapPoints = (rates[0].low - rates[2].high) / _Point;
    bool isBullGap = (rates[2].high < rates[0].low) && (bullGapPoints >= InpMinGapPoints);
    
    // 2. 动能爆发判定
    bool isBullImpulse = (rates[1].close > rates[1].open) && 
                         (rates[1].close - rates[1].open > InpMinBodyATR * atr[1]);

    if(isBullGap && isBullImpulse) {
        // 3. BOS 严谨判定：必须收盘突破前期的波段高点 (排除影线假突破)
        int hIdx = iHighest(_Symbol, InpHTF, MODE_HIGH, InpLookbackBOS, 3);
        if(rates[1].close > rates[hIdx].high) {
            
            // 4. 寻找 OB 并加入数组
            for(int i=2; i<8; i++) {
                if(rates[i].close < rates[i].open) {
                    AddNewZone(rates[i].high, rates[i].low, ORDER_TYPE_BUY, bullGapPoints);
                    break; // 找到最近的一个 OB 即停止
                }
            }
        }
    }

    // --- B. 判定看跌信号 (Bearish) - 修正了之前的逻辑不对称 ---
    // 1. 严格 FVG 缺口计算: Bar 2 的低点 到 Bar 0 的高点
    double bearGapPoints = (rates[2].low - rates[0].high) / _Point;
    bool isBearGap = (rates[2].low > rates[0].high) && (bearGapPoints >= InpMinGapPoints);

    bool isBearImpulse = (rates[1].close < rates[1].open) && 
                         (rates[1].open - rates[1].close > InpMinBodyATR * atr[1]);

    if(isBearGap && isBearImpulse) {
        // 3. BOS 严谨判定：必须收盘跌破前期波段低点
        int lIdx = iLowest(_Symbol, InpHTF, MODE_LOW, InpLookbackBOS, 3);
        if(rates[1].close < rates[lIdx].low) {
            
            for(int i=2; i<8; i++) {
                if(rates[i].close > rates[i].open) {
                    AddNewZone(rates[i].high, rates[i].low, ORDER_TYPE_SELL, bearGapPoints);
                    break;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| 辅助函数：将新区位推入数组 (最新在 0 索引)                        |
//+------------------------------------------------------------------+
void AddNewZone(double top, double bottom, ENUM_ORDER_TYPE type, double gapPoints) {
    // 将旧区位往后移，自动丢弃最老的区位
    for(int i = MAX_ZONES - 1; i > 0; i--) {
        zones[i] = zones[i-1];
    }
    
    zones[0].top = top;
    zones[0].bottom = bottom;
    zones[0].fvgGap = gapPoints;
    zones[0].type = type;
    zones[0].active = true;
    zones[0].setupTime = TimeCurrent();
    
    string typeStr = (type == ORDER_TYPE_BUY) ? "看涨" : "看跌";
    Print("发现新 ", typeStr, " 区位! 顶部: ", top, " 底部: ", bottom, " FVG缺口: ", gapPoints, "点");
}

//+------------------------------------------------------------------+
//| 优化部分 3：小周期 (M1) 轮询活跃区位入场                          |
//+------------------------------------------------------------------+
void CheckLTFEntries() {
    if(PositionSelectByMagic(InpMagic) || !CheckRiskManagement()) return;

    MqlRates ltf[];
    ArraySetAsSeries(ltf, true);
    CopyRates(_Symbol, InpLTF, 0, 3, ltf);
    
    double latr[];
    ArraySetAsSeries(latr, true);
    CopyBuffer(ltfAtrHandle, 0, 0, 2, latr);

    // 遍历所有区位，看是否有被触发的
    for(int i = 0; i < MAX_ZONES; i++) {
        if(!zones[i].active) continue;

        // A. 超时失效判定
        if((TimeCurrent() - zones[i].setupTime) > InpHTF * 60 * InpZoneExpireBars) {
            zones[i].active = false; continue;
        }

        // B. 严谨的区间入场逻辑
        if(zones[i].type == ORDER_TYPE_BUY) {
            // 失效：如果收盘价跌破 OB 底部
            if(ltf[0].close < zones[i].bottom) { zones[i].active = false; continue; }
            
            // 触发：价格进入了 OB 内部 (修正：不仅触碰顶部，还要在底部之上)
            bool isInside = (ltf[0].low <= zones[i].top && ltf[0].close >= zones[i].bottom);
            // 确认：M1 收阳线 (之后我们会升级为 MSS)
            bool reversal = (ltf[1].close > ltf[1].open); 

            if(isInside && reversal) {
                double sl = zones[i].bottom - (latr[1] * InpSL_ATR_Buffer);
                double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK); // 多单开仓价
                
                // 1. 预计算这笔单子的潜在亏损金额
                double riskAmount = CalculateRiskAmount(entry, sl, InpLotSize);
                
                // 2. 将潜在亏损丢进风控系统进行“沙盘推演”
                if(CheckRiskManagement(riskAmount)) {
                    // 3. 风控绿灯，执行下单！
                    ExecuteOrder(ORDER_TYPE_BUY, sl);
                } else {
                    // 风控红灯，放弃该区位
                    Print("因触及风控底线，放弃该 M15 黄金坑区位的做多机会。");
                }
                
                zones[i].active = false; // 无论是否下单，该区位都视为已被消耗
                break;
            }
        }
        else if(zones[i].type == ORDER_TYPE_SELL) {
            if(ltf[0].close > zones[i].top) { zones[i].active = false; continue; }
            
            bool isInside = (ltf[0].high >= zones[i].bottom && ltf[0].close <= zones[i].top);
            bool reversal = (ltf[1].close < ltf[1].open);

            if(isInside && reversal) {
                double sl = zones[i].top + (latr[1] * InpSL_ATR_Buffer);
                double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID); 
                double riskAmount = CalculateRiskAmount(entry, sl, InpLotSize);

                if(CheckRiskManagement(riskAmount)) {
                    ExecuteOrder(ORDER_TYPE_SELL, sl);
                } else {
                    Print("因触及风控底线，放弃该 M15 黄金坑区位的做空机会。");
                }

                zones[i].active = false;
                break;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| 执行交易                                                         |
//+------------------------------------------------------------------+
void ExecuteOrder(ENUM_ORDER_TYPE type, double sl) {
    double entry = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double risk = MathAbs(entry - sl);
    double tp = (type == ORDER_TYPE_BUY) ? (entry + risk * InpTP_RR) : (entry - risk * InpTP_RR);

    if(!trade.PositionOpen(_Symbol, type, InpLotSize, entry, 
                          NormalizeDouble(sl, _Digits), 
                          NormalizeDouble(tp, _Digits), InpComment)) {
        Print("下单失败: ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| 每日风控检查                                                      |
//+------------------------------------------------------------------+
bool CheckRiskManagement(double potentialRiskAmount = 0.0) {
    datetime todayStart = iTime(_Symbol, PERIOD_D1, 0);
    HistorySelect(todayStart, TimeCurrent());
    
    int dealsCount = HistoryDealsTotal();
    double currentDailyProfit = 0;
    int tradesCount = 0;

    // 统计今天已经平仓的盈亏和交易次数
    for(int i = 0; i < dealsCount; i++) {
        ulong ticket = HistoryDealGetTicket(i);
        if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagic) {
            currentDailyProfit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
            // 只统计出场(平仓)的 deal 来计算交易次数
            if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT) tradesCount++;
        }
    }

    // 1. 检查交易次数是否超标
    if(tradesCount >= InpMaxTradesDay) {
        Print("风控拦截：今日交易次数已达上限 ", InpMaxTradesDay, " 次");
        return false; 
    }
    
    // 2. 核心修复：已实现利润 - 即将承担的亏损风险 是否打穿底线？
    if(currentDailyProfit - potentialRiskAmount <= -InpMaxLossDay) {
        Print("风控拦截！今日已结盈亏: ", currentDailyProfit, 
              " 刀，若开仓将增加潜在亏损: ", potentialRiskAmount, 
              " 刀，总计将超每日限额: -", InpMaxLossDay, " 刀");
        return false;
    }

    return true;
}

bool PositionSelectByMagic(long magic) {
    for(int i=PositionsTotal()-1; i>=0; i--) {
        if(PositionGetTicket(i) && PositionGetInteger(POSITION_MAGIC) == magic) return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| 计算若触发止损将亏损的精确金额 (美元)                               |
//+------------------------------------------------------------------+
double CalculateRiskAmount(double entryPrice, double slPrice, double lotSize) {
    // 获取品种的最小跳动点大小和每跳价值
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    
    if(tickSize == 0) return 0.0; // 防止除以 0 报错

    // 计算止损距离了多少个 Tick
    double riskTicks = MathAbs(entryPrice - slPrice) / tickSize;
    
    // 亏损金额 = 跳动次数 * 每跳价值 * 手数
    double riskAmount = riskTicks * tickValue * lotSize;
    
    return riskAmount;
}

//+------------------------------------------------------------------+
//| 面板功能                                                          |
//+------------------------------------------------------------------+
string PANEL_PREFIX = "SMC_PANEL_";
int PANEL_WIDTH = 280;
int PANEL_HEIGHT = 295;
int PANEL_LINE_SPACING = 14;

// 创建背景
void PanelInit() {
    // 强制删除所有旧面板对象
    ObjectsDeleteAll(0, PANEL_PREFIX);
    
    string bg = PANEL_PREFIX + "BG";
    ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, InpPanelX);
    ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, InpPanelY);
    ObjectSetInteger(0, bg, OBJPROP_XSIZE, PANEL_WIDTH);
    ObjectSetInteger(0, bg, OBJPROP_YSIZE, PANEL_HEIGHT);
    ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, InpPanelBgColor);
    ObjectSetInteger(0, bg, OBJPROP_COLOR, InpPanelBorderColor);
    ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, bg, OBJPROP_BACK, false);
    ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
    
    // 创建标签并立即设置初始文本
    string labels[] = {"TITLE", "TIME", "SYMBOL", "TIMEFRAME", "ZONE_INFO", 
                       "ZONE_COUNT", "POSITION", "FLOAT_PNL", "TODAY_TRADES", 
                       "TODAY_PNL", "SPREAD", "RISK_STATUS", "STATUS"};
    string initTexts[] = {"=== SMC SmartMoney ===", "Time: --", "Symbol: --", 
                          "TF: --", "Zone: None", "Active Zones: 0/5",
                          "Position: None", "Floating PnL: $0.00", 
                          "Today Trades: 0/3", "Today PnL: $0.00", 
                          "Spread: 0 pts", "Risk: OK", "Status: Waiting Signal"};
    
    for(int i = 0; i < ArraySize(labels); i++) {
        string obj = PANEL_PREFIX + labels[i];
        ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, InpPanelX + 10);
        ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, InpPanelY + 5 + i * PANEL_LINE_SPACING);
        ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, InpPanelFontSize);
        ObjectSetInteger(0, obj, OBJPROP_COLOR, clrWhite);
        ObjectSetString(0, obj, OBJPROP_FONT, "Consolas");
        ObjectSetString(0, obj, OBJPROP_TEXT, initTexts[i]);
    }
}

// 删除面板
void PanelDelete() {
    ObjectDelete(0, PANEL_PREFIX + "BG");
    string labels[] = {"TITLE", "TIME", "SYMBOL", "TIMEFRAME", "ZONE_INFO", 
                       "ZONE_COUNT", "POSITION", "FLOAT_PNL", "TODAY_TRADES", 
                       "TODAY_PNL", "SPREAD", "RISK_STATUS", "STATUS"};
    for(int i = 0; i < ArraySize(labels); i++) {
        ObjectDelete(0, PANEL_PREFIX + labels[i]);
    }
}

// 设置文本
void PanelSetText(string name, string text, color clr = clrWhite) {
    ObjectSetString(0, PANEL_PREFIX + name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, PANEL_PREFIX + name, OBJPROP_COLOR, clr);
}

// 计算活跃区域数量
int CountActiveZones() {
    int count = 0;
    for(int i = 0; i < MAX_ZONES; i++) {
        if(zones[i].active) count++;
    }
    return count;
}

// 检查是否有活跃区位
bool HasActiveZone() {
    for(int i = 0; i < MAX_ZONES; i++) {
        if(zones[i].active) return true;
    }
    return false;
}

// 获取当日交易次数
int GetTodayTrades() {
    datetime dayStart = iTime(_Symbol, PERIOD_D1, 0);
    HistorySelect(dayStart, TimeCurrent());
    int count = 0;
    for(int i = 0; i < HistoryDealsTotal(); i++) {
        ulong deal = HistoryDealGetTicket(i);
        if(HistoryDealGetInteger(deal, DEAL_MAGIC) == InpMagic) {
            long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
            if(entry == DEAL_ENTRY_IN || entry == DEAL_ENTRY_INOUT)
                count++;
        }
    }
    return count;
}

// 获取当日盈亏
double GetTodayPnL() {
    datetime dayStart = iTime(_Symbol, PERIOD_D1, 0);
    HistorySelect(dayStart, TimeCurrent());
    double pnl = 0;
    for(int i = 0; i < HistoryDealsTotal(); i++) {
        ulong deal = HistoryDealGetTicket(i);
        if(HistoryDealGetInteger(deal, DEAL_MAGIC) == InpMagic) {
            pnl += HistoryDealGetDouble(deal, DEAL_PROFIT);
            pnl += HistoryDealGetDouble(deal, DEAL_SWAP);
            pnl += HistoryDealGetDouble(deal, DEAL_COMMISSION);
        }
    }
    return pnl;
}

// 获取浮动盈亏
double GetFloatingPnL() {
    double pnl = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(PositionGetTicket(i) && PositionGetInteger(POSITION_MAGIC) == InpMagic) {
            pnl += PositionGetDouble(POSITION_PROFIT);
        }
    }
    return pnl;
}

// 检查是否有持仓
bool HasPosition() {
    return PositionSelectByMagic(InpMagic);
}

// 周期转字符串
string TFToString(ENUM_TIMEFRAMES tf) {
    switch(tf) {
        case PERIOD_M1:  return "M1";
        case PERIOD_M5:  return "M5";
        case PERIOD_M15: return "M15";
        case PERIOD_M30: return "M30";
        case PERIOD_H1:  return "H1";
        case PERIOD_H4:  return "H4";
        case PERIOD_D1:  return "D1";
    }
    return "Unknown";
}

// 更新面板
void PanelUpdate() {
    PanelSetText("TITLE", "=== SMC SmartMoney ===", InpPanelBorderColor);
    PanelSetText("TIME", "Time: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
    PanelSetText("SYMBOL", "Symbol: " + _Symbol);
    PanelSetText("TIMEFRAME", "TF: HTF=" + TFToString(InpHTF) + " LTF=" + TFToString(InpLTF));
    
    // 当前活跃区域信息（显示最新的活跃区位）
    int latestActiveIdx = -1;
    for(int i = 0; i < MAX_ZONES; i++) {
        if(zones[i].active) {
            latestActiveIdx = i;
            break;
        }
    }
    
    if(latestActiveIdx >= 0) {
        string typeStr = (zones[latestActiveIdx].type == ORDER_TYPE_BUY) ? "BULL" : "BEAR";
        color typeColor = (zones[latestActiveIdx].type == ORDER_TYPE_BUY) ? clrLime : clrRed;
        PanelSetText("ZONE_INFO", "Zone: " + typeStr + " [" + 
                     DoubleToString(zones[latestActiveIdx].top, 1) + " - " + 
                     DoubleToString(zones[latestActiveIdx].bottom, 1) + "]", typeColor);
    } else {
        PanelSetText("ZONE_INFO", "Zone: None", clrGray);
    }
    
    // 活跃区域数量
    int activeCount = CountActiveZones();
    PanelSetText("ZONE_COUNT", "Active Zones: " + IntegerToString(activeCount) + "/" + IntegerToString(MAX_ZONES),
                 activeCount > 0 ? clrLime : clrGray);
    
    // 持仓信息
    if(HasPosition()) {
        double vol = 0;
        double entry = 0;
        for(int i = PositionsTotal() - 1; i >= 0; i--) {
            if(PositionGetTicket(i) && PositionGetInteger(POSITION_MAGIC) == InpMagic) {
                vol = PositionGetDouble(POSITION_VOLUME);
                entry = PositionGetDouble(POSITION_PRICE_OPEN);
                break;
            }
        }
        PanelSetText("POSITION", "Position: " + DoubleToString(vol, 2) + " @ " + DoubleToString(entry, 2), clrLime);
    } else {
        PanelSetText("POSITION", "Position: None", clrGray);
    }
    
    // 浮动盈亏
    double floatPnL = GetFloatingPnL();
    color floatColor = (floatPnL >= 0) ? clrLime : clrRed;
    PanelSetText("FLOAT_PNL", "Floating PnL: $" + DoubleToString(floatPnL, 2), floatColor);
    
    // 当日交易数
    int todayTrades = GetTodayTrades();
    PanelSetText("TODAY_TRADES", "Today Trades: " + IntegerToString(todayTrades) + "/" + IntegerToString(InpMaxTradesDay),
                 todayTrades >= InpMaxTradesDay ? clrOrange : clrWhite);
    
    // 当日盈亏
    double todayPnL = GetTodayPnL();
    color todayColor = (todayPnL >= 0) ? clrLime : clrRed;
    PanelSetText("TODAY_PNL", "Today PnL: $" + DoubleToString(todayPnL, 2), todayColor);
    
    // 实时点差
    double spreadPoints = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
    int spreadInt = (int)(spreadPoints / _Point);
    color spreadColor = (spreadInt <= 30) ? clrLime : (spreadInt <= 50) ? clrOrange : clrRed;
    PanelSetText("SPREAD", "Spread: " + IntegerToString(spreadInt) + " pts", spreadColor);
    
    // 风控状态
    bool riskOk = CheckRiskManagement();
    PanelSetText("RISK_STATUS", "Risk: " + (riskOk ? "OK" : "LIMIT"),
                 riskOk ? clrLime : clrOrange);
    
    // 总状态
    string status = "Waiting Signal";
    color statusColor = clrWhite;
    if(HasPosition()) {
        status = "In Position";
        statusColor = clrLime;
    } else if(!riskOk) {
        status = "Risk Limit";
        statusColor = clrOrange;
    } else if(activeCount > 0) {
        status = "Monitoring Zone";
        statusColor = clrDodgerBlue;
    }
    PanelSetText("STATUS", "Status: " + status, statusColor);
}