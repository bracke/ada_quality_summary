with Ada.Strings.Unbounded;
with Ada_Quality.Indicators;
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
         Name => To_Unbounded_String (Basename (To_String (Project.Path))),
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
            Facts : constant Repository.Run_Facts := Repository.Facts (Data, Current);
         begin
            Result.Quality := Facts.Quality;
            Result.Totals := Facts.Totals;
            Result.Finding_Count := Facts.Findings;
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

   function Build_Portfolio (Projects : Project_Vectors.Vector) return Portfolio_Summary is
     ((Totals => Build_Totals (Projects), Projects => Projects));

   function State_Of
     (Data : Repository.Snapshot; Project : Project_Summary; Indicator : Indicator_Id) return Indicator_State is
     (if Project.Current_Run_Id = 0 then Missing_State
      else Repository.Facts (Data, Project.Current_Run_Id).States (Indicator));

   function Empty_Summary (Indicator : Indicator_Id) return Indicator_Summary is
      Descriptor : constant Ada_Quality.Indicators.Indicator_Descriptor := Ada_Quality.Indicators.Registry (Indicator);
   begin
      return (Id => Indicator, Category => Descriptor.Category, Version => Descriptor.Version,
              Name => To_Unbounded_String (Descriptor.Name.all), others => <>);
   end Empty_Summary;

   function Build_Indicator
     (Data : Repository.Snapshot; Projects : Project_Vectors.Vector; Indicator : Indicator_Id)
      return Indicator_Summary
   is
      Result : Indicator_Summary := Empty_Summary (Indicator);
   begin
      for Project of Projects loop
         Rules.Counting.Tally
           (Rules.Indicator_Totals (Result.Totals), Rules.Result_State (State_Of (Data, Project, Indicator)));
      end loop;
      pragma Assert (Sum (Result.Totals) = Natural (Projects.Length));
      return Result;
   end Build_Indicator;

   function Build_Indicators (Data : Repository.Snapshot; Projects : Project_Vectors.Vector)
      return Indicator_Summary_Vectors.Vector
   is
      Result : Indicator_Summary_Vectors.Vector;
   begin
      for Id in Indicator_Id loop
         Result.Append (Empty_Summary (Id));
      end loop;
      --  Each current assessment's facts are derived once and attribute its 33 states.
      for Project of Projects loop
         for Item of Result loop
            Rules.Counting.Tally
              (Rules.Indicator_Totals (Item.Totals), Rules.Result_State (State_Of (Data, Project, Item.Id)));
         end loop;
      end loop;
      for Item of Result loop
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
            Result.Append (Summary_Of (Project_Id, Value.Run.Id, F));
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
