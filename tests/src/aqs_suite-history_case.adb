separate (Aqs_Suite)
procedure History_Case (Id : Test_Id) is
   Database : constant String := New_Database (Test_Id'Image (Id));
   Project  : Positive;
   Ignored  : Positive;
begin
   Create (Database);
   Project := Register (Database, Parent (Database), "alpha");
   case Id is
      when T021 =>
         --  As in Ada Quality's own regressions command: a policy change keeps the previous run as the baseline
         --  and classifies what the policy changed as policy-induced; a toolchain change leaves no baseline.
         Ignored := Publish (Database, Build (Project, Shape));
         Ignored := Publish (Database, Build (Project, Shape ("DOC-01", Policy => "policy-b")));
         declare
            Other : constant Positive := Register (Database, Parent (Database), "beta");
         begin
            Ignored := Publish (Database, Build (Other, Shape));
            Ignored := Publish (Database, Build (Other, Shape ("DOC-01", Toolchain => "toolchain-b")));
         end;
         declare
            Text  : constant String := Json (Database, "regressions");
            Terse : constant String := Output (Report (Database, "regressions|--width|200"));
            Count : constant Natural := Count_Of (Text, "data.regressions");
         begin
            Expect_Equal (Value (Text, "data.baseline_exclusions[0].status"), """compared""", "policy change");
            Expect_Equal (Value (Text, "data.baseline_exclusions[0].comparison"), """comparison_available""",
                          "the upstream decision is reported");
            Expect_Equal (Value (Text, "data.baseline_exclusions[0].policy_changed"), "true", "flagged");
            Expect_Equal (Value (Text, "data.baseline_exclusions[0].excluded_runs"), "[]", "nothing skipped");
            Expect (Count > 0, "the policy-changed comparison reports its changes");
            for Index in 0 .. Count - 1 loop
               Expect_Equal (Value (Text, "data.regressions[" & Image (Index) & "].kind"),
                             """policy_induced_change""", "no source regression across policies");
            end loop;
            Expect_Equal (Value (Text, "data.baseline_exclusions[1].status"), """no_baseline""", "toolchain");
            Expect_Equal (Value (Text, "data.baseline_exclusions[1].comparison"), """toolchain_changed""",
                          "the reason is preserved");
            Expect_Equal (Value (Text, "data.baseline_exclusions[1].excluded_runs[0].reason"),
                          """toolchain_changed""", "the incompatible predecessor is explained");
            Expect (Contains (Terse, "under a changed policy"), "terminal policy note");
            Expect (Contains (Terse, "no comparable baseline: the toolchain changed"),
                    "terminal reason");
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
            --  The current measurement is the series reference; with it unavailable, neither observation is
            --  comparable, so both are excluded and counted.
            Expect_Equal (Value (Text, "data.series[2].excluded_observations"), "2",
                          "the unavailable reference excludes every observation");
            Expect_Equal (Image (Count_Of (Text, "data.series[2].points")), "0", "no mixed or orphaned points");
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
         Ignored := Publish_Legacy (Database, Build (Project, Shape ("DOC-01")));
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
      when others => raise Program_Error with "unhandled " & Id'Image;
   end case;
end History_Case;
