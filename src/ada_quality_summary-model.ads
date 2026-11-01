with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Ada_Quality.History;
with Ada_Quality.Indicators;
with Ada_Quality.Reporting;
with Ada_Quality.Types;

--  Typed report records shared by aggregation, terminal rendering, and JSON rendering.
--
--  Identifiers use Natural with zero meaning absent only where a field documents that sentinel. Timestamps use
--  Ada_Quality.Reporting.Optional_Timestamp so that absent values are never fabricated.
package Ada_Quality_Summary.Model is
   --  Typed report records shared by aggregation, terminal rendering, and JSON rendering.
   subtype UString is Ada.Strings.Unbounded.Unbounded_String;
   --  Dynamically sized report text.

   type Project_Quality_State is (Passing, Violations, Incomplete, Unassessed);
   --  Presentation-level project classification; distinct from the assessment lifecycle.
   --  @enum Passing The current completed assessment has no violation and no unknown result.
   --  @enum Violations The current completed assessment has a violation and no unknown result.
   --  @enum Incomplete The current completed assessment has at least one unknown result.
   --  @enum Unassessed The project has no completed assessment.

   function Image (State : Project_Quality_State) return String;
   --  Return the stable lowercase spelling used in JSON and filters.
   --  @param State Classification.
   --  @return `passing`, `violations`, `incomplete`, or `unassessed`.

   function Parse (Text : String; State : out Project_Quality_State) return Boolean;
   --  Parse a stable classification spelling.
   --  @param Text Lowercase spelling.
   --  @param State Parsed classification.
   --  @return True when Text names a classification.

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

   function Applicable (Totals : Indicator_Totals) return Natural is
     (Totals.Passed + Totals.Violated + Totals.Unknown_Count);
   --  Return the number of applicable requirements.
   --  @param Totals Counts.
   --  @return Passed plus violated plus unknown.

   function Sum (Totals : Indicator_Totals) return Natural is
     (Applicable (Totals) + Totals.Not_Applicable + Totals.Missing);
   --  Return the sum of every state count.
   --  @param Totals Counts.
   --  @return Total population covered by Totals.

   type Newer_Run_State is (No_Newer_Run, Newer_Running, Newer_Interrupted, Newer_Invalid);
   --  Lifecycle of a run newer than the selected completed assessment.
   --  @enum No_Newer_Run The latest run is the selected completed assessment, or no run exists.
   --  @enum Newer_Running A newer run is still running.
   --  @enum Newer_Interrupted A newer run was interrupted.
   --  @enum Newer_Invalid A newer run failed publication validation.

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
      Affected : Natural := 0;
   end record;
   --  Cross-project aggregate for one indicator.
   --  @field Id Indicator identity.
   --  @field Category Registry category.
   --  @field Version Indicator contract version.
   --  @field Name Registry name.
   --  @field Totals One state per selected project.
   --  @field Affected Projects violating the indicator.

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
      Regressions_Report, Trends_Report, History_Report);
   --  Report command.
   --  @enum Summary_Report Portfolio overview.
   --  @enum Projects_Report Project table.
   --  @enum Project_Report One project assessment.
   --  @enum Indicators_Report Indicator matrix.
   --  @enum Indicator_Report One indicator across projects.
   --  @enum Problems_Report Outstanding findings.
   --  @enum Regressions_Report Regressions.
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
