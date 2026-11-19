separate (Aqs_Suite)
package body Feature_Tests is
   function Q (Text : String) return String is ('"' & Text & '"');

   function Code_Of (Database, Arguments : String) return Natural is (Exit_Of (Report (Database, Arguments)));

   --  The schema of a JSON report, named by its command word.
   procedure Validates (Text, Command : String) is
      Problem : constant String := Aqs_Schema.Validate (Schemas, Command & ".schema.json", Text);
   begin
      Expect (Problem = "", Command & " validates: " & Problem);
   end Validates;

   --  The standard database: alpha violates and has three regressions, beta is incomplete, gamma is unassessed.
   procedure Quality_Gate is
      Database : constant String := Standard_Database ("gate");

      procedure Fails (Arguments, Diagnostic : String) is
         Result : constant Ada_Quality_Summary.CLI.Outcome := Report (Database, Arguments);
      begin
         Expect (Exit_Of (Result) = Ada_Quality_Summary.CLI.Gate_Exit, Arguments & " exits with the gate status");
         Expect (Contains (Errors (Result), "quality gate failed: " & Diagnostic & LF),
                 Arguments & " names " & Diagnostic & ": " & Errors (Result));
         Expect (Output (Result) /= "", Arguments & " still writes the report");
      end Fails;

      procedure Passes (Arguments : String) is
         Result : constant Ada_Quality_Summary.CLI.Outcome := Report (Database, Arguments);
      begin
         Expect (Exit_Of (Result) = 0 and then Errors (Result) = "", Arguments & " passes: " & Errors (Result));
      end Passes;
   begin
      Fails ("summary|--fail-on|violations", "violations (1)");
      Fails ("summary|--fail-on|regressions", "regressions (3)");
      Fails ("problems|--fail-on|regressions", "regressions (3)");
      Fails ("indicators|--fail-on|unassessed,regressions,incomplete",
             "regressions (3), incomplete (1), unassessed (1)");
      Fails ("compare|1|2|--fail-on|regressions,violations", "regressions (3), violations (1)");
      Fails ("history|beta|--fail-on|incomplete", "incomplete (1)");
      Passes ("project|alpha|--fail-on|incomplete,unassessed");
      Passes ("summary|--status|passing|--fail-on|violations,regressions,incomplete,unassessed");
      Passes ("compare|1|2|--fail-on|incomplete,unassessed");
      Passes ("summary");
      Expect (Output (Report (Database, "summary|--format|json|--fail-on|violations")) = Json (Database, "summary"),
              "a failing gate does not change the report");
      Expect (Code_Of (Database, "summary|--fail-on|nonsense") = 2, "an unknown condition is an argument error");
      Expect (Code_Of (Database, "summary|--fail-on|violations,") = 2, "an empty condition is an argument error");
      Expect (Code_Of (Database, "summary|--fail-on|violations|--fail-on|regressions") = 2, "one --fail-on");
      Expect (Exit_Of (Run ("help --fail-on violations")) = 2, "help itself accepts no gate");
      Expect (Exit_Of (Run ("help summary --fail-on violations")) = 0, "help for a report accepts the gate");
      declare
         Process : constant Process_Result := Spawn ("--database|" & Database & "|summary|--fail-on|violations");
         Text    : constant String := To_String (Process.Output);
      begin
         Expect (Process.Status = 1, "the executable exits 1 when the gate fails");
         Expect (Ada.Strings.Fixed.Index (Text, "quality gate failed") > Ada.Strings.Fixed.Index (Text, "PROJECTS"),
                 "the diagnostic follows the report it judged");
      end;
   end Quality_Gate;

   --  Two chosen assessments, by identity or alias, compared without baseline substitution.
   procedure Explicit_Comparison is
      Database : constant String := New_Database ("compare");
      Ids      : array (1 .. 6) of Positive;
      One, Two : Positive;

      function Field (Arguments, Path : String) return String is (Value (Json (Database, Arguments), "data." & Path));
   begin
      Create (Database);
      One := Register (Database, Parent (Database), "one");
      Two := Register (Database, Parent (Database), "two");
      Ids (1) := Publish (Database, Build (One, Shape));
      Ids (2) := Publish (Database, Build (One, Shape ("DOC-01")));
      Ids (3) := Publish (Database, Build (One, Shape (Toolchain => "toolchain-b")));
      Ids (4) := Publish (Database, Build (One, Shape ("DOC-01", Policy => "policy-b", Toolchain => "toolchain-b")));
      Ids (5) := Start (Database, One);
      Interrupt (Database, Ids (5));
      Ids (6) := Publish (Database, Build (Two, Shape));
      Alias (Database, Ids (1), "release-1.0");
      Alias (Database, Ids (2), "candidate");
      declare
         Text : constant String := Json (Database, "compare|release-1.0|candidate");
      begin
         Validates (Text, "compare");
         Expect_Equal (Value (Text, "data.comparison"), Q ("comparison_available"), "a compatible pair");
         Expect_Equal (Value (Text, "data.baseline.run_id") & Value (Text, "data.current.run_id"), "12",
                       "aliases resolve to their runs");
         Expect_Equal (Value (Text, "data.incompatibility"), "null", "no incompatibility");
         Expect_Equal (Value (Text, "selection.project_id"), Image (One), "the owning project is selected");
         Expect_Equal (Column (Text, "data.regressions", "kind"), Q ("new_violation") & "," &
                         Q ("introduced_finding"), "the pair's regressions");
         Expect_Equal (Value (Text, "data.totals.regressions"), "2", "counted");
      end;
      Expect_Equal (Field ("compare|1|3", "comparison"), Q ("toolchain_changed"), "a toolchain change");
      Expect_Equal (Field ("compare|1|3", "incompatibility"), Q ("toolchain_changed"), "explained");
      Expect_Equal (Field ("compare|1|3", "totals.regressions"), "0", "an incompatible pair has no regressions");
      Expect_Equal (Field ("compare|3|4", "policy_changed"), "true", "a policy change is comparable");
      Expect_Equal (Field ("compare|3|4", "regressions[0].kind"), Q ("policy_induced_change"), "policy-induced");
      Expect_Equal (Field ("compare|1|5", "comparison"), Q ("current_incomplete"), "an interrupted current run");
      Expect_Equal (Field ("compare|1|5", "current.state"), Q ("interrupted"), "keeps its state");
      Expect (Contains (Errors (Report (Database, "compare|1|5|--fail-on|incomplete,unassessed")),
                        "quality gate failed: incomplete (1)" & LF),
              "an unfinished current run is incomplete, never unassessed");
      Validates (Json (Database, "compare|1|5"), "compare");
      Expect_Equal (Column (Json (Database, "compare|1|2|--sort|kind|--reverse"), "data.regressions", "kind"),
                    Q ("introduced_finding") & "," & Q ("new_violation"), "--sort kind --reverse");
      declare
         Terminal : constant String := Output (Report (Database, "compare|1|3|--width|120"));
         Wanted   : constant String := Output (Report (Database, "compare|release-1.0|candidate|--width|120"));
      begin
         Expect (Contains (Terminal, "toolchain fingerprint differs"), "the terminal explains the incompatibility");
         Expect (Contains (Wanted, "Baseline run") and then Contains (Wanted, "new-violation"),
                 "the terminal shows both runs and the regressions");
         Expect (Contains (Output (Report (Database, "compare|3|4")), "policy changed"), "and a policy change");
      end;
      Expect (Contains (Errors (Report (Database, "compare|2|1")), "older"), "the baseline must be older");
      Expect (Contains (Errors (Report (Database, "compare|1|" & Image (Ids (6)))), "different projects"),
              "both runs belong to one project");
      Expect (Contains (Errors (Report (Database, "compare|1|99")), "unknown assessment 99"), "an unknown run");
      Expect (Code_Of (Database, "compare|1|no-such-alias") = 2, "an unknown alias");
      Expect (Code_Of (Database, "compare|1") = 2, "two assessments are required");
      Expect (Code_Of (Database, "compare|1|2|3") = 2, "and no more");
      Expect (Code_Of (Database, "compare|1|2|--sort|name") = 2, "compare sorts by indicator or kind only");
      Expect (Code_Of (Database, "compare|1|2|--project|one") = 2, "compare is not a collection report");
      declare
         Gone  : constant Positive := Register (Database, Parent (Database), "gone");
         First : constant Positive := Publish (Database, Build (Gone, Shape));
         Last  : constant Positive := Publish (Database, Build (Gone, Shape ("DOC-01")));
         Pair  : constant String := "compare|" & Image (First) & "|" & Image (Last);
      begin
         Remove (Database, Gone);
         Expect (Contains (Errors (Report (Database, Pair)), "--include-removed"),
                 "a removed project's runs are compared only on request");
         Expect_Equal (Value (Json (Database, Pair & "|--include-removed"), "data.project.removed"), "true",
                       "and then reported as removed");
      end;
   end Explicit_Comparison;

   procedure Markdown_Output is
      Database : constant String := Standard_Database ("markdown");
      Summary  : constant String := Output (Report (Database, "summary|--format|markdown"));
      Totals   : constant String := Json (Database, "summary");

      --  Every pipe table is separated from the text before it, and no block is followed by two empty lines.
      function Well_Formed (Text : String) return Boolean is
         Start    : Positive := Text'First;
         Previous : Character := LF;  --  First character of the previous line; LF for an empty line.
      begin
         for Index in Text'Range loop
            if Text (Index) = LF then
               declare
                  Current : constant Character := (if Index > Start then Text (Start) else LF);
               begin
                  if (Current = '|' and then Previous not in '|' | LF) or else (Current = LF and then Previous = LF)
                  then
                     return False;
                  end if;
                  Previous := Current;
               end;
               Start := Index + 1;
            end if;
         end loop;
         return True;
      end Well_Formed;
   begin
      for Command of All_Commands loop
         for Layout of Layout_Names loop
            declare
               Result : constant Ada_Quality_Summary.CLI.Outcome :=
                 Report (Database, Command.all & "|--format|markdown|--layout|" & Layout.all & "|--color|always");
               Text   : constant String := Output (Result);
            begin
               Expect (Exit_Of (Result) = 0, Command.all & " renders as Markdown: " & Errors (Result));
               Expect (Text'Length > 2 and then Text (Text'First .. Text'First + 1) = "# ", Command.all & " title");
               Expect (not Has_Escape (Text), Command.all & " has no terminal escapes");
               Expect (Well_Formed (Text), Command.all & " " & Layout.all & " separates its blocks");
            end;
         end loop;
      end loop;
      Expect (Contains (Summary, "- **Violations:** " & Value (Totals, "data.totals.violations") & LF),
              "Markdown fields carry the JSON totals");
      Expect (Contains (Summary, LF & "| Project | Quality |") and then Contains (Summary, "| ---: |"),
              "tables have a header and right-aligned numbers");
      Expect (Contains (Summary, "| Path |"), "a normal layout shows every column");
      Expect (not Contains (Output (Report (Database, "summary|--format|markdown|--layout|compact")), "| Path |"),
              "a compact layout keeps essential columns");
      Expect (Contains (Output (Report (Database, "project|beta|--format|markdown")), "registered\_tests"),
              "Markdown punctuation in text is escaped");
      Expect (Contains (Output (Report (Database, "regressions|--format|markdown|--layout|detailed")),
                        LF & "- beta: "), "notes become list items");
      Expect (Code_Of (Database, "summary|--format|markdown|--width|80") = 2, "--width is terminal-only");
      Expect (Code_Of (Database, "summary|--format|markdown|--pretty") = 2, "--pretty is for JSON");
      Expect (Code_Of (Database, "summary|--format|json|--layout|compact") = 2, "--layout is for text output");
   end Markdown_Output;

   --  The SARIF log of a database's problems report, rendered against Root as the source root.
   function Sarif_Of (Database, Root : String) return String is
      Store : Ada_Quality_Summary.Repository.Repository;
   begin
      Ada_Quality_Summary.Repository.Open (Store, Database);
      declare
         Data : constant Ada_Quality_Summary.Repository.Snapshot := Ada_Quality_Summary.Repository.Load (Store);
      begin
         return Ada_Quality_Summary.SARIF.Render
           (Ada_Quality_Summary.Reports.Build (Data, Ada_Quality_Summary.Options.Parse (Arguments_Of ("problems")),
                                               Database), Root);
      end;
   end Sarif_Of;

   procedure SARIF_Output is
      Database : constant String := New_Database ("sarif");
      Ignored  : Positive;
   begin
      Create (Database);
      Ignored := Publish
        (Database, Build (Register (Database, Parent (Database), "plain"),
                          Shape ("DOC-01", Findings => 2, Level => High)));
      Ignored := Publish
        (Database, Build (Register (Database, Parent (Database), "with space"),
                          Shape ("SEC-01", Waivers => "SRC-03", Level => Medium)));
      declare
         Text     : constant String := Output (Report (Database, "problems|--format|sarif"));
         Problems : constant String := Json (Database, "problems");
         Results  : constant Natural := Count_Of (Text, "runs[0].results");
         Location : constant String := "runs[0].results[2].locations[0].physicalLocation.";
      begin
         Expect_Equal (Value (Text, "version"), Q ("2.1.0"), "SARIF 2.1.0");
         Expect_Equal (Value (Text, "runs[0].tool.driver.name"), Q ("ada-quality-summary"), "the tool");
         Expect_Equal (Image (Results), Value (Problems, "data.totals.findings"), "one result per finding");
         for Index in 0 .. Results - 1 loop
            declare
               Result : constant String := "runs[0].results[" & Image (Index) & "].";
               Rule   : constant String := "runs[0].tool.driver.rules[" & Value (Text, Result & "ruleIndex") & "].id";
            begin
               Expect_Equal (Value (Text, Rule), Value (Text, Result & "ruleId"), "ruleIndex names the rule");
               Expect_Equal (Value (Text, Result & "partialFingerprints.adaQualityFinding/v1"),
                             Value (Problems, "data.findings[" & Image (Index) & "].fingerprint"),
                             "the stored fingerprint identifies the result");
            end;
         end loop;
         Expect_Equal (Column (Text, "runs[0].results", "level"),
                       Q ("error") & "," & Q ("error") & "," & Q ("warning") & "," & Q ("note"),
                       "severities map to levels");
         Expect_Equal (Value (Text, "runs[0].results[3].suppressions[0].kind"), Q ("inSource"),
                       "a waiver is suppressed in source");
         Expect_Equal (Value (Text, "runs[0].results[3].suppressions[0].justification"),
                       Q ("one decoder owns the whole wire format"), "with its justification");
         Expect (Value_Or_Absent (Text, "runs[0].results[0].suppressions") = Absent, "other results are not");
         --  The fixture projects lie outside the working directory, so their locations are absolute.
         Expect (Ada.Strings.Fixed.Tail (Value (Text, Location & "artifactLocation.uri"), 26) =
                   "with%20space/src/file.adb""" and then
                 Ada.Strings.Fixed.Head (Value (Text, Location & "artifactLocation.uri"), 8) = """file://",
                 "a location outside the source root is a percent-encoded file URI: " &
                   Value (Text, Location & "artifactLocation.uri"));
         Expect (Value_Or_Absent (Text, Location & "artifactLocation.uriBaseId") = Absent, "without a base");
         Expect_Equal (Value (Text, Location & "region.startLine"), "1", "with the finding line");
         Expect_Equal (Value (Text, "runs[0].originalUriBaseIds.%SRCROOT%.uri"),
                       Q (Ada_Quality_Summary.SARIF.File_URI (Ada.Directories.Current_Directory)),
                       "the working directory is the source root");
      end;
      --  Rendered against the directory that holds the projects, locations are relative to the source root.
      declare
         Text : constant String := Sarif_Of (Database, Parent (Database));
      begin
         Expect_Equal (Value (Text, "runs[0].results[0].locations[0].physicalLocation.artifactLocation.uri"),
                       Q ("plain/src/file.adb"), "a location inside the source root is relative");
         Expect_Equal (Value (Text, "runs[0].results[0].locations[0].physicalLocation.artifactLocation.uriBaseId"),
                       Q (Ada_Quality_Summary.SARIF.Source_Root_Id), "through the source-root base");
         Expect_Equal (Value (Text, "runs[0].results[2].locations[0].physicalLocation.artifactLocation.uri"),
                       Q ("with%20space/src/file.adb"), "and percent-encoded");
      end;
      --  A legacy finding has no path; it is located at its project's manifest, without a line.
      declare
         Legacy  : constant String := New_Database ("sarif-legacy");
         Project : Positive;
      begin
         Create (Legacy);
         Project := Register (Legacy, Parent (Legacy), "old");
         Ignored := Publish_Legacy (Legacy, Build (Project, Shape ("DOC-01")));
         declare
            Text : constant String := Sarif_Of (Legacy, Parent (Legacy));
         begin
            Expect_Equal (Value (Text, "runs[0].results[0].locations[0].physicalLocation.artifactLocation.uri"),
                          Q ("old/alire.toml"), "a finding without a path points at the manifest");
            Expect (Value_Or_Absent (Text, "runs[0].results[0].locations[0].physicalLocation.region") = Absent,
                    "without a region");
         end;
      end;
      Expect (Ada_Quality_Summary.SARIF.Relative ("/a/b", "/a/b/c/d") = "c/d" and then
                Ada_Quality_Summary.SARIF.Relative ("/a/b/", "/a/b") = "" and then
                Ada_Quality_Summary.SARIF.Relative ("/a/b", "/a/bc") = "/a/bc" and then
                not Ada_Quality_Summary.SARIF.Is_Inside ("/a/b", "/a/bc") and then
                Ada_Quality_Summary.SARIF.Is_Inside ("/", "/x"), "paths below the source root, and only those");
      Expect (Count_Of (Output (Report (Database, "problems|--format|sarif|--limit|1|--pretty")),
                        "runs[0].results") = 1, "--limit and --pretty apply");
      Expect (Contains (Errors (Report (Database, "summary|--format|sarif")), "problems command"),
              "SARIF is the problems report's format");
      Expect (Ada_Quality_Summary.SARIF.Encode ("a b/" & Character'Val (16#C3#) & Character'Val (16#BC#)) =
                "a%20b/%C3%BC", "UTF-8 bytes are percent-encoded");
      Expect (Ada_Quality_Summary.SARIF.File_URI ("/x/") = "file:///x/" and then
                Ada_Quality_Summary.SARIF.File_URI ("/x") = "file:///x/", "a directory URI ends with one slash");
   end SARIF_Output;

   procedure Waiver_Report is
      Database : constant String := New_Database ("waivers");
      Ids      : array (1 .. 4) of Positive;
      Ignored  : Positive;
   begin
      Create (Database);
      for Index in Ids'Range loop
         Ids (Index) := Register (Database, Parent (Database), "w" & Image (Index));
      end loop;
      Ignored := Publish (Database, Build (Ids (1), Shape (Waivers => "SRC-06 SRC-03")));
      Ignored := Publish (Database, Build (Ids (2), Shape ("DOC-01", Waivers => "SRC-03")));
      Ignored := Publish (Database, Build (Ids (3), Shape));
      declare
         Text : constant String := Json (Database, "waivers");
      begin
         Validates (Text, "waivers");
         Expect_Equal (Value (Text, "data.totals.waivers") & Value (Text, "data.totals.projects"), "32",
                       "three waivers in two projects");
         Expect_Equal (Column (Text, "data.by_indicator", "waivers"), "2,1", "per indicator");
         Expect_Equal (Column (Text, "data.by_indicator", "projects"), "2,1", "and per affected project");
         Expect_Equal (Column (Text, "data.waivers", "indicator_id"), Q ("SRC-03") & "," & Q ("SRC-03") & "," &
                         Q ("SRC-06"), "indicator order");
         Expect_Equal (Column (Text, "data.waivers", "project_id"), "1,2,1", "then project order");
         Expect_Equal (Value (Text, "data.waivers[0].target"), Q ("process_batch"), "the waived subprogram");
         Expect_Equal (Value (Text, "data.waivers[2].target"), Q ("file"), "a waived file");
         Expect_Equal (Value (Text, "data.waivers[0].justification"), Q ("one decoder owns the whole wire format"),
                       "the justification");
         Expect_Equal (Value (Text, "data.waivers[0].relative_path") & Value (Text, "data.waivers[0].line"),
                       Q ("src/large_unit.adb") & "null", "the waived file without a line");
      end;
      Expect_Equal (Column (Json (Database, "waivers|--sort|project"), "data.waivers", "project_id"), "1,1,2",
                    "--sort project");
      Expect_Equal (Value (Json (Database, "waivers|--project|w2"), "data.totals.waivers"), "1", "--project");
      Expect_Equal (Value (Json (Database, "waivers|--status|passing"), "data.totals.waivers"), "2", "--status");
      Expect_Equal (Value (Json (Database, "problems|--sort|indicator"), "data.totals.by_severity.low"), "3",
                    "the problems report still lists waivers as low findings");
      declare
         Limited_Text : constant String := Json (Database, "waivers|--limit|1");
         Terminal     : constant String := Output (Report (Database, "waivers|--width|120|--limit|1"));
      begin
         Expect (Count_Of (Limited_Text, "data.waivers") = 1, "the limit applies to rows");
         Expect_Equal (Value (Limited_Text, "data.totals.waivers"), "3", "not to totals");
         Expect (Contains (Terminal, "Justification") and then Contains (Terminal, "process_batch") and then
                   Contains (Terminal, "Showing 1 of 3 rows"), "the terminal table");
      end;
      Expect (Contains (Output (Report (Standard_Database ("no-waivers"), "waivers")), "No waivers."),
              "an empty waiver report says so");
      Expect (Ada_Quality_Summary.Model.Waiver_Target ("free text") = "" and then
                Ada_Quality_Summary.Model.Waiver_Justification ("free text") = "free text",
              "a message without fields is the justification");
      Expect (Ada_Quality_Summary.Model.Waiver_Target ("SRC-03 target=parse") = "parse", "a target without a reason");
   end Waiver_Report;

   procedure Shell_Completion is
      Shells  : constant Text_List := [new String'("bash"), new String'("zsh"), new String'("fish")];
      Scripts : constant String := Absolute (Dir ("completion"));

      function Script_Of (Shell : String) return String is (Scripts & "/script." & Shell);

      --  Run Code with a shell, or return Absent when the shell is not installed.
      function Shell_Run (Shell, Code : String; Status : out Integer) return String is
         Program : constant String := Project_Tools.Processes.Locate_Command (Shell);
      begin
         Status := -1;
         if Program = "" then
            return Absent;
         end if;
         declare
            Result : constant Project_Tools.Processes.Captured_Process :=
              Project_Tools.Processes.Capture_Command
                (Program, Project_Tools.Processes.Arguments
                   ([Project_Tools.Processes.Argument ("-c"), Project_Tools.Processes.Argument (Code)]),
                 Err_To_Out => True);
         begin
            Status := Result.Status;
            return To_String (Result.Output);
         end;
      end Shell_Run;

      --  The candidates the bash script offers for the last of Words, without the final line feed.
      function Complete (Words : String) return String is
         Status : Integer;
      begin
         return Shell_Run
           ("bash", "source " & Script_Of ("bash") & "; COMP_WORDS=(ada-quality-summary " & Words &
              "); COMP_CWORD=$((${#COMP_WORDS[@]} - 1)); _ada_quality_summary; echo ""${COMPREPLY[*]}""", Status);
      end Complete;

      --  Whether a shell parses its script, or True when the shell is not installed.
      function Parses (Shell, Check : String) return Boolean is
         Status : Integer;
         Text   : constant String := Shell_Run (Shell, Check & " " & Script_Of (Shell), Status);
      begin
         return Text = Absent or else Status = 0;
      end Parses;

      Status : Integer;
   begin
      for Shell of Shells loop
         declare
            Text : constant String := Output (Run ("completion " & Shell.all));
         begin
            Project_Tools.Files.Write_Text_File (Script_Of (Shell.all), Text);
            for Option in Ada_Quality_Summary.Options.Option_Kind loop
               declare
                  Spelling : constant String := Ada_Quality_Summary.Options.Spelling (Option);
               begin
                  Expect (Contains (Text, (if Shell.all = "fish" then "-l " & Spelling (Spelling'First + 2 ..
                                                                                        Spelling'Last)
                                          else Spelling)), Shell.all & " completes " & Spelling);
               end;
            end loop;
            for Command in Ada_Quality_Summary.Options.Named_Command loop
               Expect (Contains (Text, Ada_Quality_Summary.Options.Name (Command)),
                       Shell.all & " completes " & Ada_Quality_Summary.Options.Name (Command));
            end loop;
            Expect (Contains (Text, "terminal json markdown sarif"), Shell.all & " completes format choices");
            Expect (Contains (Text, Ada_Quality_Summary.Completion.Sort_Keys
                                      (Ada_Quality_Summary.Options.Waivers_Command)),
                    Shell.all & " completes sort keys per command");
         end;
      end loop;
      --  Each installed shell parses its script; CI installs all three.
      Expect (Parses ("bash", "bash -n"), "bash parses its script");
      Expect (Parses ("zsh", "zsh -n"), "zsh parses its script");
      Expect (Parses ("fish", "fish --no-execute"), "fish parses its script");
      if Complete ("") /= Absent then
         Expect_Equal (Complete ("--format m"), "markdown", "bash completes a choice");
         Expect_Equal (Complete ("wai"), "waivers", "bash completes a command");
         Expect_Equal (Complete ("--fail"), "--fail-on", "bash completes an option");
         Expect_Equal (Complete ("waivers --sort ''"), "indicator project", "bash offers the command's sort keys");
         Expect_Equal (Complete ("--database x.db compare 1 2 --sort ''"), "indicator kind",
                       "an option value is not taken for the command");
         Expect_Equal (Complete ("--sort ''"), "name id quality violations", "without a command, summary's keys");
      end if;
      declare
         Candidates : constant String :=
           Shell_Run ("fish", "source " & Script_Of ("fish") &
                        "; complete -C 'ada-quality-summary waivers --sort '", Status);
      begin
         Expect (Candidates = Absent or else
                   (Contains (Candidates, "indicator") and then not Contains (Candidates, "quality")),
                 "fish offers the command's sort keys: " & Candidates);
      end;
      Expect_Equal (Ada_Quality_Summary.Completion.Choices (Ada_Quality_Summary.Options.Fail_On_Option),
                    "regressions violations incomplete unassessed", "gate conditions");
      Expect_Equal (Ada_Quality_Summary.Completion.Sort_Keys (Ada_Quality_Summary.Options.Help_Command), "",
                    "help has no sort keys");
   end Shell_Completion;

   --  Positional arguments are assigned by command, and every command accepts only its own options.
   procedure Option_Scope is
   begin
      Expect (Exit_Of (Run ("completion tcsh")) = 2, "an unknown shell is an argument error");
      Expect (Exit_Of (Run ("completion")) = 2, "completion requires a shell");
      Expect (Exit_Of (Run ("completion bash zsh")) = 2, "and only one");
      Expect (Exit_Of (Run ("completion bash --limit 5")) = 2, "completion accepts no report option");
      Expect (Exit_Of (Run ("help --format json")) = 2, "nor does help itself");
      Expect (not Contains (Output (Run ("help completion")), "--database"), "and help says so");
      Expect (Contains (Errors (Run ("help frobnicate")), "unknown command frobnicate"), "a help topic is a command");
      Expect (Contains (Errors (Run ("help summary projects")), "unexpected argument projects"), "one topic only");
      Expect (Contains (Output (Run ("project alpha --help")), "project PROJECT"),
              "--help describes the command it follows");
      Expect (Contains (Errors (Run ("summary extra")), "unexpected argument extra"), "summary takes no argument");
      Expect (Contains (Errors (Run ("indicator")), "indicator ID"), "indicator requires its ID");
      Expect (Contains (Errors (Run ("completion bash --no-color")), "option --no-color is not accepted"),
              "a rejected --no-color is named as given");
      Expect (Contains (Errors (Run ("summary --color never --no-color")), "option --no-color was given more"),
              "--color and --no-color together are one duplicate setting");
   end Option_Scope;

   --  The committed manual page is the generated one and documents every command and option.
   procedure Manual_Page is
   begin
      declare
         Page : constant String := Aqs_Manual.Page;
      begin
         Expect (Project_Tools.Files.Read_Raw_File (Absolute ("../" & Aqs_Manual.Page_Path)) = Page,
                 "the committed manual page is current; run tests/bin/aqs_manpage");
         for Option in Ada_Quality_Summary.Options.Option_Kind loop
            declare
               Spelling : constant String := Ada_Quality_Summary.Options.Spelling (Option);
               Escaped  : Ada.Strings.Unbounded.Unbounded_String;
            begin
               for C of Spelling loop
                  Append (Escaped, (if C = '-' then "\-" else [C]));
               end loop;
               Expect (Contains (Page, LF & ".B" & (if Ada_Quality_Summary.Options.Value_Name (Option) = "" then ""
                                                  else "I") & " " & To_String (Escaped)),
                       "the manual lists " & Spelling);
            end;
         end loop;
         Expect (Contains (Page, ".B compare BASELINE CURRENT"), "the manual shows command usage");
      end;
   end Manual_Page;
end Feature_Tests;
