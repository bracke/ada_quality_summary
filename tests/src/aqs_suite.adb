with Ada.Calendar;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;
with Ada.Text_IO;
with AUnit;
with AUnit.Assertions;
with AUnit.Simple_Test_Cases;
with GNAT.OS_Lib;
with Jsonlib.Documents;
with Jsonlib.Errors;
with Jsonlib.Parsers;
with Jsonlib.Serializers;
with Ada_Quality.Indicators;
with Ada_Quality.Reporting;
with Ada_Quality.Storage;
with Ada_Quality.Types;
with Ada_Quality_Summary.Aggregation;
with Ada_Quality_Summary.CLI;
with Ada_Quality_Summary.Filtering;
with Ada_Quality_Summary.JSON;
with Ada_Quality_Summary.Reports;
with Ada_Quality_Summary.Model;
with Ada_Quality_Summary.Options;
with Ada_Quality_Summary.Repository;
with Ada_Quality_Summary.Terminal;
with Ada_Quality_Summary.Text;
with Ada_Quality_Summary.Trends;
with Aqs_Fixtures;
with Aqs_Schema;
with Project_Tools.Files;
with Project_Tools.Processes;

--  AQ: size-reviewed -- one catalog keeps the specification-identified acceptance tests together and auditable.
--  AQ: complexity-reviewed -- every acceptance case is a short, linear scenario dispatched by identifier.
package body Aqs_Suite is
   use Ada.Strings.Unbounded;
   use AUnit.Assertions;
   use Ada_Quality.Types;
   use Aqs_Fixtures;
   use type Ada_Quality_Summary.Model.Project_Quality_State;
   use type Ada_Quality_Summary.Options.Command_Kind;
   use type Ada_Quality_Summary.Options.Sort_Key;

   type Test_Id is
     (T001, T002, T003, T004, T005, T006, T007, T008, T009, T010, T011, T012, T013, T014, T015, T016, T017, T018,
      T019, T020, T021, T022, T023, T024, T025, T026, T027, T028, T029, T030, T031, T032, T033, T034, T035, T036,
      T037, T038, T039, T040, T041, T042, T043, T044, T045, T046, T047, T048, T049, T050,
      X_Options, X_Precedence, X_Properties, X_Display, X_Catalog, X_Round_Trip, X_Help, X_Concurrent_Readers,
      X_Recovering_Writer, X_Killed_Reader, X_Layouts, X_Sorting);

   function Title (Id : Test_Id) return String is
     (case Id is
         when T001 => "Empty_Registry",
         when T002 => "Never_Assessed_Project",
         when T003 => "All_Passing",
         when T004 => "One_Violation",
         when T005 => "Incomplete_Assessment",
         when T006 => "Violation_And_Unknown",
         when T007 => "Not_Applicable_Denominator",
         when T008 => "Interrupted_Latest_Run",
         when T009 => "Running_Latest_Run",
         when T010 => "No_Completed_Assessment",
         when T011 => "Duplicate_Indicator_Result",
         when T012 => "Missing_Indicator_Result",
         when T013 => "Invalid_Measurement_Encoding",
         when T014 => "Shared_Fingerprint_Across_Projects",
         when T015 => "Multiple_Findings_One_Indicator",
         when T016 => "Stable_Sort_Equal_Names",
         when T017 => "Disabled_Project",
         when T018 => "Removed_Project",
         when T019 => "Ambiguous_Basename",
         when T020 => "Unknown_Indicator",
         when T021 => "Incompatible_Baseline",
         when T022 => "Pass_To_Violation",
         when T023 => "Pass_To_Unknown",
         when T024 => "Metric_Unavailable",
         when T025 => "Decimal_Measurement",
         when T026 => "Width_40",
         when T027 => "Width_80",
         when T028 => "Width_120",
         when T029 => "Unicode_Paths",
         when T030 => "No_Color",
         when T031 => "Redirected_Stdout",
         when T032 => "JSON_Schemas",
         when T033 => "Repeated_JSON_Export",
         when T034 => "JSON_Terminal_Parity",
         when T035 => "Missing_Database",
         when T036 => "Old_Schema",
         when T037 => "Future_Schema",
         when T038 => "Corrupt_Persisted_Data",
         when T039 => "Concurrent_Writer_Lock",
         when T040 => "Writer_Publishes_During_Reports",
         when T041 => "Output_Stream_Failure",
         when T042 => "Resource_Limit",
         when T043 => "Large_Collection",
         when T044 => "All_33_Indicators",
         when T045 => "No_Assessment_Tools_Spawned",
         when T046 => "Database_Unchanged",
         when T047 => "Missing_Timestamps",
         when T048 => "Limit_Keeps_Totals",
         when T049 => "Unknown_CLI_Option",
         when T050 => "Nonexistent_Database_Not_Created",
         when X_Options => "Option_Parsing",
         when X_Precedence => "Database_Precedence",
         when X_Properties => "Aggregation_Properties",
         when X_Display => "Display_Width",
         when X_Catalog => "Message_Catalog",
         when X_Round_Trip => "JSON_Round_Trip",
         when X_Help => "Help_Topics",
         when X_Concurrent_Readers => "Concurrent_Readers",
         when X_Recovering_Writer => "Recovering_Writer",
         when X_Killed_Reader => "Killed_Reader",
         when X_Layouts => "Layouts",
         when X_Sorting => "Sort_Keys");

   type Acceptance_Test (Id : Test_Id) is new AUnit.Simple_Test_Cases.Test_Case with null record;
   overriding function Name (Item : Acceptance_Test) return AUnit.Message_String;
   overriding procedure Run_Test (Item : in out Acceptance_Test);

   overriding function Name (Item : Acceptance_Test) return AUnit.Message_String is
      Raw : constant String := Test_Id'Image (Item.Id);
   begin
      return AUnit.Format
        ((if Raw (Raw'First) = 'T' then "AQS_" & Raw & "_" else "AQS_") & Title (Item.Id));
   end Name;

   LF : constant Character := Character'Val (10);

   ------------------------------------------------------------------------------------------------------------------
   --  Helpers
   ------------------------------------------------------------------------------------------------------------------

   --  The coverage driver substitutes instrumented executables through AQS_BINARY and AQS_TOOLS.
   function Binary return String is
     (if Ada.Environment_Variables.Exists ("AQS_BINARY") then Absolute (Ada.Environment_Variables.Value ("AQS_BINARY"))
      else Absolute ("../bin/ada-quality-summary"));

   function Tool (Name : String) return String is
     (if Ada.Environment_Variables.Exists ("AQS_TOOLS")
      then Absolute (Ada.Environment_Variables.Value ("AQS_TOOLS") & "/" & Name)
      else Absolute ("bin/" & Name));
   function Schemas return String is (Absolute ("../schemas"));

   function Shape
     (Violations : String := ""; Unknowns : String := ""; NA : String := ""; Policy : String := "policy-a";
      Toolchain : String := "toolchain-a"; Findings : Natural := 1; Fingerprint : String := "";
      Coverage : Long_Long_Integer := 9_500; Status : Assessment_Status := Assessment_Completed) return Plan is
     ((Violations => Set_Of (Violations), Unknowns => Set_Of (Unknowns), Not_Applicable => Set_Of (NA),
       Findings => Findings, Fingerprint => To_Unbounded_String (Fingerprint), Level => Medium,
       Coverage => Coverage, Source => To_Unbounded_String ("source-a"), Policy => To_Unbounded_String (Policy),
       Toolchain => To_Unbounded_String (Toolchain), Status => Status));

   --  A fresh fixture directory and the absolute path of its (not yet created) database.
   function New_Database (Name : String) return String is (Absolute (Dir (Name)) & "/quality.db");

   function Parent (Database : String) return String is (Ada.Directories.Containing_Directory (Database));

   function Exit_Of (Item : Ada_Quality_Summary.CLI.Outcome) return Natural is (Item.Exit_Code);

   --  Run a report against a database, in-process.
   function Report (Database, Arguments : String) return Ada_Quality_Summary.CLI.Outcome is
     (Run ("--database|" & Database & "|" & Arguments));

   function Json (Database, Arguments : String) return String is
      Result : constant Ada_Quality_Summary.CLI.Outcome := Report (Database, Arguments & "|--format|json");
   begin
      Assert (Exit_Of (Result) = 0, "JSON report " & Arguments & " succeeds: " & Errors (Result));
      return Output (Result);
   end Json;

   --  Return the compact JSON text of the value at a dotted path such as `data.totals.projects` or
   --  `data.projects[0].quality`.
   function Value (Text, Path : String) return String is
      Doc   : Jsonlib.Documents.Document;
      Error : Jsonlib.Errors.Error_Info;
      Item  : Jsonlib.Documents.Node;
      Start : Positive := Path'First;
      use type Jsonlib.Errors.Error_Code;
   begin
      Jsonlib.Parsers.Parse (Text, Doc, Error);
      Assert (Error.Code = Jsonlib.Errors.No_Error, "output is valid JSON");
      Item := Doc.Root;
      for Index in Path'First .. Path'Last + 1 loop
         if Index > Path'Last or else Path (Index) = '.' then
            declare
               Part    : constant String := Path (Start .. Index - 1);
               Bracket : constant Natural := Ada.Strings.Fixed.Index (Part, "[");
            begin
               if Bracket = 0 then
                  Item := Doc.Member (Item, Part);
               else
                  Item := Doc.Member (Item, Part (Part'First .. Bracket - 1));
                  Item := Doc.Element (Item, Natural'Value (Part (Bracket + 1 .. Part'Last - 1)) + 1);
               end if;
               if not Jsonlib.Documents.Is_Present (Item) then
                  return "<absent>";
               end if;
            end;
            Start := Index + 1;
         end if;
      end loop;
      return Jsonlib.Serializers.To_String (Doc, Item);
   end Value;

   function Count_Of (Text, Path : String) return Natural is
      Doc   : Jsonlib.Documents.Document;
      Error : Jsonlib.Errors.Error_Info;
      Raw   : constant String := Value (Text, Path);
   begin
      Jsonlib.Parsers.Parse (Raw, Doc, Error);
      return Doc.Length (Doc.Root);
   end Count_Of;

   function Int (Text : String) return Natural is (Natural'Value (Text));

   function Image (Number : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Number), Ada.Strings.Left));

   procedure Expect (Condition : Boolean; Message : String) is
   begin
      Assert (Condition, Message);
   end Expect;

   procedure Expect_Equal (Actual, Wanted, Message : String) is
   begin
      Assert (Actual = Wanted, Message & ": expected " & Wanted & ", found " & Actual);
   end Expect_Equal;

   --  Every line of Text fits Width display cells.
   function Fits (Text : String; Width : Positive) return Boolean is
      Start : Positive := Text'First;
   begin
      for Index in Text'Range loop
         if Text (Index) = LF then
            if Ada_Quality_Summary.Terminal.Display_Width (Text (Start .. Index - 1)) > Width then
               return False;
            end if;
            Start := Index + 1;
         end if;
      end loop;
      return True;
   end Fits;

   function Has_Escape (Text : String) return Boolean is (Contains (Text, [Character'Val (27)]));

   type Text_Access is access constant String;
   type Text_List is array (Positive range <>) of Text_Access;

   Layout_Names : constant Text_List := [new String'("compact"), new String'("normal"), new String'("detailed")];
   Format_Names : constant Text_List := [new String'("terminal"), new String'("json")];
   Variants     : constant Text_List :=
     [new String'(""), new String'("|--pretty"), new String'("|--limit|1"), new String'("|--include-removed")];
   Trap_Names   : constant Text_List :=
     [new String'("alr"), new String'("gprbuild"), new String'("gnat"), new String'("gnatprove"),
      new String'("gnatdoc"), new String'("gcov"), new String'("git"), new String'("sh"),
      new String'("ada-quality"), new String'("check_all")];
   Unicode_Widths : constant array (1 .. 4) of Positive := [40, 60, 80, 120];

   All_Commands : constant Text_List (1 .. 9) :=
     [new String'("summary"), new String'("projects"), new String'("project|alpha"), new String'("indicators"),
      new String'("indicator|TST-03"), new String'("problems"), new String'("regressions"), new String'("trends"),
      new String'("history|alpha")];

   Template_Built : Boolean := False;

   --  A copy of one template with a violating project `alpha` (two compatible runs), an incomplete `beta`, and an
   --  unassessed `gamma`. The template is published once through the storage API and copied per test.
   function Standard_Database (Name : String) return String is
      Template : constant String := Absolute (Root) & "/template/quality.db";
      Database : constant String := New_Database (Name);
   begin
      if not Template_Built then
         declare
            Store   : Ada_Quality.Storage.Store;
            Ids     : array (1 .. 3) of Positive;
            Ignored : Positive;
         begin
            if Ada.Directories.Exists (Parent (Template)) then
               Ada.Directories.Delete_Tree (Parent (Template));
            end if;
            Ada.Directories.Create_Path (Parent (Template));
            Ada_Quality.Storage.Open (Store, Template);
            Ids (1) := Register (Store, Parent (Template), "alpha");
            Ids (2) := Register (Store, Parent (Template), "beta");
            Ids (3) := Register (Store, Parent (Template), "gamma");
            Ignored := Publish (Store, Build (Ids (1), Shape (NA => "PRF-01")));
            Ignored := Publish (Store, Build (Ids (1), Shape ("DOC-01", NA => "PRF-01", Coverage => 9_123)));
            Ignored := Publish (Store, Build (Ids (2), Shape ("TST-03 SRC-01", "BLD-02", Findings => 2)));
            Ada_Quality.Storage.Close (Store);
            Template_Built := True;
         end;
      end if;
      Copy_Database (Template, Database);
      return Database;
   end Standard_Database;

   type Process_Result is record
      Status : Integer := -1;
      Output : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Run the executable as a separate process with standard error merged into the captured output.
   function Spawn (Arguments : String) return Process_Result is
      Items : Project_Tools.Processes.Argument_Vectors.Vector;
      Start : Positive := Arguments'First;
   begin
      for Index in Arguments'First .. Arguments'Last + 1 loop
         if Index > Arguments'Last or else Arguments (Index) = '|' then
            if Index > Start then
               Items.Append (To_Unbounded_String (Arguments (Start .. Index - 1)));
            end if;
            Start := Index + 1;
         end if;
      end loop;
      declare
         Result : constant Project_Tools.Processes.Captured_Process :=
           Project_Tools.Processes.Capture_Command (Binary, Items, Err_To_Out => True);
      begin
         return (Status => Result.Status, Output => Result.Output);
      end;
   end Spawn;

   function Argument_List (Arguments : String) return GNAT.OS_Lib.Argument_List_Access is
      Count : Natural := 1;
   begin
      for C of Arguments loop
         if C = '|' then
            Count := Count + 1;
         end if;
      end loop;
      declare
         Result : constant GNAT.OS_Lib.Argument_List_Access := new GNAT.OS_Lib.Argument_List (1 .. Count);
         Start  : Positive := Arguments'First;
         Slot   : Positive := 1;
      begin
         for Index in Arguments'First .. Arguments'Last + 1 loop
            if Index > Arguments'Last or else Arguments (Index) = '|' then
               Result (Slot) := new String'(Arguments (Start .. Index - 1));
               Slot := Slot + 1;
               Start := Index + 1;
            end if;
         end loop;
         return Result;
      end;
   end Argument_List;

   procedure Set_Env (Name, Value : String) is
   begin
      Ada.Environment_Variables.Set (Name, Value);
   end Set_Env;

   procedure Clear_Env (Name : String) is
   begin
      if Ada.Environment_Variables.Exists (Name) then
         Ada.Environment_Variables.Clear (Name);
      end if;
   end Clear_Env;

   ------------------------------------------------------------------------------------------------------------------
   --  Classification and counting: T001-T010
   ------------------------------------------------------------------------------------------------------------------

   procedure Classification (Id : Test_Id) is
      Database : constant String := New_Database (Test_Id'Image (Id));
      Project  : Positive;
      Previous : Positive;
      Ignored  : Positive;
   begin
      Create (Database);
      if Id = T001 then
         declare
            Text : constant String := Json (Database, "summary");
         begin
            Expect_Equal (Value (Text, "data.totals.projects"), "0", "empty registry has zero projects");
            Expect_Equal (Value (Text, "data.projects"), "[]", "empty registry lists no projects");
            Expect (Contains (Output (Report (Database, "summary")), "No projects selected."),
                    "terminal output states that no project is selected");
         end;
         return;
      end if;
      Project := Register (Database, Parent (Database), "alpha");
      case Id is
         when T003 => Ignored := Publish (Database, Build (Project, Shape));
         when T004 => Ignored := Publish (Database, Build (Project, Shape ("DOC-01")));
         when T005 => Ignored := Publish (Database, Build (Project, Shape (Unknowns => "TST-04")));
         when T006 => Ignored := Publish (Database, Build (Project, Shape ("DOC-01", "TST-04")));
         when T007 => Ignored := Publish (Database, Build (Project, Shape (NA => "PRF-01")));
         when T008 =>
            Previous := Publish (Database, Build (Project, Shape));
            Interrupt (Database, Start (Database, Project));
         when T009 =>
            Previous := Publish (Database, Build (Project, Shape));
            Ignored := Start (Database, Project);
         when T010 =>
            Interrupt (Database, Start (Database, Project));
            Ignored := Publish (Database, Build (Project, Shape (Status => Assessment_Invalid)));
         when others => null;
      end case;
      declare
         Text : constant String := Json (Database, "summary");
         Row  : constant String := "data.projects[0].";
      begin
         case Id is
            when T002 =>
               Expect_Equal (Value (Text, Row & "quality"), """unassessed""", "never-assessed project");
               Expect_Equal (Value (Text, Row & "indicators"), "null", "unassessed states are absent, not unknown");
               Expect_Equal (Value (Text, Row & "current_run_id"), "null", "no completed assessment is null");
               Expect (Contains (Output (Report (Database, "summary")), "UNASSESSED"), "terminal labels unassessed");
            when T003 =>
               Expect_Equal (Value (Text, Row & "quality"), """passing""", "33 passes classify as passing");
               Expect_Equal (Value (Text, Row & "indicators.passed"), "33", "33 passes are counted");
            when T004 =>
               Expect_Equal (Value (Text, Row & "quality"), """violations""", "one violation");
               Expect_Equal (Value (Text, Row & "indicators.violated"), "1", "violation count");
               Expect_Equal (Value (Text, Row & "indicators.passed"), "32", "pass count");
            when T005 =>
               Expect_Equal (Value (Text, Row & "quality"), """incomplete""", "one unknown is incomplete");
               Expect_Equal (Value (Text, Row & "indicators.unknown"), "1", "unknown count");
            when T006 =>
               Expect_Equal (Value (Text, Row & "quality"), """incomplete""", "unknown takes precedence");
               Expect_Equal (Value (Text, Row & "indicators.violated"), "1", "violations remain visible");
               Expect_Equal (Value (Text, Row & "indicators.unknown"), "1", "unknowns remain visible");
               Expect_Equal (Value (Text, "data.totals.indicator_violations"), "1", "portfolio violation count");
            when T007 =>
               Expect_Equal (Value (Text, Row & "quality"), """passing""", "not applicable does not violate");
               Expect_Equal (Value (Text, Row & "indicators.not_applicable"), "1", "N/A count");
               Expect (Contains (Output (Report (Database, "project|alpha")), "32/32 applicable passing"),
                       "the denominator excludes not-applicable requirements");
            when T008 =>
               Expect_Equal (Value (Text, Row & "current_run_id"), Ada.Strings.Fixed.Trim
                               (Positive'Image (Previous), Ada.Strings.Both), "previous completed data is used");
               Expect_Equal (Value (Text, Row & "newer_run"), """interrupted""", "newer interrupted run is flagged");
               Expect_Equal (Value (Text, "data.activity.newer_unfinished"), "1", "activity counts it");
               Expect (Contains (Output (Report (Database, "summary")), "interrupted or invalid assessments: 1"),
                       "terminal warns about the newer run");
            when T009 =>
               Expect_Equal (Value (Text, Row & "quality"), """passing""", "latest completed data is preserved");
               Expect_Equal (Value (Text, Row & "newer_run"), """running""", "newer running run is flagged");
               Expect_Equal (Value (Text, "data.activity.newer_running"), "1", "activity counts it");
            when T010 =>
               Expect_Equal (Value (Text, Row & "quality"), """unassessed""", "failed runs do not assess");
               Expect (Value (Text, Row & "latest_run_id") /= "null", "the latest run is still recorded");
            when others => null;
         end case;
      end;
   end Classification;

   ------------------------------------------------------------------------------------------------------------------
   --  Integrity: T011-T013, T036-T038, T035, T050
   ------------------------------------------------------------------------------------------------------------------

   procedure Integrity (Id : Test_Id) is
      Database : constant String := New_Database (Test_Id'Image (Id));
      Copy     : constant String := Parent (Database) & "/copy.db";
      Project  : Positive;
      Run_Id   : Positive;
   begin
      Create (Database);
      Project := Register (Database, Parent (Database), "alpha");
      Run_Id := Publish (Database, Build (Project, Shape ("DOC-01")));
      Copy_Database (Database, Copy);
      case Id is
         when T011 => Corrupt (Copy, Run_Id, Ada_Quality.Storage.Duplicate_Result);
         when T012 => Corrupt (Copy, Run_Id, Ada_Quality.Storage.Missing_Result);
         when T013 => Corrupt (Copy, Run_Id, Ada_Quality.Storage.Invalid_Measurement);
         when T038 => Corrupt (Copy, Run_Id, Ada_Quality.Storage.Malformed_Finding);
         when T036 => Set_Schema (Copy, 2);
         when T037 => Set_Schema (Copy, 99);
         when others => null;
      end case;
      declare
         Before : constant File_State_Vectors.Vector := Capture (Parent (Database));
         Result : constant Ada_Quality_Summary.CLI.Outcome := Report (Copy, "summary|--format|json");
      begin
         Expect (Exit_Of (Result) = 4, "integrity and schema failures exit with code 4");
         Expect (Output (Result) = "", "no partial report is written");
         case Id is
            when T011 => Expect (Contains (Errors (Result), "duplicate result"), "duplicate result diagnosed");
            when T012 => Expect (Contains (Errors (Result), "missing result"), "missing result diagnosed");
            when T013 => Expect (Contains (Errors (Result), "invalid number"), "invalid measurement diagnosed");
            when T038 => Expect (Contains (Errors (Result), "finding"), "corrupt finding diagnosed");
            when T036 => Expect (Contains (Errors (Result), "migrate"), "old schema asks for migration");
            when T037 => Expect (Contains (Errors (Result), "unsupported schema version 99"), "future schema");
            when others => null;
         end case;
         Expect (Same (Before, Capture (Parent (Database))), "the database is unchanged");
      end;
   end Integrity;

   procedure Missing (Id : Test_Id) is
      Directory : constant String := Absolute (Dir (Test_Id'Image (Id)));
      Database  : constant String :=
        (if Id = T035 then Directory & "/absent.db" else Directory & "/no/such/dir/absent.db");
      Result    : constant Ada_Quality_Summary.CLI.Outcome := Report (Database, "summary");
   begin
      Expect (Exit_Of (Result) = 4, "a missing database is a database failure");
      Expect (Contains (Errors (Result), "database not found"), "the missing database is named");
      Expect (not Ada.Directories.Exists (Database), "the database is not created");
      Expect (not Ada.Directories.Exists (Directory & "/no"), "no directory is created");
      Expect (Capture (Directory).Is_Empty, "no file is created");
   end Missing;

   ------------------------------------------------------------------------------------------------------------------
   --  Findings, selection, and resolution: T014-T020
   ------------------------------------------------------------------------------------------------------------------

   procedure Selection (Id : Test_Id) is
      Database : constant String := New_Database (Test_Id'Image (Id));
      A, B     : Positive;
      Ignored  : Positive;
   begin
      Create (Database);
      case Id is
         when T014 =>
            A := Register (Database, Parent (Database), "alpha");
            B := Register (Database, Parent (Database), "beta");
            Ignored := Publish (Database, Build (A, Shape ("DOC-01", Fingerprint => "shared")));
            Ignored := Publish (Database, Build (B, Shape ("DOC-01", Fingerprint => "shared")));
            declare
               Text : constant String := Json (Database, "problems");
            begin
               Expect_Equal (Value (Text, "data.totals.findings"), "2", "both occurrences are reported");
               Expect_Equal (Value (Text, "data.findings[0].fingerprint"), Value (Text, "data.findings[1].fingerprint"),
                             "occurrences share the fingerprint");
               Expect (Value (Text, "data.findings[0].project_id") /= Value (Text, "data.findings[1].project_id"),
                       "occurrences belong to separate projects");
               Expect_Equal (Value (Text, "data.grouped_by_indicator[0].projects"), "2", "grouped by project");
               Expect_Equal (Value (Json (Database, "summary"), "data.findings_by_indicator"),
                             Value (Text, "data.grouped_by_indicator"),
                             "the overview aggregates findings by indicator exactly as the problems report");
            end;
         when T015 =>
            A := Register (Database, Parent (Database), "alpha");
            Ignored := Publish (Database, Build (A, Shape ("DOC-01", Findings => 3)));
            declare
               Text : constant String := Json (Database, "summary");
            begin
               Expect_Equal (Value (Text, "data.projects[0].indicators.violated"), "1", "one violated indicator");
               Expect_Equal (Value (Text, "data.projects[0].finding_count"), "3", "three findings");
               Expect_Equal (Value (Text, "data.totals.indicator_violations"), "1", "violations are not findings");
            end;
         when T016 =>
            declare
               First_Dir  : constant String := Parent (Database) & "/one";
               Second_Dir : constant String := Parent (Database) & "/two";
            begin
               Ada.Directories.Create_Path (First_Dir);
               Ada.Directories.Create_Path (Second_Dir);
               Ignored := Register (Database, Second_Dir, "same");
               Ignored := Register (Database, First_Dir, "same");
               Ignored := Register (Database, First_Dir, "aaa");
               declare
                  Text : constant String := Json (Database, "projects");
               begin
                  Expect_Equal (Value (Text, "data.projects[0].name"), """aaa""", "names sort first");
                  Expect_Equal (Value (Text, "data.projects[1].project_id"), "1", "equal names sort by ID");
                  Expect_Equal (Value (Text, "data.projects[2].project_id"), "2", "equal names sort by ID");
               end;
               Expect (Exit_Of (Report (Database, "project|same")) = 2, "an ambiguous basename is rejected");
               Expect (Exit_Of (Report (Database, "project|2")) = 0, "a numeric ID resolves exactly");
            end;
         when T017 =>
            A := Register (Database, Parent (Database), "alpha");
            B := Register (Database, Parent (Database), "beta");
            Set_Enabled (Database, B, False);
            Expect_Equal (Value (Json (Database, "summary"), "data.totals.projects"), "2", "disabled is included");
            Expect_Equal (Value (Json (Database, "summary"), "data.totals.disabled"), "1", "disabled is counted");
            Expect_Equal (Value (Json (Database, "summary|--enabled-only"), "data.totals.projects"), "1",
                          "--enabled-only excludes disabled projects");
         when T018 =>
            A := Register (Database, Parent (Database), "alpha");
            B := Register (Database, Parent (Database), "beta");
            Remove (Database, B);
            Expect_Equal (Value (Json (Database, "projects"), "data.totals.projects"), "1", "removed is excluded");
            Expect_Equal (Value (Json (Database, "projects|--include-removed"), "data.totals.projects"), "2",
                          "--include-removed includes tombstones");
            Expect_Equal (Value (Json (Database, "projects|--include-removed"), "data.projects[1].removed"), "true",
                          "tombstones are marked");
            Expect (Exit_Of (Report (Database, "project|beta")) = 2, "a removed project is not resolved by default");
         when T019 =>
            declare
               First_Dir  : constant String := Parent (Database) & "/one";
               Second_Dir : constant String := Parent (Database) & "/two";
            begin
               Ada.Directories.Create_Path (First_Dir);
               Ada.Directories.Create_Path (Second_Dir);
               A := Register (Database, First_Dir, "dup");
               B := Register (Database, Second_Dir, "dup");
               declare
                  Result : constant Ada_Quality_Summary.CLI.Outcome := Report (Database, "project|dup");
               begin
                  Expect (Exit_Of (Result) = 2, "ambiguity is an argument error");
                  Expect (Contains (Errors (Result), "matching project IDs: 1, 2"), "candidate IDs are listed");
               end;
               Expect (Exit_Of (Report (Database, "project|Dup")) = 2, "matching is case-sensitive");
               Expect (Exit_Of (Report (Database, "project|du")) = 2, "no substring matching");
               Expect (Exit_Of (Report (Database, "summary|--project|dup")) = 2, "--project resolves exactly too");
            end;
         when T020 =>
            A := Register (Database, Parent (Database), "alpha");
            declare
               Result : constant Ada_Quality_Summary.CLI.Outcome := Report (Database, "indicator|XYZ-99");
            begin
               Expect (Exit_Of (Result) = 2, "an unknown indicator is an argument error");
               Expect (Contains (Errors (Result), "unknown indicator XYZ-99"), "the indicator is named");
            end;
            Expect (Exit_Of (Report (Database, "indicator|tst-03")) = 2, "indicator IDs are case-sensitive");
            Expect (Exit_Of (Report (Database, "indicator|TST-03")) = 0, "a registered indicator resolves");
         when others => null;
      end case;
   end Selection;

   ------------------------------------------------------------------------------------------------------------------
   --  History: T021-T025, T047
   ------------------------------------------------------------------------------------------------------------------

   procedure History_Case (Id : Test_Id) is
      Database : constant String := New_Database (Test_Id'Image (Id));
      Project  : Positive;
      Ignored  : Positive;
   begin
      Create (Database);
      Project := Register (Database, Parent (Database), "alpha");
      case Id is
         when T021 =>
            Ignored := Publish (Database, Build (Project, Shape));
            Ignored := Publish (Database, Build (Project, Shape ("DOC-01", Policy => "policy-b")));
            declare
               Text : constant String := Json (Database, "regressions");
            begin
               Expect_Equal (Value (Text, "data.regressions"), "[]", "no source regression across policies");
               Expect_Equal (Value (Text, "data.baseline_exclusions[0].status"), """no_baseline""", "no baseline");
               Expect_Equal (Value (Text, "data.baseline_exclusions[0].excluded_runs[0].reason"),
                             """policy_changed""", "the incompatible predecessor is explained");
            end;
         when T022 =>
            Ignored := Publish (Database, Build (Project, Shape));
            Ignored := Publish (Database, Build (Project, Shape ("DOC-02 TST-01")));
            declare
               Text  : constant String := Json (Database, "regressions|--sort|indicator");
               Count : constant Natural := Count_Of (Text, "data.regressions");
               Seen  : Ada.Strings.Unbounded.Unbounded_String;

               --  Index of the regression with this indicator and kind, or -1.
               function Find (Indicator, Kind : String) return Integer is
               begin
                  for Index in 0 .. Count - 1 loop
                     if Value (Text, "data.regressions[" & Image (Index) & "].indicator_id") = '"' & Indicator & '"'
                       and then Value (Text, "data.regressions[" & Image (Index) & "].kind") = '"' & Kind & '"'
                     then
                        return Index;
                     end if;
                  end loop;
                  return -1;
               end Find;
            begin
               for Index in 0 .. Count - 1 loop
                  Append (Seen, " " & Value (Text, "data.regressions[" & Image (Index) & "].indicator_id") & "/" &
                            Value (Text, "data.regressions[" & Image (Index) & "].kind"));
               end loop;
               Expect_Equal (Value (Text, "data.regressions[0].indicator_id"), """TST-01""", "registry order");
               Expect (Find ("TST-01", "failed_gate") >= 0, "gates fail:" & To_String (Seen));
               Expect (Find ("DOC-02", "new_violation") >= 0, "nongates violate:" & To_String (Seen));
               Expect (Find ("DOC-02", "new_violation") < 0 or else
                         Value (Text, "data.regressions[" & Image (Find ("DOC-02", "new_violation")) & "].before") =
                         """succeeded/pass""",
                       "before state");
               Expect (Find ("DOC-02", "introduced_finding") >= 0,
                       "a finding absent from all earlier evidence is introduced:" & To_String (Seen));
               Expect_Equal (Value (Text, "data.projects_affected"), "1", "one project is affected");
            end;
         when T023 =>
            Ignored := Publish (Database, Build (Project, Shape));
            Ignored := Publish (Database, Build (Project, Shape (Unknowns => "DOC-02")));
            Expect_Equal (Value (Json (Database, "regressions"), "data.regressions[0].kind"), """lost_evidence""",
                          "pass to unknown loses evidence");
         when T024 =>
            Ignored := Publish (Database, Build (Project, Shape));
            Ignored := Publish (Database, Build (Project, Shape (Unknowns => "SRC-01")));
            declare
               Text : constant String := Json (Database, "trends");
               Proj : constant String := Json (Database, "project|alpha");
            begin
               Expect_Equal (Value (Text, "data.series[2].indicator_id"), """SRC-01""", "series in registry order");
               Expect_Equal (Value (Text, "data.series[2].excluded_observations"), "1",
                             "the unavailable measurement is excluded and counted");
               Expect_Equal (Value (Proj, "data.indicators[13].measurement.kind"), """unavailable""", "tagged");
               Expect_Equal (Value (Proj, "data.indicators[13].measurement.reason"), """tool unavailable""",
                             "the explanation is preserved");
            end;
         when T025 =>
            Ignored := Publish (Database, Build (Project, Shape (Coverage => 9_123)));
            declare
               Text : constant String := Json (Database, "project|alpha");
            begin
               Expect_Equal (Value (Text, "data.indicators[11].id"), """TST-03""", "TST-03 position");
               Expect_Equal (Value (Text, "data.indicators[11].measurement"),
                             "{""kind"":""decimal"",""basis_points"":9123}", "exact basis points");
               Expect (Contains (Output (Report (Database, "project|alpha|--width|120")), "91.23%"),
                       "terminal renders exact percentages");
               Expect (Contains (Json (Database, "trends"), """unit"":""basis_points"""), "units are preserved");
               Expect_Equal (Value (Json (Database, "trends|--since|2100-01-01"), "data.series[1].measurement_kind"),
                             """decimal""", "an empty series keeps the indicator's measurement kind");
            end;
         when T047 =>
            Ada_Quality.Storage.Testing_Use_Legacy_Evidence (True);
            Ignored := Publish (Database, Build (Project, Shape ("DOC-01")));
            Ada_Quality.Storage.Testing_Use_Legacy_Evidence (False);
            Ignored := Publish (Database, Build (Register (Database, Parent (Database), "beta"), Shape));
            declare
               Text     : constant String := Json (Database, "history|alpha");
               Filtered : constant String := Json (Database, "history|alpha|--since|2000-01-01");
               Trend    : constant String := Json (Database, "trends|--since|2000-01-01");
               Daily    : constant String := Json (Database, "trends");
            begin
               Expect_Equal (Value (Trend, "data.comparison_metadata.undated_excluded"), "1",
                             "each undated run is reported once, not once per numeric series");
               Expect_Equal (Value (Daily, "data.snapshots[0].projects"), "2", "both projects are in the snapshot");
               Expect_Equal (Value (Daily, "data.snapshots[0].unassessed"), "0",
                             "a legacy assessment precedes every snapshot day and keeps its project assessed");
               Expect_Equal (Value (Daily, "data.snapshots[0].violations"), "1", "the legacy state is classified");
               Expect_Equal (Value (Text, "data.runs[0].finished_at"), "null", "no timestamp is invented");
               Expect_Equal (Value (Text, "data.runs[0].started_at"), "null", "no start time is invented");
               Expect_Equal (Value (Filtered, "data.runs"), "[]", "undated runs are not placed in a date range");
               Expect_Equal (Value (Filtered, "data.undated_excluded"), "1", "the exclusion is reported");
               Expect_Equal (Value (Json (Database, "project|alpha"), "data.findings[0].line"), "null",
                             "legacy finding locations are absent, not inferred");
            end;
         when others => null;
      end case;
   end History_Case;

   ------------------------------------------------------------------------------------------------------------------
   --  Terminal: T026-T031
   ------------------------------------------------------------------------------------------------------------------

   procedure Terminal_Case (Id : Test_Id) is
      Database : constant String := Standard_Database (Test_Id'Image (Id));
   begin
      case Id is
         when T026 | T027 | T028 =>
            declare
               Width : constant Positive := (case Id is when T026 => 40, when T027 => 80, when others => 120);
               Image : constant String := Ada.Strings.Fixed.Trim (Positive'Image (Width), Ada.Strings.Both);
            begin
               for Command of All_Commands loop
                  for Layout of Layout_Names loop
                     declare
                        Result : constant Ada_Quality_Summary.CLI.Outcome :=
                          Report (Database, Command.all & "|--width|" & Image & "|--layout|" & Layout.all);
                     begin
                        Expect (Exit_Of (Result) = 0, Command.all & " renders: " & Errors (Result));
                        Expect (Fits (Output (Result), Width), Command.all & " " & Layout.all & " fits " & Image);
                     end;
                  end loop;
               end loop;
               declare
                  Summary : constant String := Output (Report (Database, "summary|--width|" & Image));
               begin
                  Expect (Contains (Summary, "VIOLATIONS"), "statuses are spelled out at every width");
                  if Id = T027 then
                     Expect (Contains (Summary, "Unknown") and then Contains (Summary, "N/A"),
                             "standard width shows indicator counts");
                     Expect (not Contains (Summary, "  Path"), "standard width omits expanded columns");
                  elsif Id = T028 then
                     Expect (Contains (Summary, "Path") and then Contains (Summary, "Regr"),
                             "wide terminals show expanded columns");
                  else
                     Expect (Contains (Summary, "Fail"), "narrow tables keep essential columns");
                  end if;
               end;
            end;
         when T029 =>
            declare
               Unicode  : constant String := New_Database ("unicode");
               Name     : constant String :=
                 "proj-" & Character'Val (16#C3#) & Character'Val (16#BC#) & Character'Val (16#E6#) &
                 Character'Val (16#BC#) & Character'Val (16#A2#) & Character'Val (16#E5#) & Character'Val (16#AD#) &
                 Character'Val (16#97#) & "-with-a-rather-long-directory-name";
               Project  : Positive;
               Ignored  : Positive;
            begin
               Create (Unicode);
               Project := Register (Unicode, Parent (Unicode), Name);
               Ignored := Publish (Unicode, Build (Project, Shape ("DOC-01")));
               for Width of Unicode_Widths loop
                  declare
                     Text : constant String := Output
                       (Report (Unicode, "summary|--width|" & Ada.Strings.Fixed.Trim (Integer'Image (Width),
                                                                                    Ada.Strings.Both)));
                     Decoded : constant Wide_Wide_String := Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Text);
                  begin
                     Expect (Decoded'Length > 0, "terminal output is valid UTF-8");
                     Expect (Fits (Text, Width), "wide characters are measured in display cells");
                  end;
               end loop;
               Expect_Equal (Value (Json (Unicode, "summary"), "data.projects[0].name"), """" & Name & """",
                             "JSON keeps the full Unicode name");
            end;
         when T030 =>
            Set_Env ("NO_COLOR", "1");
            Expect (not Has_Escape (Output (Report (Database, "summary|--color|auto"))), "NO_COLOR disables color");
            Expect (not Has_Escape (Output (Report (Database, "summary"))), "the default honors NO_COLOR");
            Expect (Has_Escape (Output (Report (Database, "summary|--color|always"))), "always overrides NO_COLOR");
            Expect (not Has_Escape (Output (Report (Database, "summary|--no-color"))), "--no-color disables color");
            Expect (not Has_Escape (Json (Database, "summary|--color|always")), "JSON is never styled");
            Clear_Env ("NO_COLOR");
            declare
               Colored : constant String := Output (Report (Database, "summary|--color|always"));
            begin
               Expect (Contains (Colored, "VIOLATIONS") and then Contains (Colored, "INCOMPLETE"),
                       "status text is present alongside color");
            end;
         when T031 =>
            Clear_Env ("NO_COLOR");
            declare
               Result : constant Process_Result := Spawn ("--database|" & Database & "|summary");
            begin
               Expect (Result.Status = 0, "redirected report succeeds");
               Expect (not Has_Escape (To_String (Result.Output)), "redirected output has no automatic styling");
               Expect (Has_Escape (To_String (Spawn ("--database|" & Database & "|summary|--color|always").Output)),
                       "explicit color still applies when redirected");
            end;
         when others => null;
      end case;
   end Terminal_Case;

   ------------------------------------------------------------------------------------------------------------------
   --  JSON: T032-T034, round trip
   ------------------------------------------------------------------------------------------------------------------

   function Schema_Name (Command : String) return String is
      Bar : constant Natural := Ada.Strings.Fixed.Index (Command, "|");
   begin
      return (if Bar = 0 then Command else Command (Command'First .. Bar - 1)) & ".schema.json";
   end Schema_Name;

   procedure JSON_Case (Id : Test_Id) is
      Database : constant String := Standard_Database (Test_Id'Image (Id));
      Ignored  : Positive;
   begin
      --  A running run, an interrupted run, and a removed project exercise nullable and enumerated fields.
      Ignored := Start (Database, 3);
      for Command of All_Commands loop
         for Variant of Variants loop
            declare
               Text : constant String := Json (Database, Command.all & Variant.all);
            begin
               case Id is
                  when T032 =>
                     declare
                        Problem : constant String := Aqs_Schema.Validate (Schemas, Schema_Name (Command.all), Text);
                     begin
                        Expect (Problem = "", Command.all & Variant.all & " validates: " & Problem);
                     end;
                     Expect_Equal (Value (Text, "schema_version"), "1", "versioned envelope");
                     Expect (not Contains (Text, "quality.db"), "the database filename is not embedded");
                  when T033 =>
                     Expect (Text = Json (Database, Command.all & Variant.all), "byte-identical repeated export");
                  when X_Round_Trip =>
                     declare
                        Doc   : Jsonlib.Documents.Document;
                        Error : Jsonlib.Errors.Error_Info;
                     begin
                        Jsonlib.Parsers.Parse (Text, Doc, Error);
                        if Variant.all /= "|--pretty" then
                           Expect (Jsonlib.Serializers.To_String (Doc) & LF = Text,
                                   "parsing and serializing preserve every field");
                        end if;
                     end;
                  when others => null;
               end case;
            end;
         end loop;
      end loop;
      if Id = T032 then
         Expect (Aqs_Schema.Validate (Schemas, "summary.schema.json", "{""schema_version"":1}") /= "",
                 "the validator rejects incomplete documents");
         Expect (Aqs_Schema.Matches ("^(STR|BLD)-[0-9]{2}$", "BLD-04"), "pattern alternation");
         Expect (not Aqs_Schema.Matches ("^[0-9]{2}$", "123"), "pattern anchoring");
      end if;
   end JSON_Case;

   procedure Parity is
      Database : constant String := Standard_Database ("T034");
      Text     : constant String := Json (Database, "summary");
      Terminal : constant String := Output (Report (Database, "summary|--width|100"));

      function Line_Value (Label : String) return String is
         Position : constant Natural := Ada.Strings.Fixed.Index (Terminal, LF & "  " & Label);
         Stop     : constant Natural := Ada.Strings.Fixed.Index (Terminal (Position + 1 .. Terminal'Last), [LF]);
      begin
         return Ada.Strings.Fixed.Trim (Terminal (Position + 3 + Label'Length .. Stop - 1), Ada.Strings.Both);
      end Line_Value;
   begin
      Expect_Equal (Line_Value ("Passing"), Value (Text, "data.totals.passing"), "passing parity");
      Expect_Equal (Line_Value ("Violations"), Value (Text, "data.totals.violations"), "violation parity");
      Expect_Equal (Line_Value ("Incomplete"), Value (Text, "data.totals.incomplete"), "incomplete parity");
      Expect_Equal (Line_Value ("Unassessed"), Value (Text, "data.totals.unassessed"), "unassessed parity");
      Expect (Contains (Terminal, "Projects with regressions: " &
                          Value (Text, "data.regression_summary.projects_with_regressions")),
              "regression parity");
      Expect (Contains (Terminal, "Projects: " & Value (Text, "data.totals.projects") & " registered"),
              "population parity");
   end Parity;

   ------------------------------------------------------------------------------------------------------------------
   --  Separate-process behavior: T039-T041, T045, concurrency
   ------------------------------------------------------------------------------------------------------------------

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

   ------------------------------------------------------------------------------------------------------------------
   --  T042-T046, T048-T049
   ------------------------------------------------------------------------------------------------------------------

   procedure Limits is
      Database : constant String := Standard_Database ("T042");
      Store    : Ada_Quality_Summary.Repository.Repository;
      Raised   : Boolean := False;
   begin
      Ada_Quality_Summary.Repository.Open (Store, Database, (Max_Findings => 1, others => <>));
      begin
         declare
            Data : constant Ada_Quality_Summary.Repository.Snapshot := Ada_Quality_Summary.Repository.Load (Store);
         begin
            Expect (Ada_Quality_Summary.Repository.Schema_Version (Data) = 3, "unreachable");
         end;
      exception
         when Ada_Quality_Summary.Report_Error => Raised := True;
      end;
      Expect (Raised, "exceeding a resource limit is a typed reporting failure");
      declare
         Generous : Ada_Quality_Summary.Repository.Repository;
      begin
         Ada_Quality_Summary.Repository.Open (Generous, Database, (Max_Findings => 10, others => <>));
         declare
            Data : constant Ada_Quality_Summary.Repository.Snapshot := Ada_Quality_Summary.Repository.Load (Generous);
         begin
            Expect (Ada_Quality_Summary.Repository.Schema_Version (Data) = 3, "a snapshot within the limit loads");
         end;
      end;
      declare
         Raised_JSON : Boolean := False;
      begin
         begin
            declare
               Ignored : constant String :=
                 Ada_Quality_Summary.JSON.Render (Ada_Quality_Summary.Reports.Report'(others => <>), False, 10);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Ada_Quality_Summary.Report_Error => Raised_JSON := True;
         end;
         Expect (Raised_JSON, "an oversized JSON document is a typed reporting failure");
      end;
   end Limits;

   procedure Large is
      Database : constant String := New_Database ("T043");
      Ignored  : Positive;
      Count    : constant := 40;
      Store    : Ada_Quality.Storage.Store;
   begin
      Ada_Quality.Storage.Open (Store, Database);
      for Index in 1 .. Count loop
         declare
            Name    : constant String := "p" & Ada.Strings.Fixed.Trim (Integer'Image (1_000 + Index), Ada.Strings.Both);
            Project : constant Positive := Register (Store, Parent (Database), Name);
         begin
            case Index mod 4 is
               when 0 => Ignored := Publish (Store, Build (Project, Shape));
               when 1 => Ignored := Publish (Store, Build (Project, Shape ("DOC-01 SRC-0" &
                                                              Character'Val (48 + Index mod 6 + 1))));
               when 2 => Ignored := Publish (Store, Build (Project, Shape (Unknowns => "BLD-02")));
               when others => null;
            end case;
         end;
      end loop;
      Ada_Quality.Storage.Close (Store);
      declare
         First  : constant String := Json (Database, "summary");
         Second : constant String := Json (Database, "summary");
         Matrix : constant String := Json (Database, "indicators");
      begin
         Expect (First = Second, "large aggregation is deterministic");
         Expect_Equal (Value (First, "data.totals.projects"), "40", "every project is aggregated");
         Expect_Equal (Value (First, "data.totals.passing"), "10", "passing count");
         Expect_Equal (Value (First, "data.totals.violations"), "10", "violation count");
         Expect_Equal (Value (First, "data.totals.incomplete"), "10", "incomplete count");
         Expect_Equal (Value (First, "data.totals.unassessed"), "10", "unassessed count");
         Expect (Count_Of (First, "data.projects") = 40, "the overview lists every project without a limit");
         for Index in 0 .. 32 loop
            declare
               Row : constant String := "data.indicators[" & Ada.Strings.Fixed.Trim (Integer'Image (Index),
                                                                                    Ada.Strings.Both) & "].";
            begin
               Expect (Int (Value (Matrix, Row & "passed")) + Int (Value (Matrix, Row & "violated")) +
                         Int (Value (Matrix, Row & "unknown")) + Int (Value (Matrix, Row & "not_applicable")) +
                         Int (Value (Matrix, Row & "missing")) = 40, "indicator states sum to the population");
            end;
         end loop;
      end;
   end Large;

   procedure Registry_Grouping is
      Database : constant String := Standard_Database ("T044");
      Text     : constant String := Json (Database, "indicators");
      Counts   : array (Ada_Quality.Indicators.Indicator_Category) of Natural := [others => 0];
   begin
      Expect (Count_Of (Text, "data.indicators") = 33, "all 33 indicators are reported");
      for Id in Indicator_Id loop
         declare
            Row : constant String := "data.indicators[" &
              Ada.Strings.Fixed.Trim (Integer'Image (Indicator_Id'Pos (Id)), Ada.Strings.Both) & "].";
         begin
            Expect_Equal (Value (Text, Row & "id"), """" & Image (Id) & """", "registry order");
            Counts (Ada_Quality.Indicators.Registry (Id).Category) :=
              Counts (Ada_Quality.Indicators.Registry (Id).Category) + 1;
         end;
      end loop;
      Expect (Counts = [5, 4, 4, 6, 3, 3, 3, 4, 1], "registry grouping matches the fixed categories");
      Expect_Equal (Value (Text, "data.indicators[0].category"), """structure""", "categories come from the registry");
   end Registry_Grouping;

   procedure Unchanged is
      Database : constant String := Standard_Database ("T046");
      Before   : constant File_State_Vectors.Vector := Capture (Parent (Database));
   begin
      for Command of All_Commands loop
         for Format of Format_Names loop
            Expect (Exit_Of (Report (Database, Command.all & "|--format|" & Format.all)) = 0, Command.all);
         end loop;
      end loop;
      Expect (Same (Before, Capture (Parent (Database))), "no report changes any database artifact");
   end Unchanged;

   procedure Limit_Totals is
      Database : constant String := Standard_Database ("T048");
      Text     : constant String := Json (Database, "summary|--limit|1");
   begin
      Expect_Equal (Value (Text, "data.totals.projects"), "3", "totals are computed before the row limit");
      Expect (Count_Of (Text, "data.projects") = 1, "the limit applies to rows");
      Expect (Count_Of (Json (Database, "summary|--limit|0"), "data.projects") = 3, "--limit 0 means no limit");
      Expect (Contains (Output (Report (Database, "summary|--limit|1")), "Showing 1 of 3 rows"),
              "terminal output states that rows were limited");
   end Limit_Totals;

   procedure Unknown_Option is
      Result : constant Ada_Quality_Summary.CLI.Outcome := Run ("summary --frobnicate");
   begin
      Expect (Exit_Of (Result) = 2, "unknown options exit 2");
      Expect (Contains (Errors (Result), "unknown option --frobnicate"), "the option is named");
      Expect (Output (Result) = "", "nothing is written to standard output");
      Expect (Spawn ("--frobnicate").Status = 2, "the executable exits 2");
   end Unknown_Option;

   ------------------------------------------------------------------------------------------------------------------
   --  Units and properties
   ------------------------------------------------------------------------------------------------------------------

   procedure Option_Parsing is
      function Fails (Arguments : String) return Boolean is (Exit_Of (Run (Arguments)) = 2);
      Parsed : Ada_Quality_Summary.Options.Options;
      Items  : Ada_Quality_Summary.Options.String_Vectors.Vector;
   begin
      Expect (Fails ("summary projects"), "exactly one command");
      Expect (Fails ("project"), "PROJECT is mandatory");
      Expect (Fails ("history"), "PROJECT is mandatory for history");
      Expect (Fails ("indicator"), "ID is mandatory");
      Expect (Fails ("project x --project y"), "--project only for collections");
      Expect (Fails ("summary --since 2026-01-01"), "--since only for history commands");
      Expect (Fails ("trends --since 2026-02-30"), "invalid calendar dates are rejected");
      Expect (Fails ("trends --since 2026-1-01"), "dates use YYYY-MM-DD");
      Expect (Fails ("trends --since 2026-03-02 --until 2026-03-01"), "since must not follow until");
      Expect (Fails ("summary --format json --layout compact"), "layout is rejected with JSON");
      Expect (Fails ("summary --pretty"), "--pretty requires JSON");
      Expect (Fails ("summary --sort severity"), "unsupported sort keys are rejected");
      Expect (Fails ("summary --sort nonsense"), "unknown sort keys are rejected");
      Expect (Fails ("summary --limit -1"), "negative limits are rejected");
      Expect (Fails ("summary --width 10"), "too narrow widths are rejected");
      Expect (Fails ("summary --width 501"), "too wide widths are rejected");
      Expect (Fails ("summary --color blue"), "invalid color modes are rejected");
      Expect (Fails ("summary --no-color --color never"), "--no-color and --color are one option");
      Expect (Fails ("summary --limit 1 --limit 2"), "duplicate scalar options are rejected");
      Expect (Fails ("summary --status great"), "unknown statuses are rejected");
      Expect (Fails ("summary --database"), "missing values are rejected");
      Expect (Fails ("summary --database --format json"), "an option is never taken as another option's value");
      Expect (Fails ("--version --pretty"), "--version takes no other arguments");
      Expect (not Fails ("--version"), "--version alone succeeds");
      Expect (Fails ("summary -x"), "short options are rejected");
      Expect (Fails ("summary --reverse=yes"), "flags take no value");
      Expect (Fails ("help nothing"), "unknown help topics are rejected");
      Items.Append ("--sort=violations");
      Items.Append ("projects");
      Items.Append ("--limit=5");
      Items.Append ("--status");
      Items.Append ("violations");
      Parsed := Ada_Quality_Summary.Options.Parse (Items);
      Expect (Parsed.Command = Ada_Quality_Summary.Options.Projects_Command, "command after option");
      Expect (Parsed.Sort = Ada_Quality_Summary.Options.Sort_Violations, "inline option values");
      Expect (Parsed.Limit = 5 and then Parsed.Has_Status and then
              Parsed.Status = Ada_Quality_Summary.Model.Violations, "scalar options are parsed");
      Expect (Exit_Of (Run ("--version")) = 0 and then Contains (Output (Run ("--version")), "0.1.0"), "version");
      Expect (Exit_Of (Run ("summary --format json --color always")) /= 2,
              "terminal color options are ignored, not rejected, for JSON");
   end Option_Parsing;

   procedure Precedence is
      Directory : constant String := Absolute (Dir ("precedence"));
      Explicit  : constant String := Standard_Database ("precedence-explicit");
      From_Env  : constant String := New_Database ("precedence-env");
      Saved_Dir : constant String := Ada.Directories.Current_Directory;
   begin
      Create (From_Env);
      Set_Env ("ADA_QUALITY_DATABASE", From_Env);
      Expect_Equal (Value (Output (Run ("summary --format json")), "data.totals.projects"), "0",
                    "ADA_QUALITY_DATABASE is used without --database");
      Expect_Equal (Value (Json (Explicit, "summary"), "data.totals.projects"), "3", "--database takes precedence");
      Clear_Env ("ADA_QUALITY_DATABASE");
      Ada.Directories.Set_Directory (Directory);
      declare
         Result : constant Ada_Quality_Summary.CLI.Outcome := Run ("summary");
      begin
         Ada.Directories.Set_Directory (Saved_Dir);
         Expect (Exit_Of (Result) = 4 and then Contains (Errors (Result), ".ada-quality.db"),
                 "the working-directory default is used last");
         Expect (not Ada.Directories.Exists (Directory & "/.ada-quality.db"), "the default is not created");
      end;
      Ada.Directories.Copy_File (Explicit, Directory & "/.ada-quality.db");
      Ada.Directories.Set_Directory (Directory);
      declare
         Result : constant Ada_Quality_Summary.CLI.Outcome := Run ("projects --format json");
      begin
         Ada.Directories.Set_Directory (Saved_Dir);
         Expect (Exit_Of (Result) = 0, "the default database is read: " & Errors (Result));
      end;
   exception
      when others =>  --  AQ: audited exception boundary -- restores the directory and environment, re-raises
         Ada.Directories.Set_Directory (Saved_Dir);
         Clear_Env ("ADA_QUALITY_DATABASE");
         raise;
   end Precedence;

   procedure Properties is
      use Ada_Quality_Summary.Model;
      use type Indicator_Summary_Vectors.Vector;
      Database : constant String := Standard_Database ("properties");
      Store    : Ada_Quality_Summary.Repository.Repository;
   begin
      Ada_Quality_Summary.Repository.Open (Store, Database);
      declare
         Data     : constant Ada_Quality_Summary.Repository.Snapshot := Ada_Quality_Summary.Repository.Load (Store);
         Registry : constant Ada_Quality.Reporting.Project_Vectors.Vector :=
           Ada_Quality_Summary.Repository.Projects (Data, Include_Removed => False);
         Rows     : constant Project_Vectors.Vector := Ada_Quality_Summary.Aggregation.Build_Projects (Data, Registry);
         Reversed : Project_Vectors.Vector;
         Value    : constant Ada_Quality.Reporting.Assessment_Record :=
           Ada_Quality_Summary.Repository.Assessment (Data, Ada_Quality_Summary.Repository.Current_Run (Data, 2));
         Shuffled : Result_Vectors.Vector;
      begin
         for Index in reverse Rows.First_Index .. Rows.Last_Index loop
            Reversed.Append (Rows (Index));
         end loop;
         Expect (Ada_Quality_Summary.Aggregation.Build_Totals (Rows) =
                   Ada_Quality_Summary.Aggregation.Build_Totals (Reversed),
                 "reordering projects never changes totals");
         Expect (Ada_Quality_Summary.Aggregation.Build_Indicators (Data, Rows) =
                   Ada_Quality_Summary.Aggregation.Build_Indicators (Data, Reversed),
                 "reordering projects never changes the indicator matrix");
         for Index in reverse Value.Results.First_Index .. Value.Results.Last_Index loop
            Shuffled.Append (Value.Results (Index));
         end loop;
         Expect (Classify (Shuffled) = Classify (Value.Results), "reordering results never changes compliance");
         Expect (Count_Indicators (Shuffled) = Count_Indicators (Value.Results), "or counts");
         Expect (Sum (Count_Indicators (Value.Results)) = 33, "P+V+U+N=33");
         declare
            Totals : constant Portfolio_Totals := Ada_Quality_Summary.Aggregation.Build_Totals (Rows);
            Fewer  : Project_Vectors.Vector := Rows;
         begin
            Expect (Totals.Passing + Totals.Violations + Totals.Incomplete + Totals.Unassessed = Totals.Projects,
                    "categories reproduce the population");
            Fewer.Delete_Last;
            for Indicator of Ada_Quality_Summary.Aggregation.Build_Indicators (Data, Fewer) loop
               declare
                  Full : constant Indicator_Summary :=
                    Ada_Quality_Summary.Aggregation.Build_Indicator (Data, Rows, Indicator.Id);
               begin
                  Expect (Indicator.Totals.Violated <= Full.Totals.Violated and then
                          Indicator.Totals.Passed <= Full.Totals.Passed,
                          "filtering the population cannot introduce a result");
               end;
            end loop;
         end;
      end;
      --  Each report compares a project with its baseline at most once, and only when it shows regressions.
      declare
         function Comparisons_For (Arguments : String) return Natural is
            Before : constant Natural := Ada_Quality_Summary.Trends.Comparisons;
            Result : constant Ada_Quality_Summary.CLI.Outcome := Report (Database, Arguments);
         begin
            Expect (Exit_Of (Result) = 0, Arguments & " succeeds");
            return Ada_Quality_Summary.Trends.Comparisons - Before;
         end Comparisons_For;
      begin
         Expect (Comparisons_For ("summary") = 3, "the summary compares each of three projects once");
         Expect (Comparisons_For ("projects") = 3, "projects compares each project once");
         Expect (Comparisons_For ("regressions") = 3, "regressions compares each project once");
         Expect (Comparisons_For ("project|alpha") = 1, "a project report compares one project once");
         Expect (Comparisons_For ("history|alpha") = 1, "a history report compares one project once");
         Expect (Comparisons_For ("indicators") = 0, "indicators makes no comparison");
         Expect (Comparisons_For ("problems") = 0, "problems makes no comparison");
         Expect (Comparisons_For ("trends") = 0, "trends makes no baseline comparison");
      end;
      --  Every positive identity parses, however many digits it has; nothing beyond Positive'Last does.
      declare
         use Ada_Quality_Summary.Filtering;
         Id   : Natural;
         Last : constant String := Ada.Strings.Fixed.Trim (Positive'Image (Positive'Last), Ada.Strings.Left);
      begin
         Expect (Parse_Project_Id ("7", Id) and then Id = 7, "a small identity parses");
         Expect (Parse_Project_Id ("1000000000", Id) and then Id = 1_000_000_000, "a ten-digit identity parses");
         Expect (Parse_Project_Id (Last, Id) and then Id = Positive'Last, "Positive'Last parses");
         Expect (not Parse_Project_Id (Last & "0", Id) and then Id = 0,
                 "a value beyond Positive'Last is not an identity");
         Expect (not Parse_Project_Id ([1 .. 40 => '9'], Id) and then Id = 0,
                 "a very long number is rejected without overflow");
         Expect (not Parse_Project_Id ("0", Id) and then Id = 0, "zero is not an identity");
         Expect (not Parse_Project_Id ("12a", Id) and then Id = 0
                   and then not Parse_Project_Id ("", Id) and then Id = 0,
                 "only digits form an identity");
      end;
   end Properties;

   procedure Display is
      package T renames Ada_Quality_Summary.Terminal;
      type Text_Access is access constant String;
      type Text_List is array (Positive range <>) of Text_Access;
      Narrow_Widths   : constant Text_List := [new String'("1"), new String'("4"), new String'("19")];
      Narrow_Commands : constant Text_List :=
        [new String'("summary"), new String'("projects"), new String'("project|alpha"), new String'("indicators"),
         new String'("indicator|TST-03"), new String'("problems"), new String'("regressions"), new String'("trends"),
         new String'("history|alpha")];
      Wide : constant String := Character'Val (16#E6#) & Character'Val (16#BC#) & Character'Val (16#A2#);
      Mark : constant String := "e" & Character'Val (16#CC#) & Character'Val (16#81#);
      Red  : constant String := Character'Val (27) & "[31mred" & Character'Val (27) & "[0m";
   begin
      Expect (T.Display_Width (Wide & Wide & "ab") = 6, "East Asian wide characters take two cells");
      Expect (T.Display_Width (Mark) = 1, "combining characters take no cell");
      Expect (T.Display_Width (Red) = 3, "ANSI escapes take no cell");
      Expect (T.Display_Width (T.Fit (Wide & Wide & Wide & "abc", 5, True)) <= 5, "fitting respects wide cells");
      Expect (T.Fit ("abcdef", 4, False) = "a...", "ASCII ellipsis");
      Expect (T.Fit ("abc", 4, True) = "abc", "short text is unchanged");
      Expect (T.Pad ("7", 3, Right => True) = "  7", "integers align right");
      Expect (T.Basis_Points_Image (9_123) = "91.23%", "basis points");
      Expect (T.Basis_Points_Image (5) = "0.05%", "small basis points");
      Expect (T.Basis_Points_Image (-150) = "-1.50%", "negative basis points");
      Expect (T.Detect_Width (77) = 77, "an explicit width wins");
      Set_Env ("COLUMNS", "93");
      Expect (T.Detect_Width (0) in 1 .. 500, "a detected width is bounded");
      Set_Env ("COLUMNS", "9999");
      Expect (T.Detect_Width (0) <= 500, "the maximum width is enforced");
      for Narrow of Narrow_Widths loop
         Set_Env ("COLUMNS", Narrow.all);
         Expect (T.Detect_Width (0) >= Ada_Quality_Summary.Options.Minimum_Width,
                 "a detected width of " & Narrow.all & " is raised to the minimum");
      end loop;
      --  A child process writes to a pipe, so it takes its width from COLUMNS.
      Set_Env ("COLUMNS", "1");
      declare
         Database : constant String := Standard_Database ("narrow");
      begin
         for Command of Narrow_Commands loop
            declare
               Result : constant Process_Result := Spawn ("--database|" & Database & "|" & Command.all);
               Text   : constant String := To_String (Result.Output);
               Start  : Positive := Text'First;
            begin
               Expect (Result.Status = 0, Command.all & " succeeds at COLUMNS=1");
               for Index in Text'Range loop
                  if Text (Index) = ASCII.LF then
                     Expect (T.Display_Width (Text (Start .. Index - 1)) <= Ada_Quality_Summary.Options.Minimum_Width,
                             Command.all & " fits the minimum width: " & Text (Start .. Index - 1));
                     Start := Index + 1;
                  end if;
               end loop;
            end;
         end loop;
      end;
      Clear_Env ("COLUMNS");
      Set_Env ("LC_ALL", "C");
      Expect (not T.Unicode_Locale, "C locale is ASCII-only");
      Set_Env ("LC_ALL", "en_US.UTF-8");
      Expect (T.Unicode_Locale, "UTF-8 locale");
      Clear_Env ("LC_ALL");
   end Display;

   procedure Catalog is
   begin
      Expect (Ada_Quality_Summary.Text.Catalog_Is_Valid, "the message catalog is valid");
      Expect (Ada_Quality_Summary.Text.Has_Message ("label.title"), "labels are cataloged");
      declare
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant String := Ada_Quality_Summary.Text.Message ("no.such.key");
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Ada_Quality_Summary.Report_Error => Raised := True;
         end;
         Expect (Raised, "unknown keys are reporting failures");
      end;
   end Catalog;

   procedure Help_Topics is
   begin
      for Command in Ada_Quality_Summary.Options.Summary_Command .. Ada_Quality_Summary.Options.Help_Command loop
         declare
            Topic  : constant String := Ada_Quality_Summary.Options.Name (Command);
            Result : constant Ada_Quality_Summary.CLI.Outcome := Run ("help " & Topic);
         begin
            Expect (Exit_Of (Result) = 0 and then Contains (Output (Result), Topic), "help " & Topic);
            Expect (Exit_Of (Run (Topic & " --help")) = 0, Topic & " --help");
         end;
      end loop;
      Expect (Contains (Output (Run ("help")), "Commands:"), "general help lists commands");
      Expect (Contains (Output (Run ("help trends")), "--since"), "historical help lists date options");
      Expect (not Contains (Output (Run ("help project")), "--since"), "detail help omits date options");
   end Help_Topics;

   procedure Layouts is
      Database : constant String := Standard_Database ("layouts");
      Compact  : constant String := Output (Report (Database, "project|beta|--layout|compact|--width|120"));
      Detailed : constant String := Output (Report (Database, "project|beta|--layout|detailed|--width|120"));
   begin
      Expect (not Contains (Compact, "FINDINGS"), "compact omits expanded findings");
      Expect (Contains (Detailed, "EVIDENCE") and then Contains (Detailed, "policy-a"),
              "detailed shows evidence and fingerprints");
      Expect (Contains (Output (Report (Database, "summary|--layout|compact|--width|80")), "VIOL"),
              "compact abbreviates statuses");
      Expect (Contains (Output (Report (Database, "trends|--width|100")), "LAST-KNOWN STATE BY DAY"),
              "trends show daily last-known states");
      Expect (Contains (Output (Report (Database, "regressions|--layout|detailed")), "compared with baseline"),
              "detailed regressions explain every baseline");
      Expect (Exit_Of (Report (Database, "trends|--since|2000-01-01|--until|2099-12-31")) = 0, "date filters");
   end Layouts;

   procedure Sorting is
      Database : constant String := Standard_Database ("sorting");
   begin
      Expect_Equal (Value (Json (Database, "summary"), "data.projects[0].name"), """beta""",
                    "overview priority: incomplete first");
      Expect_Equal (Value (Json (Database, "summary|--reverse"), "data.projects[0].name"), """gamma""",
                    "--reverse reverses the ordering");
      Expect_Equal (Value (Json (Database, "projects|--sort|id|--reverse"), "data.projects[0].project_id"), "3",
                    "sort by identity");
      Expect_Equal (Value (Json (Database, "projects|--status|unassessed"), "data.totals.projects"), "1",
                    "status filters apply before totals");
      Expect_Equal (Value (Json (Database, "indicators|--sort|violations"), "data.indicators[0].violated"), "1",
                    "indicator sorting");
      Expect_Equal (Value (Json (Database, "problems|--sort|project"), "data.findings[0].project_id"), "1",
                    "finding sorting by project");
      Expect_Equal (Value (Json (Database, "problems"), "data.findings[0].severity"), """medium""",
                    "findings default to severity order");
      Expect_Equal (Value (Json (Database, "history|alpha"), "data.runs[0].run_id"), "2", "history is newest first");
      Expect_Equal (Value (Json (Database, "summary|--project|gamma"), "data.totals.projects"), "1",
                    "--project restricts collections");
      Expect_Equal (Value (Json (Database, "indicator|TST-03|--sort|name"), "data.projects[0].name"), """alpha""",
                    "indicator rows by name");
      Expect_Equal (Value (Json (Database, "project|beta|--sort|state"), "data.indicators[0].compliance"),
                    """violation""", "project rows by state");
      Expect_Equal (Value (Json (Database, "projects|--sort|violations"), "data.projects[0].name"), """beta""",
                    "projects by violations");
      Expect_Equal (Value (Json (Database, "projects|--sort|unknown"), "data.projects[0].name"), """beta""",
                    "projects by unknown results");
      Expect_Equal (Value (Json (Database, "projects|--sort|findings"), "data.projects[0].name"), """beta""",
                    "projects by findings");
      Expect_Equal (Value (Json (Database, "projects|--sort|path"), "data.projects[0].name"), """alpha""",
                    "projects by path");
      Expect_Equal (Value (Json (Database, "projects|--sort|quality"), "data.projects[0].name"), """beta""",
                    "projects by quality");
      Expect_Equal (Value (Json (Database, "summary|--sort|name"), "data.projects[0].name"), """alpha""",
                    "summary by name");
      Expect_Equal (Value (Json (Database, "indicators|--sort|name"), "data.indicators[0].id"), """TST-01""",
                    "indicators by name");
      Expect_Equal (Value (Json (Database, "indicators|--sort|unknown"), "data.indicators[0].id"), """BLD-02""",
                    "indicators by unknown results");
      Expect_Equal (Value (Json (Database, "indicators|--sort|affected"), "data.indicators[0].id"), """TST-03""",
                    "indicators by affected projects");
      Expect_Equal (Value (Json (Database, "indicators|--sort|id|--reverse"), "data.indicators[0].id"), """PRF-01""",
                    "indicators reversed");
      Expect_Equal (Value (Json (Database, "problems|--sort|indicator"), "data.findings[0].indicator_id"),
                    """TST-03""", "findings by indicator");
      Expect_Equal (Value (Json (Database, "regressions|--sort|kind"), "data.regressions[0].kind"),
                    """new_violation""", "regressions by kind");
      Expect_Equal (Value (Json (Database, "regressions|--sort|project"), "data.regressions[0].project_id"), "1",
                    "regressions by project");
      Expect_Equal (Value (Json (Database, "trends|--sort|project"), "data.series[0].points[0].project_id"), "1",
                    "trend points by project");
      Expect_Equal (Value (Json (Database, "trends|--sort|run|--reverse"), "data.series[0].points[0].run_id"), "3",
                    "trend points by run, reversed");
      Expect_Equal (Value (Json (Database, "indicator|TST-03|--sort|id|--reverse"), "data.projects[0].project_id"),
                    "3", "indicator rows by identity");
   end Sorting;

   procedure Dispatch (Id : Test_Id);

   overriding procedure Run_Test (Item : in out Acceptance_Test) is
      Started : constant Ada.Calendar.Time := Ada.Calendar.Clock;
   begin
      Ada.Directories.Create_Path (Root);
      Dispatch (Item.Id);
      if Ada.Environment_Variables.Exists ("AQS_TIMING") then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            Test_Id'Image (Item.Id) & Duration'Image (Ada.Calendar."-" (Ada.Calendar.Clock, Started)));
      end if;
   end Run_Test;

   procedure Dispatch (Id : Test_Id) is
   begin
      case Id is
         when T001 .. T010 => Classification (Id);
         when T011 .. T013 | T036 .. T038 => Integrity (Id);
         when T014 .. T020 => Selection (Id);
         when T021 .. T025 | T047 => History_Case (Id);
         when T026 .. T031 => Terminal_Case (Id);
         when T032 | T033 | X_Round_Trip => JSON_Case (Id);
         when T034 => Parity;
         when T035 | T050 => Missing (Id);
         when T039 => Locked_Writer;
         when T040 => Publishing_Writer;
         when T041 => Output_Failure;
         when T042 => Limits;
         when T043 => Large;
         when T044 => Registry_Grouping;
         when T045 => No_Tools;
         when T046 => Unchanged;
         when T048 => Limit_Totals;
         when T049 => Unknown_Option;
         when X_Options => Option_Parsing;
         when X_Precedence => Precedence;
         when X_Properties => Properties;
         when X_Display => Display;
         when X_Catalog => Catalog;
         when X_Help => Help_Topics;
         when X_Concurrent_Readers => Concurrent_Readers;
         when X_Recovering_Writer => Recovering_Writer;
         when X_Killed_Reader => Killed_Reader;
         when X_Layouts => Layouts;
         when X_Sorting => Sorting;
      end case;
   end Dispatch;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      type Test_Access is access all AUnit.Simple_Test_Cases.Test_Case'Class;
      Result : constant AUnit.Test_Suites.Access_Test_Suite := AUnit.Test_Suites.New_Suite;
   begin
      for Id in Test_Id loop
         Result.Add_Test (Test_Access'(new Acceptance_Test (Id)));
      end loop;
      return Result;
   end Suite;
end Aqs_Suite;
