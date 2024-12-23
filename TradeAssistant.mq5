﻿//+------------------------------------------------------------------+
//|                                               TradeAssistant.mq5 |
//+------------------------------------------------------------------+

#property copyright "Riccardo Moreo"
#property strict
#property description "Il TradeAssistant è uno strumento avanzato per il trading discrezionale progettato per Velocizzare le decisioni operative. Integra il monitoraggio in tempo reale delle notizie economiche, l'analisi multi-timeframe dei trend di mercato e il calcolo automatico della dimensione dei lotti in base al rischio. Consente una gestione completa di ordini e posizioni con funzioni come stop loss, take profit e break even, il tutto attraverso un'interfaccia intuitiva. Sviluppato da Riccardo Moreo."
#property version   "2.00"
#property icon   "TradeAssistant.ico"
#property tester_indicator "VWAP"
#include<Trade/Trade.mqh>
CTrade trade;
CPositionInfo position;
CObject object;
CHistoryOrderInfo info;
CDealInfo dealinfo;

//+------------------------------------------------------------------+
//| News Library                                                     |
//+------------------------------------------------------------------+

#define   GMT_OFFSET_WINTER_DEFAULT 2
#define   GMT_OFFSET_SUMMER_DEFAULT 3

enum ENUM_COUNTRY_ID
  {
   World=0,
   EU=999,
   USA=840,
   Canada=124,
   Australia=36,
   NewZealand=554,
   Japan=392,
   China=156,
   UK=826,
   Switzerland=756,
   Germany=276,
   France=250,
   Italy=380,
   Spain=724,
   Brazil=76,
   SouthKorea=410
  };

enum Importanza
  {
   Bassa = 0,
   Media = 1,
   Alta = 2,
  };

//News Class//                                                       

class CNews
  {
   private:
   struct EventStruct
     {
      ulong          value_id;
      ulong          event_id;
      datetime       time;
      datetime       period;
      int            revision;
      long           actual_value;
      long           prev_value;
      long           revised_prev_value;
      long           forecast_value;
      ENUM_CALENDAR_EVENT_IMPACT impact_type;
      ENUM_CALENDAR_EVENT_TYPE event_type;
      ENUM_CALENDAR_EVENT_SECTOR sector;
      ENUM_CALENDAR_EVENT_FREQUENCY frequency;
      ENUM_CALENDAR_EVENT_TIMEMODE timemode;
      ENUM_CALENDAR_EVENT_IMPORTANCE importance;
      ENUM_CALENDAR_EVENT_MULTIPLIER multiplier;
      ENUM_CALENDAR_EVENT_UNIT unit;
      uint           digits;
      ulong          country_id; 
     };
   string            future_eventname[];
   MqlDateTime       tm;
   datetime          servertime;
   
   public:
   datetime          GMT(ushort server_offset_winter,ushort server_offset_summer);
   EventStruct       event[];
   string            eventname[];
   int               SaveHistory(bool printlog_info=false);
   int               LoadHistory(bool printlog_info=false);
   int               update(int interval_seconds,bool printlog_info=false);
   int               next(int pointer_start,string currency,bool show_on_chart,long chart_id);
   string            CountryIdToCurrency(ENUM_COUNTRY_ID c);
   int               CurrencyToCountryId(string currency);
   int               GetNextNewsEvent(int pointer_start, string currency, Importanza importance, ENUM_COUNTRY_ID countri);
   datetime          last_update;
   ushort            GMT_offset_winter;
   ushort            GMT_offset_summer;
   
   CNews(void)
     {
      ArrayResize(event,100000,0);
      ZeroMemory(event);
      ArrayResize(eventname,100000,0);
      ZeroMemory(eventname);
      ArrayResize(future_eventname,100000,0);
      ZeroMemory(future_eventname);
      GMT_offset_winter=GMT_OFFSET_WINTER_DEFAULT;
      GMT_offset_summer=GMT_OFFSET_SUMMER_DEFAULT;
      last_update=0;
      SaveHistory(true);
      LoadHistory(true);
     }
   ~CNews(void) {};
  };

//Dichiarazione Struct//

CNews news;

//Update News Events//

int CNews::update(int interval_seconds=60,bool printlog_info=false)
  {
   static datetime last_time=0;
   static int total_events=0;
   if(TimeCurrent()<last_time+interval_seconds)
     {
      return total_events;
     }
   SaveHistory(printlog_info);
   total_events=LoadHistory(printlog_info);
   last_time=TimeCurrent();
   return total_events;
  }

//Grab News History & Save It//

int CNews::SaveHistory(bool printlog_info=false)
  {
   datetime tm_gmt=GMT(GMT_offset_winter,GMT_offset_summer);
   int filehandle;

   if(!FileIsExist("news\\newshistory.bin",FILE_COMMON))
     {
      filehandle=FileOpen("news\\newshistory.bin",FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_COMMON|FILE_BIN);
      if(filehandle!=INVALID_HANDLE)
        {
         if(printlog_info)
           {
            Print(__FUNCTION__,": creating new file common/files/news/newshistory.bin");
           }
        }
      else
        {
         if(printlog_info)
           {
            Print(__FUNCTION__,"invalid filehandle, can't create news history file");
           }
         return 0;
        }
      FileSeek(filehandle,0,SEEK_SET);
      FileWriteLong(filehandle,(long)last_update);
     }
   else
     {
      filehandle=FileOpen("news\\newshistory.bin",FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_COMMON|FILE_BIN);
      FileSeek(filehandle,0,SEEK_SET);
      last_update=(datetime)FileReadLong(filehandle);
      if(filehandle!=INVALID_HANDLE)
        {
         if(printlog_info)
           {
            Print(__FUNCTION__,": previous newshistory file found in common/files; history update starts from ",last_update," GMT");
           }
        }
      else
        {
         if(printlog_info)
           {
            Print(__FUNCTION__,": invalid filehandle; can't open previous news history file");
           };
         return 0;
        }
      bool from_beginning=FileSeek(filehandle,0,SEEK_END);
      if(!from_beginning)
        {
         Print(__FUNCTION__": unable to go to the file's beginning");
        }
     }
   if(last_update>tm_gmt)
     {
      if(printlog_info)
        {
         Print(__FUNCTION__,": time of last news update is in the future relative to timestamp of request; the existing data won't be overwritten/replaced,",
               "\nexecution of function therefore prohibited; only future events relative to this timestamp will be loaded");
        }
      return 0; 
     }

   MqlCalendarValue eventvaluebuffer[];
   ZeroMemory(eventvaluebuffer);
   MqlCalendarEvent eventbuffer;
   ZeroMemory(eventbuffer);
   CalendarValueHistory(eventvaluebuffer,last_update,tm_gmt);

   int number_of_events=ArraySize(eventvaluebuffer);
   int saved_elements=0;
   if(number_of_events>=ArraySize(event))
     {
      ArrayResize(event,number_of_events,0);
     }
   for(int i=0;i<number_of_events;i++)
     {
      event[i].value_id          =  eventvaluebuffer[i].id;
      event[i].event_id          =  eventvaluebuffer[i].event_id;
      event[i].time              =  eventvaluebuffer[i].time;
      event[i].period            =  eventvaluebuffer[i].period;
      event[i].revision          =  eventvaluebuffer[i].revision;
      event[i].actual_value      =  eventvaluebuffer[i].actual_value;
      event[i].prev_value        =  eventvaluebuffer[i].prev_value;
      event[i].revised_prev_value=  eventvaluebuffer[i].revised_prev_value;
      event[i].forecast_value    =  eventvaluebuffer[i].forecast_value;
      event[i].impact_type       =  eventvaluebuffer[i].impact_type;

      CalendarEventById(eventvaluebuffer[i].event_id,eventbuffer);

      event[i].event_type        =  eventbuffer.type;
      event[i].sector            =  eventbuffer.sector;
      event[i].frequency         =  eventbuffer.frequency;
      event[i].timemode          =  eventbuffer.time_mode;
      event[i].multiplier        =  eventbuffer.multiplier;
      event[i].unit              =  eventbuffer.unit;
      event[i].digits            =  eventbuffer.digits;
      event[i].country_id        =  eventbuffer.country_id;
      
      if(event[i].event_type!=CALENDAR_TYPE_HOLIDAY &&           
         event[i].timemode==CALENDAR_TIMEMODE_DATETIME)        
        {
         FileWriteStruct(filehandle,event[i]);
         int length=StringLen(eventbuffer.name);
         FileWriteInteger(filehandle,length,INT_VALUE);
         FileWriteString(filehandle,eventbuffer.name,length);
         saved_elements++;
        }
     }
   FileSeek(filehandle,0,SEEK_SET);
   FileWriteLong(filehandle,(long)tm_gmt);
   FileClose(filehandle);
   if(printlog_info)
     {
      Print(__FUNCTION__,": ",number_of_events," total events found, ",saved_elements,
            " events saved (holiday events and events without exact published time are ignored)");
     }
   return saved_elements;
  }

//Load History//

int CNews::LoadHistory(bool printlog_info=false)
  {
   datetime dt_gmt = GMT(GMT_offset_winter, GMT_offset_summer);
   int filehandle;
   int number_of_events = 0;

   if(FileIsExist("news\\newshistory.bin", FILE_COMMON))
     {
      filehandle = FileOpen("news\\newshistory.bin", FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_COMMON | FILE_BIN);

      if(filehandle != INVALID_HANDLE)
        {
         FileSeek(filehandle, 0, SEEK_SET);
         last_update = (datetime)FileReadLong(filehandle);
         if(printlog_info)
            Print(__FUNCTION__, ": previous news history file found; last update was on ", last_update, " (GMT)");
        }
      else
        {
         if(printlog_info)
            Print(__FUNCTION__, ": can't open previous news history file; invalid file handle");
         return 0;
        }

      ZeroMemory(event);  

      int i = 0;
      while(!FileIsEnding(filehandle) && !IsStopped())
        {
         if(ArraySize(event) <= i)
            ArrayResize(event, i + 1000);  

         FileReadStruct(filehandle, event[i]);

         int length = FileReadInteger(filehandle, INT_VALUE);
         if(ArraySize(eventname) <= i)
            ArrayResize(eventname, i + 1000); 

         eventname[i] = FileReadString(filehandle, length);
         i++;
        }

      number_of_events = i;
      FileClose(filehandle);

      if(printlog_info)
         Print(__FUNCTION__, ": loading of event history completed (", number_of_events, " events), continuing with events after ", last_update, " (GMT) ...");
     }
   else
     {
      if(printlog_info)
         Print(__FUNCTION__, ": no newshistory file found, only upcoming events will be loaded");
      last_update = dt_gmt;
     }

   MqlCalendarValue eventvaluebuffer[];
   ZeroMemory(eventvaluebuffer);
   MqlCalendarEvent eventbuffer;
   ZeroMemory(eventbuffer);

   CalendarValueHistory(eventvaluebuffer, last_update, 0);
   int future_events = ArraySize(eventvaluebuffer);

   if(printlog_info)
      Print(__FUNCTION__, ": ", future_events, " new events found (holiday events and events without published exact time will be ignored)");

   ArrayResize(event, number_of_events + future_events);
   ArrayResize(eventname, number_of_events + future_events);

   for(int i = 0; i < future_events; i++)
     {
      event[number_of_events].value_id          = eventvaluebuffer[i].id;
      event[number_of_events].event_id          = eventvaluebuffer[i].event_id;
      event[number_of_events].time              = eventvaluebuffer[i].time;
      event[number_of_events].period            = eventvaluebuffer[i].period;
      event[number_of_events].revision          = eventvaluebuffer[i].revision;
      event[number_of_events].actual_value      = eventvaluebuffer[i].actual_value;
      event[number_of_events].prev_value        = eventvaluebuffer[i].prev_value;
      event[number_of_events].revised_prev_value= eventvaluebuffer[i].revised_prev_value;
      event[number_of_events].forecast_value    = eventvaluebuffer[i].forecast_value;
      event[number_of_events].impact_type       = eventvaluebuffer[i].impact_type;

      CalendarEventById(eventvaluebuffer[i].event_id, eventbuffer);

      event[number_of_events].event_type        = eventbuffer.type;
      event[number_of_events].sector            = eventbuffer.sector;
      event[number_of_events].frequency         = eventbuffer.frequency;
      event[number_of_events].timemode          = eventbuffer.time_mode;
      event[number_of_events].importance        = eventbuffer.importance;
      event[number_of_events].multiplier        = eventbuffer.multiplier;
      event[number_of_events].unit              = eventbuffer.unit;
      event[number_of_events].digits            = eventbuffer.digits;
      event[number_of_events].country_id        = eventbuffer.country_id;

      eventname[number_of_events] = eventbuffer.name;

      if(event[number_of_events].event_type != CALENDAR_TYPE_HOLIDAY &&
         event[number_of_events].timemode == CALENDAR_TIMEMODE_DATETIME)
        {
         number_of_events++;  
        }
     }

   if(printlog_info)
      Print(__FUNCTION__, ": loading of news history completed, ", number_of_events, " events in memory");

   last_update = dt_gmt; 
   return number_of_events;
  }

