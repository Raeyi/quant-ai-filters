//+------------------------------------------------------------------+
//| XAUUSD Tick Proxy Scalping MVP - 简化版                         |
//+------------------------------------------------------------------+
#property strict
#property version "2.2"

//================ 参数 =================
input double InpLots            = 0.01;
input int    InpMinTicks        = 2;      // 连续 tick 数
input int    InpMaxHoldSeconds  = 2;      // 持仓时间
input int    InpCooldownMS      = 300;    // 毫秒冷却
input int    InpSLPoints        = 80;     // 止损点数
input bool   InpPrintLog        = true;
input double InpMinChange       = 0.01;   // 最小价格变化（美元）

//================ 全局 =================
double   lastPrice = 0;
int      upTicks = 0;
int      downTicks = 0;
ulong    lastTradeMS = 0;
bool     inPosition = false;
datetime positionOpenTime = 0;
int      tickCounter = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   Print("Tick Proxy Scalp MVP 初始化完成");
   Print("最小价格变化: ", InpMinChange, " 美元");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnTick()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   ulong nowMS = GetTickCount64();
   
   tickCounter++;
   
   // 如果有持仓，管理出场
   if(inPosition)
   {
      ManageExit();
      if(inPosition) return;  // 仍有持仓则不执行开仓
   }
   
   // 冷却时间检查
   if(lastTradeMS > 0 && (nowMS - lastTradeMS) < (ulong)InpCooldownMS)
   {
      return;
   }
   
   // 第一次运行
   if(lastPrice < 0.1)
   {
      lastPrice = bid;
      return;
   }
   
   double priceChange = bid - lastPrice;
   double absChange = MathAbs(priceChange);
   
   // 更新连续计数（忽略微小变化）
   if(absChange >= InpMinChange)
   {
      if(priceChange > 0)  // 上涨
      {
         upTicks++;
         downTicks = 0;
         if(InpPrintLog && upTicks >= InpMinTicks) 
            Print(StringFormat("连续上涨 %d 次，变化: %.3f", upTicks, priceChange));
      }
      else if(priceChange < 0)  // 下跌
      {
         downTicks++;
         upTicks = 0;
         if(InpPrintLog && downTicks >= InpMinTicks) 
            Print(StringFormat("连续下跌 %d 次，变化: %.3f", downTicks, priceChange));
      }
   }
   else
   {
      // 价格变化太小，重置计数
      if(upTicks > 0 || downTicks > 0)
      {
         if(InpPrintLog && tickCounter % 50 == 0)
            Print("价格停滞，重置计数");
         upTicks = 0;
         downTicks = 0;
      }
   }
   
   // 状态打印
   if(InpPrintLog && tickCounter % 50 == 0)
   {
      Print(StringFormat("状态: bid=%.3f, 上=%d, 下=%d, 持仓=%d", 
            bid, upTicks, downTicks, inPosition));
   }
   
   // 开仓条件检查
   CheckForEntry(bid, priceChange);
   
   lastPrice = bid;
}

//+------------------------------------------------------------------+
void CheckForEntry(double bid, double priceChange)
{
   // 开空条件：连续上涨后下跌
   if(upTicks >= InpMinTicks && priceChange < 0 && MathAbs(priceChange) >= InpMinChange)
   {
      Print(StringFormat("=== 开空信号: 连续上涨%d次后下跌%.3f ===", upTicks, priceChange));
      if(OpenTrade(ORDER_TYPE_SELL))
      {
         upTicks = 0;
         downTicks = 0;
         inPosition = true;
         positionOpenTime = TimeCurrent();
         Print("开空单成功!");
      }
   }
   // 开多条件：连续下跌后上涨
   else if(downTicks >= InpMinTicks && priceChange > 0 && MathAbs(priceChange) >= InpMinChange)
   {
      Print(StringFormat("=== 开多信号: 连续下跌%d次后上涨%.3f ===", downTicks, priceChange));
      if(OpenTrade(ORDER_TYPE_BUY))
      {
         upTicks = 0;
         downTicks = 0;
         inPosition = true;
         positionOpenTime = TimeCurrent();
         Print("开多单成功!");
      }
   }
}

//+------------------------------------------------------------------+
bool OpenTrade(ENUM_ORDER_TYPE type)
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      Print("终端不允许交易");
      return false;
   }
   
   MqlTradeRequest req;
   MqlTradeCheckResult checkResult;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(checkResult);
   ZeroMemory(res);
   
   double price, sl;
   
   if(type == ORDER_TYPE_BUY)
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sl    = NormalizeDouble(price - InpSLPoints * _Point, _Digits);
      Print(StringFormat("开多: 价格=%.3f, 止损=%.3f", price, sl));
   }
   else
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl    = NormalizeDouble(price + InpSLPoints * _Point, _Digits);
      Print(StringFormat("开空: 价格=%.3f, 止损=%.3f", price, sl));
   }
   
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.type      = type;
   req.volume    = InpLots;
   req.price     = price;
   req.sl        = sl;
   req.magic     = 777888;
   req.deviation = 10;
   req.comment   = "TickProxyScalp";
   
   // 检查订单
   if(!OrderCheck(req, checkResult))
   {
      Print("订单检查失败: ", checkResult.comment);
      return false;
   }
   
   // 发送订单
   if(OrderSend(req, res))
   {
      lastTradeMS = GetTickCount64();
      Print(StringFormat("订单成功! 单号: %d, 价格: %.3f", res.order, res.price));
      return true;
   }
   else
   {
      Print(StringFormat("订单失败! 错误: %d, %s", res.retcode, res.comment));
      return false;
   }
}

//+------------------------------------------------------------------+
void ManageExit()
{
   if(!PositionSelect(_Symbol))
   {
      inPosition = false;
      return;
   }
   
   ulong posTicket = PositionGetInteger(POSITION_TICKET);
   datetime currentTime = TimeCurrent();
   
   // 时间出场
   if(currentTime - positionOpenTime >= InpMaxHoldSeconds)
   {
      Print(StringFormat("持仓时间到: %d秒，平仓", currentTime - positionOpenTime));
      ClosePosition();
   }
   // 检查止损（由服务器处理）
   // 可添加其他出场条件
}

//+------------------------------------------------------------------+
void ClosePosition()
{
   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);
   
   if(!PositionSelect(_Symbol)) return;
   
   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.volume = PositionGetDouble(POSITION_VOLUME);
   
   long posType = PositionGetInteger(POSITION_TYPE);
   if(posType == POSITION_TYPE_BUY)
   {
      req.type = ORDER_TYPE_SELL;
      req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   }
   else
   {
      req.type = ORDER_TYPE_BUY;
      req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   }
   
   req.deviation = 10;
   req.comment = "Time Exit";
   
   if(OrderSend(req, res))
   {
      Print("平仓成功! 单号: ", res.order);
      inPosition = false;
      positionOpenTime = 0;
   }
   else
   {
      Print("平仓失败! 错误: ", res.retcode);
   }
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA卸载");
   if(PositionSelect(_Symbol))
   {
      ClosePosition();
   }
}