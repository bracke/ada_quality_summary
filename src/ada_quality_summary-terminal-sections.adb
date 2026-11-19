with Ada.Characters.Handling;
with Ada.Strings.Fixed;
with Ada_Quality_Summary.Terminal.Cells;
with Ada_Quality_Summary.Text;

package body Ada_Quality_Summary.Terminal.Sections is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Types;
   use Ada_Quality_Summary.Options;
   use Ada_Quality_Summary.Reports;
   use Ada_Quality_Summary.Terminal.Cells;

   ------------------------------------------------------------------------------------------------------------------
   --  Values
   ------------------------------------------------------------------------------------------------------------------

   function Trimmed (Value : Long_Long_Integer) return String renames Ada_Quality_Summary.Text.Decimal;

   function Num (Value : Natural) return String is (Trimmed (Long_Long_Integer (Value)));

   ------------------------------------------------------------------------------------------------------------------
   --  Labels
   ------------------------------------------------------------------------------------------------------------------

   function L (Key : String) return String is (Ada_Quality_Summary.Text.Message ("label." & Key));

   function L (Key : String; Value : String) return String is
     (Ada_Quality_Summary.Text.Message ("label." & Key, [Ada_Quality_Summary.Text.Arg ("value", Value)]));

   function Quality_Label (State : Project_Quality_State; Short : Boolean := False) return String is
     (Ada_Quality_Summary.Text.Message ((if Short then "short." else "quality.") & Image (State)));

   function State_Label (State : Indicator_State) return String is
     (Ada_Quality_Summary.Text.Message ("state." & Image (State)));

   function Category_Label (Category : Ada_Quality.Indicators.Indicator_Category) return String is
     (Ada_Quality_Summary.Text.Message ("category." & Image (Category)));

   function Severity_Label (Level : Severity) return String is (Ada.Characters.Handling.To_Upper (Image (Level)));

   function Kind_Label (Kind : Ada_Quality.History.Regression_Kind) return String is (Ada_Quality.History.Image (Kind));

   function Run_State_Label (State : Assessment_Status) return String is
     (Ada_Quality_Summary.Text.Message
        ("run." & (case State is
                      when Assessment_Running => "running",
                      when Assessment_Completed => "completed",
                      when Assessment_Invalid => "invalid",
                      when Assessment_Interrupted => "interrupted")));

   function Id_Text (Value : Natural) return String is (if Value = 0 then "-" else Num (Value));

   function Time_Text (Value : Ada_Quality.Reporting.Optional_Timestamp) return String is
     (if Value.Present then Ada_Quality.Reporting.Image (Value) else "-");

   function Measurement_Text (Id : Indicator_Id; Value : Measurement_Value) return String is
   begin
      case Value.Kind is
         when Unavailable_Value => return L ("unavailable");
         when Boolean_Value => return (if Value.Boolean_Data then "true" else "false");
         when Integer_Value =>
            declare
               Unit : constant String := Ada_Quality.Indicators.Measurement_Unit (Id);
            begin
               return Trimmed (Value.Integer_Data) & (if Unit = "none" then "" else " " & Unit);
            end;
         when Decimal_Value => return Basis_Points_Image (Value.Basis_Points);
         when Text_Value | Enum_Value => return To_String (Value.Text_Data);
      end case;
   end Measurement_Text;


   function Quality_Role (State : Project_Quality_State) return Role_Kind is
     (case State is
         when Passing => Good_Role,
         when Violations => Bad_Role,
         when Incomplete => Warn_Role,
         when Unassessed => Muted_Role);

   function State_Role (State : Indicator_State) return Role_Kind is
     (case State is
         when Pass_State => Good_Role,
         when Violation_State => Bad_Role,
         when Unknown_State => Warn_Role,
         when Not_Applicable_State | Missing_State => Muted_Role);

   function Names_Of (Item : Report) return Name_Maps.Map is
      Result : Name_Maps.Map;
   begin
      for P of Item.Portfolio.Projects loop
         Result.Include (P.Project_Id, P.Name);
      end loop;
      if Item.Metadata.Kind in Model.Project_Report | Model.History_Report | Model.Compare_Report then
         Result.Include (Item.Project.Project_Id, Item.Project.Name);
      end if;
      return Result;
   end Names_Of;

   function Name_Of (Names : Name_Maps.Map; Project_Id : Positive) return String is
     (if Names.Contains (Project_Id) then To_String (Names.Element (Project_Id)) else Num (Project_Id));

   ------------------------------------------------------------------------------------------------------------------
   --  Sections
   ------------------------------------------------------------------------------------------------------------------

   procedure Project_Table (Out_Text : in out Writer; Projects : Model.Project_Vectors.Vector) is
      Columns : Column_Vectors.Vector;
      Rows    : Row_Vectors.Vector;
      Short   : constant Boolean := Out_Text.Style.Layout = Compact_Layout;
   begin
      Columns.Append (Col (L ("project"), Shrink => True, Minimum => 8));
      Columns.Append (Col (L ("quality")));
      Columns.Append (Col (L ("pass"), Right => True));
      Columns.Append (Col (L ("fail"), Right => True));
      Columns.Append (Col (L ("unknown"), Right => True, Priority => 2));
      Columns.Append (Col (L ("not_applicable"), Right => True, Priority => 2));
      Columns.Append (Col (L ("findings"), Right => True, Priority => 2));
      Columns.Append (Col (L ("id"), Right => True, Priority => 3));
      Columns.Append (Col (L ("run"), Right => True, Priority => 3));
      Columns.Append (Col (L ("regressions"), Right => True, Priority => 3));
      Columns.Append (Col (L ("enabled"), Priority => 3));
      Columns.Append (Col (L ("path"), Shrink => True, Priority => 3, Minimum => 8));
      for Project of Projects loop
         declare
            Row      : Cell_Vectors.Vector;
            Assessed : constant Boolean := Project.Current_Run_Id /= 0;
         begin
            Row.Append (C (To_String (Project.Name)));
            Row.Append (C (Quality_Label (Project.Quality, Short), Quality_Role (Project.Quality)));
            Row.Append (C (if Assessed then Num (Project.Totals.Passed) else "-"));
            Row.Append (C (if Assessed then Num (Project.Totals.Violated) else "-"));
            Row.Append (C (if Assessed then Num (Project.Totals.Unknown_Count) else "-"));
            Row.Append (C (if Assessed then Num (Project.Totals.Not_Applicable) else "-"));
            Row.Append (C (Num (Project.Finding_Count)));
            Row.Append (C (Num (Project.Project_Id)));
            Row.Append (C (Id_Text (Project.Current_Run_Id)));
            Row.Append (C (Num (Project.Regression_Count)));
            Row.Append (C (if Project.Enabled then L ("yes") else L ("no")));
            Row.Append (C (To_String (Project.Project_Path)));
            Rows.Append (Row);
         end;
      end loop;
      if Rows.Is_Empty then
         Note (Out_Text, L ("no_projects"));
      else
         Table (Out_Text, Columns, Rows);
      end if;
   end Project_Table;

   procedure Status_Section (Out_Text : in out Writer; Totals : Portfolio_Totals) is
      Width : Natural := 0;
   begin
      for State in Project_Quality_State loop
         Width := Natural'Max (Width, Display_Width (L ("status." & Image (State))));
      end loop;
      Heading (Out_Text, L ("quality_status"));
      Field (Out_Text, L ("status.passing"), Pad (Num (Totals.Passing), 6, True), Width, Number => True);
      Field (Out_Text, L ("status.violations"), Pad (Num (Totals.Violations), 6, True), Width, Number => True);
      Field (Out_Text, L ("status.incomplete"), Pad (Num (Totals.Incomplete), 6, True), Width, Number => True);
      Field (Out_Text, L ("status.unassessed"), Pad (Num (Totals.Unassessed), 6, True), Width, Number => True);
   end Status_Section;

   procedure Header (Out_Text : in out Writer; Item : Report; Title : String) is
   begin
      Heading (Out_Text, Title);
      Note (Out_Text, L ("database", To_String (Item.Database_Label)), Indent => 0);
      Note (Out_Text, Ada_Quality_Summary.Text.Message
              ("label.population",
               [Ada_Quality_Summary.Text.Arg ("selected", Long_Long_Integer (Item.Portfolio.Totals.Projects)),
                Ada_Quality_Summary.Text.Arg ("enabled", Long_Long_Integer (Item.Portfolio.Totals.Enabled))]),
            Indent => 0);
      if Out_Text.Style.Layout = Detailed_Layout then
         Note (Out_Text, L ("snapshot", To_String (Item.Metadata.Snapshot_Identity)), Indent => 0);
      end if;
   end Header;

   function Location_Of (F : Finding_Summary) return String is
     (if Length (F.Path) = 0 then "-"
      elsif F.Line = 0 then To_String (F.Path)
      else To_String (F.Path) & ":" & Num (F.Line));

   procedure Finding_Table (Out_Text : in out Writer; Findings : Finding_Summary_Vectors.Vector;
                            Names : Name_Maps.Map; With_Project : Boolean) is
      Columns : Column_Vectors.Vector;
      Rows    : Row_Vectors.Vector;
   begin
      Columns.Append (Col (L ("severity")));
      Columns.Append (Col (L ("indicator")));
      Columns.Append (Col (L ("project"), Shrink => True, Priority => (if With_Project then 1 else 3), Minimum => 8));
      Columns.Append (Col (L ("location"), Shrink => True, Priority => 2, Minimum => 8));
      Columns.Append (Col (L ("rule"), Shrink => True, Priority => 3, Minimum => 6));
      Columns.Append (Col (L ("message"), Shrink => True, Priority => (if Out_Text.Style.Layout = Compact_Layout
                                                                     then 4 else 2), Minimum => 10));
      for F of Findings loop
         declare
            Row : Cell_Vectors.Vector;
         begin
            Row.Append (C (Severity_Label (F.Level), (if F.Level >= High then Bad_Role else Warn_Role)));
            Row.Append (C (Image (F.Indicator)));
            Row.Append (C (Name_Of (Names, F.Project_Id)));
            Row.Append (C (Location_Of (F)));
            Row.Append (C (To_String (F.Rule)));
            Row.Append (C (To_String (F.Message)));
            Rows.Append (Row);
         end;
      end loop;
      if Rows.Is_Empty then
         Note (Out_Text, L ("no_findings"));
      else
         Table (Out_Text, Columns, Rows);
      end if;
   end Finding_Table;

   procedure Regression_Table (Out_Text : in out Writer; Changes : Regression_Summary_Vectors.Vector;
                               Names : Name_Maps.Map) is
      Columns : Column_Vectors.Vector;
      Rows    : Row_Vectors.Vector;
   begin
      Columns.Append (Col (L ("project"), Shrink => True, Minimum => 8));
      Columns.Append (Col (L ("indicator")));
      Columns.Append (Col (L ("kind")));
      Columns.Append (Col (L ("before"), Shrink => True, Priority => 2, Minimum => 6));
      Columns.Append (Col (L ("after"), Shrink => True, Priority => 2, Minimum => 6));
      Columns.Append (Col (L ("baseline"), Right => True, Priority => 3));
      Columns.Append (Col (L ("run"), Right => True, Priority => 3));
      for Change of Changes loop
         declare
            Row : Cell_Vectors.Vector;
         begin
            Row.Append (C (Name_Of (Names, Change.Project_Id)));
            Row.Append (C (Image (Change.Indicator)));
            Row.Append (C (Kind_Label (Change.Kind), Bad_Role));
            Row.Append (C (Ada.Strings.Fixed.Trim (To_String (Change.Before), Ada.Strings.Both)));
            Row.Append (C (Ada.Strings.Fixed.Trim (To_String (Change.After), Ada.Strings.Both)));
            Row.Append (C (Num (Change.Baseline_Run_Id)));
            Row.Append (C (Num (Change.Current_Run_Id)));
            Rows.Append (Row);
         end;
      end loop;
      if Rows.Is_Empty then
         Note (Out_Text, L ("no_regressions"));
      else
         Table (Out_Text, Columns, Rows);
      end if;
   end Regression_Table;

   procedure Baseline_Lines (Out_Text : in out Writer; Info : Baseline_Info; Name : String) is
   begin
      case Info.Status is
         when No_Current_Assessment =>
            Note (Out_Text, Name & ": " & L ("baseline.no_current"));
         when No_Baseline =>
            Note (Out_Text, Name & ": " & L ("baseline.none", L ("comparison." & Image (Info.Comparison))));
         when Compared =>
            Note (Out_Text, Name & ": " & L ((if Info.Policy_Changed then "baseline.policy_changed"
                                               else "baseline.compared"), Num (Info.Baseline_Run_Id)));
      end case;
      for Run of Info.Excluded loop
         Note (Out_Text, "  " & Ada_Quality_Summary.Text.Message
                 ("label.baseline.excluded",
                  [Ada_Quality_Summary.Text.Arg ("run", Long_Long_Integer (Run.Run_Id)),
                   Ada_Quality_Summary.Text.Arg ("reason", L ("reason." & Image (Run.Reason)))]));
      end loop;
   end Baseline_Lines;

   function Pair_Run_Text (Run : History_Summary) return String is
     (Ada_Quality_Summary.Text.Message
        ("label.pair_run",
         [Ada_Quality_Summary.Text.Arg ("run", Long_Long_Integer (Run.Run_Id)),
          Ada_Quality_Summary.Text.Arg
            ("state", (if Run.Has_Quality then Quality_Label (Run.Quality) else Run_State_Label (Run.State))),
          Ada_Quality_Summary.Text.Arg ("finished", Time_Text (Run.Finished_At))]));
end Ada_Quality_Summary.Terminal.Sections;
