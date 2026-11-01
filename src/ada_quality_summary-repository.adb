with Ada.Calendar;
with Ada.Exceptions;
with Ada_Quality.Types;

package body Ada_Quality_Summary.Repository is
   use Ada.Strings.Unbounded;
   use type Ada_Quality.Types.Assessment_Status;

   procedure Open
     (Item : in out Repository; Path : String; Limits : Ada_Quality.Reporting.Load_Limits := (others => <>);
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
               Data.Project_Runs.Insert (Project.Id, Ada_Quality.Reporting.Run_Vectors.Empty_Vector);
               Data.Histories.Insert (Project.Id, Ada_Quality.Storage.History_Vectors.Empty_Vector);
               Data.Measures.Insert (Project.Id, Ada_Quality.Storage.Detail_Vectors.Empty_Vector);
            end loop;
            --  Runs arrive in ascending identity order, so each per-project list is ordered too.
            for Run of Ada_Quality.Reporting.Runs (Data.Session) loop
               Data.Run_Map.Insert (Run.Id, Run);
               Data.Project_Runs.Reference (Run.Project_Id).Append (Run);
               Data.Latest.Include (Run.Project_Id, Run.Id);
               if Run.State = Ada_Quality.Types.Assessment_Completed then
                  Data.Current.Include (Run.Project_Id, Run.Id);
               end if;
            end loop;
            for Item of Ada_Quality.Reporting.History_Items (Data.Session) loop
               Data.Histories.Reference (Item.Project_Id).Append (Item);
            end loop;
            for Row of Ada_Quality.Reporting.All_Measurements (Data.Session) loop
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

   function Has_Project (Data : Snapshot; Project_Id : Positive) return Boolean is
     (Data.Project_Map.Contains (Project_Id));

   function Project (Data : Snapshot; Project_Id : Positive) return Ada_Quality.Reporting.Project_Record is
   begin
      if not Data.Project_Map.Contains (Project_Id) then
         raise Report_Error with "unknown project identity" & Positive'Image (Project_Id);
      end if;
      return Data.Project_Map.Element (Project_Id);
   end Project;

   function Runs (Data : Snapshot; Project_Id : Positive) return Ada_Quality.Reporting.Run_Vectors.Vector is
     (if Data.Project_Runs.Contains (Project_Id) then Data.Project_Runs.Element (Project_Id)
      else Ada_Quality.Reporting.Run_Vectors.Empty_Vector);

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
     (Ada_Quality.Reporting.Read_History_Evidence (Data.Session, Run_Id));

   function Measurements (Data : Snapshot; Project_Id : Positive) return Ada_Quality.Storage.Detail_Vectors.Vector is
     (if Data.Measures.Contains (Project_Id) then Data.Measures.Element (Project_Id)
      else Ada_Quality.Storage.Detail_Vectors.Empty_Vector);
end Ada_Quality_Summary.Repository;
