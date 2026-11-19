with Ada.Calendar;
with Ada.Exceptions;
with Ada.Unchecked_Deallocation;
with Ada_Quality_Summary.Text;

package body Ada_Quality_Summary.Repository is
   use Ada.Strings.Unbounded;
   use type Ada_Quality.Types.Assessment_Status;

   overriding procedure Finalize (Item : in out Fact_Cache) is
      procedure Free is new Ada.Unchecked_Deallocation (Fact_Store, Fact_Store_Access);
   begin
      Free (Item.Store);
   end Finalize;

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
               Data.Histories.Insert (Project.Id, Ada_Quality.Storage.History_Vectors.Empty_Vector);
               Data.Measures.Insert (Project.Id, Ada_Quality.Storage.Detail_Vectors.Empty_Vector);
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
            for Item of Ada_Quality.Reporting.History_Items (Data.Session) loop
               Require (Data.Histories.Contains (Item.Project_Id), "assessment", Item.Id);
               Data.Histories.Reference (Item.Project_Id).Append (Item);
            end loop;
            for Row of Ada_Quality.Reporting.All_Measurements (Data.Session) loop
               Require (Data.Run_Map.Contains (Row.Run_Id), "measurement of run", Row.Run_Id);
               Data.Measures.Reference (Data.Run_Map.Element (Row.Run_Id).Project_Id).Append (Row);
            end loop;
            for Position in Data.Current.Iterate loop
               declare
                  Run_Id : constant Positive := Id_Maps.Element (Position);
               begin
                  Data.Decoded.Insert (Run_Id, Ada_Quality.Reporting.Read_Assessment (Data.Session, Run_Id));
               end;
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

   function Assessment (Data : Snapshot; Run_Id : Positive) return Ada_Quality.Reporting.Assessment_Record is
   begin
      if Data.Decoded.Contains (Run_Id) then
         return Data.Decoded.Element (Run_Id);
      end if;
      return Ada_Quality.Reporting.Read_Assessment (Data.Session, Run_Id);
   exception
      when Error : Ada_Quality.Reporting.Integrity_Error | Ada_Quality.Reporting.Reporting_Error =>
         raise Data_Error with Ada.Exceptions.Exception_Message (Error);
   end Assessment;

   function History_Items (Data : Snapshot; Project_Id : Positive) return Ada_Quality.Storage.History_Vectors.Vector is
     (if Data.Histories.Contains (Project_Id) then Data.Histories.Element (Project_Id)
      else Ada_Quality.Storage.History_Vectors.Empty_Vector);

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
      if Data.Decoded.Contains (Run_Id) then
         return Data.Decoded.Constant_Reference (Run_Id).Results (Position);
      end if;
      return Assessment (Data, Run_Id).Results (Position);
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
      Memo : Fact_Maps.Map renames Data.Fact_Memo.Store.Map;
   begin
      if not Memo.Contains (Run_Id) then
         Memo.Insert (Run_Id, Derive (Assessment (Data, Run_Id)));
      end if;
      return Memo.Element (Run_Id);
   end Facts;

   function Measurements (Data : Snapshot; Project_Id : Positive) return Ada_Quality.Storage.Detail_Vectors.Vector is
     (if Data.Measures.Contains (Project_Id) then Data.Measures.Element (Project_Id)
      else Ada_Quality.Storage.Detail_Vectors.Empty_Vector);
end Ada_Quality_Summary.Repository;
