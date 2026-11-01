with Ada.Containers.Vectors;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada_Quality.History;
with Ada_Quality.Indicators;
with Ada_Quality_Summary.Text;

package body Ada_Quality_Summary.Filtering is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Types;
   use Ada_Quality_Summary.Model;
   use Ada_Quality_Summary.Options;
   use Ada_Quality_Summary.Text;
   use type Ada_Quality.History.Regression_Kind;

   function Basename (Path : String) return String is
      Slash : constant Natural := Ada.Strings.Fixed.Index (Path, "/", Ada.Strings.Backward);
   begin
      if Slash = 0 then
         return Path;
      elsif Slash = Path'Last and then Path'Length > 1 then
         return Basename (Path (Path'First .. Path'Last - 1));
      end if;
      return Path (Slash + 1 .. Path'Last);
   end Basename;

   function Is_Number (Text : String) return Boolean is
     (Text'Length in 1 .. 9 and then (for all C of Text => C in '0' .. '9'));

   function Resolve_Project
     (Data : Ada_Quality_Summary.Repository.Snapshot; Text : String; Include_Removed : Boolean) return Positive
   is
      Candidates : constant Ada_Quality.Reporting.Project_Vectors.Vector :=
        Ada_Quality_Summary.Repository.Projects (Data, Include_Removed);
      Found      : Natural := 0;
      Matches    : Ada.Strings.Unbounded.Unbounded_String;
   begin
      if Is_Number (Text) and then Natural'Value (Text) > 0 then
         for Project of Candidates loop
            if Project.Id = Natural'Value (Text) then
               return Project.Id;
            end if;
         end loop;
      end if;
      for Project of Candidates loop
         if Basename (To_String (Project.Path)) = Text then
            if Found /= 0 then
               Append (Matches, ", ");
            end if;
            Append (Matches, Ada.Strings.Fixed.Trim (Positive'Image (Project.Id), Ada.Strings.Both));
            if Found = 0 then
               Found := Project.Id;
            else
               Found := Natural'Last;
            end if;
         end if;
      end loop;
      if Found = 0 then
         raise Argument_Error with Message ("error.unknown_project", [Arg ("project", Text)]);
      elsif Found = Natural'Last then
         raise Argument_Error with
           Message ("error.ambiguous_project", [Arg ("project", Text), Arg ("ids", To_String (Matches))]);
      end if;
      return Found;
   end Resolve_Project;

   function Resolve_Indicator (Text : String) return Indicator_Id is
      Id : Indicator_Id;
   begin
      if not Ada_Quality.Indicators.Parse (Text, Id) or else Image (Id) /= Text then
         raise Argument_Error with Message ("error.unknown_indicator", [Arg ("indicator", Text)]);
      end if;
      return Id;
   end Resolve_Indicator;

   function Population
     (Data : Ada_Quality_Summary.Repository.Snapshot; Filter : Selection)
      return Ada_Quality.Reporting.Project_Vectors.Vector
   is
      Result : Ada_Quality.Reporting.Project_Vectors.Vector;
   begin
      for Project of Ada_Quality_Summary.Repository.Projects (Data, Filter.Include_Removed) loop
         if (Filter.Project_Id = 0 or else Project.Id = Filter.Project_Id) and then
           (not Filter.Enabled_Only or else Project.Enabled)
         then
            Result.Append (Project);
         end if;
      end loop;
      return Result;
   end Population;

   --  Generic ordering helper: Less_Base is a strict total order; Reverse_Order flips it.
   generic
      type Element_Type is private;
      with package Vectors is new Ada.Containers.Vectors (Positive, Element_Type, <>);
   procedure Ordered_Sort
     (Items : in out Vectors.Vector;
      Less_Base : not null access function (Left, Right : Element_Type) return Boolean;
      Reverse_Order : Boolean);

   procedure Ordered_Sort
     (Items : in out Vectors.Vector;
      Less_Base : not null access function (Left, Right : Element_Type) return Boolean;
      Reverse_Order : Boolean)
   is
      --  Every Less_Base is a strict total order ending in unique identities, so an unstable sort is deterministic.
      function Less (Left, Right : Element_Type) return Boolean is
        (if Reverse_Order then Less_Base (Left => Right, Right => Left) else Less_Base (Left, Right));
      package Sorting is new Vectors.Generic_Sorting ("<" => Less);
   begin
      Sorting.Sort (Items);
   end Ordered_Sort;

   procedure Sort_Project_Rows is new Ordered_Sort (Project_Summary, Model.Project_Vectors);
   procedure Sort_Indicator_Rows is new Ordered_Sort (Indicator_Summary, Indicator_Summary_Vectors);
   procedure Sort_Finding_Rows is new Ordered_Sort (Finding_Summary, Finding_Summary_Vectors);
   procedure Sort_Regression_Rows is new Ordered_Sort (Regression_Summary, Regression_Summary_Vectors);
   procedure Sort_History_Rows is new Ordered_Sort (History_Summary, History_Summary_Vectors);
   procedure Sort_Point_Rows is new Ordered_Sort (Trend_Point, Trend_Point_Vectors);

   function Name_Then_Id (Left, Right : Project_Summary) return Boolean is
     (if Left.Name /= Right.Name then Left.Name < Right.Name else Left.Project_Id < Right.Project_Id);

   procedure Sort_Projects
     (Items : in out Model.Project_Vectors.Vector; Key : Sort_Key; Overview : Boolean; Reverse_Order : Boolean)
   is
      Effective : constant Sort_Key :=
        (if Key /= Default_Sort then Key elsif Overview then Sort_Quality else Sort_Name);

      function Less (Left, Right : Project_Summary) return Boolean is
      begin
         case Effective is
            when Sort_Id =>
               return Left.Project_Id < Right.Project_Id;
            when Sort_Path =>
               return (if Left.Project_Path /= Right.Project_Path then Left.Project_Path < Right.Project_Path
                       else Left.Project_Id < Right.Project_Id);
            when Sort_Quality =>
               if Quality_Priority (Left.Quality) /= Quality_Priority (Right.Quality) then
                  return Quality_Priority (Left.Quality) < Quality_Priority (Right.Quality);
               elsif Left.Totals.Violated /= Right.Totals.Violated then
                  return Left.Totals.Violated > Right.Totals.Violated;
               end if;
               return Name_Then_Id (Left, Right);
            when Sort_Violations =>
               return (if Left.Totals.Violated /= Right.Totals.Violated
                       then Left.Totals.Violated > Right.Totals.Violated else Name_Then_Id (Left, Right));
            when Sort_Unknown =>
               return (if Left.Totals.Unknown_Count /= Right.Totals.Unknown_Count
                       then Left.Totals.Unknown_Count > Right.Totals.Unknown_Count
                       else Name_Then_Id (Left, Right));
            when Sort_Findings =>
               return (if Left.Finding_Count /= Right.Finding_Count then Left.Finding_Count > Right.Finding_Count
                       else Name_Then_Id (Left, Right));
            when others =>
               return Name_Then_Id (Left, Right);
         end case;
      end Less;
   begin
      Sort_Project_Rows (Items, Less'Access, Reverse_Order);
   end Sort_Projects;

   procedure Sort_Indicators
     (Items : in out Indicator_Summary_Vectors.Vector; Key : Sort_Key; Reverse_Order : Boolean)
   is
      function Less (Left, Right : Indicator_Summary) return Boolean is
      begin
         case Key is
            when Sort_Name =>
               return (if Left.Name /= Right.Name then Left.Name < Right.Name else Left.Id < Right.Id);
            when Sort_Violations =>
               return (if Left.Totals.Violated /= Right.Totals.Violated
                       then Left.Totals.Violated > Right.Totals.Violated else Left.Id < Right.Id);
            when Sort_Unknown =>
               return (if Left.Totals.Unknown_Count /= Right.Totals.Unknown_Count
                       then Left.Totals.Unknown_Count > Right.Totals.Unknown_Count else Left.Id < Right.Id);
            when Sort_Affected =>
               return (if Left.Affected /= Right.Affected then Left.Affected > Right.Affected else Left.Id < Right.Id);
            when others =>
               return Left.Id < Right.Id;
         end case;
      end Less;
   begin
      Sort_Indicator_Rows (Items, Less'Access, Reverse_Order);
   end Sort_Indicators;

   procedure Sort_Common (Items : in out Indicator_Summary_Vectors.Vector) is
   begin
      Sort_Indicators (Items, Sort_Violations, Reverse_Order => False);
   end Sort_Common;

   function Finding_Tail (Left, Right : Finding_Summary) return Boolean is
     (if Left.Fingerprint /= Right.Fingerprint then Left.Fingerprint < Right.Fingerprint
      elsif Left.Run_Id /= Right.Run_Id then Left.Run_Id < Right.Run_Id
      elsif Left.Path /= Right.Path then Left.Path < Right.Path
      elsif Left.Line /= Right.Line then Left.Line < Right.Line
      else Left.Message < Right.Message);

   procedure Sort_Findings
     (Items : in out Finding_Summary_Vectors.Vector; Key : Sort_Key; Reverse_Order : Boolean)
   is
      function By_Indicator (Left, Right : Finding_Summary) return Boolean is
        (if Left.Indicator /= Right.Indicator then Left.Indicator < Right.Indicator
         elsif Left.Project_Id /= Right.Project_Id then Left.Project_Id < Right.Project_Id
         else Finding_Tail (Left, Right));

      function Less (Left, Right : Finding_Summary) return Boolean is
      begin
         case Key is
            when Sort_Indicator =>
               return By_Indicator (Left, Right);
            when Sort_Project =>
               return (if Left.Project_Id /= Right.Project_Id then Left.Project_Id < Right.Project_Id
                       else By_Indicator (Left, Right));
            when others =>
               return (if Left.Level /= Right.Level then Left.Level > Right.Level else By_Indicator (Left, Right));
         end case;
      end Less;
   begin
      Sort_Finding_Rows (Items, Less'Access, Reverse_Order);
   end Sort_Findings;

   procedure Sort_Regressions
     (Items : in out Regression_Summary_Vectors.Vector; Key : Sort_Key; Reverse_Order : Boolean)
   is
      function Tail (Left, Right : Regression_Summary) return Boolean is
        (if Left.Before /= Right.Before then Left.Before < Right.Before
         elsif Left.After /= Right.After then Left.After < Right.After
         else Left.Current_Run_Id < Right.Current_Run_Id);

      function Less (Left, Right : Regression_Summary) return Boolean is
      begin
         case Key is
            when Sort_Indicator =>
               return (if Left.Indicator /= Right.Indicator then Left.Indicator < Right.Indicator
                       elsif Left.Project_Id /= Right.Project_Id then Left.Project_Id < Right.Project_Id
                       elsif Left.Kind /= Right.Kind then Left.Kind < Right.Kind
                       else Tail (Left, Right));
            when Sort_Kind =>
               return (if Left.Kind /= Right.Kind then Left.Kind < Right.Kind
                       elsif Left.Project_Id /= Right.Project_Id then Left.Project_Id < Right.Project_Id
                       elsif Left.Indicator /= Right.Indicator then Left.Indicator < Right.Indicator
                       else Tail (Left, Right));
            when others =>
               return (if Left.Project_Id /= Right.Project_Id then Left.Project_Id < Right.Project_Id
                       elsif Left.Indicator /= Right.Indicator then Left.Indicator < Right.Indicator
                       elsif Left.Kind /= Right.Kind then Left.Kind < Right.Kind
                       else Tail (Left, Right));
         end case;
      end Less;
   begin
      Sort_Regression_Rows (Items, Less'Access, Reverse_Order);
   end Sort_Regressions;

   procedure Sort_History (Items : in out History_Summary_Vectors.Vector; Reverse_Order : Boolean) is
      function Less (Left, Right : History_Summary) return Boolean is
        (if Left.Run_Id /= Right.Run_Id then Left.Run_Id > Right.Run_Id else Left.Project_Id < Right.Project_Id);
   begin
      Sort_History_Rows (Items, Less'Access, Reverse_Order);
   end Sort_History;

   procedure Sort_Points (Items : in out Trend_Point_Vectors.Vector; Key : Sort_Key; Reverse_Order : Boolean) is
      function Less (Left, Right : Trend_Point) return Boolean is
      begin
         if Key = Sort_Project then
            return (if Left.Project_Id /= Right.Project_Id then Left.Project_Id < Right.Project_Id
                    else Left.Run_Id < Right.Run_Id);
         end if;
         return (if Left.Run_Id /= Right.Run_Id then Left.Run_Id < Right.Run_Id
                 else Left.Project_Id < Right.Project_Id);
      end Less;
   begin
      Sort_Point_Rows (Items, Less'Access, Reverse_Order);
   end Sort_Points;

end Ada_Quality_Summary.Filtering;
