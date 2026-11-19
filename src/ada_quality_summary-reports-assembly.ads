with Ada.Containers.Ordered_Maps;
with Ada_Quality_Summary.Model;
with Ada_Quality_Summary.Options;
with Ada_Quality_Summary.Repository;

--  The steps that build a report, each over an explicit Context: start the report, select the projects, compare them
--  with their baselines, fill the fields of the report kind, and count the --fail-on conditions.
private package Ada_Quality_Summary.Reports.Assembly is
   --  The steps that build a report.

   type Comparison is record
      Baseline : Ada_Quality_Summary.Model.Baseline_Info;
      Changes  : Ada_Quality_Summary.Model.Regression_Summary_Vectors.Vector;
   end record;
   --  One project's baseline comparison, made at most once per report.
   --  @field Baseline Baseline selection.
   --  @field Changes Regressions against the baseline.

   package Comparison_Maps is new Ada.Containers.Ordered_Maps (Positive, Comparison);
   --  Comparisons by project identity.

   type Context is record
      Item     : Report;
      Selected : Ada_Quality_Summary.Model.Project_Vectors.Vector;
      Compared : Comparison_Maps.Map;
   end record;
   --  A report under construction.
   --  @field Item Report.
   --  @field Selected Selected projects, before any row limit.
   --  @field Compared Baseline comparisons made so far.

   procedure Start
     (Data           : Ada_Quality_Summary.Repository.Snapshot;
      Invocation     : Ada_Quality_Summary.Options.Options;
      Database_Label : String;
      State          : in out Context);
   --  Fill the provenance and the population filter.
   --  @param Data Snapshot.
   --  @param Invocation Validated report options.
   --  @param Database_Label Database path for terminal headings.
   --  @param State Report under construction.
   --  @exception Argument_Error The --project argument cannot be resolved.

   procedure Select_Projects
     (Data : Ada_Quality_Summary.Repository.Snapshot; Invocation : Ada_Quality_Summary.Options.Options;
      State : in out Context);
   --  Select the reported projects: the target of a detail command, the owner of a compared pair, or the filtered
   --  population; compare reports also classify the pair here.
   --  @param Data Snapshot.
   --  @param Invocation Validated report options.
   --  @param State Report under construction.
   --  @exception Argument_Error A PROJECT or assessment argument cannot be resolved.

   procedure Compare_Selected
     (Data : Ada_Quality_Summary.Repository.Snapshot; Invocation : Ada_Quality_Summary.Options.Options;
      State : in out Context);
   --  Compare each selected project with its baseline once, for the reports that show regressions or their counts
   --  and when --fail-on regressions is requested.
   --  @param Data Snapshot.
   --  @param Invocation Validated report options.
   --  @param State Report under construction.

   procedure Summarize_Population (State : in out Context);
   --  Record the selected population: its size and the portfolio rows and totals.
   --  @param State Report under construction.

   procedure Fill_Command
     (Data : Ada_Quality_Summary.Repository.Snapshot; Invocation : Ada_Quality_Summary.Options.Options;
      State : in out Context);
   --  Fill the fields the report kind renders, sorted and limited.
   --  @param Data Snapshot.
   --  @param Invocation Validated report options.
   --  @param State Report under construction.
   --  @exception Argument_Error An indicator argument cannot be resolved.

   procedure Count_Gate (Invocation : Ada_Quality_Summary.Options.Options; State : in out Context);
   --  Count how often each --fail-on condition holds.
   --  @param Invocation Validated report options.
   --  @param State Report under construction.
end Ada_Quality_Summary.Reports.Assembly;
