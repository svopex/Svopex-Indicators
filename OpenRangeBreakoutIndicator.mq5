//+------------------------------------------------------------------+
//|                                  OpenRangeBreakoutIndicator.mq5 |
//|                                  Copyright 2023, Petr Svoboda    |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, Petr Svoboda"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_plots 0

//--- vstupní parametry
input string   InpStartTime = "16:30";    // Čas začátku (15min svíčka)
input string   InpEndTime   = "22:45";    // Čas ukončení (včetně smazání linií)
input bool     InpBlinkByHue = true;      // Povolit blikání Hue

//--- globální proměnné
double         rangeHigh = 0;
double         rangeLow  = 0;
bool           rangeDefined = false;
bool           signalFired  = false;
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
      string data = "'BTCUSD Greater Than 9001'"; 
      int lineSize = StringLen(data);
      uchar line[];
      ArrayResize(line, lineSize);
      StringToCharArray(data, line, 0, -1);

      string headers = "Content-Type: text/plain; charset=utf-8";
      int HttpOpen = InternetOpenW(" ", 0, " ", "", 0);
      int HttpConnect = InternetConnectW(HttpOpen, "localhost", 80, "", "", 3, 0, 0);
      int HttpRequest = HttpOpenRequestW(HttpConnect, "POST", "/hue", "", "", "", 0, 0);
      
      bool result = HttpSendRequestW(HttpRequest, headers, StringLen(headers), line, lineSize);
      
      InternetCloseHandle(HttpRequest);
      InternetCloseHandle(HttpConnect);
      InternetCloseHandle(HttpOpen);
   }
}

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpBlinkByHue && !TerminalInfoInteger(TERMINAL_DLLS_ALLOWED))
   {
      Print("ORB Error: Povolte DLL importy v nastavení MetaTraderu pro funkci Hue!");
   }
   
   EventSetTimer(2); // Timer pro případ, že nejsou ticky (víkend) nebo se čeká na data
   Print("ORB Indicator: Inicializace úspěšná.");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, "ORB_");
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < 10) return(0);

   // Kontrola dostupnosti dat pro M15 a M2
   int bars15 = iBars(_Symbol, PERIOD_M15);
   int bars2  = iBars(_Symbol, PERIOD_M2);
   
   if(bars15 <= 0 || bars2 <= 0) 
   {
      static datetime lastPrint = 0;
      if(TimeCurrent() - lastPrint > 10)
      {
         PrintFormat("ORB Indicator: Čekám na data (M15: %d, M2: %d)...", bars15, bars2);
         lastPrint = TimeCurrent();
      }
      // Vynucení načtení dat ze serveru
      datetime dummy[];
      CopyTime(_Symbol, PERIOD_M15, 0, 1, dummy);
      CopyTime(_Symbol, PERIOD_M2, 0, 1, dummy);
      return(0); 
   }
   
   // Nastavení polí jako série (index 0 je nejnovější)
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   int limit = rates_total - prev_calculated;
   if(prev_calculated == 0) 
   {
      limit = rates_total - 1;
      ObjectsDeleteAll(0, "ORB_"); 
   }
   else limit++; 
   
   if(limit >= rates_total) limit = rates_total - 1;

   // Procházíme historii od nejstarších po nejnovější
   for(int i = limit; i >= 0; i--)
   {
      datetime barTime = time[i];
      MqlDateTime dt;
      TimeToStruct(barTime, dt);
      
      // Začátek dne pro aktuální bar
      datetime dayStart = barTime - (dt.hour * 3600 + dt.min * 60 + dt.sec);
      string dateStr = TimeToString(dayStart, TIME_DATE);
      
      datetime startTime = StringToTime(dateStr + " " + InpStartTime);
      datetime endTime   = StringToTime(dateStr + " " + InpEndTime);
      
      // Pokud jsme v čase po 15min svíčce
      if(barTime >= startTime + 15 * 60 && barTime <= endTime)
      {
         string highName = "ORB_High_" + dateStr;
         string lowName  = "ORB_Low_" + dateStr;
         
         // Pokud linky ještě neexistují, vytvoříme je
         if(ObjectFind(0, highName) < 0)
         {
            MqlRates rates15[];
            if(CopyRates(_Symbol, PERIOD_M15, startTime, 1, rates15) > 0)
            {
               CreateLine(highName, startTime, rates15[0].high, clrBlue);
               CreateLine(lowName, startTime, rates15[0].low, clrRed);
            }
            else if(i == 0) return(0); // Pokud selže CopyRates pro aktuální den, zkusíme to znovu příště
         }
         
         // Pokud linky existují, aktualizujeme jejich konec na aktuální bar
         if(ObjectFind(0, highName) >= 0)
         {
            ObjectSetInteger(0, highName, OBJPROP_TIME, 1, barTime);
            ObjectSetInteger(0, lowName, OBJPROP_TIME, 1, barTime);
            
            // Kontrola signálu na M2 (pouze pokud ještě nebyl signál pro tento den)
            string sigName = "ORB_Sig_" + dateStr;
            if(ObjectFind(0, sigName) < 0)
            {
               double dHigh = ObjectGetDouble(0, highName, OBJPROP_PRICE, 0);
               double dLow  = ObjectGetDouble(0, lowName, OBJPROP_PRICE, 0);
               
               datetime sigTime = CheckSignalForBar(barTime, startTime, endTime, dHigh, dLow);
               if(sigTime > 0)
               {
                  // Vytvoříme značku signálu (např. svislou čáru nebo text)
                  ObjectCreate(0, sigName, OBJ_VLINE, 0, sigTime, 0);
                  ObjectSetInteger(0, sigName, OBJPROP_COLOR, clrYellow);
                  ObjectSetInteger(0, sigName, OBJPROP_STYLE, STYLE_DOT);
                  
                  // Pokud je to aktuální čas, blikáme
                  if(i <= 1) CallHue();
               }
            }
         }
      }
   }

   ChartRedraw();
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Kontrola signálu pro konkrétní čas                               |
//+------------------------------------------------------------------+
datetime CheckSignalForBar(datetime barTime, datetime startTime, datetime endTime, double dHigh, double dLow)
{
   if(dHigh <= 0) return 0;
   
   MqlRates m2[];
   ArraySetAsSeries(m2, true);
   // Kopírujeme 4 svíčky, abychom měli jistotu, že najdeme 3 kompletní
   if(CopyRates(_Symbol, PERIOD_M2, barTime, 4, m2) >= 3)
   {
      bool allAbove = true;
      bool allBelow = true;
      int found = 0;
      datetime sigTime = 0;
      
      for(int j=0; j<ArraySize(m2); j++)
      {
         // Svíčka je kompletní pouze pokud barTime je alespoň na jejím konci (začátek + 2 minuty)
         if(barTime < m2[j].time + 120) continue; 
         
         if(m2[j].close <= dHigh) allAbove = false;
         if(m2[j].close >= dLow)  allBelow = false;
         if(m2[j].time < startTime + 15 * 60) { allAbove = false; allBelow = false; }
         
         if(found == 0) sigTime = m2[j].time; // Čas poslední kompletní svíčky
         
         found++;
         if(found == 3) break;
      }
      
      if(found == 3 && (allAbove || allBelow)) return sigTime;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Pomocná funkce pro vytvoření trendové linky                      |
//+------------------------------------------------------------------+
void CreateLine(string name, datetime t1, double p1, color clr)
{
   ObjectDelete(0, name);
   if(ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t1 + 60, p1))
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   }
}
//+------------------------------------------------------------------+
