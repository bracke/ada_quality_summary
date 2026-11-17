with Ada.Strings.Fixed;

package body Ada_Quality_Summary.Model is
   use Ada_Quality.Types;

   --  Ada Quality spells its classifications with hyphens; report JSON uses underscores.
   function Underscored (Text : String) return String is
      Result : String := Text;
   begin
      for C of Result loop
         if C = '-' then
            C := '_';
         end if;
      end loop;
      return Result;
   end Underscored;

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
         Rules.Counting.Tally (Rules.Indicator_Totals (Totals), Rules.Result_State (State_Of (Result.Compliance)));
      end loop;
      return Totals;
   end Count_Indicators;

   function Quality_Priority (State : Project_Quality_State) return Positive is
     (Rules.Counting.Priority (Rules.Quality_State (State)));

   function Image (State : Indicator_State) return String is
     (case State is
         when Pass_State => "pass",
         when Violation_State => "violation",
         when Unknown_State => "unknown",
         when Not_Applicable_State => "not_applicable",
         when Missing_State => "missing");

   function State_Of (Compliance : Compliance_Status) return Indicator_State is
     (case Compliance is
         when Pass => Pass_State,
         when Violation => Violation_State,
         when Unknown => Unknown_State,
         when Compliance_Status'(Not_Applicable) => Not_Applicable_State);

   function Summary_Of
     (Project_Id, Run_Id : Positive; Finding : Ada_Quality.Types.Finding) return Finding_Summary is
     ((Project_Id => Project_Id, Run_Id => Run_Id, Indicator => Finding.Indicator, Rule => Finding.Rule,
       Level => Finding.Level, Message => Finding.Message, Path => Finding.Relative_Path, Line => Finding.Line,
       Fingerprint => Finding.Fingerprint));

   function Basename (Path : String) return String is
      Slash : constant Natural := Ada.Strings.Fixed.Index (Path, "/", Ada.Strings.Backward);
   begin
      if Slash = 0 then
         return Path;
      elsif Slash = Path'Last and then Path'Length > 1 then
         return Basename (Path (Path'First .. Path'Last - 1));
      end if;
      return Path (Slash + 1 .. Path'Last);
   end Basename;

   function Image (Kind : Ada_Quality.History.Regression_Kind) return String is
     (Underscored (Ada_Quality.History.Image (Kind)));

   function Image (Status : Baseline_Status) return String is
     (case Status is
         when No_Current_Assessment => "no_current_assessment",
         when No_Baseline => "no_baseline",
         when Compared => "compared");

   function Image (Status : Ada_Quality.History.Comparison_Status) return String is
     (Underscored (Ada_Quality.History.Image (Status)));

   function Image (Reason : Exclusion_Reason) return String is
     (case Reason is
         when Missing_Source_Fingerprint => "missing_source_fingerprint",
         when Policy_Changed => "policy_changed",
         when Toolchain_Changed => "toolchain_changed");
end Ada_Quality_Summary.Model;
