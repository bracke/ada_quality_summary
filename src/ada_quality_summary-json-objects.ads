with Ada.Strings.Unbounded;
with Ada_Quality.Reporting;
with Ada_Quality.Types;
with Ada_Quality_Summary.Criteria;
with Ada_Quality_Summary.Model;
with Ada_Quality_Summary.Reports;
with Jsonlib.Documents;

--  The JSON objects several reports share, built into a caller's document: values, projects, totals, indicator
--  aggregates and results, measurements, findings, regressions, baselines, and runs.
private package Ada_Quality_Summary.JSON.Objects is
   --  Shared JSON objects of the report family.
   use Ada_Quality.Types;
   use Ada_Quality_Summary.Model;
   use Jsonlib.Documents;

   function Int (Doc : in out Document; Value : Long_Long_Integer) return Node;
   --  Return a JSON integer.
   --  @param Doc Document the node belongs to.
   --  @param Value Integer.
   --  @return Node.

   function Nat (Doc : in out Document; Value : Natural) return Node;
   --  Return a JSON count.
   --  @param Doc Document the node belongs to.
   --  @param Value Count.
   --  @return Node.

   function Str (Doc : in out Document; Value : String) return Node;
   --  Return a JSON string.
   --  @param Doc Document the node belongs to.
   --  @param Value Text.
   --  @return Node.

   function Str (Doc : in out Document; Value : Ada.Strings.Unbounded.Unbounded_String) return Node;
   --  Return a JSON string.
   --  @param Doc Document the node belongs to.
   --  @param Value Text.
   --  @return Node.

   function Bool (Doc : in out Document; Value : Boolean) return Node;
   --  Return a JSON Boolean.
   --  @param Doc Document the node belongs to.
   --  @param Value Boolean.
   --  @return Node.

   function Null_Value (Doc : in out Document) return Node;
   --  Return a JSON null.
   --  @param Doc Document the node belongs to.
   --  @return Node.

   function Id_Or_Null (Doc : in out Document; Value : Natural) return Node;
   --  Return an optional identity: null for the absent sentinel zero.
   --  @param Doc Document the node belongs to.
   --  @param Value Identity, or zero.
   --  @return Node.

   function Time_Or_Null (Doc : in out Document; Value : Ada_Quality.Reporting.Optional_Timestamp) return Node;
   --  Return an optional timestamp: an ISO 8601 UTC string, or null.
   --  @param Doc Document the node belongs to.
   --  @param Value Timestamp.
   --  @return Node.

   function Date_Or_Null (Doc : in out Document; Value : Criteria.Date_Bound) return Node;
   --  Return an optional UTC day: `YYYY-MM-DD`, or null.
   --  @param Doc Document the node belongs to.
   --  @param Value Day bound.
   --  @return Node.

   procedure Put (Doc : in out Document; Object : Node; Name : String; Value : Node);
   --  Add a member to an object.
   --  @param Doc Document the node belongs to.
   --  @param Object Object.
   --  @param Name Member name.
   --  @param Value Member value.

   procedure Put_Totals (Doc : in out Document; Object : Node; Totals : Indicator_Totals; With_Missing : Boolean);
   --  Add indicator state counts to an object; only cross-project aggregates report missing results.
   --  @param Doc Document the node belongs to.
   --  @param Object Object.
   --  @param Totals Counts.
   --  @param With_Missing Whether to add `missing`.

   function Indicator_Totals_Object (Doc : in out Document; Totals : Indicator_Totals) return Node;
   --  Return indicator state counts of one assessment.
   --  @param Doc Document the node belongs to.
   --  @param Totals Counts.
   --  @return Node.

   procedure Put_Provenance
     (Doc : in out Document; Object : Node; Source, Policy, Toolchain : Ada.Strings.Unbounded.Unbounded_String;
      Started_At, Finished_At : Ada_Quality.Reporting.Optional_Timestamp);
   --  Add the fingerprints and timestamps of one assessment to an object.
   --  @param Doc Document the node belongs to.
   --  @param Object Object.
   --  @param Source Source fingerprint.
   --  @param Policy Policy fingerprint.
   --  @param Toolchain Toolchain fingerprint.
   --  @param Started_At Start time.
   --  @param Finished_At Terminal time.

   function Project_Object (Doc : in out Document; Project : Project_Summary) return Node;
   --  Return a project row.
   --  @param Doc Document the node belongs to.
   --  @param Project Project.
   --  @return Node.

   function Projects_Array (Doc : in out Document; Projects : Model.Project_Vectors.Vector) return Node;
   --  Return project rows in order.
   --  @param Doc Document the node belongs to.
   --  @param Projects Projects.
   --  @return Node.

   function Totals_Object (Doc : in out Document; Totals : Portfolio_Totals) return Node;
   --  Return portfolio totals.
   --  @param Doc Document the node belongs to.
   --  @param Totals Totals.
   --  @return Node.

   function Indicator_Summary_Object (Doc : in out Document; Indicator : Indicator_Summary) return Node;
   --  Return a cross-project indicator aggregate.
   --  @param Doc Document the node belongs to.
   --  @param Indicator Aggregate.
   --  @return Node.

   function Measurement_Object (Doc : in out Document; Id : Indicator_Id; Value : Measurement_Value) return Node;
   --  Return a measurement in its tagged form.
   --  @param Doc Document the node belongs to.
   --  @param Id Measured indicator.
   --  @param Value Measurement.
   --  @return Node.

   function Finding_Object (Doc : in out Document; Finding : Finding_Summary) return Node;
   --  Return a finding.
   --  @param Doc Document the node belongs to.
   --  @param Finding Finding.
   --  @return Node.

   function Findings_Array (Doc : in out Document; Findings : Finding_Summary_Vectors.Vector) return Node;
   --  Return findings in order.
   --  @param Doc Document the node belongs to.
   --  @param Findings Findings.
   --  @return Node.

   function Result_Object (Doc : in out Document; Project_Id, Run_Id : Positive; Result : Indicator_Result) return Node;
   --  Return an indicator result with its findings.
   --  @param Doc Document the node belongs to.
   --  @param Project_Id Owning project.
   --  @param Run_Id Owning assessment.
   --  @param Result Result.
   --  @return Node.

   function Kind_Counts_Object (Doc : in out Document; Counts : Ada_Quality_Summary.Reports.Kind_Counts) return Node;
   --  Return regressions per classification.
   --  @param Doc Document the node belongs to.
   --  @param Counts Counts.
   --  @return Node.

   function Regression_Object (Doc : in out Document; Change : Regression_Summary) return Node;
   --  Return a regression.
   --  @param Doc Document the node belongs to.
   --  @param Change Regression.
   --  @return Node.

   function Regressions_Array (Doc : in out Document; Changes : Regression_Summary_Vectors.Vector) return Node;
   --  Return regressions in order.
   --  @param Doc Document the node belongs to.
   --  @param Changes Regressions.
   --  @return Node.

   function Baseline_Object (Doc : in out Document; Info : Baseline_Info) return Node;
   --  Return a baseline selection with its skipped runs.
   --  @param Doc Document the node belongs to.
   --  @param Info Baseline selection.
   --  @return Node.

   function Run_Object (Doc : in out Document; Run : History_Summary) return Node;
   --  Return a run of a project history.
   --  @param Doc Document the node belongs to.
   --  @param Run Run.
   --  @return Node.
end Ada_Quality_Summary.JSON.Objects;
