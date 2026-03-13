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
#include "Indicators/RSI.mqh"

// 核心结构
#include "Core/Signal.mqh"
#include "Core/TradeTypes.mqh"

// 策略 & 管理
#include "Core/Strategy.mqh"
#include "Core/StrategyManager.mqh"
#include "Core/StrategyRegistry.mqh"
#include "Strategies/Strategy_BollMR_enhanced.mqh"
#include "Strategies/Strategy_BollMR_Base.mqh"
#include "Strategies/Strategy_BollMR_RSI.mqh"
#include "Strategies/Strategy_BollMR_Time.mqh"
#include "Strategies/Strategy_BollMR_RSI_Time.mqh"
#include "Strategies/Strategy_TrendPullback.mqh"
#include "Strategies/Strategy_DonchianBreakout.mqh"
#include "Strategies/Strategy_Combo.mqh"
#include "Strategies/Strategy_SmartMoney.mqh"

// 执行 & 风控
#include "Core/TradeExecutor.mqh"
#include "Core/Risk/RiskPipeline.mqh"
#include "Core/PositionCoordinator.mqh"

// AI 决策网关
#include "Core/IAIFilter.mqh"
#include "Core/ConfidenceFilter.mqh"
#include "Core/AIDecisionGateway.mqh"

// Regime Filter
#include "Core/Regime/RegimeFilter.mqh"

//  UI 状态面板
#include "Core/UI/StatusPanel.mqh"

// 特征导出（如果还需要）
// #include "Utils/Export.mqh"

//---------------- 全局对象 ----------------
StrategyManager     manager; // 策略管理器
StrategyRegistry    registry; // 策略注册表

Strategy_BollMR     boll_enhanced; // Bollinger 均值回归策略（增强版）
Strategy_BollMR_Base boll_base;    // Bollinger 均值回归策略（基线版）
Strategy_BollMR_RSI  boll_rsi;     // Bollinger 均值回归策略（RSI 过滤）
Strategy_BollMR_Time boll_time;    // Bollinger 均值回归策略（时间过滤）
Strategy_BollMR_RSI_Time boll_rsi_time; // Bollinger 均值回归策略（RSI + 时间过滤）
Strategy_TrendPullback trend_pullback; // 趋势回撤策略 (M4)
Strategy_DonchianBreakout donchian_breakout; // Donchian 突破策略 (M9)
Strategy_Combo combo;                  // 组合策略
Strategy_SmartMoney smart_money;       // 聪明钱策略 (SMC)

TradeExecutor       executor; // 交易执行器
RiskPipeline        risk_pipeline; // 风控管道
PositionCoordinator pos_coord; // 单品种单向一仓

AIDecisionGateway   ai_gateway; // AI 决策网关
ConfidenceFilter    conf_filter; // 置信度过滤器

// Regime Filter
CRegimeFilter       regime_filter; // Regime 过滤器

StatusPanel status_panel; // 状态面板

//---------------- 运行时状态 ----------------
bool g_period_valid = true;
bool g_period_warned = false;
datetime g_suppress_chart_event_until = 0;
string g_template_key = "";
string g_boll_variant = "";

// 指标导出文件句柄（如果需要导出 features）
int g_file = INVALID_HANDLE;
int g_signal_file = INVALID_HANDLE;
int g_signal_pos = 0;
int g_signal_state = 0;

