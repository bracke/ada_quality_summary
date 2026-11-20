with Ada.Calendar;
with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Exceptions;
with Ada.Unchecked_Deallocation;
with Ada_Quality_Summary.Text;

package body Ada_Quality_Summary.Repository is
   use Ada.Strings.Unbounded;
   use type Ada_Quality.Types.Assessment_Status;

   overriding procedure Finalize (Item : in out Memo) is
      procedure Free is new Ada.Unchecked_Deallocation (Memo_Store, Memo_Store_Access);
   begin
      Free (Item.Store);
   end Finalize;

   package Indicator_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type => String, Element_Type => Ada_Quality.Types.Indicator_Id, "=" => Ada_Quality.Types."=");

   --  Each indicator by the spelling a measurement row names it with.
   function Indicator_Index return Indicator_Maps.Map is
   begin
      return Result : Indicator_Maps.Map do
         for Id in Ada_Quality.Types.Indicator_Id loop
            Result.Insert (Ada_Quality.Types.Image (Id), Id);
         end loop;
      end return;
   end Indicator_Index;

   Indicators_By_Name : constant Indicator_Maps.Map := Indicator_Index;

   --  Every row must refer to a project or run loaded in the same snapshot; anything else is corrupt evidence.
   procedure Require (Present : Boolean; What : String; Id : Positive) is
   begin
      if not Present then
         raise Data_Error with What & Positive'Image (Id) & " refers to a row that does not exist";
      end if;
   end Require;

   procedure Open
     (Item          : in out Repository;
      Path          : String;
      Limits        : Ada_Quality.Reporting.Load_Limits := Ada_Quality_Summary.Limits.Default_Load;
      Busy_Deadline : Duration := Default_Busy_Deadline) is
   begin
      Item.Path := To_Unbounded_String (Path);
      Item.Limits := Limits;
      Item.Busy_Deadline := Busy_Deadline;
      Item.Opened := True;
   end Open;

   procedure Close (Item : in out Repository) is
   begin
      Item.Path := Null_Unbounded_String;
      Item.Opened := False;
   end Close;

   function Load (Item : in out Repository) return Snapshot is
   begin
      if not Item.Opened then
         raise Report_Error with "repository is not open";
      end if;
      return Data : Snapshot do
         begin
            declare
               Deadline : constant Ada.Calendar.Time := Ada.Calendar."+" (Ada.Calendar.Clock, Item.Busy_Deadline);
            begin
               loop
                  begin
                     Ada_Quality.Reporting.Open (Data.Session, To_String (Item.Path), Item.Limits);
                     exit;
                  exception
                     when Ada_Quality.Reporting.Busy_Error =>
                        if Ada.Calendar."<" (Deadline, Ada.Calendar.Clock) then
                           raise;
                        end if;
                        delay 0.01;
                  end;
               end loop;
            end;
            for Project of Ada_Quality.Reporting.Projects (Data.Session, Include_Removed => True) loop
               Data.Project_Map.Insert (Project.Id, Project);
               Data.Project_Runs.Insert (Project.Id, Id_Vectors.Empty_Vector);
            end loop;
            --  Runs arrive in ascending identity order, so each per-project list is ordered too.
            for Run of Ada_Quality.Reporting.Runs (Data.Session) loop
               Require (Data.Project_Runs.Contains (Run.Project_Id), "run", Run.Id);
               Data.Run_Map.Insert (Run.Id, Run);
               Data.Project_Runs.Reference (Run.Project_Id).Append (Run.Id);
               Data.Latest.Include (Run.Project_Id, Run.Id);
               if Run.State = Ada_Quality.Types.Assessment_Completed then
                  Data.Current.Include (Run.Project_Id, Run.Id);
               end if;
            end loop;
         exception
            when Error : Ada_Quality.Reporting.Limit_Error =>
               raise Report_Error with Ada.Exceptions.Exception_Message (Error);
            when Error : Ada_Quality.Reporting.Reporting_Error | Ada_Quality.Reporting.Schema_Error |
                 Ada_Quality.Reporting.Integrity_Error | Ada_Quality.Reporting.Busy_Error =>
               raise Data_Error with Ada.Exceptions.Exception_Message (Error);
         end;
      end return;
   end Load;

   function Schema_Version (Data : Snapshot) return Positive is
     (Ada_Quality.Reporting.Supported_Schema_Version (Data.Session));

   function Identity (Data : Snapshot) return String is (Ada_Quality.Reporting.Snapshot_Identity (Data.Session));

   function Projects (Data : Snapshot; Include_Removed : Boolean) return Ada_Quality.Reporting.Project_Vectors.Vector is
     (Ada_Quality.Reporting.Projects (Data.Session, Include_Removed));

   function Project (Data : Snapshot; Project_Id : Positive) return Ada_Quality.Reporting.Project_Record is
   begin
      if not Data.Project_Map.Contains (Project_Id) then
         raise Report_Error with "unknown project identity" & Positive'Image (Project_Id);
      end if;
      return Data.Project_Map.Element (Project_Id);
   end Project;

   function Runs (Data : Snapshot; Project_Id : Positive) return Ada_Quality.Reporting.Run_Vectors.Vector is
      Result : Ada_Quality.Reporting.Run_Vectors.Vector;
   begin
      if Data.Project_Runs.Contains (Project_Id) then
         for Id of Data.Project_Runs.Constant_Reference (Project_Id) loop
            Result.Append (Data.Run_Map.Element (Id));
         end loop;
      end if;
      return Result;
   end Runs;

   function Run (Data : Snapshot; Run_Id : Positive) return Ada_Quality.Reporting.Run_Record is
   begin
      if not Data.Run_Map.Contains (Run_Id) then
         raise Report_Error with "unknown run identity" & Positive'Image (Run_Id);
      end if;
      return Data.Run_Map.Element (Run_Id);
   end Run;

   function Current_Run (Data : Snapshot; Project_Id : Positive) return Natural is
     (if Data.Current.Contains (Project_Id) then Data.Current.Element (Project_Id) else 0);

   function Latest_Run (Data : Snapshot; Project_Id : Positive) return Natural is
     (if Data.Latest.Contains (Project_Id) then Data.Latest.Element (Project_Id) else 0);

   --  Read and decode a completed assessment from the snapshot.
   function Decode (Data : Snapshot; Run_Id : Positive) return Ada_Quality.Reporting.Assessment_Record is
   begin
      return Ada_Quality.Reporting.Read_Assessment (Data.Session, Run_Id);
   exception
      when Error : Ada_Quality.Reporting.Integrity_Error | Ada_Quality.Reporting.Reporting_Error =>
         raise Data_Error with Ada.Exceptions.Exception_Message (Error);
   end Decode;

   function Is_Current (Data : Snapshot; Run_Id : Positive) return Boolean is
     (Data.Run_Map.Contains (Run_Id) and then Current_Run (Data, Data.Run_Map.Element (Run_Id).Project_Id) = Run_Id);

   --  Decode a current assessment on first use and keep it; other assessments are decoded when asked for.
   procedure Ensure_Decoded (Data : Snapshot; Run_Id : Positive) is
      Decoded : Assessment_Maps.Map renames Data.Derived.Store.Decoded;
   begin
      if not Decoded.Contains (Run_Id) then
         Decoded.Insert (Run_Id, Decode (Data, Run_Id));
      end if;
   end Ensure_Decoded;

   procedure Visit_Assessment
     (Data    : Snapshot;
      Run_Id  : Positive;
      Process : not null access procedure (Value : Ada_Quality.Reporting.Assessment_Record)) is
   begin
      if Is_Current (Data, Run_Id) then
         Ensure_Decoded (Data, Run_Id);
         Process (Data.Derived.Store.Decoded.Constant_Reference (Run_Id));
      else
         Process (Decode (Data, Run_Id));
      end if;
   end Visit_Assessment;

   function Assessment (Data : Snapshot; Run_Id : Positive) return Ada_Quality.Reporting.Assessment_Record is
   begin
      if Is_Current (Data, Run_Id) then
         Ensure_Decoded (Data, Run_Id);
         return Data.Derived.Store.Decoded.Element (Run_Id);
      end if;
      return Decode (Data, Run_Id);
   end Assessment;

   --  Read a project's history items on first use, with its completed ones separately for metric trends.
   procedure Ensure_History (Data : Snapshot; Project_Id : Positive) is
      Store : Memo_Store renames Data.Derived.Store.all;
   begin
      if not Store.Histories.Contains (Project_Id) then
         declare
            Items     : Ada_Quality.Storage.History_Vectors.Vector;
            Completed : Ada_Quality.Storage.History_Vectors.Vector;
         begin
            if Data.Project_Map.Contains (Project_Id) then
               Items := Ada_Quality.Reporting.History_Items (Data.Session, Project_Id);
            end if;
            for Item of Items loop
               if To_String (Item.Status) = "completed" then
                  Completed.Append (Item);
               end if;
            end loop;
            Store.Histories.Insert (Project_Id, Items);
            Store.Completed.Insert (Project_Id, Completed);
         end;
      end if;
   exception
      when Error : Ada_Quality.Reporting.Integrity_Error | Ada_Quality.Reporting.Reporting_Error =>
         raise Data_Error with Ada.Exceptions.Exception_Message (Error);
   end Ensure_History;

   function History_Items (Data : Snapshot; Project_Id : Positive) return Ada_Quality.Storage.History_Vectors.Vector is
   begin
      Ensure_History (Data, Project_Id);
      return Data.Derived.Store.Histories.Element (Project_Id);
   end History_Items;

   function History_Evidence
     (Data : Snapshot; Run_Id : Positive) return Ada_Quality.Reporting.History_Evidence is
   begin
      return Ada_Quality.Reporting.Read_History_Evidence (Data.Session, Run_Id);
   exception
      when Error : Ada_Quality.Reporting.Integrity_Error | Ada_Quality.Reporting.Reporting_Error =>
         raise Data_Error with Ada.Exceptions.Exception_Message (Error);
   end History_Evidence;

   function Compare
     (Data : Snapshot; Project_Id, Current_Id : Positive) return Ada_Quality.Reporting.Project_Comparison is
   begin
      return Ada_Quality.Reporting.Compare_Project (Data.Session, Project_Id, Current_Id);
   exception
      when Error : Ada_Quality.Reporting.Integrity_Error | Ada_Quality.Reporting.Reporting_Error =>
         raise Data_Error with Ada.Exceptions.Exception_Message (Error);
   end Compare;

   function Resolve_Run (Data : Snapshot; Reference : String) return Positive is
   begin
      return Ada_Quality.Reporting.Resolve_Assessment (Data.Session, Reference);
   exception
      when Ada_Quality.Reporting.Reporting_Error =>
         raise Argument_Error with
           Ada_Quality_Summary.Text.Message ("error.unknown_assessment", [Ada_Quality_Summary.Text.Arg
                                                                            ("reference", Reference)]);
   end Resolve_Run;

   function Compare_Runs
     (Data : Snapshot; Baseline_Id, Current_Id : Positive) return Ada_Quality.Reporting.Project_Comparison is
   begin
      return Ada_Quality.Reporting.Compare_Assessments (Data.Session, Baseline_Id, Current_Id);
   exception
      when Error : Ada_Quality.Reporting.Integrity_Error | Ada_Quality.Reporting.Reporting_Error =>
         raise Data_Error with Ada.Exceptions.Exception_Message (Error);
   end Compare_Runs;

   function Result_Of
     (Data : Snapshot; Run_Id : Positive; Indicator : Ada_Quality.Types.Indicator_Id)
      return Ada_Quality.Types.Indicator_Result
   is
      Position : constant Positive := Ada_Quality.Types.Indicator_Id'Pos (Indicator) + 1;
   begin
      if Is_Current (Data, Run_Id) then
         Ensure_Decoded (Data, Run_Id);
         return Data.Derived.Store.Decoded.Constant_Reference (Run_Id).Results (Position);
      end if;
      return Decode (Data, Run_Id).Results (Position);
   end Result_Of;

   function Derive (Value : Ada_Quality.Reporting.Assessment_Record) return Run_Facts is
      Result : Run_Facts;
   begin
      for Item of Value.Results loop
         Result.States (Item.Indicator) := Ada_Quality_Summary.Model.State_Of (Item.Compliance);
         Result.Kinds (Item.Indicator) := Item.Measurement.Kind;
         Result.Findings_By_Indicator (Item.Indicator) := Natural (Item.Findings.Length);
         Result.Findings := Result.Findings + Natural (Item.Findings.Length);
         for F of Item.Findings loop
            Result.By_Severity (F.Level) := Result.By_Severity (F.Level) + 1;
         end loop;
      end loop;
      Result.Totals := Ada_Quality_Summary.Model.Count_Indicators (Value.Results);
      Result.Quality := Ada_Quality_Summary.Model.Classify (Value.Results);
      return Result;
   end Derive;

   function Facts (Data : Snapshot; Run_Id : Positive) return Run_Facts is
      Known : Fact_Maps.Map renames Data.Derived.Store.Facts;
      Value : Run_Facts;

      procedure Keep (Item : Ada_Quality.Reporting.Assessment_Record) is
      begin
         Value := Derive (Item);
      end Keep;
   begin
      if not Known.Contains (Run_Id) then
         Visit_Assessment (Data, Run_Id, Keep'Access);
         Known.Insert (Run_Id, Value);
      end if;
      return Known.Element (Run_Id);
   end Facts;

   --  Read a project's measurement rows on first use, grouped by the indicator they measure.
   procedure Ensure_Measures (Data : Snapshot; Project_Id : Positive) is
      Measures : Detail_Group_Maps.Map renames Data.Derived.Store.Measures;
      Groups   : Indicator_Details;

      procedure Add (Row : Ada_Quality.Storage.Detail_Info) is
         Position : constant Indicator_Maps.Cursor := Indicators_By_Name.Find (To_String (Row.Kind));
      begin
         if Indicator_Maps.Has_Element (Position) then
            Groups (Indicator_Maps.Element (Position)).Append (Row);
         end if;
      end Add;
   begin
      if Measures.Contains (Project_Id) then
         return;
      end if;
      if Data.Project_Runs.Contains (Project_Id) then
         for Run_Id of Data.Project_Runs.Constant_Reference (Project_Id) loop
            Ada_Quality.Reporting.Visit_Details
              (Data.Session, Run_Id, Ada_Quality.Reporting.Measurement_Details, Add'Access);
         end loop;
      end if;
      Measures.Insert (Project_Id, Groups);
   exception
      when Error : Ada_Quality.Reporting.Integrity_Error | Ada_Quality.Reporting.Reporting_Error =>
         raise Data_Error with Ada.Exceptions.Exception_Message (Error);
   end Ensure_Measures;

   function Metric_Trend
     (Data : Snapshot; Project_Id : Positive; Indicator : Ada_Quality.Types.Indicator_Id)
      return Ada_Quality.History.Trend_Vectors.Vector
   is
      Store : Memo_Store renames Data.Derived.Store.all;
   begin
      Ensure_History (Data, Project_Id);
      if Store.Completed.Constant_Reference (Project_Id).Is_Empty then
         return Ada_Quality.History.Trend_Vectors.Empty_Vector;
      end if;
      Ensure_Measures (Data, Project_Id);
      return Ada_Quality.History.Metric_Trend
        (Store.Completed.Constant_Reference (Project_Id),
         Store.Measures.Constant_Reference (Project_Id) (Indicator), Indicator);
   end Metric_Trend;
end Ada_Quality_Summary.Repository;
