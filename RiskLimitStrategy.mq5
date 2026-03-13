#property strict
#property version   "1.00"
#property description "EA pro zadani limitniho prikazu podle risku a RR z chart editboxu."

input double InpRiskPercent = 1.0;
input double InpRewardRiskRatio = 2.0;
input ulong  InpMagicNumber = 26031301;
input int    InpSlippagePoints = 10;
input int    InpPanelTopOffset = 150;

string PREFIX = "RiskLimitStrategy_";
string RISK_EDIT;
string ENTRY_EDIT;
string SL_EDIT;
string RR_EDIT;
string SEND_BUTTON;
string SEND_BUTTON_RR2;
string SEND_BUTTON_RR1;
string RISK_LABEL;
string ENTRY_LABEL;
string SL_LABEL;
string RR_LABEL;
string PANEL_BG;
string PANEL_HEADER_BG;
string TITLE_LABEL;

int OnInit()
{
   RISK_EDIT = PREFIX + "RiskEdit";
   ENTRY_EDIT = PREFIX + "EntryEdit";
   SL_EDIT = PREFIX + "SlEdit";
   RR_EDIT = PREFIX + "RrEdit";
   SEND_BUTTON = PREFIX + "SendButton";
   SEND_BUTTON_RR2 = PREFIX + "SendButtonRr2";
   SEND_BUTTON_RR1 = PREFIX + "SendButtonRr1";
   RISK_LABEL = PREFIX + "RiskLabel";
   ENTRY_LABEL = PREFIX + "EntryLabel";
   SL_LABEL = PREFIX + "SlLabel";
   RR_LABEL = PREFIX + "RrLabel";
   PANEL_BG = PREFIX + "PanelBg";
   PANEL_HEADER_BG = PREFIX + "PanelHeaderBg";
   TITLE_LABEL = PREFIX + "TitleLabel";

   CreatePanel();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   ObjectDelete(0, RISK_EDIT);
   ObjectDelete(0, ENTRY_EDIT);
   ObjectDelete(0, SL_EDIT);
   ObjectDelete(0, RR_EDIT);
   ObjectDelete(0, SEND_BUTTON);
   ObjectDelete(0, SEND_BUTTON_RR2);
   ObjectDelete(0, SEND_BUTTON_RR1);
   ObjectDelete(0, RISK_LABEL);
   ObjectDelete(0, ENTRY_LABEL);
   ObjectDelete(0, SL_LABEL);
   ObjectDelete(0, RR_LABEL);
   ObjectDelete(0, PANEL_BG);
   ObjectDelete(0, PANEL_HEADER_BG);
   ObjectDelete(0, TITLE_LABEL);
}

void OnTick()
{
}

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   if(sparam == SEND_BUTTON)
   {
      SubmitPendingOrder();
      return;
   }

   if(sparam == SEND_BUTTON_RR2)
   {
      SubmitPresetOrder(2.0);
      return;
   }

   if(sparam == SEND_BUTTON_RR1)
      SubmitPresetOrder(1.0);
}