//---------------- 初始化 ----------------
int OnInit()
{
   Print("EA Init start");

   // 调试：打印品种和账户信息
   {
      string acc_currency = AccountInfoString(ACCOUNT_CURRENCY);
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double tick_val = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_sz = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double contract = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      string profit_currency = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
      bool is_cent = (StringFind(acc_currency, "CENT") >= 0);
      
      Print("[DEBUG] Account: currency=", acc_currency, " equity=", equity, " is_cent=", is_cent);
      Print("[DEBUG] Symbol: ", _Symbol, 
            " tick_val=", tick_val, 
            " tick_sz=", tick_sz, 
            " contract=", contract,
            " profit_currency=", profit_currency);
   }

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
         // 先设置全局变量，因为 ChartApplyTemplate 可能触发 EA 重新加载
         if(ApplyTemplateOnce && g_template_key != "")
            GlobalVariableSet(g_template_key, TimeCurrent());
         
         if(!ChartApplyTemplate(0, TemplateName))
         {
            Print("Failed to apply template: ", TemplateName, " err=", GetLastError());
            // 失败时删除标记，下次重试
            if(ApplyTemplateOnce && g_template_key != "")
               GlobalVariableDel(g_template_key);
         }
         else
         {
            Print("Template applied: ", TemplateName);
            // 模板应用成功，继续初始化
            // 注意：如果模板触发了 EA 重新加载，后续代码会在新实例中执行
         }
      }
      else
      {
         Print("Template skipped (ApplyTemplateOnce): ", TemplateName);
      }
   }

   status_panel.Init(); // 初始化状态面板
   EventSetTimer(1); // 每秒刷新面板时间显示

   // 1. 注册所有策略到注册表
   registry.Register("enhanced", &boll_enhanced);
   registry.Register("base", &boll_base);
   registry.Register("rsi", &boll_rsi);
   registry.Register("time", &boll_time);
   registry.Register("rsi_time", &boll_rsi_time);
   registry.Register("trend_pullback", &trend_pullback);
   registry.Register("donchian", &donchian_breakout);
   registry.Register("smart_money", &smart_money);
   
   // 注册组合策略的子策略（标记为 combo_child）
   registry.Register("boll_enhanced_child", &boll_enhanced, true);
   registry.Register("trend_pullback_child", &trend_pullback, true);
   registry.Register("donchian_child", &donchian_breakout, true);
   
   // 2. 选择策略变体
   g_boll_variant = StrategyVariant;
   StringToLower(g_boll_variant);
   
   // 组合策略特殊处理
   if(g_boll_variant == "combo")
   {
      combo.AddStrategy(&boll_enhanced, "BollMR_enhanced");
      combo.AddStrategy(&trend_pullback, "TrendPullback");
      combo.AddStrategy(&donchian_breakout, "DonchianBreakout");
      registry.RegisterCombo(&combo, "combo");
   }
   
   // 选择策略
   if(!registry.Select(g_boll_variant))
   {
      // 未找到则使用默认
      registry.Select("enhanced");
      g_boll_variant = "enhanced";
   }
   
   // 3. 初始化策略
   if(!registry.Init())
   {
      Print("Failed to initialize strategy: ", g_boll_variant);
      return INIT_FAILED;
   }
   
   // 4. 添加到策略管理器
   manager.Add(registry.GetPrimary());
   
   // 添加 SMC 策略（独立运行，不受 regime 过滤）
   if(!smart_money.Init())
   {
      Print("Failed to initialize SmartMoney strategy");
      return INIT_FAILED;
   }
   smart_money.SetRegimeFilter(&regime_filter);  // 注入但不强制过滤
   manager.Add(&smart_money);
   
   // M6.3: 注入 RegimeFilter 到所有策略（消除策略层趋势判断）
   registry.SetRegimeFilterForAll(&regime_filter);

   // 5. 风控管道初始化
   risk_pipeline.Init();

   // 6. AI 决策网关：挂上一个简单的置信度过滤器
   ai_gateway.AddFilter(&conf_filter);

   // 5. Regime Filter 初始化
   if(!regime_filter.Init(_Symbol, _Period))
   {
      Print("Failed to initialize RegimeFilter");
      return INIT_FAILED;
   }

   // 6. 仓位协调器与真实终端同步（防止 EA 重启时状态不一致）
   pos_coord.SyncFromTerminal();

   // 面板首次显示
   UpdateStatusPanel();

   // 6. 如果需要导出特征，就打开文件
   // 先关闭旧句柄（防止时间框架切换时重复打开）
   if(g_file != INVALID_HANDLE) 
   {
      FileClose(g_file);
      g_file = INVALID_HANDLE;
   }
   if(g_signal_file != INVALID_HANDLE)
   {
      FileClose(g_signal_file);
      g_signal_file = INVALID_HANDLE;
   }
   
   g_file = FileOpen("features.csv",
                     FILE_WRITE | FILE_CSV | FILE_COMMON | FILE_SHARE_WRITE);
   if(g_file != INVALID_HANDLE)
   {
      // 扩展特征头（25+ 列，用于 ML/RL 训练）
      FileWrite(g_file,
         // 时间特征
         "time","hour","day_of_week","session",
         // 价格特征
         "open","high","low","close","price_change","price_range",
         // 技术指标
         "atr","adx","rsi","boll_upper","boll_lower","boll_mid","boll_width","boll_position",
         // 市场质量
         "efficiency","false_breakout_rate","q_score",
         // Regime 状态
         "regime_state","regime_type","sub_type","trend_direction","volatility_state",
         // 策略信号
         "final_signal","position_size");
      Print("Feature file opened with extended columns for ML/RL.");
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
      FileWrite(g_signal_file, "time","signal","event","source","regime");
      Print("Signals file opened.");
   }
   else
   {
      Print("Signals file open failed: ", GetLastError());
   }

   Print("EA Init finished");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. 初始化与数据准备
   Signal signal;
   RegimeState regime_state = regime_filter.GetState();

   // 2. 数据更新与前置检查
   if(!PreUpdateChecks(regime_state))
      return;

   // 2.1 在 PreUpdateChecks 之后获取 sub_type，确保与策略内部检查一致
   RegimeSubType sub_type = regime_filter.GetSubType();

   // 3. Tick级别退出检查（每个tick都执行，实时监控出场机会）
   if(pos_coord.HasPosition())
   {
      // 必须调用 GetSignal 来获取退出信号，而不是使用空的 signal
      signal = manager.GetSignal();
      
      bool should_close = risk_pipeline.ShouldClosePosition(signal);
      if(should_close)
         ManagePositionExit(signal, regime_state);
      
      UpdateStatusPanel(); // 每个tick都更新一次
   }
   
   // 3.1 SMC 策略 Tick 级别检查（每个 tick 都执行）
   // SMC 策略需要 tick 级别检查 HTF zone 和 LTF 入场
   Signal smc_signal = smart_money.TickCheck();
   if(smc_signal.type != SIGNAL_NONE)
   {
      ProcessSignal(smc_signal, regime_state, sub_type);
   }

   // 4. 新K线逻辑（入场信号等）
   if(IsNewBar())
   {
      ProcessNewBarLogic(signal, regime_state, sub_type);
   }

   // 5. 最终状态更新
   UpdateStatusPanel(); // 仅在Tick结束前更新一次
}

