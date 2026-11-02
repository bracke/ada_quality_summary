--  Counting types of the reporting rules, shared by the proved rules and the report model.
--
--  The report model derives its classification and count types from these declarations, so the operations proved in
--  Ada_Quality_Summary.Rules.Counting apply to the values every report renders.
package Ada_Quality_Summary.Rules
  with SPARK_Mode
is
   --  Counting types of the reporting rules.

   type Quality_State is (Passing, Violations, Incomplete, Unassessed);
   --  Presentation-level project classification; distinct from the assessment lifecycle.
   --  @enum Passing The current completed assessment has no violation and no unknown result.
   --  @enum Violations The current completed assessment has a violation and no unknown result.
   --  @enum Incomplete The current completed assessment has at least one unknown result.
   --  @enum Unassessed The project has no completed assessment.

   type Newer_State is (No_Newer_Run, Newer_Running, Newer_Interrupted, Newer_Invalid);
   --  Lifecycle of a run newer than the selected completed assessment.
   --  @enum No_Newer_Run The latest run is the selected completed assessment, or no run exists.
   --  @enum Newer_Running A newer run is still running.
   --  @enum Newer_Interrupted A newer run was interrupted.
   --  @enum Newer_Invalid A newer run failed publication validation.

   type Result_State is (Pass_State, Violation_State, Unknown_State, Not_Applicable_State, Missing_State);
   --  One project's state for one indicator.
   --  @enum Pass_State Requirement passes.
   --  @enum Violation_State Requirement is violated.
   --  @enum Unknown_State Compliance is unknown.
   --  @enum Not_Applicable_State Requirement does not apply.
   --  @enum Missing_State The project has no completed assessment.

   type Indicator_Totals is record
      Passed         : Natural := 0;
      Violated       : Natural := 0;
      Unknown_Count  : Natural := 0;
      Not_Applicable : Natural := 0;
      Missing        : Natural := 0;
   end record;
   --  Result-state counts; per project they count indicators, per indicator they count projects.
   --  @field Passed Pass results.
   --  @field Violated Violation results.
   --  @field Unknown_Count Unknown-compliance results.
   --  @field Not_Applicable Not-applicable results.
   --  @field Missing Projects without a usable completed assessment; always zero within one assessment.

   type Portfolio_Totals is record
      Projects             : Natural := 0;
      Passing              : Natural := 0;
      Violations           : Natural := 0;
      Incomplete           : Natural := 0;
      Unassessed           : Natural := 0;
      Enabled              : Natural := 0;
      Disabled             : Natural := 0;
      Findings             : Natural := 0;
      Indicator_Violations : Natural := 0;
      Unknown_Results      : Natural := 0;
      Newer_Running        : Natural := 0;
      Newer_Unfinished     : Natural := 0;
      With_Regressions     : Natural := 0;
   end record;
   --  Aggregate counts over the selected project population, computed before any row limit.
   --  @field Projects Selected projects.
   --  @field Passing Passing projects.
   --  @field Violations Violating projects.
   --  @field Incomplete Incomplete projects.
   --  @field Unassessed Unassessed projects.
   --  @field Enabled Enabled projects.
   --  @field Disabled Disabled projects.
   --  @field Findings Persisted findings in current assessments.
   --  @field Indicator_Violations Violated indicator results in current assessments.
   --  @field Unknown_Results Unknown-compliance indicator results in current assessments.
   --  @field Newer_Running Projects with a newer running assessment.
   --  @field Newer_Unfinished Projects with a newer interrupted or invalid assessment.
   --  @field With_Regressions Projects whose current assessment has at least one regression.
end Ada_Quality_Summary.Rules;