//Pointer Next Event//

int timezone_off = 180*PeriodSeconds(PERIOD_M1);

int CNews::next(int pointer_start,string currency,bool show_on_chart=true,long chart_id=0)
  {
   datetime dt_gmt=GMT(GMT_offset_winter,GMT_offset_summer);
   for(int p=pointer_start;p<ArraySize(event);p++)
     {
      if
      (
         event[p].country_id==CurrencyToCountryId(currency) &&
         event[p].time>=dt_gmt
      )
        {
         if(pointer_start!=p && show_on_chart && MQLInfoInteger(MQL_VISUAL_MODE))
           {
            ObjectCreate(chart_id,"event "+IntegerToString(p),OBJ_VLINE,0,event[p].time+TimeTradeServer()-dt_gmt-timezone_off,0);
            ObjectSetInteger(chart_id,"event "+IntegerToString(p),OBJPROP_WIDTH,3);
            ObjectCreate(chart_id,"label "+IntegerToString(p),OBJ_TEXT,0,event[p].time+TimeTradeServer()-dt_gmt-timezone_off,SymbolInfoDouble(Symbol(),SYMBOL_BID));
            ObjectSetInteger(chart_id,"label "+IntegerToString(p),OBJPROP_YOFFSET,800);
            ObjectSetInteger(chart_id,"label "+IntegerToString(p),OBJPROP_BACK,true);
            ObjectSetString(chart_id,"label "+IntegerToString(p),OBJPROP_FONT,"Arial");
            ObjectSetInteger(chart_id,"label "+IntegerToString(p),OBJPROP_FONTSIZE,10);
            ObjectSetDouble(chart_id,"label "+IntegerToString(p),OBJPROP_ANGLE,-90);
            ObjectSetString(chart_id,"label "+IntegerToString(p),OBJPROP_TEXT,eventname[p]);
           }
         return p;
        }
     }
   return pointer_start;
  }

//Country ID to Currency//

string CNews::CountryIdToCurrency(ENUM_COUNTRY_ID c)
  {
   switch(c)
     {
      case 999:
         return "EUR";     // EU
      case 840:
         return "USD";     // USA
      case 36:
         return "AUD";     // Australia
      case 554:
         return "NZD";     // NewZealand
      case 156:
         return "CNY";     // China
      case 826:
         return "GBP";     // UK
      case 756:
         return "CHF";     // Switzerland
      case 276:
         return "EUR";     // Germany
      case 250:
         return "EUR";     // France
      case 380:
         return "EUR";     // Italy
      case 724:
         return "EUR";     // Spain
      case 76:
         return "BRL";     // Brazil
      case 410:
         return "KRW";     // South Korea
      default:
         return "";
     }
  }

//Currency To Country ID//

int CNews::CurrencyToCountryId(string currency)
  {
   if(currency=="EUR")
     {
      return 999;
     }
   if(currency=="USD")
     {
      return 840;
     }
   if(currency=="AUD")
     {
      return 36;
     }
   if(currency=="NZD")
     {
      return 554;
     }
   if(currency=="CNY")
     {
      return 156;
     }
   if(currency=="GBP")
     {
      return 826;
     }
   if(currency=="CHF")
     {
      return 756;
     }
   if(currency=="BRL")
     {
      return 76;
     }
   if(currency=="KRW")
     {
      return 410;
     }
   return 0;
  }

//Server Time To GMT//

datetime CNews::GMT(ushort server_offset_winter,ushort server_offset_summer)
  {
   if(!MQLInfoInteger(MQL_OPTIMIZATION) && !MQLInfoInteger(MQL_TESTER))
     {
      return TimeGMT();
     }

   servertime=TimeCurrent(); 
   TimeToStruct(servertime,tm);
   static bool initialized=false;
   static bool summertime=true;

   if(!initialized)
     {
      if(tm.mon<=2 || (tm.mon==3 && tm.day<=7))
        {
         summertime=false;
        }
      if((tm.mon==11 && tm.day>=8) || tm.mon==12)
        {
         summertime=false;
        }
      initialized=true;
     }

   if(tm.mon==3 && tm.day>7 && tm.day_of_week==0 && tm.hour==7+server_offset_winter)  
     {
      summertime=true;
     }

   if(tm.mon==11 && tm.day<=7 && tm.day_of_week==0 && tm.hour==7+server_offset_summer)  
     {
      summertime=false;
     }
   if(summertime)
     {
      return servertime-server_offset_summer*3600;
     }
   else
     {
      return servertime-server_offset_winter*3600;
     }
  }

//Get Next News Panel//

int CNews::GetNextNewsEvent(int pointer_start, string currency, Importanza importance, ENUM_COUNTRY_ID countri)
  {
   for(int p = pointer_start; p < ArraySize(event); p++)
      {
       if(StringFind(eventname[p], "IPC a/a") >= 0 || StringFind(eventname[p], "Tasso Di Disoccupazione") >= 0 ||
          StringFind(eventname[p], "IPC m/m") >= 0 || StringFind(eventname[p], "IPP m/m") >= 0 || StringFind(eventname[p], "Richieste iniziali di sussidi di disoccupazione negli Stati Uniti") >= 0 || 
          StringFind(eventname[p],"Vendite al Dettaglio negli Stati Uniti a/a") >= 0 || StringFind(eventname[p], "Vendite al Dettaglio negli Stati Uniti a/a") >= 0)
         {
          event[p].importance = CALENDAR_IMPORTANCE_HIGH; 
         }
         
       if(StringFind(eventname[p], "IPC Core a/a") >= 0 || StringFind(eventname[p], "IPP Core a/a") >= 0 || StringFind(eventname[p], "IPP a/a") >= 0 ||
          StringFind(eventname[p], "IPC Core m/m") >= 0 || StringFind(eventname[p], "IPP Core m/m") >= 0)
         {
          event[p].importance = CALENDAR_IMPORTANCE_MODERATE; 
         }
         
       bool ImportanceFilter = (importance == Bassa) ? event[p].importance == CALENDAR_IMPORTANCE_LOW ||
                                                       event[p].importance == CALENDAR_IMPORTANCE_MODERATE ||
                                                       event[p].importance == CALENDAR_IMPORTANCE_HIGH : 
                               (importance == Media) ? event[p].importance == CALENDAR_IMPORTANCE_MODERATE ||
                                                       event[p].importance == CALENDAR_IMPORTANCE_HIGH : 
                               (importance == Alta)  ? event[p].importance == CALENDAR_IMPORTANCE_HIGH : false;                

       if(ImportanceFilter && CountryIdToCurrency((ENUM_COUNTRY_ID)event[p].country_id) == currency && news.event[p].country_id == countri && news.event[p].sector != CALENDAR_SECTOR_BUSINESS)
         {
          return p;
         }
      }
   return -1;
  }

//+------------------------------------------------------------------+
//| Functions                                                        |
//+------------------------------------------------------------------+

//Enum//

enum ENUM_CURRENCY
  {
   USD = 0,//Dollaro Americano (USD)
   EUR = 1,//Euro (EUR)
   GBP = 2,//Sterlina (GBP)
   AUD = 3,//Dollaro Australiano (AUD)
   CAD = 4,//Dollaro Canadese (CAD)
   CHF = 5,//Franco Svizzero (CHF)
   CNY = 6,//Yuan Cinese (CNY)
   JPY = 7,//Yen Giapponese (JPY)
   NZD = 8,//Dollaro Neozelandese (NZD)
  };

enum VolumeType
  {
   Tick = 0,//Volumi Tick
   Reali = 1,//Volumi Reali
  };

//Errori//

string ErrorDescription(int error_code)
  {
   switch (error_code)
    {
     case 0: return "Nessun errore";
     case 1: return "Errore di funzione sconosciuta";
     case 2: return "Parametro non valido";
     case 3: return "Condizioni di mercato non valide";
     case 4: return "Operazione non consentita";
     case 5: return "Timeout della richiesta";
     case 10004: return "Nessuna connessione al server di trading";
     case 10006: return "La richiesta di trading è stata scartata";
     case 10007: return "Il server di trading è occupato";
     case 10008: return "Timeout della richiesta di trading";
     case 10009: return "Prevenzione del rischio: ordine rifiutato";
     case 10010: return "Non ci sono ordini aperti";
     case 10011: return "Operazione non valida per il conto corrente";
     case 10012: return "Volume del lotto non valido";
     case 10013: return "Prezzo non valido";
     case 10014: return "Stop loss o take profit non valido";
     case 10015: return "Prezzo di mercato non disponibile";
     case 10016: return "Condizioni di margine insufficienti";
     case 10017: return "Limite massimo di ordini raggiunto";
     case 10018: return "La richiesta di trading è stata annullata";
     case 10019: return "Nessuna cronologia di trading disponibile";
     default: return "Errore sconosciuto. Codice: " + IntegerToString(error_code);
    }
 }

//Punti//

double point(string Simbolo)
  {
   double p = SymbolInfoDouble(Simbolo, SYMBOL_POINT);
  
   return(p);
  }
  
//Prezzo//

double Bid(string Simbolo)
  {
   double bid = NormalizeDouble(SymbolInfoDouble(Simbolo, SYMBOL_BID), Digit(Simbolo));
   
   return(bid);
  }
  
double Ask(string Simbolo) 
  {
   double ask = NormalizeDouble(SymbolInfoDouble(Simbolo, SYMBOL_ASK), Digit(Simbolo));
   
   return(ask);
  }

//Prezzo//

double Open(string Simbolo, ENUM_TIMEFRAMES TimeFrame, int Shift)
  {
   double value = NormalizeDouble(iOpen(Simbolo,TimeFrame,Shift), Digit(Simbolo));
   
   return value;
  }

double Close(string Simbolo, ENUM_TIMEFRAMES TimeFrame, int Shift)
  {
   double value = NormalizeDouble(iClose(Simbolo,TimeFrame,Shift), Digit(Simbolo));
   
   return value;
  }

double High(string Simbolo, ENUM_TIMEFRAMES TimeFrame, int Shift)
  {
   double value = NormalizeDouble(iHigh(Simbolo,TimeFrame,Shift), Digit(Simbolo));
   
   return value;
  }
  
double Low(string Simbolo, ENUM_TIMEFRAMES TimeFrame, int Shift)
  {
   double value = NormalizeDouble(iLow(Simbolo,TimeFrame,Shift), Digit(Simbolo));
   
   return value;
  }

double LowestLow(string symbol, ENUM_TIMEFRAMES TimeFrame, int count)
  {
   double lL = iLow(symbol,TimeFrame,iLowest(symbol,TimeFrame,MODE_LOW,count,0));

   return(lL);
  }

double HighestHigh(string symbol, ENUM_TIMEFRAMES TimeFrame, int count)
  {
   double hH = iHigh(symbol,TimeFrame,iHighest(symbol,TimeFrame,MODE_HIGH,count,0));

   return(hH);
  }
  
//Ordini a Mercato//

void SendBuy(double Lotti, string Simbolo, string Commento, int MagicNumber)
  {
   trade.SetExpertMagicNumber(MagicNumber);
   
   if(!trade.Buy(Lotti, Simbolo, SymbolInfoDouble(Simbolo, SYMBOL_BID), 0.0, 0.0, Commento))
      {
       int error_code = GetLastError();
       Print("Errore nell'aprire ordine BUY per ", Simbolo, ". Codice errore: ", error_code, " - Descrizione: ", ErrorDescription(error_code));
       ResetLastError();
      }
    else
      {
       Print("Ordine BUY aperto correttamente per ", Simbolo, ". Lotti: ", Lotti);
      }
  }
  
void SendSell(double Lotti, string Simbolo, string Commento, int MagicNumber)
  {
   trade.SetExpertMagicNumber(MagicNumber);
   
   if(!trade.Sell(Lotti, Simbolo, SymbolInfoDouble(Simbolo, SYMBOL_ASK), 0.0, 0.0, Commento))
     {
      int error_code = GetLastError();
      Print("Errore nell'aprire ordine SELL per ", Simbolo, ". Codice errore: ", error_code, " - Descrizione: ", ErrorDescription(error_code));
      ResetLastError();  
     }
    else
     {
      Print("Ordine SELL aperto correttamente per ", Simbolo, ". Lotti: ", Lotti);
     }
  }

//Ordini Limite//

