with Ada.Command_Line;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with GNAT.OS_Lib;
with Ada_Quality.Checks;
with Ada_Quality.Coverage;
with Aqs_Evidence;
with Project_Tools.Files;
with Project_Tools.Gcov;
with Project_Tools.Processes;

--  Production line-coverage gate.
--
--  Builds the instrumented suite and executables from tests/coverage.gpr, runs the complete AUnit suite with the
--  instrumented executables substituted for spawned processes, measures every production unit in src/ with gcov,
--  and writes coverage/gcov-summary.txt in the gcov-production-lines-v3 evidence format consumed by Ada Quality's
--  TST-03: gcov-dump independently lists the sources the compiler notes cover, and every one of them must have a
--  gcov record. Exits with failure when the suite fails, a unit is uninstrumented or incompletely recorded, or
--  coverage is below 90 percent.
procedure Aqs_Coverage is
   use Ada.Strings.Unbounded;
   package P renames Project_Tools.Processes;

   Minimum_Basis_Points : constant := 9_000;
   LF : constant Character := Character'Val (10);

   Root      : constant String :=
     Project_Tools.Files.Find_Root_Upward (Ada.Directories.Current_Directory, "ada_quality_summary.gpr");
   Tests     : constant String := Project_Tools.Files.Join (Root, "tests");
   Objects   : constant String := Project_Tools.Files.Join (Tests, "cov-obj");
   Binaries  : constant String := Project_Tools.Files.Join (Tests, "cov-bin");
   Output    : constant String := Project_Tools.Files.Join (Root, "coverage");
   Summary   : constant String := Project_Tools.Files.Join (Output, "gcov-summary.txt");
   Alr       : constant String := P.Locate_Command ("alr");

   procedure Fail (Message : String) is
   begin
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "coverage: " & Message);
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end Fail;

   function Trim (Value : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));

   function Alr_Exec (Label, Directory : String; Items : P.Argument_Items) return P.Captured_Process is
      Arguments : P.Argument_Vectors.Vector := P.Arguments ([P.Argument ("exec"), P.Argument ("--")]);
   begin
      for Item of Items loop
         Arguments.Append (Item);
      end loop;
      return P.Capture (Label, Directory, Alr, Arguments, Quiet => True);
   end Alr_Exec;

   --  Keep only per-file records: each `File '...'` line and the line that follows it. gcov's trailing aggregate
   --  line is not attached to any file and is dropped.
   function Per_File (Text : String) return String is
      Result : Unbounded_String;
      Start  : Positive := Text'First;
      Keep_Next : Boolean := False;
   begin
      for Index in Text'First .. Text'Last + 1 loop
         if Index > Text'Last or else Text (Index) = LF then
            declare
               Line : constant String := Text (Start .. Index - 1);
            begin
               if Line'Length >= 6 and then Line (Line'First .. Line'First + 5) = "File '" then
                  Append (Result, Line & LF);
                  Keep_Next := True;
               elsif Keep_Next then
                  Append (Result, Line & LF);
                  Keep_Next := False;
               end if;
            end;
            Start := Index + 1;
         end if;
      end loop;
      return To_String (Result);
   end Per_File;

   --  Run gcov-dump on one unit's notes and keep the note inventory Ada Quality reconciles against: the header line
   --  and the function records, which name the sources holding executable lines. The full dump runs to megabytes, so
   --  it goes to a scratch file read line by line rather than through a captured string.
   function Note_Inventory (Notes : String; Inventory : out Unbounded_String) return Boolean is
      Dump_File : constant String := Project_Tools.Files.Join (Objects, "gcov-dump.txt");
      Arguments : GNAT.OS_Lib.Argument_List :=
        [new String'("-C"), new String'(Tests), new String'("exec"), new String'("--"), new String'("gcov-dump"),
         new String'(Notes)];
      Success   : Boolean;
      Status    : Integer;
      File      : Ada.Text_IO.File_Type;
      First     : Boolean := True;
   begin
      Inventory := Null_Unbounded_String;
      GNAT.OS_Lib.Spawn (Alr, Arguments, Dump_File, Success, Status, Err_To_Out => False);
      for Item of Arguments loop
         GNAT.OS_Lib.Free (Item);
      end loop;
      if not Success or else Status /= 0 then
         return False;
      end if;
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Dump_File);
      while not Ada.Text_IO.End_Of_File (File) loop
         declare
            Line : constant String := Ada.Text_IO.Get_Line (File);
         begin
            if First or else Ada.Strings.Fixed.Index (Line, "FUNCTION") > 0 then
               Append (Inventory, Line & LF);
            end if;
            First := False;
         end;
      end loop;
      Ada.Text_IO.Close (File);
      Ada.Directories.Delete_File (Dump_File);
      return True;
   end Note_Inventory;


   procedure Remove_Profiles is
      Search : Ada.Directories.Search_Type;
      Item   : Ada.Directories.Directory_Entry_Type;
   begin
      if not Ada.Directories.Exists (Objects) then
         return;
      end if;
      Ada.Directories.Start_Search (Search, Objects, "*.gcda");
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Item);
         Ada.Directories.Delete_File (Ada.Directories.Full_Name (Item));
      end loop;
      Ada.Directories.End_Search (Search);
   end Remove_Profiles;

   --  Build the instrumented suite and executables and run the suite with them substituted for spawned processes.
   function Run_Instrumented_Suite return Boolean is
      Build : constant P.Captured_Process :=
        Alr_Exec ("coverage build", Tests,
                  [P.Argument ("gprbuild"), P.Argument ("-q"), P.Argument ("-p"), P.Argument ("-P"),
                   P.Argument ("coverage.gpr")]);
   begin
      if Build.Status /= 0 then
         Fail ("instrumented build failed:" & LF & To_String (Build.Output));
         return False;
      end if;
      Ada.Environment_Variables.Set ("AQS_BINARY", Project_Tools.Files.Join (Binaries, "ada-quality-summary"));
      Ada.Environment_Variables.Set ("AQS_TOOLS", Binaries);
      declare
         Suite : constant P.Captured_Process :=
           P.Capture ("instrumented suite", Tests, Project_Tools.Files.Join (Binaries, "ada_quality_summary_tests"),
                      P.No_Arguments, Quiet => True);
      begin
         if Suite.Status /= 0 then
            Fail ("instrumented AUnit suite failed:" & LF & To_String (Suite.Output));
            return False;
         end if;
      end;
      return True;
   end Run_Instrumented_Suite;

   --  Measure the executable lines of one production unit, its body, specification, and subunits, from its notes.
   function Measure_Unit
     (Unit : Ada_Quality.Coverage.Production_Unit; Unit_Covered, Unit_Total : out Natural) return Boolean
   is
      Stem  : constant String := To_String (Unit.Stem);
      Notes : constant String := Project_Tools.Files.Join (Objects, Stem & ".gcno");
   begin
      Unit_Covered := 0;
      Unit_Total := 0;
      if not Ada.Directories.Exists (Notes) then
         Fail ("production unit is not instrumented: " & Stem);
         return False;
      end if;
      declare
         Run       : constant P.Captured_Process :=
           Alr_Exec ("gcov", Tests, [P.Argument ("gcov"), P.Argument ("-n"), P.Argument ("-o"),
                                     P.Argument (Objects), P.Argument (Notes)]);
         Records   : constant String := Per_File (To_String (Run.Output));
         Inventory : Unbounded_String;

         procedure Include (Source : Unbounded_String) is
            One : Project_Tools.Gcov.Coverage_Summary;
         begin
            if Length (Source) > 0 and then Ada_Quality.Coverage.Has_Source_Record (Records, To_String (Source)) then
               One := Project_Tools.Gcov.Parse_Lines_Executed_Output (Records, To_String (Source));
               Unit_Covered := Unit_Covered + Project_Tools.Gcov.Covered_Lines (One);
               Unit_Total := Unit_Total + Project_Tools.Gcov.Total_Lines (One);
            end if;
         end Include;
      begin
         if Run.Status /= 0 then
            Fail ("gcov failed for " & Stem);
            return False;
         elsif not Note_Inventory (Notes, Inventory) then
            Fail ("gcov-dump failed for " & Stem);
            return False;
         elsif not Ada_Quality.Coverage.Has_Complete_Source_Records (Records, To_String (Inventory), Unit) then
            Fail ("gcov output is missing a production source in unit " & Stem);
            return False;
         end if;
         Include (Unit.Body_Path);
         Include (Unit.Spec_Path);
         for Source of Unit.Subunit_Paths loop
            Include (Source);
         end loop;
      end;
      return True;
   end Measure_Unit;

   --  Measure every production unit in src/, each once through its body when it has one.
   --  Measure every production unit of src/ as Ada Quality inventories them: sorted, with bodies, specifications,
   --  and subunits, so the evidence covers exactly the sources TST-03 expects.
   function Measure_Units (Covered, Total, Units : out Natural; Details : out Unbounded_String) return Boolean is
   begin
      Covered := 0;
      Total := 0;
      Units := 0;
      Details := Null_Unbounded_String;
      for Unit of Ada_Quality.Coverage.Production_Units (Root) loop
         declare
            Stem         : constant String := To_String (Unit.Stem);
            Unit_Covered : Natural;
            Unit_Total   : Natural;
         begin
            if not Measure_Unit (Unit, Unit_Covered, Unit_Total) then
               return False;
            end if;
            Units := Units + 1;
            Covered := Covered + Unit_Covered;
            Total := Total + Unit_Total;
            Append (Details, "file_" & Stem & "_covered=" & Trim (Unit_Covered) & LF &
                      "file_" & Stem & "_total=" & Trim (Unit_Total) & LF);
         end;
      end loop;
      return True;
   end Measure_Units;

   procedure Report (Covered, Total : Natural) is
      Result : constant Project_Tools.Gcov.Coverage_Summary := Project_Tools.Gcov.Summary (Covered, Total);
   begin
      Ada.Text_IO.Put_Line
        ("production line coverage: " & Trim (Covered) & "/" & Trim (Total) & " (" &
         Project_Tools.Gcov.Percent_Image (Result) & ")");
      if Long_Long_Integer (Covered) * 10_000 < Long_Long_Integer (Minimum_Basis_Points) * Long_Long_Integer (Total)
      then
         Fail ("production line coverage is below 90%");
      end if;
   end Report;
