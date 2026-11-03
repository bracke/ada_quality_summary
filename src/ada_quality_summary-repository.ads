with Ada.Containers.Ordered_Maps;
with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Ada_Quality.Reporting;
with Ada_Quality.Storage;
with Ada_Quality_Summary.Limits;

--  Coherent, read-only, in-memory database snapshot for one report invocation.
--
--  Load reads every required row in one read transaction through Ada_Quality.Reporting and releases the
--  database before returning. A Snapshot never holds a database handle, cursor, or lock; every query below is a
--  pure function of the loaded data.
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

   function Has_Project (Data : Snapshot; Project_Id : Positive) return Boolean;
   --  Test whether a registry entry exists, including tombstones.
   --  @param Data Snapshot.
   --  @param Project_Id Project identity.
   --  @return True when registered.

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

   package Run_List_Maps is new Ada.Containers.Ordered_Maps
     (Key_Type => Positive, Element_Type => Ada_Quality.Reporting.Run_Vectors.Vector,
      "=" => Ada_Quality.Reporting.Run_Vectors."=");

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
      Project_Runs : Run_List_Maps.Map;
      Histories    : History_Maps.Map;
      Measures     : Detail_List_Maps.Map;
      Current      : Id_Maps.Map;
      Latest       : Id_Maps.Map;
      Decoded      : Assessment_Maps.Map;
   end record;
end Ada_Quality_Summary.Repository;
