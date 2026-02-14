//+------------------------------------------------------------------+
//|                     Ea_run.mq5                                   |
//|   多策略 + 风控管道 + AI Filter + Bollinger/ATR 指标初始化与更新   |
//+------------------------------------------------------------------+
#property strict
#property description "StrategyManager + BollMR + RiskPipeline + AI Filter"

// 标准库
#include <Trade/Trade.mqh>
#include <Files/File.mqh>

// 版本管理
#include "Core/Version.mqh"

// 统一输入参数（必须在其他模块之前引入）
#include "Core/Inputs_All.mqh"

// 指标
#include "Indicators/Bollinger.mqh"
#include "Indicators/ATR.mqh"

// 核心结构
#include "Core/Signal.mqh"
#include "Core/TradeTypes.mqh"

// 策略 & 管理
#include "Core/Strategy.mqh"
#include "Core/StrategyManager.mqh"
#include "Strategies/Strategy_BollMR_enhanced.mqh"
#include "Strategies/Strategy_BollMR_Base.mqh"
#include "Strategies/Strategy_BollMR_RSI.mqh"
#include "Strategies/Strategy_BollMR_Time.mqh"
#include "Strategies/Strategy_BollMR_RSI_Time.mqh"
#include "Strategies/Strategy_TrendPullback.mqh"
#include "Strategies/Strategy_Combo.mqh"

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
Strategy_BollMR     boll_enhanced; // Bollinger 均值回归策略（增强版）
Strategy_BollMR_Base boll_base;    // Bollinger 均值回归策略（基线版）
Strategy_BollMR_RSI  boll_rsi;     // Bollinger 均值回归策略（RSI 过滤）
Strategy_BollMR_Time boll_time;    // Bollinger 均值回归策略（时间过滤）
Strategy_BollMR_RSI_Time boll_rsi_time; // Bollinger 均值回归策略（RSI + 时间过滤）
Strategy_TrendPullback trend_pullback; // 趋势回撤策略 (M2)
Strategy_Combo combo;                  // 组合策略 (M1+M2)

TradeExecutor       executor; // 交易执行器
RiskPipeline        risk_pipeline; // 风控管道
PositionCoordinator pos_coord; // 单品种单向一仓

AIDecisionGateway   ai_gateway; // AI 决策网关
ConfidenceFilter    conf_filter; // 置信度过滤器

StatusPanel status_panel; // 状态面板

//---------------- 运行时状态 ----------------
bool g_period_valid = true;
bool g_period_warned = false;
datetime g_suppress_chart_event_until = 0;
string g_template_key = "";
datetime g_last_bar_time = 0;
int g_gap_skip_bars_remaining = 0;
string g_boll_variant = "";

// 指标导出文件句柄（如果需要导出 features）
int g_file = INVALID_HANDLE;
int g_signal_file = INVALID_HANDLE;
int g_signal_pos = 0;
int g_signal_state = 0;

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

void UpdateStatusPanel()
{
   bool ea_disabled = (!g_period_valid && DisableOnTimeframeChange);
   string reason = "";
   if(ea_disabled)
      reason = "TF " + EnumToString((ENUM_TIMEFRAMES)_Period) + " != " + EnumToString(TargetTimeframe);
   bool time_allowed = true;
   if(g_boll_variant == "enhanced")
      time_allowed = boll_enhanced.TimeFilterOK();
   else if(g_boll_variant == "time")
      time_allowed = boll_time.TimeFilterOK();
   else if(g_boll_variant == "trend_pullback")
      time_allowed = trend_pullback.TimeFilterOK();
   else if(g_boll_variant == "combo")
      // combo 模式：任一策略时间过滤通过即可
      time_allowed = boll_enhanced.TimeFilterOK() || trend_pullback.TimeFilterOK();
   string time_reason = "";
   if(!time_allowed)
      time_reason = "交易时间限制";

   // 统一从 RiskPipeline 获取结构冷却状态
   bool sc_active = risk_pipeline.IsStructuralCooldownActive();
   string sc_reason = risk_pipeline.GetStructuralCooldownReason();
   int sc_remaining = risk_pipeline.GetStructuralCooldownRemaining();

   status_panel.Update(risk_pipeline, pos_coord, ea_disabled, reason, time_allowed, time_reason,
                       sc_active, sc_reason, sc_remaining);
}