void SendBuyLimit(double Prezzo, double Lotti, string Simbolo, string Commento, int MagicNumber)
  {
   trade.SetExpertMagicNumber(MagicNumber);
   
   if(!trade.BuyLimit(Lotti, Prezzo, Simbolo, 0.0, 0.0, 0, 0, Commento))
      {
       int error_code = GetLastError();
       Print("Errore nell'aprire ordine BUY per ", Simbolo, ". Codice errore: ", error_code, " - Descrizione: ", ErrorDescription(error_code));
       ResetLastError();
      }
    else
      {
       Print("Ordine BUY aperto correttamente per ", Simbolo, ". Lotti: ", Lotti);
      }
  }
  
void SendSellLimit(double Prezzo, double Lotti, string Simbolo, string Commento, int MagicNumber)
  {
   trade.SetExpertMagicNumber(MagicNumber);
   
   if(!trade.SellLimit(Lotti, Prezzo, Simbolo, 0.0, 0.0, 0, 0, Commento))
     {
      int error_code = GetLastError();
      Print("Errore nell'aprire ordine SELL per ", Simbolo, ". Codice errore: ", error_code, " - Descrizione: ", ErrorDescription(error_code));
      ResetLastError();  
     }
    else
     {
      Print("Ordine SELL aperto correttamente per ", Simbolo, ". Lotti: ", Lotti);
     }
  }

//Digits//

int Digit(string Simbolo)
  {
   int i = 0;
   
   i = (int)SymbolInfoInteger(Simbolo,SYMBOL_DIGITS);
   
   return(i);
  }
   
//Chiudi tutti i Buy//

void CloseAllBuy(string Simbolo, int MagicNumber)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      long PositionMagicNumber = PositionGetInteger(POSITION_MAGIC);
      long PositionDirection = PositionGetInteger(POSITION_TYPE);
      string PositionSymbol = PositionGetString(POSITION_SYMBOL);

      if(PositionDirection == POSITION_TYPE_BUY && PositionMagicNumber == MagicNumber && PositionSymbol == Simbolo)
        {
         trade.PositionClose(ticket);
        }
     }
  }

//Chiudi tutti i Sell//

void CloseAllSell(string Simbolo, int MagicNumber)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      long PositionMagicNumber = PositionGetInteger(POSITION_MAGIC);
      long PositionDirection = PositionGetInteger(POSITION_TYPE);
      string PositionSymbol = PositionGetString(POSITION_SYMBOL);

      if(PositionDirection == POSITION_TYPE_SELL && PositionMagicNumber == MagicNumber && PositionSymbol == Simbolo)
        {
         trade.PositionClose(ticket);
        }
     }
  }
  
//Counter Ordini//

double CountOrders(string Simbolo, int MagicNumber, int positionType)
  {
   int OpenOrders = 0;

   for(int i = 0; i < PositionsTotal(); i++)
      {
       if(PositionGetSymbol(i) == Simbolo && 
          PositionGetInteger(POSITION_TYPE) == positionType && 
          PositionGetInteger(POSITION_MAGIC) == MagicNumber) 
         {
          OpenOrders++;
         }
      }
      
    return OpenOrders;
   }

double CounterBuy(string Simbolo, int MagicNumber) 
  { 
   return CountOrders(Simbolo, MagicNumber, POSITION_TYPE_BUY);
  }

double CounterSell(string Simbolo, int MagicNumber)
  {
   return CountOrders(Simbolo, MagicNumber, POSITION_TYPE_SELL);
  }
  
//Counter Ordini Limite//

double CountOrdersLimit(string Simbolo, int MagicNumber, int OrderType)
  {
   int OpenOrders = 0;

   for(int i = 0; i < OrdersTotal(); i++)
      {
       if(OrderGetString(ORDER_SYMBOL) == Simbolo && 
          OrderGetInteger(ORDER_TYPE) == OrderType && 
          OrderGetInteger(ORDER_MAGIC) == MagicNumber) 
         {
          OpenOrders++;
         }
      }
      
    return OpenOrders;
   }

double CounterBuyLimit(string Simbolo, int MagicNumber) 
  { 
   return CountOrders(Simbolo, MagicNumber, ORDER_TYPE_BUY_LIMIT);
  }

double CounterSellLimit(string Simbolo, int MagicNumber)
  {
   return CountOrders(Simbolo, MagicNumber, ORDER_TYPE_SELL_LIMIT);
  }

//LotSize Per SL//

double CalculateLotSize(string Simbolo, double SL, double Risk_Per_Trade)
  {
   double StopLoss = NormalizeDouble(SL,Digit(Simbolo));
   double tickValue = SymbolInfoDouble(Simbolo, SYMBOL_TRADE_TICK_VALUE);
   double point = SymbolInfoDouble(Simbolo, SYMBOL_POINT);
   double volumeStep = SymbolInfoDouble(Simbolo, SYMBOL_VOLUME_STEP);
   double volumeMin = SymbolInfoDouble(Simbolo, SYMBOL_VOLUME_MIN);
   double volumeMax = SymbolInfoDouble(Simbolo, SYMBOL_VOLUME_MAX);
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double accountRisk = accountBalance * (Risk_Per_Trade / 100.0);   
   double pipValue = tickValue / point;
   double lotSize = accountRisk / (pipValue * StopLoss);

   lotSize = MathFloor(lotSize / volumeStep) * volumeStep;

   if (lotSize < volumeMin) lotSize = volumeMin;
   if (lotSize > volumeMax) lotSize = volumeMax;
   if (lotSize < volumeMin || lotSize > volumeMax)
     {
      Print("Calculated lot size is invalid: ", lotSize);
      return 0;
     }
   return lotSize;
  }

//Contracts Per SL//

