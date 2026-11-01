with Ada.Containers.Vectors;
with Ada_Quality.History;
with Ada_Quality.Reporting;
with Ada_Quality.Types;
with Ada_Quality_Summary.Aggregation;
with Ada_Quality_Summary.Filtering;
with Ada_Quality_Summary.Model;
with Ada_Quality_Summary.Options;
with Ada_Quality_Summary.Repository;
with Ada_Quality_Summary.Trends;

--  Complete typed data of one report, built before any rendering and shared by the terminal and JSON renderers.
package Ada_Quality_Summary.Reports is
   --  Complete typed data of one report, built before any rendering.
   subtype UString is Ada_Quality_Summary.Model.UString;
   --  Dynamically sized text.

   type Indicator_Row is record
      Project    : Ada_Quality_Summary.Model.Project_Summary;
      State      : Ada_Quality_Summary.Aggregation.Indicator_State;
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

   type Severity_Counts is array (Ada_Quality.Types.Severity) of Natural;
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

   type Kind_Counts is array (Ada_Quality.History.Regression_Kind) of Natural;
   --  Regressions per classification.

   type Report is record
      Metadata          : Ada_Quality_Summary.Model.Report_Metadata;
      Filter            : Ada_Quality_Summary.Filtering.Selection;
      Layout            : Ada_Quality_Summary.Options.Layout_Mode := Ada_Quality_Summary.Options.Normal_Layout;
      Database_Label    : UString;
      Limit             : Natural := 0;
      Portfolio         : Ada_Quality_Summary.Model.Portfolio_Summary;
      Row_Count         : Natural := 0;
      Common            : Ada_Quality_Summary.Model.Indicator_Summary_Vectors.Vector;
      Indicators        : Ada_Quality_Summary.Model.Indicator_Summary_Vectors.Vector;
      Indicator         : Ada_Quality_Summary.Model.Indicator_Summary;
      Indicator_Rows    : Indicator_Row_Vectors.Vector;
      Project           : Ada_Quality_Summary.Model.Project_Summary;
      Has_Assessment    : Boolean := False;
      Assessment        : Ada_Quality.Reporting.Assessment_Record;
      Findings          : Ada_Quality_Summary.Model.Finding_Summary_Vectors.Vector;
      Finding_Total     : Natural := 0;
      Finding_Projects  : Natural := 0;
      By_Severity       : Severity_Counts := [others => 0];
      Groups            : Finding_Group_Vectors.Vector;
      Regressions       : Ada_Quality_Summary.Model.Regression_Summary_Vectors.Vector;
      Regression_Total  : Natural := 0;
      By_Kind           : Kind_Counts := [others => 0];
      Projects_Affected : Natural := 0;
      Baselines         : Ada_Quality_Summary.Trends.Baseline_Info_Vectors.Vector;
      History           : Ada_Quality_Summary.Model.History_Summary_Vectors.Vector;
      Completed_Count   : Natural := 0;
      Running_Count     : Natural := 0;
      Interrupted_Count : Natural := 0;
      Invalid_Count     : Natural := 0;
      Series            : Ada_Quality_Summary.Model.Trend_Summary_Vectors.Vector;
      Daily             : Ada_Quality_Summary.Trends.State_Snapshot_Vectors.Vector;
      Undated           : Natural := 0;
      Since             : Ada_Quality_Summary.Options.Date_Bound;
      Until_Date        : Ada_Quality_Summary.Options.Date_Bound;
   end record;
   --  Report data; fields not used by a report kind keep their defaults.
   --  @field Metadata Provenance.
   --  @field Filter Population selection.
   --  @field Layout Terminal layout.
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
   --  @field Regressions Regressions (after limit).
   --  @field Regression_Total Regressions before the limit.
   --  @field By_Kind Regressions per classification.
   --  @field Projects_Affected Projects with regressions.
   --  @field Baselines Baseline selection per project.
   --  @field History Runs (after limit).
   --  @field Completed_Count Completed runs.
   --  @field Running_Count Running runs.
   --  @field Interrupted_Count Interrupted runs.
   --  @field Invalid_Count Invalid runs.
   --  @field Series Numeric series.
   --  @field Daily Daily last-known-state snapshots.
   --  @field Undated Runs or observations without timestamps excluded by a date filter.
   --  @field Since Earliest included instant.
   --  @field Until_Date Exclusive latest instant.

   function Build
     (Data : Ada_Quality_Summary.Repository.Snapshot; Invocation : Ada_Quality_Summary.Options.Options;
      Database_Label : String) return Report;
   --  Build the complete report selected by an invocation.
   --  @param Data Snapshot.
   --  @param Invocation Validated report options.
   --  @param Database_Label Database path for terminal headings.
   --  @return Report.
   --  @exception Argument_Error A PROJECT or indicator argument cannot be resolved.
end Ada_Quality_Summary.Reports;
