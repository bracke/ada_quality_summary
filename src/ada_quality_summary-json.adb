with Ada.Calendar;
with Ada.Characters.Handling;
with Ada.Strings.Unbounded;
with Ada_Quality.History;
with Ada_Quality.Indicators;
with Ada_Quality.Reporting;
with Ada_Quality.Types;
with Ada_Quality_Summary.Aggregation;
with Ada_Quality_Summary.Model;
with Ada_Quality_Summary.Options;
with Ada_Quality_Summary.Text;
with Ada_Quality_Summary.Trends;
with Jsonlib.Documents;
with Jsonlib.Serializers;

package body Ada_Quality_Summary.JSON is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Types;
   use Ada_Quality_Summary.Model;
   use Ada_Quality_Summary.Reports;
   use Jsonlib.Documents;
   use type Ada_Quality.Reporting.Evidence_Format;

   function Lower (Text : String) return String renames Ada.Characters.Handling.To_Lower;

   function Category_Image (Category : Ada_Quality.Indicators.Indicator_Category) return String is
     (Lower (Ada_Quality.Indicators.Indicator_Category'Image (Category)));

   function Severity_Image (Level : Severity) return String is (Lower (Severity'Image (Level)));

   function Run_State_Image (State : Assessment_Status) return String is
     (case State is
         when Assessment_Running => "running",
         when Assessment_Completed => "completed",
         when Assessment_Invalid => "invalid",
         when Assessment_Interrupted => "interrupted");

   function Render
     (Item : Report; Pretty : Boolean := False; Maximum_Bytes : Positive := Default_Maximum_Bytes) return String
   is
      Doc : Document;

      function Int (Value : Long_Long_Integer) return Node is (Doc.New_Integer (Value));
      function Nat (Value : Natural) return Node is (Doc.New_Integer (Long_Long_Integer (Value)));
      function Str (Value : String) return Node is (Doc.New_String (Value));
      function Str (Value : Ada.Strings.Unbounded.Unbounded_String) return Node is (Doc.New_String (To_String (Value)));
      function Bool (Value : Boolean) return Node is (Doc.New_Boolean (Value));
      function Null_Value return Node is (Doc.New_Null);

      --  Zero is the documented absent sentinel for optional identities.
      function Id_Or_Null (Value : Natural) return Node is (if Value = 0 then Null_Value else Nat (Value));

      function Time_Or_Null (Value : Ada_Quality.Reporting.Optional_Timestamp) return Node is
        (if Value.Present then Str (Ada_Quality.Reporting.Image (Value)) else Null_Value);

      function Date_Or_Null (Value : Ada_Quality_Summary.Options.Date_Bound; Upper : Boolean) return Node is
      begin
         if not Value.Present then
            return Null_Value;
         end if;
         declare
            Stamp : constant String :=
              Ada_Quality.Reporting.Image
                ((Present => True, Value => (if Upper then Ada.Calendar."-" (Value.Value, 86_400.0) else Value.Value)));
         begin
            return Str (Stamp (Stamp'First .. Stamp'First + 9));
         end;
      end Date_Or_Null;

      procedure Put (Object : Node; Name : String; Value : Node) is
      begin
         Doc.Insert (Object, Name, Value);
      end Put;

      function Indicator_Totals_Object (Totals : Indicator_Totals) return Node is
         Object : constant Node := Doc.New_Object;
      begin
         Put (Object, "passed", Nat (Totals.Passed));
         Put (Object, "violated", Nat (Totals.Violated));
         Put (Object, "unknown", Nat (Totals.Unknown_Count));
         Put (Object, "not_applicable", Nat (Totals.Not_Applicable));
         return Object;
      end Indicator_Totals_Object;

      function Project_Object (Project : Project_Summary) return Node is
         Object : constant Node := Doc.New_Object;
      begin
         Put (Object, "project_id", Nat (Project.Project_Id));
         Put (Object, "name", Str (Project.Name));
         Put (Object, "path", Str (Project.Project_Path));
         Put (Object, "enabled", Bool (Project.Enabled));
         Put (Object, "removed", Bool (Project.Removed));
         Put (Object, "quality", Str (Image (Project.Quality)));
         Put (Object, "current_run_id", Id_Or_Null (Project.Current_Run_Id));
         Put (Object, "latest_run_id", Id_Or_Null (Project.Latest_Run_Id));
         Put (Object, "newer_run", Str (Image (Project.Newer_Run)));
         --  Unassessed projects have no indicator states at all; they are not reported as unknown.
         Put (Object, "indicators",
              (if Project.Current_Run_Id = 0 then Null_Value else Indicator_Totals_Object (Project.Totals)));
         Put (Object, "finding_count", Nat (Project.Finding_Count));
         Put (Object, "regression_count", Nat (Project.Regression_Count));
         return Object;
      end Project_Object;

      function Projects_Array (Projects : Model.Project_Vectors.Vector) return Node is
         List : constant Node := Doc.New_Array;
      begin
         for Project of Projects loop
            Doc.Append (List, Project_Object (Project));
         end loop;
         return List;
      end Projects_Array;

      function Totals_Object (Totals : Portfolio_Totals) return Node is
         Object : constant Node := Doc.New_Object;
      begin
         Put (Object, "projects", Nat (Totals.Projects));
         Put (Object, "passing", Nat (Totals.Passing));
         Put (Object, "violations", Nat (Totals.Violations));
         Put (Object, "incomplete", Nat (Totals.Incomplete));
         Put (Object, "unassessed", Nat (Totals.Unassessed));
         Put (Object, "enabled", Nat (Totals.Enabled));
         Put (Object, "disabled", Nat (Totals.Disabled));
         Put (Object, "findings", Nat (Totals.Findings));
         Put (Object, "indicator_violations", Nat (Totals.Indicator_Violations));
         Put (Object, "unknown_results", Nat (Totals.Unknown_Results));
         Put (Object, "newer_running", Nat (Totals.Newer_Running));
         Put (Object, "newer_unfinished", Nat (Totals.Newer_Unfinished));
         Put (Object, "projects_with_regressions", Nat (Totals.With_Regressions));
         return Object;
      end Totals_Object;

      function Indicator_Summary_Object (Indicator : Indicator_Summary) return Node is
         Object : constant Node := Doc.New_Object;
      begin
         Put (Object, "id", Str (Image (Indicator.Id)));
         Put (Object, "name", Str (Indicator.Name));
         Put (Object, "category", Str (Category_Image (Indicator.Category)));
         Put (Object, "version", Nat (Indicator.Version));
         Put (Object, "passed", Nat (Indicator.Totals.Passed));
         Put (Object, "violated", Nat (Indicator.Totals.Violated));
         Put (Object, "unknown", Nat (Indicator.Totals.Unknown_Count));
         Put (Object, "not_applicable", Nat (Indicator.Totals.Not_Applicable));
         Put (Object, "missing", Nat (Indicator.Totals.Missing));
         Put (Object, "affected_projects", Nat (Indicator.Affected));
         return Object;
      end Indicator_Summary_Object;

      function Measurement_Object (Id : Indicator_Id; Value : Measurement_Value) return Node is
         Object : constant Node := Doc.New_Object;
      begin
         case Value.Kind is
            when Unavailable_Value =>
               Put (Object, "kind", Str ("unavailable"));
               Put (Object, "reason", Str (Value.Reason));
            when Boolean_Value =>
               Put (Object, "kind", Str ("boolean"));
               Put (Object, "value", Bool (Value.Boolean_Data));
            when Integer_Value =>
               Put (Object, "kind", Str ("integer"));
               Put (Object, "value", Int (Value.Integer_Data));
               Put (Object, "unit", Str (Ada_Quality.Indicators.Measurement_Unit (Id)));
            when Decimal_Value =>
               Put (Object, "kind", Str ("decimal"));
               Put (Object, "basis_points", Int (Value.Basis_Points));
            when Text_Value =>
               Put (Object, "kind", Str ("text"));
               Put (Object, "value", Str (Value.Text_Data));
            when Enum_Value =>
               Put (Object, "kind", Str ("enum"));
               Put (Object, "value", Str (Value.Text_Data));
         end case;
         return Object;
      end Measurement_Object;

      function Finding_Object (Finding : Finding_Summary) return Node is
         Object : constant Node := Doc.New_Object;
      begin
         Put (Object, "project_id", Nat (Finding.Project_Id));
         Put (Object, "run_id", Nat (Finding.Run_Id));
         Put (Object, "indicator_id", Str (Image (Finding.Indicator)));
         Put (Object, "rule", Str (Finding.Rule));
         Put (Object, "severity", Str (Severity_Image (Finding.Level)));
         Put (Object, "message", Str (Finding.Message));
         Put (Object, "relative_path", (if Length (Finding.Path) = 0 then Null_Value else Str (Finding.Path)));
         Put (Object, "line", (if Finding.Line = 0 then Null_Value else Nat (Finding.Line)));
         Put (Object, "fingerprint", Str (Finding.Fingerprint));
         return Object;
      end Finding_Object;

      function Findings_Array (Findings : Finding_Summary_Vectors.Vector) return Node is
         List : constant Node := Doc.New_Array;
      begin
         for Finding of Findings loop
            Doc.Append (List, Finding_Object (Finding));
         end loop;
         return List;
      end Findings_Array;

      function Result_Object (Project_Id, Run_Id : Positive; Result : Indicator_Result) return Node is
         Object     : constant Node := Doc.New_Object;
         Descriptor : constant Ada_Quality.Indicators.Indicator_Descriptor :=
           Ada_Quality.Indicators.Registry (Result.Indicator);
         Findings   : constant Node := Doc.New_Array;
      begin
         Put (Object, "id", Str (Image (Result.Indicator)));
         Put (Object, "name", Str (Descriptor.Name.all));
         Put (Object, "category", Str (Category_Image (Descriptor.Category)));
         Put (Object, "version", Nat (Descriptor.Version));
         Put (Object, "execution", Str (Image (Result.Execution)));
         Put (Object, "compliance", Str (Image (Result.Compliance)));
         Put (Object, "applicable", Bool (Result.Applicable));
         Put (Object, "summary", Str (Result.Summary));
         Put (Object, "evidence", Str (Result.Evidence));
         Put (Object, "measurement", Measurement_Object (Result.Indicator, Result.Measurement));
         for F of Result.Findings loop
            Doc.Append
              (Findings,
               Finding_Object
                 ((Project_Id => Project_Id, Run_Id => Run_Id, Indicator => F.Indicator, Rule => F.Rule,
                   Level => F.Level, Message => F.Message, Path => F.Relative_Path, Line => F.Line,
                   Fingerprint => F.Fingerprint)));
         end loop;
         Put (Object, "findings", Findings);
         return Object;
      end Result_Object;

      function Kind_Counts_Object (Counts : Kind_Counts) return Node is
         Object : constant Node := Doc.New_Object;
      begin
         for Kind in Counts'Range loop
            declare
               Name : String := Ada_Quality.History.Image (Kind);
            begin
               for C of Name loop
                  if C = '-' then C := '_'; end if;
               end loop;
               Put (Object, Name, Nat (Counts (Kind)));
            end;
         end loop;
         return Object;
      end Kind_Counts_Object;

      function Regression_Kind_Image (Kind : Ada_Quality.History.Regression_Kind) return String is
         Name : String := Ada_Quality.History.Image (Kind);
      begin
         for C of Name loop
            if C = '-' then C := '_'; end if;
         end loop;
         return Name;
      end Regression_Kind_Image;

      function Regression_Object (Change : Regression_Summary) return Node is
         Object : constant Node := Doc.New_Object;
      begin
         Put (Object, "project_id", Nat (Change.Project_Id));
         Put (Object, "current_run_id", Nat (Change.Current_Run_Id));
         Put (Object, "baseline_run_id", Nat (Change.Baseline_Run_Id));
         Put (Object, "indicator_id", Str (Image (Change.Indicator)));
         Put (Object, "kind", Str (Regression_Kind_Image (Change.Kind)));
         Put (Object, "before", Str (Change.Before));
         Put (Object, "after", Str (Change.After));
         return Object;
      end Regression_Object;

      function Regressions_Array (Changes : Regression_Summary_Vectors.Vector) return Node is
         List : constant Node := Doc.New_Array;
      begin
         for Change of Changes loop
            Doc.Append (List, Regression_Object (Change));
         end loop;
         return List;
      end Regressions_Array;

      function Baseline_Object (Info : Trends.Baseline_Info) return Node is
         Object   : constant Node := Doc.New_Object;
         Excluded : constant Node := Doc.New_Array;
      begin
         Put (Object, "project_id", Nat (Info.Project_Id));
         Put (Object, "status", Str (Trends.Image (Info.Status)));
         Put (Object, "current_run_id", Id_Or_Null (Info.Current_Run_Id));
         Put (Object, "baseline_run_id", Id_Or_Null (Info.Baseline_Run_Id));
         for Run of Info.Excluded loop
            declare
               Entry_Object : constant Node := Doc.New_Object;
            begin
               Put (Entry_Object, "run_id", Nat (Run.Run_Id));
               Put (Entry_Object, "reason", Str (Trends.Image (Run.Reason)));
               Doc.Append (Excluded, Entry_Object);
            end;
         end loop;
         Put (Object, "excluded_runs", Excluded);
         return Object;
      end Baseline_Object;

      function Run_Object (Run : History_Summary) return Node is
         Object : constant Node := Doc.New_Object;
      begin
         Put (Object, "run_id", Nat (Run.Run_Id));
         Put (Object, "state", Str (Run_State_Image (Run.State)));
         Put (Object, "source_fingerprint", Str (Run.Source_Id));
         Put (Object, "policy_fingerprint", Str (Run.Policy_Id));
         Put (Object, "toolchain_fingerprint", Str (Run.Toolchain_Id));
         Put (Object, "started_at", Time_Or_Null (Run.Started_At));
         Put (Object, "finished_at", Time_Or_Null (Run.Finished_At));
         Put (Object, "quality", (if Run.Has_Quality then Str (Image (Run.Quality)) else Null_Value));
         return Object;
      end Run_Object;

      function Summary_Data return Node is
         Data    : constant Node := Doc.New_Object;
         Common  : constant Node := Doc.New_Array;
         Summary : constant Node := Doc.New_Object;
         Activity : constant Node := Doc.New_Object;
      begin
         Put (Data, "totals", Totals_Object (Item.Portfolio.Totals));
         Put (Data, "projects", Projects_Array (Item.Portfolio.Projects));
         for Indicator of Item.Common loop
            declare
               Object : constant Node := Doc.New_Object;
            begin
               Put (Object, "indicator_id", Str (Image (Indicator.Id)));
               Put (Object, "name", Str (Indicator.Name));
               Put (Object, "projects", Nat (Indicator.Totals.Violated));
               Doc.Append (Common, Object);
            end;
         end loop;
         Put (Data, "common_violations", Common);
         Put (Summary, "projects_with_regressions", Nat (Item.Projects_Affected));
         Put (Summary, "regressions", Nat (Item.Regression_Total));
         Put (Summary, "by_kind", Kind_Counts_Object (Item.By_Kind));
         Put (Data, "regression_summary", Summary);
         Put (Activity, "newer_running", Nat (Item.Portfolio.Totals.Newer_Running));
         Put (Activity, "newer_unfinished", Nat (Item.Portfolio.Totals.Newer_Unfinished));
         Put (Data, "activity", Activity);
         return Data;
      end Summary_Data;

      function Projects_Data return Node is
         Data : constant Node := Doc.New_Object;
      begin
         Put (Data, "projects", Projects_Array (Item.Portfolio.Projects));
         Put (Data, "totals", Totals_Object (Item.Portfolio.Totals));
         return Data;
      end Projects_Data;

      function Project_Data return Node is
         Data       : constant Node := Doc.New_Object;
         Indicators : constant Node := Doc.New_Array;
      begin
         Put (Data, "project", Project_Object (Item.Project));
         if Item.Has_Assessment then
            declare
               Run        : constant Ada_Quality.Reporting.Run_Record := Item.Assessment.Run;
               Assessment : constant Node := Doc.New_Object;
            begin
               Put (Assessment, "run_id", Nat (Run.Id));
               Put (Assessment, "source_fingerprint", Str (Run.Source_Id));
               Put (Assessment, "policy_fingerprint", Str (Run.Policy_Id));
               Put (Assessment, "toolchain_fingerprint", Str (Run.Toolchain_Id));
               Put (Assessment, "started_at", Time_Or_Null (Run.Started_At));
               Put (Assessment, "finished_at", Time_Or_Null (Run.Finished_At));
               Put (Assessment, "evidence_format",
                    Str (if Run.Format = Ada_Quality.Reporting.Lossless_Evidence then "lossless" else "legacy"));
               Put (Assessment, "totals", Indicator_Totals_Object (Item.Project.Totals));
               Put (Data, "assessment", Assessment);
               for Result of Item.Assessment.Results loop
                  Doc.Append (Indicators, Result_Object (Item.Project.Project_Id, Run.Id, Result));
               end loop;
            end;
         else
            Put (Data, "assessment", Null_Value);
         end if;
         Put (Data, "indicators", Indicators);
         Put (Data, "findings", Findings_Array (Item.Findings));
         Put (Data, "regressions", Regressions_Array (Item.Regressions));
         Put (Data, "baseline", Baseline_Object (Item.Baselines.First_Element));
         return Data;
      end Project_Data;

      function Indicators_Data return Node is
         Data : constant Node := Doc.New_Object;
         List : constant Node := Doc.New_Array;
      begin
         for Indicator of Item.Indicators loop
            Doc.Append (List, Indicator_Summary_Object (Indicator));
         end loop;
         Put (Data, "indicators", List);
         Put (Data, "project_count", Nat (Item.Portfolio.Totals.Projects));
         return Data;
      end Indicators_Data;

      function Indicator_Data return Node is
         Data   : constant Node := Doc.New_Object;
         List   : constant Node := Doc.New_Array;
         Totals : constant Node := Doc.New_Object;
      begin
         Put (Data, "indicator", Indicator_Summary_Object (Item.Indicator));
         for Row of Item.Indicator_Rows loop
            declare
               Object : constant Node := Doc.New_Object;
            begin
               Put (Object, "project_id", Nat (Row.Project.Project_Id));
               Put (Object, "name", Str (Row.Project.Name));
               Put (Object, "path", Str (Row.Project.Project_Path));
               Put (Object, "state", Str (Aggregation.Image (Row.State)));
               Put (Object, "run_id", Id_Or_Null (Row.Project.Current_Run_Id));
               Put (Object, "result",
                    (if Row.Has_Result
                     then Result_Object (Row.Project.Project_Id, Row.Project.Current_Run_Id, Row.Result)
                     else Null_Value));
               Doc.Append (List, Object);
            end;
         end loop;
         Put (Data, "projects", List);
         Put (Totals, "projects", Nat (Item.Portfolio.Totals.Projects));
         Put (Totals, "passed", Nat (Item.Indicator.Totals.Passed));
         Put (Totals, "violated", Nat (Item.Indicator.Totals.Violated));
         Put (Totals, "unknown", Nat (Item.Indicator.Totals.Unknown_Count));
         Put (Totals, "not_applicable", Nat (Item.Indicator.Totals.Not_Applicable));
         Put (Totals, "missing", Nat (Item.Indicator.Totals.Missing));
         Put (Data, "totals", Totals);
         return Data;
      end Indicator_Data;

      function Problems_Data return Node is
         Data     : constant Node := Doc.New_Object;
         Groups   : constant Node := Doc.New_Array;
         Totals   : constant Node := Doc.New_Object;
         Severity_Object : constant Node := Doc.New_Object;
      begin
         Put (Data, "findings", Findings_Array (Item.Findings));
         for Group of Item.Groups loop
            declare
               Object : constant Node := Doc.New_Object;
            begin
               Put (Object, "indicator_id", Str (Image (Group.Indicator)));
               Put (Object, "name", Str (Ada_Quality.Indicators.Registry (Group.Indicator).Name.all));
               Put (Object, "findings", Nat (Group.Findings));
               Put (Object, "projects", Nat (Group.Projects));
               Doc.Append (Groups, Object);
            end;
         end loop;
         Put (Data, "grouped_by_indicator", Groups);
         Put (Totals, "findings", Nat (Item.Finding_Total));
         Put (Totals, "projects", Nat (Item.Finding_Projects));
         for Level in reverse Severity loop
            Put (Severity_Object, Severity_Image (Level), Nat (Item.By_Severity (Level)));
         end loop;
         Put (Totals, "by_severity", Severity_Object);
         Put (Data, "totals", Totals);
         return Data;
      end Problems_Data;

      function Regressions_Data return Node is
         Data       : constant Node := Doc.New_Object;
         Exclusions : constant Node := Doc.New_Array;
         Totals     : constant Node := Doc.New_Object;
      begin
         Put (Data, "regressions", Regressions_Array (Item.Regressions));
         Put (Data, "projects_affected", Nat (Item.Projects_Affected));
         for Info of Item.Baselines loop
            Doc.Append (Exclusions, Baseline_Object (Info));
         end loop;
         Put (Data, "baseline_exclusions", Exclusions);
         Put (Totals, "regressions", Nat (Item.Regression_Total));
         Put (Totals, "by_kind", Kind_Counts_Object (Item.By_Kind));
         Put (Data, "totals", Totals);
         return Data;
      end Regressions_Data;

      function Trends_Data return Node is
         Data      : constant Node := Doc.New_Object;
         Series    : constant Node := Doc.New_Array;
         Snapshots : constant Node := Doc.New_Array;
         Meta      : constant Node := Doc.New_Object;
         Excluded  : Natural := 0;
      begin
         for Trend of Item.Series loop
            declare
               Object : constant Node := Doc.New_Object;
               Points : constant Node := Doc.New_Array;
            begin
               Put (Object, "indicator_id", Str (Image (Trend.Indicator)));
               Put (Object, "name", Str (Ada_Quality.Indicators.Registry (Trend.Indicator).Name.all));
               Put (Object, "measurement_kind", Str (if Trend.Kind = Decimal_Value then "decimal" else "integer"));
               Put (Object, "unit", Str (Trend.Unit));
               for Point of Trend.Points loop
                  declare
                     P : constant Node := Doc.New_Object;
                  begin
                     Put (P, "project_id", Nat (Point.Project_Id));
                     Put (P, "run_id", Nat (Point.Run_Id));
                     Put (P, "value", Int (Point.Value));
                     Put (P, "observed_at", Time_Or_Null (Point.Observed));
                     Doc.Append (Points, P);
                  end;
               end loop;
               Put (Object, "points", Points);
               Put (Object, "projects_included", Nat (Trend.Projects_Included));
               Put (Object, "projects_excluded", Nat (Trend.Projects_Excluded));
               Put (Object, "excluded_observations", Nat (Trend.Excluded_Observations));
               Doc.Append (Series, Object);
               Excluded := Excluded + Trend.Excluded_Observations;
            end;
         end loop;
         Put (Data, "series", Series);
         Put (Data, "excluded_observations", Nat (Excluded));
         Put (Meta, "method", Str ("ada_quality.history.metric_trend"));
         Put (Meta, "reference", Str ("current_completed_assessment"));
         Put (Meta, "since", Date_Or_Null (Item.Since, Upper => False));
         Put (Meta, "until", Date_Or_Null (Item.Until_Date, Upper => True));
         Put (Meta, "undated_excluded", Nat (Item.Undated));
         Put (Data, "comparison_metadata", Meta);
         for Day of Item.Daily loop
            declare
               Object : constant Node := Doc.New_Object;
            begin
               Put (Object, "date", Str (Day.Day));
               Put (Object, "projects", Nat (Day.Totals.Projects));
               Put (Object, "passing", Nat (Day.Totals.Passing));
               Put (Object, "violations", Nat (Day.Totals.Violations));
               Put (Object, "incomplete", Nat (Day.Totals.Incomplete));
               Put (Object, "unassessed", Nat (Day.Totals.Unassessed));
               Put (Object, "indicator_violations", Nat (Day.Totals.Indicator_Violations));
               Put (Object, "unknown_results", Nat (Day.Totals.Unknown_Results));
               Doc.Append (Snapshots, Object);
            end;
         end loop;
         Put (Data, "snapshots", Snapshots);
         return Data;
      end Trends_Data;

      function History_Data return Node is
         Data : constant Node := Doc.New_Object;
         Runs : constant Node := Doc.New_Array;
      begin
         Put (Data, "project", Project_Object (Item.Project));
         for Run of Item.History loop
            Doc.Append (Runs, Run_Object (Run));
         end loop;
         Put (Data, "runs", Runs);
         Put (Data, "completed_count", Nat (Item.Completed_Count));
         Put (Data, "interrupted_count", Nat (Item.Interrupted_Count));
         Put (Data, "invalid_count", Nat (Item.Invalid_Count));
         Put (Data, "running_count", Nat (Item.Running_Count));
         Put (Data, "undated_excluded", Nat (Item.Undated));
         return Data;
      end History_Data;

      Root      : constant Node := Doc.New_Object;
      Source    : constant Node := Doc.New_Object;
      Selection : constant Node := Doc.New_Object;
   begin
      Put (Root, "schema_version", Nat (Item.Metadata.Format_Version));
      Put (Root, "report_type", Str (Image (Item.Metadata.Kind)));
      Put (Source, "application", Str ("ada_quality"));
      Put (Source, "database_schema_version", Nat (Item.Metadata.Source_Schema_Version));
      Put (Source, "snapshot", Str (Item.Metadata.Snapshot_Identity));
      Put (Root, "source", Source);
      Put (Selection, "include_removed", Bool (Item.Filter.Include_Removed));
      Put (Selection, "enabled_only", Bool (Item.Filter.Enabled_Only));
      Put (Selection, "project_id", Id_Or_Null (Item.Filter.Project_Id));
      Put (Selection, "status", (if Item.Filter.Has_Status then Str (Image (Item.Filter.Status)) else Null_Value));
      Put (Selection, "limit", Id_Or_Null (Item.Limit));
      Put (Selection, "selected_projects", Nat (Item.Metadata.Selected_Projects));
      Put (Root, "selection", Selection);
      Put (Root, "data",
           (case Item.Metadata.Kind is
               when Summary_Report => Summary_Data,
               when Projects_Report => Projects_Data,
               when Project_Report => Project_Data,
               when Indicators_Report => Indicators_Data,
               when Indicator_Report => Indicator_Data,
               when Problems_Report => Problems_Data,
               when Regressions_Report => Regressions_Data,
               when Trends_Report => Trends_Data,
               when History_Report => History_Data));
      Doc.Set_Root (Root);
      declare
         Settings : constant Jsonlib.Serializers.Options :=
           (Form => (if Pretty then Jsonlib.Serializers.Pretty else Jsonlib.Serializers.Compact), Indent => 2,
            Escape_Non_Ascii => False, Sort_Members => False);
         Text     : constant String := Jsonlib.Serializers.To_String (Doc, Settings) & Character'Val (10);
      begin
         if Text'Length > Maximum_Bytes then
            raise Report_Error with
              Ada_Quality_Summary.Text.Message
                ("error.json_size", [Ada_Quality_Summary.Text.Arg ("size", Long_Long_Integer (Text'Length)),
                                     Ada_Quality_Summary.Text.Arg ("limit", Long_Long_Integer (Maximum_Bytes))]);
         end if;
         return Text;
      end;
   end Render;
end Ada_Quality_Summary.JSON;
