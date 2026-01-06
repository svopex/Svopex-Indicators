//+------------------------------------------------------------------+
//|                                           OpenRangeBreakout.mq5 |
//|                                  Copyright 2023, Petr Svoboda    |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+

// Navrhni srategii pro metatrader 5.
// Cas v parametru, cas 16:30.
// Prvni patnactiminutova svicka, low a high jsou s/r zony.
// Po prorazeni 3-mi dvouminutovymi svickami (musi uzavrit nad a pod s/r zonou specifikovanou vyse)
// se nastavi limitni prikaz na s/r zonu.
// StopLoss ve velikosti do poloviny prvni patnactiminutove svicky.
// TP aby bylo RRR 1:1.
// Nech obchod probehnout, uzavri nejdele v 22:45, tento cas bude v parametru.

#property copyright "Copyright 2023, Petr Svoboda"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- vstupní parametry
input string   InpStartTime = "16:30";    // Čas začátku (15min svíčka)
input string   InpEndTime   = "23:30";    // Čas ukončení obchodů (včetně uzavření pozic)
input double   InpLotSize   = 0.1;        // Velikost lotu
input double   InpRangeKoef = 0.85;       // Koeficient pro StopLoss (z velikosti 15min svíčky)
input bool     InpBlinkByHue = true;      // Povolit blikání Hue
input int      InpMagicNum  = 123456;     // Magic Number pro identifikaci obchodů

//--- globální proměnné
CTrade         trade;
double         rangeHigh = 0;
double         rangeLow  = 0;
double         rangeSize = 0;
bool           rangeDefined = false;
bool           orderPlaced  = false;
datetime       lastM2Time   = 0;
datetime       currentDay   = 0;

//+------------------------------------------------------------------+
//| Blinking - Původní WinInet implementace                          |
//+------------------------------------------------------------------+
#import "wininet.dll"
   int InternetOpenW(string lpszAgent, int dwAccessType, string lpszProxyName, string lpszProxyBypass, int dwFlags);
   int InternetConnectW(int hInternet, string lpszServerName, int nServerPort, string lpszUsername, string lpszPassword, int dwService, int dwFlags, int dwContext);
   int HttpOpenRequestW(int hConnect, string lpszVerb, string lpszObjectName, string lpszVersion, string lpszReferer, string lpszAcceptTypes, int dwFlags, int dwContext);
   bool HttpSendRequestW(int hRequest, string lpszHeaders, int dwHeadersLength, uchar& lpOptional[], int dwOptionalLength);
   int InternetCloseHandle(int hInternet);
#import

