#ifndef __INPUTS_BOLLMR_MQH__
#define __INPUTS_BOLLMR_MQH__

// 统一管理 BollMR 相关输入参数（避免 base/rsi/enhanced 重复显示）

input group "BollMR.Base"
input int    BollMR_BollPeriod  = 20;  // 布林带周期
input double BollMR_BollDev     = 2.0; // 布林带标准差
input int    BollMR_ATRPeriod   = 14;  // ATR 周期
input double BollMR_StructATRSL = 0.8; // 结构止损 ATR 倍数
input double BollMR_VolATRSL    = 2.0; // 波动止损 ATR 倍数
input double BollMR_ATRVolLimit = 1.5; // ATR 波动过滤倍数

input group "BollMR.RSI"
input int    BollMR_RSIPeriod     = 14;   // RSI 周期
input double BollMR_RSIOverbought = 70.0; // RSI 超买阈值（做空过滤）
input double BollMR_RSIOversold   = 30.0; // RSI 超卖阈值（做多过滤）

input group "BollMR.TimeFilter"
input string BollMR_TimeMode = "session"; // session / custom
input string BollMR_Session  = "overlap"; // 支持逗号分隔：asia, europe, us, overlap, europe+us
input int    BollMR_ServerUTCOffset = 2;  // MT5 服务器 UTC 偏移（小时）
input bool   BollMR_UseDST = false;       // 手动夏令时开关（欧/美盘 +1 小时）
input int    BollMR_DSTShiftHours = 1;    // DST 平移小时数
input int    BollMR_StartHour = 8;        // 自定义开始时间（北京时间）
input int    BollMR_EndHour   = 16;       // 自定义结束时间（北京时间）

input group "BollMR.Enhanced"
input int    BollMR_ShortestClosingTime = 10;  // 最短持仓时间（秒）
input double BollMR_MidATRTP           = 0.2;  // 中轨止盈 ATR 倍数
input double BollMR_MidATRTP2          = 0.5;  // 中轨止盈2 ATR 倍数
input double BollMR_PartialExit1       = 0.5;  // 第一层部分平仓比例
input double BollMR_PartialExit2       = 0.25; // 第二层部分平仓比例
input double BollMR_UplowATRTP         = 0.1;  // 上/下轨止盈 ATR 倍数
input int    BollMR_MAPeriod           = 50;   // MA 周期
input string BollMR_EntryMode          = "A";  // 入场模式：A / B / C
input bool   BollMR_LogSignalDetails   = true; // 仅在信号生成时打印关键信息

#endif // __INPUTS_BOLLMR_MQH__
