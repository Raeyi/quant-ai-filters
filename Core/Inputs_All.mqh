#ifndef __INPUTS_ALL_MQH__
#define __INPUTS_ALL_MQH__

//=====================================================================
//                        统一输入参数管理
//  按 4 大模块分组：公用 / 风控 / BollMR / TrendPullback
//=====================================================================

//+--------------------------------------------------------------------
//|                        【公用设置】
//+--------------------------------------------------------------------
input group "========== 公用设置 =========="

//--- 策略选择 ---
input group "策略选择"
input string BollMRVariant = "trend_pullback"; // 策略变体 (base/rsi/time/rsi_time/enhanced/trend_pullback/combo)

//--- 面板/模板 ---
input group "面板与模板"
input bool   ApplyTemplateOnInit = true;       // 附加EA时加载模板
input bool   ApplyTemplateOnce = true;         // 仅首次加载模板
input bool   ClearTemplateOnceOnRemove = true; // EA移除时清理"仅一次"标记
input string TemplateName = "zz_bb_rsi.tpl";   // 模板文件名 (Profiles/Templates)

//--- 周期设置 ---
input group "周期设置"
input bool            ForceTimeframeOnInit = true;     // 附加EA时自动切换周期
input ENUM_TIMEFRAMES TargetTimeframe = PERIOD_M5;     // 目标周期
input bool            AlertOnTimeframeChange = true;   // 周期变化提示
input bool            DisableOnTimeframeChange = true; // 周期变化后禁用EA
input bool            ReloadOnTimeframeChange = false; // 周期变化后移除EA
input bool            AutoRevertTimeframe = false;     // 周期变化后自动切回目标周期

//--- 交易提示 ---
input group "交易提示"
input bool AlertOnOrderOpen  = true;   // 开仓提示
input bool AlertOnOrderClose = true;   // 平仓提示
input bool AlertOnOrderFail  = true;   // 下单/平仓失败提示

//--- 缺口冷却 ---
input group "缺口处理"
input int  GapCooldownBars = 5;        // 发现停盘缺口后跳过的bar数量


//+--------------------------------------------------------------------
//|                        【风控设置】
//+--------------------------------------------------------------------
input group "========== 风控设置 =========="

//--- 仓位控制 ---
input group "仓位控制"
input double InpRiskPercent = 1.0;     // 每单风险占权益百分比 (%)

//--- 持仓控制 ---
input group "持仓控制"
input int    MaxHoldingBars = 5;       // 最大持仓时间 (bar数, 0=不限)
input int    CooldownSeconds = 60;     // 每次交易后冷却时间 (秒, 0=不冷却)

//--- 连亏保护 ---
input group "连亏保护"
input int    MaxLosingStreak = 3;      // 连续亏损次数阈值
input int    CooldownBarsAfter = 5;    // 触发后冷却的bar数

//--- 日亏损限制 ---
input group "日亏损限制"
input double MAX_DAILY_LOSS_PERCENT = 5.0; // 最大日亏损百分比 (%)


//+--------------------------------------------------------------------
//|                        【BollMR 策略参数】
//+--------------------------------------------------------------------
input group "========== BollMR 策略 =========="

//--- 布林带基础参数 ---
input group "BollMR.布林带"
input int    BollMR_BollPeriod  = 18;  // 布林带周期 (优化: 20→18)
input double BollMR_BollDev     = 2.0; // 布林带标准差
input int    BollMR_ATRPeriod   = 14;  // ATR 周期
input double BollMR_StructATRSL = 0.8; // 结构止损 ATR 倍数
input double BollMR_VolATRSL    = 2.0; // 波动止损 ATR 倍数
input double BollMR_ATRVolLimit = 1.5; // ATR 波动过滤倍数

//--- RSI 过滤 ---
input group "BollMR.RSI过滤"
input int    BollMR_RSIPeriod     = 14;   // RSI 周期
input double BollMR_RSIOverbought = 70.0; // RSI 超买阈值 (做空过滤)
input double BollMR_RSIOversold   = 30.0; // RSI 超卖阈值 (做多过滤)

//--- 时间过滤 ---
input group "BollMR.时间过滤"
input string BollMR_TimeMode = "session";   // 时间模式: session/custom
input string BollMR_Session  = "europe,us"; // 交易时段 (优化: overlap→europe,us 覆盖2-20点)
input int    BollMR_ServerUTCOffset = 2;    // MT5 服务器 UTC 偏移 (小时)
input bool   BollMR_UseDST = false;         // 手动夏令时开关
input int    BollMR_DSTShiftHours = 1;      // DST 平移小时数
input int    BollMR_StartHour = 2;          // 自定义开始时间 (北京时间, 优化: 8→2)
input int    BollMR_EndHour   = 20;         // 自定义结束时间 (北京时间, 优化: 16→20)

//--- 增强参数 ---
input group "BollMR.增强参数"
input int    BollMR_ShortestClosingTime = 10;  // 最短持仓时间 (秒)
input double BollMR_MidATRTP           = 0.2;  // 中轨止盈 ATR 倍数
input double BollMR_MidATRTP2          = 0.5;  // 中轨止盈2 ATR 倍数
input double BollMR_PartialExit1       = 0.5;  // 第一层部分平仓比例
input double BollMR_PartialExit2       = 0.25; // 第二层部分平仓比例
input double BollMR_UplowATRTP         = 0.1;  // 上/下轨止盈 ATR 倍数
input int    BollMR_MAPeriod           = 50;   // MA 周期
input string BollMR_EntryMode          = "A";  // 入场模式: A/B/C
input bool   BollMR_LogSignalDetails   = true; // 记录信号详情
input int    BollMR_Slope_Abs          = 150;  // 斜率绝对值阈值