double CalculateContractSize(string Simbolo, double SL, double Risk_Per_Trade)
  {
   double StopLoss = NormalizeDouble(SL, Digit(Simbolo));
   double tickValue = SymbolInfoDouble(Simbolo, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(Simbolo, SYMBOL_TRADE_TICK_SIZE);  
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double accountRisk = accountBalance * (Risk_Per_Trade / 100.0);  
   double stopTicks = StopLoss / tickSize;
   double contractSize = accountRisk / (tickValue * stopTicks);

   contractSize = MathFloor(contractSize);

   double contractMin = SymbolInfoDouble(Simbolo, SYMBOL_VOLUME_MIN);
   double contractMax = SymbolInfoDouble(Simbolo, SYMBOL_VOLUME_MAX);

   if(contractSize < contractMin) contractSize = contractMin;
   if(contractSize > contractMax) contractSize = contractMax;
   if(contractSize < contractMin || contractSize > contractMax)
     {
      Print("La dimensione calcolata del contratto non è valida: ", contractSize);
      return 0;
     }

   return contractSize;
  }

//Creazione Label//

void Label(string Name, ENUM_BASE_CORNER Corner, int Distance_X, int Distance_Y, string Text, color Color, string Font, int Size)
  {
   ObjectCreate(0, Name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, Name, OBJPROP_CORNER, Corner);
   ObjectSetInteger(0, Name, OBJPROP_XDISTANCE, Distance_X);
   ObjectSetInteger(0, Name, OBJPROP_YDISTANCE, Distance_Y);
   ObjectSetString(0, Name, OBJPROP_TEXT, Text);
   ObjectSetString(0, Name, OBJPROP_FONT, Font);
   ObjectSetInteger(0, Name, OBJPROP_FONTSIZE, Size);
   ObjectSetInteger(0, Name, OBJPROP_COLOR, Color);
   ObjectSetInteger(0 ,Name ,OBJPROP_SELECTABLE ,false); 
   ObjectSetInteger(0 ,Name ,OBJPROP_SELECTED ,false); 
   ObjectSetInteger(0 ,Name ,OBJPROP_HIDDEN ,true);    
  }

//Creazione Edit//

void Edit(string Name, ENUM_BASE_CORNER Corner, int Distance_X, int Distance_Y, int Size_X, int Size_Y, string Text, color Color, string Font, int Size)
  {
   ObjectCreate(0, Name, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, Name, OBJPROP_CORNER, Corner);
   ObjectSetInteger(0, Name, OBJPROP_XDISTANCE, Distance_X);
   ObjectSetInteger(0, Name, OBJPROP_YDISTANCE, Distance_Y);
   ObjectSetInteger(0, Name, OBJPROP_XSIZE, Size_X);
   ObjectSetInteger(0, Name, OBJPROP_YSIZE, Size_Y);   
   ObjectSetString(0, Name, OBJPROP_TEXT, Text);
   ObjectSetString(0, Name, OBJPROP_FONT, Font);
   ObjectSetInteger(0, Name, OBJPROP_FONTSIZE, Size);
   ObjectSetInteger(0, Name, OBJPROP_COLOR, Color);
   ObjectSetInteger(0, Name, OBJPROP_READONLY, false);
   ObjectSetInteger(0 ,Name, OBJPROP_ZORDER, 0); 
   ObjectSetInteger(0 ,Name ,OBJPROP_SELECTABLE ,false); 
   ObjectSetInteger(0 ,Name ,OBJPROP_SELECTED ,false); 
   ObjectSetInteger(0 ,Name ,OBJPROP_HIDDEN ,true);    
  }


//Creazione Button//

void Button(string Name, ENUM_BASE_CORNER Corner, int Distance_X, int Distance_Y, int Size_X, int Size_Y, string Text, color Color, color BackGround_Color, string Font)
  {
   ObjectCreate(0, Name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, Name, OBJPROP_CORNER, Corner);
   ObjectSetInteger(0, Name, OBJPROP_XDISTANCE, Distance_X);
   ObjectSetInteger(0, Name, OBJPROP_YDISTANCE, Distance_Y);
   ObjectSetInteger(0, Name, OBJPROP_XSIZE, Size_X);
   ObjectSetInteger(0, Name, OBJPROP_YSIZE, Size_Y);
   ObjectSetInteger(0, Name, OBJPROP_BGCOLOR, BackGround_Color);
   ObjectSetInteger(0, Name, OBJPROP_BORDER_COLOR, Color);
   ObjectSetInteger(0 ,Name, OBJPROP_ZORDER, 0); 
   ObjectSetInteger(0, Name, OBJPROP_COLOR, Color);
   ObjectSetString(0, Name, OBJPROP_TEXT, Text);
   ObjectSetString(0, Name, OBJPROP_FONT, Font);
   ObjectSetInteger(0, Name ,OBJPROP_STATE ,false); 
  }

//Creazione Label Rettangolare//

void RectangleLabel(string Name, ENUM_BASE_CORNER Corner, int Distance_X, int Distance_Y, int Size_X, int Size_Y, color Border_Color, color BackGround_Color, ENUM_BORDER_TYPE Border_Type)
  {
   ObjectCreate(0, Name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, Name, OBJPROP_CORNER, Corner);
   ObjectSetInteger(0, Name, OBJPROP_XDISTANCE, Distance_X);
   ObjectSetInteger(0, Name, OBJPROP_YDISTANCE, Distance_Y);
   ObjectSetInteger(0, Name, OBJPROP_XSIZE, Size_X);
   ObjectSetInteger(0, Name, OBJPROP_YSIZE, Size_Y);
   ObjectSetInteger(0, Name, OBJPROP_BGCOLOR, BackGround_Color);
   ObjectSetInteger(0, Name, OBJPROP_BORDER_COLOR, Border_Color);
   ObjectSetInteger(0, Name, OBJPROP_BORDER_TYPE, Border_Type);
   ObjectSetInteger(0 ,Name ,OBJPROP_SELECTABLE ,false); 
   ObjectSetInteger(0 ,Name ,OBJPROP_SELECTED ,false); 
   ObjectSetInteger(0 ,Name ,OBJPROP_HIDDEN ,true);    
  }

//Creazione Linea Verticale//

void VerticalLine(string Name, datetime time, color Color, int Width, ENUM_LINE_STYLE Style)
  {
   ObjectCreate(0, Name, OBJ_VLINE, 0, time, 0);
   ObjectSetInteger(0, Name, OBJPROP_COLOR, Color);
   ObjectSetInteger(0, Name, OBJPROP_STYLE, Style);
   ObjectSetInteger(0 ,Name ,OBJPROP_WIDTH ,Width);    
   ObjectSetInteger(0 ,Name ,OBJPROP_HIDDEN ,true);    
   ObjectSetInteger(0 ,Name ,OBJPROP_SELECTABLE ,false); 
   ObjectSetInteger(0 ,Name ,OBJPROP_SELECTED ,false); 
  }
  
//Creazione Evento//

void Event(string Name, datetime time, string Text, color Color, int Width)
  {
   ObjectCreate(0, Name, OBJ_EVENT, 0, time, 0);
   ObjectSetString(0, Name, OBJPROP_TEXT, Text);
   ObjectSetInteger(0, Name, OBJPROP_COLOR, Color);
   ObjectSetInteger(0 ,Name ,OBJPROP_WIDTH ,Width);    
   ObjectSetInteger(0 ,Name ,OBJPROP_HIDDEN ,true);    
   ObjectSetInteger(0 ,Name, OBJPROP_ZORDER, 0); 
  }

// TimeFrame to String //

string TimeFrameToString(ENUM_TIMEFRAMES timeframe)
  {
   switch(timeframe)
     {
      case PERIOD_CURRENT: return "Corrente";
      case PERIOD_M1:   return "1 Minuto";
      case PERIOD_M2:   return "2 Minuti";
      case PERIOD_M3:   return "3 Minuti";
      case PERIOD_M4:   return "4 Minuti";
      case PERIOD_M5:   return "5 Minuti";
      case PERIOD_M6:   return "6 Minuti";
      case PERIOD_M10:  return "10 Minuti";
      case PERIOD_M12:  return "12 Minuti";
      case PERIOD_M15:  return "15 Minuti";
      case PERIOD_M20:  return "20 Minuti";
      case PERIOD_M30:  return "30 Minuti";
      case PERIOD_H1:   return "1 Ora";
      case PERIOD_H2:   return "2 Ore";
      case PERIOD_H3:   return "3 Ore";
      case PERIOD_H4:   return "4 Ore";
      case PERIOD_H6:   return "6 Ore";
      case PERIOD_H8:   return "8 Ore";
      case PERIOD_H12:  return "12 Ore";
      case PERIOD_D1:   return "Giornaliero";
      case PERIOD_W1:   return "Settimanale";
      case PERIOD_MN1:  return "Mensile";
      default:          return "Unknown Timeframe";
     }
  }

//TimeFrame to Int//

int TimeFrameToInt(ENUM_TIMEFRAMES timeframe)
  {
   switch(timeframe)
     {
      case PERIOD_M1:   return 1;
      case PERIOD_M2:   return 2;
      case PERIOD_M3:   return 3;
      case PERIOD_M4:   return 4;
      case PERIOD_M5:   return 5;
      case PERIOD_M6:   return 6;
      case PERIOD_M10:  return 10;
      case PERIOD_M12:  return 12;
      case PERIOD_M15:  return 15;
      case PERIOD_M20:  return 20;
      case PERIOD_M30:  return 30;
      case PERIOD_H1:   return 60;
      case PERIOD_H2:   return 120;
      case PERIOD_H3:   return 180;
      case PERIOD_H4:   return 240;
      case PERIOD_H6:   return 360;
      case PERIOD_H8:   return 480;
      case PERIOD_H12:  return 720;
      case PERIOD_D1:   return 1440;
      case PERIOD_W1:   return 10080;
      case PERIOD_MN1:  return 40320;
      default:          return 0;
     }
  }

//Setta SL ad un prezzo Limite//

void SetStopLossPriceBuyLimit(string Simbolo, int MagicNumber, double StopLoss, string comment)
  {
   double SL = NormalizeDouble(StopLoss,Digit(Simbolo));
      
   for(int w = (OrdersTotal() - 1); w >= 0; w--)
      {
       ulong Ticket = OrderGetTicket(w);
       long PositionMagicNumber = OrderGetInteger(ORDER_MAGIC);
       string PositionComment = OrderGetString(ORDER_COMMENT);
       string PositionSymbol = OrderGetString(ORDER_SYMBOL);
       long PositionDirection = OrderGetInteger(ORDER_TYPE);       
     
       if(PositionSymbol == Simbolo && PositionMagicNumber == MagicNumber && PositionDirection == ORDER_TYPE_BUY_LIMIT && PositionComment == comment)
         {
          double PositionStopLoss = OrderGetDouble(ORDER_SL);
          
          if(PositionStopLoss == 0.0) 
            {            
             int j = trade.OrderModify(Ticket, Price, SL, OrderGetDouble(ORDER_TP),ORDER_TIME_DAY,0,0);
           }
         }
      }    
  } 

void SetStopLossPriceSellLimit(string Simbolo, int MagicNumber, double StopLoss, string comment)
  {
   double SL = NormalizeDouble(StopLoss,Digit(Simbolo));
      
   for(int w = (OrdersTotal() - 1); w >= 0; w--)
      {
       ulong Ticket = OrderGetTicket(w);
       long PositionMagicNumber = OrderGetInteger(ORDER_MAGIC);
       string PositionComment = OrderGetString(ORDER_COMMENT);
       string PositionSymbol = OrderGetString(ORDER_SYMBOL);
       long PositionDirection = OrderGetInteger(ORDER_TYPE);       
     
       if(PositionSymbol == Simbolo && PositionMagicNumber == MagicNumber && PositionDirection == ORDER_TYPE_SELL_LIMIT && PositionComment == comment)
         {
          double PositionStopLoss = OrderGetDouble(ORDER_SL);
          
          if(PositionStopLoss == 0.0) 
            {                       
             int j = trade.OrderModify(Ticket, Price, SL, OrderGetDouble(ORDER_TP),ORDER_TIME_DAY,0,0);
            }
         }   
      }    
  }   
  
//Setta TP ad un prezzo Limite//

void SetTakeProfitPriceBuyLimit(string Simbolo, int MagicNumber, double TakeProfit, string comment)
  {
   double TP = NormalizeDouble(TakeProfit,Digit(Simbolo));
      
   for(int w = (OrdersTotal() - 1); w >= 0; w--)
      {
       ulong Ticket = OrderGetTicket(w);
       long PositionMagicNumber = OrderGetInteger(ORDER_MAGIC);
       string PositionComment = OrderGetString(ORDER_COMMENT);
       string PositionSymbol = OrderGetString(ORDER_SYMBOL);
       long PositionDirection = OrderGetInteger(ORDER_TYPE);       
     
       if(PositionSymbol == Simbolo && PositionMagicNumber == MagicNumber && PositionDirection == ORDER_TYPE_BUY_LIMIT && PositionComment == comment)
         {
          double PositionTP = OrderGetDouble(ORDER_TP);
          
          if(PositionTP == 0.0) 
            {                       
             int j = trade.OrderModify(Ticket, Price, OrderGetDouble(ORDER_SL), TP,ORDER_TIME_DAY,0,0);
            }
         }   
      }    
  } 

void SetTakeProfitPriceSellLimit(string Simbolo, int MagicNumber, double TakeProfit, string comment)
  {
   double TP = NormalizeDouble(TakeProfit,Digit(Simbolo));
      
      
   for(int w = (OrdersTotal() - 1); w >= 0; w--)
      {
       ulong Ticket = OrderGetTicket(w);
       long PositionMagicNumber = OrderGetInteger(ORDER_MAGIC);
       string PositionComment = OrderGetString(ORDER_COMMENT);
       string PositionSymbol = OrderGetString(ORDER_SYMBOL);
       long PositionDirection = OrderGetInteger(ORDER_TYPE);       
     
       if(PositionSymbol == Simbolo && PositionMagicNumber == MagicNumber && PositionDirection == ORDER_TYPE_SELL_LIMIT && PositionComment == comment)
         {
          double PositionTP = OrderGetDouble(ORDER_TP);
          
          if(PositionTP == 0.0) 
            {                       
             int j = trade.OrderModify(Ticket, Price, OrderGetDouble(ORDER_SL), TP,ORDER_TIME_DAY,0,0);
            }
         }   
      }    
  }   

//Setta SL ad un prezzo//

void SetStopLossPriceBuy(string Simbolo, int MagicNumber, double StopLoss, string comment)
  {
   double SL = NormalizeDouble(StopLoss,Digit(Simbolo));
      
   for(int w = (PositionsTotal() - 1); w >= 0; w--)
      {
       ulong Ticket = PositionGetTicket(w);
       long PositionMagicNumber = PositionGetInteger(POSITION_MAGIC);
       string PositionComment = PositionGetString(POSITION_COMMENT);
       string PositionSymbol = PositionGetString(POSITION_SYMBOL);
       long PositionDirection = PositionGetInteger(POSITION_TYPE);       
     
       if(PositionSymbol == Simbolo && PositionMagicNumber == MagicNumber && PositionDirection == POSITION_TYPE_BUY && PositionComment == comment)
         {
          double PositionStopLoss = PositionGetDouble(POSITION_SL);
          
          if(PositionStopLoss == 0.0) 
            {            
             int j = trade.PositionModify(Ticket, SL, position.TakeProfit());
           }
         }
      }    
  } 

void SetStopLossPriceSell(string Simbolo, int MagicNumber, double StopLoss, string comment)
  {
   double SL = NormalizeDouble(StopLoss,Digit(Simbolo));
      
   for(int w = (PositionsTotal() - 1); w >= 0; w--)
      {
       ulong Ticket = PositionGetTicket(w);
       long PositionMagicNumber = PositionGetInteger(POSITION_MAGIC);
       string PositionComment = PositionGetString(POSITION_COMMENT);
       string PositionSymbol = PositionGetString(POSITION_SYMBOL);
       long PositionDirection = PositionGetInteger(POSITION_TYPE);       
     
       if(PositionSymbol == Simbolo && PositionMagicNumber == MagicNumber && PositionDirection == POSITION_TYPE_SELL && PositionComment == comment)
         {
          double PositionStopLoss = PositionGetDouble(POSITION_SL);
          
          if(PositionStopLoss == 0.0) 
            {                       
             int j = trade.PositionModify(Ticket, SL, position.TakeProfit());
            }
         }   
      }    
  }   
  
//Setta TP ad un prezzo//

void SetTakeProfitPriceBuy(string Simbolo, int MagicNumber, double TakeProfit, string comment)
  {
   double TP = NormalizeDouble(TakeProfit,Digit(Simbolo));
      
   for(int w = (PositionsTotal() - 1); w >= 0; w--)
      {
       ulong Ticket = PositionGetTicket(w);
       long PositionMagicNumber = PositionGetInteger(POSITION_MAGIC);
       string PositionComment = PositionGetString(POSITION_COMMENT);
       string PositionSymbol = PositionGetString(POSITION_SYMBOL);
       long PositionDirection = PositionGetInteger(POSITION_TYPE);       
     
       if(PositionSymbol == Simbolo && PositionMagicNumber == MagicNumber && PositionDirection == POSITION_TYPE_BUY && PositionComment == comment)
         {
          double PositionTP = PositionGetDouble(POSITION_TP);
          
          if(PositionTP == 0.0) 
            {                       
             int j = trade.PositionModify(Ticket, position.StopLoss(), TP);
            }
         }   
      }    
  } 

void SetTakeProfitPriceSell(string Simbolo, int MagicNumber, double TakeProfit, string comment)
  {
   double TP = NormalizeDouble(TakeProfit,Digit(Simbolo));
      
   for(int w = (PositionsTotal() - 1); w >= 0; w--)
      {
       ulong Ticket = PositionGetTicket(w);
       long PositionMagicNumber = PositionGetInteger(POSITION_MAGIC);
       string PositionComment = PositionGetString(POSITION_COMMENT);
       string PositionSymbol = PositionGetString(POSITION_SYMBOL);
       long PositionDirection = PositionGetInteger(POSITION_TYPE);       
     
       if(PositionSymbol == Simbolo && PositionMagicNumber == MagicNumber && PositionDirection == POSITION_TYPE_SELL && PositionComment == comment)
         {
          double PositionTP = PositionGetDouble(POSITION_TP);
          
          if(PositionTP == 0.0) 
            {                       
             int j = trade.PositionModify(Ticket, position.StopLoss(), TP);
            }
         }   
      }    
  }   

//Break Even//

void BreakEven(string Simbolo, int MagicNumber, string comment)
  {      
   for(int w = (PositionsTotal() - 1); w >= 0; w--)
      {
       ulong Ticket = PositionGetTicket(w);
       long PositionMagicNumber = PositionGetInteger(POSITION_MAGIC);
       string PositionComment = PositionGetString(POSITION_COMMENT);
       string PositionSymbol = PositionGetString(POSITION_SYMBOL);
       long PositionDirection = PositionGetInteger(POSITION_TYPE);       
     
       if(PositionSymbol == Simbolo && PositionMagicNumber == MagicNumber && PositionComment == comment && PositionDirection == POSITION_TYPE_BUY)
         {
          double PositionSL = NormalizeDouble(PositionGetDouble(POSITION_SL),Digit(Simbolo));         
          double PositionOpen = NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN),Digit(Simbolo));
          
          if(PositionSL != PositionOpen) 
            {                      
             if(Ask(Simbolo) > PositionOpen)
               { 
                int j = trade.PositionModify(Ticket, PositionOpen, position.TakeProfit());
               }
             else
                if(Ask(Simbolo) < PositionOpen)
                  {
                   Alert("Trade is in loss and cannot be moved to Break Even");
                  }
            }
         }   
       if(PositionSymbol == Simbolo && PositionMagicNumber == MagicNumber && PositionComment == comment && PositionDirection == POSITION_TYPE_SELL)
         {
          double PositionSL = NormalizeDouble(PositionGetDouble(POSITION_SL),Digit(Simbolo));         
          double PositionOpen = NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN),Digit(Simbolo));
          
          if(PositionSL != PositionOpen) 
            {                       
             if(Bid(Simbolo) < PositionOpen)
               {
                int j = trade.PositionModify(Ticket, PositionOpen, position.TakeProfit());
               }
             else
                if(Bid(Simbolo) > PositionOpen)
                  {
                   Alert("Trade is in loss and cannot be moved to Break Even");                   
                  }
            }
         }   
      }    
  }   

