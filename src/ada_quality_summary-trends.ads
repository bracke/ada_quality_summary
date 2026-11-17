with Ada_Quality.Types;
with Ada_Quality_Summary.Model;
with Ada_Quality_Summary.Criteria;
with Ada_Quality_Summary.Repository;

--  Thin adapter over Ada_Quality.History: baseline selection, regression comparison, histories, and metric trends.
--
--  Every baseline, compatibility, and classification decision is delegated to Ada_Quality.History, which the
--  Ada Quality `regressions` command uses too. This package adds the owning project identity, explanations for
--  skipped predecessors, and reporting filters.
package Ada_Quality_Summary.Trends is
   --  Thin adapter over Ada_Quality.History.

   procedure Regressions
     (Data       : Ada_Quality_Summary.Repository.Snapshot;
      Project_Id : Positive;
      Baseline   : out Ada_Quality_Summary.Model.Baseline_Info;
      Changes    : out Ada_Quality_Summary.Model.Regression_Summary_Vectors.Vector);
   --  Compare a project's current assessment with the baseline Ada_Quality.History.Select_Comparison selects.
   --  @param Data Snapshot.
   --  @param Project_Id Project.
   --  @param Baseline Baseline selection.
   --  @param Changes Regressions classified by Ada_Quality.History.Compare.

   function History
     (Data : Ada_Quality_Summary.Repository.Snapshot; Project_Id : Positive;
      Since, Until_Date : Ada_Quality_Summary.Criteria.Date_Bound; Undated : out Natural)
      return Ada_Quality_Summary.Model.History_Summary_Vectors.Vector;
   --  Return a project's runs, classified when completed, in ascending identity order.
   --  @param Data Snapshot.
   --  @param Project_Id Project.
   --  @param Since First included UTC day.
   --  @param Until_Date Last included UTC day.
   --  @param Undated Runs without a persisted timestamp excluded by a date filter.
   --  @return Runs.

   function Metric_Series
     (Data       : Ada_Quality_Summary.Repository.Snapshot;
      Projects   : Ada_Quality_Summary.Model.Project_Vectors.Vector;
      Indicator  : Ada_Quality.Types.Indicator_Id;
      Since, Until_Date : Ada_Quality_Summary.Criteria.Date_Bound) return Ada_Quality_Summary.Model.Trend_Summary;
   --  Build one numeric series from Ada_Quality.History.Metric_Trend, per project, against its current assessment.
   --  The series kind is the indicator's measurement kind, also when no observation is included; observations of
   --  another kind are excluded and counted.
   --  @param Data Snapshot.
   --  @param Projects Selected projects.
   --  @param Indicator Numeric indicator.
   --  @param Since First included UTC day.
   --  @param Until_Date Last included UTC day.
   --  @return Series.

   function Undated_Runs
     (Data : Ada_Quality_Summary.Repository.Snapshot;
      Projects : Ada_Quality_Summary.Model.Project_Vectors.Vector;
      Since, Until_Date : Ada_Quality_Summary.Criteria.Date_Bound) return Natural;
   --  Count the completed runs a date filter excludes because they have no persisted timestamp.
   --  @param Data Snapshot.
   --  @param Projects Selected projects.
   --  @param Since First included UTC day.
   --  @param Until_Date Last included UTC day.
   --  @return Undated completed runs of Projects, or zero without a date filter.

   function Daily_States
     (Data : Ada_Quality_Summary.Repository.Snapshot;
      Projects : Ada_Quality_Summary.Model.Project_Vectors.Vector;
      Since, Until_Date : Ada_Quality_Summary.Criteria.Date_Bound)
      return Ada_Quality_Summary.Model.State_Snapshot_Vectors.Vector;
   --  Classify the population at the end of each UTC day on which a dated completed assessment finished.
   --
   --  Each project counts with its latest completed assessment at or before the end of the day. Legacy runs without
   --  a timestamp were completed before the schema migration that started recording timestamps, and every snapshot
   --  day is the day a dated run finished, so a legacy run precedes every snapshot day; no date is inferred for it.
   --  @param Data Snapshot.
   --  @param Projects Selected projects.
   --  @param Since First included UTC day.
   --  @param Until_Date Last included UTC day.
   --  @return Snapshots; projects without a completed assessment by that day count as unassessed.
end Ada_Quality_Summary.Trends;
