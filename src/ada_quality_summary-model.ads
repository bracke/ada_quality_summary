with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Ada_Quality.History;
with Ada_Quality.Indicators;
with Ada_Quality.Reporting;
with Ada_Quality.Types;
with Ada_Quality_Summary.Rules.Counting;

--  Typed report records shared by aggregation, terminal rendering, and JSON rendering.
--
--  Identifiers use Natural with zero meaning absent only where a field documents that sentinel. Timestamps use
--  Ada_Quality.Reporting.Optional_Timestamp so that absent values are never fabricated.
package Ada_Quality_Summary.Model is
   --  Typed report records shared by aggregation, terminal rendering, and JSON rendering.
   subtype UString is Ada.Strings.Unbounded.Unbounded_String;
   --  Dynamically sized report text.

   type Project_Quality_State is new Ada_Quality_Summary.Rules.Quality_State;
   --  Presentation-level project classification; distinct from the assessment lifecycle. The literals and their
   --  meaning are those of Ada_Quality_Summary.Rules.Quality_State.

   function Image (State : Project_Quality_State) return String;
   --  Return the stable lowercase spelling used in JSON and filters.
   --  @param State Classification.
   --  @return `passing`, `violations`, `incomplete`, or `unassessed`.

   function Image (Level : Ada_Quality.Types.Severity) return String;
   --  Return the stable spelling of a finding severity used in JSON, SARIF, and the message catalog.
   --  @param Level Severity.
   --  @return `info`, `low`, `medium`, `high`, or `critical`.

   function Image (Category : Ada_Quality.Indicators.Indicator_Category) return String;
   --  Return the stable spelling of an indicator category.
   --  @param Category Registry category.
   --  @return Lowercase category, such as `test`.

   function Image (State : Ada_Quality.Types.Assessment_Status) return String;
   --  Return the stable spelling of an assessment lifecycle state.
   --  @param State Lifecycle state.
   --  @return `running`, `completed`, `invalid`, or `interrupted`.

   function Parse (Text : String; State : out Project_Quality_State) return Boolean;
   --  Parse a stable classification spelling.
   --  @param Text Lowercase spelling.
   --  @param State Parsed classification.
   --  @return True when Text names a classification.

   type Indicator_Totals is new Ada_Quality_Summary.Rules.Indicator_Totals;
   --  Result-state counts; per project they count indicators, per indicator they count projects. The fields are
   --  those of Ada_Quality_Summary.Rules.Indicator_Totals.

   function Applicable (Totals : Indicator_Totals) return Natural is
     (Ada_Quality_Summary.Rules.Counting.Applicable (Ada_Quality_Summary.Rules.Indicator_Totals (Totals)));
   --  Return the number of applicable requirements.
   --  @param Totals Counts.
   --  @return Passed plus violated plus unknown.

   function Sum (Totals : Indicator_Totals) return Natural is
     (Ada_Quality_Summary.Rules.Counting.Sum (Ada_Quality_Summary.Rules.Indicator_Totals (Totals)));
   --  Return the sum of every state count.
   --  @param Totals Counts.
   --  @return Total population covered by Totals.

   type Newer_Run_State is new Ada_Quality_Summary.Rules.Newer_State;
   --  Lifecycle of a run newer than the selected completed assessment. The literals and their meaning are those of
   --  Ada_Quality_Summary.Rules.Newer_State.

   function Image (State : Newer_Run_State) return String;
   --  Return the stable lowercase spelling.
   --  @param State Newer-run state.
   --  @return `none`, `running`, `interrupted`, or `invalid`.

   type Project_Summary is record
      Project_Id       : Positive;
      Project_Path     : UString;
      Name             : UString;
      Enabled          : Boolean;
      Removed          : Boolean := False;
      Quality          : Project_Quality_State := Unassessed;
      Current_Run_Id   : Natural := 0;
      Latest_Run_Id    : Natural := 0;
      Newer_Run        : Newer_Run_State := No_Newer_Run;
      Totals           : Indicator_Totals;
      Finding_Count    : Natural := 0;
      Regression_Count : Natural := 0;
   end record;
   --  Portfolio row for one registered project.
   --  @field Project_Id Authoritative project identity.
   --  @field Project_Path Canonical project root.
   --  @field Name Project directory basename.
   --  @field Enabled Whether bulk assessment includes the project.
   --  @field Removed Whether the project is a tombstone.
   --  @field Quality Classification of the current completed assessment.
   --  @field Current_Run_Id Selected completed assessment, or zero when none exists.
   --  @field Latest_Run_Id Most recent run in any lifecycle state, or zero when none exists.
   --  @field Newer_Run State of a run newer than the current assessment.
   --  @field Totals Indicator counts of the current assessment; all zero when unassessed.
   --  @field Finding_Count Persisted findings in the current assessment.
   --  @field Regression_Count Regressions of the current assessment against its compatible baseline.

   package Project_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Project_Summary);
   --  Project rows.

   type Portfolio_Totals is new Ada_Quality_Summary.Rules.Portfolio_Totals;
   --  Aggregate counts over the selected project population, computed before any row limit. The fields are those of
   --  Ada_Quality_Summary.Rules.Portfolio_Totals; Ada_Quality_Summary.Rules.Counting maintains their invariants.

   type Portfolio_Summary is record
      Totals   : Portfolio_Totals;
      Projects : Project_Vectors.Vector;
   end record;
   --  Portfolio report data.
   --  @field Totals Aggregate counts.
   --  @field Projects Project rows.

   type Indicator_Summary is record
      Id       : Ada_Quality.Types.Indicator_Id;
      Category : Ada_Quality.Indicators.Indicator_Category;
      Version  : Positive;
      Name     : UString;
      Totals   : Indicator_Totals;
   end record;
   --  Cross-project aggregate for one indicator.
   --  @field Id Indicator identity.
   --  @field Category Registry category.
   --  @field Version Indicator contract version.
   --  @field Name Registry name.
   --  @field Totals One state per selected project; Totals.Violated is the number of affected projects.

   package Indicator_Summary_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Indicator_Summary);
   --  Indicator aggregates.

   type Finding_Summary is record
      Project_Id  : Positive;
      Run_Id      : Positive;
      Indicator   : Ada_Quality.Types.Indicator_Id;
      Rule        : UString;
      Level       : Ada_Quality.Types.Severity;
      Message     : UString;
      Path        : UString;
      Line        : Natural := 0;
      Fingerprint : UString;
   end record;
   --  One persisted finding occurrence.
   --  @field Project_Id Owning project.
   --  @field Run_Id Owning assessment.
   --  @field Indicator Owning indicator.
   --  @field Rule Stable rule identifier.
   --  @field Level Severity.
   --  @field Message Diagnostic text.
   --  @field Path Project-relative path, or empty when unavailable.
   --  @field Line One-based line, or zero when unavailable.
   --  @field Fingerprint Stored finding identity.

   package Finding_Summary_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Finding_Summary);
   --  Finding occurrences.

   Waiver_Rule : constant String := "review-waiver";
   --  Rule of the finding Ada Quality records for a valid structured review waiver, whose message is
   --  `INDICATOR target=TARGET justification=TEXT`.

   function Is_Waiver (Finding : Finding_Summary) return Boolean is
     (Ada.Strings.Unbounded.To_String (Finding.Rule) = Waiver_Rule);
   --  Test whether a finding records a review waiver.
   --  @param Finding Finding.
   --  @return True for a waiver finding.

   function Waiver_Target (Message : String) return String;
   --  Return the subprogram or file a waiver message names.
   --  @param Message Waiver finding message.
   --  @return Text after `target=` up to the justification, or empty when the message names no target.

   function Waiver_Justification (Message : String) return String;
   --  Return the justification of a waiver message.
   --  @param Message Waiver finding message.
   --  @return Text after `justification=`, or the whole message when it has no justification field.

   type Regression_Summary is record
      Project_Id      : Positive;
      Current_Run_Id  : Positive;
      Baseline_Run_Id : Positive;
      Kind            : Ada_Quality.History.Regression_Kind;
      Indicator       : Ada_Quality.Types.Indicator_Id;
      Before          : UString;
      After           : UString;
   end record;
   --  One regression classified by Ada_Quality.History.Compare.
   --  @field Project_Id Owning project.
   --  @field Current_Run_Id Current assessment.
   --  @field Baseline_Run_Id Compatible baseline assessment.
   --  @field Kind Existing regression classification.
   --  @field Indicator Indicator whose evidence changed.
   --  @field Before Baseline state or value.
   --  @field After Current state or value.

   package Regression_Summary_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Regression_Summary);
   --  Regressions.

   type History_Summary is record
      Project_Id   : Positive;
      Run_Id       : Positive;
      State        : Ada_Quality.Types.Assessment_Status;
      Source_Id    : UString;
      Policy_Id    : UString;
      Toolchain_Id : UString;
      Started_At   : Ada_Quality.Reporting.Optional_Timestamp;
      Finished_At  : Ada_Quality.Reporting.Optional_Timestamp;
      Has_Quality  : Boolean := False;
      Quality      : Project_Quality_State := Unassessed;
   end record;
   --  One run in a project history.
   --  @field Project_Id Owning project.
   --  @field Run_Id Assessment identity.
   --  @field State Lifecycle state.
   --  @field Source_Id Source fingerprint.
   --  @field Policy_Id Policy fingerprint.
   --  @field Toolchain_Id Toolchain fingerprint.
   --  @field Started_At Persisted start time.
   --  @field Finished_At Persisted terminal time.
   --  @field Has_Quality Whether the run is completed and therefore classified.
   --  @field Quality Classification of a completed run.

   package History_Summary_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => History_Summary);
   --  Run histories.

   type Trend_Point is record
      Project_Id : Positive;
      Run_Id     : Positive;
      Value      : Long_Long_Integer;
      Observed   : Ada_Quality.Reporting.Optional_Timestamp;
   end record;
   --  One numeric observation from Ada_Quality.History.Metric_Trend.
   --  @field Project_Id Owning project.
   --  @field Run_Id Assessment identity.
   --  @field Value Persisted integer, or basis points for decimal measurements.
   --  @field Observed Persisted terminal time of the run.

   package Trend_Point_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Trend_Point);
   --  Ordered observations.

   type Trend_Summary is record
      Indicator             : Ada_Quality.Types.Indicator_Id;
      Kind                  : Ada_Quality.Types.Value_Kind := Ada_Quality.Types.Integer_Value;
      Unit                  : UString;
      Points                : Trend_Point_Vectors.Vector;
      Projects_Included     : Natural := 0;
      Projects_Excluded     : Natural := 0;
      Excluded_Observations : Natural := 0;
   end record;
   --  Numeric series for one indicator.
   --  @field Indicator Indicator identity.
   --  @field Kind Stored measurement kind shared by every point.
   --  @field Unit Unit from the indicator registry.
   --  @field Points Observations ordered by run identity, then project identity.
   --  @field Projects_Included Projects contributing at least one point.
   --  @field Projects_Excluded Selected projects without comparable numeric evidence.
   --  @field Excluded_Observations Completed runs whose measurement was not comparable or not numeric.

   package Trend_Summary_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Trend_Summary);
   --  Trend series.

   type Report_Kind is
     (Summary_Report, Projects_Report, Project_Report, Indicators_Report, Indicator_Report, Problems_Report,
      Waivers_Report, Regressions_Report, Compare_Report, Trends_Report, History_Report);
   --  Report command.
   --  @enum Summary_Report Portfolio overview.
   --  @enum Projects_Report Project table.
   --  @enum Project_Report One project assessment.
   --  @enum Indicators_Report Indicator matrix.
   --  @enum Indicator_Report One indicator across projects.
   --  @enum Problems_Report Outstanding findings.
   --  @enum Waivers_Report Review waivers.
   --  @enum Regressions_Report Regressions.
   --  @enum Compare_Report Regressions between two chosen assessments.
   --  @enum Trends_Report Historical trends.
   --  @enum History_Report One project history.

   function Image (Kind : Report_Kind) return String;
   --  Return the JSON report-type spelling.
   --  @param Kind Report command.
   --  @return Lowercase command name.

   type Report_Metadata is record
      Format_Version        : Positive := Report_Format_Version;
      Source_Schema_Version : Positive := Ada_Quality.Reporting.Supported_Schema;
      Selected_Projects     : Natural := 0;
      Snapshot_Identity     : UString;
      Kind                  : Report_Kind := Summary_Report;
   end record;
   --  Report provenance.
   --  @field Format_Version Report schema version.
   --  @field Source_Schema_Version Ada Quality database schema version.
   --  @field Selected_Projects Projects in the selected population.
   --  @field Snapshot_Identity Digest of the database snapshot.
   --  @field Kind Report command.

   type Indicator_State is new Ada_Quality_Summary.Rules.Result_State;
   --  One project's state for one indicator. The literals and their meaning are those of
   --  Ada_Quality_Summary.Rules.Result_State.

   function Image (State : Indicator_State) return String;
   --  Return the stable spelling.
   --  @param State State.
   --  @return `pass`, `violation`, `unknown`, `not_applicable`, or `missing`.

   function State_Of (Compliance : Ada_Quality.Types.Compliance_Status) return Indicator_State;
   --  Return the state of a persisted result: the one mapping from Ada Quality compliance to reporting state.
   --  @param Compliance Persisted compliance.
   --  @return Pass, violation, unknown, or not-applicable state; never Missing_State.

   type Indicator_Row is record
      Project    : Project_Summary;
      State      : Indicator_State;
      Has_Result : Boolean := False;
      Result     : Ada_Quality.Types.Indicator_Result;
   end record;
   --  One project's result for the indicator report.
   --  @field Project Project row.
   --  @field State Result state.
   --  @field Has_Result Whether a completed assessment supplied Result.
   --  @field Result Decoded result.

   package Indicator_Row_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Indicator_Row);
   --  Indicator report rows.

   function Summary_Of
     (Project_Id, Run_Id : Positive; Finding : Ada_Quality.Types.Finding) return Finding_Summary;
   --  Return the report row of one persisted finding.
   --  @param Project_Id Owning project.
   --  @param Run_Id Owning assessment.
   --  @param Finding Persisted finding.
   --  @return Finding row.

   function Basename (Path : String) return String;
   --  Return the final path component, ignoring one trailing separator.
   --  @param Path Project path.
   --  @return Directory basename.

   function Image (Kind : Ada_Quality.History.Regression_Kind) return String;
   --  Return the JSON spelling of a regression classification: Ada Quality's image with underscores.
   --  @param Kind Classification.
   --  @return Lowercase underscore spelling, such as `new_violation`.

   type Baseline_Status is (No_Current_Assessment, No_Baseline, Compared);
   --  Outcome of baseline selection for one project.
   --  @enum No_Current_Assessment The project has no completed assessment.
   --  @enum No_Baseline No comparable earlier assessment exists; the comparison status gives the reason.
   --  @enum Compared The current assessment was compared with its selected baseline.

   function Image (Status : Baseline_Status) return String;
   --  Return the stable spelling.
   --  @param Status Baseline status.
   --  @return `no_current_assessment`, `no_baseline`, or `compared`.

   type Exclusion_Reason is (Missing_Source_Fingerprint, Policy_Changed, Toolchain_Changed);
   --  Why Ada_Quality.History.Compatible rejected an earlier completed assessment.
   --  @enum Missing_Source_Fingerprint A source fingerprint is absent.
   --  @enum Policy_Changed The policy fingerprint differs or is absent.
   --  @enum Toolchain_Changed The toolchain fingerprint differs or is absent.

   function Image (Status : Ada_Quality.History.Comparison_Status) return String;
   --  Return the JSON spelling of a baseline-selection decision: Ada Quality's image with underscores.
   --  @param Status Selection decision.
   --  @return Lowercase underscore spelling, such as `comparison_available` or `toolchain_changed`.

   function Image (Reason : Exclusion_Reason) return String;
   --  Return the stable spelling.
   --  @param Reason Reason.
   --  @return Lowercase underscore spelling.

   type Excluded_Run is record
      Run_Id : Positive;
      Reason : Exclusion_Reason;
   end record;
   --  Earlier completed assessment skipped as an incompatible baseline.
   --  @field Run_Id Skipped assessment.
   --  @field Reason Incompatibility.

   package Excluded_Run_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Excluded_Run);
   --  Skipped assessments, newest first.

   type Baseline_Info is record
      Project_Id      : Positive;
      Status          : Baseline_Status := No_Current_Assessment;
      Current_Run_Id  : Natural := 0;
      Baseline_Run_Id : Natural := 0;
      Comparison      : Ada_Quality.History.Comparison_Status := Ada_Quality.History.No_Assessments;
      Policy_Changed  : Boolean := False;
      Excluded        : Excluded_Run_Vectors.Vector;
   end record;
   --  Baseline selection for one project.
   --  @field Project_Id Project.
   --  @field Status Outcome.
   --  @field Current_Run_Id Current completed assessment, or zero.
   --  @field Baseline_Run_Id Selected baseline, or zero.
   --  @field Comparison Ada_Quality.History.Select_Comparison decision for the current assessment.
   --  @field Policy_Changed Whether the baseline was assessed under a different policy, so changes the policy caused
   --  are classified as policy-induced.
   --  @field Excluded Incompatible completed assessments newer than the baseline.

   package Baseline_Info_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Baseline_Info);
   --  Baseline selections.

   type Pair_Comparison is record
      Project_Id     : Positive;
      Baseline       : History_Summary;
      Current        : History_Summary;
      Comparison     : Ada_Quality.History.Comparison_Status := Ada_Quality.History.No_Compatible_Baseline;
      Policy_Changed : Boolean := False;
      Has_Reason     : Boolean := False;
      Reason         : Exclusion_Reason := Toolchain_Changed;
   end record;
   --  Comparison of two chosen assessments of one project, without automatic baseline substitution.
   --  @field Project_Id Project owning both assessments.
   --  @field Baseline Earlier assessment.
   --  @field Current Later assessment.
   --  @field Comparison Ada_Quality.Reporting.Compare_Assessments decision.
   --  @field Policy_Changed Whether the policy differs, so changes the policy caused are classified as
   --  policy-induced.
   --  @field Has_Reason Whether two completed assessments were found incompatible.
   --  @field Reason The incompatibility, when Has_Reason is True.

   type State_Snapshot is record
      Day        : UString;
      Totals     : Portfolio_Totals;
   end record;
   --  Last-known-state classification of the population at the end of one UTC day.
   --  @field Day UTC date `YYYY-MM-DD`.
   --  @field Totals Classification counts and indicator totals.

   package State_Snapshot_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => State_Snapshot);
   --  Daily snapshots in ascending date order.

   function Classify (Results : Ada_Quality.Types.Result_Vectors.Vector) return Project_Quality_State;
   --  Classify a completed assessment; unknown takes precedence over violation.
   --  @param Results Results of one completed assessment.
   --  @return Incomplete, Violations, or Passing.

   function Count_Indicators (Results : Ada_Quality.Types.Result_Vectors.Vector) return Indicator_Totals;
   --  Count result states of one completed assessment.
   --  @param Results Results of one completed assessment.
   --  @return Counts with Missing equal to zero.

   function Quality_Priority (State : Project_Quality_State) return Positive;
   --  Return the overview ordering rank.
   --  @param State Classification.
   --  @return One for Incomplete, two for Violations, three for Unassessed, four for Passing.
end Ada_Quality_Summary.Model;
