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

//---------------- Tick 驱动 ----------------
void OnTick()
{
   
   Signal signal;
   RegimeState regime_state = regime_filter.GetState();

   // 指标数据更新
   if(!registry.UpdateIndicators())
      return;

   // 更新 Regime Filter 状态
   double close = iClose(_Symbol, _Period, 1);
   double high = iHigh(_Symbol, _Period, 1);
   double low = iLow(_Symbol, _Period, 1);
   if(!regime_filter.Update(close, high, low))
   {
      Print("[EA] RegimeFilter update failed");
   }

   if(!g_period_valid && DisableOnTimeframeChange)
   {
      UpdateStatusPanel();
      return;
   }

   UpdateStatusPanel();

   // 只在新 bar 上执行一次, 避免重复计算
   if(!IsNewBar())
      return;

   // 检查 Regime Filter 状态
   bool regime_active = (regime_state == STATE_ACTIVE);

   // 获取信号
   signal = manager.GetSignal();

   // 管理仓位
   ManagePositionExitOnBar(signal, regime_state);

   // 同步仓位状态
   pos_coord.SyncFromTerminal();

   UpdateStatusPanel();

   if(!regime_active)
   {  
      // 如果当前信号不是平仓信号，就过滤掉（如果是平仓信号则放行，允许在非 ACTIVE 状态下平仓）
      if(signal.type != SIGNAL_EXIT)
      {
         signal.type = SIGNAL_NONE;
         signal.source = "";  // 清空 source，表示信号被过滤
      }
      // Regime Filter 状态调试输出 - 只在新 bar 上打印一次
      regime_filter.PrintState();
      return;
   }
   
   // Regime Filter 状态调试输出
   regime_filter.PrintState();

   // 风控管道
   // 通知 RiskPipeline 新K线（用于冷却器计时）
   risk_pipeline.OnNewBar();

   // 检查是否跳过当前 K 线（冷却器）
   if (!risk_pipeline.IsCheckGapOk())
   {
      return;
   }

   // 更新结构冷却器状态（检查是否可以解除冷却）
   if(risk_pipeline.IsStructuralCooldownActive())
   {
      double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double atr = 0;
      double structurePrice = 0;
      
      // trend_pullback 或 combo 模式需要获取结构价格
      string variant = registry.GetVariant();
      if(variant == "trend_pullback" || variant == "combo")
      {
         atr = trend_pullback.GetCurrentATR();
         structurePrice = trend_pullback.GetCurrentStructurePrice();
      }
      
      if(atr > 0)
         risk_pipeline.UpdateCooldownState(price, atr, structurePrice);
      
      return; // 冷却中不执行后续逻辑
   }

   UpdateStatusPanel();

   // 如果有开仓, 加仓信号
   if(signal.type == SIGNAL_BUY || signal.type == SIGNAL_SELL || signal.type == SIGNAL_ADD_LONG || signal.type == SIGNAL_ADD_SHORT)
   {
      Print("[EA] Processing opening signal. type=", signal.type, " source=", signal.source);
      if(!pos_coord.AllowSignal(signal))
      {
         pos_coord.PrintState();
         return;
      }
      else
      {
         // AI 决策网关过滤
         double ai_score = 1.0;
         if(!ai_gateway.Pass(signal, ai_score))
         {
            ai_gateway.PrintState(signal);
            return; // 不通过则过滤
         }
         else
         {
            // 风控构建 TradeRequest
            TradeRequest req;
            if(risk_pipeline.BuildTrade(signal, req))
            {
               Print("[EA] BuildTrade OK. dir=",
                     (req.direction==TRADE_BUY?"BUY":"SELL"),
                     " vol=", DoubleToString(req.volume,2),
                     " sl=", DoubleToString(req.sl,_Digits),
                     " tp=", DoubleToString(req.tp,_Digits));

               // 执行下单
               if(executor.Execute(req, signal.source))
               {
                  Print("[EA] Order executed.");
                  if(AlertOnOrderOpen)
                     Alert("开仓成功: ", _Symbol, " ", (req.direction==TRADE_BUY?"BUY":"SELL"),
                           " vol=", DoubleToString(req.volume,2));
                  risk_pipeline.OnTradeExecuted(signal);
                  pos_coord.OnPositionOpened(signal);
                  RecordSignal(signal.type, signal.source, regime_state); 
                  RecordFeatures(signal.type, signal.source, regime_state);
                  signal.type = SIGNAL_NONE; // 清空信号类型，防止后续重复处理
               }
               else
               {
                  if(AlertOnOrderFail)
                  {
                     RecordSignal(signal.type, signal.source, regime_state); 
                     RecordFeatures(signal.type, signal.source, regime_state);
                     signal.type = SIGNAL_NONE; // 清空信号类型，防止后续重复处理
                     Alert("开仓失败: ", _Symbol, " ", (req.direction==TRADE_BUY?"BUY":"SELL"));
                  }
               }
            }
            else
            {
               string sig_dir = (signal.type==SIGNAL_BUY ? "BUY" :
                                 (signal.type==SIGNAL_SELL ? "SELL" : "OTHER"));
               RecordSignal(signal.type, signal.source, regime_state); 
               RecordFeatures(signal.type, signal.source, regime_state);
               signal.type = SIGNAL_NONE; // 清空信号类型，防止后续重复处理         
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

   UpdateStatusPanel();
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

void ManagePositionExitOnBar(Signal &signal, RegimeState regime_state){
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
                  pos_coord.PrintState();
                  RecordSignal(SIGNAL_EXIT, signal.source, regime_state); 
                  RecordFeatures(SIGNAL_EXIT, signal.source, regime_state);
                  signal.type = SIGNAL_NONE; // 平仓信号处理完成，重置信号类型，防止后续重复处理
            }
            else
            {
               pos_coord.SyncFromTerminal(); // 如果平仓后仓位仍然存在，可能是部分平仓或平仓失败，强制同步状态以防止不一致
               pos_coord.PrintState();
               RecordSignal(SIGNAL_EXIT, signal.source, regime_state); 
               RecordFeatures(SIGNAL_EXIT, signal.source, regime_state);
               signal.type = SIGNAL_NONE; // 无论平仓成功与否都重置信号类型，防止重复处理
               Print("[EA] ", signal.source, " Position still exists after close attempt. Syncing state."); // 如果平仓失败，发出警报
            }
         }
         else
         {  
            Print("[EA] ", signal.source, " Failed to close position when requested.");
            pos_coord.PrintState();
            RecordSignal(SIGNAL_EXIT, signal.source, regime_state); 
            RecordFeatures(SIGNAL_EXIT, signal.source, regime_state);
            signal.type = SIGNAL_NONE; // 无论平仓成功与否都重置信号类型，防止重复处理
            if(AlertOnOrderFail)
               Alert("平仓失败: ", _Symbol); // 如果平仓失败，发出警报
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