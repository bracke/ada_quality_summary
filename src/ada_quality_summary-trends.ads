with Ada.Containers.Vectors;
with Ada_Quality.Types;
with Ada_Quality_Summary.Model;
with Ada_Quality_Summary.Options;
with Ada_Quality_Summary.Repository;

--  Thin adapter over Ada_Quality.History: baseline selection, regression comparison, histories, and metric trends.
--
--  Every compatibility and classification decision is delegated to Ada_Quality.History. This package adds the
--  owning project identity, explanations for skipped predecessors, and reporting filters.
package Ada_Quality_Summary.Trends is
   --  Thin adapter over Ada_Quality.History.

   type Baseline_Status is (No_Current_Assessment, No_Baseline, Compared);
   --  Outcome of baseline selection for one project.
   --  @enum No_Current_Assessment The project has no completed assessment.
   --  @enum No_Baseline No earlier compatible completed assessment exists.
   --  @enum Compared The current assessment was compared with its compatible baseline.

   function Image (Status : Baseline_Status) return String;
   --  Return the stable spelling.
   --  @param Status Baseline status.
   --  @return `no_current_assessment`, `no_baseline`, or `compared`.

   type Exclusion_Reason is (Missing_Source_Fingerprint, Policy_Changed, Toolchain_Changed);
   --  Why Ada_Quality.History.Compatible rejected an earlier completed assessment.
   --  @enum Missing_Source_Fingerprint A source fingerprint is absent.
   --  @enum Policy_Changed The policy fingerprint differs or is absent.
   --  @enum Toolchain_Changed The toolchain fingerprint differs or is absent.

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
      Excluded        : Excluded_Run_Vectors.Vector;
   end record;
   --  Baseline selection for one project.
   --  @field Project_Id Project.
   --  @field Status Outcome.
   --  @field Current_Run_Id Current completed assessment, or zero.
   --  @field Baseline_Run_Id Selected baseline, or zero.
   --  @field Excluded Incompatible completed assessments newer than the baseline.

   package Baseline_Info_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Baseline_Info);
   --  Baseline selections.

   procedure Regressions
     (Data       : Ada_Quality_Summary.Repository.Snapshot;
      Project_Id : Positive;
      Baseline   : out Baseline_Info;
      Changes    : out Ada_Quality_Summary.Model.Regression_Summary_Vectors.Vector);
   --  Compare a project's current assessment with its compatible baseline.
   --  @param Data Snapshot.
   --  @param Project_Id Project.
   --  @param Baseline Baseline selection.
   --  @param Changes Regressions classified by Ada_Quality.History.Compare.

   function History
     (Data : Ada_Quality_Summary.Repository.Snapshot; Project_Id : Positive;
      Since, Until_Date : Ada_Quality_Summary.Options.Date_Bound; Undated : out Natural)
      return Ada_Quality_Summary.Model.History_Summary_Vectors.Vector;
   --  Return a project's runs, classified when completed, in ascending identity order.
   --  @param Data Snapshot.
   --  @param Project_Id Project.
   --  @param Since Earliest included instant.
   --  @param Until_Date Exclusive latest instant.
   --  @param Undated Runs without a persisted timestamp excluded by a date filter.
   --  @return Runs.

   function Metric_Series
     (Data       : Ada_Quality_Summary.Repository.Snapshot;
      Projects   : Ada_Quality_Summary.Model.Project_Vectors.Vector;
      Indicator  : Ada_Quality.Types.Indicator_Id;
      Since, Until_Date : Ada_Quality_Summary.Options.Date_Bound;
      Undated    : in out Natural) return Ada_Quality_Summary.Model.Trend_Summary;
   --  Build one numeric series from Ada_Quality.History.Metric_Trend, per project, against its current assessment.
   --  @param Data Snapshot.
   --  @param Projects Selected projects.
   --  @param Indicator Numeric indicator.
   --  @param Since Earliest included instant.
   --  @param Until_Date Exclusive latest instant.
   --  @param Undated Incremented for observations without a timestamp excluded by a date filter.
   --  @return Series.

   type State_Snapshot is record
      Day        : Ada_Quality_Summary.Model.UString;
      Totals     : Ada_Quality_Summary.Model.Portfolio_Totals;
   end record;
   --  Last-known-state classification of the population at the end of one UTC day.
   --  @field Day UTC date `YYYY-MM-DD`.
   --  @field Totals Classification counts and indicator totals.

   package State_Snapshot_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => State_Snapshot);
   --  Daily snapshots in ascending date order.

   function Daily_States
     (Data : Ada_Quality_Summary.Repository.Snapshot;
      Projects : Ada_Quality_Summary.Model.Project_Vectors.Vector;
      Since, Until_Date : Ada_Quality_Summary.Options.Date_Bound) return State_Snapshot_Vectors.Vector;
   --  Classify the population at the end of each UTC day on which a dated completed assessment finished.
   --  @param Data Snapshot.
   --  @param Projects Selected projects.
   --  @param Since Earliest included instant.
   --  @param Until_Date Exclusive latest instant.
   --  @return Snapshots; projects without a dated completed assessment by that day count as unassessed.
end Ada_Quality_Summary.Trends;