//---------------- 初始化 ----------------
int OnInit()
{
   Print("EA Init start");

   // 目标周期强制切换
   if(ForceTimeframeOnInit && _Period != TargetTimeframe)
   {
      g_suppress_chart_event_until = TimeCurrent() + 2;
      bool changed = ChartSetSymbolPeriod(0, _Symbol, TargetTimeframe);
      Print("Switching timeframe to ", EnumToString(TargetTimeframe),
            " result=", (changed ? "true" : "false"));
      if(changed)
         return INIT_SUCCEEDED;
   }

   if(ApplyTemplateOnInit && !MQLInfoInteger(MQL_TESTER))  // 策略测试器不支持模板
   {
      bool should_apply = true;
      if(ApplyTemplateOnce)
      {
         g_template_key = "EA_TEMPLATE_APPLIED_" + IntegerToString((int)ChartID()) + "_" + TemplateName;
         if(GlobalVariableCheck(g_template_key))
            should_apply = false;
      }

      if(should_apply)
      {
         if(!ChartApplyTemplate(0, TemplateName))
            Print("Failed to apply template: ", TemplateName, " err=", GetLastError());
         else
         {
            Print("Template applied: ", TemplateName);
            if(ApplyTemplateOnce && g_template_key != "")
               GlobalVariableSet(g_template_key, TimeCurrent());
         }
      }
      else
      {
         Print("Template skipped (ApplyTemplateOnce): ", TemplateName);
      }
   }

   status_panel.Init(); // 初始化状态面板
   EventSetTimer(1); // 每秒刷新面板时间显示

   // 1. 策略管理器：挂上策略
   g_boll_variant = BollMRVariant;
   StringToLower(g_boll_variant);
   if(g_boll_variant == "base")
      manager.Add(&boll_base);
   else if(g_boll_variant == "rsi")
      manager.Add(&boll_rsi);
   else if(g_boll_variant == "time")
      manager.Add(&boll_time);
   else if(g_boll_variant == "rsi_time")
      manager.Add(&boll_rsi_time);
   else if(g_boll_variant == "trend_pullback")
      manager.Add(&trend_pullback);
   else if(g_boll_variant == "combo")
      manager.Add(&combo);
   else
      manager.Add(&boll_enhanced);

   // 2. 初始化策略
    if(g_boll_variant == "base")
    {
        if(!boll_base.Init())
        {
            Print("Failed to initialize BollMR base strategy");
            return INIT_FAILED;
        }
    }
    else if(g_boll_variant == "rsi")
    {
        if(!boll_rsi.Init())
        {
            Print("Failed to initialize BollMR RSI strategy");
            return INIT_FAILED;
        }
    }
    else if(g_boll_variant == "time")
    {
        if(!boll_time.Init())
        {
            Print("Failed to initialize BollMR time strategy");
            return INIT_FAILED;
        }
    }
    else if(g_boll_variant == "rsi_time")
    {
        if(!boll_rsi_time.Init())
        {
            Print("Failed to initialize BollMR RSI+Time strategy");
            return INIT_FAILED;
        }
    }
    else if(g_boll_variant == "trend_pullback")
    {
        if(!trend_pullback.Init())
        {
            Print("Failed to initialize TrendPullback strategy");
            return INIT_FAILED;
        }
    }
    else if(g_boll_variant == "combo")
    {
        // 组合策略：添加子策略
        // M1: BollMR Enhanced（亚欧盘）
        combo.AddStrategy(&boll_enhanced, "BollMR");
        // M2: TrendPullback（欧美盘）
        combo.AddStrategy(&trend_pullback, "TrendPullback");
        // M3: 未来可继续添加...
        // combo.AddStrategy(&xauusd_alpha, "XauusdAlpha");
        
        // 初始化各子策略
        if(!boll_enhanced.Init())
        {
            Print("Failed to initialize BollMR for combo");
            return INIT_FAILED;
        }
        if(!trend_pullback.Init())
        {
            Print("Failed to initialize TrendPullback for combo");
            return INIT_FAILED;
        }
        
        // 初始化组合策略
        if(!combo.Init())
        {
            Print("Failed to initialize Combo strategy");
            return INIT_FAILED;
        }
    }
    else
    {
        if(!boll_enhanced.Init())
        {
            Print("Failed to initialize BollMR enhanced strategy");
            return INIT_FAILED;
        }
    }
   // 3. 风控管道初始化
   risk_pipeline.Init();

   // 4. AI 决策网关：挂上一个简单的置信度过滤器
   ai_gateway.AddFilter(&conf_filter);

   // 5. 仓位协调器与真实终端同步（防止 EA 重启时状态不一致）
   pos_coord.SyncFromTerminal();

   // 面板首次显示
   UpdateStatusPanel();

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
      FileWrite(g_signal_file, "time","signal","event","source");
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
   if(!g_period_valid && DisableOnTimeframeChange)
   {
      UpdateStatusPanel();
      return;
   }

   // 只在新 bar 上做决策
   if(!IsNewBar())
      return;


   // 通知 RiskPipeline 新K线（用于冷却器计时）
   risk_pipeline.OnNewBar();

   // 缺口检测 + 冷却
   datetime bar_time = iTime(_Symbol, _Period, 0);
   if(g_last_bar_time > 0)
   {
      int period_sec = PeriodSeconds(_Period);
      if(period_sec > 0 && (bar_time - g_last_bar_time) > (int)(period_sec * 1.5))
      {
         g_gap_skip_bars_remaining = GapCooldownBars;
         // Print("[EA] Gap detected. Skip next ", g_gap_skip_bars_remaining, " bars.");
      }
   }
   g_last_bar_time = bar_time;

   if(g_gap_skip_bars_remaining > 0)
   {
      g_gap_skip_bars_remaining--;
      // Print("[EA] Gap cooldown active. Remaining bars: ", g_gap_skip_bars_remaining);
      UpdateStatusPanel();
      return;
   }

   // 指标数据更新
   if(g_boll_variant == "base")
   {
      if(!boll_base.UpdateIndicators())
         return;
   }
   else if(g_boll_variant == "rsi")
   {
      if(!boll_rsi.UpdateIndicators())
         return;
   }
   else if(g_boll_variant == "time")
   {
      if(!boll_time.UpdateIndicators())
         return;
   }
   else if(g_boll_variant == "rsi_time")
   {
      if(!boll_rsi_time.UpdateIndicators())
         return;
   }
   else if(g_boll_variant == "trend_pullback")
   {
      if(!trend_pullback.UpdateIndicators())
         return;
   }
   else if(g_boll_variant == "combo")
   {
      // 更新组合策略中各子策略的指标
      if(!boll_enhanced.UpdateIndicators())
         return;
      if(!trend_pullback.UpdateIndicators())
         return;
   }
   else
   {
      if(!boll_enhanced.UpdateIndicators())
         return;
   }

   // 指标调试输出（可选）
   // Print("BollLower0=", GetBollLower(0), " BollLower1=", GetBollLower(1),
   //       " ATR1=", GetATR(1));

   pos_coord.SyncFromTerminal(); // 同步仓位状态

   // 更新结构冷却器状态（检查是否可以解除冷却）
   if(risk_pipeline.IsStructuralCooldownActive())
   {
      double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double atr = 0;
      double structurePrice = 0;
      
      // combo 模式下，trend_pullback 是组合的一部分
      if(g_boll_variant == "trend_pullback" || g_boll_variant == "combo")
      {
         atr = trend_pullback.GetCurrentATR();
         structurePrice = trend_pullback.GetCurrentStructurePrice();
      }
      
      if(atr > 0)
         risk_pipeline.UpdateCooldownState(price, atr, structurePrice);
   }

   Signal signal; // 声明信号变量
   signal = manager.GetSignal(); // 获取策略信号

   int signal_event = 0;
   bool has_event = false;
   if(signal.type == SIGNAL_BUY)
   {
      g_signal_pos = 1;
      signal_event = 1;
      has_event = true;
   }
   else if(signal.type == SIGNAL_SELL)
   {
      g_signal_pos = -1;
      signal_event = -1;
      has_event = true;
   }
   else if(signal.type == SIGNAL_EXIT)
   {
      g_signal_pos = 0;
      signal_event = 0;
      has_event = true;
   }

   // 如果有信号，就更新状态
   if(has_event)
      g_signal_state = g_signal_pos;

   if(g_signal_file != INVALID_HANDLE)
   {
      FileWrite(g_signal_file,
                TimeToString(iTime(_Symbol, _Period, 0), TIME_DATE|TIME_SECONDS),
                g_signal_state,
                (has_event ? IntegerToString(signal_event) : ""),
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
               if(AlertOnOrderClose)
                  Alert("平仓完成: ", _Symbol);
            }
            else
            {
               pos_coord.SyncFromTerminal();
            }
         }
         else
         {
            Print("[EA] ", signal.source, " Failed to close position when requested.");
            if(AlertOnOrderFail)
               Alert("平仓失败: ", _Symbol);
         }
      }
   }

   if(signal.type != SIGNAL_NONE && signal.type != SIGNAL_EXIT) // 如果有开仓信号
   {
      Print("[EA] Processing opening signal. type=", signal.type, " source=", signal.source);
      // 3.1 多策略冲突仲裁：单品种单向一仓
      if(!pos_coord.AllowSignal(signal))
      {
         // 每分钟最多打印一次PositionCoordinator拒绝日志
         static datetime last_pos_coord_reject_log = 0;
         datetime current_time = TimeCurrent();
         if(current_time - last_pos_coord_reject_log >= 60)
         {
            last_pos_coord_reject_log = current_time;
            Print("[EA] PositionCoordinator rejected signal from ", signal.source);
         }
         // 即便有信号，当前有仓位或不允许冲突，就直接退出
      }
      else
      {
         // 3.2 AI 决策网关过滤
         double ai_score = 1.0;
         if(!ai_gateway.Pass(signal, ai_score))
         {
            // 每分钟最多打印一次AIDecisionGateway拒绝日志
            static datetime last_ai_gateway_reject_log = 0;
            datetime current_time = TimeCurrent();
            if(current_time - last_ai_gateway_reject_log >= 60)
            {
               last_ai_gateway_reject_log = current_time;
               Print("[EA] AIDecisionGateway rejected signal from ", signal.source);
            }
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
                  if(AlertOnOrderOpen)
                     Alert("开仓成功: ", _Symbol, " ", (req.direction==TRADE_BUY?"BUY":"SELL"),
                           " vol=", DoubleToString(req.volume,2));
                  risk_pipeline.OnTradeExecuted(signal);
                  pos_coord.OnPositionOpened(signal);
               }
               else
               {
                  if(AlertOnOrderFail)
                     Alert("开仓失败: ", _Symbol, " ", (req.direction==TRADE_BUY?"BUY":"SELL"));
               }
            }
            else
            {
              string sig_dir = (signal.type==SIGNAL_BUY ? "BUY" :
                               (signal.type==SIGNAL_SELL ? "SELL" : "OTHER"));
              Print("[EA] BuildTrade failed. source=", signal.source,
                    " dir=", sig_dir,
                    " price=", DoubleToString(signal.price,_Digits),
                    " sl=", DoubleToString(signal.sl,_Digits),
                    " tp=", DoubleToString(signal.tp,_Digits),
                    " reason=", risk_pipeline.GetBlockReason());
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

   UpdateStatusPanel(); // 更新状态面板
}

//---------------- 定时器 ----------------
void OnTimer()
{
   if(!g_period_valid && DisableOnTimeframeChange)
   {
      UpdateStatusPanel();
      return;
   }
   UpdateStatusPanel();
}

//---------------- 图表事件 ----------------
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id != CHARTEVENT_CHART_CHANGE)
      return;

   if(g_suppress_chart_event_until > 0 && TimeCurrent() <= g_suppress_chart_event_until)
      return;

   if(_Period != TargetTimeframe)
   {
      g_period_valid = false;
      if(AlertOnTimeframeChange && !g_period_warned)
      {
         g_period_warned = true;
         string msg = "周期改变为 " + EnumToString((ENUM_TIMEFRAMES)_Period) +
                      "，期望 " + EnumToString(TargetTimeframe) + "。";
         if(ReloadOnTimeframeChange)
            msg += " 将移除EA。";
         else if(DisableOnTimeframeChange)
            msg += " EA已禁用。";
         Alert(msg);
         Print(msg);
      }

      if(ReloadOnTimeframeChange)
      {
         ExpertRemove();
         return;
      }

      if(AutoRevertTimeframe)
      {
         g_suppress_chart_event_until = TimeCurrent() + 2;
         bool changed = ChartSetSymbolPeriod(0, _Symbol, TargetTimeframe);
         Print("Auto revert timeframe to ", EnumToString(TargetTimeframe),
               " result=", (changed ? "true" : "false"));
      }
   }
   else
   {
      g_period_valid = true;
      g_period_warned = false;
   }
}

//---------------- 反初始化 ----------------
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(ApplyTemplateOnce && ClearTemplateOnceOnRemove && g_template_key != "")
   {
      if(reason == REASON_REMOVE || reason == REASON_RECOMPILE || reason == REASON_CHARTCLOSE)
         GlobalVariableDel(g_template_key);
   }

   if(g_file != INVALID_HANDLE)
      FileClose(g_file);
   if(g_signal_file != INVALID_HANDLE)
      FileClose(g_signal_file);
}
