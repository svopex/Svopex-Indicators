//+------------------------------------------------------------------+
//|                                                 SvpOrderSize.mq5 |
//|                        Copyright 2021, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2021, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property indicator_chart_window

int static counter;

input color font_color = White;
input color font_color_reduced_position_size = Red;
input int font_size = 9;
input string font_face = "Arial";
input int spread_distance_x = 5;
#ifdef __MQL4__
input int spread_distance_y = 70;
#else
input int spread_distance_y = 70;
#endif
input double equity = 0; // Pokud je nula, bere se skutecna equity castka.
input double percentFromCapital = 0.01; // Risk na jeden obchod.
input bool fullTradeVolume = false; // Zobrazeni volume i pro pozice 60%, 30% a 10%.
input double marginRate = 0; // Potencialni margin rate pro korekci vypoctu
input string marginRateSymbols; //EURUSD,BTCUSD
input string marginRates; //0.01,0.2
input ENUM_ANCHOR_POINT corner = ANCHOR_LEFT_UPPER;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnStart()
  {
   counter = 0;
   EventSetMillisecondTimer(1);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnInit()
  {
   counter = 0;
   EventSetMillisecondTimer(1);
   if(!GlobalVariableCheck("SvpOrderSize_ShowLines"))
     {
      GlobalVariableSet("SvpOrderSize_ShowLines", 1);
     }
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double CzechCourse(string currency = "USD")
  {
// Ziskej kurz koruny vuci currency (defaultne USD)
#ifdef __MQL4__
   string usdCzk = currency + AccountInfoString(ACCOUNT_CURRENCY) + "_ecn";
   double vbid = MarketInfo(usdCzk, MODE_BID);
   double vask = MarketInfo(usdCzk, MODE_ASK);
#endif
#ifdef __MQL5__
   string usdCzk = currency + AccountInfoString(ACCOUNT_CURRENCY);
   double vbid = SymbolInfoDouble(usdCzk, SYMBOL_BID);
   double vask = SymbolInfoDouble(usdCzk, SYMBOL_ASK);
#endif
   return (vbid + vask) / 2;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double Price(string currency = "USD")
  {
// Ziskej kurz koruny vuci currency (defaultne USD)
#ifdef __MQL4__
   return ((MarketInfo(Symbol(), MODE_ASK) + MarketInfo(Symbol(), MODE_BID)) / 2);
#endif
#ifdef __MQL5__
   return (SymbolInfoDouble(Symbol(), SYMBOL_ASK) + SymbolInfoDouble(Symbol(), SYMBOL_BID)) / 2;
#endif
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetMarginRate()
  {
   string mrs[100];
   double mr[100];
   int length = StrToStringArray(marginRateSymbols, mrs);
   length = StrToDoubleArray(marginRates, mr);
   for(int i = 0; i < length; i++)
     {
      if(Symbol() == mrs[i])
        {
         return mr[i];
        }
     }
   return marginRate;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Calculate(int i, int row)
  {
   double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double accountEquity = equity > 0 ? equity : AccountInfoDouble(ACCOUNT_EQUITY);
   
   if(tickValue > 0 && accountEquity > 0)
     {

      double tradeVolume = accountEquity * percentFromCapital / (i * tickValue);
#ifdef __MQL4__
      if(Symbol() == "CL_ecn" || Symbol() == "DAX_ecn" || Symbol() == "NSDQ_ecn")
#endif
#ifdef __MQL5__
         if(Symbol() == "BRENT1" || Symbol() == "NGAS1")
#endif
           {
            // Hodnota tickValue je chybne v USD a ne v Kc!!! Chyba, mozna u PurpleTrading!

            // accountEquity - je v Kc.
            //printf(accountEquity);

            // MODE_TICKVALUE = 1 USD je MODE_TICKSIZE = 0.001 hodnoty CL -  Odpocida, 0.001 CL je 1 USD.
            //printf(MarketInfo(Symbol(), MODE_TICKVALUE) + ", " + MarketInfo(Symbol(), MODE_TICKSIZE));

            // Treba 24.5 Kc/USD
            //printf("czechCourse "+ CzechCourse());

            // Pro CL 1000 bodu, jeden bod je za 1 USD * kurz USDCZK...
            // 500000 * 0.01 / (1000 * 1 * 24.5)
            tradeVolume = accountEquity * percentFromCapital / (i * tickValue * CzechCourse());
           }

#ifdef __MQL4__
      double accountFreeMargin = AccountFreeMargin();
#endif
#ifdef __MQL5__
      double accountFreeMargin = AccountInfoDouble(ACCOUNT_FREEMARGIN);
#endif

      double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
      //printf(tickSize + " " + tickValue + " " + Price() + " " + tickValue / tickSize * Price());


      bool showReducedPositionSize = false;
      double reducedPositionSize = 0;
      //double margin = tradeVolume * Price() * CzechCourse() * marginRate * MarketInfo(Symbol(), MODE_TICKVALUE) / MarketInfo(Symbol(), MODE_TICKSIZE);
      double margin = tradeVolume * Price() * tickValue / tickSize * GetMarginRate();

      //printf("!" + margin + " " + accountFreeMargin);

      if(margin > accountFreeMargin)
        {
         reducedPositionSize = tradeVolume;
         tradeVolume = tradeVolume / margin * accountEquity;
         showReducedPositionSize = true;
        }

      //printf(AverageCandleSize());

      string volumeName = "SvpOrderSize_Volume" + IntegerToString(row);
      if(GlobalVariableGet("SvpOrderSize_ShowLines") > 0.5)
        {
         ObjectDelete(0, volumeName);
         ObjectCreate(0, volumeName, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, volumeName, OBJPROP_ANCHOR, corner);
         ObjectSetInteger(0, volumeName, OBJPROP_XDISTANCE, spread_distance_x * GetDesktopScaling(false));
         ObjectSetInteger(0, volumeName, OBJPROP_YDISTANCE, spread_distance_y * GetDesktopScaling(false)  + (int)NormalizeDouble((row + 1) * font_size * GetDesktopScaling(true), 0));
         string tradeVolumeResult = IntegerToString(i) + ": " + DoubleToString(NormalizeDouble(tradeVolume, 2), 2);
         if(fullTradeVolume)
           {
            tradeVolumeResult += " (" + DoubleToString(NormalizeDouble(tradeVolume / 100 * 60, 2), 2) + ", " + DoubleToString(NormalizeDouble(tradeVolume / 100 * 30, 2), 2) + ", " + DoubleToString(NormalizeDouble(tradeVolume / 100 * 10, 2), 2) +  ")";
           }
         if(showReducedPositionSize)
           {
            if(fullTradeVolume)
              {
               tradeVolumeResult += ", " + DoubleToString(NormalizeDouble(reducedPositionSize, 2), 2);
               tradeVolumeResult += " (" + DoubleToString(NormalizeDouble(reducedPositionSize / 100 * 60, 2), 2) + ", " + DoubleToString(NormalizeDouble(reducedPositionSize / 100 * 30, 2), 2) + ", " + DoubleToString(NormalizeDouble(reducedPositionSize / 100 * 10, 2), 2) +  ")";
              }
            else
              {
               tradeVolumeResult += " (" + DoubleToString(NormalizeDouble(reducedPositionSize, 2), 2) + ")";
              }
           }
         ObjectSetString(0, volumeName, OBJPROP_TEXT, /*((i == 50 || i == 75 || i == 50000) ? "0" : "") + */ tradeVolumeResult);
         ObjectSetString(0, volumeName, OBJPROP_FONT, font_face);
         ObjectSetInteger(0, volumeName, OBJPROP_FONTSIZE, font_size);
         if(showReducedPositionSize)
           {
            ObjectSetInteger(0, volumeName, OBJPROP_COLOR, font_color_reduced_position_size);
           }
         else
           {
            ObjectSetInteger(0, volumeName, OBJPROP_COLOR, font_color);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Clean();
   EventKillTimer();
  }
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//|                                                                  |
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
   OnTimer();
   return(rates_total);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int MyDigits(string symbol)
  {
   int digits = SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   return digits;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double AverageCandleSize()
  {
   double avg = 0;
   for(int shift = 0; shift < 180; shift++)
     {
      double low = NormalizeDouble(iLow(Symbol(), Period(), shift), MyDigits(Symbol()));
      double high = NormalizeDouble(iHigh(Symbol(), Period(), shift), MyDigits(Symbol()));
      avg += (high - low);
     }
   avg = avg / 180;
   avg =  avg * MathPow(10, MyDigits(Symbol()));
   return avg;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Clean()
  {
   for(int j = 0; j < 150; j++)
     {
      string volumeName = "SvpOrderSize_Volume" + IntegerToString(j);
      ObjectDelete(0, volumeName);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Calculate(int from, int to, int step)
  {
   Clean();
   int row = 0;
   for(int i = from; i <= to; i += step)
     {
      Calculate(i, row++);
     }
  }

struct trade_limits
  {
   int               csLow;
   int               csHi;
   int               from;
   int               to;
   int               step;
  };
trade_limits limits[] =
  {
     {10, 100, 10, 650, 20 }, // OIL
     {100, 400, 50, 1200, 50}, // FOREX
     {400, 3000, 200, 10000, 250}, // WHEAT
     {3000, 10000, 2000, 40000, 1000}, // GOLD
     {10000, 100000, 10000, 130000, 5000}, // BTC
     {100000, 800000, 50000, 950000, 50000}, // BTC
  };

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetDesktopScaling(bool rowCorrection)
  {
   int     desktopScreenDpi = TerminalInfoInteger(TERMINAL_SCREEN_DPI);
   double desktopScaling = desktopScreenDpi > 96.0 ? desktopScreenDpi / 96.0 : 1.0;
   if(rowCorrection)
     {
      desktopScaling = desktopScaling * 1.5;
     }
   return desktopScaling;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTimer()
  {
   if(counter >= 0)
     {
      if(counter > 0)
        {
         // Podle counteru pripadne vynech rendering.
         counter--;
         return;
        }
      counter = 0; // Sem lze dat pocet vynechani spusteni funkcionality ontimer, nula posti se vzdy.
      EventSetTimer(10); // Renderuj kazdych 10 sec.
     }
   else
     {
      // counter == -1, jsem ve stavu po spusteni z OnInit().
      counter = 0; // Priste zase spust hned.
     }
   int row = 0;        
   for(int l = 0; l < ArraySize(limits); l++)
     {
      if(AverageCandleSize() > limits[l].csLow && AverageCandleSize() <= limits[l].csHi)
        {
         Calculate(limits[l].from, limits[l].to, limits[l].step);
        }
     }
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,         // Event ID
                  const long & lparam,  // Parameter of type long eventff
                  const double & dparam, // Parameter of type double event
                  const string & sparam) // Parameter of type string events
  {
   if(id == CHARTEVENT_KEYDOWN)
     {
      if(lparam == 70)
        {
         if(GlobalVariableGet("SvpOrderSize_ShowLines") > 0.5)
           {
            GlobalVariableSet("SvpOrderSize_ShowLines", 0);
           }
         else
           {
            GlobalVariableSet("SvpOrderSize_ShowLines", 1);
           }
         counter = 0;
         EventSetMillisecondTimer(1);
        }
     }
  }
//+------------------------------------------------------------------+

//+----------------------------------------------------------------------------+
//| int StrToDoubleArray(string str, double &a[], string delim=",", int init=0)
//+----------------------------------------------------------------------------+
// Breaks down a single string into double array 'a' (elements delimited by 'delim')
//  e.g. string is "1,2,3,4,5";  if delim is "," then the result will be
//  a[0]=1.0   a[1]=2.0   a[2]=3.0   a[3]=4.0   a[4]=5.0
//  Unused array elements are initialized by value in 'init' (default is 0)
//+----------------------------------------------------------------------------+
int StrToDoubleArray(string str, double &a[], string delim=",", int init=0)
  {
   for(int i=0; i<ArraySize(a); i++)
      a[i] = init;
   int z1=-1, z2=0;
   if(StringRight(str,1) != delim)
      str = str + delim;
#ifdef __MQL4__      
   for(i=0; i<ArraySize(a); i++)
#endif
#ifdef __MQL5__
   for(int i=0; i<ArraySize(a); i++)
#endif
     {
      z2 = StringFind(str,delim,z1+1);
      a[i] = StrToNumber(StringSubstr(str,z1+1,z2-z1-1));
      if(z2 >= StringLen(str)-1)
         break;
      z1 = z2;
     }
   return(StringFindCount(str,delim));
  }

//+----------------------------------------------------------------------------+
//| int StrToIntegerArray(string str, int &a[], string delim=",", int init=0)
//+----------------------------------------------------------------------------+
// Breaks down a single string into integer array 'a' (elements delimited by 'delim')
//  e.g. string is "1,2,3,4,5";  if delim is "," then the result will be
//  a[0]=1   a[1]=2   a[2]=3   a[3]=4   a[4]=5
//  Unused array elements are initialized by value in 'init' (default is 0)
//+----------------------------------------------------------------------------+
int StrToIntegerArray(string str, int &a[], string delim=",", int init=0)
  {
   for(int i=0; i<ArraySize(a); i++)
      a[i] = init;
   int z1=-1, z2=0;
   if(StringRight(str,1) != delim)
      str = str + delim;
#ifdef __MQL4__      
   for(i=0; i<ArraySize(a); i++)
#endif
#ifdef __MQL5__
   for(int i=0; i<ArraySize(a); i++)
#endif
     {
      z2 = StringFind(str,delim,z1+1);
      a[i] = StrToNumber(StringSubstr(str,z1+1,z2-z1-1));
      if(z2 >= StringLen(str)-1)
         break;
      z1 = z2;
     }
   return(StringFindCount(str,delim));
  }

//+----------------------------------------------------------------------------+
//| int StrToStringArray(string str, string &a[], string delim=",", string init="")
//+----------------------------------------------------------------------------+
// Breaks down a single string into string array 'a' (elements delimited by 'delim')
//+----------------------------------------------------------------------------+
int StrToStringArray(string str, string &a[], string delim=",", string init="")
  {
   for(int i=0; i<ArraySize(a); i++)
      a[i] = init;
   int z1=-1, z2=0;
   if(StringRight(str,1) != delim)
      str = str + delim;
#ifdef __MQL4__      
   for(i=0; i<ArraySize(a); i++)
#endif
#ifdef __MQL5__
   for(int i=0; i<ArraySize(a); i++)
#endif
     {
      z2 = StringFind(str,delim,z1+1);
      a[i] = StringSubstr(str,z1+1,z2-z1-1);
      if(z2 >= StringLen(str)-1)
         break;
      z1 = z2;
     }
   return(StringFindCount(str,delim));
  }

//+----------------------------------------------------------------------------+
//| string StringRight(string str, int n=1)
//+----------------------------------------------------------------------------+
// Returns the rightmost N characters of STR, if N is positive
// Usage:    string x=StringRepeat("ABCDEFG",2)  returns x = "FG"
//
// Returns all but the leftmost N characters of STR, if N is negative
// Usage:    string x=StringRepeat("ABCDEFG",-2)  returns x = "CDEFG"
//+----------------------------------------------------------------------------+
string StringRight(string str, int n=1)
  {
   if(n > 0)
      return(StringSubstr(str,StringLen(str)-n,n));
   if(n < 0)
      return(StringSubstr(str,-n,StringLen(str)-n));
   return("");
  }

//+----------------------------------------------------------------------------+
//| int StringFindCount(string str, string str2)
//+----------------------------------------------------------------------------+
// Returns the number of occurrences of STR2 in STR
// Usage:   int x = StringFindCount("ABCDEFGHIJKABACABB","AB")   returns x = 3
//+----------------------------------------------------------------------------+
int StringFindCount(string str, string str2)
  {
   int c = 0;
   for(int i=0; i<StringLen(str); i++)
      if(StringSubstr(str,i,StringLen(str2)) == str2)
         c++;
   return(c);
  }

//+----------------------------------------------------------------------------+
//| double StrToNumber(string str)
//+----------------------------------------------------------------------------+
// Usage: strips all non-numeric characters out of a string, to return a numeric (double) value
//  valid numeric characters are digits 0,1,2,3,4,5,6,7,8,9, decimal point (.) and minus sign (-)
//+----------------------------------------------------------------------------+
double StrToNumber(string str)
  {
   int    dp   = -1;
   int    sgn  = 1;
   double num  = 0.0;
   for(int i=0; i<StringLen(str); i++)
     {
      string s = StringSubstr(str,i,1);
      if(s == "-")
         sgn = -sgn;
      else
         if(s == ".")
            dp = 0;
         else
            if(s >= "0" && s <= "9")
              {
               if(dp >= 0)
                  dp++;
               if(dp > 0)
                  num = num + StringToInteger(s) / MathPow(10,dp);
               else
                  num = num * 10 + StringToInteger(s);
              }
     }
   return(num*sgn);
  }

//+------------------------------------------------------------------+
