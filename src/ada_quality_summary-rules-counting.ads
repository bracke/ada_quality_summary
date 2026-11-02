--  Proved classification and counting rules of the summary reports.
--
--  GNATprove shows that every operation is free of run-time errors, that a completed assessment is never classified
--  as unassessed, that unknown compliance takes precedence over violation, that each tally adds exactly one to the
--  counted population, and that portfolio totals always partition the projects they count.
package Ada_Quality_Summary.Rules.Counting
  with SPARK_Mode
is
   --  Proved classification and counting rules of the summary reports.

   function Total (Totals : Indicator_Totals) return Long_Long_Integer is
     (Long_Long_Integer (Totals.Passed) + Long_Long_Integer (Totals.Violated) +
      Long_Long_Integer (Totals.Unknown_Count) + Long_Long_Integer (Totals.Not_Applicable) +
      Long_Long_Integer (Totals.Missing));
   --  Return the counted population without overflow.
   --  @param Totals Counts.
   --  @return Sum of every state count.

   function Applicable (Totals : Indicator_Totals) return Natural is
     (Totals.Passed + Totals.Violated + Totals.Unknown_Count)
   with
     Pre  => Long_Long_Integer (Totals.Passed) + Long_Long_Integer (Totals.Violated) +
             Long_Long_Integer (Totals.Unknown_Count) <= Long_Long_Integer (Natural'Last);
   --  Return the number of applicable requirements.
   --  @param Totals Counts.
   --  @return Passed plus violated plus unknown.

   function Sum (Totals : Indicator_Totals) return Natural is
     (Totals.Passed + Totals.Violated + Totals.Unknown_Count + Totals.Not_Applicable + Totals.Missing)
   with
     Pre  => Total (Totals) <= Long_Long_Integer (Natural'Last),
     Post => Long_Long_Integer (Sum'Result) = Total (Totals);
   --  Return the sum of every state count.
   --  @param Totals Counts.
   --  @return Total population covered by Totals.

   procedure Tally (Totals : in out Indicator_Totals; State : Result_State)
   with
     Pre  => Total (Totals) < Long_Long_Integer (Natural'Last),
     Post => Total (Totals) = Total (Totals'Old) + 1
             and then
             (case State is
                 when Pass_State => Totals = (Totals'Old with delta Passed => Totals'Old.Passed + 1),
                 when Violation_State => Totals = (Totals'Old with delta Violated => Totals'Old.Violated + 1),
                 when Unknown_State =>
                    Totals = (Totals'Old with delta Unknown_Count => Totals'Old.Unknown_Count + 1),
                 when Not_Applicable_State =>
                    Totals = (Totals'Old with delta Not_Applicable => Totals'Old.Not_Applicable + 1),
                 when Missing_State => Totals = (Totals'Old with delta Missing => Totals'Old.Missing + 1));
   --  Count one result in the field of its state.
   --  @param Totals Counts to extend.
   --  @param State Counted state.

   function Classify (Totals : Indicator_Totals) return Quality_State is
     (if Totals.Unknown_Count > 0 then Incomplete elsif Totals.Violated > 0 then Violations else Passing)
   with
     Post => Classify'Result /= Unassessed;
   --  Classify a completed assessment from its result counts; unknown takes precedence over violation.
   --  @param Totals Result counts of one completed assessment.
   --  @return Incomplete, Violations, or Passing.

   function Priority (State : Quality_State) return Positive is
     (case State is
         when Incomplete => 1,
         when Violations => 2,
         when Unassessed => 3,
         when Passing => 4)
   with
     Post => Priority'Result <= 4;
   --  Return the overview ordering rank.
   --  @param State Classification.
   --  @return One for Incomplete, two for Violations, three for Unassessed, four for Passing.

   function Classified (Totals : Portfolio_Totals) return Boolean is
     (Long_Long_Integer (Totals.Projects) =
        Long_Long_Integer (Totals.Passing) + Long_Long_Integer (Totals.Violations) +
        Long_Long_Integer (Totals.Incomplete) + Long_Long_Integer (Totals.Unassessed));
   --  Return whether the four classifications partition the projects.
   --  @param Totals Portfolio counts.
   --  @return True when every project has exactly one classification.

   function Consistent (Totals : Portfolio_Totals) return Boolean is
     (Classified (Totals)
      and then Long_Long_Integer (Totals.Projects) =
                 Long_Long_Integer (Totals.Enabled) + Long_Long_Integer (Totals.Disabled)
      and then Long_Long_Integer (Totals.Newer_Running) + Long_Long_Integer (Totals.Newer_Unfinished) <=
                 Long_Long_Integer (Totals.Projects)
      and then Totals.With_Regressions <= Totals.Projects);
   --  Return whether portfolio counts describe one population.
   --  @param Totals Portfolio counts.
   --  @return True when classifications and enablement partition the projects and per-project flags never
   --  exceed them.

   procedure Add_Classified
     (Totals : in out Portfolio_Totals; Quality : Quality_State; Violated, Unknown : Natural)
   with
     Pre  => Classified (Totals)
             and then Totals.Projects < Natural'Last
             and then Totals.Indicator_Violations <= Natural'Last - Violated
             and then Totals.Unknown_Results <= Natural'Last - Unknown,
     Post => Classified (Totals)
             and then Totals.Projects = Totals'Old.Projects + 1
             and then Totals.Indicator_Violations = Totals'Old.Indicator_Violations + Violated
             and then Totals.Unknown_Results = Totals'Old.Unknown_Results + Unknown
             and then Totals.Passing = Totals'Old.Passing + (if Quality = Passing then 1 else 0)
             and then Totals.Violations = Totals'Old.Violations + (if Quality = Violations then 1 else 0)
             and then Totals.Incomplete = Totals'Old.Incomplete + (if Quality = Incomplete then 1 else 0)
             and then Totals.Unassessed = Totals'Old.Unassessed + (if Quality = Unassessed then 1 else 0)
             and then Totals.Enabled = Totals'Old.Enabled
             and then Totals.Disabled = Totals'Old.Disabled
             and then Totals.Findings = Totals'Old.Findings
             and then Totals.Newer_Running = Totals'Old.Newer_Running
             and then Totals.Newer_Unfinished = Totals'Old.Newer_Unfinished
             and then Totals.With_Regressions = Totals'Old.With_Regressions;
   --  Count one project by its classification and current result counts.
   --  @param Totals Portfolio counts to extend.
   --  @param Quality Project classification.
   --  @param Violated Violated results of the project's current assessment.
   --  @param Unknown Unknown-compliance results of the project's current assessment.

   procedure Add_Project
     (Totals    : in out Portfolio_Totals;
      Quality   : Quality_State;
      Enabled   : Boolean;
      Findings  : Natural;
      Violated  : Natural;
      Unknown   : Natural;
      Newer     : Newer_State;
      Regressed : Boolean)
   with
     Pre  => Consistent (Totals)
             and then Totals.Projects < Natural'Last
             and then Totals.Findings <= Natural'Last - Findings
             and then Totals.Indicator_Violations <= Natural'Last - Violated
             and then Totals.Unknown_Results <= Natural'Last - Unknown,
     Post => Consistent (Totals)
             and then Totals.Projects = Totals'Old.Projects + 1
             and then Totals.Findings = Totals'Old.Findings + Findings
             and then Totals.Indicator_Violations = Totals'Old.Indicator_Violations + Violated
             and then Totals.Unknown_Results = Totals'Old.Unknown_Results + Unknown
             and then Totals.Passing = Totals'Old.Passing + (if Quality = Passing then 1 else 0)
             and then Totals.Violations = Totals'Old.Violations + (if Quality = Violations then 1 else 0)
             and then Totals.Incomplete = Totals'Old.Incomplete + (if Quality = Incomplete then 1 else 0)
             and then Totals.Unassessed = Totals'Old.Unassessed + (if Quality = Unassessed then 1 else 0)
             and then Totals.Enabled = Totals'Old.Enabled + (if Enabled then 1 else 0)
             and then Totals.Disabled = Totals'Old.Disabled + (if Enabled then 0 else 1)
             and then Totals.Newer_Running = Totals'Old.Newer_Running + (if Newer = Newer_Running then 1 else 0)
             and then Totals.Newer_Unfinished =
                        Totals'Old.Newer_Unfinished + (if Newer in Newer_Interrupted | Newer_Invalid then 1 else 0)
             and then Totals.With_Regressions = Totals'Old.With_Regressions + (if Regressed then 1 else 0);
   --  Count one project row.
   --  @param Totals Portfolio counts to extend.
   --  @param Quality Project classification.
   --  @param Enabled Whether the project is enabled.
   --  @param Findings Persisted findings of the project's current assessment.
   --  @param Violated Violated results of the project's current assessment.
   --  @param Unknown Unknown-compliance results of the project's current assessment.
   --  @param Newer Lifecycle of a newer run.
   --  @param Regressed Whether the current assessment has at least one regression.
end Ada_Quality_Summary.Rules.Counting;