begin
   if Root'Length = 0 then
      Fail ("cannot locate the ada_quality_summary project root");
      return;
   elsif Alr'Length = 0 then
      Fail ("alr is not on PATH");
      return;
   end if;
   --  Evidence from an earlier run must not survive a failing one.
   if Ada.Directories.Exists (Summary) then
      Ada.Directories.Delete_File (Summary);
   end if;
   declare
      Toolchain : constant String := Aqs_Evidence.Toolchain_Fingerprint (Root);
      Source    : constant String := Ada_Quality.Checks.Source_Fingerprint (Root);
      Covered, Total, Units : Natural;
      Details   : Unbounded_String;
   begin
      if Toolchain'Length = 0 then
         Fail ("toolchain fingerprint query failed");
         return;
      end if;
      if Ada.Command_Line.Argument_Count = 0 or else Ada.Command_Line.Argument (1) /= "--report-only" then
         Remove_Profiles;
         if not Run_Instrumented_Suite then
            return;
         end if;
      end if;
      if not Measure_Units (Covered, Total, Units, Details) then
         return;
      end if;
      if Units = 0 or else Total = 0 then
         Fail ("no production executable lines were measured");
         return;
      end if;
      Ada.Directories.Create_Path (Output);
      Project_Tools.Files.Write_Text_File
        (Summary,
         "covered=" & Trim (Covered) & LF & "total=" & Trim (Total) & LF & "complete=true" & LF &
         "inventory=" & Aqs_Evidence.Inventory & LF & "source_fingerprint=" & Source & LF &
         "toolchain_fingerprint=" & Toolchain & LF & To_String (Details));
      Report (Covered, Total);
   end;
end Aqs_Coverage;
