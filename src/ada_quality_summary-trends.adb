with Ada.Calendar;
with Ada.Containers.Ordered_Sets;
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
   use type Ada.Calendar.Time;
   subtype Unbounded_String is Ada.Strings.Unbounded.Unbounded_String;

   package Repository renames Ada_Quality_Summary.Repository;

   function Image (Status : Baseline_Status) return String is
     (case Status is
         when No_Current_Assessment => "no_current_assessment",
         when No_Baseline => "no_baseline",
         when Compared => "compared");

   function Image (Reason : Exclusion_Reason) return String is
     (case Reason is
         when Missing_Source_Fingerprint => "missing_source_fingerprint",
         when Policy_Changed => "policy_changed",
         when Toolchain_Changed => "toolchain_changed");

   --  Explain a rejection already decided by Ada_Quality.History.Compatible.
   function Reason_For (Baseline, Current : Ada_Quality.Storage.History_Item) return Exclusion_Reason is
   begin
      if Length (Baseline.Source_Fingerprint) = 0 or else Length (Current.Source_Fingerprint) = 0 then
         return Missing_Source_Fingerprint;
      elsif Length (Baseline.Policy_Fingerprint) = 0 or else
        Baseline.Policy_Fingerprint /= Current.Policy_Fingerprint
      then
         return Policy_Changed;
      end if;
      return Toolchain_Changed;
   end Reason_For;

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
         Items        : constant Ada_Quality.Storage.History_Vectors.Vector :=
           Repository.History_Items (Data, Project_Id);
         Baseline_Id  : constant Natural := Ada_Quality.History.Baseline_Id (Items, Current_Id);
         Current_Item : Ada_Quality.Storage.History_Item := Items.First_Element;
      begin
         for Item of Items loop
            if Item.Id = Current_Id then
               Current_Item := Item;
            end if;
         end loop;
         for Index in reverse Items.First_Index .. Items.Last_Index loop
            declare
               Item : constant Ada_Quality.Storage.History_Item := Items (Index);
            begin
               if Item.Id < Current_Id and then Item.Id > Baseline_Id and then To_String (Item.Status) = "completed"
                 and then not Ada_Quality.History.Compatible (Item, Current_Item)
               then
                  Baseline.Excluded.Append
                    (Excluded_Run'(Run_Id => Item.Id, Reason => Reason_For (Item, Current_Item)));
               end if;
            end;
         end loop;
         if Baseline_Id = 0 then
            Baseline.Status := No_Baseline;
            return;
         end if;
         Baseline.Status := Compared;
         Baseline.Baseline_Run_Id := Baseline_Id;
         declare
            Baseline_Item : Ada_Quality.Storage.History_Item := Current_Item;
         begin
            for Item of Items loop
               if Item.Id = Baseline_Id then
                  Baseline_Item := Item;
               end if;
            end loop;
            declare
               Old_Rows : constant Ada_Quality.Reporting.History_Evidence :=
                 Repository.History_Evidence (Data, Baseline_Id);
               New_Rows : constant Ada_Quality.Reporting.History_Evidence :=
                 Repository.History_Evidence (Data, Current_Id);
               Found    : constant Ada_Quality.History.Regression_Vectors.Vector :=
                 Ada_Quality.History.Compare
                   (Baseline_Item, Current_Item, Old_Rows.Results, New_Rows.Results, Old_Rows.Measurements,
                    New_Rows.Measurements, Old_Rows.Findings, New_Rows.Findings);
            begin
               for Change of Found loop
                  Changes.Append
                    (Regression_Summary'
                       (Project_Id => Project_Id, Current_Run_Id => Current_Id, Baseline_Run_Id => Baseline_Id,
                      Kind => Change.Kind, Indicator => Change.Indicator, Before => Change.Before,
                      After => Change.After));
               end loop;
            end;
         end;
      end;
   end Regressions;

   function In_Range
     (Stamp : Ada_Quality.Reporting.Optional_Timestamp; Since, Until_Date : Options.Date_Bound) return Boolean is
     ((not Since.Present or else (Stamp.Present and then Stamp.Value >= Since.Value)) and then
      (not Until_Date.Present or else (Stamp.Present and then Stamp.Value < Until_Date.Value)));

   function Filtered (Since, Until_Date : Options.Date_Bound) return Boolean is
     (Since.Present or else Until_Date.Present);

   --  The timestamp that places a run in time: its terminal time, or its start time while running.
   function Placed (Run : Ada_Quality.Reporting.Run_Record) return Ada_Quality.Reporting.Optional_Timestamp is
     (if Run.Finished_At.Present then Run.Finished_At else Run.Started_At);

   function History
     (Data : Repository.Snapshot; Project_Id : Positive;
      Since, Until_Date : Options.Date_Bound; Undated : out Natural) return History_Summary_Vectors.Vector
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
                  Item.Quality := Classify (Repository.Assessment (Data, Run.Id).Results);
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
      Since, Until_Date : Options.Date_Bound) return Trend_Summary
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
            --  Ada_Quality.History.Metric_Trend uses the last element as its comparison reference. Passing only
            --  completed runs makes that reference the current assessment rather than a newer unfinished run.
            if not Completed.Is_Empty then
               Points := Ada_Quality.History.Metric_Trend
                 (Completed, Repository.Measurements (Data, Project.Project_Id), Indicator);
            end if;
            for Item of Completed loop
               declare
                  Run : constant Ada_Quality.Reporting.Run_Record := Repository.Run (Data, Item.Id);
               begin
                  if In_Range (Run.Finished_At, Since, Until_Date) then
                     Eligible := Eligible + 1;
                  end if;
               end;
            end loop;
            for Point of Points loop
               declare
                  Run   : constant Ada_Quality.Reporting.Run_Record := Repository.Run (Data, Point.Run_Id);
                  Value : constant Measurement_Value :=
                    Repository.Assessment (Data, Point.Run_Id).Results (Indicator_Id'Pos (Indicator) + 1).Measurement;
               begin
                  --  Never combine measurement representations within one series.
                  if In_Range (Run.Finished_At, Since, Until_Date) and then Value.Kind = Result.Kind then
                     Result.Points.Append
                       (Trend_Point'(Project_Id => Project.Project_Id, Run_Id => Point.Run_Id, Value => Point.Value,
                         Observed => Run.Finished_At));
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
     (Data : Repository.Snapshot; Projects : Project_Vectors.Vector; Since, Until_Date : Options.Date_Bound)
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

   function Day_Of (Time : Ada.Calendar.Time) return String is
      Image : constant String := Ada_Quality.Reporting.Image ((Present => True, Value => Time));
   begin
      return Image (Image'First .. Image'First + 9);
   end Day_Of;

   package Day_Sets is new Ada.Containers.Ordered_Sets (Element_Type => Unbounded_String);

   function Daily_States
     (Data : Repository.Snapshot;
      Projects : Project_Vectors.Vector;
      Since, Until_Date : Options.Date_Bound) return State_Snapshot_Vectors.Vector
   is
      Days   : Day_Sets.Set;
      Result : State_Snapshot_Vectors.Vector;
   begin
      for Project of Projects loop
         for Run of Repository.Runs (Data, Project.Project_Id) loop
            if Run.State = Assessment_Completed and then Run.Finished_At.Present and then
              In_Range (Run.Finished_At, Since, Until_Date)
            then
               Days.Include (To_Unbounded_String (Day_Of (Run.Finished_At.Value)));
            end if;
         end loop;
      end loop;
      for Day of Days loop
         declare
            Day_End : constant Ada.Calendar.Time := Options.Parse_Date (To_String (Day)) + 86_400.0;
            Totals  : Portfolio_Totals;
         begin
            for Project of Projects loop
               declare
                  Selected : Natural := 0;
               begin
                  for Run of Repository.Runs (Data, Project.Project_Id) loop
                     --  Legacy runs predate every snapshot day; see Daily_States in the package specification.
                     if Run.State = Assessment_Completed and then
                       (not Run.Finished_At.Present or else Run.Finished_At.Value < Day_End)
                     then
                        Selected := Run.Id;
                     end if;
                  end loop;
                  if Selected = 0 then
                     Rules.Counting.Add_Classified (Rules.Portfolio_Totals (Totals), Rules.Unassessed, 0, 0);
                  else
                     declare
                        Counts : constant Indicator_Totals :=
                          Count_Indicators (Repository.Assessment (Data, Selected).Results);
                     begin
                        Rules.Counting.Add_Classified
                          (Rules.Portfolio_Totals (Totals), Rules.Counting.Classify (Rules.Indicator_Totals (Counts)),
                           Violated => Counts.Violated, Unknown => Counts.Unknown_Count);
                     end;
                  end if;
               end;
            end loop;
            Result.Append (State_Snapshot'(Day => Day, Totals => Totals));
         end;
      end loop;
      return Result;
   end Daily_States;
end Ada_Quality_Summary.Trends;
