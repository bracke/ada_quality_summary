separate (Aqs_Suite)
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
