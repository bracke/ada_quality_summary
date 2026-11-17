separate (Aqs_Suite)
package body Process_Tests is
   --  Wait for a writer to report a state, failing the test when it never does.
   procedure Wait_For_Line (Path, Text : String) is
   begin
      for Attempt in 1 .. 6_000 loop
         if Ada.Directories.Exists (Path) and then Contains (Project_Tools.Files.Read_Raw_File (Path), Text) then
            return;
         end if;
         delay 0.01;
      end loop;
      Assert (False, "the writer reports " & Text);
   end Wait_For_Line;

   --  Let a waiting writer continue.
   procedure Signal (Path : String) is
   begin
      Project_Tools.Files.Write_Text_File (Path, "");
   end Signal;

   procedure Locked_Writer is
      Database : constant String := Standard_Database ("T039");
      Log      : constant String := Parent (Database) & "/writer.out";
      Release  : constant String := Parent (Database) & "/release";
      Args     : GNAT.OS_Lib.Argument_List_Access := Argument_List ("hold|" & Database & "|" & Release);
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
      Signal (Release);
      GNAT.OS_Lib.Wait_Process (Done, Success);
      Expect (Success and then GNAT.OS_Lib."=" (Done, Pid), "the writer completes normally");
      Expect (Spawn ("--database|" & Database & "|summary").Status = 0, "reporting succeeds after the writer");
   end Locked_Writer;

   procedure Publishing_Writer is
      Database : constant String := Standard_Database ("T040");
      Log      : constant String := Parent (Database) & "/writer.out";
      Resume   : constant String := Parent (Database) & "/resume";
      Args     : GNAT.OS_Lib.Argument_List_Access := Argument_List ("publish|" & Database & "|3|25|" & Resume);
      Pid      : GNAT.OS_Lib.Process_Id;
      Done     : GNAT.OS_Lib.Process_Id;
      Success  : Boolean;
      Reports     : Natural := 0;
      Points_Seen : Natural := 0;
      Partial     : Boolean := False;

      --  The overview row of gamma, the project the writer publishes to; rows are ordered by name.
      function Gamma_Row (Text : String) return String is
      begin
         for Index in 0 .. Count_Of (Text, "data.projects") - 1 loop
            if Value (Text, "data.projects[" & Image (Index) & "].name") = """gamma""" then
               return "data.projects[" & Image (Index) & "].";
            end if;
         end loop;
         Assert (False, "the overview lists gamma");
         return "";
      end Gamma_Row;
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
               Expect (Value (Text, Gamma_Row (Text) & "current_run_id") =
                         Value (Text, Gamma_Row (Text) & "latest_run_id"),
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
               --  A report taken while the writer pauses halfway sees a partial generation; then it may go on.
               if Count_Of (Text, "data.series[1].points") in 1 .. 24 and then not Partial then
                  Partial := True;
                  Signal (Resume);
               end if;
            else
               Expect (Result.Status = 4 and then Contains (Text, "locked"), "only a typed busy failure is allowed");
            end if;
         end;
      end loop;
      Signal (Resume);
      GNAT.OS_Lib.Wait_Process (Done, Success);
      Expect (Success, "the writer publishes every assessment: " & Project_Tools.Files.Read_Raw_File (Log));
      Expect (Reports > 0, "reports interleave with publication");
      Expect (Partial, "a report ran while publication was in progress");
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
               Expect (Contains (To_String (Result.Output), """state"":""running""") xor
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
      Killed   : Natural := 0;
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
            --  A reader that finished before the signal exits successfully; only a terminated one counts.
            if not Success then
               Killed := Killed + 1;
            end if;
         end;
      end loop;
      Expect (Killed > 0, "at least one reader was terminated while running");
      Expect (Same (Before, Capture (Parent (Database))), "a terminated reader leaves the database unchanged");
      --  A lock left behind by a terminated reader would make this exclusive open fail with Storage_Error.
      declare
         Store : Ada_Quality.Storage.Store;
      begin
         Ada_Quality.Storage.Open (Store, Database, Create_If_Missing => False);
         Ada_Quality.Storage.Close (Store);
      exception
         when Ada_Quality.Storage.Storage_Error =>
            Assert (False, "the process lock is released when a reader is terminated");
      end;
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
      Saved_Path : Saved_Variable := Saving ("PATH");
      Saved_Log  : Saved_Variable := Saving ("AQS_TRAP_LOG");
      pragma Unreferenced (Saved_Path, Saved_Log);
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
      Expect (not Ada.Directories.Exists (Log), "no assessment tool is spawned");
   end No_Tools;
end Process_Tests;
