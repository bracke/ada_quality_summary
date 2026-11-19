with Ada.Calendar;
with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Finalization;
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
with Ada_Quality.Storage.Testing;
with Ada_Quality.Types;
with Ada_Quality_Summary.Aggregation;
with Ada_Quality_Summary.CLI;
with Ada_Quality_Summary.Completion;
with Ada_Quality_Summary.Criteria;
with Ada_Quality_Summary.Filtering;
with Ada_Quality_Summary.JSON;
with Ada_Quality_Summary.Reports;
with Ada_Quality_Summary.Model;
with Ada_Quality_Summary.Options;
with Ada_Quality_Summary.Repository;
with Ada_Quality_Summary.SARIF;
with Ada_Quality_Summary.Terminal.Cells;
with Ada_Quality_Summary.Terminal.Environment;
with Ada_Quality_Summary.Text;
with Aqs_Fixtures;
with Aqs_Manual;
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
   use type Ada_Quality_Summary.Criteria.Sort_Key;

   type Test_Id is
     (T001, T002, T003, T004, T005, T006, T007, T008, T009, T010, T011, T012, T013, T014, T015, T016, T017, T018,
      T019, T020, T021, T022, T023, T024, T025, T026, T027, T028, T029, T030, T031, T032, T033, T034, T035, T036,
      T037, T038, T039, T040, T041, T042, T043, T044, T045, T046, T047, T048, T049, T050,
      X_Options, X_Precedence, X_Properties, X_Display, X_Catalog, X_Round_Trip, X_Help, X_Concurrent_Readers,
      X_Recovering_Writer, X_Killed_Reader, X_Layouts, X_Sorting, X_Baselines, X_Lifecycle, X_Executions,
      X_Report_Fields, X_Input_Edges, X_Gate, X_Compare, X_Markdown, X_SARIF, X_Waivers, X_Completion);

   type Title_Access is access constant String;

   Titles : constant array (Test_Id) of Title_Access :=
     [T001 => new String'("Empty_Registry"),
      T002 => new String'("Never_Assessed_Project"),
      T003 => new String'("All_Passing"),
      T004 => new String'("One_Violation"),
      T005 => new String'("Incomplete_Assessment"),
      T006 => new String'("Violation_And_Unknown"),
      T007 => new String'("Not_Applicable_Denominator"),
      T008 => new String'("Interrupted_Latest_Run"),
      T009 => new String'("Running_Latest_Run"),
      T010 => new String'("No_Completed_Assessment"),
      T011 => new String'("Duplicate_Indicator_Result"),
      T012 => new String'("Missing_Indicator_Result"),
      T013 => new String'("Invalid_Measurement_Encoding"),
      T014 => new String'("Shared_Fingerprint_Across_Projects"),
      T015 => new String'("Multiple_Findings_One_Indicator"),
      T016 => new String'("Stable_Sort_Equal_Names"),
      T017 => new String'("Disabled_Project"),
      T018 => new String'("Removed_Project"),
      T019 => new String'("Ambiguous_Basename"),
      T020 => new String'("Unknown_Indicator"),
      T021 => new String'("Incompatible_Baseline"),
      T022 => new String'("Pass_To_Violation"),
      T023 => new String'("Pass_To_Unknown"),
      T024 => new String'("Metric_Unavailable"),
      T025 => new String'("Decimal_Measurement"),
      T026 => new String'("Width_40"),
      T027 => new String'("Width_80"),
      T028 => new String'("Width_120"),
      T029 => new String'("Unicode_Paths"),
      T030 => new String'("No_Color"),
      T031 => new String'("Redirected_Stdout"),
      T032 => new String'("JSON_Schemas"),
      T033 => new String'("Repeated_JSON_Export"),
      T034 => new String'("JSON_Terminal_Parity"),
      T035 => new String'("Missing_Database"),
      T036 => new String'("Old_Schema"),
      T037 => new String'("Future_Schema"),
      T038 => new String'("Corrupt_Persisted_Data"),
      T039 => new String'("Concurrent_Writer_Lock"),
      T040 => new String'("Writer_Publishes_During_Reports"),
      T041 => new String'("Output_Stream_Failure"),
      T042 => new String'("Resource_Limit"),
      T043 => new String'("Large_Collection"),
      T044 => new String'("All_33_Indicators"),
      T045 => new String'("No_Assessment_Tools_Spawned"),
      T046 => new String'("Database_Unchanged"),
      T047 => new String'("Missing_Timestamps"),
      T048 => new String'("Limit_Keeps_Totals"),
      T049 => new String'("Unknown_CLI_Option"),
      T050 => new String'("Nonexistent_Database_Not_Created"),
      X_Options => new String'("Option_Parsing"),
      X_Precedence => new String'("Database_Precedence"),
      X_Properties => new String'("Aggregation_Properties"),
      X_Display => new String'("Display_Width"),
      X_Catalog => new String'("Message_Catalog"),
      X_Round_Trip => new String'("JSON_Round_Trip"),
      X_Help => new String'("Help_Topics"),
      X_Concurrent_Readers => new String'("Concurrent_Readers"),
      X_Recovering_Writer => new String'("Recovering_Writer"),
      X_Killed_Reader => new String'("Killed_Reader"),
      X_Layouts => new String'("Layouts"),
      X_Sorting => new String'("Sort_Keys"),
      X_Baselines => new String'("Baseline_Reasons"),
      X_Lifecycle => new String'("Finding_Lifecycle"),
      X_Executions => new String'("Execution_Spellings"),
      X_Report_Fields => new String'("Report_Fields"),
      X_Input_Edges => new String'("Input_Edges"),
      X_Gate => new String'("Quality_Gate"),
      X_Compare => new String'("Explicit_Comparison"),
      X_Markdown => new String'("Markdown_Output"),
      X_SARIF => new String'("SARIF_Output"),
      X_Waivers => new String'("Waiver_Report"),
      X_Completion => new String'("Shell_Completion_And_Manual")];

   type Acceptance_Test (Id : Test_Id) is new AUnit.Simple_Test_Cases.Test_Case with null record;
   overriding function Name (Item : Acceptance_Test) return AUnit.Message_String;
   overriding procedure Run_Test (Item : in out Acceptance_Test);

   overriding function Name (Item : Acceptance_Test) return AUnit.Message_String is
      Raw : constant String := Test_Id'Image (Item.Id);
   begin
      return AUnit.Format
        ((if Raw (Raw'First) = 'T' then "AQS_" & Raw & "_" else "AQS_") & Titles (Item.Id).all);
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
      Coverage : Long_Long_Integer := 9_500; Status : Assessment_Status := Assessment_Completed;
      Source : String := "source-a"; Level : Severity := Medium; Unknown_Run : Execution_Status := Blocked;
      Waivers : String := "") return Plan is
     ((Violations => Set_Of (Violations), Unknowns => Set_Of (Unknowns), Not_Applicable => Set_Of (NA),
       Findings => Findings, Fingerprint => To_Unbounded_String (Fingerprint), Level => Level,
       Coverage => Coverage, Source => To_Unbounded_String (Source), Policy => To_Unbounded_String (Policy),
       Toolchain => To_Unbounded_String (Toolchain), Status => Status, Unknown_Run => Unknown_Run,
       Waivers => Set_Of (Waivers)));

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

   Absent : constant String := "<absent>";

   --  Return the compact JSON text of the value at a dotted path such as `data.totals.projects` or
   --  `data.projects[0].quality`, or Absent when the path names nothing.
   function Value_Or_Absent (Text, Path : String) return String is
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
                  return Absent;
               end if;
            end;
            Start := Index + 1;
         end if;
      end loop;
      return Jsonlib.Serializers.To_String (Doc, Item);
   end Value_Or_Absent;

   --  Return the value at Path, failing the test when the path names nothing: a missing or renamed field must not
   --  compare equal to another missing field.
   function Value (Text, Path : String) return String is
      Result : constant String := Value_Or_Absent (Text, Path);
   begin
      Assert (Result /= Absent, "the JSON output has " & Path);
      return Result;
   end Value;

   --  Return the length of the array at Path, failing the test when Path is not an array.
   function Count_Of (Text, Path : String) return Natural is
      Doc   : Jsonlib.Documents.Document;
      Error : Jsonlib.Errors.Error_Info;
      Raw   : constant String := Value (Text, Path);
      use type Jsonlib.Errors.Error_Code;
   begin
      Jsonlib.Parsers.Parse (Raw, Doc, Error);
      Assert (Error.Code = Jsonlib.Errors.No_Error and then Raw (Raw'First) = '[', Path & " is an array");
      return Doc.Length (Doc.Root);
   end Count_Of;

   --  The Field of every element of the array at Path, comma-separated, to compare a whole ordering at once.
   function Column (Text, Path, Field : String) return String is
      Result : Ada.Strings.Unbounded.Unbounded_String;
   begin
      for Index in 0 .. Count_Of (Text, Path) - 1 loop
         if Index > 0 then
            Append (Result, ",");
         end if;
         Append (Result, Value (Text, Path & "[" & Ada.Strings.Fixed.Trim (Index'Image, Ada.Strings.Left) & "]." &
                                  Field));
      end loop;
      return To_String (Result);
   end Column;

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

   --  The first line of Text wider than Width display cells, or Absent; a last line without a line feed counts too.
   function Wider_Line (Text : String; Width : Natural) return String is
      Start : Positive := Text'First;
   begin
      for Index in Text'First .. Text'Last + 1 loop
         if Index > Text'Last or else Text (Index) = LF then
            if Ada_Quality_Summary.Terminal.Cells.Display_Width (Text (Start .. Index - 1)) > Width then
               return Text (Start .. Index - 1);
            end if;
            Start := Index + 1;
         end if;
      end loop;
      return Absent;
   end Wider_Line;

   --  Every line of Text fits Width display cells.
   function Fits (Text : String; Width : Positive) return Boolean is (Wider_Line (Text, Width) = Absent);

   function Has_Escape (Text : String) return Boolean is (Contains (Text, [Character'Val (27)]));

   type Text_Access is access constant String;
   type Text_List is array (Positive range <>) of Text_Access;

   Layout_Names : constant Text_List := [new String'("compact"), new String'("normal"), new String'("detailed")];
   Format_Names : constant Text_List := [new String'("terminal"), new String'("json"), new String'("markdown")];
   Variants     : constant Text_List :=
     [new String'(""), new String'("|--pretty"), new String'("|--limit|1"), new String'("|--include-removed")];
   Trap_Names   : constant Text_List :=
     [new String'("alr"), new String'("gprbuild"), new String'("gnat"), new String'("gnatprove"),
      new String'("gnatdoc"), new String'("gcov"), new String'("git"), new String'("sh"),
      new String'("ada-quality"), new String'("check_all")];
   Unicode_Widths : constant array (1 .. 4) of Positive := [40, 60, 80, 120];

   All_Commands : constant Text_List (1 .. 11) :=
     [new String'("summary"), new String'("projects"), new String'("project|alpha"), new String'("indicators"),
      new String'("indicator|TST-03"), new String'("problems"), new String'("waivers"), new String'("regressions"),
      new String'("compare|1|2"), new String'("trends"), new String'("history|alpha")];

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

   --  Restores one environment variable when it goes out of scope, so a failing test cannot leak a setting into the
   --  tests that follow it.
   type Saved_Variable (Length : Natural) is new Ada.Finalization.Limited_Controlled with record
      Name    : String (1 .. Length);
      Present : Boolean := False;
      Value   : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   overriding procedure Finalize (Item : in out Saved_Variable);

   overriding procedure Finalize (Item : in out Saved_Variable) is
   begin
      if Item.Present then
         Set_Env (Item.Name, To_String (Item.Value));
      else
         Clear_Env (Item.Name);
      end if;
   end Finalize;

   function Saving (Name : String) return Saved_Variable is
   begin
      return Item : Saved_Variable (Name'Length) do
         Item.Name := Name;
         Item.Present := Ada.Environment_Variables.Exists (Name);
         if Item.Present then
            Item.Value := To_Unbounded_String (Ada.Environment_Variables.Value (Name));
         end if;
      end return;
   end Saving;

   --  Classification and counting: T001-T010
   procedure Classification (Id : Test_Id) is separate;

   --  Integrity: T011-T013, T036-T038, T035, T050
   package Integrity_Tests is
      procedure Integrity (Id : Test_Id);
      procedure Missing (Id : Test_Id);
   end Integrity_Tests;
   package body Integrity_Tests is separate;
   use Integrity_Tests;

   --  Findings, selection, and resolution: T014-T020
   procedure Selection (Id : Test_Id) is separate;

   --  History: T021-T025, T047
   procedure History_Case (Id : Test_Id) is separate;

   --  Terminal: T026-T031
   procedure Terminal_Case (Id : Test_Id) is separate;

   --  JSON: T032-T034, round trip
   package JSON_Tests is
      procedure JSON_Case (Id : Test_Id);
      procedure Parity;
   end JSON_Tests;
   package body JSON_Tests is separate;
   use JSON_Tests;

   --  Separate-process behavior: T039-T041, T045, concurrency
   package Process_Tests is
      procedure Locked_Writer;
      procedure Publishing_Writer;
      procedure Concurrent_Readers;
      procedure Recovering_Writer;
      procedure Killed_Reader;
      procedure Output_Failure;
      procedure No_Tools;
   end Process_Tests;
   package body Process_Tests is separate;
   use Process_Tests;

   --  T042-T046, T048-T049
   package Limit_Tests is
      procedure Limits;
      procedure Large;
      procedure Registry_Grouping;
      procedure Unchanged;
      procedure Limit_Totals;
      procedure Unknown_Option;
   end Limit_Tests;
   package body Limit_Tests is separate;
   use Limit_Tests;

   --  Units and properties
   package Unit_Tests is
      procedure Option_Parsing;
      procedure Precedence;
      procedure Properties;
      procedure Display;
      procedure Catalog;
      procedure Help_Topics;
      procedure Layouts;
      procedure Sorting;
   end Unit_Tests;
   package body Unit_Tests is separate;
   use Unit_Tests;

   --  Behaviors found unasserted in review: baseline reasons, finding lifecycles, execution spellings, report
   --  fields, and option and input edges
   package Review_Tests is
      procedure Baseline_Reasons;
      procedure Finding_Lifecycle;
      procedure Execution_Spellings;
      procedure Report_Fields;
      procedure Input_Edges;
   end Review_Tests;
   package body Review_Tests is separate;
   use Review_Tests;

   --  Additions: the --fail-on quality gate, explicit comparisons, Markdown and SARIF output, the waiver report, and
   --  shell completion with the manual page
   package Feature_Tests is
      procedure Quality_Gate;
      procedure Explicit_Comparison;
      procedure Markdown_Output;
      procedure SARIF_Output;
      procedure Waiver_Report;
      procedure Shell_Completion;
   end Feature_Tests;
   package body Feature_Tests is separate;
   use Feature_Tests;

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

   --  Run a test procedure that needs no identity through the uniform runner signature.
   generic
      with procedure Test;
   procedure Ignoring_Id (Id : Test_Id);

   procedure Ignoring_Id (Id : Test_Id) is
      pragma Unreferenced (Id);
   begin
      Test;
   end Ignoring_Id;

   procedure Run_Catalog is new Ignoring_Id (Catalog);
   procedure Run_Concurrent_Readers is new Ignoring_Id (Concurrent_Readers);
   procedure Run_Display is new Ignoring_Id (Display);
   procedure Run_Help_Topics is new Ignoring_Id (Help_Topics);
   procedure Run_Killed_Reader is new Ignoring_Id (Killed_Reader);
   procedure Run_Large is new Ignoring_Id (Large);
   procedure Run_Layouts is new Ignoring_Id (Layouts);
   procedure Run_Limit_Totals is new Ignoring_Id (Limit_Totals);
   procedure Run_Limits is new Ignoring_Id (Limits);
   procedure Run_Locked_Writer is new Ignoring_Id (Locked_Writer);
   procedure Run_No_Tools is new Ignoring_Id (No_Tools);
   procedure Run_Option_Parsing is new Ignoring_Id (Option_Parsing);
   procedure Run_Output_Failure is new Ignoring_Id (Output_Failure);
   procedure Run_Parity is new Ignoring_Id (Parity);
   procedure Run_Precedence is new Ignoring_Id (Precedence);
   procedure Run_Properties is new Ignoring_Id (Properties);
   procedure Run_Publishing_Writer is new Ignoring_Id (Publishing_Writer);
   procedure Run_Recovering_Writer is new Ignoring_Id (Recovering_Writer);
   procedure Run_Registry_Grouping is new Ignoring_Id (Registry_Grouping);
   procedure Run_Sorting is new Ignoring_Id (Sorting);
   procedure Run_Unchanged is new Ignoring_Id (Unchanged);
   procedure Run_Unknown_Option is new Ignoring_Id (Unknown_Option);
   procedure Run_Baseline_Reasons is new Ignoring_Id (Baseline_Reasons);
   procedure Run_Finding_Lifecycle is new Ignoring_Id (Finding_Lifecycle);
   procedure Run_Execution_Spellings is new Ignoring_Id (Execution_Spellings);
   procedure Run_Report_Fields is new Ignoring_Id (Report_Fields);
   procedure Run_Input_Edges is new Ignoring_Id (Input_Edges);
   procedure Run_Quality_Gate is new Ignoring_Id (Quality_Gate);
   procedure Run_Explicit_Comparison is new Ignoring_Id (Explicit_Comparison);
   procedure Run_Markdown_Output is new Ignoring_Id (Markdown_Output);
   procedure Run_SARIF_Output is new Ignoring_Id (SARIF_Output);
   procedure Run_Waiver_Report is new Ignoring_Id (Waiver_Report);
   procedure Run_Shell_Completion is new Ignoring_Id (Shell_Completion);

   type Runner is access procedure (Id : Test_Id);

   Runners : constant array (Test_Id) of Runner :=
     [T001 .. T010 => Classification'Access,
      T011 .. T013 | T036 .. T038 => Integrity'Access,
      T014 .. T020 => Selection'Access,
      T021 .. T025 | T047 => History_Case'Access,
      T026 .. T031 => Terminal_Case'Access,
      T032 | T033 | X_Round_Trip => JSON_Case'Access,
      T034 => Run_Parity'Access,
      T035 | T050 => Missing'Access,
      T039 => Run_Locked_Writer'Access,
      T040 => Run_Publishing_Writer'Access,
      T041 => Run_Output_Failure'Access,
      T042 => Run_Limits'Access,
      T043 => Run_Large'Access,
      T044 => Run_Registry_Grouping'Access,
      T045 => Run_No_Tools'Access,
      T046 => Run_Unchanged'Access,
      T048 => Run_Limit_Totals'Access,
      T049 => Run_Unknown_Option'Access,
      X_Options => Run_Option_Parsing'Access,
      X_Precedence => Run_Precedence'Access,
      X_Properties => Run_Properties'Access,
      X_Display => Run_Display'Access,
      X_Catalog => Run_Catalog'Access,
      X_Help => Run_Help_Topics'Access,
      X_Concurrent_Readers => Run_Concurrent_Readers'Access,
      X_Recovering_Writer => Run_Recovering_Writer'Access,
      X_Killed_Reader => Run_Killed_Reader'Access,
      X_Layouts => Run_Layouts'Access,
      X_Sorting => Run_Sorting'Access,
      X_Baselines => Run_Baseline_Reasons'Access,
      X_Lifecycle => Run_Finding_Lifecycle'Access,
      X_Executions => Run_Execution_Spellings'Access,
      X_Report_Fields => Run_Report_Fields'Access,
      X_Input_Edges => Run_Input_Edges'Access,
      X_Gate => Run_Quality_Gate'Access,
      X_Compare => Run_Explicit_Comparison'Access,
      X_Markdown => Run_Markdown_Output'Access,
      X_SARIF => Run_SARIF_Output'Access,
      X_Waivers => Run_Waiver_Report'Access,
      X_Completion => Run_Shell_Completion'Access];

   procedure Dispatch (Id : Test_Id) is
   begin
      Runners (Id).all (Id);
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
