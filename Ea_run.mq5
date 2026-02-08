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

//  UI 状态面板
#include "Core/UI/StatusPanel.mqh"

// 特征导出（如果还需要）
// #include "Utils/Export.mqh"

//---------------- 全局对象 ----------------
StrategyManager     manager; // 策略管理器
Strategy_BollMR     boll; // Bollinger 均值回归策略

TradeExecutor       executor; // 交易执行器
RiskPipeline        risk_pipeline; // 风控管道
PositionCoordinator pos_coord; // 单品种单向一仓

AIDecisionGateway   ai_gateway; // AI 决策网关
ConfidenceFilter    conf_filter; // 置信度过滤器

StatusPanel status_panel; // 状态面板

// 指标导出文件句柄（如果需要导出 features）
int g_file = INVALID_HANDLE;
int g_signal_file = INVALID_HANDLE;
int g_signal_pos = 0;

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

   status_panel.Init(); // 初始化状态面板

   // 1. 策略管理器：挂上 Bollinger 策略
   manager.Add(&boll);

   // 2. 初始化策略
    if(!boll.Init())
    {
        Print("Failed to initialize BollMR strategy");
        return INIT_FAILED;
    }
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

   g_signal_file = FileOpen("signals_mt5.csv",
                            FILE_WRITE | FILE_CSV | FILE_COMMON | FILE_SHARE_WRITE);
   if(g_signal_file != INVALID_HANDLE)
   {
      FileWrite(g_signal_file, "time","signal","source");
      Print("Signals file opened.");
   }
   else
   {
      Print("Signals file open failed: ", GetLastError());
   }

   Print("EA Init finished");
   return INIT_SUCCEEDED;
}

//---------------- Tick 驱动 ----------------
void OnTick()
{
   // 只在新 bar 上做决策
   if(!IsNewBar())
      return;

   // 指标数据更新
   if(!boll.UpdateIndicators())
   {
      return;
   }

   // 指标调试输出（可选）
   // Print("BollLower0=", GetBollLower(0), " BollLower1=", GetBollLower(1),
   //       " ATR1=", GetATR(1));

   pos_coord.SyncFromTerminal(); // 同步仓位状态

   Signal signal; // 声明信号变量
   signal = manager.GetSignal(); // 获取策略信号

   if(signal.type == SIGNAL_BUY)
      g_signal_pos = 1;
   else if(signal.type == SIGNAL_SELL)
      g_signal_pos = -1;
   else if(signal.type == SIGNAL_EXIT)
      g_signal_pos = 0;

   if(g_signal_file != INVALID_HANDLE)
   {
      FileWrite(g_signal_file,
                TimeToString(iTime(_Symbol, _Period, 1), TIME_DATE|TIME_SECONDS),
                g_signal_pos,
                signal.source);
   }

   if(pos_coord.HasPosition()) // 如果当前有仓位，先检查是否需要平仓
   {
      bool should_close = risk_pipeline.ShouldClosePosition(signal);
      if(should_close) //需要平仓
      {
         bool closed = false;

         if(signal.type == SIGNAL_EXIT && signal.exit_volume > 0.0)
         {
            double pos_vol = PositionGetDouble(POSITION_VOLUME);
            double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
            double min_vol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            double close_vol = MathMin(signal.exit_volume, pos_vol);

            if(close_vol >= pos_vol - step * 0.5)
               closed = executor.Close();
            else if(close_vol >= min_vol)
               closed = executor.ClosePartial(close_vol);
            else
               closed = executor.Close();
         }
         else
         {
            closed = executor.Close();
         }

         if(closed)
         {
            if(!PositionSelect(_Symbol))
            {
               risk_pipeline.OnPositionClosed();  // 只有当仓位确实关闭后才调用这个函数，防止误判
               pos_coord.OnPositionClosed();      // 更新仓位协调器状态
            }
            else
            {
               pos_coord.SyncFromTerminal();
            }
         }
         else
         {
            Print("[EA] ", signal.source, " Failed to close position when requested.");
         }
      }
   }

   if(signal.type != SIGNAL_NONE && signal.type != SIGNAL_EXIT) // 如果有开仓信号
   {
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
               if(executor.Execute(req, signal.source))
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

   // 5. 特征导出（如果你还想保留）
   if(g_file != INVALID_HANDLE)
   {
      double close  = iClose(_Symbol, _Period, 1);    // 上一根收盘价
      double bu     = GetBollUpper(0);
      double bl     = GetBollLower(0);
      double atr1   = GetATR(1);

      FileWrite(g_file,
                TimeToString(iTime(_Symbol, _Period, 1), TIME_DATE|TIME_SECONDS),
                DoubleToString(close,_Digits),
                DoubleToString(bu,_Digits),
                DoubleToString(bl,_Digits),
                DoubleToString(atr1,_Digits));
   }

   status_panel.Update(risk_pipeline, pos_coord); // 更新状态面板
}

//---------------- 反初始化 ----------------
void OnDeinit(const int reason)
{
   if(g_file != INVALID_HANDLE)
      FileClose(g_file);
   if(g_signal_file != INVALID_HANDLE)
      FileClose(g_signal_file);
}