//News//

void GetNextNews(string currency, int OffSet, ENUM_COUNTRY_ID country, bool reset_index)
  {
   if(reset_index)
     {
      last_event_index = 0;
      GlobalIndex = 0;
     }
  
   int total_events = news.update();

   if(total_events > 0)
     {
      datetime current_time = TimeCurrent();
      datetime closest_event_time = 0;
      int closest_event_index = -1;
      int highest_importance = -1;

      for(int next_event_index = news.next(last_event_index, currency, false, 0); next_event_index < total_events; next_event_index++)
         {
          if(StringFind(news.eventname[next_event_index], "IPC a/a") >= 0 || StringFind(news.eventname[next_event_index], "Tasso Di Disoccupazione") >= 0 ||
             StringFind(news.eventname[next_event_index], "IPC m/m") >= 0 || StringFind(news.eventname[next_event_index], "IPP m/m") >= 0 || StringFind(news.eventname[next_event_index], "Richieste iniziali di sussidi di disoccupazione negli Stati Uniti") >= 0 || 
             StringFind(news.eventname[next_event_index],"Vendite al Dettaglio negli Stati Uniti a/a") >= 0 || StringFind(news.eventname[next_event_index], "Vendite al Dettaglio negli Stati Uniti a/a") >= 0)
            {
             news.event[next_event_index].importance = CALENDAR_IMPORTANCE_HIGH; 
            }
            
          if(StringFind(news.eventname[next_event_index], "IPC Core a/a") >= 0 || StringFind(news.eventname[next_event_index], "IPP Core a/a") >= 0 || StringFind(news.eventname[next_event_index], "IPP a/a") >= 0 ||
             StringFind(news.eventname[next_event_index], "IPC Core m/m") >= 0 || StringFind(news.eventname[next_event_index], "IPP Core m/m") >= 0)
            {
             news.event[next_event_index].importance = CALENDAR_IMPORTANCE_MODERATE; 
            }
   
         bool ImportanceFilter = (Imp == Bassa) ? news.event[next_event_index].importance != CALENDAR_IMPORTANCE_NONE : 
                                 (Imp == Media) ? news.event[next_event_index].importance == CALENDAR_IMPORTANCE_MODERATE ||
                                                  news.event[next_event_index].importance == CALENDAR_IMPORTANCE_HIGH : 
                                 (Imp == Alta)  ? news.event[next_event_index].importance == CALENDAR_IMPORTANCE_HIGH : false;                
         
         if(ImportanceFilter && news.event[next_event_index].country_id == country && news.event[next_event_index].sector != CALENDAR_SECTOR_BUSINESS)
           {
            if(news.event[next_event_index].time >= current_time - PeriodSeconds(PERIOD_M10))
              {
               if(closest_event_index == -1 || news.event[next_event_index].time < closest_event_time)
                 {
                  closest_event_time = news.event[next_event_index].time;
                  closest_event_index = next_event_index;
                  highest_importance = news.event[next_event_index].importance;
                 }
               else
                  if(news.event[next_event_index].time == closest_event_time)
                    {
                     if(news.event[next_event_index].importance > highest_importance)
                       {
                        closest_event_index = next_event_index;
                        highest_importance = news.event[next_event_index].importance;
                       }
                    }
              }
           }
        }

      if(closest_event_index != -1)
        {
         last_event_index = closest_event_index;
         GlobalIndex = last_event_index;

         GlobalEventName = news.eventname[closest_event_index];
         
         StringSetLength(GlobalEventName, 52);
         
         GlobalEventTime = news.event[closest_event_index].time + OffSet;
         GlobalEventActualTime = news.event[closest_event_index].time;
         GlobalForecastValue = (double)news.event[closest_event_index].forecast_value / 1000000;
         GlobalPrevValue = (double)news.event[closest_event_index].prev_value / 1000000;
         GlobalActualValue = (double)news.event[closest_event_index].actual_value / 1000000;
         
         if(news.event[closest_event_index].unit == CALENDAR_UNIT_CURRENCY)
           {
            GlobalUnit = " "+valuta;
           }
         else
            if(news.event[closest_event_index].unit == CALENDAR_UNIT_PERCENT)
              {
               GlobalUnit = " %";
              }  
            else
              {
               GlobalUnit = "";
              } 
         
         if(news.event[closest_event_index].multiplier == CALENDAR_MULTIPLIER_NONE)
           {
            GlobalMultiplier = "";
           }
         else
            if(news.event[closest_event_index].multiplier == CALENDAR_MULTIPLIER_THOUSANDS)
              {
               GlobalMultiplier = " K";
              }  
            else
               if(news.event[closest_event_index].multiplier == CALENDAR_MULTIPLIER_MILLIONS)
                 {
                  GlobalMultiplier = " M";
                 }  
               else
                  if(news.event[closest_event_index].multiplier == CALENDAR_MULTIPLIER_BILLIONS)
                    {
                     GlobalMultiplier = " B";
                    }  
                  else
                     if(news.event[closest_event_index].multiplier == CALENDAR_MULTIPLIER_TRILLIONS)
                       {
                        GlobalMultiplier = " T";
                       }  
         
         if(news.event[closest_event_index].event_type == CALENDAR_TYPE_INDICATOR)
           {
            GlobalEventType = 1;
           }
         else
           {
            GlobalEventType = 0;
           }
          
         if(news.event[closest_event_index].importance == CALENDAR_IMPORTANCE_HIGH)
           {
            GlobalColor = Red;
            GlobalImportance = "Alta";
            GlobalEnumImportance = CALENDAR_IMPORTANCE_HIGH;
           }
         else
            if(news.event[closest_event_index].importance == CALENDAR_IMPORTANCE_MODERATE)
              {
               GlobalColor = Orange;
               GlobalImportance = "Media";
               GlobalEnumImportance = CALENDAR_IMPORTANCE_MODERATE;
              }
            else
               if(news.event[closest_event_index].importance == CALENDAR_IMPORTANCE_LOW)
                 {
                  GlobalColor = DarkGray;
                  GlobalImportance = "Bassa";
                  GlobalEnumImportance = CALENDAR_IMPORTANCE_LOW;
                 }

         Print("Prossima notizia di " + GlobalImportance + " importanza per ", currency, ":");
         Print("Nome: ", GlobalEventName);
         Print("Tempo: ", TimeToString(GlobalEventTime, TIME_DATE | TIME_MINUTES));
         Print("Valore Previsione: ", GlobalForecastValue,GlobalUnit,GlobalMultiplier);
         Print("Valore Precedente: ", GlobalPrevValue,GlobalUnit,GlobalMultiplier);
        }
      else
        {
         Print("Nessun evento rilevante trovato per ", currency);
        }
     }
   else
     {
      Print("Nessun evento disponibile per ", currency);
     }
  }

//News Panel//

void NewsPanel(int Max_News = 20, string currency = "USD", ENUM_COUNTRY_ID coun = USA, Importanza importance = Media, int offSet = 1)
  {
   int indexes = 0;

   if(ObjectFind(0, Prefix + "NewsBackground1") < 0 && ObjectFind(0, "Newstitle") >= 0)
     {
      int news_found = 0;
      int yOffset = 45;
      datetime event_time;
      double prev_value, forecast_value, actual_value;

      for(int index = news.GetNextNewsEvent(0, currency, importance, coun); index >= 0; index = news.GetNextNewsEvent(index + 1, currency, importance, coun))
         {
          if(news_found >= Max_News)
             break;

          indexes = index;
          event_time = news.event[index].time;
 
          if(event_time >= TimeCurrent() - PeriodSeconds(PERIOD_H12))
            {
             prev_value = (double)news.event[index].prev_value / 1000000;
             forecast_value = (double)news.event[index].forecast_value / 1000000;
             actual_value = (double)news.event[index].actual_value / 1000000;

             string event_name = news.eventname[indexes];
             string eventtime = TimeToString(event_time + offSet * PeriodSeconds(PERIOD_H1), TIME_DATE | TIME_MINUTES);
             string eventimportance = news.event[indexes].importance == CALENDAR_IMPORTANCE_LOW ? "Bassa" :
                                      news.event[indexes].importance == CALENDAR_IMPORTANCE_MODERATE ? "Media" :
                                      news.event[indexes].importance == CALENDAR_IMPORTANCE_HIGH ? "Alta" : "";
             string eventprevious = DoubleToString(prev_value, 1);
             string eventforecast = DoubleToString(forecast_value, 1);
             string eventactual = DoubleToString(actual_value, 1);
             string eventsector = EnumToString(news.event[indexes].sector);
                          
             if(prev_value == (double)LONG_MIN / 1000000)
                eventprevious = "ND";
             if(forecast_value == (double)LONG_MIN / 1000000)
                eventforecast = "ND";
             if(actual_value == (double)LONG_MIN / 1000000)
                eventactual = "ND";

             string label_news = Prefix + "Label" + IntegerToString(indexes);
             string label_name = Prefix + "Name" + IntegerToString(indexes);
             string label_importance = Prefix + "Importance" + IntegerToString(indexes);
             string label_time = Prefix + "Time" + IntegerToString(indexes);
             string label_previous = Prefix + "Previous" + IntegerToString(indexes);
             string label_forecast = Prefix + "Forecast" + IntegerToString(indexes);
             string label_actual = Prefix + "Actual" + IntegerToString(indexes);

             StringSetLength(event_name, 40);

             color clr = Black;
             
             if(eventimportance == "Bassa")
                clr = clrDarkGray;
             if(eventimportance == "Media")
                clr = clrOrange;
             if(eventimportance == "Alta")
                clr = clrRed;
                
             RectangleLabel(Prefix + "NewsBackground1", CORNER_LEFT_LOWER, 0, yOffset + 20, 860, yOffset + 20, Black, clrLightSkyBlue, BORDER_FLAT);
             RectangleLabel(Prefix + "NewsBackground2", CORNER_LEFT_LOWER, 5, yOffset + 15, 850, yOffset + 10, Black, White, BORDER_FLAT);
             Label(Prefix + "Nomes",CORNER_LEFT_LOWER,40,yOffset + 10,"Prossima Notizia",clrLightSkyBlue,"Impact",9);
             Label(Prefix + "Times",CORNER_LEFT_LOWER,320,yOffset + 10,"Data e Ora",clrLightSkyBlue,"Impact",9);
             Label(Prefix + "Importances",CORNER_LEFT_LOWER,435,yOffset + 10,"Importanza",clrLightSkyBlue,"Impact",9);
             Label(Prefix + "Previouss",CORNER_LEFT_LOWER,525,yOffset + 10,"Precedente",clrLightSkyBlue,"Impact",9);
             Label(Prefix + "Forecasts",CORNER_LEFT_LOWER,635,yOffset + 10,"Previsto",clrLightSkyBlue,"Impact",9);
             Label(Prefix + "Actuals",CORNER_LEFT_LOWER,735,yOffset + 10,"Attuale",clrLightSkyBlue,"Impact",9);
             RectangleLabel(label_news, CORNER_LEFT_LOWER, 5, yOffset - 10, 850, 30, Black, White, BORDER_FLAT);
             Label(label_name, CORNER_LEFT_LOWER, 20, yOffset - 15, event_name, Black, "Impact", 9);
             Label(label_time, CORNER_LEFT_LOWER, 300, yOffset - 15, eventtime, Black, "Impact", 9);
             Label(label_importance, CORNER_LEFT_LOWER, 450, yOffset - 15, eventimportance, clr, "Impact", 9);
             Label(label_previous, CORNER_LEFT_LOWER, 550, yOffset - 15, eventprevious, Black, "Impact", 9);
             Label(label_forecast, CORNER_LEFT_LOWER, 650, yOffset - 15, eventforecast, Black, "Impact", 9);
             Label(label_actual, CORNER_LEFT_LOWER, 750, yOffset - 15, eventactual, Black, "Impact", 9);
             Button(Prefix + "O/C", CORNER_LEFT_LOWER, 810, yOffset + 20, 50, 30, "Chiudi", Black, LightSkyBlue, "Impact");

             ObjectDelete(0,"NewsBackground");  
             ObjectDelete(0,"NewsBackGround");  
             ObjectDelete(0,"O/C");  
             ObjectDelete(0,"Newstitle");  
         
             yOffset += 30;
             news_found++;
            }
         }
     }
   else 
     {
      ObjectsDeleteAll(0, Prefix, -1, -1);

      RectangleLabel("NewsBackground", CORNER_LEFT_LOWER, 0, 50, 860, 50, Black, clrLightSkyBlue, BORDER_FLAT);
      RectangleLabel("NewsBackGround", CORNER_LEFT_LOWER, 5, 45, 850, 40, Black, White, BORDER_FLAT);
      Button("O/C", CORNER_LEFT_LOWER, 800, 40, 50, 30, "Apri", Black, LightSkyBlue, "Impact");
      Label("Newstitle", CORNER_LEFT_LOWER, 15, 40, "News Assistant : " + Currency, clrLightSkyBlue, "Impact", 15);
     }
  }

