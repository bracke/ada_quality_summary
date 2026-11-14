separate (Aqs_Suite)
procedure Classification (Id : Test_Id) is
   Database : constant String := New_Database (Test_Id'Image (Id));
   Project  : Positive;
   Previous : Positive := 1;

   --  An empty registry has nothing to classify.
   procedure Check_Empty is
   begin
      declare
         Text : constant String := Json (Database, "summary");
      begin
         Expect_Equal (Value (Text, "data.totals.projects"), "0", "empty registry has zero projects");
         Expect_Equal (Value (Text, "data.projects"), "[]", "empty registry lists no projects");
         Expect (Contains (Output (Report (Database, "summary")), "No projects selected."),
                 "terminal output states that no project is selected");
      end;
   end Check_Empty;

   --  Publish the runs the case classifies; Previous is the completed run a newer one must not replace.
   procedure Arrange is
      Ignored : Positive;
   begin
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
   end Arrange;

   --  Check the overview row of the single project.
   procedure Verify (Text : String) is
      Row : constant String := "data.projects[0].";
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
   end Verify;
begin
   Create (Database);
   if Id = T001 then
      Check_Empty;
      return;
   end if;
   Project := Register (Database, Parent (Database), "alpha");
   Arrange;
   Verify (Json (Database, "summary"));
end Classification;
