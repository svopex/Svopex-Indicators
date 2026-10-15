//+------------------------------------------------------------------+
//|                                                   PulnockaSL.mq5 |
//| Dočasné odebrání StopLossů kolem půlnoční svíčky.                |
//| V čase odebrání (výchozí 23:50 času serveru) odebere SL ze všech |
//| otevřených pozic na forexových párech a v čase vrácení           |
//| (výchozí 01:00) je vrátí zpět. Stav se ukládá do souboru, takže  |
//| expert přežije restart experta i celého terminálu.               |
//| Podporované jsou jen forexové páry z měn USD, EUR, GBP, JPY,     |
//| CHF, CAD, AUD, NZD. Ostatních instrumentů se expert nedotkne.    |
//+------------------------------------------------------------------+
#property copyright "pulnocka"
#property version   "1.12"
#property description "Odebere SL pozic na forexových párech v čase odebrání a vrátí je v čase vrácení (čas serveru)."
#property description "Expert stačí spustit na jednom libovolném grafu, spravuje pozice na všech forexových párech."
#property description "Podporované měny: USD, EUR, GBP, JPY, CHF, CAD, AUD, NZD."

#include <Trade\Trade.mqh>

// Co dělat, když v čase vrácení je cena již za původním SL
// (SL by mezitím byl zasažen a server by jeho nastavení odmítl).
enum ENUM_CROSSED_ACTION
  {
   CROSSED_CLOSE_POSITION = 0, // Zavřít pozici tržně
   CROSSED_LEAVE_NO_SL    = 1  // Ponechat pozici bez SL
  };

input string              InpRemoveTime         = "21:55";                // Čas odebrání SL (čas serveru, HH:MM)
input string              InpRestoreTime        = "23:05";                // Čas vrácení SL (čas serveru, HH:MM)
input bool                InpRestoreOnlyIfEmpty = true;                   // Vrátit SL jen pokud pozice mezitím nedostala nový SL
input ENUM_CROSSED_ACTION InpCrossedAction      = CROSSED_CLOSE_POSITION; // Akce, když je cena při vracení za SL
input int                 InpRetrySeconds       = 10;                     // Interval opakování neúspěšných požadavků (s)
input int                 InpSlippagePoints     = 30;                     // Max. skluz při zavírání pozice (body)
input ulong               InpMagic              = 202610142350;           // Magic number uzavíracího obchodu (jen pro identifikaci v historii)

// Měny, ze kterých se skládají podporované forexové páry
const string FOREX_CURRENCIES[] = {"USD", "EUR", "GBP", "JPY", "CHF", "CAD", "AUD", "NZD"};

// Stavy uložené pozice
#define STATUS_PENDING_REMOVE 0  // SL zaznamenán, odebrání ještě nebylo potvrzeno
#define STATUS_REMOVED        1  // SL odebrán, čeká na vrácení

// Záznam o jedné pozici, které expert odebral (odebírá) SL
struct SlEntry
  {
   ulong             ticket;       // ticket pozice
   string            symbol;       // symbol pozice (jen pro informaci a logy)
   double            sl;           // původní hodnota SL
   int               status;       // STATUS_PENDING_REMOVE / STATUS_REMOVED
   uint              lastRetcode;  // poslední návratový kód (neukládá se, slouží proti zahlcení logu)
   datetime          lastAttempt;  // čas posledního pokusu (lokální čas, neukládá se)
  };

CTrade   g_trade;
SlEntry  g_entries[];
datetime g_lastCycle      = 0;   // začátek posledního okna, ve kterém již proběhlo odebrání
int      g_removeMinutes  = 0;   // čas odebrání v minutách od půlnoci
int      g_restoreMinutes = 0;   // čas vrácení v minutách od půlnoci
string   g_stateFile      = "";  // soubor se stavem v MQL5\Files
bool     g_tradingAllowed = true; // poslední známý stav povolení Algo Tradingu (pro logování změn)