void CreatePanel()
{
   int panelLeft = 0;
   int panelTop = MathMax(0, InpPanelTopOffset);
   int panelWidth = 420;
   int panelHeight = 479;
   int headerHeight = 50;
   int contentLeft = panelLeft + 14;
   int labelWidth = 150;
   int gap = 14;
   int controlWidth = panelWidth - 28 - labelWidth - gap;
   int editLeft = contentLeft + labelWidth + gap;

   // Pozadi panelu -- vytvori se jako prvni, tedy vizualne dole
   CreatePanelBackground(PANEL_BG, panelLeft, panelTop, panelWidth, panelHeight, C'22,26,32', clrSlateGray);
   CreatePanelBackground(PANEL_HEADER_BG, panelLeft, panelTop, panelWidth, headerHeight, C'32,78,122', C'32,78,122');

   // Titulkovy label
   CreateLabel(TITLE_LABEL, "Risk Limit Strategy", contentLeft, panelTop + 11, clrWhite, 13);

   // Popisky vlevo, editboxy vpravo
   CreateLabel(ENTRY_LABEL, "Limit cena:", contentLeft, panelTop + 78, clrWhite, 12);
   CreateLabel(SL_LABEL, "SL cena:", contentLeft, panelTop + 140, clrWhite, 12);
   CreateLabel(RR_LABEL, "RR pomer:", contentLeft, panelTop + 202, clrWhite, 12);
   CreateLabel(RISK_LABEL, "Risk %:", contentLeft, panelTop + 264, clrWhite, 12);

   // Interaktivni prvky (vytvori se jako posledni = na vrchu GUI vrstvy)
   CreateEdit(ENTRY_EDIT, "0.0", editLeft, panelTop + 64, controlWidth, 50, 16);
   CreateEdit(SL_EDIT, "0.0", editLeft, panelTop + 126, controlWidth, 50, 16);
   CreateEdit(RR_EDIT, DoubleToString(InpRewardRiskRatio, 2), editLeft, panelTop + 188, controlWidth, 50, 16);
   CreateEdit(RISK_EDIT, DoubleToString(InpRiskPercent, 2), editLeft, panelTop + 250, controlWidth, 50, 16);
   CreateButton(SEND_BUTTON, "Zadat prikaz", contentLeft, panelTop + 311, panelWidth - 28, 44, 13);
   CreateButton(SEND_BUTTON_RR2, "RR 2:1 | 1/2 risk", contentLeft, panelTop + 368, panelWidth - 28, 44, 11);
   CreateButton(SEND_BUTTON_RR1, "RR 1:1 | 1/2 risk", contentLeft, panelTop + 425, panelWidth - 28, 44, 11);
}

void CreateLabel(const string name,
                 const string text,
                 const int x,
                 const int y,
                 const color textColor,
                 const int fontSize)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 0);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void CreateEdit(const string name,
                const string text,
                const int x,
                const int y,
                const int width,
                const int height,
                const int fontSize)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, C'45,49,56');
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrSlateGray);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_READONLY, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 1);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void CreateButton(const string name,
                  const string text,
                  const int x,
                  const int y,
                  const int width,
                  const int height,
                  const int fontSize)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrDodgerBlue);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrRoyalBlue);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 1);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void CreatePanelBackground(const string name,
                           const int x,
                           const int y,
                           const int width,
                           const int height,
                           const color backgroundColor,
                           const color borderColor)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, backgroundColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, borderColor);
   ObjectSetInteger(0, name, OBJPROP_COLOR, borderColor);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 0);
}

bool ReadPriceFromEdit(const string objectName, double &price)
{
   string raw = ObjectGetString(0, objectName, OBJPROP_TEXT);
   StringTrimLeft(raw);
   StringTrimRight(raw);
   StringReplace(raw, ",", ".");

   if(raw == "")
      return(false);

   price = StringToDouble(raw);
   return(price > 0.0);
}

bool ReadDoubleFromEdit(const string objectName, double &value)
{
   string raw = ObjectGetString(0, objectName, OBJPROP_TEXT);
   StringTrimLeft(raw);
   StringTrimRight(raw);
   StringReplace(raw, ",", ".");

   if(raw == "")
      return(false);

   value = StringToDouble(raw);
   return(true);
}

