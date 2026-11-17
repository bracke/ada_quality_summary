with Ada.Calendar;
with Ada.Containers.Ordered_Sets;
with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Ada_Quality.History;
with Ada_Quality.Indicators;
with Ada_Quality.Reporting;
with Ada_Quality.Storage;
with Ada_Quality_Summary.Rules.Counting;

package body Ada_Quality_Summary.Trends is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Types;
   use Ada_Quality_Summary.Model;
   use Ada_Quality_Summary.Criteria;
   use type Ada.Calendar.Time;
   use type Ada_Quality.History.Comparison_Status;
   use type Ada_Quality.History.Incompatibility;

   package Repository renames Ada_Quality_Summary.Repository;

   --  The report spelling of why Ada_Quality.History.Compatible rejected a completed predecessor of the same project;
   --  those predecessors cannot fail for another project or an unfinished state.
   function Reason_Of (Value : Ada_Quality.History.Incompatibility) return Exclusion_Reason is
     (case Value is
         when Ada_Quality.History.Missing_Source_Fingerprint => Missing_Source_Fingerprint,
         when Ada_Quality.History.Policy_Changed => Policy_Changed,
         when others => Toolchain_Changed);

   function Completed_Only (Items : Ada_Quality.Storage.History_Vectors.Vector)
      return Ada_Quality.Storage.History_Vectors.Vector
   is
      Result : Ada_Quality.Storage.History_Vectors.Vector;
   begin
      for Item of Items loop
         if To_String (Item.Status) = "completed" then
            Result.Append (Item);
         end if;
      end loop;
      return Result;
   end Completed_Only;

   procedure Regressions
     (Data       : Repository.Snapshot;
      Project_Id : Positive;
      Baseline   : out Baseline_Info;
      Changes    : out Regression_Summary_Vectors.Vector)
   is
      Current_Id : constant Natural := Repository.Current_Run (Data, Project_Id);
   begin
      Baseline := (Project_Id => Project_Id, others => <>);
      Changes.Clear;
      if Current_Id = 0 then
         return;
      end if;
      Baseline.Current_Run_Id := Current_Id;
      declare
         --  Ada Quality selects the baseline and classifies the changes for the current completed assessment.
         Outcome   : constant Ada_Quality.Reporting.Project_Comparison :=
           Repository.Compare (Data, Project_Id, Current_Id);
         Selection : constant Ada_Quality.History.Comparison_Selection := Outcome.Selection;
         Items     : constant Ada_Quality.Storage.History_Vectors.Vector :=
           Repository.History_Items (Data, Project_Id);
         Current   : Ada_Quality.Storage.History_Item := Items.First_Element;
      begin
         for Item of Items loop
            if Item.Id = Current_Id then
               Current := Item;
            end if;
         end loop;
         Baseline.Comparison := Selection.Status;
         Baseline.Policy_Changed := Selection.Policy_Changed;
         --  Explain each completed run between the baseline and the current assessment that was skipped.
         for Index in reverse Items.First_Index .. Items.Last_Index loop
            declare
               Item   : constant Ada_Quality.Storage.History_Item := Items (Index);
               Reason : constant Ada_Quality.History.Incompatibility :=
                 Ada_Quality.History.Incompatibility_Of (Item, Current);
            begin
               if Item.Id < Current_Id and then Item.Id > Selection.Baseline_Id and then
                 To_String (Item.Status) = "completed" and then Reason /= Ada_Quality.History.No_Incompatibility
               then
                  Baseline.Excluded.Append (Excluded_Run'(Run_Id => Item.Id, Reason => Reason_Of (Reason)));
               end if;
            end;
         end loop;
         if Selection.Status /= Ada_Quality.History.Comparison_Available then
            Baseline.Status := No_Baseline;
            return;
         end if;
         Baseline.Status := Compared;
         Baseline.Baseline_Run_Id := Selection.Baseline_Id;
         for Change of Outcome.Changes loop
            Changes.Append
              (Regression_Summary'
                 (Project_Id => Project_Id, Current_Run_Id => Current_Id, Baseline_Run_Id => Selection.Baseline_Id,
                  Kind => Change.Kind, Indicator => Change.Indicator, Before => Change.Before, After => Change.After));
         end loop;
      end;
   end Regressions;

   function In_Range
     (Stamp : Ada_Quality.Reporting.Optional_Timestamp; Since, Until_Date : Date_Bound) return Boolean is
     ((not Since.Present and then not Until_Date.Present) or else
      (Stamp.Present and then Within (Stamp.Value, Since, Until_Date)));

   function Filtered (Since, Until_Date : Date_Bound) return Boolean is (Since.Present or else Until_Date.Present);

   --  The timestamp that places a run in time: its terminal time, or its start time while running.
   function Placed (Run : Ada_Quality.Reporting.Run_Record) return Ada_Quality.Reporting.Optional_Timestamp is
     (if Run.Finished_At.Present then Run.Finished_At else Run.Started_At);

   function History
     (Data : Repository.Snapshot; Project_Id : Positive;
      Since, Until_Date : Date_Bound; Undated : out Natural) return History_Summary_Vectors.Vector
   is
      Result : History_Summary_Vectors.Vector;
   begin
      Undated := 0;
      for Run of Repository.Runs (Data, Project_Id) loop
         if Filtered (Since, Until_Date) and then not Placed (Run).Present then
            Undated := Undated + 1;
         elsif In_Range (Placed (Run), Since, Until_Date) then
            declare
               Item : History_Summary :=
                 (Project_Id => Project_Id, Run_Id => Run.Id, State => Run.State, Source_Id => Run.Source_Id,
                  Policy_Id => Run.Policy_Id, Toolchain_Id => Run.Toolchain_Id, Started_At => Run.Started_At,
                  Finished_At => Run.Finished_At, Has_Quality => False, Quality => Unassessed);
            begin
               if Run.State = Assessment_Completed then
                  Item.Has_Quality := True;
                  Item.Quality := Repository.Facts (Data, Run.Id).Quality;
               end if;
               Result.Append (Item);
            end;
         end if;
      end loop;
      return Result;
   end History;

   function Metric_Series
     (Data       : Repository.Snapshot;
      Projects   : Project_Vectors.Vector;
      Indicator  : Indicator_Id;
      Since, Until_Date : Date_Bound) return Trend_Summary
   is
      Unit   : constant String := Ada_Quality.Indicators.Measurement_Unit (Indicator);
      --  Ada_Quality.Types defines Decimal_Value as the fixed basis-point kind; every other numeric unit is an
      --  integer count.
      Result : Trend_Summary :=
        (Indicator => Indicator, Kind => (if Unit = "basis_points" then Decimal_Value else Integer_Value),
         Unit => To_Unbounded_String (Unit), others => <>);
   begin
      for Project of Projects loop
         declare
            Completed : constant Ada_Quality.Storage.History_Vectors.Vector :=
              Completed_Only (Repository.History_Items (Data, Project.Project_Id));
            Points    : Ada_Quality.History.Trend_Vectors.Vector;
            Included  : Natural := 0;
            Eligible  : Natural := 0;
         begin
            --  Ada_Quality.History.Metric_Trend anchors the series on the latest completed run's measurement
            --  semantics. Passing only completed runs keeps that reference the current assessment.
            if not Completed.Is_Empty then
               Points := Ada_Quality.History.Metric_Trend
                 (Completed, Repository.Measurements (Data, Project.Project_Id), Indicator);
            end if;
            for Item of Completed loop
               if In_Range (Repository.Run (Data, Item.Id).Finished_At, Since, Until_Date) then
                  Eligible := Eligible + 1;
               end if;
            end loop;
            for Point of Points loop
               declare
                  Observed : constant Ada_Quality.Reporting.Optional_Timestamp :=
                    Repository.Run (Data, Point.Run_Id).Finished_At;
               begin
                  --  Never combine measurement representations within one series.
                  if In_Range (Observed, Since, Until_Date) and then
                    Repository.Facts (Data, Point.Run_Id).Kinds (Indicator) = Result.Kind
                  then
                     Result.Points.Append
                       (Trend_Point'(Project_Id => Project.Project_Id, Run_Id => Point.Run_Id, Value => Point.Value,
                         Observed => Observed));
                     Included := Included + 1;
                  end if;
               end;
            end loop;
            if Included = 0 then
               Result.Projects_Excluded := Result.Projects_Excluded + 1;
            else
               Result.Projects_Included := Result.Projects_Included + 1;
            end if;
            Result.Excluded_Observations := Result.Excluded_Observations + (Eligible - Included);
         end;
      end loop;
      return Result;
   end Metric_Series;

   function Undated_Runs
     (Data : Repository.Snapshot; Projects : Project_Vectors.Vector; Since, Until_Date : Date_Bound)
      return Natural
   is
      Count : Natural := 0;
   begin
      if Filtered (Since, Until_Date) then
         for Project of Projects loop
            for Run of Repository.Runs (Data, Project.Project_Id) loop
               if Run.State = Assessment_Completed and then not Run.Finished_At.Present then
                  Count := Count + 1;
               end if;
            end loop;
         end loop;
      end if;
      return Count;
   end Undated_Runs;

   package Day_Sets is new Ada.Containers.Ordered_Sets (Element_Type => Ada.Calendar.Time);

   package Day_Vectors is new Ada.Containers.Vectors (Index_Type => Positive, Element_Type => Ada.Calendar.Time);

   --  Placeholder day of an undated run; Earlier orders undated runs first without consulting it.
   Epoch : constant Ada.Calendar.Time := Ada.Calendar.Time_Of (Ada.Calendar.Year_Number'First, 1, 1);

   --  A completed run placed on the day it counts from; undated legacy runs count from before every day.
   type Placed_Run is record
      Undated : Boolean;
      Day     : Ada.Calendar.Time;
      Run_Id  : Positive;
   end record;

   function Earlier (Left, Right : Placed_Run) return Boolean is
     (if Left.Undated /= Right.Undated then Left.Undated
      elsif not Left.Undated and then Left.Day /= Right.Day then Left.Day < Right.Day
      else Left.Run_Id < Right.Run_Id);

   package Placed_Vectors is new Ada.Containers.Vectors (Index_Type => Positive, Element_Type => Placed_Run);

   package Placed_Sorting is new Placed_Vectors.Generic_Sorting ("<" => Earlier);

   --  Classify the population at the end of each of Days, ascending. Each project's completed runs are walked in
   --  placement order alongside the days: the run counted on a day is the newest one placed on or before it, so one
   --  pass per project replaces a scan per day.
   function Snapshots_Of
     (Data : Repository.Snapshot; Projects : Project_Vectors.Vector; Days : Day_Vectors.Vector)
      return State_Snapshot_Vectors.Vector
   is
      Totals : array (1 .. Natural (Days.Length)) of Portfolio_Totals;
      Result : State_Snapshot_Vectors.Vector;
   begin
      for Project of Projects loop
         declare
            Placed   : Placed_Vectors.Vector;
            Next     : Positive := 1;
            Selected : Natural := 0;
         begin
            for Run of Repository.Runs (Data, Project.Project_Id) loop
               if Run.State = Assessment_Completed then
                  Placed.Append
                    (Placed_Run'
                       (Undated => not Run.Finished_At.Present,
                        Day     => (if Run.Finished_At.Present then Day_Start (Run.Finished_At.Value) else Epoch),
                        Run_Id  => Run.Id));
               end if;
            end loop;
            Placed_Sorting.Sort (Placed);
            for Index in Days.First_Index .. Days.Last_Index loop
               while Next <= Placed.Last_Index and then
                 (Placed (Next).Undated or else Placed (Next).Day <= Days (Index))
               loop
                  Selected := Natural'Max (Selected, Placed (Next).Run_Id);
                  Next := Next + 1;
               end loop;
               if Selected = 0 then
                  Rules.Counting.Add_Classified (Rules.Portfolio_Totals (Totals (Index)), Rules.Unassessed, 0, 0);
               else
                  declare
                     Counts : constant Indicator_Totals := Repository.Facts (Data, Selected).Totals;
                  begin
                     Rules.Counting.Add_Classified
                       (Rules.Portfolio_Totals (Totals (Index)),
                        Rules.Counting.Classify (Rules.Indicator_Totals (Counts)),
                        Violated => Counts.Violated, Unknown => Counts.Unknown_Count);
                  end;
               end if;
            end loop;
         end;
      end loop;
      for Index in Days.First_Index .. Days.Last_Index loop
         Result.Append
           (State_Snapshot'(Day => To_Unbounded_String (Day_Image (Days (Index))), Totals => Totals (Index)));
      end loop;
      return Result;
   end Snapshots_Of;

   function Daily_States
     (Data : Repository.Snapshot;
      Projects : Project_Vectors.Vector;
      Since, Until_Date : Date_Bound) return State_Snapshot_Vectors.Vector
   is
      Day_Set : Day_Sets.Set;
      Days    : Day_Vectors.Vector;
   begin
      for Project of Projects loop
         for Run of Repository.Runs (Data, Project.Project_Id) loop
            if Run.State = Assessment_Completed and then Run.Finished_At.Present and then
              Within (Run.Finished_At.Value, Since, Until_Date)
            then
               Day_Set.Include (Day_Start (Run.Finished_At.Value));
            end if;
         end loop;
      end loop;
      for Day of Day_Set loop
         Days.Append (Day);
      end loop;
      return Snapshots_Of (Data, Projects, Days);
   end Daily_States;
end Ada_Quality_Summary.Trends;