//+------------------------------------------------------------------+
//| Převede text "HH:MM" na počet minut od půlnoci.                  |
//| text    - vstupní čas                                            |
//| minutes - výstup, minuty od půlnoci                              |
//| Vrací false při neplatném formátu.                               |
//+------------------------------------------------------------------+
bool ParseTimeOfDay(const string text, int &minutes)
  {
   string parts[];
   if(StringSplit(text, ':', parts) != 2)
      return false;

   StringTrimLeft(parts[0]);
   StringTrimRight(parts[0]);
   StringTrimLeft(parts[1]);
   StringTrimRight(parts[1]);

   // Obě části musí být čistě číselné, StringToInteger by jinak tiše vrátil 0
   for(int p = 0; p < 2; p++)
     {
      if(StringLen(parts[p]) == 0 || StringLen(parts[p]) > 2)
         return false;
      for(int c = 0; c < StringLen(parts[p]); c++)
        {
         ushort ch = StringGetCharacter(parts[p], c);
         if(ch < '0' || ch > '9')
            return false;
        }
     }

   int hours = (int)StringToInteger(parts[0]);
   int mins  = (int)StringToInteger(parts[1]);
   if(hours > 23 || mins > 59)
      return false;

   minutes = hours * 60 + mins;
   return true;
  }

//+------------------------------------------------------------------+
//| Zjistí, zda je měna v seznamu podporovaných forexových měn.      |
//| currency - kód měny (např. "EUR")                                |
//+------------------------------------------------------------------+
bool IsSupportedCurrency(const string currency)
  {
   for(int i = 0; i < ArraySize(FOREX_CURRENCIES); i++)
      if(FOREX_CURRENCIES[i] == currency)
         return true;
   return false;
  }

//+------------------------------------------------------------------+
//| Zjistí, zda je symbol podporovaný forexový pár.                  |
//| Rozhoduje se podle bázové a kotované měny symbolu, ne podle      |
//| názvu, takže fungují i názvy s příponou brokera (EURUSD.m).      |
//| Pár musí být složen ze dvou různých měn ze seznamu - tím se      |
//| vyloučí např. kov XAUUSD (XAU není v seznamu) nebo index US30    |
//| (bázová i kotovaná měna je USD).                                 |
//| symbol - název symbolu                                           |
//+------------------------------------------------------------------+
bool IsForexPair(const string symbol)
  {
   string baseCurrency   = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
   string profitCurrency = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);

   if(baseCurrency == profitCurrency)
      return false;
   return (IsSupportedCurrency(baseCurrency) && IsSupportedCurrency(profitCurrency));
  }

//+------------------------------------------------------------------+
//| Zjistí, zda je daný čas serveru uvnitř okna bez SL.              |
//| now        - aktuální čas serveru                                |
//| cycleStart - výstup, okamžik začátku aktuálního okna             |
//|              (jednoznačně identifikuje "noc", slouží k tomu,     |
//|              aby se odebrání provedlo jen jednou)                |
//+------------------------------------------------------------------+
bool IsInWindow(const datetime now, datetime &cycleStart)
  {
   long     seconds    = (long)now;
   int      dayMinutes = (int)((seconds % 86400) / 60);
   datetime dayStart   = (datetime)(seconds - seconds % 86400);

   // Okno v rámci jednoho dne (např. 22:00 - 23:00)
   if(g_removeMinutes < g_restoreMinutes)
     {
      cycleStart = dayStart + g_removeMinutes * 60;
      return (dayMinutes >= g_removeMinutes && dayMinutes < g_restoreMinutes);
     }

   // Okno přes půlnoc (např. 23:50 - 01:00): část před půlnocí patří k dnešku
   if(dayMinutes >= g_removeMinutes)
     {
      cycleStart = dayStart + g_removeMinutes * 60;
      return true;
     }

   // Část po půlnoci patří k oknu, které začalo předchozí den
   if(dayMinutes < g_restoreMinutes)
     {
      cycleStart = dayStart - 86400 + g_removeMinutes * 60;
      return true;
     }

   cycleStart = 0;
   return false;
  }

//+------------------------------------------------------------------+
//| Vyhledá záznam podle ticketu pozice, vrací index nebo -1.        |
//+------------------------------------------------------------------+
int FindEntry(const ulong ticket)
  {
   for(int i = 0; i < ArraySize(g_entries); i++)
      if(g_entries[i].ticket == ticket)
         return i;
   return -1;
  }

//+------------------------------------------------------------------+
//| Odstraní záznam na daném indexu (ruční posun kvůli stringu       |
//| ve struktuře).                                                   |
//+------------------------------------------------------------------+
void DeleteEntry(const int index)
  {
   int total = ArraySize(g_entries);
   for(int i = index; i < total - 1; i++)
      g_entries[i] = g_entries[i + 1];
   ArrayResize(g_entries, total - 1);
  }

