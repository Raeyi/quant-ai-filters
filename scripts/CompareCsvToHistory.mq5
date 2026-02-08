//+------------------------------------------------------------------+
//| CompareCsvToHistory.mq5                                          |
//| Compare external CSV bars with MT5 history bars                  |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

input string CsvPath = "E:\\mt5测试数据\\mt5\\XAUUSD_M5_202409050345_202602062350.csv";
input string OutputRelative = "data\\csv_diff.csv"; // under Common\\Files
input double Tolerance = 0.000001;                 // price tolerance
input int MaxRows = 0;                             // 0 = no limit

int OnStart()
{
   // Open CSV (tab-delimited MT5 export format)
   int in = FileOpen(CsvPath, FILE_READ | FILE_CSV | FILE_ANSI | FILE_SHARE_READ);
   if(in == INVALID_HANDLE)
   {
      Print("Failed to open CSV: ", CsvPath, " err=", GetLastError());
      return 1;
   }
   FileSetInteger(in, FILE_CSV_SEPARATOR, '\t');

   int out = FileOpen(OutputRelative, FILE_WRITE | FILE_CSV | FILE_COMMON);
   if(out == INVALID_HANDLE)
   {
      Print("Failed to open output: Common\\Files\\", OutputRelative, " err=", GetLastError());
      FileClose(in);
      return 1;
   }

   FileWrite(out, "time",
                  "csv_open","csv_high","csv_low","csv_close",
                  "mt5_open","mt5_high","mt5_low","mt5_close",
                  "diff_open","diff_high","diff_low","diff_close",
                  "status");

   // Read header line (skip)
   if(!FileIsEnding(in))
      FileReadString(in); // <DATE>
   if(!FileIsEnding(in))
      FileReadString(in); // <TIME>
   if(!FileIsEnding(in))
      FileReadString(in); // <OPEN>
   if(!FileIsEnding(in))
      FileReadString(in); // <HIGH>
   if(!FileIsEnding(in))
      FileReadString(in); // <LOW>
   if(!FileIsEnding(in))
      FileReadString(in); // <CLOSE>
   // skip remaining header columns if any
   while(!FileIsEnding(in))
   {
      string rest = FileReadString(in);
      if(StringLen(rest) == 0)
         break;
   }

   long total = 0;
   long matched = 0;
   long missing = 0;
   double sum_open = 0, sum_high = 0, sum_low = 0, sum_close = 0;
   double max_open = 0, max_high = 0, max_low = 0, max_close = 0;

   while(!FileIsEnding(in))
   {
      string date = FileReadString(in);
      if(StringLen(date) == 0) break;
      string time = FileReadString(in);
      string s_open = FileReadString(in);
      string s_high = FileReadString(in);
      string s_low  = FileReadString(in);
      string s_close= FileReadString(in);

      // consume remaining fields
      for(int i=0;i<3;i++)
      {
         if(FileIsEnding(in)) break;
         FileReadString(in);
      }

      datetime t = StringToTime(date + " " + time);
      if(t <= 0) continue;

      double o = StringToDouble(s_open);
      double h = StringToDouble(s_high);
      double l = StringToDouble(s_low);
      double c = StringToDouble(s_close);

      int shift = iBarShift(_Symbol, _Period, t, true);
      if(shift < 0)
      {
         missing++;
         FileWrite(out, TimeToString(t, TIME_DATE|TIME_SECONDS),
                        o,h,l,c,
                        0,0,0,0,
                        0,0,0,0,
                        "missing");
         total++;
         if(MaxRows > 0 && total >= MaxRows) break;
         continue;
      }

      double mo = iOpen(_Symbol, _Period, shift);
      double mh = iHigh(_Symbol, _Period, shift);
      double ml = iLow(_Symbol, _Period, shift);
      double mc = iClose(_Symbol, _Period, shift);

      double doff = MathAbs(mo - o);
      double dh = MathAbs(mh - h);
      double dl = MathAbs(ml - l);
      double dc = MathAbs(mc - c);

      sum_open += doff; sum_high += dh; sum_low += dl; sum_close += dc;
      if(doff > max_open) max_open = doff;
      if(dh > max_high) max_high = dh;
      if(dl > max_low) max_low = dl;
      if(dc > max_close) max_close = dc;

      string status = (doff <= Tolerance && dh <= Tolerance && dl <= Tolerance && dc <= Tolerance) ? "match" : "diff";
      if(status == "match") matched++;

      FileWrite(out, TimeToString(t, TIME_DATE|TIME_SECONDS),
                     o,h,l,c,
                     mo,mh,ml,mc,
                     doff,dh,dl,dc,
                     status);

      total++;
      if(MaxRows > 0 && total >= MaxRows) break;
   }

   FileClose(in);
   FileClose(out);

   Print("Compare done.");
   Print("Total rows: ", total, " matched: ", matched, " missing: ", missing);
   if(total - missing > 0)
   {
      double denom = (double)(total - missing);
      Print("Mean abs diff: open=", sum_open/denom, " high=", sum_high/denom,
            " low=", sum_low/denom, " close=", sum_close/denom);
      Print("Max abs diff: open=", max_open, " high=", max_high,
            " low=", max_low, " close=", max_close);
   }

   Print("Output: Common\\Files\\", OutputRelative);
   return 0;
}