//Ordini Limite//

void OrdersType()
  {
   if(ObjectFind(0,"Limit") < 0)
     {
      Edit("Limit",CORNER_LEFT_UPPER,200,330,120,20," ",clrLightSkyBlue,"Impact",9);
      Button("Market",CORNER_LEFT_UPPER,110,330,70,20,"Limite",Black,White,"Impact");
     }
   else
      if(ObjectFind(0,"Limit") >= 0)
        {  
         ObjectDelete(0,"Limit");
         
         Button("Market",CORNER_LEFT_UPPER,110,330,70,20,"Mercato",Black,White,"Impact");      
        }
  }

//Trade Panel//

void TradePanel()
  {   
   if(ObjectFind(0,"BE") < 0)   
     { 
      ObjectDelete(0,"Sfondobase");
      ObjectDelete(0,"Sfondobase1");
      ObjectDelete(0,"Trade Assistant");
      ObjectDelete(0,"A/C");

      RectangleLabel("Sfondo",CORNER_LEFT_UPPER,0,0,400,570,Black,LightSkyBlue,BORDER_FLAT);
      RectangleLabel("Sfondo2",CORNER_LEFT_UPPER,5, 5,390,560,Black,White,BORDER_FLAT);

      Label("Trade Assistant",CORNER_LEFT_UPPER, 15, 10,"Trade Assistant : "+Symbol(),LightSkyBlue,"Impact",15);
      
      Button("A/C",CORNER_LEFT_UPPER,340,10,50,30,"Chiudi",Black,LightSkyBlue,"Impact");
                  
      Label("Trend1",CORNER_LEFT_UPPER,15, 60,"Trend "+TimeFrameToString(Timeframe)+" : ND",Black,"Impact",9);
      Label("P/V",CORNER_LEFT_UPPER,15, 95,"Correlazione Prezzo / Volumi"+tipovolume+": ND",Black,"Impact",9);
      Label("Price",CORNER_LEFT_UPPER,15, 130,"Condizione Prezzo / VWAP :  ND",Black,"Impact",9);
      
      RectangleLabel("NewsBack",CORNER_LEFT_UPPER,5, 165,390,120,Black,Beige,BORDER_FLAT);
      Label("EventName",CORNER_LEFT_UPPER,15, 170,"Prossima Notizia Non Disponibile",Black,"Impact",9);
      Label("EventTime",CORNER_LEFT_UPPER,15, 200,"Data e Ora : ND",Black,"Impact",9);
      Label("EventImportance",CORNER_LEFT_UPPER,220, 200,"Importanza : ND",Black,"Impact",9);
      Label("EventForecast",CORNER_LEFT_UPPER,15, 230,"Previsto : ND",Black,"Impact",9);
      Label("EventPrevValue",CORNER_LEFT_UPPER,220, 230,"Precedente : ND",Black,"Impact",9);       
      Label("EventValue",CORNER_LEFT_UPPER,15, 260,"Attuale : ND",Black,"Impact",9);       
         
      RectangleLabel("AskBack",CORNER_LEFT_UPPER,5, 284,130,40,PaleGreen,PaleGreen,BORDER_FLAT);
      RectangleLabel("SpreadBack",CORNER_LEFT_UPPER,134, 284,131,40,LightBlue,LightBlue,BORDER_FLAT);
      RectangleLabel("BidBack",CORNER_LEFT_UPPER,264, 284,131,40,IndianRed,IndianRed,BORDER_FLAT);
      Label("Ask",CORNER_LEFT_UPPER,15, 293,"Ask : ND",Black,"Impact",9);
      Label("Spread",CORNER_LEFT_UPPER,145,293,"Spread : ND",Black,"Impact",9);
      Label("Bid",CORNER_LEFT_UPPER,270, 293,"Bid : ND",Black,"Impact",9);
      
      Label("Type",CORNER_LEFT_UPPER,15, 330,"Tipo Di Ordine : ",Black,"Impact",9);
      Button("Market",CORNER_LEFT_UPPER,110,330,70,20,"Mercato",Black,White,"Impact");
         
      Label("Lots",CORNER_LEFT_UPPER,15, 360,"Rischio Per Trade % : ",Blue,"Impact",9);
      Edit("RiskPerTrade",CORNER_LEFT_UPPER,150, 360,60,20," ",LightSkyBlue,"Impact",9);  
      
      Label("SetSL",CORNER_LEFT_UPPER,15, 390,"Prezzo Stop Loss : ",Red,"Impact",9);
      Edit("SL",CORNER_LEFT_UPPER,130, 390,120,20," ",LightSkyBlue,"Impact",9);
      
      Label("SetTP",CORNER_LEFT_UPPER,15, 420,"Prezzo Take Profit : ",Green,"Impact",9);
      Edit("TP",CORNER_LEFT_UPPER,135,420,120,20," ",LightSkyBlue,"Impact",9);
      
      Button("Open Buy",CORNER_LEFT_UPPER,15, 450,120,50,"Apri Buy",Black,LightSkyBlue,"Impact");
      Button("Open Sell",CORNER_LEFT_UPPER,265, 450,120,50,"Apri Sell",Black,LightSkyBlue,"Impact");
      Button("Close Buy",CORNER_LEFT_UPPER,15, 505,120,50,"Chiudi Buy",Black,LightSkyBlue,"Impact");
      Button("Close Sell",CORNER_LEFT_UPPER,265, 505,120,50,"Chiudi Sell",Black,LightSkyBlue,"Impact");
      Button("BE",CORNER_LEFT_UPPER,140, 450,120,105,"Break Even",Black,LightSkyBlue,"Impact");
     }
   else
      if(BEexist >= 0)
        {      
         ObjectDelete(0,"Sfondo");
         ObjectDelete(0,"Sfondo2");
         ObjectDelete(0,"Trend1");
         ObjectDelete(0,"P/V");
         ObjectDelete(0,"Price");
         ObjectDelete(0,"NewsBack");
         ObjectDelete(0,"EventName");
         ObjectDelete(0,"EventTime");
         ObjectDelete(0,"EventImportance");
         ObjectDelete(0,"EventForecast");
         ObjectDelete(0,"EventPrevValue");
         ObjectDelete(0,"EventValue");
         ObjectDelete(0,"AskBack");
         ObjectDelete(0,"SpreadBack");
         ObjectDelete(0,"BidBack");
         ObjectDelete(0,"Ask");
         ObjectDelete(0,"Spread");
         ObjectDelete(0,"Bid");
         ObjectDelete(0,"Lots");
         ObjectDelete(0,"RiskPerTrade");
         ObjectDelete(0,"SetSL");
         ObjectDelete(0,"SL");
         ObjectDelete(0,"SetTP");
         ObjectDelete(0,"TP");
         ObjectDelete(0,"Open Buy");
         ObjectDelete(0,"Open Sell");
         ObjectDelete(0,"Close Buy");
         ObjectDelete(0,"Close Sell");
         ObjectDelete(0,"BE");
         ObjectDelete(0,"Trade Assistant");
         ObjectDelete(0,"A/C");
         ObjectDelete(0,"Type");
         ObjectDelete(0,"Market");
         ObjectDelete(0,"Limit");
         
         RectangleLabel("Sfondobase",CORNER_LEFT_UPPER,0,0,400,50,Black,LightSkyBlue,BORDER_FLAT);
         RectangleLabel("Sfondobase1",CORNER_LEFT_UPPER,5, 5,390,40,Black,White,BORDER_FLAT);
    
         Label("Trade Assistant",CORNER_LEFT_UPPER, 15, 10,"Trade Assistant : "+Symbol(),LightSkyBlue,"Impact",15);
         
         Button("A/C",CORNER_LEFT_UPPER,340,10,50,30,"Apri",Black,LightSkyBlue,"Impact");         
        }  
  }

//+------------------------------------------------------------------+
//| Expert Variables                                                 |
//+------------------------------------------------------------------+

input ENUM_TIMEFRAMES TimeframeVolume = PERIOD_M15;//TimeFrame di Calcolo per i Volumi
input ENUM_TIMEFRAMES Timeframe = PERIOD_W1;//TimeFrame di Calcolo per il Trend
input double SecondDev = 1.5;//Deviazione Bande VWAP
input ENUM_CURRENCY Curren = USD;//Valuta Da Analizzare Per Le News
input Importanza Imp = Media;//Importanza Minima News da Analizzare
input int TimeOffSet = -1;//Offset in Ore dell'orario del Broker

string commento = "Trade Assistant", trend = "", divergence = "", Condition = "", GlobalEventName, GlobalImportance, GlobalUnit, GlobalMultiplier,Currency, valuta, tipovolume, Prefix = "NewsPanel_", TradeInitObjects[] = {"Trade Assistant", "BE"},
       NewsInitObjects[] = {"Newstitle" ,"O/C"}; 

color GlobalColor = Black;

datetime GlobalEventTime, last_news_event_time = 0, news_dates[], GlobalEventActualTime;

int VWAP, Volume, last_event_index = 0, magicNumber = 322974,timezone_offset = TimeOffSet * PeriodSeconds(PERIOD_H1), GlobalEventType = -1, GlobalIndex, MaxNews = 10;

static int TradeInitPanel = -1, BEexist = -1, NewsInitPanel = -1, Limitexist = -1;

double UpBandBuffer[], LowbandBuffer[], MidHighBandBuffer[], MidLowBandBuffer[], VolumesBuffer[],
       UpBand, LowBand, MidLowBand, MidUpBand, Volumes, VolumesPrevious, AvaragePrice, Lots, Take, Stop, Risk, Price, 
       GlobalActualValue = (double)LONG_MIN/1000000, GlobalForecastValue = (double)LONG_MIN/1000000, GlobalPrevValue = (double)LONG_MIN/1000000;

ENUM_COUNTRY_ID Country;

ENUM_CALENDAR_EVENT_IMPORTANCE GlobalEnumImportance;

ENUM_APPLIED_VOLUME Vol;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+

int OnInit()
  {  
   //Currency//
   
   switch(Curren)
     {
      case USD : Currency = "USD"; Country = USA; valuta = "$"; break;
      case EUR : Currency = "EUR"; Country = EU; valuta = "€"; break;
      case GBP : Currency = "GBP"; Country = UK; valuta = "£"; break;
      case AUD : Currency = "AUD"; Country = Australia; valuta = "$"; break;
      case CAD : Currency = "CAD"; Country = Canada; valuta = "$"; break;      
      case CHF : Currency = "CHF"; Country = Switzerland; valuta = "Fr"; break;
      case CNY : Currency = "CNY"; Country = China; valuta = "¥"; break;
      case JPY : Currency = "JPY"; Country = Japan; valuta = "¥"; break;
      case NZD : Currency = "NZD"; Country = NewZealand; valuta = "$"; break;
     }  
     
   //News//
   
   news.update();
      
   GetNextNews(Currency,timezone_offset,Country,true);
   
   //Grafic Trade Panel//

   if(TradeInitPanel < 0)
     {
     for(int i = 0; i < ArraySize(TradeInitObjects); i++)
        {
         if(ObjectFind(0, TradeInitObjects[i]) >= 0)
           {
            TradeInitPanel = 1;
            break;
           }
        }   
     }
     
   if(TradeInitPanel < 0)
     {  
      RectangleLabel("Sfondobase",CORNER_LEFT_UPPER,0,0,400,50,Black,LightSkyBlue,BORDER_FLAT);
      RectangleLabel("Sfondobase1",CORNER_LEFT_UPPER,5, 5,390,40,Black,White,BORDER_FLAT);      
      Button("A/C",CORNER_LEFT_UPPER,340,10,50,30,"Apri",Black,LightSkyBlue,"Impact");
      Label("Trade Assistant",CORNER_LEFT_UPPER, 15, 10,"Trade Assistant : "+Symbol(),LightSkyBlue,"Impact",15);
     }

   //Grafic News Panel//

   if(NewsInitPanel < 0)
     {
     for(int i = 0; i < ArraySize(NewsInitObjects); i++)
        {
         if(ObjectFind(0, NewsInitObjects[i]) >= 0)
           {
            NewsInitPanel = 1;
            break;
           }
        }   
     }

   if(NewsInitPanel < 0)
     {
      RectangleLabel("NewsBackground", CORNER_LEFT_LOWER, 0, 50, 860, 50, Black, clrLightSkyBlue, BORDER_FLAT);
      RectangleLabel("NewsBackGround", CORNER_LEFT_LOWER, 5, 45, 850, 40, Black, White, BORDER_FLAT);    
      Button("O/C",CORNER_LEFT_LOWER,800,40,50,30,"Apri",Black,LightSkyBlue,"Impact");      
      Label("Newstitle",CORNER_LEFT_LOWER, 15, 40,"News Assistant : "+Currency,clrLightSkyBlue,"Impact",15);
     }   
            
   //Volumi//
   
   if(SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_REAL) > 0) 
     {
      Vol = VOLUME_REAL;
      tipovolume = " Reali ";
      Print("Utilizzo volumi reali.");
     }
   else
     {
      Vol = VOLUME_TICK;
      tipovolume = " Tick ";
      Print("Volumi reali non disponibili. Utilizzo volumi tick.");
     }   
      
   //Indicators//
   
   VWAP = iCustom(Symbol(),PERIOD_CURRENT,"VWAP",SecondDev,Vol);
   Volume = iOBV(Symbol(),TimeframeVolume,Vol);
        
   //Errors//
   
   if(VWAP == INVALID_HANDLE || Volume == INVALID_HANDLE)
     {
      Print("Indicator Handle failed");
      return(INIT_FAILED);
     }  
           
   return(INIT_SUCCEEDED);
  }
  
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+

