separate (Aqs_Suite)
package body Unit_Tests is
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
      Expect (Parsed.Sort = Ada_Quality_Summary.Criteria.Sort_Violations, "inline option values");
      Expect (Parsed.Limit = 5 and then Parsed.Has_Status and then
              Parsed.Status = Ada_Quality_Summary.Model.Violations, "scalar options are parsed");
      Expect (Exit_Of (Run ("--version")) = 0 and then Contains (Output (Run ("--version")), "0.1.0"), "version");
      Expect (Exit_Of (Run ("--database|" & Standard_Database ("options") & "|summary|--format|json|--color|always"))
                = 0, "terminal color options are ignored, not rejected, for JSON");
   end Option_Parsing;

   procedure Precedence is
      Directory : constant String := Absolute (Dir ("precedence"));
      Explicit  : constant String := Standard_Database ("precedence-explicit");
      From_Env  : constant String := New_Database ("precedence-env");
      Saved_Dir : constant String := Ada.Directories.Current_Directory;
      Saved_Env : Saved_Variable := Saving ("ADA_QUALITY_DATABASE");
      pragma Unreferenced (Saved_Env);
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
      when others =>  --  AQ: audited exception boundary -- restores the directory and re-raises
         Ada.Directories.Set_Directory (Saved_Dir);
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
            Store : Ada_Quality_Summary.Repository.Repository;
         begin
            Ada_Quality_Summary.Repository.Open (Store, Database);
            declare
               Data : constant Ada_Quality_Summary.Repository.Snapshot := Ada_Quality_Summary.Repository.Load (Store);
            begin
               return Ada_Quality_Summary.Reports.Build
                 (Data, Ada_Quality_Summary.Options.Parse (Arguments_Of (Arguments)), Database).Comparisons;
            end;
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
      package T renames Ada_Quality_Summary.Terminal.Cells;
      package E renames Ada_Quality_Summary.Terminal.Environment;
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
      Saved_Columns : Saved_Variable := Saving ("COLUMNS");
      Saved_Locale  : Saved_Variable := Saving ("LC_ALL");
      pragma Unreferenced (Saved_Columns, Saved_Locale);
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
      Expect (E.Detect_Width (77) = 77, "an explicit width wins");
      Set_Env ("COLUMNS", "93");
      Expect (E.Detect_Width (0) in 1 .. 500, "a detected width is bounded");
      Set_Env ("COLUMNS", "9999");
      Expect (E.Detect_Width (0) <= 500, "the maximum width is enforced");
      for Narrow of Narrow_Widths loop
         Set_Env ("COLUMNS", Narrow.all);
         Expect (E.Detect_Width (0) >= Ada_Quality_Summary.Options.Minimum_Width,
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
               Wider  : constant String := Wider_Line (Text, Ada_Quality_Summary.Options.Minimum_Width);
            begin
               Expect (Result.Status = 0, Command.all & " succeeds at COLUMNS=1");
               Expect (Wider = Absent, Command.all & " fits the minimum width: " & Wider);
            end;
         end loop;
      end;
      Clear_Env ("COLUMNS");
      Set_Env ("LC_ALL", "C");
      Expect (not E.Unicode_Locale, "C locale is ASCII-only");
      Set_Env ("LC_ALL", "en_US.UTF-8");
      Expect (E.Unicode_Locale, "UTF-8 locale");
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

   --  Two projects with regressions whose runs interleave: a1, c1, b1, a2, c2, so run order and project order
   --  differ, and a project with no regression in between.
   function Ordering_Database return String is
      Database : constant String := New_Database ("ordering");
      Ignored  : Positive;
      A, B, C  : Positive;
   begin
      Create (Database);
      A := Register (Database, Parent (Database), "a");
      B := Register (Database, Parent (Database), "b");
      C := Register (Database, Parent (Database), "c");
      Ignored := Publish (Database, Build (A, Shape (Coverage => 9_000)));
      Ignored := Publish (Database, Build (C, Shape (Coverage => 9_100)));
      Ignored := Publish (Database, Build (B, Shape (Coverage => 9_200)));
      Ignored := Publish (Database, Build (A, Shape ("DOC-01 TST-01", Coverage => 8_000)));
      Ignored := Publish (Database, Build (C, Shape ("DOC-02", Coverage => 8_100)));
      return Database;
   end Ordering_Database;

   procedure Sorting is
      Database : constant String := Standard_Database ("sorting");
      Ordering : constant String := Ordering_Database;

      function Q (Text : String) return String is ('"' & Text & '"');
   begin
      Expect_Equal (Column (Json (Database, "summary"), "data.projects", "name"), """beta"",""alpha"",""gamma""",
                    "overview priority: incomplete, violations, unassessed");
      Expect_Equal (Column (Json (Database, "summary|--reverse"), "data.projects", "name"),
                    """gamma"",""alpha"",""beta""", "--reverse reverses the whole ordering");
      Expect_Equal (Column (Json (Database, "projects|--sort|id|--reverse"), "data.projects", "project_id"), "3,2,1",
                    "identity order, reversed");
      Expect_Equal (Column (Json (Database, "projects|--sort|path"), "data.projects", "name"),
                    """alpha"",""beta"",""gamma""", "path order");
      Expect_Equal (Column (Json (Ordering, "regressions"), "data.regressions", "project_id"), "1,1,1,1,1,3,3,3",
                    "regressions default to project order");
      Expect_Equal (Column (Json (Ordering, "regressions|--sort|project|--reverse"), "data.regressions", "project_id"),
                    "3,3,3,1,1,1,1,1", "regressions by project, reversed");
      Expect_Equal (Column (Json (Ordering, "regressions|--sort|indicator"), "data.regressions", "project_id"),
                    "1,1,1,3,1,1,3,3", "regressions by indicator in registry order, then project");
      Expect_Equal (Column (Json (Ordering, "regressions|--sort|kind"), "data.regressions", "project_id"),
                    "1,3,1,3,1,1,1,3", "regressions by kind, then project");
      Expect_Equal (Column (Json (Ordering, "regressions"), "data.regressions", "kind"),
                    Q ("failed_gate") & "," & Q ("introduced_finding") & "," & Q ("worsened_metric") & "," &
                    Q ("new_violation") & "," & Q ("introduced_finding") & "," &
                    Q ("worsened_metric") & "," & Q ("new_violation") & "," & Q ("introduced_finding"),
                    "gates, findings, and worsened metrics are classified");
      Expect_Equal (Column (Json (Ordering, "trends"), "data.series[1].points", "run_id"), "1,2,3,4,5",
                    "trend points default to run order");
      Expect_Equal (Column (Json (Ordering, "trends|--sort|project"), "data.series[1].points", "project_id"),
                    "1,1,2,3,3", "trend points by project");
      Expect_Equal (Column (Json (Ordering, "trends|--sort|project"), "data.series[1].points", "run_id"),
                    "1,4,3,2,5", "trend points by project, then run");
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
end Unit_Tests;
