with Ada.Containers.Vectors;
with Ada_Quality.History;
with Ada_Quality.Reporting;
with Ada_Quality.Types;
with Ada_Quality_Summary.Criteria;
with Ada_Quality_Summary.Filtering;
with Ada_Quality_Summary.Model;
with Ada_Quality_Summary.Options;
with Ada_Quality_Summary.Repository;

--  Complete typed data of one report, built before any rendering and shared by the terminal and JSON renderers.
--
--  Build fills the fields its report kind renders and leaves the rest at their defaults:
--
--  | Kind        | Fields beyond Metadata, Filter, Database_Label, Limit, Portfolio, and Row_Count            |
--  |-------------|----------------------------------------------------------------------------------------------|
--  | summary     | Common, finding counts and Groups, regression counts, Baselines                              |
--  | projects    | per-project regression counts in Portfolio                                                   |
--  | project     | Project, Assessment, Findings and counts, Regressions and counts, Baselines                  |
--  | indicators  | Indicators                                                                                   |
--  | indicator   | Indicator, Indicator_Rows                                                                    |
--  | problems    | Findings and counts, Groups                                                                  |
--  | waivers     | Waivers, Waiver_Total, Waiver_Projects, Waiver_Groups                                        |
--  | regressions | Regressions and counts, Baselines                                                            |
--  | compare     | Project, Pair, Regressions and counts                                                        |
--  | trends      | Series, Excluded_Observations, Daily, Undated, Since, Until_Date                             |
--  | history     | Project, History and lifecycle counts, Undated, Since, Until_Date                            |
--
--  Every kind fills Gate.
package Ada_Quality_Summary.Reports is
   --  Complete typed data of one report, built before any rendering.
   subtype UString is Ada_Quality_Summary.Model.UString;
   --  Dynamically sized text.

   subtype Severity_Counts is Ada_Quality_Summary.Repository.Severity_Counts;
   --  Findings per severity.

   type Finding_Group is record
      Indicator : Ada_Quality.Types.Indicator_Id;
      Findings  : Natural := 0;
      Projects  : Natural := 0;
   end record;
   --  Findings attributed to one indicator.
   --  @field Indicator Indicator.
   --  @field Findings Finding occurrences.
   --  @field Projects Projects with at least one finding.

   package Finding_Group_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Finding_Group);
   --  Groups in registry order.

   type Waiver_Group is record
      Indicator : Ada_Quality.Types.Indicator_Id;
      Waivers   : Natural := 0;
      Projects  : Natural := 0;
   end record;
   --  Review waivers of one indicator.
   --  @field Indicator Waived indicator.
   --  @field Waivers Waiver findings.
   --  @field Projects Projects with at least one waiver of the indicator.

   package Waiver_Group_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Waiver_Group);
   --  Waiver groups in registry order.

   type Kind_Counts is array (Ada_Quality.History.Regression_Kind) of Natural;
   --  Regressions per classification.

   type Report is record
      Metadata          : Ada_Quality_Summary.Model.Report_Metadata;
      Filter            : Ada_Quality_Summary.Filtering.Selection;
      Database_Label    : UString;
      Limit             : Natural := 0;
      Portfolio         : Ada_Quality_Summary.Model.Portfolio_Summary;
      Row_Count         : Natural := 0;
      Common            : Ada_Quality_Summary.Model.Indicator_Summary_Vectors.Vector;
      Indicators        : Ada_Quality_Summary.Model.Indicator_Summary_Vectors.Vector;
      Indicator         : Ada_Quality_Summary.Model.Indicator_Summary;
      Indicator_Rows    : Ada_Quality_Summary.Model.Indicator_Row_Vectors.Vector;
      Project           : Ada_Quality_Summary.Model.Project_Summary;
      Has_Assessment    : Boolean := False;
      Assessment        : Ada_Quality.Reporting.Assessment_Record;
      Findings          : Ada_Quality_Summary.Model.Finding_Summary_Vectors.Vector;
      Finding_Total     : Natural := 0;
      Finding_Projects  : Natural := 0;
      By_Severity       : Severity_Counts := [others => 0];
      Groups            : Finding_Group_Vectors.Vector;
      Waivers           : Ada_Quality_Summary.Model.Finding_Summary_Vectors.Vector;
      Waiver_Total      : Natural := 0;
      Waiver_Projects   : Natural := 0;
      Waiver_Groups     : Waiver_Group_Vectors.Vector;
      Regressions       : Ada_Quality_Summary.Model.Regression_Summary_Vectors.Vector;
      Regression_Total  : Natural := 0;
      By_Kind           : Kind_Counts := [others => 0];
      Projects_Affected : Natural := 0;
      Baselines         : Ada_Quality_Summary.Model.Baseline_Info_Vectors.Vector;
      Pair              : Ada_Quality_Summary.Model.Pair_Comparison;
      History           : Ada_Quality_Summary.Model.History_Summary_Vectors.Vector;
      Completed_Count   : Natural := 0;
      Running_Count     : Natural := 0;
      Interrupted_Count : Natural := 0;
      Invalid_Count     : Natural := 0;
      Series            : Ada_Quality_Summary.Model.Trend_Summary_Vectors.Vector;
      Excluded_Observations : Natural := 0;
      Daily             : Ada_Quality_Summary.Model.State_Snapshot_Vectors.Vector;
      Undated           : Natural := 0;
      Since             : Ada_Quality_Summary.Criteria.Date_Bound;
      Until_Date        : Ada_Quality_Summary.Criteria.Date_Bound;
      Gate              : Ada_Quality_Summary.Criteria.Gate_Counts := [others => 0];
   end record;
   --  Report data; fields not used by a report kind keep their defaults.
   --  @field Metadata Provenance.
   --  @field Filter Population selection.
   --  @field Database_Label Database path shown by terminal output only.
   --  @field Limit Requested row limit, or zero.
   --  @field Portfolio Project rows (after limit) and totals (before limit).
   --  @field Row_Count Rows before the limit.
   --  @field Common Indicators violated by at least one project, most frequent first.
   --  @field Indicators Indicator aggregates.
   --  @field Indicator Selected indicator aggregate.
   --  @field Indicator_Rows Per-project results for the selected indicator.
   --  @field Project Selected project row.
   --  @field Has_Assessment Whether the selected project has a current assessment.
   --  @field Assessment Current assessment of the selected project.
   --  @field Findings Finding occurrences (after limit).
   --  @field Finding_Total Findings before the limit.
   --  @field Finding_Projects Projects with findings.
   --  @field By_Severity Findings per severity.
   --  @field Groups Findings per indicator.
   --  @field Waivers Review-waiver findings (after limit).
   --  @field Waiver_Total Waivers before the limit.
   --  @field Waiver_Projects Projects with waivers.
   --  @field Waiver_Groups Waivers per indicator.
   --  @field Regressions Regressions (after limit).
   --  @field Regression_Total Regressions before the limit.
   --  @field By_Kind Regressions per classification.
   --  @field Projects_Affected Projects with regressions.
   --  @field Baselines Baseline selection per project.
   --  @field Pair The two assessments a compare report compares.
   --  @field History Runs (after limit).
   --  @field Completed_Count Completed runs.
   --  @field Running_Count Running runs.
   --  @field Interrupted_Count Interrupted runs.
   --  @field Invalid_Count Invalid runs.
   --  @field Series Numeric series.
   --  @field Excluded_Observations Excluded observations summed over Series.
   --  @field Daily Daily last-known-state snapshots.
   --  @field Undated Runs or observations without timestamps excluded by a date filter.
   --  @field Since First included UTC day.
   --  @field Until_Date Last included UTC day.
   --  @field Gate How often each `--fail-on` condition holds: regressions of the compared projects, and selected
   --  projects that have violations, are incomplete, or are unassessed. For compare: the pair's regressions, and
   --  whether its current run has violations or is incomplete, which a run that did not complete is; a chosen run is
   --  never unassessed. Regressions are counted only when they were compared, which `--fail-on regressions`
   --  requests.

   function Build
     (Data : Ada_Quality_Summary.Repository.Snapshot; Invocation : Ada_Quality_Summary.Options.Options;
      Database_Label : String) return Report;
   --  Build the complete report selected by an invocation.
   --  @param Data Snapshot.
   --  @param Invocation Validated report options.
   --  @param Database_Label Database path for terminal headings.
   --  @return Report.
   --  @exception Argument_Error A PROJECT, indicator, or assessment argument cannot be resolved.
end Ada_Quality_Summary.Reports;
