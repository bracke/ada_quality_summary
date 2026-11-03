with Ada.Strings.Unbounded;
with Ada_Quality.Indicators;
with Ada_Quality_Summary.Filtering;
with Ada_Quality_Summary.Rules.Counting;

package body Ada_Quality_Summary.Aggregation is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Types;
   use Ada_Quality_Summary.Model;

   package Repository renames Ada_Quality_Summary.Repository;

   function Build_Project
     (Data : Repository.Snapshot; Project : Ada_Quality.Reporting.Project_Record) return Project_Summary
   is
      Current : constant Natural := Repository.Current_Run (Data, Project.Id);
      Latest  : constant Natural := Repository.Latest_Run (Data, Project.Id);
      Result  : Project_Summary :=
        (Project_Id => Project.Id, Project_Path => Project.Path,
         Name => To_Unbounded_String (Filtering.Basename (To_String (Project.Path))),
         Enabled => Project.Enabled, Removed => Project.Removed, Current_Run_Id => Current,
         Latest_Run_Id => Latest, others => <>);
   begin
      if Latest /= 0 and then Latest /= Current then
         Result.Newer_Run :=
           (case Repository.Run (Data, Latest).State is
               when Assessment_Running => Newer_Running,
               when Assessment_Interrupted => Newer_Interrupted,
               when Assessment_Invalid => Newer_Invalid,
               when Assessment_Completed => No_Newer_Run);
      end if;
      if Current /= 0 then
         declare
            Value : constant Ada_Quality.Reporting.Assessment_Record := Repository.Assessment (Data, Current);
         begin
            Result.Quality := Classify (Value.Results);
            Result.Totals := Count_Indicators (Value.Results);
            for Item of Value.Results loop
               Result.Finding_Count := Result.Finding_Count + Natural (Item.Findings.Length);
            end loop;
         end;
      end if;
      return Result;
   end Build_Project;

   function Build_Projects
     (Data : Repository.Snapshot; Population : Ada_Quality.Reporting.Project_Vectors.Vector)
      return Project_Vectors.Vector
   is
      Result : Project_Vectors.Vector;
   begin
      for Project of Population loop
         Result.Append (Build_Project (Data, Project));
      end loop;
      return Result;
   end Build_Projects;

   function Build_Totals (Projects : Project_Vectors.Vector) return Portfolio_Totals is
      Totals : Portfolio_Totals;
   begin
      for Item of Projects loop
         Rules.Counting.Add_Project
           (Rules.Portfolio_Totals (Totals), Rules.Quality_State (Item.Quality), Enabled => Item.Enabled,
            Findings => Item.Finding_Count, Violated => Item.Totals.Violated, Unknown => Item.Totals.Unknown_Count,
            Newer => Rules.Newer_State (Item.Newer_Run), Regressed => Item.Regression_Count > 0);
      end loop;
      return Totals;
   end Build_Totals;

   function Build_Portfolio (Data : Repository.Snapshot; Projects : Project_Vectors.Vector) return Portfolio_Summary
   is
      pragma Unreferenced (Data);
   begin
      return (Totals => Build_Totals (Projects), Projects => Projects);
   end Build_Portfolio;

   function Image (State : Indicator_State) return String is
     (case State is
         when Pass_State => "pass",
         when Violation_State => "violation",
         when Unknown_State => "unknown",
         when Not_Applicable_State => "not_applicable",
         when Missing_State => "missing");

   function State_Of
     (Data : Repository.Snapshot; Project : Project_Summary; Indicator : Indicator_Id) return Indicator_State is
   begin
      if Project.Current_Run_Id = 0 then
         return Missing_State;
      end if;
      declare
         Value : constant Indicator_Result :=
           Repository.Assessment (Data, Project.Current_Run_Id).Results (Indicator_Id'Pos (Indicator) + 1);
      begin
         pragma Assert (Value.Indicator = Indicator);
         return
           (case Value.Compliance is
               when Pass => Pass_State,
               when Violation => Violation_State,
               when Unknown => Unknown_State,
               when Compliance_Status'(Not_Applicable) => Not_Applicable_State);
      end;
   end State_Of;

   function Build_Indicator
     (Data : Repository.Snapshot; Projects : Project_Vectors.Vector; Indicator : Indicator_Id)
      return Indicator_Summary
   is
      Descriptor : constant Ada_Quality.Indicators.Indicator_Descriptor :=
        Ada_Quality.Indicators.Registry (Indicator);
      Result     : Indicator_Summary :=
        (Id => Indicator, Category => Descriptor.Category, Version => Descriptor.Version,
         Name => To_Unbounded_String (Descriptor.Name.all), others => <>);
   begin
      for Project of Projects loop
         Rules.Counting.Tally
           (Rules.Indicator_Totals (Result.Totals), Rules.Result_State (State_Of (Data, Project, Indicator)));
      end loop;
      Result.Affected := Result.Totals.Violated;
      pragma Assert (Sum (Result.Totals) = Natural (Projects.Length));
      return Result;
   end Build_Indicator;

   function Build_Indicators (Data : Repository.Snapshot; Projects : Project_Vectors.Vector)
      return Indicator_Summary_Vectors.Vector
   is
      Result : Indicator_Summary_Vectors.Vector;
   begin
      for Id in Indicator_Id loop
         declare
            Descriptor : constant Ada_Quality.Indicators.Indicator_Descriptor := Ada_Quality.Indicators.Registry (Id);
         begin
            Result.Append
              (Indicator_Summary'(Id => Id, Category => Descriptor.Category, Version => Descriptor.Version,
                Name => To_Unbounded_String (Descriptor.Name.all), others => <>));
         end;
      end loop;
      --  Decode each current assessment once and attribute its 33 results.
      for Project of Projects loop
         if Project.Current_Run_Id = 0 then
            for Item of Result loop
               Rules.Counting.Tally (Rules.Indicator_Totals (Item.Totals), Rules.Missing_State);
            end loop;
         else
            for Value of Repository.Assessment (Data, Project.Current_Run_Id).Results loop
               declare
                  Item : Indicator_Summary renames Result (Indicator_Id'Pos (Value.Indicator) + 1);
               begin
                  Rules.Counting.Tally
                    (Rules.Indicator_Totals (Item.Totals),
                     (case Value.Compliance is
                         when Pass => Rules.Pass_State,
                         when Violation => Rules.Violation_State,
                         when Unknown => Rules.Unknown_State,
                         when Compliance_Status'(Not_Applicable) => Rules.Not_Applicable_State));
               end;
            end loop;
         end if;
      end loop;
      for Item of Result loop
         Item.Affected := Item.Totals.Violated;
         pragma Assert (Sum (Item.Totals) = Natural (Projects.Length));
      end loop;
      return Result;
   end Build_Indicators;

   function Findings_Of
     (Project_Id : Positive; Value : Ada_Quality.Reporting.Assessment_Record) return Finding_Summary_Vectors.Vector
   is
      Result : Finding_Summary_Vectors.Vector;
   begin
      for Item of Value.Results loop
         for F of Item.Findings loop
            Result.Append
              (Finding_Summary'
                 (Project_Id => Project_Id, Run_Id => Value.Run.Id, Indicator => F.Indicator, Rule => F.Rule,
                Level => F.Level, Message => F.Message, Path => F.Relative_Path, Line => F.Line,
                Fingerprint => F.Fingerprint));
         end loop;
      end loop;
      return Result;
   end Findings_Of;

   function Build_Findings (Data : Repository.Snapshot; Projects : Project_Vectors.Vector)
      return Finding_Summary_Vectors.Vector
   is
      Result : Finding_Summary_Vectors.Vector;
   begin
      for Project of Projects loop
         if Project.Current_Run_Id /= 0 then
            Result.Append (Findings_Of (Project.Project_Id, Repository.Assessment (Data, Project.Current_Run_Id)));
         end if;
      end loop;
      return Result;
   end Build_Findings;
end Ada_Quality_Summary.Aggregation;
