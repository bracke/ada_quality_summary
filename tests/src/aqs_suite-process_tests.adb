separate (Aqs_Suite)
package body Process_Tests is
   procedure Wait_For_Line (Path, Text : String) is
   begin
      for Attempt in 1 .. 500 loop
         exit when Ada.Directories.Exists (Path) and then Contains (Project_Tools.Files.Read_Raw_File (Path), Text);
         delay 0.01;
      end loop;
   end Wait_For_Line;

   procedure Locked_Writer is
      Database : constant String := Standard_Database ("T039");
      Log      : constant String := Parent (Database) & "/writer.out";
      Args     : GNAT.OS_Lib.Argument_List_Access := Argument_List ("hold|" & Database & "|3");
      Pid      : GNAT.OS_Lib.Process_Id;
      Done     : GNAT.OS_Lib.Process_Id;
      Success  : Boolean;
   begin
      Pid := GNAT.OS_Lib.Non_Blocking_Spawn (Tool ("aqs_writer"), Args.all, Log, Err_To_Out => True);
      GNAT.OS_Lib.Free (Args);
      Wait_For_Line (Log, "locked");
      declare
         Result : constant Process_Result := Spawn ("--database|" & Database & "|summary|--format|json");
      begin
         Expect (Result.Status = 4, "a writer holding the lock yields a typed busy failure");
         Expect (Contains (To_String (Result.Output), "locked by another process"), "busy diagnostic");
         Expect (not Contains (To_String (Result.Output), "schema_version"), "no partial report is written");
      end;
      GNAT.OS_Lib.Wait_Process (Done, Success);
      Expect (Success and then GNAT.OS_Lib."=" (Done, Pid), "the writer completes normally");
      Expect (Spawn ("--database|" & Database & "|summary").Status = 0, "reporting succeeds after the writer");
   end Locked_Writer;

   procedure Publishing_Writer is
      Database : constant String := Standard_Database ("T040");
      Log      : constant String := Parent (Database) & "/writer.out";
      Args     : GNAT.OS_Lib.Argument_List_Access := Argument_List ("publish|" & Database & "|3|25");
      Pid      : GNAT.OS_Lib.Process_Id;
      Done     : GNAT.OS_Lib.Process_Id;
      Success  : Boolean;
      Reports     : Natural := 0;
      Points_Seen : Natural := 0;
   begin
      Pid := GNAT.OS_Lib.Non_Blocking_Spawn (Tool ("aqs_writer"), Args.all, Log, Err_To_Out => True);
      GNAT.OS_Lib.Free (Args);
      for Attempt in 1 .. 30 loop
         declare
            Result : constant Process_Result := Spawn ("--database|" & Database & "|projects|--format|json");
            Text   : constant String := To_String (Result.Output);
         begin
            if Result.Status = 0 then
               Reports := Reports + 1;
               --  One coherent generation: the per-project rows reproduce the totals exactly.
               Expect_Equal (Value (Text, "data.totals.projects"), "3", "registry is complete");
               Expect (Int (Value (Text, "data.totals.passing")) + Int (Value (Text, "data.totals.violations")) +
                         Int (Value (Text, "data.totals.incomplete")) +
                         Int (Value (Text, "data.totals.unassessed")) = 3,
                       "classification totals are consistent");
               Expect (Value (Text, "data.projects[1].current_run_id") = Value (Text, "data.projects[1].latest_run_id"),
                       "the current run of a publishing project is its latest completed run");
            else
               Expect (Result.Status = 4 and then Contains (Text, "locked"), "only a typed busy failure is allowed");
            end if;
         end;
         --  The K-th publication carries TST-03 = 5000 + K. Runs, results, and measurements of one generation give
         --  exactly 5001 .. 5000 + M in run order; rows from two generations would leave a gap or a stray value.
         declare
            Result : constant Process_Result :=
              Spawn ("--database|" & Database & "|trends|--project|gamma|--format|json");
            Text   : constant String := To_String (Result.Output);
         begin
            if Result.Status = 0 then
               Expect_Equal (Value (Text, "data.series[1].indicator_id"), """TST-03""", "TST-03 series");
               for Index in 0 .. Count_Of (Text, "data.series[1].points") - 1 loop
                  Expect_Equal (Value (Text, "data.series[1].points[" & Image (Index) & "].value"),
                                Image (5_001 + Index), "every publication of one generation, in order");
                  Points_Seen := Points_Seen + 1;
               end loop;
            else
               Expect (Result.Status = 4 and then Contains (Text, "locked"), "only a typed busy failure is allowed");
            end if;
         end;
      end loop;
      GNAT.OS_Lib.Wait_Process (Done, Success);
      Expect (Success, "the writer publishes every assessment: " & Project_Tools.Files.Read_Raw_File (Log));
      Expect (Reports > 0, "reports interleave with publication");
      Expect (Points_Seen > 0, "the generation check observed published measurements");
      if Ada.Environment_Variables.Exists ("AQS_TIMING") then
         Ada.Text_IO.Put_Line
           ("T040 reports:" & Natural'Image (Reports) & " points checked:" & Natural'Image (Points_Seen));
      end if;
      declare
         Final : constant String := Json (Database, "history|gamma");
      begin
         Expect_Equal (Value (Final, "data.completed_count"), "25", "every publication is visible afterwards");
      end;
      pragma Unreferenced (Pid);
   end Publishing_Writer;

   procedure Concurrent_Readers is
      Database : constant String := Standard_Database ("readers");
      Pids     : array (1 .. 4) of GNAT.OS_Lib.Process_Id;
      Done     : GNAT.OS_Lib.Process_Id;
      Success  : Boolean;
      Expected : constant String := Json (Database, "summary");
   begin
      for Index in Pids'Range loop
         declare
            Args : GNAT.OS_Lib.Argument_List_Access :=
              Argument_List ("--database|" & Database & "|summary|--format|json");
            Out_File : constant String := Parent (Database) & "/reader" & Character'Val (48 + Index) & ".json";
         begin
            Pids (Index) := GNAT.OS_Lib.Non_Blocking_Spawn
              (Binary, Args.all, Out_File, Parent (Database) & "/reader" & Character'Val (48 + Index) & ".err");
            GNAT.OS_Lib.Free (Args);
         end;
      end loop;
      for Index in Pids'Range loop
         GNAT.OS_Lib.Wait_Process (Done, Success);
         Expect (Success, "concurrent readers share the lock");
      end loop;
      for Index in Pids'Range loop
         Expect (Project_Tools.Files.Read_Raw_File
                   (Parent (Database) & "/reader" & Character'Val (48 + Index) & ".json") = Expected,
                 "every reader sees the same snapshot");
      end loop;
   end Concurrent_Readers;

   procedure Recovering_Writer is
      Database : constant String := Standard_Database ("recover");
      Running  : constant Positive := Start (Database, 3);
      Args     : GNAT.OS_Lib.Argument_List_Access := Argument_List ("recover|" & Database);
      Pid      : GNAT.OS_Lib.Process_Id;
      Done     : GNAT.OS_Lib.Process_Id;
      Success  : Boolean;
   begin
      Pid := GNAT.OS_Lib.Non_Blocking_Spawn
        (Tool ("aqs_writer"), Args.all, Parent (Database) & "/recover.out", Err_To_Out => True);
      GNAT.OS_Lib.Free (Args);
      for Attempt in 1 .. 10 loop
         declare
            Result : constant Process_Result := Spawn ("--database|" & Database & "|history|gamma|--format|json");
         begin
            Expect (Result.Status in 0 | 4, "recovery yields a coherent report or a busy failure");
            if Result.Status = 0 then
               Expect (Contains (To_String (Result.Output), """state"":""running""") or else
                       Contains (To_String (Result.Output), """state"":""interrupted"""),
                       "the run is either still running or recovered, never both");
            end if;
         end;
      end loop;
      GNAT.OS_Lib.Wait_Process (Done, Success);
      Expect (Success, "recovery completes");
      Expect (Contains (Json (Database, "history|gamma"), """state"":""interrupted"""), "recovery is visible");
      pragma Unreferenced (Running, Pid);
   end Recovering_Writer;

   procedure Killed_Reader is
      Database : constant String := Standard_Database ("killed");
      Before   : constant File_State_Vectors.Vector := Capture (Parent (Database));
   begin
      for Attempt in 1 .. 5 loop
         declare
            Args : GNAT.OS_Lib.Argument_List_Access := Argument_List ("--database|" & Database & "|trends");
            Pid  : constant GNAT.OS_Lib.Process_Id :=
              GNAT.OS_Lib.Non_Blocking_Spawn (Binary, Args.all, "/dev/null", Err_To_Out => True);
            Done    : GNAT.OS_Lib.Process_Id;
            Success : Boolean;
         begin
            GNAT.OS_Lib.Free (Args);
            delay Duration (Attempt) * 0.002;
            GNAT.OS_Lib.Kill (Pid);
            GNAT.OS_Lib.Wait_Process (Done, Success);
         end;
      end loop;
      Expect (Same (Before, Capture (Parent (Database))), "a terminated reader leaves the database unchanged");
      declare
         Store : Ada_Quality.Storage.Store;
      begin
         Ada_Quality.Storage.Open (Store, Database, Create_If_Missing => False);
         Ada_Quality.Storage.Close (Store);
      end;
      Expect (True, "the process lock is released when a reader is terminated");
   end Killed_Reader;

   procedure Output_Failure is
      Database : constant String := Standard_Database ("T041");
      Before   : constant File_State_Vectors.Vector := Capture (Parent (Database));
      Args     : GNAT.OS_Lib.Argument_List_Access := Argument_List ("--database|" & Database & "|summary");
      Success  : Boolean;
      Code     : Integer;
   begin
      GNAT.OS_Lib.Spawn (Binary, Args.all, "/dev/full", Success, Code, Err_To_Out => False);
      GNAT.OS_Lib.Free (Args);
      Expect (Code = 3, "an output stream failure exits with the reporting code");
      Expect (Same (Before, Capture (Parent (Database))), "cleanup leaves the database intact");
      Expect (Spawn ("--database|" & Database & "|summary").Status = 0, "no lock is left behind");
   end Output_Failure;

   procedure No_Tools is
      Database : constant String := Standard_Database ("T045");
      Traps    : constant String := Absolute (Dir ("T045-traps"));
      Log      : constant String := Traps & "/spawned.log";
      Saved    : constant String := Ada.Environment_Variables.Value ("PATH", "");
   begin
      for Name of Trap_Names loop
         Ada.Directories.Copy_File (Tool ("aqs_trap"), Traps & "/" & Name.all);
         GNAT.OS_Lib.Set_Executable (Traps & "/" & Name.all);
      end loop;
      Set_Env ("AQS_TRAP_LOG", Log);
      Set_Env ("PATH", Traps);
      for Command of All_Commands loop
         for Format of Format_Names loop
            declare
               Args    : GNAT.OS_Lib.Argument_List_Access :=
                 Argument_List ("--database|" & Database & "|" & Command.all & "|--format|" & Format.all);
               Success : Boolean;
               Code    : Integer;
            begin
               GNAT.OS_Lib.Spawn (Binary, Args.all, "/dev/null", Success, Code, Err_To_Out => True);
               GNAT.OS_Lib.Free (Args);
               Expect (Code = 0, Command.all & " succeeds without any tool on PATH");
            end;
         end loop;
      end loop;
      Set_Env ("PATH", Saved);
      Clear_Env ("AQS_TRAP_LOG");
      Expect (not Ada.Directories.Exists (Log), "no assessment tool is spawned");
   exception
      when others =>  --  AQ: audited exception boundary -- restores PATH and re-raises
         Set_Env ("PATH", Saved);
         raise;
   end No_Tools;
end Process_Tests;
