with Ada.Containers.Ordered_Maps;
with Ada.Containers.Vectors;
with Ada.Finalization;
with Ada.Strings.Unbounded;
with Ada_Quality.Reporting;
with Ada_Quality.Storage;
with Ada_Quality.Types;
with Ada_Quality_Summary.Limits;
with Ada_Quality_Summary.Model;

--  Coherent, read-only, in-memory database snapshot for one report invocation.
--
--  Load reads every required row in one read transaction through Ada_Quality.Reporting and releases the
--  database before returning. A Snapshot never holds a database handle, cursor, or lock; every query below is a
--  pure function of the loaded data. Facts memoizes the per-run summaries derived from that data, so each completed
--  assessment is decoded at most once per snapshot however many reports, days, or series consult it.
package Ada_Quality_Summary.Repository is
   --  Coherent, read-only, in-memory database snapshot for one report invocation.
   subtype UString is Ada.Strings.Unbounded.Unbounded_String;
   --  Dynamically sized text.

   type Repository is limited private;
   --  Selected database and resource limits.

   type Snapshot is limited private;
   --  Immutable loaded data.

   package Id_Vectors is new Ada.Containers.Vectors (Index_Type => Positive, Element_Type => Positive);
   --  Ordered identities.

   Default_Busy_Deadline : constant Duration := 1.0;
   --  How long Load waits for a writer to release the database before failing as busy.

   procedure Open
     (Item          : in out Repository;
      Path          : String;
      Limits        : Ada_Quality.Reporting.Load_Limits := Ada_Quality_Summary.Limits.Default_Load;
      Busy_Deadline : Duration := Default_Busy_Deadline);
   --  Select a database for loading.
   --  @param Item Repository.
   --  @param Path Database path.
   --  @param Limits Resource limits.
   --  @param Busy_Deadline Bounded wait for a writer holding the lock; zero fails immediately.

   procedure Close (Item : in out Repository);
   --  Forget the selected database.
   --  @param Item Repository.

   function Load (Item : in out Repository) return Snapshot;
   --  Load one coherent snapshot and decode every current completed assessment. While a writer holds the
   --  database, Load retries in an orderly way until the busy deadline expires.
   --  @param Item Opened repository.
   --  @return Snapshot.
   --  @exception Data_Error The database is missing, locked, unsupported, or corrupt.
   --  @exception Report_Error A resource limit is exceeded.

   function Schema_Version (Data : Snapshot) return Positive;
   --  Return the source database schema version.
   --  @param Data Snapshot.
   --  @return Schema version.

   function Identity (Data : Snapshot) return String;
   --  Return the snapshot digest.
   --  @param Data Snapshot.
   --  @return Deterministic identity.

   function Projects (Data : Snapshot; Include_Removed : Boolean) return Ada_Quality.Reporting.Project_Vectors.Vector;
   --  Return registry entries in ascending identity order.
   --  @param Data Snapshot.
   --  @param Include_Removed Whether tombstones are included.
   --  @return Projects.

   function Project (Data : Snapshot; Project_Id : Positive) return Ada_Quality.Reporting.Project_Record;
   --  Return one registry entry.
   --  @param Data Snapshot.
   --  @param Project_Id Registered project identity.
   --  @return Registry entry.

   function Runs (Data : Snapshot; Project_Id : Positive) return Ada_Quality.Reporting.Run_Vectors.Vector;
   --  Return all runs of a project in ascending identity order.
   --  @param Data Snapshot.
   --  @param Project_Id Project identity.
   --  @return Runs in every lifecycle state.

   function Run (Data : Snapshot; Run_Id : Positive) return Ada_Quality.Reporting.Run_Record;
   --  Return one run.
   --  @param Data Snapshot.
   --  @param Run_Id Existing run identity.
   --  @return Run metadata.

   function Current_Run (Data : Snapshot; Project_Id : Positive) return Natural;
   --  Return the latest completed assessment of a project.
   --  @param Data Snapshot.
   --  @param Project_Id Project identity.
   --  @return Run identity, or zero when no completed assessment exists.

   function Latest_Run (Data : Snapshot; Project_Id : Positive) return Natural;
   --  Return the most recent run of a project in any lifecycle state.
   --  @param Data Snapshot.
   --  @param Project_Id Project identity.
   --  @return Run identity, or zero when no run exists.

   function Assessment (Data : Snapshot; Run_Id : Positive) return Ada_Quality.Reporting.Assessment_Record;
   --  Return a decoded completed assessment, using the preloaded current assessments when possible.
   --  @param Data Snapshot.
   --  @param Run_Id Completed run identity.
   --  @return Decoded assessment.
   --  @exception Data_Error Stored evidence is corrupt.

   function Result_Of
     (Data : Snapshot; Run_Id : Positive; Indicator : Ada_Quality.Types.Indicator_Id)
      return Ada_Quality.Types.Indicator_Result;
   --  Return one result of a completed assessment without copying the whole assessment.
   --  @param Data Snapshot.
   --  @param Run_Id Completed run identity.
   --  @param Indicator Indicator.
   --  @return Persisted result.
   --  @exception Data_Error Stored evidence is corrupt.

   type Indicator_States is array (Ada_Quality.Types.Indicator_Id) of Ada_Quality_Summary.Model.Indicator_State;
   --  One state per indicator.

   type Value_Kinds is array (Ada_Quality.Types.Indicator_Id) of Ada_Quality.Types.Value_Kind;
   --  One measurement representation per indicator.

   type Indicator_Counts is array (Ada_Quality.Types.Indicator_Id) of Natural;
   --  One count per indicator.

   type Severity_Counts is array (Ada_Quality.Types.Severity) of Natural;
   --  One count per finding severity.

   type Run_Facts is record
      Totals                : Ada_Quality_Summary.Model.Indicator_Totals;
      Quality               : Ada_Quality_Summary.Model.Project_Quality_State := Ada_Quality_Summary.Model.Unassessed;
      States                : Indicator_States := [others => Ada_Quality_Summary.Model.Missing_State];
      Kinds                 : Value_Kinds := [others => Ada_Quality.Types.Unavailable_Value];
      Findings              : Natural := 0;
      Findings_By_Indicator : Indicator_Counts := [others => 0];
      By_Severity           : Severity_Counts := [others => 0];
   end record;
   --  Summary of one completed assessment, derived once from its decoded results.
   --  @field Totals Result-state counts.
   --  @field Quality Classification of the assessment.
   --  @field States Per-indicator result state.
   --  @field Kinds Per-indicator measurement representation.
   --  @field Findings Finding count.
   --  @field Findings_By_Indicator Finding count per indicator.
   --  @field By_Severity Finding count per severity.

   function Facts (Data : Snapshot; Run_Id : Positive) return Run_Facts;
   --  Return the summary of a completed assessment, decoding it on first use only.
   --  @param Data Snapshot.
   --  @param Run_Id Completed run identity.
   --  @return Facts.
   --  @exception Data_Error Stored evidence is corrupt.

   function History_Items (Data : Snapshot; Project_Id : Positive) return Ada_Quality.Storage.History_Vectors.Vector;
   --  Return run metadata in the shape Ada_Quality.History consumes.
   --  @param Data Snapshot.
   --  @param Project_Id Project identity.
   --  @return History items in ascending identity order.

   function History_Evidence
     (Data : Snapshot; Run_Id : Positive) return Ada_Quality.Reporting.History_Evidence;
   --  Return opaque evidence rows of a completed run for Ada_Quality.History.Compare.
   --  @param Data Snapshot.
   --  @param Run_Id Completed run identity.
   --  @return Evidence rows.
   --  @exception Data_Error Stored evidence is corrupt.

   function Compare
     (Data : Snapshot; Project_Id, Current_Id : Positive) return Ada_Quality.Reporting.Project_Comparison;
   --  Select a baseline for a project's assessment Current_Id and classify its changes, through
   --  Ada_Quality.Reporting.Compare_Project; runs after Current_Id are ignored.
   --  @param Data Snapshot.
   --  @param Project_Id Project.
   --  @param Current_Id Completed assessment in the current role.
   --  @return Selection and regressions.
   --  @exception Data_Error Stored evidence is corrupt.

   function Measurements (Data : Snapshot; Project_Id : Positive) return Ada_Quality.Storage.Detail_Vectors.Vector;
   --  Return measurement rows of a project's completed runs for Ada_Quality.History.Metric_Trend.
   --  @param Data Snapshot.
   --  @param Project_Id Project identity.
   --  @return Measurement rows.