//+--------------------------------------------------------------------
//|                     【TrendPullback 策略参数】
//+--------------------------------------------------------------------
input group "========== TrendPullback 策略 =========="

//--- 高时间框架 (趋势方向) ---
input group "TP.高时间框架"
input ENUM_TIMEFRAMES TP_HTF    = PERIOD_M15;  // 高时间框架 (方向)
input int   TP_EMA50_Period     = 50;          // EMA50 周期
input int   TP_EMA200_Period    = 200;         // EMA200 周期
input bool  TP_UseVWAP_HTF      = true;        // 使用 VWAP 辅助判断

//--- 低时间框架 (入场) ---
input group "TP.低时间框架"
input ENUM_TIMEFRAMES TP_LTF    = PERIOD_M5;   // 低时间框架 (入场)
input int   TP_EMA20_Period     = 20;          // EMA20 周期
input bool  TP_UseVWAP_LTF      = true;        // 使用 VWAP 作为价值区
input double TP_ValueZoneATR    = 0.5;         // 价值区容差 (ATR倍数)
input int   TP_PullbackBars     = 5;           // 回撤确认K线数

//--- 结构分析 ---
input group "TP.结构分析"
input int   TP_Structure_Lookback = 20;        // 结构回看周期
input bool  TP_RequireBreak     = true;        // 要求突破回撤结构点
input double TP_PullbackDepthATR = 0.5;        // 回撤深度上限 (ATR倍数, 优化: 0.618→0.5)

//--- 止损止盈 ---
input group "TP.止损止盈"
input int   TP_ATR_Period       = 14;          // ATR 周期
input double TP_ATR_SL_Multi    = 1.5;         // 初始止损 ATR 倍数
input double TP_PartialExit1_ATR  = 1.5;       // 第一层部分平仓触发 (ATR倍数)
input double TP_PartialExit1_Ratio = 0.35;     // 第一层平仓比例 (%)
input double TP_BE_OffsetATR      = -0.2;      // 保本止损偏移 (ATR倍数)
input double TP_TrailATR_Multi    = 2.5;       // Trailing Stop ATR倍数
input bool  TP_EnableTrailing     = true;      // 启用 Trailing Stop

//--- 时间过滤 ---
input group "TP.时间过滤"
input string TP_Session          = "europe,us,overlap"; // 交易时段 (优化: 扩展至欧美盘)
input bool   TP_TimeFilterEntry  = true;         // 入场时间过滤
input bool   TP_TimeExitEndSession = true;       // 时段结束时平仓

//--- 冷却机制 ---
input group "TP.冷却机制"
input bool   TP_EnableCooldown   = true;         // 启用结构冷却器
input int    TP_CooldownBars     = 3;            // 冷却K线数
input int    TP_MaxCooldownBars  = 12;           // 最大冷却K线数(强制解除)
input int    TP_FastFailBars     = 5;            // 快速失败判定K线数
input double TP_MinMomentumATR   = 0.5;          // 最小动量要求 (ATR倍数)
input double TP_StructureUpgradeATR = 0.5;       // 结构升级距离 (ATR倍数)

//--- 加仓策略 ---
input group "TP.加仓策略"
input bool   TP_EnableAddPosition = true;        // 启用加仓
input double TP_Add1_Ratio       = 0.4;          // 第一次加仓比例 (%)
input double TP_Add2_Ratio       = 0.25;         // 第二次加仓比例 (%)
input double TP_Add2_ProfitATR   = 2.0;          // 第二次加仓盈利要求 (ATR倍数)
input double TP_MaxTotalRisk     = 2.5;          // 最大总风险 (R倍数)

//--- 日志 ---
input group "TP.日志"
input bool   TP_LogSignalDetails = true;         // 详细日志


//+--------------------------------------------------------------------
//|                     【DonchianBreakout 策略参数】
//+--------------------------------------------------------------------
input group "========== DonchianBreakout 策略 =========="

//--- 通道参数 ---
input group "Donchian.通道"
input int    Donchian_Period = 20;               // Donchian 通道周期
input int    Donchian_EMA_Fast = 55;             // 快速 EMA 周期
input int    Donchian_EMA_Slow = 144;            // 慢速 EMA 周期

//--- ATR 止损止盈 ---
input group "Donchian.ATR止损止盈"
input int    Donchian_ATR_Period = 14;           // ATR 周期
input double Donchian_ATR_SL_Mult = 1.5;         // 止损 ATR 倍数
input double Donchian_ATR_TP_Mult = 2.2;         // 止盈 ATR 倍数
input int    Donchian_ATR_Avg_Period = 30;       // ATR 均值周期（波动扩张判断）
input double Donchian_ATR_Exp_Ratio = 1.0;       // ATR 扩张比例阈值

//--- 时间过滤 ---
input group "Donchian.时间过滤"
input int    Donchian_US_Start_Hour = 20;        // 美盘开始小时 (北京时间)
input int    Donchian_US_Start_Min = 30;         // 美盘开始分钟
input int    Donchian_US_End_Hour = 23;          // 美盘结束小时 (北京时间)
input int    Donchian_US_End_Min = 30;           // 美盘结束分钟
input bool   Donchian_Enable_Euro = false;       // 启用欧盘观察模式
input bool   Donchian_Enable_Asian = false;      // 启用亚盘试错模式

//--- 其他 ---
input group "Donchian.其他"
input bool   Donchian_Enable_Trailing = true;    // 启用 Donchian 拖尾止损
input bool   Donchian_LogSignalDetails = true;   // 详细日志


#endif // __INPUTS_ALL_MQH__