void OnTick()
  {           
   //Grafic Trade Panel//

   if(TradeInitPanel == -1)
     {
     for(int i = 0; i < ArraySize(TradeInitObjects); i++)
        {
         if(ObjectFind(0, TradeInitObjects[i]) >= 0)
           {
            TradeInitPanel = 1;
            break;
           }
        }   
     }
     
   if(TradeInitPanel < 0)
     {  
      RectangleLabel("Sfondobase",CORNER_LEFT_UPPER,0,0,400,50,Black,LightSkyBlue,BORDER_FLAT);
      RectangleLabel("Sfondobase1",CORNER_LEFT_UPPER,5, 5,390,40,Black,White,BORDER_FLAT);      
      Button("A/C",CORNER_LEFT_UPPER,340,10,50,30,"Apri",Black,LightSkyBlue,"Impact");
      Label("Trade Assistant",CORNER_LEFT_UPPER, 15, 10,"Trade Assistant : "+Symbol(),LightSkyBlue,"Impact",15);
     }

   //Grafic News Panel//

   if(NewsInitPanel == -1)
     {
     for(int i = 0; i < ArraySize(NewsInitObjects); i++)
        {
         if(ObjectFind(0, NewsInitObjects[i]) >= 0)
           {
            NewsInitPanel = 1;
            break;
           }
        }   
     }

   if(NewsInitPanel < 0)
     {
      RectangleLabel("NewsBackground", CORNER_LEFT_LOWER, 0, 50, 860, 50, Black, clrLightSkyBlue, BORDER_FLAT);
      RectangleLabel("NewsBackGround", CORNER_LEFT_LOWER, 5, 45, 850, 40, Black, White, BORDER_FLAT);    
      Button("O/C",CORNER_LEFT_LOWER,800,40,50,30,"Apri",Black,LightSkyBlue,"Impact");      
      Label("Newstitle",CORNER_LEFT_LOWER, 15, 40,"News Assistant : "+Currency,clrLightSkyBlue,"Impact",15);
     }   
      
   //News//
      
   if(BEexist < 0 || ObjectFind(0, "BE") < 0)
     {
      BEexist = ObjectFind(0,"BE");
     }
         
   if(BEexist >= 0) 
     {      
      timezone_offset = TimeOffSet * PeriodSeconds(PERIOD_H1);
   
      if(TimeCurrent() >= GlobalEventActualTime + PeriodSeconds(PERIOD_M10)) 
        {
         news.update();
         GetNextNews(Currency, timezone_offset, Country, false);
         GlobalActualValue = (double)LONG_MIN / 1000000; 
        }
   
      if(MQLInfoInteger(MQL_TESTER))
        {
         if(GlobalIndex >= 0 && TimeCurrent() >= GlobalEventActualTime && GlobalEventType == 1) 
           { 
            if(news.event[GlobalIndex].time == GlobalEventActualTime &&
               news.event[GlobalIndex].actual_value != LONG_MIN)
              {             
               GlobalActualValue = (double)news.event[GlobalIndex].actual_value / 1000000;
              }
           }
        }
      else
        {
         if(GlobalIndex >= 0 && TimeCurrent() >= GlobalEventActualTime && GlobalEventType == 1 && GlobalActualValue == (double)LONG_MIN/1000000) 
           { 
            news.update(0);
            
            GetNextNews(Currency,timezone_offset,Country,false);
           }
        }      
      if(GlobalActualValue == (double)LONG_MIN/1000000 && GlobalEventType == 1)
        {
         Label("EventValue",CORNER_LEFT_UPPER,15, 260,"Attuale : Non Ancora Rilasciato",Black,"Impact",9);       
        }
        else 
           if(GlobalActualValue != (double)LONG_MIN/1000000 && GlobalEventType == 1)
             {
              if(GlobalActualValue > GlobalForecastValue)
                {
                 Label("EventValue",CORNER_LEFT_UPPER,15, 260,"Attuale : "+DoubleToString(GlobalActualValue,2)+GlobalUnit+GlobalMultiplier,Green,"Impact",9);       
                }
              else
                 if(GlobalActualValue < GlobalForecastValue)
                   {
                    Label("EventValue",CORNER_LEFT_UPPER,15, 260,"Attuale : "+DoubleToString(GlobalActualValue,2)+GlobalUnit+GlobalMultiplier,Red,"Impact",9);                     
                   }  
                 else 
                    if(GlobalActualValue == GlobalForecastValue)
                      {
                       Label("EventValue",CORNER_LEFT_UPPER,15, 260,"Attuale : "+DoubleToString(GlobalActualValue,2)+GlobalUnit+GlobalMultiplier,Black,"Impact",9);
                      }  
           }  
        
      if(GlobalForecastValue == (double)LONG_MIN/1000000)
        {
         Label("EventForecast",CORNER_LEFT_UPPER,15, 230,"Previsto : ND",Black,"Impact",9);
        }
        else
           {
            if(GlobalForecastValue > GlobalPrevValue && GlobalEventType == 1)
              {
               Label("EventForecast",CORNER_LEFT_UPPER,15, 230,"Previsto : "+DoubleToString(GlobalForecastValue,2)+GlobalUnit+GlobalMultiplier,Green,"Impact",9);
               Label("EventPrevValue",CORNER_LEFT_UPPER,220, 230,"Precedente : "+DoubleToString(GlobalPrevValue,2)+GlobalUnit+GlobalMultiplier,Red,"Impact",9);  
              }
            else
               if(GlobalForecastValue < GlobalPrevValue && GlobalEventType == 1)
                 {
                  Label("EventForecast",CORNER_LEFT_UPPER,15, 230,"Previsto : "+DoubleToString(GlobalForecastValue,2)+GlobalUnit+GlobalMultiplier,Red,"Impact",9);
                  Label("EventPrevValue",CORNER_LEFT_UPPER,220, 230,"Precedente : "+DoubleToString(GlobalPrevValue,2)+GlobalUnit+GlobalMultiplier,Green,"Impact",9);  
                 }  
               else
                  if(GlobalForecastValue == GlobalPrevValue && GlobalEventType == 1)
                    {
                     Label("EventForecast",CORNER_LEFT_UPPER,15, 230,"Previsto : "+DoubleToString(GlobalForecastValue,2)+GlobalUnit+GlobalMultiplier,Black,"Impact",9);
                     Label("EventPrevValue",CORNER_LEFT_UPPER,220,230,"Precedente : "+DoubleToString(GlobalPrevValue,2)+GlobalUnit+GlobalMultiplier,Black,"Impact",9);  
                    } 
           }  
        
      if(GlobalPrevValue == (double)LONG_MIN/1000000)
        {
         Label("EventPrevValue",CORNER_LEFT_UPPER,220, 230,"Precedente : ND",Black,"Impact",9);       
        }
      
      if(GlobalEventType == 0)
        {
         Label("EventValue",CORNER_LEFT_UPPER,15, 260,"Attuale : ND",Black,"Impact",9);       
         Label("EventForecast",CORNER_LEFT_UPPER,15, 230,"Previsto : ND",Black,"Impact",9);
         Label("EventPrevValue",CORNER_LEFT_UPPER,220, 230,"Precedente : ND",Black,"Impact",9);       
        }
       
      Label("EventName",CORNER_LEFT_UPPER,15,170,GlobalEventName,Black,"Impact",9);
      Label("EventTime",CORNER_LEFT_UPPER,15,200,"Data e Ora : "+TimeToString(GlobalEventTime),Black,"Impact",9);
      Label("EventImportance",CORNER_LEFT_UPPER,220, 200,"Importanza : "+GlobalImportance,GlobalColor,"Impact",9);
      
      //Prezzo//
      
      AvaragePrice = Ask(Symbol()) - ((Ask(Symbol()) - Bid(Symbol()))/2);
      
      Label("Ask",CORNER_LEFT_UPPER,15,293,"Ask : "+DoubleToString(Ask(Symbol()),Digit(Symbol())),Black,"Impact",9);
      Label("Spread",CORNER_LEFT_UPPER,145,293,"Spread : "+DoubleToString((Ask(Symbol())-Bid(Symbol())),Digit(Symbol())),Black,"Impact",9);
      Label("Bid",CORNER_LEFT_UPPER,270,293,"Bid : "+DoubleToString(Bid(Symbol()),Digit(Symbol())),Black,"Impact",9);
        
      //Structure Trend//
   
      double highcurrent = HighestHigh(Symbol(),Timeframe,0);
      double highprevious = HighestHigh(Symbol(),Timeframe,1);
     
      double lowcurrent = LowestLow(Symbol(),Timeframe,0);
      double lowprevious = LowestLow(Symbol(),Timeframe,1);
      
      double closeprevious = Close(Symbol(),Timeframe,1);

      trend = (highcurrent > highprevious && lowcurrent > lowprevious && highcurrent > closeprevious) ? "Rialzista" : 
              (highcurrent < highprevious && lowcurrent > lowprevious && closeprevious > lowcurrent && closeprevious < highcurrent) ? "Consolidamento" :
              (highcurrent > highprevious && lowcurrent < lowprevious) ? "Consolidamento Volatile" :
              (highcurrent < highprevious && lowcurrent < lowprevious && lowcurrent < closeprevious) ? "Ribassista" : "";
                   
      if(trend == "Rialzista")
        {
         Label("Trend1",CORNER_LEFT_UPPER,15, 60,"Trend "+TimeFrameToString(Timeframe)+" : "+trend,Green,"Impact",9);
        }
      else    
        if(trend == "Ribassista")
          {
           Label("Trend1",CORNER_LEFT_UPPER,15, 60,"Trend "+TimeFrameToString(Timeframe)+" : "+trend,Red,"Impact",9);
          }
         else
           if(trend == "Consolidamento")
             {
              Label("Trend1",CORNER_LEFT_UPPER,15, 60,"Trend "+TimeFrameToString(Timeframe)+" : "+trend,Black,"Impact",9);
             }         
            else
              if(trend == "Consolidamento Volatile")
                {
                 Label("Trend1",CORNER_LEFT_UPPER,15, 60,"Trend "+TimeFrameToString(Timeframe)+" : "+trend,Black,"Impact",9);
                } 
        
      //CVD//
      
      CopyBuffer(Volume,0,0,3,VolumesBuffer);
      
      Volumes = NormalizeDouble(VolumesBuffer[1],Digit(Symbol()));
      VolumesPrevious = NormalizeDouble(VolumesBuffer[2],Digit(Symbol()));
         
      divergence = ((Close(Symbol(),TimeframeVolume,1) >= Close(Symbol(),TimeframeVolume,2) && Volumes >= VolumesPrevious) ||
                    (Close(Symbol(),TimeframeVolume,1) <= Close(Symbol(),TimeframeVolume,2) && Volumes <= VolumesPrevious)) ? "Convergente" :
                   ((Close(Symbol(),TimeframeVolume,1) > Close(Symbol(),TimeframeVolume,2) && Volumes < VolumesPrevious) ||
                    (Close(Symbol(),TimeframeVolume,1) < Close(Symbol(),TimeframeVolume,2) && Volumes > VolumesPrevious)) ? "Divergente" : ""; 
      
      Label("P/V",CORNER_LEFT_UPPER,15, 95,"Correlazione Prezzo / Volumi"+tipovolume+": "+divergence,Black,"Impact",9);
        
      //VWAP//
         
      CopyBuffer(VWAP,1,0,1,MidLowBandBuffer);
      CopyBuffer(VWAP,2,0,1,MidHighBandBuffer);
      CopyBuffer(VWAP,3,0,1,LowbandBuffer);
      CopyBuffer(VWAP,4,0,1,UpBandBuffer);
      
      MidLowBand = NormalizeDouble(MidLowBandBuffer[0],Digit(Symbol()));
      MidUpBand = NormalizeDouble(MidHighBandBuffer[0],Digit(Symbol()));
      LowBand = NormalizeDouble(LowbandBuffer[0],Digit(Symbol()));
      UpBand = NormalizeDouble(UpBandBuffer[0],Digit(Symbol())); 
      
      Condition = (Ask(Symbol()) > UpBand) ? "Estremamente Sovra-Prezzato" :
                  (Ask(Symbol()) < LowBand) ? "Estremamente Scontato" :
                  (Ask(Symbol()) > MidUpBand && Ask(Symbol()) < UpBand) ? "Sovra-Prezzato" :
                  (Ask(Symbol()) < MidLowBand && Ask(Symbol()) > LowBand) ? "Scontato" :               
                  (Ask(Symbol()) > LowBand && Ask(Symbol()) < UpBand) ? "Fair Value" : "";
   
      if(Condition == "Estremamente Sovra-Prezzato" || Condition == "Estremamente Scontato")
        {
         Label("Price",CORNER_LEFT_UPPER,15,130,"Condizione Prezzo / VWAP : "+Condition,Red,"Impact",9);            
        }
       else
         {
          Label("Price",CORNER_LEFT_UPPER,15,130,"Condizione Prezzo / VWAP : "+Condition,Black,"Impact",9);
         } 
     }     
          
   //Lots//
   
   if(Limitexist == -1)
     {
      Limitexist = ObjectFind(0, "Limit");
     }
   
   if(Limitexist < 0)
     { 
      if(Vol == VOLUME_REAL)
        {
         if(Stop != 0.0)
           {
            if(Stop > Bid(Symbol()))
              {
               Lots = CalculateContractSize(Symbol(), Stop - Bid(Symbol()), Risk);     
              }
             else 
                if(Stop < Ask(Symbol()))
                  {
                   Lots = CalculateContractSize(Symbol(), Ask(Symbol()) - Stop, Risk);          
                  } 
           }
         else
           {
            Lots = 0.0;
           }
        }          
      else
         if(Vol == VOLUME_TICK)
           {
            if(Stop != 0.0)
              {
               if(Stop > Bid(Symbol()))
                 {
                  Lots = CalculateLotSize(Symbol(), Stop - Bid(Symbol()), Risk);     
                 }
                else 
                   if(Stop < Ask(Symbol()))
                     {
                      Lots = CalculateLotSize(Symbol(), Ask(Symbol()) - Stop, Risk);          
                     } 
              }
            else
              {
               Lots = 0.0;
              }
           }
     }   
   else     
      if(Limitexist >= 0)
        { 
         if(Vol == VOLUME_REAL)
           {
            if(Stop != 0.0)
              {
               if(Stop > Price)
                 {
                  Lots = CalculateContractSize(Symbol(), Stop - Price, Risk);     
                 }
                else 
                   if(Stop < Price)
                     {
                      Lots = CalculateContractSize(Symbol(), Price - Stop, Risk);          
                     } 
              }
            else
              {
               Lots = 0.0;
              }
           }          
         else
            if(Vol == VOLUME_TICK)
              {
               if(Stop != 0.0)
                 {
                  if(Stop > Price)
                    {
                     Lots = CalculateLotSize(Symbol(), Stop - Price, Risk);     
                    }
                   else 
                      if(Stop < Price)
                        {
                         Lots = CalculateLotSize(Symbol(), Price - Stop, Risk);          
                        } 
                 }
               else
                 {
                  Lots = 0.0;
                 }
              }
         }     

   // TP & SL per ordini limite
   
   if(CounterBuyLimit(Symbol(), magicNumber) > 0)
     {
      for(int w = (OrdersTotal() - 1); w >= 0; w--)
         {
          ulong Ticket = OrderGetTicket(w);
          long OrderMagicNumber = OrderGetInteger(ORDER_MAGIC);
          string OrderComment = OrderGetString(ORDER_COMMENT);
          string OrderSymbol = OrderGetString(ORDER_SYMBOL);
          long OrderType = OrderGetInteger(ORDER_TYPE);       
          double OrderTP = OrderGetDouble(ORDER_TP);       
          double OrderSL = OrderGetDouble(ORDER_SL);       
         
          if(OrderSymbol == Symbol() && OrderMagicNumber == magicNumber && OrderType == ORDER_TYPE_BUY_LIMIT && OrderComment == commento)
            {             
             if(OrderSL == 0.0)
               {
                SetStopLossPriceBuyLimit(Symbol(), magicNumber, Stop, commento);        
               }
            
             if(OrderTP == 0.0)
               {
                SetTakeProfitPriceBuyLimit(Symbol(), magicNumber, Take, commento);
               } 
             break;                 
            }
        }          
     }
   
   if(CounterSellLimit(Symbol(), magicNumber) > 0)
     {
      for(int w = (OrdersTotal() - 1); w >= 0; w--)
         {
          ulong Ticket = OrderGetTicket(w);
          long OrderMagicNumber = OrderGetInteger(ORDER_MAGIC);
          string OrderComment = OrderGetString(ORDER_COMMENT);
          string OrderSymbol = OrderGetString(ORDER_SYMBOL);
          long OrderType = OrderGetInteger(ORDER_TYPE);       
          double OrderTP = OrderGetDouble(ORDER_TP);       
          double OrderSL = OrderGetDouble(ORDER_SL);       
         
          if(OrderSymbol == Symbol() && OrderMagicNumber == magicNumber && OrderType == ORDER_TYPE_SELL_LIMIT && OrderComment == commento)
            {
             if(OrderSL == 0.0)
               {
                SetStopLossPriceSellLimit(Symbol(), magicNumber, Stop, commento);   
               }
            
             if(OrderTP == 0.0)
               {
                SetTakeProfitPriceSellLimit(Symbol(), magicNumber, Take, commento);             
               }
             break;                 
            }
         }       
     }  
   
   //TP & SL//
   
   if(CounterBuy(Symbol(),magicNumber) > 0)
     {
      for(int w = (PositionsTotal() - 1); w >= 0; w--)
         {
          ulong Ticket = PositionGetTicket(w);
          long PositionMagicNumber = PositionGetInteger(POSITION_MAGIC);
          string PositionComment = PositionGetString(POSITION_COMMENT);
          string PositionSymbol = PositionGetString(POSITION_SYMBOL);
          long PositionDirection = PositionGetInteger(POSITION_TYPE);       
          double PositionTP = PositionGetDouble(POSITION_TP);       
          double PositionSL = PositionGetDouble(POSITION_SL);       
        
          if(PositionSymbol == Symbol() && PositionMagicNumber == magicNumber && PositionDirection == POSITION_TYPE_BUY && PositionComment == commento)     
            {             
             if(PositionSL == 0.0)
               {
                SetStopLossPriceBuy(Symbol(),magicNumber,Stop,commento);        
               }
             
             if(PositionTP == 0.0)
               {
                SetTakeProfitPriceBuy(Symbol(),magicNumber,Take,commento);
               }
             break;                 
            }
         }       
     }   
         
   if(CounterSell(Symbol(),magicNumber) > 0)
     {
      for(int w = (PositionsTotal() - 1); w >= 0; w--)
         {
          ulong Ticket = PositionGetTicket(w);
          long PositionMagicNumber = PositionGetInteger(POSITION_MAGIC);
          string PositionComment = PositionGetString(POSITION_COMMENT);
          string PositionSymbol = PositionGetString(POSITION_SYMBOL);
          long PositionDirection = PositionGetInteger(POSITION_TYPE);       
          double PositionTP = PositionGetDouble(POSITION_TP);       
          double PositionSL = PositionGetDouble(POSITION_SL);       
        
          if(PositionSymbol == Symbol() && PositionMagicNumber == magicNumber && PositionDirection == POSITION_TYPE_SELL && PositionComment == commento)     
            {
             if(PositionSL == 0.0)
               {
                SetStopLossPriceSell(Symbol(),magicNumber,Stop,commento);   
               }
             
             if(PositionTP == 0.0)
               {
                SetTakeProfitPriceSell(Symbol(),magicNumber,Take,commento);             
               }
             break;                 
            }
         }       
     }
  }     

