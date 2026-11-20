with Ada.Strings.Unbounded;
with Ada_Quality.Types;
with Ada_Quality_Summary.Aggregation;
with Ada_Quality_Summary.Criteria;
with Ada_Quality_Summary.Filtering;
with Ada_Quality_Summary.Text;
with Ada_Quality_Summary.Trends;

package body Ada_Quality_Summary.Reports.Assembly is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Types;
   use Ada_Quality_Summary.Aggregation;
   use Ada_Quality_Summary.Criteria;
   use Ada_Quality_Summary.Model;
   use Ada_Quality_Summary.Options;

   package Projects_Limit is new Filtering.Limiting (Project_Summary, Model.Project_Vectors);
   package Indicators_Limit is new Filtering.Limiting (Indicator_Summary, Indicator_Summary_Vectors);
   package Findings_Limit is new Filtering.Limiting (Finding_Summary, Finding_Summary_Vectors);
   package Regressions_Limit is new Filtering.Limiting (Regression_Summary, Regression_Summary_Vectors);
   package History_Limit is new Filtering.Limiting (History_Summary, History_Summary_Vectors);
   package Points_Limit is new Filtering.Limiting (Trend_Point, Trend_Point_Vectors);
   package Indicator_Rows_Limit is new Filtering.Limiting (Indicator_Row, Indicator_Row_Vectors);

   procedure Add_Regressions (Item : in out Report; Compared : Comparison) is
   begin
      Item.Baselines.Append (Compared.Baseline);
      if not Compared.Changes.Is_Empty then
         Item.Projects_Affected := Item.Projects_Affected + 1;
      end if;
      for Change of Compared.Changes loop
         Item.By_Kind (Change.Kind) := Item.By_Kind (Change.Kind) + 1;
         Item.Regressions.Append (Change);
      end loop;
      Item.Regression_Total := Natural (Item.Regressions.Length);
   end Add_Regressions;

   --  Count the findings of the current assessments of Projects, per severity and per indicator, from the facts
   --  derived once per assessment; the finding rows themselves are not needed.
   procedure Count_Findings (Item : in out Report; Data : Repository.Snapshot; Projects : Project_Vectors.Vector) is
      Findings : Repository.Indicator_Counts := [others => 0];
      Affected : Repository.Indicator_Counts := [others => 0];
   begin
      for Row of Projects loop
         if Row.Current_Run_Id /= 0 then
            declare
               Facts : constant Repository.Run_Facts := Repository.Facts (Data, Row.Current_Run_Id);
            begin
               Item.Finding_Total := Item.Finding_Total + Facts.Findings;
               if Facts.Findings > 0 then
                  Item.Finding_Projects := Item.Finding_Projects + 1;
               end if;
               for Level in Severity loop
                  Item.By_Severity (Level) := Item.By_Severity (Level) + Facts.By_Severity (Level);
               end loop;
               for Id in Indicator_Id loop
                  if Facts.Findings_By_Indicator (Id) > 0 then
                     Findings (Id) := Findings (Id) + Facts.Findings_By_Indicator (Id);
                     Affected (Id) := Affected (Id) + 1;
                  end if;
               end loop;
            end;
         end if;
      end loop;
      for Id in Indicator_Id loop
         if Findings (Id) > 0 then
            Item.Groups.Append (Finding_Group'(Indicator => Id, Findings => Findings (Id), Projects => Affected (Id)));
         end if;
      end loop;
   end Count_Findings;

   procedure Start
     (Data           : Repository.Snapshot;
      Invocation     : Options.Options;
      Database_Label : String;
      State          : in out Context)
   is
      Item : Report renames State.Item;
   begin
      Item.Metadata :=
        (Format_Version => Report_Format_Version, Source_Schema_Version => Repository.Schema_Version (Data),
         Selected_Projects => 0, Snapshot_Identity => To_Unbounded_String (Repository.Identity (Data)),
         Kind => Report_Of (Invocation.Command));
      Item.Database_Label := To_Unbounded_String (Database_Label);
      Item.Limit := Invocation.Limit;
      Item.Since := Invocation.Since;
      Item.Until_Date := Invocation.Until_Date;
      Item.Filter :=
        (Include_Removed => Invocation.Include_Removed, Enabled_Only => Invocation.Enabled_Only, Project_Id => 0,
         Has_Status => Invocation.Has_Status, Status => Invocation.Status);
      if Invocation.Has_Project then
         Item.Filter.Project_Id :=
           Filtering.Resolve_Project (Data, To_String (Invocation.Project), Invocation.Include_Removed);
      end if;
   end Start;

   procedure Summarize_Population (State : in out Context) is
   begin
      State.Item.Metadata.Selected_Projects := Natural (State.Selected.Length);
      State.Item.Portfolio := Build_Portfolio (State.Selected);
      State.Item.Row_Count := Natural (State.Selected.Length);
   end Summarize_Population;

   --  Select the reported projects: the target of a detail command, or the filtered population.
   procedure Select_Projects (Data : Repository.Snapshot; Invocation : Options.Options; State : in out Context) is
      Item     : Report renames State.Item;
      Selected : Project_Vectors.Vector renames State.Selected;
   begin
      if Invocation.Command in Project_Command | History_Command then
         declare
            Id : constant Positive :=
              Filtering.Resolve_Project (Data, To_String (Invocation.Target_Project), Invocation.Include_Removed);
         begin
            Item.Filter.Project_Id := Id;
            Item.Project := Build_Project (Data, Repository.Project (Data, Id));
            Selected.Append (Item.Project);
         end;
      elsif Invocation.Command = Compare_Command then
         Trends.Compare_Pair
           (Data, Repository.Resolve_Run (Data, To_String (Invocation.Baseline_Run)),
            Repository.Resolve_Run (Data, To_String (Invocation.Current_Run)), Item.Pair, Item.Regressions);
         Item.Filter.Project_Id := Item.Pair.Project_Id;
         Item.Project := Build_Project (Data, Repository.Project (Data, Item.Pair.Project_Id));
         --  A tombstoned project's runs are compared only on request, as its name resolves only on request.
         if Item.Project.Removed and then not Invocation.Include_Removed then
            raise Argument_Error with
              Text.Message ("error.compare_removed", [Text.Arg ("project", To_String (Item.Project.Name))]);
         end if;
         Selected.Append (Item.Project);
      else
         for Row of Build_Projects (Data, Filtering.Population (Data, Item.Filter)) loop
            if not Item.Filter.Has_Status or else Row.Quality = Item.Filter.Status then
               Selected.Append (Row);
            end if;
         end loop;
      end if;
   end Select_Projects;

   --  Compare each selected project with its baseline once, for the reports that show regressions or their counts.
   procedure Compare_Selected (Data : Repository.Snapshot; Invocation : Options.Options; State : in out Context) is
      Item     : Report renames State.Item;
      Selected : Project_Vectors.Vector renames State.Selected;
      Compared : Comparison_Maps.Map renames State.Compared;
   begin
      if Invocation.Command = Compare_Command or else
        (Invocation.Command not in Summary_Command | Projects_Command | Project_Command | History_Command |
                                   Regressions_Command
         and then not Invocation.Fail_On (Gate_Regressions))
      then
         return;
      end if;
      for Row of Selected loop
         declare
            Result : Comparison;
         begin
            Trends.Regressions (Data, Row.Project_Id, Result.Baseline, Result.Changes);
            Row.Regression_Count := Natural (Result.Changes.Length);
            Compared.Insert (Row.Project_Id, Result);
         end;
      end loop;
      if Invocation.Command in Project_Command | History_Command then
         Item.Project.Regression_Count := Selected.First_Element.Regression_Count;
      end if;
   end Compare_Selected;

   --  Summary and projects: sorted, limited rows; the summary adds indicators, finding counts, and regressions.
   procedure Fill_Overview (Data : Repository.Snapshot; Invocation : Options.Options; State : in out Context) is
      Item     : Report renames State.Item;
      Selected : Project_Vectors.Vector renames State.Selected;
      Compared : Comparison_Maps.Map renames State.Compared;
   begin
      Filtering.Sort_Projects
        (Item.Portfolio.Projects, Invocation.Sort, Invocation.Command = Summary_Command,
         Invocation.Reverse_Order);
      Projects_Limit.Limit (Item.Portfolio.Projects, Invocation.Limit);
      if Invocation.Command = Summary_Command then
         for Indicator of Build_Indicators (Data, Selected) loop
            if Indicator.Totals.Violated > 0 then
               Item.Common.Append (Indicator);
            end if;
         end loop;
         Filtering.Sort_Common (Item.Common);
         Count_Findings (Item, Data, Selected);
         for Row of Selected loop
            Add_Regressions (Item, Compared (Row.Project_Id));
         end loop;
      end if;
   end Fill_Overview;

   --  Project: the current assessment, its findings, and its regressions.
   procedure Fill_Project (Data : Repository.Snapshot; Invocation : Options.Options; State : in out Context) is
      Item     : Report renames State.Item;
      Selected : Project_Vectors.Vector renames State.Selected;
      Compared : Comparison_Maps.Map renames State.Compared;
   begin
      if Item.Project.Current_Run_Id /= 0 then
         Item.Has_Assessment := True;
         Item.Assessment := Repository.Assessment (Data, Item.Project.Current_Run_Id);
         Item.Findings := Aggregation.Findings_Of (Item.Project.Project_Id, Item.Assessment);
         Count_Findings (Item, Data, Selected);
         Filtering.Sort_Findings (Item.Findings, Default_Sort, False);
         Findings_Limit.Limit (Item.Findings, Invocation.Limit);
         Filtering.Sort_Results (Item.Assessment.Results, Invocation.Sort, Invocation.Reverse_Order);
      end if;
      Add_Regressions (Item, Compared (Item.Project.Project_Id));
      Filtering.Sort_Regressions (Item.Regressions, Default_Sort, False);
   end Fill_Project;

   --  Indicators: one aggregate per indicator.
   procedure Fill_Indicators (Data : Repository.Snapshot; Invocation : Options.Options; State : in out Context) is
      Item     : Report renames State.Item;
      Selected : Project_Vectors.Vector renames State.Selected;
   begin
      Item.Indicators := Build_Indicators (Data, Selected);
      Filtering.Sort_Indicators (Item.Indicators, Invocation.Sort, Invocation.Reverse_Order);
      Item.Row_Count := Natural (Item.Indicators.Length);
      Indicators_Limit.Limit (Item.Indicators, Invocation.Limit);
   end Fill_Indicators;

   --  Indicator: the aggregate and one row per selected project.
   procedure Fill_Indicator (Data : Repository.Snapshot; Invocation : Options.Options; State : in out Context) is
      Item     : Report renames State.Item;
      Selected : Project_Vectors.Vector renames State.Selected;
      Id : constant Indicator_Id := Filtering.Resolve_Indicator (To_String (Invocation.Indicator));
   begin
      Item.Indicator := Build_Indicator (Data, Selected, Id);
      for Row of Selected loop
         declare
            Line : Indicator_Row := (Project => Row, State => State_Of (Data, Row, Id), others => <>);
         begin
            if Row.Current_Run_Id /= 0 then
               Line.Has_Result := True;
               Line.Result := Repository.Result_Of (Data, Row.Current_Run_Id, Id);
            end if;
            Item.Indicator_Rows.Append (Line);
         end;
      end loop;
      Filtering.Sort_Indicator_Rows (Item.Indicator_Rows, Invocation.Sort, Invocation.Reverse_Order);
      Indicator_Rows_Limit.Limit (Item.Indicator_Rows, Invocation.Limit);
   end Fill_Indicator;

   --  Problems: every finding of the selected current assessments.
   procedure Fill_Problems (Data : Repository.Snapshot; Invocation : Options.Options; State : in out Context) is
      Item     : Report renames State.Item;
      Selected : Project_Vectors.Vector renames State.Selected;
   begin
      Item.Findings := Build_Findings (Data, Selected);
      Count_Findings (Item, Data, Selected);
      Filtering.Sort_Findings (Item.Findings, Invocation.Sort, Invocation.Reverse_Order);
      Item.Row_Count := Item.Finding_Total;
      Findings_Limit.Limit (Item.Findings, Invocation.Limit);
   end Fill_Problems;

   --  Regressions: every regression of the selected projects.
   procedure Fill_Regressions (Invocation : Options.Options; State : in out Context) is
      Item     : Report renames State.Item;
      Selected : Project_Vectors.Vector renames State.Selected;
      Compared : Comparison_Maps.Map renames State.Compared;
   begin
      for Row of Selected loop
         Add_Regressions (Item, Compared (Row.Project_Id));
      end loop;
      Filtering.Sort_Regressions (Item.Regressions, Invocation.Sort, Invocation.Reverse_Order);
      Item.Row_Count := Item.Regression_Total;
      Regressions_Limit.Limit (Item.Regressions, Invocation.Limit);
   end Fill_Regressions;

   --  Waivers: the review-waiver findings of the selected current assessments.
   procedure Fill_Waivers (Data : Repository.Snapshot; Invocation : Options.Options; State : in out Context) is
      Item     : Report renames State.Item;
      Selected : Project_Vectors.Vector renames State.Selected;
      Counts : Repository.Indicator_Counts := [others => 0];
      Owners : Repository.Indicator_Counts := [others => 0];

      --  Add the waivers of one project's current assessment.
      procedure Add_Project (Row : Project_Summary) is
         Seen : Repository.Indicator_Counts := [others => 0];

         --  Only the waiver findings become report rows.
         procedure Collect (Value : Ada_Quality.Reporting.Assessment_Record) is
         begin
            for Result of Value.Results loop
               for Finding of Result.Findings loop
                  if To_String (Finding.Rule) = Waiver_Rule then
                     Item.Waivers.Append (Summary_Of (Row.Project_Id, Row.Current_Run_Id, Finding));
                     Seen (Finding.Indicator) := Seen (Finding.Indicator) + 1;
                  end if;
               end loop;
            end loop;
         end Collect;
      begin
         Repository.Visit_Assessment (Data, Row.Current_Run_Id, Collect'Access);
         for Id in Indicator_Id loop
            Counts (Id) := Counts (Id) + Seen (Id);
            Owners (Id) := Owners (Id) + Natural'Min (1, Seen (Id));
         end loop;
         if (for some Count of Seen => Count > 0) then
            Item.Waiver_Projects := Item.Waiver_Projects + 1;
         end if;
      end Add_Project;
   begin
      for Row of Selected loop
         if Row.Current_Run_Id /= 0 then
            Add_Project (Row);
         end if;
      end loop;
      for Id in Indicator_Id loop
         if Counts (Id) > 0 then
            Item.Waiver_Groups.Append
              (Waiver_Group'(Indicator => Id, Waivers => Counts (Id), Projects => Owners (Id)));
         end if;
      end loop;
      Item.Waiver_Total := Natural (Item.Waivers.Length);
      Filtering.Sort_Findings (Item.Waivers, Invocation.Sort, Invocation.Reverse_Order);
      Item.Row_Count := Item.Waiver_Total;
      Findings_Limit.Limit (Item.Waivers, Invocation.Limit);
   end Fill_Waivers;

   --  Compare: the regressions between the two chosen assessments, already classified by Select_Projects.
   procedure Fill_Compare (Invocation : Options.Options; State : in out Context) is
      Item     : Report renames State.Item;
   begin
      for Change of Item.Regressions loop
         Item.By_Kind (Change.Kind) := Item.By_Kind (Change.Kind) + 1;
      end loop;
      Item.Regression_Total := Natural (Item.Regressions.Length);
      Item.Projects_Affected := (if Item.Regression_Total > 0 then 1 else 0);
      Filtering.Sort_Regressions (Item.Regressions, Invocation.Sort, Invocation.Reverse_Order);
      Item.Row_Count := Item.Regression_Total;
      Regressions_Limit.Limit (Item.Regressions, Invocation.Limit);
   end Fill_Compare;

   --  Trends: numeric series, undated runs, and daily snapshots.
   procedure Fill_Trends (Data : Repository.Snapshot; Invocation : Options.Options; State : in out Context) is
      Item     : Report renames State.Item;
      Selected : Project_Vectors.Vector renames State.Selected;
   begin
      Item.Series := Trends.Metric_Series (Data, Selected, Invocation.Since, Invocation.Until_Date);
      for Series of Item.Series loop
         Filtering.Sort_Points (Series.Points, Invocation.Sort, Invocation.Reverse_Order);
         Points_Limit.Limit (Series.Points, Invocation.Limit);
         Item.Excluded_Observations := Item.Excluded_Observations + Series.Excluded_Observations;
      end loop;
      Item.Undated := Trends.Undated_Runs (Data, Selected, Invocation.Since, Invocation.Until_Date);
      Item.Daily := Trends.Daily_States (Data, Selected, Invocation.Since, Invocation.Until_Date);
   end Fill_Trends;

   --  History: a project's runs and their lifecycle counts.
   procedure Fill_History (Data : Repository.Snapshot; Invocation : Options.Options; State : in out Context) is
      Item     : Report renames State.Item;
   begin
      Item.History :=
        Trends.History (Data, Item.Project.Project_Id, Invocation.Since, Invocation.Until_Date, Item.Undated);
      for Run of Item.History loop
         case Run.State is
            when Assessment_Completed => Item.Completed_Count := Item.Completed_Count + 1;
            when Assessment_Running => Item.Running_Count := Item.Running_Count + 1;
            when Assessment_Interrupted => Item.Interrupted_Count := Item.Interrupted_Count + 1;
            when Assessment_Invalid => Item.Invalid_Count := Item.Invalid_Count + 1;
         end case;
      end loop;
      Filtering.Sort_History (Item.History, Invocation.Reverse_Order);
      Item.Row_Count := Natural (Item.History.Length);
      History_Limit.Limit (Item.History, Invocation.Limit);
   end Fill_History;

   --  How often each --fail-on condition holds in the report.
   procedure Count_Gate (Invocation : Options.Options; State : in out Context) is
      Item     : Report renames State.Item;
      Compared : Comparison_Maps.Map renames State.Compared;
   begin
      if Invocation.Command = Compare_Command then
         declare
            Current : constant History_Summary := Item.Pair.Current;
         begin
            Item.Gate :=
              [Gate_Regressions => Item.Regression_Total,
               Gate_Violations  => (if Current.Has_Quality and then Current.Quality = Violations then 1 else 0),
               Gate_Incomplete  => (if not Current.Has_Quality or else Current.Quality = Incomplete then 1 else 0),
               Gate_Unassessed  => 0];
         end;
         return;
      end if;
      for Compared_Project of Compared loop
         Item.Gate (Gate_Regressions) := Item.Gate (Gate_Regressions) + Natural (Compared_Project.Changes.Length);
      end loop;
      Item.Gate (Gate_Violations) := Item.Portfolio.Totals.Violations;
      Item.Gate (Gate_Incomplete) := Item.Portfolio.Totals.Incomplete;
      Item.Gate (Gate_Unassessed) := Item.Portfolio.Totals.Unassessed;
   end Count_Gate;

   procedure Fill_Command (Data : Repository.Snapshot; Invocation : Options.Options; State : in out Context) is
   begin
      case Invocation.Command is
         when Summary_Command | Projects_Command => Fill_Overview (Data, Invocation, State);
         when Project_Command => Fill_Project (Data, Invocation, State);
         when Indicators_Command => Fill_Indicators (Data, Invocation, State);
         when Indicator_Command => Fill_Indicator (Data, Invocation, State);
         when Problems_Command => Fill_Problems (Data, Invocation, State);
         when Waivers_Command => Fill_Waivers (Data, Invocation, State);
         when Regressions_Command => Fill_Regressions (Invocation, State);
         when Compare_Command => Fill_Compare (Invocation, State);
         when Trends_Command => Fill_Trends (Data, Invocation, State);
         when History_Command => Fill_History (Data, Invocation, State);
         when Help_Command | Completion_Command | Version_Command =>
            raise Report_Error with "command does not produce a report";
      end case;
   end Fill_Command;
end Ada_Quality_Summary.Reports.Assembly;
