with Ada.Strings.Unbounded;
with Ada_Quality.History;
with Ada_Quality.Indicators;
with Ada_Quality.Reporting;
with Ada_Quality.Types;
with Ada_Quality_Summary.Model;
with Ada_Quality_Summary.Terminal.Cells;
with Ada_Quality_Summary.Terminal.Environment;
with Ada_Quality_Summary.Terminal.Output;
with Ada_Quality_Summary.Terminal.Sections;
with Ada_Quality_Summary.Text;

package body Ada_Quality_Summary.Terminal is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Types;
   use Ada_Quality_Summary.Model;
   use Ada_Quality_Summary.Options;
   use Ada_Quality_Summary.Reports;
   use Ada_Quality_Summary.Terminal.Cells;
   use Ada_Quality_Summary.Terminal.Output;
   use Ada_Quality_Summary.Terminal.Sections;
   use type Ada_Quality.History.Comparison_Status;
   use type Ada_Quality.Reporting.Evidence_Format;

   procedure Summary_Report (Out_Text : in out Writer; Item : Report) is
   begin
      Header (Out_Text, Item, L ("title"));
      Blank (Out_Text);
      Status_Section (Out_Text, Item.Portfolio.Totals);
      Blank (Out_Text);
      Heading (Out_Text, L ("projects"));
      Project_Table (Out_Text, Item.Portfolio.Projects);
      Shown_Note (Out_Text, Natural (Item.Portfolio.Projects.Length), Item.Row_Count);
      Blank (Out_Text);
      Heading (Out_Text, L ("common_violations"));
      if Item.Common.Is_Empty then
         Note (Out_Text, L ("none"));
      else
         declare
            Columns : Column_Vectors.Vector;
            Rows    : Row_Vectors.Vector;
         begin
            Columns.Append (Col (L ("indicator")));
            Columns.Append (Col (L ("projects_column"), Right => True));
            Columns.Append (Col (L ("name"), Shrink => True, Priority => 2, Minimum => 8));
            for Indicator of Item.Common loop
               declare
                  Row : Cell_Vectors.Vector;
               begin
                  Row.Append (C (Image (Indicator.Id)));
                  Row.Append (C (Num (Indicator.Totals.Violated)));
                  Row.Append (C (To_String (Indicator.Name)));
                  Rows.Append (Row);
               end;
            end loop;
            Table (Out_Text, Columns, Rows);
         end;
      end if;
      Blank (Out_Text);
      Heading (Out_Text, L ("regressions_heading"));
      Note (Out_Text, L ("projects_with_regressions", Num (Item.Projects_Affected)));
      Note (Out_Text, L ("regression_count", Num (Item.Regression_Total)));
      Blank (Out_Text);
      Heading (Out_Text, L ("activity"));
      Note (Out_Text, L ("newer_running", Num (Item.Portfolio.Totals.Newer_Running)));
      Note (Out_Text, L ("newer_unfinished", Num (Item.Portfolio.Totals.Newer_Unfinished)));
   end Summary_Report;

   procedure Projects_Report (Out_Text : in out Writer; Item : Report) is
   begin
      Header (Out_Text, Item, L ("projects"));
      Blank (Out_Text);
      Project_Table (Out_Text, Item.Portfolio.Projects);
      Shown_Note (Out_Text, Natural (Item.Portfolio.Projects.Length), Item.Row_Count);
      Blank (Out_Text);
      Note (Out_Text, Ada_Quality_Summary.Text.Message
              ("label.totals_line",
               [Ada_Quality_Summary.Text.Arg ("passing", Long_Long_Integer (Item.Portfolio.Totals.Passing)),
                Ada_Quality_Summary.Text.Arg ("violations", Long_Long_Integer (Item.Portfolio.Totals.Violations)),
                Ada_Quality_Summary.Text.Arg ("incomplete", Long_Long_Integer (Item.Portfolio.Totals.Incomplete)),
                Ada_Quality_Summary.Text.Arg ("unassessed", Long_Long_Integer (Item.Portfolio.Totals.Unassessed))]));
   end Projects_Report;

   procedure Project_Report (Out_Text : in out Writer; Item : Report) is
      P : constant Project_Summary := Item.Project;
      Width : constant Natural := 14;
   begin
      Heading (Out_Text, L ("project_title", To_String (P.Name)));
      Note (Out_Text, L ("database", To_String (Item.Database_Label)), Indent => 0);
      Blank (Out_Text);
      Field (Out_Text, L ("id"), Num (P.Project_Id), Width, Number => True);
      Field (Out_Text, L ("path"), To_String (P.Project_Path), Width);
      Field (Out_Text, L ("enabled"), (if P.Enabled then L ("yes") else L ("no")), Width);
      if P.Removed then
         Field (Out_Text, L ("removed"), L ("yes"), Width);
      end if;
      Field (Out_Text, L ("quality"), Quality_Label (P.Quality), Width, Quality_Role (P.Quality));
      Field (Out_Text, L ("current_run"), Id_Text (P.Current_Run_Id), Width, Number => True);
      Field (Out_Text, L ("latest_run"), Id_Text (P.Latest_Run_Id), Width, Number => True);
      if P.Newer_Run /= No_Newer_Run then
         Field (Out_Text, L ("newer_run"), L ("newer." & Image (P.Newer_Run)), Width, Warn_Role);
      end if;
      if not Item.Has_Assessment then
         Blank (Out_Text);
         Note (Out_Text, L ("no_assessment"));
         return;
      end if;
      Field (Out_Text, L ("counts"), Ada_Quality_Summary.Text.Message
               ("label.counts_value",
                [Ada_Quality_Summary.Text.Arg ("passed", Long_Long_Integer (P.Totals.Passed)),
                 Ada_Quality_Summary.Text.Arg ("applicable", Long_Long_Integer (Applicable (P.Totals))),
                 Ada_Quality_Summary.Text.Arg ("violated", Long_Long_Integer (P.Totals.Violated)),
                 Ada_Quality_Summary.Text.Arg ("unknown", Long_Long_Integer (P.Totals.Unknown_Count)),
                 Ada_Quality_Summary.Text.Arg ("na", Long_Long_Integer (P.Totals.Not_Applicable))]), Width);
      Field (Out_Text, L ("finished"), Time_Text (Item.Assessment.Run.Finished_At), Width);
      if Out_Text.Style.Layout = Detailed_Layout then
         Field (Out_Text, L ("source"), To_String (Item.Assessment.Run.Source_Id), Width);
         Field (Out_Text, L ("policy"), To_String (Item.Assessment.Run.Policy_Id), Width);
         Field (Out_Text, L ("toolchain"), To_String (Item.Assessment.Run.Toolchain_Id), Width);
         Field (Out_Text, L ("evidence_format"),
                (if Item.Assessment.Run.Format = Ada_Quality.Reporting.Lossless_Evidence then L ("format.lossless")
                 else L ("format.legacy")), Width);
      end if;
      Blank (Out_Text);
      Heading (Out_Text, L ("indicators"));
      declare
         Columns : Column_Vectors.Vector;
         Rows    : Row_Vectors.Vector;
      begin
         Columns.Append (Col (L ("indicator")));
         Columns.Append (Col (L ("compliance")));
         Columns.Append (Col (L ("name"), Shrink => True, Priority => 2, Minimum => 8));
         Columns.Append (Col (L ("execution"), Priority => 2));
         Columns.Append (Col (L ("measurement"), Shrink => True, Priority => 2, Minimum => 8));
         Columns.Append (Col (L ("findings"), Right => True, Priority => 3));
         Columns.Append (Col (L ("summary"), Shrink => True, Priority => 3, Minimum => 10));
         for R of Item.Assessment.Results loop
            declare
               Row : Cell_Vectors.Vector;
            begin
               Row.Append (C (Image (R.Indicator)));
               Row.Append
                 (C (State_Label (State_Of (R.Compliance)), State_Role (State_Of (R.Compliance))));
               Row.Append (C (Ada_Quality.Indicators.Registry (R.Indicator).Name.all));
               Row.Append (C (Image (R.Execution)));
               Row.Append (C (Measurement_Text (R.Indicator, R.Measurement)));
               Row.Append (C (Num (Natural (R.Findings.Length))));
               Row.Append (C (To_String (R.Summary)));
               Rows.Append (Row);
            end;
         end loop;
         Table (Out_Text, Columns, Rows);
      end;
      if Out_Text.Style.Layout /= Compact_Layout then
         Blank (Out_Text);
         Heading (Out_Text, L ("findings_heading"));
         Finding_Table (Out_Text, Item.Findings, Names_Of (Item), With_Project => False);
         Shown_Note (Out_Text, Natural (Item.Findings.Length), Item.Finding_Total);
      end if;
      if Out_Text.Style.Layout = Detailed_Layout then
         Blank (Out_Text);
         Heading (Out_Text, L ("evidence_heading"));
         for R of Item.Assessment.Results loop
            Note (Out_Text, Image (R.Indicator) & "  " & To_String (R.Evidence));
         end loop;
      end if;
      Blank (Out_Text);
      Heading (Out_Text, L ("regressions_heading"));
      Baseline_Lines (Out_Text, Item.Baselines.First_Element, To_String (P.Name));
      Regression_Table (Out_Text, Item.Regressions, Names_Of (Item));
   end Project_Report;

   procedure Indicators_Report (Out_Text : in out Writer; Item : Report) is
      Columns : Column_Vectors.Vector;
      Rows    : Row_Vectors.Vector;
   begin
      Header (Out_Text, Item, L ("indicators"));
      Blank (Out_Text);
      Columns.Append (Col (L ("indicator")));
      Columns.Append (Col (L ("pass"), Right => True));
      Columns.Append (Col (L ("violation"), Right => True));
      Columns.Append (Col (L ("unknown"), Right => True));
      Columns.Append (Col (L ("not_applicable"), Right => True, Priority => 2));
      Columns.Append (Col (L ("missing"), Right => True, Priority => 2));
      Columns.Append (Col (L ("name"), Shrink => True, Priority => 2, Minimum => 8));
      Columns.Append (Col (L ("category"), Priority => 3));
      Columns.Append (Col (L ("version"), Right => True, Priority => 3));
      for Indicator of Item.Indicators loop
         declare
            Row : Cell_Vectors.Vector;
         begin
            Row.Append (C (Image (Indicator.Id)));
            Row.Append (C (Num (Indicator.Totals.Passed)));
            Row.Append
              (C (Num (Indicator.Totals.Violated), (if Indicator.Totals.Violated > 0 then Bad_Role else No_Role)));
            Row.Append (C (Num (Indicator.Totals.Unknown_Count),
                           (if Indicator.Totals.Unknown_Count > 0 then Warn_Role else No_Role)));
            Row.Append (C (Num (Indicator.Totals.Not_Applicable)));
            Row.Append (C (Num (Indicator.Totals.Missing)));
            Row.Append (C (To_String (Indicator.Name)));
            Row.Append (C (Category_Label (Indicator.Category)));
            Row.Append (C (Num (Indicator.Version)));
            Rows.Append (Row);
         end;
      end loop;
      Table (Out_Text, Columns, Rows);
      Shown_Note (Out_Text, Natural (Item.Indicators.Length), Item.Row_Count);
   end Indicators_Report;

   procedure Indicator_Report (Out_Text : in out Writer; Item : Report) is
      I       : constant Indicator_Summary := Item.Indicator;
      Columns : Column_Vectors.Vector;
      Rows    : Row_Vectors.Vector;
      Width   : constant Natural := 14;
   begin
      Heading (Out_Text, Image (I.Id) & "  " & To_String (I.Name));
      Note (Out_Text, L ("database", To_String (Item.Database_Label)), Indent => 0);
      Blank (Out_Text);
      Field (Out_Text, L ("category"), Category_Label (I.Category), Width);
      Field (Out_Text, L ("version"), Num (I.Version), Width, Number => True);
      Field (Out_Text, L ("unit"), Ada_Quality.Indicators.Measurement_Unit (I.Id), Width);
      Field (Out_Text, L ("projects_column"), Num (Item.Portfolio.Totals.Projects), Width, Number => True);
      Field (Out_Text, L ("pass"), Num (I.Totals.Passed), Width, Number => True);
      Field (Out_Text, L ("violation"), Num (I.Totals.Violated), Width, Number => True);
      Field (Out_Text, L ("unknown"), Num (I.Totals.Unknown_Count), Width, Number => True);
      Field (Out_Text, L ("not_applicable"), Num (I.Totals.Not_Applicable), Width, Number => True);
      Field (Out_Text, L ("missing"), Num (I.Totals.Missing), Width, Number => True);
      Blank (Out_Text);
      Heading (Out_Text, L ("projects"));
      Columns.Append (Col (L ("project"), Shrink => True, Minimum => 8));
      Columns.Append (Col (L ("state")));
      Columns.Append (Col (L ("measurement"), Shrink => True, Priority => 2, Minimum => 8));
      Columns.Append (Col (L ("findings"), Right => True, Priority => 2));
      Columns.Append (Col (L ("run"), Right => True, Priority => 3));
      Columns.Append (Col (L ("summary"), Shrink => True, Priority => 3, Minimum => 10));
      for Row_Item of Item.Indicator_Rows loop
         declare
            Row : Cell_Vectors.Vector;
         begin
            Row.Append (C (To_String (Row_Item.Project.Name)));
            Row.Append (C (State_Label (Row_Item.State), State_Role (Row_Item.State)));
            Row.Append (C (if Row_Item.Has_Result then Measurement_Text (I.Id, Row_Item.Result.Measurement) else "-"));
            Row.Append (C (if Row_Item.Has_Result then Num (Natural (Row_Item.Result.Findings.Length)) else "-"));
            Row.Append (C (Id_Text (Row_Item.Project.Current_Run_Id)));
            Row.Append (C (if Row_Item.Has_Result then To_String (Row_Item.Result.Summary) else "-"));
            Rows.Append (Row);
         end;
      end loop;
      if Rows.Is_Empty then
         Note (Out_Text, L ("no_projects"));
      else
         Table (Out_Text, Columns, Rows);
      end if;
      Shown_Note (Out_Text, Natural (Item.Indicator_Rows.Length), Item.Row_Count);
   end Indicator_Report;

   procedure Problems_Report (Out_Text : in out Writer; Item : Report) is
   begin
      Header (Out_Text, Item, L ("problems"));
      Blank (Out_Text);
      Note (Out_Text, L ("finding_total", Num (Item.Finding_Total)));
      for Level in reverse Severity loop
         Field (Out_Text, Severity_Label (Level), Pad (Num (Item.By_Severity (Level)), 6, True), 8, Number => True);
      end loop;
      Blank (Out_Text);
      Heading (Out_Text, L ("by_indicator"));
      if Item.Groups.Is_Empty then
         Note (Out_Text, L ("none"));
      else
         declare
            Columns : Column_Vectors.Vector;
            Rows    : Row_Vectors.Vector;
         begin
            Columns.Append (Col (L ("indicator")));
            Columns.Append (Col (L ("findings"), Right => True));
            Columns.Append (Col (L ("projects_column"), Right => True));
            Columns.Append (Col (L ("name"), Shrink => True, Priority => 2, Minimum => 8));
            for Group of Item.Groups loop
               declare
                  Row : Cell_Vectors.Vector;
               begin
                  Row.Append (C (Image (Group.Indicator)));
                  Row.Append (C (Num (Group.Findings)));
                  Row.Append (C (Num (Group.Projects)));
                  Row.Append (C (Ada_Quality.Indicators.Registry (Group.Indicator).Name.all));
                  Rows.Append (Row);
               end;
            end loop;
            Table (Out_Text, Columns, Rows);
         end;
      end if;
      Blank (Out_Text);
      Heading (Out_Text, L ("findings_heading"));
      Finding_Table (Out_Text, Item.Findings, Names_Of (Item), With_Project => True);
      Shown_Note (Out_Text, Natural (Item.Findings.Length), Item.Finding_Total);
   end Problems_Report;

   procedure Waivers_Report (Out_Text : in out Writer; Item : Report) is
      Names   : constant Name_Maps.Map := Names_Of (Item);
      Columns : Column_Vectors.Vector;
      Rows    : Row_Vectors.Vector;
   begin
      Header (Out_Text, Item, L ("waivers"));
      Blank (Out_Text);
      Note (Out_Text, L ("waiver_total", Num (Item.Waiver_Total)));
      Note (Out_Text, L ("projects_with_waivers", Num (Item.Waiver_Projects)));
      Blank (Out_Text);
      Columns.Append (Col (L ("project"), Shrink => True, Minimum => 8));
      Columns.Append (Col (L ("indicator")));
      Columns.Append (Col (L ("target"), Shrink => True, Minimum => 8));
      Columns.Append (Col (L ("justification"), Shrink => True, Priority => 2, Minimum => 10));
      Columns.Append (Col (L ("location"), Shrink => True, Priority => 3, Minimum => 8));
      Columns.Append (Col (L ("run"), Right => True, Priority => 3));
      for F of Item.Waivers loop
         declare
            Row     : Cell_Vectors.Vector;
            Message : constant String := To_String (F.Message);
         begin
            Row.Append (C (Name_Of (Names, F.Project_Id)));
            Row.Append (C (Image (F.Indicator)));
            Row.Append (C (Waiver_Target (Message)));
            Row.Append (C (Waiver_Justification (Message)));
            Row.Append (C (Location_Of (F)));
            Row.Append (C (Num (F.Run_Id)));
            Rows.Append (Row);
         end;
      end loop;
      if Rows.Is_Empty then
         Note (Out_Text, L ("no_waivers"));
      else
         Table (Out_Text, Columns, Rows);
      end if;
      Shown_Note (Out_Text, Natural (Item.Waivers.Length), Item.Waiver_Total);
   end Waivers_Report;

   procedure Compare_Report (Out_Text : in out Writer; Item : Report) is
      Pair  : constant Pair_Comparison := Item.Pair;
      Width : constant Natural := 14;
      Ready : constant Boolean := Pair.Comparison = Ada_Quality.History.Comparison_Available;
   begin
      Heading (Out_Text, L ("compare_title", To_String (Item.Project.Name)));
      Note (Out_Text, L ("database", To_String (Item.Database_Label)), Indent => 0);
      Blank (Out_Text);
      Field (Out_Text, L ("path"), To_String (Item.Project.Project_Path), Width);
      Field (Out_Text, L ("baseline_run"), Pair_Run_Text (Pair.Baseline), Width,
             (if Pair.Baseline.Has_Quality then Quality_Role (Pair.Baseline.Quality) else Warn_Role));
      Field (Out_Text, L ("current_run"), Pair_Run_Text (Pair.Current), Width,
             (if Pair.Current.Has_Quality then Quality_Role (Pair.Current.Quality) else Warn_Role));
      Field (Out_Text, L ("comparison"), L ("comparison." & Image (Pair.Comparison)), Width,
             (if Ready then Good_Role else Warn_Role));
      if Pair.Has_Reason then
         Field (Out_Text, L ("incompatibility"), L ("reason." & Image (Pair.Reason)), Width, Warn_Role);
      end if;
      if Pair.Policy_Changed then
         Note (Out_Text, L ("pair.policy_changed"));
      end if;
      if Ready then
         Blank (Out_Text);
         Heading (Out_Text, L ("regressions_heading"));
         Note (Out_Text, L ("regression_count", Num (Item.Regression_Total)));
         Regression_Table (Out_Text, Item.Regressions, Names_Of (Item));
         Shown_Note (Out_Text, Natural (Item.Regressions.Length), Item.Regression_Total);
      end if;
   end Compare_Report;

   procedure Regressions_Report (Out_Text : in out Writer; Item : Report) is
   begin
      Header (Out_Text, Item, L ("regressions_heading"));
      Blank (Out_Text);
      Note (Out_Text, L ("projects_with_regressions", Num (Item.Projects_Affected)));
      Note (Out_Text, L ("regression_count", Num (Item.Regression_Total)));
      Blank (Out_Text);
      Regression_Table (Out_Text, Item.Regressions, Names_Of (Item));
      Shown_Note (Out_Text, Natural (Item.Regressions.Length), Item.Regression_Total);
      Blank (Out_Text);
      Heading (Out_Text, L ("baselines"));
      declare
         Names : constant Name_Maps.Map := Names_Of (Item);
      begin
         for Info of Item.Baselines loop
            if Info.Status /= Compared or else Info.Policy_Changed or else not Info.Excluded.Is_Empty or else
              Out_Text.Style.Layout = Detailed_Layout
            then
               Baseline_Lines (Out_Text, Info, Name_Of (Names, Info.Project_Id));
            end if;
         end loop;
      end;
   end Regressions_Report;

   procedure Trends_Report (Out_Text : in out Writer; Item : Report) is
      Names : constant Name_Maps.Map := Names_Of (Item);
   begin
      Header (Out_Text, Item, L ("trends"));
      if Item.Undated > 0 then
         Note (Out_Text, L ("undated", Num (Item.Undated)));
      end if;
      Blank (Out_Text);
      Heading (Out_Text, L ("daily_states"));
      if Item.Daily.Is_Empty then
         Note (Out_Text, L ("no_dated_assessments"));
      else
         declare
            Columns : Column_Vectors.Vector;
            Rows    : Row_Vectors.Vector;
         begin
            Columns.Append (Col (L ("date")));
            Columns.Append (Col (Quality_Label (Passing, True), Right => True));
            Columns.Append (Col (Quality_Label (Violations, True), Right => True));
            Columns.Append (Col (Quality_Label (Incomplete, True), Right => True));
            Columns.Append (Col (Quality_Label (Unassessed, True), Right => True));
            Columns.Append (Col (L ("fail"), Right => True, Priority => 2));
            Columns.Append (Col (L ("unknown"), Right => True, Priority => 2));
            for Day of Item.Daily loop
               declare
                  Row : Cell_Vectors.Vector;
               begin
                  Row.Append (C (To_String (Day.Day)));
                  Row.Append (C (Num (Day.Totals.Passing)));
                  Row.Append (C (Num (Day.Totals.Violations)));
                  Row.Append (C (Num (Day.Totals.Incomplete)));
                  Row.Append (C (Num (Day.Totals.Unassessed)));
                  Row.Append (C (Num (Day.Totals.Indicator_Violations)));
                  Row.Append (C (Num (Day.Totals.Unknown_Results)));
                  Rows.Append (Row);
               end;
            end loop;
            Table (Out_Text, Columns, Rows);
         end;
      end if;
      for Series of Item.Series loop
         if not Series.Points.Is_Empty or else Out_Text.Style.Layout = Detailed_Layout then
            Blank (Out_Text);
            Heading (Out_Text, Image (Series.Indicator) & "  " &
                       Ada_Quality.Indicators.Registry (Series.Indicator).Name.all & " (" &
                       To_String (Series.Unit) & ")");
            Note (Out_Text, Ada_Quality_Summary.Text.Message
                    ("label.series_counts",
                     [Ada_Quality_Summary.Text.Arg ("included", Long_Long_Integer (Series.Projects_Included)),
                      Ada_Quality_Summary.Text.Arg ("excluded", Long_Long_Integer (Series.Projects_Excluded)),
                      Ada_Quality_Summary.Text.Arg
                        ("observations", Long_Long_Integer (Series.Excluded_Observations))]));
            if Series.Points.Is_Empty then
               Note (Out_Text, L ("no_numeric"));
            elsif Out_Text.Style.Layout /= Compact_Layout then
               declare
                  Columns : Column_Vectors.Vector;
                  Rows    : Row_Vectors.Vector;
               begin
                  Columns.Append (Col (L ("run"), Right => True));
                  Columns.Append (Col (L ("project"), Shrink => True, Minimum => 8));
                  Columns.Append (Col (L ("value"), Right => True));
                  Columns.Append (Col (L ("observed"), Priority => 2));
                  for Point of Series.Points loop
                     declare
                        Row : Cell_Vectors.Vector;
                     begin
                        Row.Append (C (Num (Point.Run_Id)));
                        Row.Append (C (Name_Of (Names, Point.Project_Id)));
                        Row.Append (C (if Series.Kind = Decimal_Value then Basis_Points_Image (Point.Value)
                                       else Trimmed (Point.Value)));
                        Row.Append (C (Time_Text (Point.Observed)));
                        Rows.Append (Row);
                     end;
                  end loop;
                  Table (Out_Text, Columns, Rows);
               end;
            end if;
         end if;
      end loop;
   end Trends_Report;

   procedure History_Report (Out_Text : in out Writer; Item : Report) is
      Columns : Column_Vectors.Vector;
      Rows    : Row_Vectors.Vector;
   begin
      Heading (Out_Text, L ("history_title", To_String (Item.Project.Name)));
      Note (Out_Text, L ("database", To_String (Item.Database_Label)), Indent => 0);
      Blank (Out_Text);
      Note (Out_Text, Ada_Quality_Summary.Text.Message
              ("label.history_counts",
               [Ada_Quality_Summary.Text.Arg ("completed", Long_Long_Integer (Item.Completed_Count)),
                Ada_Quality_Summary.Text.Arg ("running", Long_Long_Integer (Item.Running_Count)),
                Ada_Quality_Summary.Text.Arg ("interrupted", Long_Long_Integer (Item.Interrupted_Count)),
                Ada_Quality_Summary.Text.Arg ("invalid", Long_Long_Integer (Item.Invalid_Count))]));
      if Item.Undated > 0 then
         Note (Out_Text, L ("undated", Num (Item.Undated)));
      end if;
      Blank (Out_Text);
      Columns.Append (Col (L ("run"), Right => True));
      Columns.Append (Col (L ("state")));
      Columns.Append (Col (L ("quality")));
      Columns.Append (Col (L ("finished"), Priority => 2));
      Columns.Append (Col (L ("started"), Priority => 3));
      Columns.Append (Col (L ("policy"), Shrink => True, Priority => 3, Minimum => 8));
      Columns.Append (Col (L ("toolchain"), Shrink => True, Priority => 3, Minimum => 8));
      for Run of Item.History loop
         declare
            Row : Cell_Vectors.Vector;
         begin
            Row.Append (C (Num (Run.Run_Id)));
            Row.Append (C (Run_State_Label (Run.State),
                           (if Run.State = Assessment_Completed then No_Role else Warn_Role)));
            Row.Append (if Run.Has_Quality then C (Quality_Label (Run.Quality), Quality_Role (Run.Quality))
                        else C ("-"));
            Row.Append (C (Time_Text (Run.Finished_At)));
            Row.Append (C (Time_Text (Run.Started_At)));
            Row.Append (C (To_String (Run.Policy_Id)));
            Row.Append (C (To_String (Run.Toolchain_Id)));
            Rows.Append (Row);
         end;
      end loop;
      if Rows.Is_Empty then
         Note (Out_Text, L ("no_runs"));
      else
         Table (Out_Text, Columns, Rows);
      end if;
      Shown_Note (Out_Text, Natural (Item.History.Length), Item.Row_Count);
   end History_Report;

   function Render (Item : Report; Style : Settings) return String is
      Out_Text : Writer := (Text => Null_Unbounded_String, Style => Style, others => <>);
   begin
      Out_Text.Style.Width := Environment.Clamp (Style.Width);
      case Item.Metadata.Kind is
         when Model.Summary_Report => Summary_Report (Out_Text, Item);
         when Model.Projects_Report => Projects_Report (Out_Text, Item);
         when Model.Project_Report => Project_Report (Out_Text, Item);
         when Model.Indicators_Report => Indicators_Report (Out_Text, Item);
         when Model.Indicator_Report => Indicator_Report (Out_Text, Item);
         when Model.Problems_Report => Problems_Report (Out_Text, Item);
         when Model.Waivers_Report => Waivers_Report (Out_Text, Item);
         when Model.Regressions_Report => Regressions_Report (Out_Text, Item);
         when Model.Compare_Report => Compare_Report (Out_Text, Item);
         when Model.Trends_Report => Trends_Report (Out_Text, Item);
         when Model.History_Report => History_Report (Out_Text, Item);
      end case;
      return To_String (Out_Text.Text);
   end Render;
end Ada_Quality_Summary.Terminal;
