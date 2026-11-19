with Ada.Containers.Ordered_Maps;
with Ada.Strings.Unbounded;
with Ada_Quality.Indicators;
with Ada_Quality_Summary.Aggregation;
with Ada_Quality_Summary.Text;
with Ada_Quality_Summary.Trends;

package body Ada_Quality_Summary.Reports is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Types;
   use Ada_Quality_Summary.Aggregation;
   use Ada_Quality_Summary.Criteria;
   use Ada_Quality_Summary.Model;
   use Ada_Quality_Summary.Options;

   package Repository renames Ada_Quality_Summary.Repository;

   package Projects_Limit is new Filtering.Limiting (Project_Summary, Model.Project_Vectors);
   package Indicators_Limit is new Filtering.Limiting (Indicator_Summary, Indicator_Summary_Vectors);
   package Findings_Limit is new Filtering.Limiting (Finding_Summary, Finding_Summary_Vectors);
   package Regressions_Limit is new Filtering.Limiting (Regression_Summary, Regression_Summary_Vectors);
   package History_Limit is new Filtering.Limiting (History_Summary, History_Summary_Vectors);
   package Points_Limit is new Filtering.Limiting (Trend_Point, Trend_Point_Vectors);
   package Indicator_Rows_Limit is new Filtering.Limiting (Indicator_Row, Indicator_Row_Vectors);

   --  One project's baseline comparison, made at most once per report.
   type Comparison is record
      Baseline : Baseline_Info;
      Changes  : Regression_Summary_Vectors.Vector;
   end record;

   package Comparison_Maps is new Ada.Containers.Ordered_Maps (Positive, Comparison);

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

   function Build
     (Data : Repository.Snapshot; Invocation : Options.Options; Database_Label : String) return Report
   is
      Item       : Report;
      Selected   : Project_Vectors.Vector;
      Compared   : Comparison_Maps.Map;

      --  Select the reported projects: the target of a detail command, or the filtered population.
      procedure Select_Projects is
      begin
         if Invocation.Command in Project_Command | History_Command then
            declare
               Id : constant Positive :=
                 Filtering.Resolve_Project (Data, To_String (Invocation.Target), Invocation.Include_Removed);
            begin
               Item.Filter.Project_Id := Id;
               Item.Project := Build_Project (Data, Repository.Project (Data, Id));
               Selected.Append (Item.Project);
            end;
         elsif Invocation.Command = Compare_Command then
            Trends.Compare_Pair
              (Data, Repository.Resolve_Run (Data, To_String (Invocation.Target)),
               Repository.Resolve_Run (Data, To_String (Invocation.Second)), Item.Pair, Item.Regressions);
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
      procedure Compare_Selected is
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
         Item.Comparisons := Natural (Compared.Length);
         if Invocation.Command in Project_Command | History_Command then
            Item.Project.Regression_Count := Selected.First_Element.Regression_Count;
         end if;
      end Compare_Selected;

      --  Summary and projects: sorted, limited rows; the summary adds indicators, finding counts, and regressions.
      procedure Fill_Overview is
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
      procedure Fill_Project is
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
      procedure Fill_Indicators is
      begin
         Item.Indicators := Build_Indicators (Data, Selected);
         Filtering.Sort_Indicators (Item.Indicators, Invocation.Sort, Invocation.Reverse_Order);
         Item.Row_Count := Natural (Item.Indicators.Length);
         Indicators_Limit.Limit (Item.Indicators, Invocation.Limit);
      end Fill_Indicators;

      --  Indicator: the aggregate and one row per selected project.
      procedure Fill_Indicator is
         Id : constant Indicator_Id := Filtering.Resolve_Indicator (To_String (Invocation.Target));
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
      procedure Fill_Problems is
      begin
         Item.Findings := Build_Findings (Data, Selected);
         Count_Findings (Item, Data, Selected);
         Filtering.Sort_Findings (Item.Findings, Invocation.Sort, Invocation.Reverse_Order);
         Item.Row_Count := Item.Finding_Total;
         Findings_Limit.Limit (Item.Findings, Invocation.Limit);
      end Fill_Problems;

      --  Regressions: every regression of the selected projects.
      procedure Fill_Regressions is
      begin
         for Row of Selected loop
            Add_Regressions (Item, Compared (Row.Project_Id));
         end loop;
         Filtering.Sort_Regressions (Item.Regressions, Invocation.Sort, Invocation.Reverse_Order);
         Item.Row_Count := Item.Regression_Total;
         Regressions_Limit.Limit (Item.Regressions, Invocation.Limit);
      end Fill_Regressions;

      --  Waivers: the review-waiver findings of the selected current assessments.
      procedure Fill_Waivers is
         Counts : Repository.Indicator_Counts := [others => 0];
         Owners : Repository.Indicator_Counts := [others => 0];

         --  Add the waivers of one project's current assessment.
         procedure Add_Project (Row : Project_Summary) is
            Seen : Repository.Indicator_Counts := [others => 0];
         begin
            for Finding of Aggregation.Findings_Of (Row.Project_Id, Repository.Assessment (Data, Row.Current_Run_Id))
            loop
               if Is_Waiver (Finding) then
                  Item.Waivers.Append (Finding);
                  Seen (Finding.Indicator) := Seen (Finding.Indicator) + 1;
               end if;
            end loop;
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
      procedure Fill_Compare is
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
      procedure Fill_Trends is
      begin
         for Id in Indicator_Id loop
            if Ada_Quality.Indicators.Measurement_Unit (Id) /= "none" then
               declare
                  Series : Trend_Summary :=
                    Trends.Metric_Series (Data, Selected, Id, Invocation.Since, Invocation.Until_Date);
               begin
                  Filtering.Sort_Points (Series.Points, Invocation.Sort, Invocation.Reverse_Order);
                  Points_Limit.Limit (Series.Points, Invocation.Limit);
                  Item.Excluded_Observations := Item.Excluded_Observations + Series.Excluded_Observations;
                  Item.Series.Append (Series);
               end;
            end if;
         end loop;
         Item.Undated := Trends.Undated_Runs (Data, Selected, Invocation.Since, Invocation.Until_Date);
         Item.Daily := Trends.Daily_States (Data, Selected, Invocation.Since, Invocation.Until_Date);
      end Fill_Trends;

      --  History: a project's runs and their lifecycle counts.
      procedure Fill_History is
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
      procedure Count_Gate is
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

      procedure Fill_Command is
      begin
         case Invocation.Command is
            when Summary_Command | Projects_Command => Fill_Overview;
            when Project_Command => Fill_Project;
            when Indicators_Command => Fill_Indicators;
            when Indicator_Command => Fill_Indicator;
            when Problems_Command => Fill_Problems;
            when Waivers_Command => Fill_Waivers;
            when Regressions_Command => Fill_Regressions;
            when Compare_Command => Fill_Compare;
            when Trends_Command => Fill_Trends;
            when History_Command => Fill_History;
            when Help_Command | Completion_Command | Version_Command =>
               raise Report_Error with "command does not produce a report";
         end case;
      end Fill_Command;

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

      Select_Projects;
      Compare_Selected;
      Item.Metadata.Selected_Projects := Natural (Selected.Length);
      Item.Portfolio := Build_Portfolio (Selected);
      Item.Row_Count := Natural (Selected.Length);

      Fill_Command;
      Count_Gate;
      return Item;
   end Build;
end Ada_Quality_Summary.Reports;
