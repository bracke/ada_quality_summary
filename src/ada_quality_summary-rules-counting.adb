package body Ada_Quality_Summary.Rules.Counting
  with SPARK_Mode
is
   procedure Tally (Totals : in out Indicator_Totals; State : Result_State) is
   begin
      case State is
         when Pass_State => Totals.Passed := Totals.Passed + 1;
         when Violation_State => Totals.Violated := Totals.Violated + 1;
         when Unknown_State => Totals.Unknown_Count := Totals.Unknown_Count + 1;
         when Not_Applicable_State => Totals.Not_Applicable := Totals.Not_Applicable + 1;
         when Missing_State => Totals.Missing := Totals.Missing + 1;
      end case;
   end Tally;

   procedure Add_Classified
     (Totals : in out Portfolio_Totals; Quality : Quality_State; Violated, Unknown : Natural) is
   begin
      Totals.Projects := Totals.Projects + 1;
      case Quality is
         when Passing => Totals.Passing := Totals.Passing + 1;
         when Violations => Totals.Violations := Totals.Violations + 1;
         when Incomplete => Totals.Incomplete := Totals.Incomplete + 1;
         when Unassessed => Totals.Unassessed := Totals.Unassessed + 1;
      end case;
      Totals.Indicator_Violations := Totals.Indicator_Violations + Violated;
      Totals.Unknown_Results := Totals.Unknown_Results + Unknown;
   end Add_Classified;

   procedure Add_Project
     (Totals    : in out Portfolio_Totals;
      Quality   : Quality_State;
      Enabled   : Boolean;
      Findings  : Natural;
      Violated  : Natural;
      Unknown   : Natural;
      Newer     : Newer_State;
      Regressed : Boolean) is
   begin
      Add_Classified (Totals, Quality, Violated, Unknown);
      if Enabled then
         Totals.Enabled := Totals.Enabled + 1;
      else
         Totals.Disabled := Totals.Disabled + 1;
      end if;
      Totals.Findings := Totals.Findings + Findings;
      case Newer is
         when Newer_Running => Totals.Newer_Running := Totals.Newer_Running + 1;
         when Newer_Interrupted | Newer_Invalid => Totals.Newer_Unfinished := Totals.Newer_Unfinished + 1;
         when No_Newer_Run => null;
      end case;
      if Regressed then
         Totals.With_Regressions := Totals.With_Regressions + 1;
      end if;
   end Add_Project;
end Ada_Quality_Summary.Rules.Counting;