//+------------------------------------------------------------------+
//| Uloží stav do souboru. Zapisuje se do dočasného souboru, který   |
//| se pak přesune přes původní, aby při pádu nevznikl poškozený     |
//| soubor.                                                          |
//| Formát řádků:                                                    |
//|   CYCLE;<začátek okna jako unix čas>                             |
//|   POS;<ticket>;<symbol>;<sl>;<status>                            |
//+------------------------------------------------------------------+
bool SaveState()
  {
   string tmpFile = g_stateFile + ".tmp";
   int handle = FileOpen(tmpFile, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
     {
      PrintFormat("CHYBA: nelze otevřít soubor stavu %s pro zápis, chyba %d", tmpFile, GetLastError());
      return false;
     }

   FileWriteString(handle, StringFormat("CYCLE;%I64d\r\n", (long)g_lastCycle));
   for(int i = 0; i < ArraySize(g_entries); i++)
     {
      FileWriteString(handle, StringFormat("POS;%I64u;%s;%s;%d\r\n",
                                           g_entries[i].ticket,
                                           g_entries[i].symbol,
                                           DoubleToString(g_entries[i].sl, 10),
                                           g_entries[i].status));
     }
   FileClose(handle);

   if(!FileMove(tmpFile, 0, g_stateFile, FILE_REWRITE))
     {
      PrintFormat("CHYBA: nelze přepsat soubor stavu %s, chyba %d", g_stateFile, GetLastError());
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Načte stav ze souboru (pokud existuje).                          |
//+------------------------------------------------------------------+
bool LoadState()
  {
   ArrayResize(g_entries, 0);
   g_lastCycle = 0;

   // Neexistující soubor = první spuštění, není co obnovovat
   if(!FileIsExist(g_stateFile))
      return true;

   int handle = FileOpen(g_stateFile, FILE_READ | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
     {
      PrintFormat("CHYBA: nelze otevřít soubor stavu %s pro čtení, chyba %d", g_stateFile, GetLastError());
      return false;
     }

   while(!FileIsEnding(handle))
     {
      string line = FileReadString(handle);
      string fields[];
      int count = StringSplit(line, ';', fields);
      if(count <= 0)
         continue;

      // Řádek s identifikací posledního zpracovaného okna
      if(fields[0] == "CYCLE" && count >= 2)
        {
         g_lastCycle = (datetime)StringToInteger(fields[1]);
         continue;
        }

      // Řádek s uloženou pozicí a jejím původním SL
      if(fields[0] == "POS" && count >= 5)
        {
         int n = ArraySize(g_entries);
         ArrayResize(g_entries, n + 1);
         g_entries[n].ticket      = (ulong)StringToInteger(fields[1]);
         g_entries[n].symbol      = fields[2];
         g_entries[n].sl          = StringToDouble(fields[3]);
         g_entries[n].status      = (int)StringToInteger(fields[4]);
         g_entries[n].lastRetcode = 0;
         g_entries[n].lastAttempt = 0;
        }
     }
   FileClose(handle);
   return true;
  }

//+------------------------------------------------------------------+
//| Vrací true, pokud je u záznamu čas na další pokus o požadavek,   |
//| a zároveň si pokus poznamená.                                    |
//+------------------------------------------------------------------+
bool RetryDue(const int index)
  {
   datetime nowLocal = TimeLocal();
   if(g_entries[index].lastAttempt != 0 && nowLocal - g_entries[index].lastAttempt < InpRetrySeconds)
      return false;
   g_entries[index].lastAttempt = nowLocal;
   return true;
  }

//+------------------------------------------------------------------+
//| Je poslední obchodní požadavek úspěšný?                          |
//| NO_CHANGES bereme jako úspěch (SL už má požadovanou hodnotu).    |
//+------------------------------------------------------------------+
bool LastRequestSucceeded()
  {
   uint retcode = g_trade.ResultRetcode();
   return (retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_NO_CHANGES);
  }

//+------------------------------------------------------------------+
//| Zaloguje neúspěch požadavku, ale jen při změně návratového kódu, |
//| aby se log nezahltil např. o víkendu při zavřeném trhu.          |
//+------------------------------------------------------------------+
void LogFailure(const int index, const string action)
  {
   uint retcode = g_trade.ResultRetcode();
   if(retcode == g_entries[index].lastRetcode)
      return;
   g_entries[index].lastRetcode = retcode;
   PrintFormat("%s #%I64u %s se nezdařilo: %u %s (opakuji každých %d s)",
               action, g_entries[index].ticket, g_entries[index].symbol,
               retcode, g_trade.ResultRetcodeDescription(), InpRetrySeconds);
  }

//+------------------------------------------------------------------+
//| Začátek nového okna: zaznamená SL otevřených pozic na forexových |
//| párech. Pozice na ostatních instrumentech se přeskakují.         |
//| Samotné odebrání provede ProcessPendingRemovals().               |
//| cycleStart - identifikace okna, uloží se jako zpracované         |
//+------------------------------------------------------------------+
void StartRemoval(const datetime cycleStart)
  {
   int added   = 0;
   int skipped = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      // Pozice bez SL nebo pozice, kterou už evidujeme (čeká na vrácení), přeskočíme
      double sl = PositionGetDouble(POSITION_SL);
      if(sl == 0.0 || FindEntry(ticket) >= 0)
         continue;

      // Mazání SL je podporováno jen pro forexové páry, ostatní instrumenty nechává beze změny
      string symbol = PositionGetString(POSITION_SYMBOL);
      if(!IsForexPair(symbol))
        {
         PrintFormat("Pozice #%I64u %s není forexový pár, SL se neodebírá.", ticket, symbol);
         skipped++;
         continue;
        }

      int n = ArraySize(g_entries);
      ArrayResize(g_entries, n + 1);
      g_entries[n].ticket      = ticket;
      g_entries[n].symbol      = symbol;
      g_entries[n].sl          = sl;
      g_entries[n].status      = STATUS_PENDING_REMOVE;
      g_entries[n].lastRetcode = 0;
      g_entries[n].lastAttempt = 0;
      added++;
     }

   g_lastCycle = cycleStart;

   // Pokud se stav nepodaří uložit, SL raději neodebíráme - po restartu
   // bychom je neuměli vrátit
   if(!SaveState())
     {
      for(int i = ArraySize(g_entries) - 1; i >= 0; i--)
         if(g_entries[i].status == STATUS_PENDING_REMOVE)
            DeleteEntry(i);
      Print("CHYBA: stav nelze uložit, SL se v tomto okně neodebírají.");
      return;
     }

   PrintFormat("Začátek okna bez SL (%s): zaznamenáno %d forexových pozic se SL, přeskočeno %d ostatních.",
               TimeToString(cycleStart, TIME_DATE | TIME_MINUTES), added, skipped);
  }

//+------------------------------------------------------------------+
//| Odebere SL u všech zaznamenaných pozic, kde to ještě neproběhlo. |
//+------------------------------------------------------------------+
void ProcessPendingRemovals()
  {
   bool changed = false;
   for(int i = ArraySize(g_entries) - 1; i >= 0; i--)
     {
      if(g_entries[i].status != STATUS_PENDING_REMOVE)
         continue;

      // Pozice mezitím zavřena - není co řešit
      if(!PositionSelectByTicket(g_entries[i].ticket))
        {
         PrintFormat("Pozice #%I64u %s již neexistuje, SL se neodebírá.", g_entries[i].ticket, g_entries[i].symbol);
         DeleteEntry(i);
         changed = true;
         continue;
        }

      // SL už je pryč (např. odebrán těsně před pádem terminálu, ale stav se neuložil)
      double currentSl = PositionGetDouble(POSITION_SL);
      if(currentSl == 0.0)
        {
         g_entries[i].status = STATUS_REMOVED;
         changed = true;
         continue;
        }

      if(!RetryDue(i))
         continue;

      // Před odebráním uložíme aktuální SL (mohl se mezi pokusy změnit),
      // aby se po případném pádu vracela správná hodnota
      if(g_entries[i].sl != currentSl)
        {
         g_entries[i].sl = currentSl;
         if(!SaveState())
            continue;
        }

      double tp = PositionGetDouble(POSITION_TP);
      if(g_trade.PositionModify(g_entries[i].ticket, 0.0, tp) && LastRequestSucceeded())
        {
         g_entries[i].status = STATUS_REMOVED;
         changed = true;
         PrintFormat("SL odebrán: #%I64u %s (původní SL %s)", g_entries[i].ticket, g_entries[i].symbol,
                     DoubleToString(g_entries[i].sl, (int)SymbolInfoInteger(g_entries[i].symbol, SYMBOL_DIGITS)));
        }
      else
         LogFailure(i, "Odebrání SL");
     }

   if(changed)
      SaveState();
  }

//+------------------------------------------------------------------+
//| Konec okna: pozice, u kterých se SL nepodařilo odebrat, vyřadíme |
//| (SL na nich stále je). Pozice s už odebraným SL půjdou k vrácení.|
//+------------------------------------------------------------------+
void FinalizePendingRemovals()
  {
   bool changed = false;
   for(int i = ArraySize(g_entries) - 1; i >= 0; i--)
     {
      if(g_entries[i].status != STATUS_PENDING_REMOVE)
         continue;

      if(PositionSelectByTicket(g_entries[i].ticket) && PositionGetDouble(POSITION_SL) == 0.0)
         g_entries[i].status = STATUS_REMOVED;
      else
        {
         PrintFormat("Okno skončilo, SL u #%I64u %s nebyl odebrán - ponechávám beze změny.",
                     g_entries[i].ticket, g_entries[i].symbol);
         DeleteEntry(i);
        }
      changed = true;
     }

   if(changed)
      SaveState();
  }

//+------------------------------------------------------------------+
//| Vrátí původní SL na pozice, kterým byl odebrán.                  |
//| Neúspěšné pokusy (zavřený trh, příliš blízko ceně...) se         |
//| opakují, dokud se SL nevrátí nebo pozice nezanikne.              |
//+------------------------------------------------------------------+
void ProcessRestores()
  {
   bool changed = false;
   for(int i = ArraySize(g_entries) - 1; i >= 0; i--)
     {
      if(g_entries[i].status != STATUS_REMOVED)
         continue;

      // Pozice byla mezitím zavřena
      if(!PositionSelectByTicket(g_entries[i].ticket))
        {
         PrintFormat("Pozice #%I64u %s již neexistuje, SL se nevrací.", g_entries[i].ticket, g_entries[i].symbol);
         DeleteEntry(i);
         changed = true;
         continue;
        }

      // Pozice mezitím dostala nový SL (ručně nebo jiným expertem) - nezasahujeme
      double currentSl = PositionGetDouble(POSITION_SL);
      if(currentSl != 0.0 && InpRestoreOnlyIfEmpty)
        {
         PrintFormat("Pozice #%I64u %s má mezitím nový SL %s, původní SL se nevrací.",
                     g_entries[i].ticket, g_entries[i].symbol,
                     DoubleToString(currentSl, (int)SymbolInfoInteger(g_entries[i].symbol, SYMBOL_DIGITS)));
         DeleteEntry(i);
         changed = true;
         continue;
        }

      if(!RetryDue(i))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      double sl     = NormalizeDouble(g_entries[i].sl, digits);
      double tp     = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      MqlTick tick;
      if(!SymbolInfoTick(symbol, tick))
         continue;

      // Cena je už za původním SL (long: bid <= SL, short: ask >= SL) - server by SL odmítl
      bool crossed = (type == POSITION_TYPE_BUY) ? (tick.bid <= sl) : (tick.ask >= sl);
      if(crossed)
        {
         if(InpCrossedAction == CROSSED_LEAVE_NO_SL)
           {
            PrintFormat("Cena je za původním SL %s u #%I64u %s, pozice zůstává bez SL.",
                        DoubleToString(sl, digits), g_entries[i].ticket, symbol);
            DeleteEntry(i);
            changed = true;
           }
         else if(g_trade.PositionClose(g_entries[i].ticket) && LastRequestSucceeded())
           {
            PrintFormat("Cena je za původním SL %s, pozice #%I64u %s zavřena.",
                        DoubleToString(sl, digits), g_entries[i].ticket, symbol);
            DeleteEntry(i);
            changed = true;
           }
         else
            LogFailure(i, "Zavření pozice");
         continue;
        }

      // Běžný případ - vrácení původního SL se zachováním TP
      if(g_trade.PositionModify(g_entries[i].ticket, sl, tp) && LastRequestSucceeded())
        {
         PrintFormat("SL vrácen: #%I64u %s SL %s", g_entries[i].ticket, symbol, DoubleToString(sl, digits));
         DeleteEntry(i);
         changed = true;
        }
      else
         LogFailure(i, "Vrácení SL");
     }

   if(changed)
      SaveState();
  }

//+------------------------------------------------------------------+
//| Informační výpis stavu do levého horního rohu grafu.             |
//+------------------------------------------------------------------+
void UpdateComment(const datetime now, const bool inWindow)
  {
   int pendingRemove = 0;
   int removed       = 0;
   for(int i = 0; i < ArraySize(g_entries); i++)
     {
      if(g_entries[i].status == STATUS_PENDING_REMOVE)
         pendingRemove++;
      else
         removed++;
     }

   Comment(StringFormat("PulnockaSL  |  čas serveru %s\n"
                        "Odebrání SL: %s   Vrácení SL: %s\n"
                        "Stav: %s\n"
                        "Odebrané SL čekající na vrácení: %d   Čeká na odebrání: %d",
                        TimeToString(now, TIME_DATE | TIME_SECONDS),
                        InpRemoveTime, InpRestoreTime,
                        inWindow ? "okno bez SL" : "mimo okno",
                        removed, pendingRemove));
  }

//+------------------------------------------------------------------+
//| Zjistí, zda smí expert obchodovat. Vrací false, pokud je vypnuté |
//| tlačítko Algo Trading v terminálu nebo volba "Povolit Algo       |
//| Trading" ve vlastnostech experta.                                |
//| reason - výstup, lidsky čitelný důvod zákazu                     |
//+------------------------------------------------------------------+
bool IsAlgoTradingAllowed(string &reason)
  {
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     {
      reason = "Algo Trading je v terminálu vypnutý";
      return false;
     }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      reason = "Algo Trading není povolen ve vlastnostech experta";
      return false;
     }
   reason = "";
   return true;
  }

//+------------------------------------------------------------------+
//| Inicializace: kontrola vstupů, načtení stavu, spuštění časovače. |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(!ParseTimeOfDay(InpRemoveTime, g_removeMinutes))
     {
      Print("CHYBA: neplatný čas odebrání SL, očekávám formát HH:MM, např. 23:50");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(!ParseTimeOfDay(InpRestoreTime, g_restoreMinutes))
     {
      Print("CHYBA: neplatný čas vrácení SL, očekávám formát HH:MM, např. 01:00");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(g_removeMinutes == g_restoreMinutes)
     {
      Print("CHYBA: čas odebrání a vrácení SL nesmí být stejný.");
      return INIT_PARAMETERS_INCORRECT;
     }

   // Stav je vázaný na účet, aby se nepletly pozice různých účtů
   g_stateFile = StringFormat("PulnockaSL_%I64d.csv", AccountInfoInteger(ACCOUNT_LOGIN));
   if(!LoadState())
      return INIT_FAILED;

   // Vlastní logování s potlačením opakovaných chyb, CTrade by log zahlcoval
   g_trade.LogLevel(LOG_LEVEL_NO);
   g_trade.SetDeviationInPoints(InpSlippagePoints);

   // Magic se projeví jen u obchodu, kterým expert zavírá pozici (cena za SL).
   // Úprava SL (TRADE_ACTION_SLTP) magic nepoužívá, pozice si ponechá magic
   // toho, kdo ji otevřel. Podle magicu se pozice nefiltrují.
   g_trade.SetExpertMagicNumber(InpMagic);

   PrintFormat("PulnockaSL spuštěn: odebrání %s, vrácení %s (čas serveru), načteno %d uložených SL.",
               InpRemoveTime, InpRestoreTime, ArraySize(g_entries));

   EventSetTimer(1);
   OnTimer();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Ukončení: stav zůstává v souboru pro příští spuštění.            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   Comment("");
  }

//+------------------------------------------------------------------+
//| Hlavní smyčka - běží každou sekundu nezávisle na ticích grafu.   |
//+------------------------------------------------------------------+
void OnTimer()
  {
   // Při vypnutém Algo Tradingu nic neprovádíme a na grafu jen ukážeme,
   // že expert neběží. Uložený stav zůstává a po zapnutí se pokračuje
   // (odebrání proběhne, pokud je stále okno, vrácení proběhne vždy).
   string reason;
   bool allowed = IsAlgoTradingAllowed(reason);
   if(allowed != g_tradingAllowed)
     {
      g_tradingAllowed = allowed;
      if(allowed)
         Print("Algo Trading zapnut, PulnockaSL pokračuje.");
      else
         PrintFormat("PulnockaSL pozastaven: %s.", reason);
     }
   if(!allowed)
     {
      Comment(StringFormat("PulnockaSL NEBĚŽÍ - %s", reason));
      return;
     }

   datetime now = TimeTradeServer();
   datetime cycleStart = 0;
   bool inWindow = IsInWindow(now, cycleStart);

   if(inWindow)
     {
      // Odebrání proběhne pro každé okno jen jednou (i přes restart experta)
      if(cycleStart != g_lastCycle)
         StartRemoval(cycleStart);
      ProcessPendingRemovals();
     }
   else
     {
      FinalizePendingRemovals();
      ProcessRestores();
     }

   UpdateComment(now, inWindow);
  }
//+------------------------------------------------------------------+