//+------------------------------------------------------------------+
//| Expert Chart function                                            |
//+------------------------------------------------------------------+

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_ENDEDIT)
     {
      if(sparam == "RiskPerTrade")
        {
         Risk = NormalizeDouble(StringToDouble(ObjectGetString(0,"RiskPerTrade",OBJPROP_TEXT)),2);
         Print("Il Rischio Per Trade % é settato a : "+DoubleToString(Risk,2));
        }
      if(sparam == "TP")
        {
         Take = NormalizeDouble(StringToDouble(ObjectGetString(0,"TP",OBJPROP_TEXT)),Digit(Symbol()));
         Print("Il Take Profit é settato a : "+DoubleToString(Take,Digit(Symbol())));
        }
      if(sparam == "SL")
        {
         Stop = NormalizeDouble(StringToDouble(ObjectGetString(0,"SL",OBJPROP_TEXT)),Digit(Symbol()));
         Print("Il Stop Loss é settato a : "+DoubleToString(Stop,Digit(Symbol())));
        }
      if(sparam == "Limit")
        {
         Price = NormalizeDouble(StringToDouble(ObjectGetString(0,"Limit",OBJPROP_TEXT)),Digit(Symbol()));
         Print("Il Prezzo di Entrata é settato a : "+DoubleToString(Price,Digit(Symbol())));
        }        
     }   
   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      if(sparam == "Market")
        {
         OrdersType();
        }
      if(sparam == "A/C")
        {
         TradePanel();  
        }
      if(sparam == "O/C" || sparam == Prefix + "O/C" )
        {
         NewsPanel(MaxNews,Currency,Country,Imp,TimeOffSet);
        }  
      if(sparam == "Open Buy" && Lots != 0.0 && Limitexist < 0)
        {
         if(Stop < Ask(Symbol()) && (Take == 0.0 || Take > Ask(Symbol())))
           {
            SendBuy(Lots,Symbol(),commento,magicNumber);
            SetTakeProfitPriceBuy(Symbol(),magicNumber,Take,commento);
            SetStopLossPriceBuy(Symbol(),magicNumber,Stop,commento);             
           }
         else
           {
            Alert("Incorrect parameters to Open a Buy Order");
           }              
        }
      if(sparam == "Open Sell"  && Lots != 0.0 && Limitexist < 0)
        {
         if(Stop > Ask(Symbol()) && (Take == 0.0 || Take < Ask(Symbol())))
           {
            SendSell(Lots,Symbol(),commento,magicNumber);
            SetTakeProfitPriceSell(Symbol(),magicNumber,Take,commento);
            SetStopLossPriceSell(Symbol(),magicNumber,Stop,commento);  
           }
          else
           {
            Alert("Incorrect parameters to Open a Sell Order");
           }                
        }
      if(sparam == "Open Buy" && Lots != 0.0 && Limitexist >= 0)
        {
         if(Stop < Price && (Take == 0.0 || Take > Price))
           {
            SendBuyLimit(Price,Lots,Symbol(),commento,magicNumber);
            SetTakeProfitPriceBuyLimit(Symbol(),magicNumber,Take,commento);
            SetStopLossPriceBuyLimit(Symbol(),magicNumber,Stop,commento);             
           }
         else
           {
            Alert("Incorrect parameters to Open a Buy Limit Order");
           }              
        }
      if(sparam == "Open Sell"  && Lots != 0.0 && Limitexist >= 0)
        {
         if(Stop > Price && (Take == 0.0 || Take < Price))
           {
            SendSellLimit(Price,Lots,Symbol(),commento,magicNumber);
            SetTakeProfitPriceSellLimit(Symbol(),magicNumber,Take,commento);
            SetStopLossPriceSellLimit(Symbol(),magicNumber,Stop,commento);  
           }
          else
           {
            Alert("Incorrect parameters to Open a Sell Limit Order");
           }                
        }
      if(sparam == "Close Buy")
        {
         CloseAllBuy(Symbol(),magicNumber);
        }
      if(sparam == "Close Sell")
        {
         CloseAllSell(Symbol(),magicNumber);
        }
      if(sparam == "BE")
        {
         BreakEven(Symbol(),magicNumber,commento);
        }  
     }
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+

void OnDeinit(const int reason)
  {
   if(reason != 3)
     {
      ObjectsDeleteAll(0,-1,102);
      ObjectsDeleteAll(0,-1,103);
      ObjectsDeleteAll(0,-1,107);
      ObjectsDeleteAll(0,-1,110);
     } 
  }

//+------------------------------------------------------------------+