//+------------------------------------------------------------------+
//| 前置检查：指标更新、Regime状态、时间周期有效性                   |
//+------------------------------------------------------------------+
bool PreUpdateChecks(RegimeState &regime_state)
{
   // 更新指标数据
   if(!registry.UpdateIndicators())
      return false;
   
   // 更新Regime状态
   double close = iClose(_Symbol, _Period, 1);
   double high = iHigh(_Symbol, _Period, 1);
   double low = iLow(_Symbol, _Period, 1);
   if(!regime_filter.Update(close, high, low))
   {
      Print("[EA] RegimeFilter update failed");
      return false;
   }
   regime_state = regime_filter.GetState(); // 刷新状态
   
   // 检查时间周期有效性
   if(!g_period_valid && DisableOnTimeframeChange)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| 新K线核心业务逻辑（入场信号）
//+------------------------------------------------------------------+
void ProcessNewBarLogic(Signal &signal, RegimeState regime_state, RegimeSubType sub_type)
{
   // 仓位同步
   pos_coord.SyncFromTerminal();

   // 获取信号
   signal = manager.GetSignal();

   // Regime状态过滤（非活跃状态仅允许平仓）
   bool regime_active = (regime_state == STATE_ACTIVE);
   if(!regime_active)
   {
      FilterNonExitSignals(signal);
      regime_filter.PrintState();
      return;
   }
   regime_filter.PrintState(); // 活跃状态打印调试信息
   
   // 风控管道检查（冷却器等）
   if(!RiskPipelineChecks())
      return;
   
   // 信号分发处理
   ProcessSignal(signal, regime_state, sub_type);
}

//+------------------------------------------------------------------+
//| 风控管道检查（冷却器、结构冷却等）                               |
//+------------------------------------------------------------------+
bool RiskPipelineChecks()
{
   risk_pipeline.OnNewBar(); // 通知新K线
   
   // 检查冷却器是否允许交易
   if(!risk_pipeline.IsCheckGapOk())
      return false;
   
   // 处理结构冷却器
   if(risk_pipeline.IsStructuralCooldownActive())
   {
      UpdateStructuralCooldown();
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| 更新结构冷却器状态                                               |
//+------------------------------------------------------------------+
void UpdateStructuralCooldown()
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double atr = 0;
   double structurePrice = 0;
   
   string variant = registry.GetVariant();
   if(variant == "trend_pullback" || variant == "combo")
   {
      atr = trend_pullback.GetCurrentATR();
      structurePrice = trend_pullback.GetCurrentStructurePrice();
   }
   
   if(atr > 0)
      risk_pipeline.UpdateCooldownState(price, atr, structurePrice);
}

//+------------------------------------------------------------------+
//| 过滤非平仓信号（仅在Regime非活跃时调用）                         |
//+------------------------------------------------------------------+
void FilterNonExitSignals(Signal &signal)
{
   // SMC 策略绕过 regime 过滤
   if(signal.bypass_regime_filter)
      return;
   
   if(signal.type != SIGNAL_EXIT)
   {
      signal.type = SIGNAL_NONE;
      signal.source = ""; // 标记为被过滤信号
   }
}

//+------------------------------------------------------------------+
//| 信号分发处理（开仓/加仓/修改止损止盈）                           |
//+------------------------------------------------------------------+
void ProcessSignal(Signal &signal, RegimeState regime_state, RegimeSubType sub_type)
{
   switch(signal.type)
   {
      case SIGNAL_BUY:
      case SIGNAL_SELL:
      case SIGNAL_ADD_LONG:
      case SIGNAL_ADD_SHORT:
         ProcessOpenSignal(signal, regime_state, sub_type);
         break;
         
      case SIGNAL_EXIT:
         ManagePositionExit(signal, regime_state);
         break;
         
      case SIGNAL_MODIFY_SL:
         ProcessModifySL(signal, regime_state);
         break;
         
      case SIGNAL_MODIFY_TP:
         ProcessModifyTP(signal, regime_state);
         break;
         
      default:
         // 忽略其他信号类型
         break;
   }
}

//+------------------------------------------------------------------+
//| 处理开仓/加仓信号                                                |
//+------------------------------------------------------------------+
void ProcessOpenSignal(Signal &signal, RegimeState regime_state, RegimeSubType sub_type)
{
   Print("[EA] Processing opening signal. type=", signal.type, " source=", signal.source);
   
   // 仓位协调器检查
   if(!pos_coord.AllowSignal(signal))
   {
      pos_coord.PrintState();
      return;
   }
   
   // AI网关过滤
   double ai_score = 1.0;
   if(!ai_gateway.Pass(signal, ai_score))
   {
      ai_gateway.PrintState(signal);
      return;
   }
   
   // 构建交易请求
   TradeRequest req;
   if(!risk_pipeline.BuildTrade(signal, req))
   {
      LogSignalFailure(signal, regime_state, "BuildTrade failed: " + risk_pipeline.GetBlockReason());
      return;
   }
   
   // 执行订单
   if(executor.Execute(req, signal.source))
   {
      LogOrderSuccess(req, signal, regime_state, sub_type);
      UpdatePostTradeState(signal, req);
   }
   else
   {
      LogOrderFailure(req, signal, regime_state, sub_type);
   }
   
   // 重置信号（避免重复处理）
   signal.type = SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| 处理修改止损信号                                                 |
//+------------------------------------------------------------------+
void ProcessModifySL(Signal &signal, RegimeState regime_state)
{
   Print("[EA] Processing MODIFY_SL signal. source=", signal.source, 
         " new_sl=", DoubleToString(signal.new_sl, _Digits));
   
   TradeRequest req;
   if(!risk_pipeline.ValidateModifySL(signal, req))
   {
      Print("[EA] ModifySL validation failed: ", risk_pipeline.GetBlockReason());
      signal.type = SIGNAL_NONE;
      return;
   }
   
   if(executor.ModifySL(req.new_sl, signal.source))
   {
      if(AlertOnOrderOpen)
         Alert("止损修改成功: ", _Symbol, " 新SL=", DoubleToString(req.new_sl, _Digits));
      RecordSignal(signal.type, signal.source, regime_filter.GetState());
   }
   else
   {
      Print("[EA] ModifySL execution failed.");
   }
   
   signal.type = SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| 处理修改止盈信号                                                 |
//+------------------------------------------------------------------+
void ProcessModifyTP(Signal &signal, RegimeState regime_state)
{
   Print("[EA] Processing MODIFY_TP signal. source=", signal.source,
         " new_tp=", DoubleToString(signal.new_tp, _Digits));
   
   TradeRequest req;
   if(!risk_pipeline.ValidateModifyTP(signal, req))
   {
      Print("[EA] ModifyTP validation failed: ", risk_pipeline.GetBlockReason());
      signal.type = SIGNAL_NONE;
      return;
   }
   
   if(executor.ModifyTP(req.new_tp, signal.source))
   {
      if(AlertOnOrderOpen)
         Alert("止盈修改成功: ", _Symbol, " 新TP=", DoubleToString(req.new_tp, _Digits));
      RecordSignal(signal.type, signal.source, regime_filter.GetState());
   }
   else
   {
      Print("[EA] ModifyTP execution failed.");
   }
   
   signal.type = SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| 记录信号失败日志                                                 |
//+------------------------------------------------------------------+
void LogSignalFailure(const Signal &signal, RegimeState regime_state, string reason)
{
   string sig_dir = (signal.type==SIGNAL_BUY ? "BUY" :
                    (signal.type==SIGNAL_SELL ? "SELL" : "OTHER"));
   Print("[EA] ", reason, " source=", signal.source,
         " dir=", sig_dir,
         " price=", DoubleToString(signal.price,_Digits),
         " sl=", DoubleToString(signal.sl,_Digits),
         " tp=", DoubleToString(signal.tp,_Digits));
   
   RecordSignal(signal.type, signal.source, regime_state); 
   RecordFeatures(signal.type, signal.source, regime_state);
}

//+------------------------------------------------------------------+
//| 记录订单成功日志                                                 |
//+------------------------------------------------------------------+
void LogOrderSuccess(const TradeRequest &req, const Signal &signal, RegimeState regime_state, RegimeSubType sub_type)
{
   Print("[EA] Order executed. dir=",
         (req.direction==TRADE_BUY?"BUY":"SELL"),
         " entry_price=", DoubleToString(signal.price,_Digits),
         " vol=", DoubleToString(req.volume,2),
         " sl=", DoubleToString(req.sl,_Digits),
         " tp=", DoubleToString(req.tp,_Digits));
   
   if(AlertOnOrderOpen)
      Alert("开仓成功: ", _Symbol, " ", (req.direction==TRADE_BUY?"BUY":"SELL"),
            " vol=", DoubleToString(req.volume,2),
            " entry_price=", DoubleToString(signal.price,_Digits),
            " sl=", DoubleToString(signal.sl,_Digits),
            " tp=", DoubleToString(req.tp,_Digits),
            " regime_state=", RegimeStateToString(regime_state),
            " source=", signal.source,
            " sub_type=", RegimeSubTypeToString(sub_type));
}

//+------------------------------------------------------------------+
//| 更新交易后状态（风控、仓位追踪器）                               |
//+------------------------------------------------------------------+
void UpdatePostTradeState(const Signal &signal, const TradeRequest &req)
{
   risk_pipeline.OnTradeExecuted(signal);
   pos_coord.OnPositionOpened(signal);
   
   // 初始化仓位追踪器
   if(PositionSelect(_Symbol))
   {
      long dir = PositionGetInteger(POSITION_TYPE);
      pos_coord.InitTracker(signal.price, req.volume, dir, signal.source);
   }
   
   RecordSignal(signal.type, signal.source, regime_filter.GetState()); 
   RecordFeatures(signal.type, signal.source, regime_filter.GetState());
}

//+------------------------------------------------------------------+
//| 记录订单失败日志                                                 |
//+------------------------------------------------------------------+
void LogOrderFailure(const TradeRequest &req, const Signal &signal, RegimeState regime_state, RegimeSubType sub_type)
{
   if(AlertOnOrderFail)
   {
      RecordSignal(signal.type, signal.source, regime_state); 
      RecordFeatures(signal.type, signal.source, regime_state);
      Alert("开仓失败: ", _Symbol, " ", (req.direction==TRADE_BUY?"BUY":"SELL"), 
            " sub_type=", RegimeSubTypeToString(sub_type),
            " source=", signal.source, 
            " regime_state=", RegimeStateToString(regime_state));
   }
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

//---------------- 优化器接口 ----------------
// 用于 MT5 策略测试器优化，返回自定义优化指标
double OnTester()
{
   // 获取测试器统计数据
   double netProfit = TesterStatistics(STAT_PROFIT);
   double maxDD = TesterStatistics(STAT_BALANCE_DD);
   double trades = TesterStatistics(STAT_TRADES);
   double sharpe = TesterStatistics(STAT_SHARPE_RATIO);
   
   // 防止除零
   if(maxDD <= 0) maxDD = 1.0;
   if(trades < 10) return 0;  // 交易次数太少，返回 0
   
   // 自定义优化指标: 收益/最大回撤 * 交易次数权重
   // 越大越好
   double retOverDD = netProfit / maxDD;
   double tradeBonus = MathMin(trades / 100.0, 1.0);  // 鼓励更多交易
   
   // 综合指标 (可调整权重)
   double metric = retOverDD * (0.7 + 0.3 * tradeBonus);
   
   // 惩罚负收益
   if(netProfit < 0) metric *= 0.1;
   
   return metric;
}


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

//---------------- 更新状态面板 ----------------
void UpdateStatusPanel()
{
   bool ea_disabled = (!g_period_valid && DisableOnTimeframeChange);
   string reason = "";
   if(ea_disabled)
      reason = "TF " + EnumToString((ENUM_TIMEFRAMES)_Period) + " != " + EnumToString(TargetTimeframe);
   
   // 统一通过注册表获取时间过滤状态
   bool time_allowed = registry.TimeFilterOK();
   string time_reason = "";
   if(!time_allowed)
      time_reason = "交易时间限制";

   // 统一从 RiskPipeline 获取结构冷却状态
   bool sc_active = risk_pipeline.IsStructuralCooldownActive();   
   string sc_reason = risk_pipeline.GetStructuralCooldownReason();
   int sc_remaining = risk_pipeline.GetStructuralCooldownRemaining();

   // 获取 Regime 状态
   RegimeState regime_state = regime_filter.GetState();
   string regime_state_str = RegimeStateToString(regime_state);
   string subtype_str = RegimeSubTypeToString(regime_filter.GetSubType());
   double q_score = regime_filter.GetQScore();

   status_panel.Update(risk_pipeline, pos_coord, ea_disabled, reason, time_allowed, time_reason,
                       sc_active, sc_reason, sc_remaining, regime_state_str, subtype_str, q_score);
}

//+------------------------------------------------------------------+
//| 持仓退出管理（Tick级别调用）
//+------------------------------------------------------------------+
void ManagePositionExit(Signal &signal, RegimeState regime_state)
{
   if(pos_coord.HasPosition()) // 如果当前有仓位，先检查是否需要平仓
   {
      bool should_close = risk_pipeline.ShouldClosePosition(signal);
      if(should_close) //需要平仓
      {
         bool closed = false;
         
         // 平仓前保存仓位信息
         double entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double pos_vol = PositionGetDouble(POSITION_VOLUME);
         long pos_type = PositionGetInteger(POSITION_TYPE);
         ulong pos_ticket = PositionGetInteger(POSITION_TICKET);
         bool is_full_close = false;  // 是否为全部平仓

         if(signal.type == SIGNAL_EXIT && signal.exit_volume > 0.0)
         {
            double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
            double min_vol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            double close_vol = MathMin(signal.exit_volume, pos_vol);

            if(close_vol >= pos_vol - step * 0.5)
            {
               closed = executor.Close();
               is_full_close = true;
            }
            else if(close_vol >= min_vol)
            {
               closed = executor.ClosePartial(close_vol);
               is_full_close = false;
            }
            else
            {
               closed = executor.Close();
               is_full_close = true;
            }
         }
         else
         {
            closed = executor.Close();
            is_full_close = true;
         } 

         if(closed)
         {
            // 从历史成交获取本次平仓盈亏
            double this_profit = 0, this_swap = 0, this_comm = 0, this_vol = 0, this_price = 0;
            if(HistorySelect(0, TimeCurrent() + 60))
            {
               int total = HistoryDealsTotal();
               for(int i = total - 1; i >= 0; i--)
               {
                  ulong deal_ticket = HistoryDealGetTicket(i);
                  if(deal_ticket > 0)
                  {
                     long deal_entry = HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
                     if(deal_entry == DEAL_ENTRY_OUT || deal_entry == DEAL_ENTRY_OUT_BY)
                     {
                        this_profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
                        this_swap = HistoryDealGetDouble(deal_ticket, DEAL_SWAP);
                        this_comm = HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
                        this_vol = HistoryDealGetDouble(deal_ticket, DEAL_VOLUME);
                        this_price = HistoryDealGetDouble(deal_ticket, DEAL_PRICE);
                        break;
                     }
                  }
               }
            }
            
            // 更新追踪器（如果追踪器未激活，使用当前仓位信息初始化）
            if(!pos_coord.IsTrackerActive())
            {
               pos_coord.InitTracker(entry_price, pos_vol + this_vol, pos_type, signal.source);
            }
            pos_coord.AddCloseResult(this_profit, this_swap, this_comm, this_vol);
            pos_coord.PrintCloseResult(this_profit, this_vol);
            
            if(!PositionSelect(_Symbol))  // 全部平仓完成
            {
               risk_pipeline.OnPositionClosed();
               pos_coord.OnPositionClosed();
               
               if(AlertOnOrderClose)
               {
                  double net = pos_coord.GetTrackerNetProfit();
                  string net_sign = (net >= 0 ? "+" : "");
                  Alert("平仓完成: ", _Symbol, " 净盈亏: ", net_sign, DoubleToString(net, 2));
               }
               
               pos_coord.ResetTracker();
               pos_coord.PrintState();
               RecordSignal(SIGNAL_EXIT, signal.source, regime_state); 
               RecordFeatures(SIGNAL_EXIT, signal.source, regime_state);
               signal.type = SIGNAL_NONE;
            }
            else  // 部分平仓
            {
               // 检查是否需要同步修改止损（保本止损）
               if(signal.sl_on_exit > 0 && PositionSelect(_Symbol))
               {
                  string sl_source = signal.source + "_保本";
                  if(executor.ModifySL(signal.sl_on_exit, sl_source))
                  {
                     Print("[EA] 部分平仓后同步修改止损: ", DoubleToString(signal.sl_on_exit, _Digits));
                  }
               }
               
               pos_coord.SyncFromTerminal();
               pos_coord.PrintState();
               RecordSignal(SIGNAL_EXIT, signal.source, regime_state); 
               RecordFeatures(SIGNAL_EXIT, signal.source, regime_state);
               signal.type = SIGNAL_NONE;
            }
         }
         else
         {  
            Print("[EA] ", signal.source, " Failed to close position when requested.");
            pos_coord.PrintState();
            RecordSignal(SIGNAL_EXIT, signal.source, regime_state); 
            RecordFeatures(SIGNAL_EXIT, signal.source, regime_state);
            signal.type = SIGNAL_NONE;
            if(AlertOnOrderFail)
               Alert("平仓失败: ", _Symbol);
         }
      }
   }
}

void RecordSignal(SignalType signal_type, string signal_source, RegimeState regime_state){
   int signal_event = 0;
   bool has_event = false;
   if(signal_type == SIGNAL_BUY)
   {
      g_signal_pos = 1;
      signal_event = 1;
      has_event = true;
   }
   else if(signal_type == SIGNAL_SELL)
   {
      g_signal_pos = -1;
      signal_event = -1;
      has_event = true;
   }
   else if(signal_type == SIGNAL_EXIT)
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
      // 使用辅助函数获取 Regime 状态字符串
      string regime_state_str = RegimeStateToString(regime_state);
      string subtype_str = RegimeSubTypeToString(regime_filter.GetSubType());
      FileWrite(g_signal_file,
                  TimeToString(iTime(_Symbol, _Period, 0), TIME_DATE|TIME_SECONDS),
                  g_signal_state,
                  (has_event ? IntegerToString(signal_event) : ""),
                  signal_source,
                  StringFormat("%s|%s|Q%.2f", regime_state_str, subtype_str, regime_filter.GetQScore()));
   }

}

void RecordFeatures(SignalType signal_type, string signal_source, RegimeState regime_state)
{
   if(g_file != INVALID_HANDLE)
   {
      datetime bar_time = iTime(_Symbol, _Period, 1);
      MqlDateTime dt;
      TimeToStruct(bar_time, dt);
      
      // 时间特征
      int hour = dt.hour;
      int day_of_week = dt.day_of_week;  // 0=Sunday, 1=Monday, ...
      int session = 0;  // 0=asia, 1=europe, 2=us, 3=overlap
      if(hour >= 0 && hour < 8) session = 0;       // Asia
      else if(hour >= 7 && hour < 16) session = 1; // Europe
      else if(hour >= 13 && hour < 21) session = 2; // US
      if((hour >= 7 && hour < 8) || (hour >= 13 && hour < 16)) session = 3; // Overlap
      
      // 价格特征
      double open1   = iOpen(_Symbol, _Period, 1);
      double high1   = iHigh(_Symbol, _Period, 1);
      double low1    = iLow(_Symbol, _Period, 1);
      double close1  = iClose(_Symbol, _Period, 1);
      double close2  = iClose(_Symbol, _Period, 2);  // 前一根收盘价
      double price_change = close1 - close2;
      double price_range  = high1 - low1;
      
      // 技术指标
      double atr1    = GetATR(1);
      double bu      = GetBollUpper(0);
      double bl      = GetBollLower(0);
      double bm      = (bu + bl) / 2.0;
      double boll_width = (bu - bl) / (bm + 0.0001);  // 避免除零
      double boll_position = (close1 - bl) / (bu - bl + 0.0001);  // 0-1 范围
      
      // ADX 和 RSI
      double adx = regime_filter.GetADX();
      double rsi = GetRSI(1);  // 使用全局 RSI 函数
      
      // 获取快照（一次性获取所有状态）
      RegimeSnapshot snap = regime_filter.GetSnapshot();
      
      // 市场质量
      double efficiency = snap.efficiency;
      double fbr = snap.false_breakout_rate;
      double q_score = snap.q_score;
      
      // Regime 状态
      int regime_state_int = (int)regime_state;  // 0=ACTIVE, 1=STANDBY, 2=TRANSITION
      int regime_type = (int)snap.regime_type;  // 0=RANGE, 1=TREND
      int sub_type = (int)snap.sub_type;  // 0-7
      int trend_dir = (int)snap.trend_direction;  // -1, 0, 1
      int vol_state = (int)snap.volatility_state;  // 0=LOW, 1=NORMAL, 2=HIGH
      
      // 策略信号
      int final_sig = 0;
      if(signal_type == SIGNAL_BUY) final_sig = 1;
      else if(signal_type == SIGNAL_SELL) final_sig = -1;
      
      // 仓位大小（记录信号时的参考仓位）
      double pos_size = 0.01;  // 默认最小仓位

      FileWrite(g_file,
         // 时间特征
         TimeToString(bar_time, TIME_DATE|TIME_SECONDS),
         IntegerToString(hour),
         IntegerToString(day_of_week),
         IntegerToString(session),
         // 价格特征
         DoubleToString(open1, _Digits),
         DoubleToString(high1, _Digits),
         DoubleToString(low1, _Digits),
         DoubleToString(close1, _Digits),
         DoubleToString(price_change, _Digits),
         DoubleToString(price_range, _Digits),
         // 技术指标
         DoubleToString(atr1, _Digits),
         DoubleToString(adx, 2),
         DoubleToString(rsi, 2),
         DoubleToString(bu, _Digits),
         DoubleToString(bl, _Digits),
         DoubleToString(bm, _Digits),
         DoubleToString(boll_width, 6),
         DoubleToString(boll_position, 4),
         // 市场质量
         DoubleToString(efficiency, 4),
         DoubleToString(fbr, 4),
         DoubleToString(q_score, 4),
         // Regime 状态
         IntegerToString(regime_state_int),
         IntegerToString(regime_type),
         IntegerToString(sub_type),
         IntegerToString(trend_dir),
         IntegerToString(vol_state),
         // 策略信号
         IntegerToString(final_sig),
         DoubleToString(pos_size, 2)
      );
   }
}