package body Ada_Quality_Summary.Model is
   use Ada_Quality.Types;

   function Image (State : Project_Quality_State) return String is
     (case State is
         when Passing => "passing",
         when Violations => "violations",
         when Incomplete => "incomplete",
         when Unassessed => "unassessed");

   function Parse (Text : String; State : out Project_Quality_State) return Boolean is
   begin
      for Candidate in Project_Quality_State loop
         if Image (Candidate) = Text then
            State := Candidate;
            return True;
         end if;
      end loop;
      State := Unassessed;
      return False;
   end Parse;

   function Image (State : Newer_Run_State) return String is
     (case State is
         when No_Newer_Run => "none",
         when Newer_Running => "running",
         when Newer_Interrupted => "interrupted",
         when Newer_Invalid => "invalid");

   function Image (Kind : Report_Kind) return String is
     (case Kind is
         when Summary_Report => "summary",
         when Projects_Report => "projects",
         when Project_Report => "project",
         when Indicators_Report => "indicators",
         when Indicator_Report => "indicator",
         when Problems_Report => "problems",
         when Regressions_Report => "regressions",
         when Trends_Report => "trends",
         when History_Report => "history");

   function Classify (Results : Result_Vectors.Vector) return Project_Quality_State is
      Has_Violation : Boolean := False;
   begin
      for Result of Results loop
         case Result.Compliance is
            when Unknown => return Incomplete;
            when Violation => Has_Violation := True;
            when Pass | Compliance_Status'(Not_Applicable) => null;
         end case;
      end loop;
      return (if Has_Violation then Violations else Passing);
   end Classify;

   function Count_Indicators (Results : Result_Vectors.Vector) return Indicator_Totals is
      Totals : Indicator_Totals;
   begin
      for Result of Results loop
         case Result.Compliance is
            when Pass => Totals.Passed := Totals.Passed + 1;
            when Violation => Totals.Violated := Totals.Violated + 1;
            when Unknown => Totals.Unknown_Count := Totals.Unknown_Count + 1;
            when Compliance_Status'(Not_Applicable) => Totals.Not_Applicable := Totals.Not_Applicable + 1;
         end case;
      end loop;
      return Totals;
   end Count_Indicators;

   function Quality_Priority (State : Project_Quality_State) return Positive is
     (case State is
         when Incomplete => 1,
         when Violations => 2,
         when Unassessed => 3,
         when Passing => 4);
end Ada_Quality_Summary.Model;
