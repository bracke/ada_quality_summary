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
     (Project_Quality_State
        (Rules.Counting.Classify (Rules.Indicator_Totals (Count_Indicators (Results)))));

   function Count_Indicators (Results : Result_Vectors.Vector) return Indicator_Totals is
      Totals : Indicator_Totals;
   begin
      for Result of Results loop
         Rules.Counting.Tally
           (Rules.Indicator_Totals (Totals),
            (case Result.Compliance is
                when Pass => Rules.Pass_State,
                when Violation => Rules.Violation_State,
                when Unknown => Rules.Unknown_State,
                when Compliance_Status'(Not_Applicable) => Rules.Not_Applicable_State));
      end loop;
      return Totals;
   end Count_Indicators;

   function Quality_Priority (State : Project_Quality_State) return Positive is
     (Rules.Counting.Priority (Rules.Quality_State (State)));
end Ada_Quality_Summary.Model;
