with Ada_Quality.Indicators;

package body Ada_Quality_Summary.JSON.Objects is
   use Ada.Strings.Unbounded;

   function Int (Doc : in out Document; Value : Long_Long_Integer) return Node is (Doc.New_Integer (Value));
   function Nat (Doc : in out Document; Value : Natural) return Node is (Doc.New_Integer (Long_Long_Integer (Value)));
   function Str (Doc : in out Document; Value : String) return Node is (Doc.New_String (Value));
   function Str
     (Doc : in out Document; Value : Ada.Strings.Unbounded.Unbounded_String) return Node is
       (Doc.New_String (To_String (Value)));
   function Bool (Doc : in out Document; Value : Boolean) return Node is (Doc.New_Boolean (Value));
   function Null_Value (Doc : in out Document) return Node is (Doc.New_Null);

   --  Zero is the documented absent sentinel for optional identities.
   function Id_Or_Null
     (Doc : in out Document; Value : Natural) return Node is (if Value = 0 then Null_Value (Doc) else Nat (Doc, Value));

   function Time_Or_Null (Doc : in out Document; Value : Ada_Quality.Reporting.Optional_Timestamp) return Node is
     (if Value.Present then Str (Doc, Ada_Quality.Reporting.Image (Value)) else Null_Value (Doc));

   function Date_Or_Null (Doc : in out Document; Value : Criteria.Date_Bound) return Node is
     (if Value.Present then Str (Doc, Criteria.Day_Image (Value.Value)) else Null_Value (Doc));

   procedure Put (Doc : in out Document; Object : Node; Name : String; Value : Node) is
   begin
      Doc.Insert (Object, Name, Value);
   end Put;

   --  Indicator state counts into Object; Missing is reported only by cross-project aggregates.
   procedure Put_Totals (Doc : in out Document; Object : Node; Totals : Indicator_Totals; With_Missing : Boolean) is
   begin
      Put (Doc, Object, "passed", Nat (Doc, Totals.Passed));
      Put (Doc, Object, "violated", Nat (Doc, Totals.Violated));
      Put (Doc, Object, "unknown", Nat (Doc, Totals.Unknown_Count));
      Put (Doc, Object, "not_applicable", Nat (Doc, Totals.Not_Applicable));
      if With_Missing then
         Put (Doc, Object, "missing", Nat (Doc, Totals.Missing));
      end if;
   end Put_Totals;

   function Indicator_Totals_Object (Doc : in out Document; Totals : Indicator_Totals) return Node is
      Object : constant Node := Doc.New_Object;
   begin
      Put_Totals (Doc, Object, Totals, With_Missing => False);
      return Object;
   end Indicator_Totals_Object;

   --  Provenance of one assessment, shared by the project assessment and history runs.
   procedure Put_Provenance
     (Doc : in out Document; Object : Node; Source, Policy, Toolchain : Ada.Strings.Unbounded.Unbounded_String;
                             Started_At, Finished_At : Ada_Quality.Reporting.Optional_Timestamp) is
   begin
      Put (Doc, Object, "source_fingerprint", Str (Doc, Source));
      Put (Doc, Object, "policy_fingerprint", Str (Doc, Policy));
      Put (Doc, Object, "toolchain_fingerprint", Str (Doc, Toolchain));
      Put (Doc, Object, "started_at", Time_Or_Null (Doc, Started_At));
      Put (Doc, Object, "finished_at", Time_Or_Null (Doc, Finished_At));
   end Put_Provenance;

   function Project_Object (Doc : in out Document; Project : Project_Summary) return Node is
      Object : constant Node := Doc.New_Object;
   begin
      Put (Doc, Object, "project_id", Nat (Doc, Project.Project_Id));
      Put (Doc, Object, "name", Str (Doc, Project.Name));
      Put (Doc, Object, "path", Str (Doc, Project.Project_Path));
      Put (Doc, Object, "enabled", Bool (Doc, Project.Enabled));
      Put (Doc, Object, "removed", Bool (Doc, Project.Removed));
      Put (Doc, Object, "quality", Str (Doc, Image (Project.Quality)));
      Put (Doc, Object, "current_run_id", Id_Or_Null (Doc, Project.Current_Run_Id));
      Put (Doc, Object, "latest_run_id", Id_Or_Null (Doc, Project.Latest_Run_Id));
      Put (Doc, Object, "newer_run", Str (Doc, Image (Project.Newer_Run)));
      --  Unassessed projects have no indicator states at all; they are not reported as unknown.
      Put (Doc, Object, "indicators",
           (if Project.Current_Run_Id = 0 then Null_Value (Doc) else Indicator_Totals_Object (Doc, Project.Totals)));
      Put (Doc, Object, "finding_count", Nat (Doc, Project.Finding_Count));
      Put (Doc, Object, "regression_count", Nat (Doc, Project.Regression_Count));
      return Object;
   end Project_Object;

   function Projects_Array (Doc : in out Document; Projects : Model.Project_Vectors.Vector) return Node is
      List : constant Node := Doc.New_Array;
   begin
      for Project of Projects loop
         Doc.Append (List, Project_Object (Doc, Project));
      end loop;
      return List;
   end Projects_Array;

   function Totals_Object (Doc : in out Document; Totals : Portfolio_Totals) return Node is
      Object : constant Node := Doc.New_Object;
   begin
      Put (Doc, Object, "projects", Nat (Doc, Totals.Projects));
      Put (Doc, Object, "passing", Nat (Doc, Totals.Passing));
      Put (Doc, Object, "violations", Nat (Doc, Totals.Violations));
      Put (Doc, Object, "incomplete", Nat (Doc, Totals.Incomplete));
      Put (Doc, Object, "unassessed", Nat (Doc, Totals.Unassessed));
      Put (Doc, Object, "enabled", Nat (Doc, Totals.Enabled));
      Put (Doc, Object, "disabled", Nat (Doc, Totals.Disabled));
      Put (Doc, Object, "findings", Nat (Doc, Totals.Findings));
      Put (Doc, Object, "indicator_violations", Nat (Doc, Totals.Indicator_Violations));
      Put (Doc, Object, "unknown_results", Nat (Doc, Totals.Unknown_Results));
      Put (Doc, Object, "newer_running", Nat (Doc, Totals.Newer_Running));
      Put (Doc, Object, "newer_unfinished", Nat (Doc, Totals.Newer_Unfinished));
      Put (Doc, Object, "projects_with_regressions", Nat (Doc, Totals.With_Regressions));
      return Object;
   end Totals_Object;

   function Indicator_Summary_Object (Doc : in out Document; Indicator : Indicator_Summary) return Node is
      Object : constant Node := Doc.New_Object;
   begin
      Put (Doc, Object, "id", Str (Doc, Image (Indicator.Id)));
      Put (Doc, Object, "name", Str (Doc, Indicator.Name));
      Put (Doc, Object, "category", Str (Doc, Image (Indicator.Category)));
      Put (Doc, Object, "version", Nat (Doc, Indicator.Version));
      Put_Totals (Doc, Object, Indicator.Totals, With_Missing => True);
      Put (Doc, Object, "affected_projects", Nat (Doc, Indicator.Totals.Violated));
      return Object;
   end Indicator_Summary_Object;

   function Measurement_Object (Doc : in out Document; Id : Indicator_Id; Value : Measurement_Value) return Node is
      Object : constant Node := Doc.New_Object;
   begin
      case Value.Kind is
         when Unavailable_Value =>
            Put (Doc, Object, "kind", Str (Doc, "unavailable"));
            Put (Doc, Object, "reason", Str (Doc, Value.Reason));
         when Boolean_Value =>
            Put (Doc, Object, "kind", Str (Doc, "boolean"));
            Put (Doc, Object, "value", Bool (Doc, Value.Boolean_Data));
         when Integer_Value =>
            Put (Doc, Object, "kind", Str (Doc, "integer"));
            Put (Doc, Object, "value", Int (Doc, Value.Integer_Data));
            Put (Doc, Object, "unit", Str (Doc, Ada_Quality.Indicators.Measurement_Unit (Id)));
         when Decimal_Value =>
            Put (Doc, Object, "kind", Str (Doc, "decimal"));
            Put (Doc, Object, "basis_points", Int (Doc, Value.Basis_Points));
         when Text_Value =>
            Put (Doc, Object, "kind", Str (Doc, "text"));
            Put (Doc, Object, "value", Str (Doc, Value.Text_Data));
         when Enum_Value =>
            Put (Doc, Object, "kind", Str (Doc, "enum"));
            Put (Doc, Object, "value", Str (Doc, Value.Text_Data));
      end case;
      return Object;
   end Measurement_Object;

   function Finding_Object (Doc : in out Document; Finding : Finding_Summary) return Node is
      Object : constant Node := Doc.New_Object;
   begin
      Put (Doc, Object, "project_id", Nat (Doc, Finding.Project_Id));
      Put (Doc, Object, "run_id", Nat (Doc, Finding.Run_Id));
      Put (Doc, Object, "indicator_id", Str (Doc, Image (Finding.Indicator)));
      Put (Doc, Object, "rule", Str (Doc, Finding.Rule));
      Put (Doc, Object, "severity", Str (Doc, Image (Finding.Level)));
      Put (Doc, Object, "message", Str (Doc, Finding.Message));
      Put (Doc, Object, "relative_path",
           (if Length (Finding.Path) = 0 then Null_Value (Doc) else Str (Doc, Finding.Path)));
      Put (Doc, Object, "line", (if Finding.Line = 0 then Null_Value (Doc) else Nat (Doc, Finding.Line)));
      Put (Doc, Object, "fingerprint", Str (Doc, Finding.Fingerprint));
      return Object;
   end Finding_Object;

   function Findings_Array (Doc : in out Document; Findings : Finding_Summary_Vectors.Vector) return Node is
      List : constant Node := Doc.New_Array;
   begin
      for Finding of Findings loop
         Doc.Append (List, Finding_Object (Doc, Finding));
      end loop;
      return List;
   end Findings_Array;

   function Result_Object
     (Doc : in out Document; Project_Id, Run_Id : Positive; Result : Indicator_Result) return Node is
      Object     : constant Node := Doc.New_Object;
      Descriptor : constant Ada_Quality.Indicators.Indicator_Descriptor :=
        Ada_Quality.Indicators.Registry (Result.Indicator);
      Findings   : constant Node := Doc.New_Array;
   begin
      Put (Doc, Object, "id", Str (Doc, Image (Result.Indicator)));
      Put (Doc, Object, "name", Str (Doc, Descriptor.Name.all));
      Put (Doc, Object, "category", Str (Doc, Image (Descriptor.Category)));
      Put (Doc, Object, "version", Nat (Doc, Descriptor.Version));
      Put (Doc, Object, "execution", Str (Doc, Image (Result.Execution)));
      Put (Doc, Object, "compliance", Str (Doc, Image (Result.Compliance)));
      Put (Doc, Object, "applicable", Bool (Doc, Result.Applicable));
      Put (Doc, Object, "summary", Str (Doc, Result.Summary));
      Put (Doc, Object, "evidence", Str (Doc, Result.Evidence));
      Put (Doc, Object, "measurement", Measurement_Object (Doc, Result.Indicator, Result.Measurement));
      for F of Result.Findings loop
         Doc.Append (Findings, Finding_Object (Doc, Summary_Of (Project_Id, Run_Id, F)));
      end loop;
      Put (Doc, Object, "findings", Findings);
      return Object;
   end Result_Object;

   function Kind_Counts_Object (Doc : in out Document; Counts : Ada_Quality_Summary.Reports.Kind_Counts) return Node is
      Object : constant Node := Doc.New_Object;
   begin
      for Kind in Counts'Range loop
         Put (Doc, Object, Image (Kind), Nat (Doc, Counts (Kind)));
      end loop;
      return Object;
   end Kind_Counts_Object;

   function Regression_Object (Doc : in out Document; Change : Regression_Summary) return Node is
      Object : constant Node := Doc.New_Object;
   begin
      Put (Doc, Object, "project_id", Nat (Doc, Change.Project_Id));
      Put (Doc, Object, "current_run_id", Nat (Doc, Change.Current_Run_Id));
      Put (Doc, Object, "baseline_run_id", Nat (Doc, Change.Baseline_Run_Id));
      Put (Doc, Object, "indicator_id", Str (Doc, Image (Change.Indicator)));
      Put (Doc, Object, "kind", Str (Doc, Image (Change.Kind)));
      Put (Doc, Object, "before", Str (Doc, Change.Before));
      Put (Doc, Object, "after", Str (Doc, Change.After));
      return Object;
   end Regression_Object;

   function Regressions_Array (Doc : in out Document; Changes : Regression_Summary_Vectors.Vector) return Node is
      List : constant Node := Doc.New_Array;
   begin
      for Change of Changes loop
         Doc.Append (List, Regression_Object (Doc, Change));
      end loop;
      return List;
   end Regressions_Array;

   function Baseline_Object (Doc : in out Document; Info : Baseline_Info) return Node is
      Object   : constant Node := Doc.New_Object;
      Excluded : constant Node := Doc.New_Array;
   begin
      Put (Doc, Object, "project_id", Nat (Doc, Info.Project_Id));
      Put (Doc, Object, "status", Str (Doc, Image (Info.Status)));
      Put (Doc, Object, "current_run_id", Id_Or_Null (Doc, Info.Current_Run_Id));
      Put (Doc, Object, "baseline_run_id", Id_Or_Null (Doc, Info.Baseline_Run_Id));
      Put (Doc, Object, "comparison", Str (Doc, Image (Info.Comparison)));
      Put (Doc, Object, "policy_changed", Bool (Doc, Info.Policy_Changed));
      for Run of Info.Excluded loop
         declare
            Entry_Object : constant Node := Doc.New_Object;
         begin
            Put (Doc, Entry_Object, "run_id", Nat (Doc, Run.Run_Id));
            Put (Doc, Entry_Object, "reason", Str (Doc, Image (Run.Reason)));
            Doc.Append (Excluded, Entry_Object);
         end;
      end loop;
      Put (Doc, Object, "excluded_runs", Excluded);
      return Object;
   end Baseline_Object;

   function Run_Object (Doc : in out Document; Run : History_Summary) return Node is
      Object : constant Node := Doc.New_Object;
   begin
      Put (Doc, Object, "run_id", Nat (Doc, Run.Run_Id));
      Put (Doc, Object, "state", Str (Doc, Image (Run.State)));
      Put_Provenance (Doc, Object, Run.Source_Id, Run.Policy_Id, Run.Toolchain_Id, Run.Started_At, Run.Finished_At);
      Put (Doc, Object, "quality", (if Run.Has_Quality then Str (Doc, Image (Run.Quality)) else Null_Value (Doc)));
      return Object;
   end Run_Object;
end Ada_Quality_Summary.JSON.Objects;
