with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with GNAT.OS_Lib;
with Project_Tools.Files;
with Project_Tools.Processes;
with Project_Tools.Release_Checks;
with Aqs_Schema;

--  Release checker: required structure, toolchain, validation build, GNATdoc, SPARK proof, staged pin-free release,
--  AUnit suite, coverage evidence, and schema self-consistency.
--
--  Usage: tests/bin/check_all [--skip-build]
procedure Aqs_Check_All is
   type Text_Access is access constant String;
   type Text_List is array (Positive range <>) of Text_Access;

   Required : constant Text_List :=
     [new String'("alire.toml"), new String'("ada_quality_summary.gpr"), new String'("LICENSE"),
      new String'("README.md"), new String'("AGENTS.md"), new String'(".gitignore"),
      new String'("docs/architecture.md"), new String'("docs/api.md"), new String'("docs/cli.md"),
      new String'("docs/reporting-semantics.md"), new String'("docs/database-integration.md"),
      new String'("docs/reporting-integration.md"), new String'("docs/json-contracts.md"),
      new String'("docs/testing.md"), new String'("tests/alire.toml"), new String'("tests/coverage.gpr"),
      new String'("tests/ada_quality_summary_tests.gpr"), new String'("coverage/gcov-summary.txt"),
      new String'("spark_rules.gpr")];

   Reports : constant Text_List :=
     [new String'("summary"), new String'("projects"), new String'("project"), new String'("indicators"),
      new String'("indicator"), new String'("problems"), new String'("regressions"), new String'("trends"),
      new String'("history")];

   Root  : constant String :=
     Project_Tools.Files.Find_Root_Upward (Ada.Directories.Current_Directory, "ada_quality_summary.gpr");
   Alr   : constant String := Project_Tools.Processes.Locate_Command ("alr");
   Check : constant Project_Tools.Release_Checks.Checker := Project_Tools.Release_Checks.Create (Root);
   Skip_Build : constant Boolean :=
     Ada.Command_Line.Argument_Count = 1 and then Ada.Command_Line.Argument (1) = "--skip-build";
   --  Required files, directories, and schemas, and a validator that rejects an empty summary.
   procedure Check_Structure is
   begin
      for Item of Required loop
         Check.Require_File (Item.all);
      end loop;
      Check.Require_Directory ("src");
      Check.Require_Directory ("tests/src");
      Check.Require_File ("schemas/common.schema.json");
      for Report of Reports loop
         Check.Require_File ("schemas/" & Report.all & ".schema.json");
         declare
            Schema : constant String :=
              Project_Tools.Files.Read_Raw_File
                (Project_Tools.Files.Join (Root, "schemas/" & Report.all & ".schema.json"));
         begin
            if Ada.Strings.Fixed.Index (Schema, """const"": """ & Report.all & """") = 0 then
               Project_Tools.Release_Checks.Fail ("schema does not fix its report type: " & Report.all);
            end if;
         end;
      end loop;
      if Aqs_Schema.Validate (Project_Tools.Files.Join (Root, "schemas"), "summary.schema.json", "{}") = "" then
         Project_Tools.Release_Checks.Fail ("the schema validator accepts an empty summary");
      end if;
   end Check_Structure;

   --  Complete coverage evidence of at least 90 percent.
   procedure Check_Coverage_Evidence is
      Evidence : constant String := Project_Tools.Files.Join (Root, "coverage/gcov-summary.txt");
   begin
      if Project_Tools.Files.Value_Of (Evidence, "complete") /= "true" then
         Project_Tools.Release_Checks.Fail ("coverage evidence is incomplete; run tests/bin/aqs_coverage");
      end if;
      declare
         Covered : constant Natural := Natural'Value (Project_Tools.Files.Value_Of (Evidence, "covered"));
         Total   : constant Natural := Natural'Value (Project_Tools.Files.Value_Of (Evidence, "total"));
      begin
         if Total = 0 or else Long_Long_Integer (Covered) * 10 < Long_Long_Integer (Total) * 9 then
            Project_Tools.Release_Checks.Fail ("production line coverage is below 90%");
         end if;
      end;
   end Check_Coverage_Evidence;

   --  The Alire GNAT toolchain.
   procedure Check_Toolchain is
   begin
      declare
         Version : constant Project_Tools.Processes.Captured_Process :=
           Project_Tools.Processes.Capture
             ("GNAT version", Root, Alr,
              Project_Tools.Processes.Arguments
                ([Project_Tools.Processes.Argument ("exec"), Project_Tools.Processes.Argument ("--"),
                  Project_Tools.Processes.Argument ("gnatls"), Project_Tools.Processes.Argument ("-v")]));
         Text : constant String := Ada.Strings.Unbounded.To_String (Version.Output);
      begin
         --  The Alire crate version names the toolchain directory; the compiler itself reports GCC 15.2.0.
         if Version.Status /= 0 or else Ada.Strings.Fixed.Index (Text, "gnat_native_15.2.1") = 0 then
            Project_Tools.Release_Checks.Fail ("gnat_native 15.2.1 is required through alr exec");
         end if;
      end;
   end Check_Toolchain;

   --  GNATdoc without errors or warnings.
   procedure Check_Documentation is
   begin
      declare
         Documentation : constant Project_Tools.Processes.Captured_Process :=
           Project_Tools.Processes.Capture_Command
             (Alr,
              Project_Tools.Processes.Arguments
                ([Project_Tools.Processes.Argument ("-C"), Project_Tools.Processes.Argument (Root),
                  Project_Tools.Processes.Argument ("exec"), Project_Tools.Processes.Argument ("--"),
                  Project_Tools.Processes.Argument ("gnatdoc"), Project_Tools.Processes.Argument ("-P"),
                  Project_Tools.Processes.Argument (Project_Tools.Files.Join (Root, "ada_quality_summary.gpr")),
                  Project_Tools.Processes.Argument ("--warnings"), Project_Tools.Processes.Argument ("-O"),
                  Project_Tools.Processes.Argument (Project_Tools.Files.Join (Root, "obj/gnatdoc"))]),
              Err_To_Out => True);
         Text : constant String := Ada.Strings.Unbounded.To_String (Documentation.Output);
      begin
         --  GNATdoc reports documentation warnings without failing, so any diagnostic output fails the gate.
         if Documentation.Status /= 0 or else Ada.Strings.Fixed.Trim (Text, Ada.Strings.Both)'Length > 0 then
            Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Text);
            Project_Tools.Release_Checks.Fail ("GNATdoc reported errors or warnings for the public API");
         end if;
      end;
   end Check_Documentation;

begin
   if Root'Length = 0 then
      Project_Tools.Release_Checks.Fail ("cannot locate the ada_quality_summary project root");
   end if;
   Check_Structure;
   Check_Coverage_Evidence;
   Check_Toolchain;
   if not Skip_Build then
      Project_Tools.Release_Checks.Run
        ("validation build", Root, Alr,
         [new String'("build"), new String'("--validation"), new String'("--"), new String'("-f")]);
      Project_Tools.Release_Checks.Run
        ("test build", Project_Tools.Files.Join (Root, "tests"), Alr, [new String'("build")]);
   end if;
   Check_Documentation;
   --  Any unproved check or GNATprove warning fails the proof of the classification and counting rules.
   Project_Tools.Release_Checks.Run
     ("SPARK rules proof", Root, Alr,
      [new String'("exec"), new String'("--"), new String'("gnatprove"), new String'("-P"),
       new String'("spark_rules.gpr"), new String'("--checks-as-errors=on"), new String'("--warnings=error"),
       new String'("-j0")]);
   declare
      No_Arguments : GNAT.OS_Lib.Argument_List (1 .. 0);
   begin
      --  The published manifest is the root manifest without its development pins; the stage must validate and build.
      Project_Tools.Release_Checks.Run
        ("staged pin-free release", Root, Project_Tools.Files.Join (Root, "tests/bin/aqs_release_stage"),
         No_Arguments);
   end;
   declare
      No_Arguments : GNAT.OS_Lib.Argument_List (1 .. 0);
   begin
      Project_Tools.Release_Checks.Run
        ("AUnit suite", Project_Tools.Files.Join (Root, "tests"),
         Project_Tools.Files.Join (Root, "tests/bin/ada_quality_summary_tests"), No_Arguments);
   end;
   Ada.Text_IO.Put_Line ("ada_quality_summary release checks: OK");
exception
   when Program_Error =>
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Aqs_Check_All;
