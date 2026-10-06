//+------------------------------------------------------------------+
//|                                                         VWAP.mq5 |
//| Volume Weighted Average Price s resetem po dnech, týdnech        |
//| nebo měsících a volitelnými odchylkovými pásmy (1., 2. a 3. SD).  |
//+------------------------------------------------------------------+
#property version     "1.11"
#property description "VWAP (Volume Weighted Average Price) s pásmy 1., 2. a 3. směrodatné odchylky."
#property description "Reset kumulace denně, týdně nebo měsíčně podle času serveru."
#property description "Bez reálného objemu se počítá z tick volume (aproximace)."

#property indicator_chart_window
#property indicator_buffers 10
#property indicator_plots   7

// Hlavní čára VWAP
#property indicator_label1  "VWAP"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

// Pásmo 1. směrodatné odchylky
#property indicator_label2  "VWAP +1 SD"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrDodgerBlue
#property indicator_style2  STYLE_DOT
#property indicator_width2  1

#property indicator_label3  "VWAP -1 SD"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDodgerBlue
#property indicator_style3  STYLE_DOT
#property indicator_width3  1

// Pásmo 2. směrodatné odchylky
#property indicator_label4  "VWAP +2 SD"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrDodgerBlue
#property indicator_style4  STYLE_DOT
#property indicator_width4  1

#property indicator_label5  "VWAP -2 SD"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrDodgerBlue
#property indicator_style5  STYLE_DOT
#property indicator_width5  1

// Pásmo 3. směrodatné odchylky
#property indicator_label6  "VWAP +3 SD"
#property indicator_type6   DRAW_LINE
#property indicator_color6  clrDodgerBlue
#property indicator_style6  STYLE_DOT
#property indicator_width6  1

#property indicator_label7  "VWAP -3 SD"
#property indicator_type7   DRAW_LINE
#property indicator_color7  clrDodgerBlue
#property indicator_style7  STYLE_DOT
#property indicator_width7  1

// Počet párů odchylkových pásem
#define BANDS_COUNT 3

// Období, po kterém se kumulace VWAP nuluje.
// Komentáře u hodnot se zobrazují jako popisky v dialogu vstupních parametrů.
enum ENUM_VWAP_RESET_PERIOD
  {
   RESET_DAILY   = 0, // Denně
   RESET_WEEKLY  = 1, // Týdně
   RESET_MONTHLY = 2  // Měsíčně
  };

// Vstupní parametry (komentáře slouží jako popisky v dialogu terminálu)
input ENUM_VWAP_RESET_PERIOD InpResetPeriod      = RESET_DAILY; // Období resetu
input ENUM_APPLIED_VOLUME    InpVolumeType       = VOLUME_TICK; // Typ objemu
input bool                   InpShowBands        = true;        // Zobrazit odchylková pásma
input double                 InpBand1Multiplier  = 1.0;         // Násobek 1. pásma
input double                 InpBand2Multiplier  = 2.0;         // Násobek 2. pásma
input double                 InpBand3Multiplier  = 3.0;         // Násobek 3. pásma

// Vykreslované buffery
double VwapBuffer[];
double UpperBand1Buffer[];
double LowerBand1Buffer[];
double UpperBand2Buffer[];
double LowerBand2Buffer[];
double UpperBand3Buffer[];
double LowerBand3Buffer[];

// Pomocné buffery s kumulativními součty pro každou svíčku.
// Díky nim jde přepočet začít od libovolné svíčky uprostřed období:
// součty se převezmou z předchozí svíčky stejného období.
double CumPriceVolumeBuffer[];
double CumVolumeBuffer[];
double CumPrice2VolumeBuffer[];

// Zda se skutečně používá reálný objem (false = tick volume)
bool g_useRealVolume = false;