private
   type Repository is limited record
      Path   : UString;
      Limits : Ada_Quality.Reporting.Load_Limits;
      Busy_Deadline : Duration := Default_Busy_Deadline;
      Opened : Boolean := False;
   end record;

   package Id_Maps is new Ada.Containers.Ordered_Maps (Key_Type => Positive, Element_Type => Natural);

   package Assessment_Maps is new Ada.Containers.Ordered_Maps
     (Key_Type => Positive, Element_Type => Ada_Quality.Reporting.Assessment_Record,
      "=" => Ada_Quality.Reporting."=");

   package Project_Maps is new Ada.Containers.Ordered_Maps
     (Key_Type => Positive, Element_Type => Ada_Quality.Reporting.Project_Record,
      "=" => Ada_Quality.Reporting."=");

   package Run_Maps is new Ada.Containers.Ordered_Maps
     (Key_Type => Positive, Element_Type => Ada_Quality.Reporting.Run_Record, "=" => Ada_Quality.Reporting."=");

   package Id_List_Maps is new Ada.Containers.Ordered_Maps
     (Key_Type => Positive, Element_Type => Id_Vectors.Vector, "=" => Id_Vectors."=");

   package Fact_Maps is new Ada.Containers.Ordered_Maps (Key_Type => Positive, Element_Type => Run_Facts);

   type Fact_Store is record
      Map : Fact_Maps.Map;
   end record;

   type Fact_Store_Access is access Fact_Store;

   --  Memo of derived facts; a snapshot is read through `in` parameters, so the memo lives behind an access value.
   type Fact_Cache is new Ada.Finalization.Limited_Controlled with record
      Store : Fact_Store_Access := new Fact_Store;
   end record;

   overriding procedure Finalize (Item : in out Fact_Cache);
   --  Release the memo with its snapshot.
   --  @param Item Memo.

   package History_Maps is new Ada.Containers.Ordered_Maps
     (Key_Type => Positive, Element_Type => Ada_Quality.Storage.History_Vectors.Vector,
      "=" => Ada_Quality.Storage.History_Vectors."=");

   package Detail_List_Maps is new Ada.Containers.Ordered_Maps
     (Key_Type => Positive, Element_Type => Ada_Quality.Storage.Detail_Vectors.Vector,
      "=" => Ada_Quality.Storage.Detail_Vectors."=");

   type Snapshot is limited record
      Session      : Ada_Quality.Reporting.Session;
      Project_Map  : Project_Maps.Map;
      Run_Map      : Run_Maps.Map;
      Project_Runs : Id_List_Maps.Map;
      Histories    : History_Maps.Map;
      Measures     : Detail_List_Maps.Map;
      Current      : Id_Maps.Map;
      Latest       : Id_Maps.Map;
      Decoded      : Assessment_Maps.Map;
      Fact_Memo    : Fact_Cache;
   end record;
end Ada_Quality_Summary.Repository;
