with Ada.Strings.Unbounded;
with Ada_Quality.Indicators;
with Ada_Quality.Reporting;
with Ada_Quality.Types;
with Ada_Quality_Summary.Model;
with Ada_Quality_Summary.Text;
with Jsonlib.Serializers;

with Ada_Quality_Summary.JSON.Objects;

package body Ada_Quality_Summary.JSON is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Types;
   use Ada_Quality_Summary.Model;
   use Ada_Quality_Summary.Reports;
   use Ada_Quality_Summary.JSON.Objects;
   use Jsonlib.Documents;
   use type Ada_Quality.Reporting.Evidence_Format;

   --  The application whose database every report reads.
   Source_Application : constant String := "ada_quality";


   function Render
     (Item : Report; Pretty : Boolean := False; Maximum_Bytes : Positive := Default_Maximum_Bytes) return String
   is
      Doc : Document;

      --  Findings per indicator in registry order, shared by the summary and problems reports.
      function Groups_Array return Node is
         Groups : constant Node := Doc.New_Array;
      begin
         for Group of Item.Groups loop
            declare
               Object : constant Node := Doc.New_Object;
            begin
               Put (Doc, Object, "indicator_id", Str (Doc, Image (Group.Indicator)));
               Put (Doc, Object, "name", Str (Doc, Ada_Quality.Indicators.Registry (Group.Indicator).Name.all));
               Put (Doc, Object, "findings", Nat (Doc, Group.Findings));
               Put (Doc, Object, "projects", Nat (Doc, Group.Projects));
               Doc.Append (Groups, Object);
            end;
         end loop;
         return Groups;
      end Groups_Array;

      function Summary_Data return Node is
         Data    : constant Node := Doc.New_Object;
         Common  : constant Node := Doc.New_Array;
         Summary : constant Node := Doc.New_Object;
         Activity : constant Node := Doc.New_Object;
      begin
         Put (Doc, Data, "totals", Totals_Object (Doc, Item.Portfolio.Totals));
         Put (Doc, Data, "projects", Projects_Array (Doc, Item.Portfolio.Projects));
         for Indicator of Item.Common loop
            declare
               Object : constant Node := Doc.New_Object;
            begin
               Put (Doc, Object, "indicator_id", Str (Doc, Image (Indicator.Id)));
               Put (Doc, Object, "name", Str (Doc, Indicator.Name));
               Put (Doc, Object, "projects", Nat (Doc, Indicator.Totals.Violated));
               Doc.Append (Common, Object);
            end;
         end loop;
         Put (Doc, Data, "common_violations", Common);
         Put (Doc, Data, "findings_by_indicator", Groups_Array);
         Put (Doc, Summary, "projects_with_regressions", Nat (Doc, Item.Projects_Affected));
         Put (Doc, Summary, "regressions", Nat (Doc, Item.Regression_Total));
         Put (Doc, Summary, "by_kind", Kind_Counts_Object (Doc, Item.By_Kind));
         Put (Doc, Data, "regression_summary", Summary);
         Put (Doc, Activity, "newer_running", Nat (Doc, Item.Portfolio.Totals.Newer_Running));
         Put (Doc, Activity, "newer_unfinished", Nat (Doc, Item.Portfolio.Totals.Newer_Unfinished));
         Put (Doc, Data, "activity", Activity);
         return Data;
      end Summary_Data;

      function Projects_Data return Node is
         Data : constant Node := Doc.New_Object;
      begin
         Put (Doc, Data, "projects", Projects_Array (Doc, Item.Portfolio.Projects));
         Put (Doc, Data, "totals", Totals_Object (Doc, Item.Portfolio.Totals));
         return Data;
      end Projects_Data;

      function Project_Data return Node is
         Data       : constant Node := Doc.New_Object;
         Indicators : constant Node := Doc.New_Array;
      begin
         Put (Doc, Data, "project", Project_Object (Doc, Item.Project));
         if Item.Has_Assessment then
            declare
               Run        : constant Ada_Quality.Reporting.Run_Record := Item.Assessment.Run;
               Assessment : constant Node := Doc.New_Object;
            begin
               Put (Doc, Assessment, "run_id", Nat (Doc, Run.Id));
               Put_Provenance
                 (Doc, Assessment, Run.Source_Id, Run.Policy_Id, Run.Toolchain_Id, Run.Started_At, Run.Finished_At);
               Put (Doc, Assessment, "evidence_format",
                    Str (Doc, (if Run.Format = Ada_Quality.Reporting.Lossless_Evidence then "lossless" else "legacy")));
               Put (Doc, Assessment, "totals", Indicator_Totals_Object (Doc, Item.Project.Totals));
               Put (Doc, Data, "assessment", Assessment);
               for Result of Item.Assessment.Results loop
                  Doc.Append (Indicators, Result_Object (Doc, Item.Project.Project_Id, Run.Id, Result));
               end loop;
            end;
         else
            Put (Doc, Data, "assessment", Null_Value (Doc));
         end if;
         Put (Doc, Data, "indicators", Indicators);
         Put (Doc, Data, "findings", Findings_Array (Doc, Item.Findings));
         Put (Doc, Data, "regressions", Regressions_Array (Doc, Item.Regressions));
         Put (Doc, Data, "baseline", Baseline_Object (Doc, Item.Baselines.First_Element));
         return Data;
      end Project_Data;

      function Indicators_Data return Node is
         Data : constant Node := Doc.New_Object;
         List : constant Node := Doc.New_Array;
      begin
         for Indicator of Item.Indicators loop
            Doc.Append (List, Indicator_Summary_Object (Doc, Indicator));
         end loop;
         Put (Doc, Data, "indicators", List);
         Put (Doc, Data, "project_count", Nat (Doc, Item.Portfolio.Totals.Projects));
         return Data;
      end Indicators_Data;

      function Indicator_Data return Node is
         Data   : constant Node := Doc.New_Object;
         List   : constant Node := Doc.New_Array;
         Totals : constant Node := Doc.New_Object;
      begin
         Put (Doc, Data, "indicator", Indicator_Summary_Object (Doc, Item.Indicator));
         for Row of Item.Indicator_Rows loop
            declare
               Object : constant Node := Doc.New_Object;
            begin
               Put (Doc, Object, "project_id", Nat (Doc, Row.Project.Project_Id));
               Put (Doc, Object, "name", Str (Doc, Row.Project.Name));
               Put (Doc, Object, "path", Str (Doc, Row.Project.Project_Path));
               Put (Doc, Object, "state", Str (Doc, Image (Row.State)));
               Put (Doc, Object, "run_id", Id_Or_Null (Doc, Row.Project.Current_Run_Id));
               Put (Doc, Object, "result",
                    (if Row.Has_Result
                     then Result_Object (Doc, Row.Project.Project_Id, Row.Project.Current_Run_Id, Row.Result)
                     else Null_Value (Doc)));
               Doc.Append (List, Object);
            end;
         end loop;
         Put (Doc, Data, "projects", List);
         Put (Doc, Totals, "projects", Nat (Doc, Item.Portfolio.Totals.Projects));
         Put_Totals (Doc, Totals, Item.Indicator.Totals, With_Missing => True);
         Put (Doc, Data, "totals", Totals);
         return Data;
      end Indicator_Data;

      function Problems_Data return Node is
         Data     : constant Node := Doc.New_Object;
         Totals   : constant Node := Doc.New_Object;
         Severity_Object : constant Node := Doc.New_Object;
      begin
         Put (Doc, Data, "findings", Findings_Array (Doc, Item.Findings));
         Put (Doc, Data, "grouped_by_indicator", Groups_Array);
         Put (Doc, Totals, "findings", Nat (Doc, Item.Finding_Total));
         Put (Doc, Totals, "projects", Nat (Doc, Item.Finding_Projects));
         for Level in reverse Severity loop
            Put (Doc, Severity_Object, Image (Level), Nat (Doc, Item.By_Severity (Level)));
         end loop;
         Put (Doc, Totals, "by_severity", Severity_Object);
         Put (Doc, Data, "totals", Totals);
         return Data;
      end Problems_Data;

      function Waivers_Data return Node is
         Data    : constant Node := Doc.New_Object;
         Waivers : constant Node := Doc.New_Array;
         Groups  : constant Node := Doc.New_Array;
         Totals  : constant Node := Doc.New_Object;
      begin
         for Finding of Item.Waivers loop
            declare
               --  A waiver is its finding with the message split into target and justification.
               Object  : constant Node := Finding_Object (Doc, Finding);
               Message : constant String := To_String (Finding.Message);
            begin
               Put (Doc, Object, "target", Str (Doc, Waiver_Target (Message)));
               Put (Doc, Object, "justification", Str (Doc, Waiver_Justification (Message)));
               Doc.Append (Waivers, Object);
            end;
         end loop;
         Put (Doc, Data, "waivers", Waivers);
         for Group of Item.Waiver_Groups loop
            declare
               Object : constant Node := Doc.New_Object;
            begin
               Put (Doc, Object, "indicator_id", Str (Doc, Image (Group.Indicator)));
               Put (Doc, Object, "waivers", Nat (Doc, Group.Waivers));
               Put (Doc, Object, "projects", Nat (Doc, Group.Projects));
               Doc.Append (Groups, Object);
            end;
         end loop;
         Put (Doc, Data, "by_indicator", Groups);
         Put (Doc, Totals, "waivers", Nat (Doc, Item.Waiver_Total));
         Put (Doc, Totals, "projects", Nat (Doc, Item.Waiver_Projects));
         Put (Doc, Data, "totals", Totals);
         return Data;
      end Waivers_Data;

      function Compare_Data return Node is
         Data   : constant Node := Doc.New_Object;
         Totals : constant Node := Doc.New_Object;
      begin
         Put (Doc, Data, "project", Project_Object (Doc, Item.Project));
         Put (Doc, Data, "baseline", Run_Object (Doc, Item.Pair.Baseline));
         Put (Doc, Data, "current", Run_Object (Doc, Item.Pair.Current));
         Put (Doc, Data, "comparison", Str (Doc, Image (Item.Pair.Comparison)));
         Put (Doc, Data, "policy_changed", Bool (Doc, Item.Pair.Policy_Changed));
         Put (Doc, Data, "incompatibility",
              (if Item.Pair.Has_Reason then Str (Doc, Image (Item.Pair.Reason)) else Null_Value (Doc)));
         Put (Doc, Data, "regressions", Regressions_Array (Doc, Item.Regressions));
         Put (Doc, Totals, "regressions", Nat (Doc, Item.Regression_Total));
         Put (Doc, Totals, "by_kind", Kind_Counts_Object (Doc, Item.By_Kind));
         Put (Doc, Data, "totals", Totals);
         return Data;
      end Compare_Data;

      function Regressions_Data return Node is
         Data       : constant Node := Doc.New_Object;
         Exclusions : constant Node := Doc.New_Array;
         Totals     : constant Node := Doc.New_Object;
      begin
         Put (Doc, Data, "regressions", Regressions_Array (Doc, Item.Regressions));
         Put (Doc, Data, "projects_affected", Nat (Doc, Item.Projects_Affected));
         for Info of Item.Baselines loop
            Doc.Append (Exclusions, Baseline_Object (Doc, Info));
         end loop;
         Put (Doc, Data, "baseline_exclusions", Exclusions);
         Put (Doc, Totals, "regressions", Nat (Doc, Item.Regression_Total));
         Put (Doc, Totals, "by_kind", Kind_Counts_Object (Doc, Item.By_Kind));
         Put (Doc, Data, "totals", Totals);
         return Data;
      end Regressions_Data;

      function Trends_Data return Node is
         Data      : constant Node := Doc.New_Object;
         Series    : constant Node := Doc.New_Array;
         Snapshots : constant Node := Doc.New_Array;
         Meta      : constant Node := Doc.New_Object;
      begin
         for Trend of Item.Series loop
            declare
               Object : constant Node := Doc.New_Object;
               Points : constant Node := Doc.New_Array;
            begin
               Put (Doc, Object, "indicator_id", Str (Doc, Image (Trend.Indicator)));
               Put (Doc, Object, "name", Str (Doc, Ada_Quality.Indicators.Registry (Trend.Indicator).Name.all));
               Put (Doc, Object, "measurement_kind",
                    Str (Doc, (if Trend.Kind = Decimal_Value then "decimal" else "integer")));
               Put (Doc, Object, "unit", Str (Doc, Trend.Unit));
               for Point of Trend.Points loop
                  declare
                     P : constant Node := Doc.New_Object;
                  begin
                     Put (Doc, P, "project_id", Nat (Doc, Point.Project_Id));
                     Put (Doc, P, "run_id", Nat (Doc, Point.Run_Id));
                     Put (Doc, P, "value", Int (Doc, Point.Value));
                     Put (Doc, P, "observed_at", Time_Or_Null (Doc, Point.Observed));
                     Doc.Append (Points, P);
                  end;
               end loop;
               Put (Doc, Object, "points", Points);
               Put (Doc, Object, "projects_included", Nat (Doc, Trend.Projects_Included));
               Put (Doc, Object, "projects_excluded", Nat (Doc, Trend.Projects_Excluded));
               Put (Doc, Object, "excluded_observations", Nat (Doc, Trend.Excluded_Observations));
               Doc.Append (Series, Object);
            end;
         end loop;
         Put (Doc, Data, "series", Series);
         Put (Doc, Data, "excluded_observations", Nat (Doc, Item.Excluded_Observations));
         Put (Doc, Meta, "method", Str (Doc, "ada_quality.history.metric_trend"));
         Put (Doc, Meta, "reference", Str (Doc, "current_completed_assessment"));
         Put (Doc, Meta, "since", Date_Or_Null (Doc, Item.Since));
         Put (Doc, Meta, "until", Date_Or_Null (Doc, Item.Until_Date));
         Put (Doc, Meta, "undated_excluded", Nat (Doc, Item.Undated));
         Put (Doc, Data, "comparison_metadata", Meta);
         for Day of Item.Daily loop
            declare
               Object : constant Node := Doc.New_Object;
            begin
               Put (Doc, Object, "date", Str (Doc, Day.Day));
               Put (Doc, Object, "projects", Nat (Doc, Day.Totals.Projects));
               Put (Doc, Object, "passing", Nat (Doc, Day.Totals.Passing));
               Put (Doc, Object, "violations", Nat (Doc, Day.Totals.Violations));
               Put (Doc, Object, "incomplete", Nat (Doc, Day.Totals.Incomplete));
               Put (Doc, Object, "unassessed", Nat (Doc, Day.Totals.Unassessed));
               Put (Doc, Object, "indicator_violations", Nat (Doc, Day.Totals.Indicator_Violations));
               Put (Doc, Object, "unknown_results", Nat (Doc, Day.Totals.Unknown_Results));
               Doc.Append (Snapshots, Object);
            end;
         end loop;
         Put (Doc, Data, "snapshots", Snapshots);
         return Data;
      end Trends_Data;

      function History_Data return Node is
         Data : constant Node := Doc.New_Object;
         Runs : constant Node := Doc.New_Array;
      begin
         Put (Doc, Data, "project", Project_Object (Doc, Item.Project));
         for Run of Item.History loop
            Doc.Append (Runs, Run_Object (Doc, Run));
         end loop;
         Put (Doc, Data, "runs", Runs);
         Put (Doc, Data, "completed_count", Nat (Doc, Item.Completed_Count));
         Put (Doc, Data, "interrupted_count", Nat (Doc, Item.Interrupted_Count));
         Put (Doc, Data, "invalid_count", Nat (Doc, Item.Invalid_Count));
         Put (Doc, Data, "running_count", Nat (Doc, Item.Running_Count));
         Put (Doc, Data, "undated_excluded", Nat (Doc, Item.Undated));
         return Data;
      end History_Data;

      Root      : constant Node := Doc.New_Object;
      Source    : constant Node := Doc.New_Object;
      Selection : constant Node := Doc.New_Object;
   begin
      Put (Doc, Root, "schema_version", Nat (Doc, Item.Metadata.Format_Version));
      Put (Doc, Root, "report_type", Str (Doc, Image (Item.Metadata.Kind)));
      Put (Doc, Source, "application", Str (Doc, Source_Application));
      Put (Doc, Source, "database_schema_version", Nat (Doc, Item.Metadata.Source_Schema_Version));
      Put (Doc, Source, "snapshot", Str (Doc, Item.Metadata.Snapshot_Identity));
      Put (Doc, Root, "source", Source);
      Put (Doc, Selection, "include_removed", Bool (Doc, Item.Filter.Include_Removed));
      Put (Doc, Selection, "enabled_only", Bool (Doc, Item.Filter.Enabled_Only));
      Put (Doc, Selection, "project_id", Id_Or_Null (Doc, Item.Filter.Project_Id));
      Put (Doc, Selection, "status",
           (if Item.Filter.Has_Status then Str (Doc, Image (Item.Filter.Status)) else Null_Value (Doc)));
      Put (Doc, Selection, "limit", Id_Or_Null (Doc, Item.Limit));
      Put (Doc, Selection, "selected_projects", Nat (Doc, Item.Metadata.Selected_Projects));
      Put (Doc, Root, "selection", Selection);
      Put (Doc, Root, "data",
           (case Item.Metadata.Kind is
               when Summary_Report => Summary_Data,
               when Projects_Report => Projects_Data,
               when Project_Report => Project_Data,
               when Indicators_Report => Indicators_Data,
               when Indicator_Report => Indicator_Data,
               when Problems_Report => Problems_Data,
               when Waivers_Report => Waivers_Data,
               when Regressions_Report => Regressions_Data,
               when Compare_Report => Compare_Data,
               when Trends_Report => Trends_Data,
               when History_Report => History_Data));
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty, Maximum_Bytes);
   end Render;

   function Serialize
     (Doc : Jsonlib.Documents.Document; Pretty : Boolean; Maximum_Bytes : Positive) return String
   is
      Settings : constant Jsonlib.Serializers.Options :=
        (Form => (if Pretty then Jsonlib.Serializers.Pretty else Jsonlib.Serializers.Compact), Indent => 2,
         Escape_Non_Ascii => False, Sort_Members => False);
   begin
      return Ada_Quality_Summary.Text.Bounded
        (Jsonlib.Serializers.To_String (Doc, Settings) & Character'Val (10), Maximum_Bytes);
   end Serialize;
end Ada_Quality_Summary.JSON;