//+------------------------------------------------------------------+
//| Inicializace indikátoru: kontrola vstupů, napojení bufferů,      |
//| skrytí pásem a nastavení popisků.                                 |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Násobky pásem musí být kladné, jinak by pásma neměla smysl
   if(InpBand1Multiplier <= 0.0 || InpBand2Multiplier <= 0.0 || InpBand3Multiplier <= 0.0)
     {
      Print("VWAP: násobky pásem musí být větší než nula.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   // Datové buffery musí být před výpočetními, pořadí odpovídá plotům
   SetIndexBuffer(0, VwapBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, UpperBand1Buffer, INDICATOR_DATA);
   SetIndexBuffer(2, LowerBand1Buffer, INDICATOR_DATA);
   SetIndexBuffer(3, UpperBand2Buffer, INDICATOR_DATA);
   SetIndexBuffer(4, LowerBand2Buffer, INDICATOR_DATA);
   SetIndexBuffer(5, UpperBand3Buffer, INDICATOR_DATA);
   SetIndexBuffer(6, LowerBand3Buffer, INDICATOR_DATA);
   SetIndexBuffer(7, CumPriceVolumeBuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(8, CumVolumeBuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(9, CumPrice2VolumeBuffer, INDICATOR_CALCULATIONS);

   // Prázdná hodnota pro všechny ploty, aby se nevykreslené body nezobrazovaly
   for(int plot = 0; plot <= 2 * BANDS_COUNT; plot++)
      PlotIndexSetDouble(plot, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   // Popisky pásem s použitými násobky (zobrazí se v okně Data a v tooltipu).
   // Plot 1 + 2*b je horní a plot 2 + 2*b dolní hranice pásma b.
   double multipliers[BANDS_COUNT];
   GetBandMultipliers(multipliers);
   for(int band = 0; band < BANDS_COUNT; band++)
     {
      PlotIndexSetString(1 + 2 * band, PLOT_LABEL, StringFormat("VWAP +%.2f SD", multipliers[band]));
      PlotIndexSetString(2 + 2 * band, PLOT_LABEL, StringFormat("VWAP -%.2f SD", multipliers[band]));
     }

   // Vypnutá pásma se nekreslí vůbec
   if(!InpShowBands)
     {
      for(int plot = 1; plot <= 2 * BANDS_COUNT; plot++)
         PlotIndexSetInteger(plot, PLOT_DRAW_TYPE, DRAW_NONE);
     }

   IndicatorSetString(INDICATOR_SHORTNAME, StringFormat("VWAP (%s)", ResetPeriodName()));
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Hlavní výpočet. Počítá inkrementálně od poslední svíčky,         |
//| při prvním volání nebo po změně historie počítá vše od začátku.  |
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
   if(rates_total <= 0)
      return(0);

   // Určení první přepočítávané svíčky. Poslední svíčka se přepočítává vždy,
   // protože se během vývoje mění její high/low/close i objem.
   int startIndex;
   if(prev_calculated <= 0 || prev_calculated > rates_total)
     {
      startIndex = 0;
      // Při plném přepočtu znovu ověřit dostupnost reálného objemu
      g_useRealVolume = ResolveRealVolume(volume, rates_total);
     }
   else
      startIndex = prev_calculated - 1;

   double multipliers[BANDS_COUNT];
   GetBandMultipliers(multipliers);

   // Začátek období svíčky před první přepočítávanou svíčkou,
   // podle něj se pozná, zda pokračovat v kumulaci nebo ji vynulovat
   datetime previousPeriodStart = (startIndex > 0) ? GetPeriodStart(time[startIndex - 1]) : 0;

   for(int i = startIndex; i < rates_total && !IsStopped(); i++)
     {
      datetime periodStart  = GetPeriodStart(time[i]);
      double   typicalPrice = (high[i] + low[i] + close[i]) / 3.0;
      double   barVolume    = g_useRealVolume ? (double)volume[i] : (double)tick_volume[i];

      // Na začátku období (nebo na první svíčce historie) se kumulace nuluje,
      // jinak se navazuje na součty předchozí svíčky
      double cumPriceVolume  = 0.0;
      double cumVolume       = 0.0;
      double cumPrice2Volume = 0.0;
      if(i > 0 && periodStart == previousPeriodStart)
        {
         cumPriceVolume  = CumPriceVolumeBuffer[i - 1];
         cumVolume       = CumVolumeBuffer[i - 1];
         cumPrice2Volume = CumPrice2VolumeBuffer[i - 1];
        }

      cumPriceVolume  += typicalPrice * barVolume;
      cumVolume       += barVolume;
      cumPrice2Volume += typicalPrice * typicalPrice * barVolume;

      CumPriceVolumeBuffer[i]  = cumPriceVolume;
      CumVolumeBuffer[i]       = cumVolume;
      CumPrice2VolumeBuffer[i] = cumPrice2Volume;

      // VWAP a objemově vážená směrodatná odchylka.
      // Při nulovém kumulativním objemu (zatím jen svíčky bez objemu)
      // nelze dělit, VWAP je pak typická cena a odchylka nulová.
      double vwap   = typicalPrice;
      double stdDev = 0.0;
      if(cumVolume > 0.0)
        {
         vwap = cumPriceVolume / cumVolume;
         // Záporný rozptyl může vzniknout jen zaokrouhlením, ořízne se na nulu
         double variance = cumPrice2Volume / cumVolume - vwap * vwap;
         if(variance < 0.0)
            variance = 0.0;
         stdDev = MathSqrt(variance);
        }

      VwapBuffer[i] = vwap;

      // Pásma se plní jen když jsou zapnutá, jinak zůstávají prázdná
      if(InpShowBands)
        {
         UpperBand1Buffer[i] = vwap + multipliers[0] * stdDev;
         LowerBand1Buffer[i] = vwap - multipliers[0] * stdDev;
         UpperBand2Buffer[i] = vwap + multipliers[1] * stdDev;
         LowerBand2Buffer[i] = vwap - multipliers[1] * stdDev;
         UpperBand3Buffer[i] = vwap + multipliers[2] * stdDev;
         LowerBand3Buffer[i] = vwap - multipliers[2] * stdDev;
        }
      else
        {
         UpperBand1Buffer[i] = EMPTY_VALUE;
         LowerBand1Buffer[i] = EMPTY_VALUE;
         UpperBand2Buffer[i] = EMPTY_VALUE;
         LowerBand2Buffer[i] = EMPTY_VALUE;
         UpperBand3Buffer[i] = EMPTY_VALUE;
         LowerBand3Buffer[i] = EMPTY_VALUE;
        }

      previousPeriodStart = periodStart;
     }

   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Naplní pole násobky pásem ze vstupních parametrů.                |
//| multipliers - výstupní pole o velikosti BANDS_COUNT              |
//+------------------------------------------------------------------+
void GetBandMultipliers(double &multipliers[])
  {
   multipliers[0] = InpBand1Multiplier;
   multipliers[1] = InpBand2Multiplier;
   multipliers[2] = InpBand3Multiplier;
  }

//+------------------------------------------------------------------+
//| Vrací začátek období resetu, do kterého patří čas svíčky.        |
//| barTime - čas otevření svíčky v čase serveru (z pole time[])     |
//+------------------------------------------------------------------+
datetime GetPeriodStart(const datetime barTime)
  {
   MqlDateTime parts;
   TimeToStruct(barTime, parts);

   // Oříznutí na půlnoc dne svíčky
   parts.hour = 0;
   parts.min  = 0;
   parts.sec  = 0;

   switch(InpResetPeriod)
     {
      case RESET_WEEKLY:
        {
         // Týden začíná nedělí (day_of_week = 0), aby případné nedělní
         // svíčky brokera patřily k nadcházejícímu obchodnímu týdnu
         long dayStart = (long)StructToTime(parts);
         return((datetime)(dayStart - (long)parts.day_of_week * 86400));
        }
      case RESET_MONTHLY:
         parts.day = 1;
         return(StructToTime(parts));
      default:
         return(StructToTime(parts));
     }
  }

//+------------------------------------------------------------------+
//| Rozhodne, zda použít reálný objem. Reálný objem se použije jen   |
//| při volbě VOLUME_REAL a pokud v historii existuje nenulová       |
//| hodnota, jinak se vrací k tick volume.                            |
//| volume      - pole reálných objemů z OnCalculate                  |
//| barsCount   - počet svíček v poli                                  |
//+------------------------------------------------------------------+
bool ResolveRealVolume(const long &volume[], const int barsCount)
  {
   if(InpVolumeType != VOLUME_REAL)
      return(false);

   for(int i = 0; i < barsCount; i++)
     {
      if(volume[i] > 0)
         return(true);
     }

   // Broker reálný objem neposkytuje (typicky forex a zlato)
   PrintFormat("VWAP: %s nemá reálný objem, používá se tick volume.", _Symbol);
   return(false);
  }

//+------------------------------------------------------------------+
//| Textový název období resetu pro krátký název indikátoru.         |
//+------------------------------------------------------------------+
string ResetPeriodName()
  {
   switch(InpResetPeriod)
     {
      case RESET_WEEKLY:
         return("Weekly");
      case RESET_MONTHLY:
         return("Monthly");
      default:
         return("Daily");
     }
  }
//+------------------------------------------------------------------+