ENUM_ORDER_TYPE_FILLING ResolveFillingMode(const ENUM_TRADE_REQUEST_ACTIONS requestAction)
{
   long fillingFlags = 0;
   if(!SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE, fillingFlags))
      return(requestAction == TRADE_ACTION_PENDING ? ORDER_FILLING_RETURN : ORDER_FILLING_IOC);

   if(requestAction == TRADE_ACTION_PENDING)
   {
      if((fillingFlags & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
         return(ORDER_FILLING_IOC);
      if((fillingFlags & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
         return(ORDER_FILLING_FOK);
      return(ORDER_FILLING_RETURN);
   }

   if((fillingFlags & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return(ORDER_FILLING_IOC);
   if((fillingFlags & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return(ORDER_FILLING_FOK);

   return(ORDER_FILLING_RETURN);
}

void SubmitPendingOrder()
{
   SubmitOrderFromUi(true, 0.0, false);
}

void SubmitPresetOrder(const double fixedRewardRiskRatio)
{
   SubmitOrderFromUi(false, fixedRewardRiskRatio, true);
}

void SubmitOrderFromUi(const bool useManualRewardRiskRatio,
                      const double fixedRewardRiskRatio,
                      const bool useHalfRisk)
{
   double riskPercent = 0.0;
   double entryPrice = 0.0;
   double stopLoss = 0.0;
   double rewardRiskRatio = 0.0;

   if(!ReadPriceFromEdit(RISK_EDIT, riskPercent))
   {
      Print("Neplatna hodnota risk procenta.");
      return;
   }

   if(useHalfRisk)
      riskPercent *= 0.5;

   if(!ReadDoubleFromEdit(ENTRY_EDIT, entryPrice))
   {
      Print("Neplatna hodnota limit ceny.");
      return;
   }

   if(!ReadPriceFromEdit(SL_EDIT, stopLoss))
   {
      Print("Neplatna hodnota SL ceny.");
      return;
   }

   if(useManualRewardRiskRatio)
   {
      if(!ReadPriceFromEdit(RR_EDIT, rewardRiskRatio))
      {
         Print("Neplatna hodnota RR pomeru.");
         return;
      }
   }
   else
   {
      rewardRiskRatio = fixedRewardRiskRatio;
   }

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   entryPrice = NormalizeDouble(entryPrice, digits);
   stopLoss = NormalizeDouble(stopLoss, digits);

   ENUM_TRADE_REQUEST_ACTIONS requestAction;
   ENUM_ORDER_TYPE orderType;
   ENUM_ORDER_TYPE marketSide;
   double executionPrice = 0.0;
   double takeProfit = 0.0;

   if(!ResolveOrderSetup(entryPrice, stopLoss, rewardRiskRatio, requestAction, orderType, marketSide, executionPrice, takeProfit))
      return;

   double volume = CalculatePositionSize(executionPrice, stopLoss, marketSide, riskPercent);
   if(volume <= 0.0)
   {
      Print("Nepodarilo se spocitat objem pozice.");
      return;
   }

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = requestAction;
   request.magic = InpMagicNumber;
   request.symbol = _Symbol;
   request.volume = volume;
   request.price = executionPrice;
   request.sl = stopLoss;
   request.tp = takeProfit;
   request.deviation = InpSlippagePoints;
   request.type = orderType;
   request.type_filling = ResolveFillingMode(requestAction);
   if(requestAction == TRADE_ACTION_PENDING)
      request.type_time = ORDER_TIME_GTC;
   request.comment = "Risk limit strategy";

   if(!OrderSend(request, result))
   {
      Print("OrderSend selhal. Kod: " + IntegerToString((int)GetLastError()));
      return;
   }

   if(result.retcode != TRADE_RETCODE_DONE && result.retcode != TRADE_RETCODE_PLACED)
   {
      Print("Broker odmitl pozadavek. Retcode: " + IntegerToString((int)result.retcode));
      return;
   }

   string orderTypeText = EnumToString(orderType);
   Print(orderTypeText + " odeslan. Lot: " + DoubleToString(volume, 2) + ", TP: " + DoubleToString(takeProfit, digits));
}

bool ResolveOrderSetup(const double entryPrice,
                       const double stopLoss,
                       const double rewardRiskRatio,
                       ENUM_TRADE_REQUEST_ACTIONS &requestAction,
                       ENUM_ORDER_TYPE &orderType,
                       ENUM_ORDER_TYPE &marketSide,
                       double &executionPrice,
                       double &takeProfit)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if(InpRiskPercent <= 0.0)
   {
      Print("Risk procent musi byt vetsi nez nula.");
      return(false);
   }

   if(rewardRiskRatio <= 0.0)
   {
      Print("RR musi byt vetsi nez nula.");
      return(false);
   }

   if(entryPrice < 0.0)
   {
      Print("Limit cena nesmi byt zaporna.");
      return(false);
   }

   if(entryPrice > 0.0 && entryPrice == stopLoss)
   {
      Print("Entry a SL nesmi byt stejne.");
      return(false);
   }

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(entryPrice == 0.0)
   {
      if(stopLoss < ask)
      {
         double stopDistance = ask - stopLoss;
         if(stopDistance < point)
         {
            Print("Rozdil mezi market cenou a SL je prilis maly.");
            return(false);
         }

         requestAction = TRADE_ACTION_DEAL;
         orderType = ORDER_TYPE_BUY;
         marketSide = ORDER_TYPE_BUY;
         executionPrice = NormalizeDouble(ask, digits);
         takeProfit = NormalizeDouble(executionPrice + stopDistance * rewardRiskRatio, digits);
         return(true);
      }

      if(stopLoss > bid)
      {
         double stopDistance = stopLoss - bid;
         if(stopDistance < point)
         {
            Print("Rozdil mezi market cenou a SL je prilis maly.");
            return(false);
         }

         requestAction = TRADE_ACTION_DEAL;
         orderType = ORDER_TYPE_SELL;
         marketSide = ORDER_TYPE_SELL;
         executionPrice = NormalizeDouble(bid, digits);
         takeProfit = NormalizeDouble(executionPrice - stopDistance * rewardRiskRatio, digits);
         return(true);
      }

      Print("Pro market vstup musi byt SL pod cenou pro BUY nebo nad cenou pro SELL.");
      return(false);
   }

   double stopDistance = MathAbs(entryPrice - stopLoss);
   if(stopDistance < point)
   {
      Print("Rozdil mezi entry a SL je prilis maly.");
      return(false);
   }

   if(entryPrice < ask && stopLoss < entryPrice)
   {
      requestAction = TRADE_ACTION_PENDING;
      orderType = ORDER_TYPE_BUY_LIMIT;
      marketSide = ORDER_TYPE_BUY;
      executionPrice = entryPrice;
      takeProfit = NormalizeDouble(entryPrice + stopDistance * rewardRiskRatio, digits);
      return(true);
   }

   if(entryPrice > bid && stopLoss > entryPrice)
   {
      requestAction = TRADE_ACTION_PENDING;
      orderType = ORDER_TYPE_SELL_LIMIT;
      marketSide = ORDER_TYPE_SELL;
      executionPrice = entryPrice;
      takeProfit = NormalizeDouble(entryPrice - stopDistance * rewardRiskRatio, digits);
      return(true);
   }

   Print("Urovne neodpovidaji BUY LIMIT ani SELL LIMIT logice.");
   return(false);
}

double CalculatePositionSize(const double entryPrice,
                             const double stopLoss,
                             const ENUM_ORDER_TYPE marketSide,
                             const double riskPercent)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = equity * riskPercent / 100.0;
   if(riskAmount <= 0.0)
      return(0.0);

   double estimatedLoss = 0.0;
   if(!OrderCalcProfit(marketSide, _Symbol, 1.0, entryPrice, stopLoss, estimatedLoss))
      return(0.0);

   estimatedLoss = MathAbs(estimatedLoss);
   if(estimatedLoss <= 0.0)
      return(0.0);

   double rawVolume = riskAmount / estimatedLoss;
   return(NormalizeVolume(rawVolume));
}

double NormalizeVolume(const double rawVolume)
{
   double minVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double volumeStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(volumeStep <= 0.0)
      return(0.0);

   double clamped = MathMax(minVolume, MathMin(maxVolume, rawVolume));
   double steps = MathFloor(clamped / volumeStep);
   double normalized = steps * volumeStep;

   if(normalized < minVolume)
      normalized = minVolume;

   int volumeDigits = 0;
   double stepProbe = volumeStep;
   while(volumeDigits < 8 && MathRound(stepProbe) != stepProbe)
   {
      stepProbe *= 10.0;
      volumeDigits++;
   }

   return(NormalizeDouble(normalized, volumeDigits));
}