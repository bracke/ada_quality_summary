with Ada_Quality.Reporting;
with Ada_Quality.Types;
with Ada_Quality_Summary.Model;
with Ada_Quality_Summary.Repository;
with Ada_Quality_Summary.Rules;

--  Deterministic, side-effect-free aggregation of a snapshot into report records.
--
--  Every function depends only on its arguments; reordering source records never changes a total.
package Ada_Quality_Summary.Aggregation is
   --  Deterministic, side-effect-free aggregation of a snapshot into report records.

   function Build_Project
     (Data : Ada_Quality_Summary.Repository.Snapshot; Project : Ada_Quality.Reporting.Project_Record)
      return Ada_Quality_Summary.Model.Project_Summary;
   --  Classify and count one registered project.
   --  @param Data Snapshot.
   --  @param Project Registry entry.
   --  @return Project row.

   function Build_Projects
     (Data : Ada_Quality_Summary.Repository.Snapshot; Population : Ada_Quality.Reporting.Project_Vectors.Vector)
      return Ada_Quality_Summary.Model.Project_Vectors.Vector;
   --  Build project rows in identity order.
   --  @param Data Snapshot.
   --  @param Population Selected registry entries.
   --  @return Project rows.

   function Build_Totals
     (Projects : Ada_Quality_Summary.Model.Project_Vectors.Vector) return Ada_Quality_Summary.Model.Portfolio_Totals;
   --  Sum project rows into portfolio totals.
   --  @param Projects Project rows.
   --  @return Totals.

   function Build_Portfolio
     (Data : Ada_Quality_Summary.Repository.Snapshot; Projects : Ada_Quality_Summary.Model.Project_Vectors.Vector)
      return Ada_Quality_Summary.Model.Portfolio_Summary;
   --  Combine project rows and their totals.
   --  @param Data Snapshot.
   --  @param Projects Selected project rows.
   --  @return Portfolio.

   type Indicator_State is new Ada_Quality_Summary.Rules.Result_State;
   --  One project's state for one indicator. The literals and their meaning are those of
   --  Ada_Quality_Summary.Rules.Result_State.

   function Image (State : Indicator_State) return String;
   --  Return the stable spelling.
   --  @param State State.
   --  @return `pass`, `violation`, `unknown`, `not_applicable`, or `missing`.

   function State_Of
     (Data : Ada_Quality_Summary.Repository.Snapshot; Project : Ada_Quality_Summary.Model.Project_Summary;
      Indicator : Ada_Quality.Types.Indicator_Id) return Indicator_State;
   --  Return a project's state for one indicator.
   --  @param Data Snapshot.
   --  @param Project Project row.
   --  @param Indicator Indicator.
   --  @return State.

   function Build_Indicator
     (Data : Ada_Quality_Summary.Repository.Snapshot; Projects : Ada_Quality_Summary.Model.Project_Vectors.Vector;
      Indicator : Ada_Quality.Types.Indicator_Id) return Ada_Quality_Summary.Model.Indicator_Summary;
   --  Aggregate one indicator over the selected projects.
   --  @param Data Snapshot.
   --  @param Projects Project rows.
   --  @param Indicator Indicator.
   --  @return Aggregate whose five counts sum to the project count.

   function Build_Indicators
     (Data : Ada_Quality_Summary.Repository.Snapshot; Projects : Ada_Quality_Summary.Model.Project_Vectors.Vector)
      return Ada_Quality_Summary.Model.Indicator_Summary_Vectors.Vector;
   --  Aggregate all 33 indicators in registry order.
   --  @param Data Snapshot.
   --  @param Projects Project rows.
   --  @return Aggregates.

   function Build_Findings
     (Data : Ada_Quality_Summary.Repository.Snapshot; Projects : Ada_Quality_Summary.Model.Project_Vectors.Vector)
      return Ada_Quality_Summary.Model.Finding_Summary_Vectors.Vector;
   --  Collect persisted findings of every current assessment; repeated fingerprints stay separate occurrences.
   --  @param Data Snapshot.
   --  @param Projects Project rows.
   --  @return Findings in project, indicator, and stored order.

   function Findings_Of
     (Project_Id : Positive; Value : Ada_Quality.Reporting.Assessment_Record)
      return Ada_Quality_Summary.Model.Finding_Summary_Vectors.Vector;
   --  Collect the findings of one decoded assessment.
   --  @param Project_Id Owning project.
   --  @param Value Assessment.
   --  @return Findings in indicator and stored order.
end Ada_Quality_Summary.Aggregation;
