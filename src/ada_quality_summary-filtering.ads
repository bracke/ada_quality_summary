with Ada_Quality.Reporting;
with Ada_Quality.Types;
with Ada_Quality_Summary.Model;
with Ada_Quality_Summary.Options;
with Ada_Quality_Summary.Repository;

--  Exact project and indicator resolution, population selection, and deterministic sorting.
--
--  Filters are applied before sorting and limiting. Every ordering ends with a unique identity tie-breaker, so
--  results never depend on container insertion order.
package Ada_Quality_Summary.Filtering is
   --  Exact project and indicator resolution, population selection, deterministic sorting, and row limiting.

   type Selection is record
      Include_Removed : Boolean := False;
      Enabled_Only    : Boolean := False;
      Project_Id      : Natural := 0;
      Has_Status      : Boolean := False;
      Status          : Ada_Quality_Summary.Model.Project_Quality_State := Ada_Quality_Summary.Model.Passing;
   end record;
   --  Project population filter.
   --  @field Include_Removed Whether tombstones are included.
   --  @field Enabled_Only Whether only enabled projects are included.
   --  @field Project_Id Single selected project, or zero for every project.
   --  @field Has_Status Whether the quality-state filter applies.
   --  @field Status Required quality state.

   function Resolve_Project
     (Data : Ada_Quality_Summary.Repository.Snapshot; Text : String; Include_Removed : Boolean) return Positive;
   --  Resolve PROJECT as an exact positive identity, otherwise as an exact case-sensitive directory basename.
   --  @param Data Snapshot.
   --  @param Text PROJECT argument.
   --  @param Include_Removed Whether tombstones may match.
   --  @return Project identity.
   --  @exception Argument_Error No project, or more than one project, matches.

   function Resolve_Indicator (Text : String) return Ada_Quality.Types.Indicator_Id;
   --  Resolve an exact indicator identifier such as `TST-03`.
   --  @param Text Identifier.
   --  @return Indicator.
   --  @exception Argument_Error Text is not a registered identifier.

   function Population
     (Data : Ada_Quality_Summary.Repository.Snapshot; Filter : Selection)
      return Ada_Quality.Reporting.Project_Vectors.Vector;
   --  Return registry entries matching the removal, enabled, and project filters, in identity order.
   --  @param Data Snapshot.
   --  @param Filter Selection.
   --  @return Selected registry entries.

   function Basename (Path : String) return String;
   --  Return the final path component.
   --  @param Path Project path.
   --  @return Directory basename.

   procedure Sort_Projects
     (Items : in out Ada_Quality_Summary.Model.Project_Vectors.Vector;
      Key : Ada_Quality_Summary.Options.Sort_Key; Overview : Boolean; Reverse_Order : Boolean);
   --  Order project rows; the default is quality priority for the overview and name otherwise.
   --  @param Items Rows.
   --  @param Key Sort key.
   --  @param Overview Whether the summary default applies.
   --  @param Reverse_Order Whether to reverse the ordering.

   procedure Sort_Indicators
     (Items : in out Ada_Quality_Summary.Model.Indicator_Summary_Vectors.Vector;
      Key : Ada_Quality_Summary.Options.Sort_Key; Reverse_Order : Boolean);
   --  Order indicator aggregates; the default is registry order.
   --  @param Items Aggregates.
   --  @param Key Sort key.
   --  @param Reverse_Order Whether to reverse the ordering.

   procedure Sort_Common (Items : in out Ada_Quality_Summary.Model.Indicator_Summary_Vectors.Vector);
   --  Order common violations by descending violating projects, then registry order.
   --  @param Items Aggregates.

   procedure Sort_Findings
     (Items : in out Ada_Quality_Summary.Model.Finding_Summary_Vectors.Vector;
      Key : Ada_Quality_Summary.Options.Sort_Key; Reverse_Order : Boolean);
   --  Order findings; the default is severity descending, then indicator, project, and fingerprint.
   --  @param Items Findings.
   --  @param Key Sort key.
   --  @param Reverse_Order Whether to reverse the ordering.

   procedure Sort_Regressions
     (Items : in out Ada_Quality_Summary.Model.Regression_Summary_Vectors.Vector;
      Key : Ada_Quality_Summary.Options.Sort_Key; Reverse_Order : Boolean);
   --  Order regressions; the default is project, then indicator and kind.
   --  @param Items Regressions.
   --  @param Key Sort key.
   --  @param Reverse_Order Whether to reverse the ordering.

   procedure Sort_History
     (Items : in out Ada_Quality_Summary.Model.History_Summary_Vectors.Vector; Reverse_Order : Boolean);
   --  Order runs by descending identity.
   --  @param Items Runs.
   --  @param Reverse_Order Whether to reverse the ordering.

   procedure Sort_Points
     (Items : in out Ada_Quality_Summary.Model.Trend_Point_Vectors.Vector;
      Key : Ada_Quality_Summary.Options.Sort_Key; Reverse_Order : Boolean);
   --  Order trend observations by run identity, then project; or by project, then run.
   --  @param Items Observations.
   --  @param Key Sort key.
   --  @param Reverse_Order Whether to reverse the ordering.
end Ada_Quality_Summary.Filtering;
