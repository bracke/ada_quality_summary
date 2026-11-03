with Ada.Containers;
with Ada.Strings.Unbounded;
with Ada_Quality.Indicators;

package body Ada_Quality_Summary.Reports is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Types;
   use Ada_Quality_Summary.Aggregation;
   use Ada_Quality_Summary.Model;
   use Ada_Quality_Summary.Options;

   package Repository renames Ada_Quality_Summary.Repository;

   --  Keep at most Count leading rows; zero keeps every row.
   generic
      type Element_Type is private;
      with package Vectors is new Ada.Containers.Vectors (Positive, Element_Type, <>);
   procedure Limit (Items : in out Vectors.Vector; Count : Natural);

   procedure Limit (Items : in out Vectors.Vector; Count : Natural) is
   begin
      if Count > 0 and then Natural (Items.Length) > Count then
         Items.Set_Length (Ada.Containers.Count_Type (Count));
      end if;
   end Limit;

   procedure Limit_Projects is new Limit (Project_Summary, Model.Project_Vectors);
   procedure Limit_Indicators is new Limit (Indicator_Summary, Indicator_Summary_Vectors);
   procedure Limit_Findings is new Limit (Finding_Summary, Finding_Summary_Vectors);
   procedure Limit_Regressions is new Limit (Regression_Summary, Regression_Summary_Vectors);
   procedure Limit_History is new Limit (History_Summary, History_Summary_Vectors);
   procedure Limit_Points is new Limit (Trend_Point, Trend_Point_Vectors);
   procedure Limit_Rows is new Limit (Indicator_Row, Indicator_Row_Vectors);

   function State_Rank (State : Indicator_State) return Positive is
     (case State is
         when Violation_State => 1,
         when Unknown_State => 2,
         when Missing_State => 3,
         when Pass_State => 4,
         when Not_Applicable_State => 5);

   function Compliance_Rank (Value : Compliance_Status) return Positive is
     (case Value is
         when Violation => 1,
         when Unknown => 2,
         when Pass => 3,
         when Compliance_Status'(Not_Applicable) => 4);

   procedure Sort_Rows (Items : in out Indicator_Row_Vectors.Vector; Key : Sort_Key; Reverse_Order : Boolean) is
      function Base (Left, Right : Indicator_Row) return Boolean is
      begin
         case Key is
            when Sort_Id =>
               return Left.Project.Project_Id < Right.Project.Project_Id;
            when Sort_Name =>
               return (if Left.Project.Name /= Right.Project.Name then Left.Project.Name < Right.Project.Name
                       else Left.Project.Project_Id < Right.Project.Project_Id);
            when others =>
               return (if State_Rank (Left.State) /= State_Rank (Right.State)
                       then State_Rank (Left.State) < State_Rank (Right.State)
                       elsif Left.Project.Name /= Right.Project.Name then Left.Project.Name < Right.Project.Name
                       else Left.Project.Project_Id < Right.Project.Project_Id);
         end case;
      end Base;

      function Less (Left, Right : Indicator_Row) return Boolean is
        (if Reverse_Order then Base (Left => Right, Right => Left) else Base (Left, Right));

      package Sorting is new Indicator_Row_Vectors.Generic_Sorting ("<" => Less);
   begin
      Sorting.Sort (Items);
   end Sort_Rows;

   procedure Sort_Results (Items : in out Result_Vectors.Vector; Key : Sort_Key; Reverse_Order : Boolean) is
      function Base (Left, Right : Indicator_Result) return Boolean is
        (if Key = Sort_State and then Compliance_Rank (Left.Compliance) /= Compliance_Rank (Right.Compliance)
         then Compliance_Rank (Left.Compliance) < Compliance_Rank (Right.Compliance)
         else Left.Indicator < Right.Indicator);

      function Less (Left, Right : Indicator_Result) return Boolean is
        (if Reverse_Order then Base (Left => Right, Right => Left) else Base (Left, Right));

      package Sorting is new Result_Vectors.Generic_Sorting ("<" => Less);
   begin
      Sorting.Sort (Items);
   end Sort_Results;

   procedure Add_Regressions (Item : in out Report; Data : Repository.Snapshot; Project_Id : Positive) is
      Baseline : Trends.Baseline_Info;
      Changes  : Regression_Summary_Vectors.Vector;
   begin
      Trends.Regressions (Data, Project_Id, Baseline, Changes);
      Item.Baselines.Append (Baseline);
      if not Changes.Is_Empty then
         Item.Projects_Affected := Item.Projects_Affected + 1;
      end if;
      for Change of Changes loop
         Item.By_Kind (Change.Kind) := Item.By_Kind (Change.Kind) + 1;
         Item.Regressions.Append (Change);
      end loop;
      Item.Regression_Total := Natural (Item.Regressions.Length);
   end Add_Regressions;

   procedure Count_Findings (Item : in out Report) is
      With_Findings : array (Indicator_Id) of Natural := [others => 0];
      Projects_Seen : Natural := 0;
      Previous      : Natural := 0;
   begin
      Item.Finding_Total := Natural (Item.Findings.Length);
      for F of Item.Findings loop
         Item.By_Severity (F.Level) := Item.By_Severity (F.Level) + 1;
         With_Findings (F.Indicator) := With_Findings (F.Indicator) + 1;
         --  Findings arrive grouped by project, so a change of project marks a new project.
         if F.Project_Id /= Previous then
            Projects_Seen := Projects_Seen + 1;
            Previous := F.Project_Id;
         end if;
      end loop;
      Item.Finding_Projects := Projects_Seen;
      for Id in Indicator_Id loop
         if With_Findings (Id) > 0 then
            declare
               Projects : Natural := 0;
               Last     : Natural := 0;
            begin
               for F of Item.Findings loop
                  if F.Indicator = Id and then F.Project_Id /= Last then
                     Projects := Projects + 1;
                     Last := F.Project_Id;
                  end if;
               end loop;
               Item.Groups.Append
                 (Finding_Group'(Indicator => Id, Findings => With_Findings (Id), Projects => Projects));
            end;
         end if;
      end loop;
   end Count_Findings;

   function Build
     (Data : Repository.Snapshot; Invocation : Options.Options; Database_Label : String) return Report
   is
      Item       : Report;
      Selected   : Project_Vectors.Vector;

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
         else
            for Row of Build_Projects (Data, Filtering.Population (Data, Item.Filter)) loop
               if not Item.Filter.Has_Status or else Row.Quality = Item.Filter.Status then
                  Selected.Append (Row);
               end if;
            end loop;
         end if;
      end Select_Projects;

      --  Summary and projects: sorted, limited rows; the summary adds indicators, findings, and regressions.
      procedure Fill_Overview is
      begin
         Filtering.Sort_Projects
           (Item.Portfolio.Projects, Invocation.Sort, Invocation.Command = Summary_Command,
            Invocation.Reverse_Order);
         Limit_Projects (Item.Portfolio.Projects, Invocation.Limit);
         if Invocation.Command = Summary_Command then
            for Indicator of Build_Indicators (Data, Selected) loop
               if Indicator.Totals.Violated > 0 then
                  Item.Common.Append (Indicator);
               end if;
            end loop;
            Filtering.Sort_Common (Item.Common);
            --  The overview aggregates findings by indicator; only the counts are reported.
            Item.Findings := Build_Findings (Data, Selected);
            Count_Findings (Item);
            Item.Findings.Clear;
            for Row of Selected loop
               Add_Regressions (Item, Data, Row.Project_Id);
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
            Count_Findings (Item);
            Filtering.Sort_Findings (Item.Findings, Default_Sort, False);
            Limit_Findings (Item.Findings, Invocation.Limit);
            Sort_Results (Item.Assessment.Results, Invocation.Sort, Invocation.Reverse_Order);
         end if;
         Add_Regressions (Item, Data, Item.Project.Project_Id);
         Filtering.Sort_Regressions (Item.Regressions, Default_Sort, False);
      end Fill_Project;

      --  Indicators: one aggregate per indicator.
      procedure Fill_Indicators is
      begin
         Item.Indicators := Build_Indicators (Data, Selected);
         Filtering.Sort_Indicators (Item.Indicators, Invocation.Sort, Invocation.Reverse_Order);
         Item.Row_Count := Natural (Item.Indicators.Length);
         Limit_Indicators (Item.Indicators, Invocation.Limit);
      end Fill_Indicators;

      --  Indicator: the aggregate and one row per selected project.
      procedure Fill_Indicator is
      begin
         declare
            Id : constant Indicator_Id := Filtering.Resolve_Indicator (To_String (Invocation.Target));
         begin
            Item.Indicator := Build_Indicator (Data, Selected, Id);
            for Row of Selected loop
               declare
                  Line : Indicator_Row := (Project => Row, State => State_Of (Data, Row, Id), others => <>);
               begin
                  if Row.Current_Run_Id /= 0 then
                     Line.Has_Result := True;
                     Line.Result :=
                       Repository.Assessment (Data, Row.Current_Run_Id).Results (Indicator_Id'Pos (Id) + 1);
                  end if;
                  Item.Indicator_Rows.Append (Line);
               end;
            end loop;
            Sort_Rows (Item.Indicator_Rows, Invocation.Sort, Invocation.Reverse_Order);
            Limit_Rows (Item.Indicator_Rows, Invocation.Limit);
         end;
      end Fill_Indicator;

      --  Problems: every finding of the selected current assessments.
      procedure Fill_Problems is
      begin
         Item.Findings := Build_Findings (Data, Selected);
         Count_Findings (Item);
         Filtering.Sort_Findings (Item.Findings, Invocation.Sort, Invocation.Reverse_Order);
         Item.Row_Count := Item.Finding_Total;
         Limit_Findings (Item.Findings, Invocation.Limit);
      end Fill_Problems;

      --  Regressions: every regression of the selected projects.
      procedure Fill_Regressions is
      begin
         for Row of Selected loop
            Add_Regressions (Item, Data, Row.Project_Id);
         end loop;
         Filtering.Sort_Regressions (Item.Regressions, Invocation.Sort, Invocation.Reverse_Order);
         Item.Row_Count := Item.Regression_Total;
         Limit_Regressions (Item.Regressions, Invocation.Limit);
      end Fill_Regressions;

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
                  Limit_Points (Series.Points, Invocation.Limit);
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
         Limit_History (Item.History, Invocation.Limit);
      end Fill_History;

      procedure Fill_Command is
      begin
         case Invocation.Command is
            when Summary_Command | Projects_Command => Fill_Overview;
            when Project_Command => Fill_Project;
            when Indicators_Command => Fill_Indicators;
            when Indicator_Command => Fill_Indicator;
            when Problems_Command => Fill_Problems;
            when Regressions_Command => Fill_Regressions;
            when Trends_Command => Fill_Trends;
            when History_Command => Fill_History;
            when Help_Command | Version_Command =>
               raise Report_Error with "command does not produce a report";
         end case;
      end Fill_Command;

   begin
      Item.Metadata :=
        (Format_Version => Report_Format_Version, Source_Schema_Version => Repository.Schema_Version (Data),
         Selected_Projects => 0, Snapshot_Identity => To_Unbounded_String (Repository.Identity (Data)),
         Kind => Report_Of (Invocation.Command));
      Item.Layout := Invocation.Layout;
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
      Item.Metadata.Selected_Projects := Natural (Selected.Length);
      Item.Portfolio := Build_Portfolio (Data, Selected);
      Item.Row_Count := Natural (Selected.Length);

      Fill_Command;
      return Item;
   end Build;
end Ada_Quality_Summary.Reports;
