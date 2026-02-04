//+------------------------------------------------------------------+
//|                     Ea_run.mq5                                   |
//|   多策略 + 风控管道 + AI Filter + Bollinger/ATR 指标初始化与更新   |
//+------------------------------------------------------------------+
#property strict
#property description "StrategyManager + BollMR + RiskPipeline + AI Filter"

// 标准库
#include <Trade/Trade.mqh>
#include <Files/File.mqh>

// 指标
#include "Indicators/Bollinger.mqh"
#include "Indicators/ATR.mqh"

// 核心结构
#include "Core/Signal.mqh"
#include "Core/TradeTypes.mqh"

// 策略 & 管理
#include "Core/Strategy.mqh"
#include "Core/StrategyManager.mqh"
#include "Strategies/Strategy_BollMR.mqh"

// 执行 & 风控
#include "Core/TradeExecutor.mqh"
#include "Core/Risk/RiskPipeline.mqh"
#include "Core/PositionCoordinator.mqh"

// AI 决策网关
#include "Core/IAIFilter.mqh"
#include "Core/ConfidenceFilter.mqh"
#include "Core/AIDecisionGateway.mqh"

// 特征导出（如果还需要）
// #include "Utils/Export.mqh"

//---------------- 输入参数 ----------------
input int    InpCooldownBars  = 5;    // 冷却周期（bar 数，后续可接入 Cooldown）
input int    BollPeriod       = 20;   // 布林带周期
input double BollDev          = 2.0;  // 布林带标准差
input int    ATRPeriod        = 14;   // ATR 周期

//---------------- 全局对象 ----------------
StrategyManager     manager;
Strategy_BollMR     boll;

TradeExecutor       executor;
RiskPipeline        risk_pipeline;
PositionCoordinator pos_coord;

AIDecisionGateway   ai_gateway;
ConfidenceFilter    conf_filter;

// 指标导出文件句柄（如果需要导出 features）
int g_file = INVALID_HANDLE;

//---------------- 新 bar 检测（沿用你旧 EA 的） ----------------
bool IsNewBar()
{
   static datetime lastBar = 0;
   datetime barTime = iTime(_Symbol, _Period, 0);
   if(barTime != lastBar)
   {
      lastBar = barTime;
      return true;
   }
   return false;
}

//---------------- 初始化 ----------------
int OnInit()
{
   Print("EA Init start");

   // 1. 指标初始化
   if(!InitBollinger(BollPeriod, BollDev))
   {
      Print("Bollinger init failed");
      return INIT_FAILED;
   }

   if(!InitATR(ATRPeriod))
   {
      Print("ATR init failed");
      return INIT_FAILED;
   }

   Print("Indicators init OK");

   // 2. 策略管理器：挂上 Bollinger 策略
   manager.Add(&boll);

   // 3. 风控管道初始化
   risk_pipeline.Init();

   // 4. AI 决策网关：挂上一个简单的置信度过滤器
   ai_gateway.AddFilter(&conf_filter);

   // 5. 仓位协调器与真实终端同步（防止 EA 重启时状态不一致）
   pos_coord.SyncFromTerminal();

   // 6. 如果需要导出特征，就打开文件
   g_file = FileOpen("features.csv",
                     FILE_WRITE | FILE_CSV | FILE_COMMON | FILE_SHARE_WRITE);
   if(g_file != INVALID_HANDLE)
   {
      FileWrite(g_file, "time","close","boll_u","boll_l","atr");
      Print("Feature file opened.");
   }
   else
   {
      Print("Feature file open failed: ", GetLastError());
      // 不影响交易，可以不 return FAILED
   }

   Print("EA Init finished");
   return INIT_SUCCEEDED;
}

//---------------- Tick 驱动 ----------------
void OnTick()
{
   // 0. 只在新 bar 上做决策（沿用你原逻辑）
   if(!IsNewBar())
      return;

   // 1. 每个 bar 更新指标缓存（这一步是之前缺失的关键）
   if(!UpdateBollinger())
   {
      Print("UpdateBollinger FAILED");
      return;
   }

   if(!UpdateATR(50))   // 取最近 50 根，足够你用 shift 0/1 和平均
   {
      Print("UpdateATR FAILED");
      return;
   }

   // 指标调试输出（可选）
   // Print("BollLower0=", GetBollLower(0), " BollLower1=", GetBollLower(1),
   //       " ATR1=", GetATR(1));

   // 2. 同步当前仓位状态
   pos_coord.SyncFromTerminal();

   // 3. 策略层获取信号
   Signal signal;
   if(manager.GetSignal(signal))
   {
      Print("[EA] Got signal: type=", signal.type,
            " price=", DoubleToString(signal.price,_Digits),
            " source=", signal.source,
            " conf=", DoubleToString(signal.confidence,2));

      // 3.1 多策略冲突仲裁：单品种单向一仓
      if(!pos_coord.AllowSignal(signal))
      {
         Print("[EA] PositionCoordinator rejected signal from ", signal.source);
         // 即便有信号，当前有仓位或不允许冲突，就直接退出
      }
      else
      {
         // 3.2 AI 决策网关过滤
         double ai_score = 1.0;
         if(!ai_gateway.Pass(signal, ai_score))
         {
            Print("[EA] AIDecisionGateway rejected signal from ", signal.source);
         }
         else
         {
            // 3.3 风控构建 TradeRequest
            TradeRequest req;
            if(risk_pipeline.BuildTrade(signal, req))
            {
               Print("[EA] BuildTrade OK. dir=",
                     (req.direction==TRADE_BUY?"BUY":"SELL"),
                     " vol=", DoubleToString(req.volume,2),
                     " sl=", DoubleToString(req.sl,_Digits),
                     " tp=", DoubleToString(req.tp,_Digits));

               // 3.4 执行下单
               if(executor.Execute(req))
               {
                  Print("[EA] Order executed.");
                  risk_pipeline.OnTradeExecuted();
                  pos_coord.OnPositionOpened(signal);
               }
            }
            else
            {
               Print("[EA] RiskPipeline.BuildTrade returned false");
            }
         }
      }
   }
   // else
   //    Print("[EA] No strategy signal on this bar");

   // 4. 持仓期间平仓判断
   if(risk_pipeline.ShouldClosePosition())
   {
      if(executor.Close())
      {
         risk_pipeline.OnPositionClosed();  // 通知 RiskPipeline 有一笔平仓
         pos_coord.OnPositionClosed();      // 仓位协调器更新状态
      }
   }

   // 5. 特征导出（如果你还想保留）
   if(g_file != INVALID_HANDLE)
   {
      double close  = iClose(_Symbol, _Period, 1);    // 上一根收盘价
      double bu     = GetBollUpper(0);
      double bl     = GetBollLower(0);
      double atr1   = GetATR(1);

      FileWrite(g_file,
                TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
                DoubleToString(close,_Digits),
                DoubleToString(bu,_Digits),
                DoubleToString(bl,_Digits),
                DoubleToString(atr1,_Digits));
   }
}

//---------------- 反初始化 ----------------
void OnDeinit(const int reason)
{
   if(g_file != INVALID_HANDLE)
      FileClose(g_file);
}
