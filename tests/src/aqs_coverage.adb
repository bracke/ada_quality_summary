with Ada.Command_Line;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Interfaces;
with Ada_Quality.Checks;
with Project_Tools.Files;
with Project_Tools.Gcov;
with Project_Tools.Processes;

--  Production line-coverage gate.
--
--  Builds the instrumented suite and executables from tests/coverage.gpr, runs the complete AUnit suite with the
--  instrumented executables substituted for spawned processes, measures every production unit in src/ with gcov,
--  and writes coverage/gcov-summary.txt in the gcov-production-lines-v2 evidence format consumed by Ada Quality's
--  TST-03. Exits with failure when the suite fails, a unit is uninstrumented, or coverage is below 90 percent.
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
   Run_Suite : Boolean := False;

   procedure Fail (Message : String) is
   begin
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "coverage: " & Message);
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end Fail;

   function Trim (Value : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));

   --  Same FNV-1a digest Ada Quality applies to toolchain output.
   function Digest (Text : String) return String is
      use type Interfaces.Unsigned_64;
      Hash   : Interfaces.Unsigned_64 := 16#CBF29CE484222325#;
      Hex    : constant String := "0123456789abcdef";
      Result : String (1 .. 16);
   begin
      for C of Text loop
         Hash := (Hash xor Interfaces.Unsigned_64 (Character'Pos (C))) * 16#100000001B3#;
      end loop;
      for J in reverse Result'Range loop
         Result (J) := Hex (Natural (Hash and 15) + 1);
         Hash := Interfaces.Shift_Right (Hash, 4);
      end loop;
      return Result;
   end Digest;

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
begin
   if Root'Length = 0 then
      Fail ("cannot locate the ada_quality_summary project root");
      return;
   end if;
   declare
      Toolchain : constant P.Captured_Process :=
        Alr_Exec ("toolchain", Root, [P.Argument ("gnatls"), P.Argument ("--version")]);
      Source    : constant String := Ada_Quality.Checks.Source_Fingerprint (Root);
   begin
      if Toolchain.Status /= 0 then
         Fail ("toolchain fingerprint query failed");
         return;
      end if;
      if Ada.Command_Line.Argument_Count = 0 or else Ada.Command_Line.Argument (1) /= "--report-only" then
         Remove_Profiles;
         Run_Suite := True;
      end if;
      if Run_Suite then
      declare
         Build : constant P.Captured_Process :=
           Alr_Exec ("coverage build", Tests,
                     [P.Argument ("gprbuild"), P.Argument ("-q"), P.Argument ("-p"), P.Argument ("-P"),
                      P.Argument ("coverage.gpr")]);
      begin
         if Build.Status /= 0 then
            Fail ("instrumented build failed:" & LF & To_String (Build.Output));
            return;
         end if;
      end;
      Ada.Environment_Variables.Set ("AQS_BINARY", Project_Tools.Files.Join (Binaries, "ada-quality-summary"));
      Ada.Environment_Variables.Set ("AQS_TOOLS", Binaries);
      declare
         Suite : constant P.Captured_Process :=
           P.Capture ("instrumented suite", Tests, Project_Tools.Files.Join (Binaries, "ada_quality_summary_tests"),
                      P.No_Arguments, Quiet => True);
      begin
         if Suite.Status /= 0 then
            Fail ("instrumented AUnit suite failed:" & LF & To_String (Suite.Output));
            return;
         end if;
      end;
      end if;

      declare
         Search  : Ada.Directories.Search_Type;
         Item    : Ada.Directories.Directory_Entry_Type;
         Covered : Natural := 0;
         Total   : Natural := 0;
         Details : Unbounded_String;
         Units   : Natural := 0;
      begin
         Ada.Directories.Start_Search
           (Search, Project_Tools.Files.Join (Root, "src"), "*.ad?",
            [Ada.Directories.Ordinary_File => True, others => False]);
         while Ada.Directories.More_Entries (Search) loop
            Ada.Directories.Get_Next_Entry (Search, Item);
            declare
               Simple   : constant String := Ada.Directories.Simple_Name (Item);
               Stem     : constant String := Ada.Directories.Base_Name (Simple);
               Is_Body  : constant Boolean := Ada.Directories.Extension (Simple) = "adb";
               Has_Body : constant Boolean :=
                 Ada.Directories.Exists (Project_Tools.Files.Join (Root, "src/" & Stem & ".adb"));
               Notes    : constant String := Project_Tools.Files.Join (Objects, Stem & ".gcno");
            begin
               --  Each unit is measured once, through its body when it has one.
               if Is_Body or else not Has_Body then
                  Units := Units + 1;
                  if not Ada.Directories.Exists (Notes) then
                     Ada.Directories.End_Search (Search);
                     Fail ("production unit is not instrumented: " & Stem);
                     return;
                  end if;
                  declare
                     Run : constant P.Captured_Process :=
                       Alr_Exec ("gcov", Tests, [P.Argument ("gcov"), P.Argument ("-n"), P.Argument ("-o"),
                                                 P.Argument (Objects), P.Argument (Notes)]);
                     Records      : constant String := Per_File (To_String (Run.Output));
                     Unit_Covered : Natural := 0;
                     Unit_Total   : Natural := 0;
                  begin
                     if Run.Status /= 0 then
                        Ada.Directories.End_Search (Search);
                        Fail ("gcov failed for " & Stem);
                        return;
                     end if;
                     for Is_Spec in Boolean loop
                        declare
                           Extension   : constant String := (if Is_Spec then ".ads" else ".adb");
                           Source_File : constant String := Project_Tools.Files.Join (Root, "src/" & Stem & Extension);
                           One         : Project_Tools.Gcov.Coverage_Summary;
                        begin
                           if Ada.Directories.Exists (Source_File) and then
                             Ada.Strings.Fixed.Index (Records, Source_File & "'") > 0
                           then
                              One := Project_Tools.Gcov.Parse_Lines_Executed_Output (Records, Source_File);
                              Unit_Covered := Unit_Covered + Project_Tools.Gcov.Covered_Lines (One);
                              Unit_Total := Unit_Total + Project_Tools.Gcov.Total_Lines (One);
                           end if;
                        end;
                     end loop;
                     Covered := Covered + Unit_Covered;
                     Total := Total + Unit_Total;
                     Append (Details, "file_" & Stem & "_covered=" & Trim (Unit_Covered) & LF &
                               "file_" & Stem & "_total=" & Trim (Unit_Total) & LF);
                  end;
               end if;
            end;
         end loop;
         Ada.Directories.End_Search (Search);
         if Units = 0 or else Total = 0 then
            Fail ("no production executable lines were measured");
            return;
         end if;
         Ada.Directories.Create_Path (Output);
         Project_Tools.Files.Write_Text_File
           (Summary,
            "covered=" & Trim (Covered) & LF & "total=" & Trim (Total) & LF & "complete=true" & LF &
            "inventory=gcov-production-lines-v2" & LF & "source_fingerprint=" & Source & LF &
            "toolchain_fingerprint=" & Digest (To_String (Toolchain.Output)) & LF & To_String (Details));
         declare
            Result : constant Project_Tools.Gcov.Coverage_Summary := Project_Tools.Gcov.Summary (Covered, Total);
         begin
            Ada.Text_IO.Put_Line
              ("production line coverage: " & Trim (Covered) & "/" & Trim (Total) & " (" &
               Project_Tools.Gcov.Percent_Image (Result) & ")");
            if Long_Long_Integer (Covered) * 10_000 <
              Long_Long_Integer (Minimum_Basis_Points) * Long_Long_Integer (Total)
            then
               Fail ("production line coverage is below 90%");
            end if;
         end;
      end;
   end;
end Aqs_Coverage;
