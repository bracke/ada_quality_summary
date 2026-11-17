separate (Aqs_Suite)
package body Review_Tests is
   function Q (Text : String) return String is ('"' & Text & '"');

   function Lower (Text : String) return String renames Ada.Characters.Handling.To_Lower;

   --  Whether the regressions report lists a regression of Kind for Indicator of Project.
   function Has_Regression (Text : String; Project : Positive; Indicator, Kind : String) return Boolean is
   begin
      for Index in 0 .. Count_Of (Text, "data.regressions") - 1 loop
         declare
            Row : constant String := "data.regressions[" & Image (Index) & "].";
         begin
            if Value (Text, Row & "project_id") = Image (Project) and then
              Value (Text, Row & "indicator_id") = Q (Indicator) and then Value (Text, Row & "kind") = Q (Kind)
            then
               return True;
            end if;
         end;
      end loop;
      return False;
   end Has_Regression;

   --  Each reason Ada_Quality.History.Select_Comparison gives for a missing baseline, and a newer running run that
   --  does not prevent comparing the current assessment.
   procedure Baseline_Reasons is
      Database : constant String := New_Database ("baselines");
      Ignored  : Positive;
      Ids      : array (1 .. 5) of Positive;
   begin
      Create (Database);
      for Index in Ids'Range loop
         Ids (Index) := Register (Database, Parent (Database), "p" & Image (Index));
      end loop;
      --  1: the toolchain was not identified, so no run is comparable. (A missing source fingerprint, the other way
      --  to this reason, can no longer be published; Ada Quality's own tests cover it.)
      Ignored := Publish (Database, Build (Ids (1), Shape (Toolchain => "toolchain-unavailable")));
      Ignored := Publish (Database, Build (Ids (1), Shape (Toolchain => "toolchain-unavailable")));
      --  2: the predecessor of a policy change did not complete.
      Ignored := Publish (Database, Build (Ids (2), Shape));
      Interrupt (Database, Start (Database, Ids (2)));
      Ignored := Publish (Database, Build (Ids (2), Shape (Policy => "policy-b")));
      --  3: never assessed. 4: one assessment only.
      Ignored := Publish (Database, Build (Ids (4), Shape));
      --  5: a violation, then a newer running run.
      Ignored := Publish (Database, Build (Ids (5), Shape));
      Ignored := Publish (Database, Build (Ids (5), Shape ("DOC-01")));
      Ignored := Start (Database, Ids (5));
      declare
         Text : constant String := Json (Database, "regressions");
         function Field (Index : Natural; Name : String) return String is
           (Value (Text, "data.baseline_exclusions[" & Image (Index) & "]." & Name));
      begin
         Expect_Equal (Field (0, "comparison"), Q ("no_compatible_baseline"), "an unidentified toolchain");
         Expect_Equal (Field (0, "excluded_runs[0].reason"), Q ("toolchain_changed"), "explained");
         Expect_Equal (Field (1, "comparison"), Q ("no_completed_baseline"), "an interrupted predecessor");
         Expect_Equal (Field (2, "status"), Q ("no_current_assessment"), "never assessed");
         Expect_Equal (Field (2, "comparison"), Q ("no_assessments"), "no assessments to select from");
         Expect_Equal (Field (3, "comparison"), Q ("no_baseline"), "a single assessment");
         Expect_Equal (Field (4, "status"), Q ("compared"), "a newer running run does not prevent comparison");
         Expect (Has_Regression (Text, Ids (5), "DOC-01", "new_violation"), "the current assessment is compared");
      end;
   end Baseline_Reasons;

   --  A finding that returns after it was resolved, and a finding whose severity rose.
   procedure Finding_Lifecycle is
      Database : constant String := New_Database ("lifecycle");
      Ignored  : Positive;
      Back     : Positive;
      Worse    : Positive;
   begin
      Create (Database);
      Back := Register (Database, Parent (Database), "back");
      Worse := Register (Database, Parent (Database), "worse");
      Ignored := Publish (Database, Build (Back, Shape ("DOC-01", Fingerprint => "returning")));
      Ignored := Publish (Database, Build (Back, Shape));
      Ignored := Publish (Database, Build (Back, Shape ("DOC-01", Fingerprint => "returning")));
      Ignored := Publish (Database, Build (Worse, Shape ("DOC-01", Fingerprint => "rising", Level => Low)));
      Ignored := Publish (Database, Build (Worse, Shape ("DOC-01", Fingerprint => "rising", Level => High)));
      declare
         Text : constant String := Json (Database, "regressions");
      begin
         Expect (Has_Regression (Text, Back, "DOC-01", "reintroduced_finding"),
                 "a finding seen before the baseline is reintroduced");
         Expect (not Has_Regression (Text, Back, "DOC-01", "introduced_finding"), "and not newly introduced");
         Expect (Has_Regression (Text, Worse, "DOC-01", "increased_severity"), "a higher severity is a regression");
      end;
   end Finding_Lifecycle;

   --  The persisted execution states of unknown results keep their spelling in JSON and the terminal.
   procedure Execution_Spellings is
      Database : constant String := New_Database ("executions");
      Ignored  : Positive;
      Position : constant String := Image (Indicator_Id'Pos (BLD_01));
   begin
      Create (Database);
      for State in Execution_Status range Blocked .. Errored loop
         Ignored := Publish
           (Database, Build (Register (Database, Parent (Database), Lower (State'Image)),
                             Shape (Unknowns => "BLD-01", Unknown_Run => State)));
         declare
            Name : constant String := Lower (State'Image);
         begin
            Expect_Equal (Value (Json (Database, "project|" & Name), "data.indicators[" & Position & "].execution"),
                          Q (Name), "execution " & Name);
            Expect (Contains (Output (Report (Database, "project|" & Name & "|--width|200")), Name),
                    "the terminal shows execution " & Name);
         end;
      end loop;
   end Execution_Spellings;

   --  Report fields no other test reads: common violations, affected projects, and per-project regression counts.
   procedure Report_Fields is
      Database : constant String := Standard_Database ("fields");
      Summary  : constant String := Json (Database, "summary");
   begin
      Expect_Equal (Column (Summary, "data.common_violations", "indicator_id"),
                    Q ("TST-03") & "," & Q ("SRC-01") & "," & Q ("DOC-01"),
                    "common violations by projects, then registry order");
      Expect_Equal (Column (Summary, "data.common_violations", "projects"), "1,1,1", "violating projects");
      Expect_Equal (Value (Json (Database, "indicator|TST-03"), "data.indicator.affected_projects"), "1",
                    "affected projects of one indicator");
      Expect_Equal (Column (Json (Database, "projects|--sort|name"), "data.projects", "regression_count"), "3,0,0",
                    "per-project regression counts");
   end Report_Fields;

   --  Option and input edges: the last representable day, help options checked against the topic, a long list of
   --  ambiguous matches, undated runs and an inclusive last day, and corrupt baseline evidence.
   procedure Input_Edges is
      Database : constant String := Standard_Database ("edges");
      function Code (Arguments : String) return Natural is (Exit_Of (Report (Database, Arguments)));
   begin
      Expect (Code ("trends|--until|2399-12-31") = 0, "the last representable day is a valid --until");
      Expect (Code ("history|alpha|--since|2399-12-31|--until|2399-12-31") = 0, "a one-day range");
      Expect (Code ("trends|--since|2026-03-02|--until|2026-03-02") = 0, "since may equal until");
      Expect (Exit_Of (Run ("help --sort name")) = 2, "help without a topic accepts no sort key");
      Expect (Exit_Of (Run ("help projects --sort name")) = 0, "help accepts the topic's sort keys");
      Expect (Exit_Of (Run ("help --since 2026-01-01")) = 2, "help without a topic accepts no dates");
      Expect (Exit_Of (Run ("help trends --since 2026-01-01")) = 0, "help accepts the topic's dates");
      Expect (Exit_Of (Run ("summary --format json --width 80")) = 2, "--width is rejected with JSON");
      declare
         Many    : constant String := New_Database ("many");
         Ignored : Positive;
      begin
         Create (Many);
         for Index in 1 .. 11 loop
            declare
               Directory : constant String := Parent (Many) & "/d" & Image (Index);
            begin
               Ada.Directories.Create_Path (Directory);
               Ignored := Register (Many, Directory, "same");
            end;
         end loop;
         declare
            Result : constant Ada_Quality_Summary.CLI.Outcome := Report (Many, "project|same");
         begin
            Expect (Exit_Of (Result) = 2, "an ambiguous name is an argument error");
            Expect (Contains (Errors (Result), "1, 2, 3, 4, 5, 6, 7, 8, and 3 more"),
                    "a long list of matches is shortened, not truncated: " & Errors (Result));
         end;
      end;
      declare
         Legacy  : constant String := New_Database ("undated-until");
         Project : Positive;
         Ignored : Positive;
      begin
         Create (Legacy);
         Project := Register (Legacy, Parent (Legacy), "alpha");
         Ignored := Publish_Legacy (Legacy, Build (Project, Shape));
         Ignored := Publish (Legacy, Build (Project, Shape));
         Expect_Equal (Value (Json (Legacy, "history|alpha|--until|2399-12-31"), "data.undated_excluded"), "1",
                       "--until excludes undated runs and counts them");
         Expect_Equal (Value (Json (Legacy, "history|alpha|--until|2399-12-31"), "data.completed_count"), "1",
                       "a run on or before the last day is included");
      end;
      declare
         Copy : constant String := Parent (Database) & "/corrupt.db";
      begin
         Copy_Database (Database, Copy);
         Corrupt (Copy, 1, Ada_Quality.Storage.Testing.Invalid_Measurement);
         declare
            Result : constant Ada_Quality_Summary.CLI.Outcome := Report (Copy, "regressions");
         begin
            Expect (Exit_Of (Result) = 4, "corrupt baseline evidence is a data failure: " & Errors (Result));
            Expect (not Contains (Errors (Result), "internal error"), "and not an internal error");
         end;
      end;
   end Input_Edges;
end Review_Tests;
