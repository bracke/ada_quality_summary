with Ada.Calendar.Formatting;

package body Ada_Quality_Summary.Criteria is
   use type Ada.Calendar.Time;

   function Image (Condition : Gate_Condition) return String is
     (case Condition is
         when Gate_Regressions => "regressions",
         when Gate_Violations => "violations",
         when Gate_Incomplete => "incomplete",
         when Gate_Unassessed => "unassessed");

   function Image (Key : Sort_Key) return String is
     (case Key is
         when Default_Sort => "default",
         when Sort_Name => "name",
         when Sort_Id => "id",
         when Sort_Path => "path",
         when Sort_Quality => "quality",
         when Sort_Violations => "violations",
         when Sort_Unknown => "unknown",
         when Sort_Findings => "findings",
         when Sort_Affected => "affected",
         when Sort_Severity => "severity",
         when Sort_Indicator => "indicator",
         when Sort_Project => "project",
         when Sort_Kind => "kind",
         when Sort_Run => "run",
         when Sort_State => "state");

   function Day_Start (Time : Ada.Calendar.Time) return Ada.Calendar.Time is
      Year    : Ada.Calendar.Year_Number;
      Month   : Ada.Calendar.Month_Number;
      Day     : Ada.Calendar.Day_Number;
      Seconds : Ada.Calendar.Day_Duration;
      Leap    : Boolean;
   begin
      Ada.Calendar.Formatting.Split (Time, Year, Month, Day, Seconds, Leap, Time_Zone => 0);
      return Ada.Calendar.Formatting.Time_Of (Year, Month, Day, 0.0, Time_Zone => 0);
   end Day_Start;

   function Day_Image (Time : Ada.Calendar.Time) return String is
     (Ada.Calendar.Formatting.Image (Time, Time_Zone => 0) (1 .. 10));

   function Within (Time : Ada.Calendar.Time; Since, Until_Date : Date_Bound) return Boolean is
     ((not Since.Present or else Time >= Since.Value) and then
      (not Until_Date.Present or else Day_Start (Time) <= Until_Date.Value));
end Ada_Quality_Summary.Criteria;