void CallHue()
{
   if(InpBlinkByHue)
   {
      string data = "'ORB!'"; 
      int lineSize = StringLen(data);
      uchar line[];
      ArrayResize(line, lineSize);
      StringToCharArray(data, line, 0, -1);

      string headers = "Content-Type: text/plain; charset=utf-8";
      int HttpOpen = InternetOpenW(" ", 0, " ", "", 0);
      int HttpConnect = InternetConnectW(HttpOpen, "localhost", 80, "", "", 3, 0, 0);
      int HttpRequest = HttpOpenRequestW(HttpConnect, "POST", "/huemax", "", "", "", 0, 0);
      
      bool result = HttpSendRequestW(HttpRequest, headers, StringLen(headers), line, lineSize);
      
      InternetCloseHandle(HttpRequest);
      InternetCloseHandle(HttpConnect);
      InternetCloseHandle(HttpOpen);
   }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNum);
   Print("EA OpenRangeBreakout inicializován.");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA OpenRangeBreakout ukončen.");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   
   // Začátek dne pro resetování stavu
   datetime todayStart = now - (dt.hour * 3600 + dt.min * 60 + dt.sec);
   
   if(todayStart != currentDay)
   {
      currentDay = todayStart;
      rangeDefined = false;
      orderPlaced = false;
      rangeHigh = 0;
      rangeLow = 0;
      lastM2Time = 0;
      Print("Nový obchodní den: ", TimeToString(currentDay, TIME_DATE));
   }

   // Převod parametrů na datetime pro aktuální den
   string dateStr = TimeToString(now, TIME_DATE);
   datetime startTime = StringToTime(dateStr + " " + InpStartTime);
   datetime endTime   = StringToTime(dateStr + " " + InpEndTime);
   
   // 1. Časový exit - uzavření všeho po EndTime
   if(now >= endTime)
   {
      if(PositionsTotal() > 0 || OrdersTotal() > 0)
      {
         CloseAllPositions();
         CancelAllPendingOrders();
         Print("Čas vypršel (", InpEndTime, "). Všechny pozice a objednávky byly uzavřeny.");
      }
      return;
   }

   // 2. Definice S/R zóny z první 15min svíčky (po jejím uzavření)
   if(!rangeDefined && now >= startTime + 15 * 60)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      // Hledáme svíčku, která začala přesně v startTime
      if(CopyRates(_Symbol, PERIOD_M15, startTime, 1, rates) > 0)
      {
         rangeHigh = rates[0].high;
         rangeLow  = rates[0].low;
         rangeSize = rangeHigh - rangeLow;
         rangeDefined = true;
         Print("S/R zóna definována z 15min svíčky: High=", rangeHigh, " Low=", rangeLow, " Range=", rangeSize);
      }
   }

   // 3. Sledování průrazu na M2 a zadání limitního příkazu
   if(rangeDefined && !orderPlaced)
   {
      MqlRates m2Rates[];
      ArraySetAsSeries(m2Rates, true);
      
      // Potřebujeme alespoň 3 uzavřené M2 svíčky
      if(CopyRates(_Symbol, PERIOD_M2, 0, 4, m2Rates) >= 4)
      {
         // Kontrola, zda máme novou uzavřenou M2 svíčku
         if(m2Rates[1].time != lastM2Time)
         {
            lastM2Time = m2Rates[1].time;
            
            // Kontrola 3 po sobě jdoucích uzavřených svíček (indexy 1, 2, 3)
            bool allAbove = true;
            bool allBelow = true;
            
            for(int i=1; i<=3; i++)
            {
               // Svíčky musí uzavřít nad/pod zónou
               if(m2Rates[i].close <= rangeHigh) allAbove = false;
               if(m2Rates[i].close >= rangeLow)  allBelow = false;
               
               // Svíčky musí být časově až po referenční 15min svíčce
               // ÚPRAVA: Povolíme i svíčku, která začala v Range, ale končí až po něm
               if(m2Rates[i].time + 120 <= startTime + 15 * 60)
               {
                  allAbove = false;
                  allBelow = false;
               }
            }
            
            // StopLoss je definován koeficientem z velikosti 15min svíčky
            double sl_dist = rangeSize * InpRangeKoef;
            
            if(allAbove)
            {
               double sl = rangeHigh - sl_dist;
               double tp = rangeHigh + sl_dist; // RRR 1:1
               if(trade.BuyLimit(InpLotSize, rangeHigh, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "ORB Long Limit"))
               {
                  orderPlaced = true;
                  CallHue();
                  Print("Průraz nahoru potvrzen 3x M2. Zadán Buy Limit na ", rangeHigh, " SL: ", sl, " TP: ", tp);
               }
            }
            else if(allBelow)
            {
               double sl = rangeLow + sl_dist;
               double tp = rangeLow - sl_dist; // RRR 1:1
               if(trade.SellLimit(InpLotSize, rangeLow, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "ORB Short Limit"))
               {
                  orderPlaced = true;
                  CallHue();
                  Print("Průraz dolů potvrzen 3x M2. Zadán Sell Limit na ", rangeLow, " SL: ", sl, " TP: ", tp);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Uzavře všechny otevřené pozice s daným Magic Number              |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNum)
            trade.PositionClose(PositionGetTicket(i));
      }
   }
}

//+------------------------------------------------------------------+
//| Zruší všechny čekající objednávky s daným Magic Number           |
//+------------------------------------------------------------------+
void CancelAllPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
      {
         if(OrderGetInteger(ORDER_MAGIC) == InpMagicNum)
            trade.OrderDelete(ticket);
      }
   }
}
