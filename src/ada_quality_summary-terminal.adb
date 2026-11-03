with Ada.Characters.Handling;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada_Quality.History;
with Ada_Quality.Indicators;
with Ada_Quality.Reporting;
with Ada_Quality.Types;
with Ada_Quality_Summary.Aggregation;
with Ada_Quality_Summary.Model;
with Ada_Quality_Summary.Terminal.Output;
with Ada_Quality_Summary.Text;
with Ada_Quality_Summary.Trends;
with Hostkit.Descriptors;
with Hostkit.Terminal_Control;
with Humanize.Status;
with Humanize.Strings;
with Terminal_Styles;

package body Ada_Quality_Summary.Terminal is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Types;
   use Ada_Quality_Summary.Model;
   use Ada_Quality_Summary.Options;
   use Ada_Quality_Summary.Reports;
   use Ada_Quality_Summary.Terminal.Output;
   use type Ada_Quality.Reporting.Evidence_Format;
   use type Ada_Quality_Summary.Trends.Baseline_Status;
   subtype Unbounded_String is Ada.Strings.Unbounded.Unbounded_String;

   Ellipsis : constant String := Character'Val (16#E2#) & Character'Val (16#80#) & Character'Val (16#A6#);

   ------------------------------------------------------------------------------------------------------------------
   --  Environment
   ------------------------------------------------------------------------------------------------------------------

   --  Terminal detection and size come from hostkit, which answers portably for POSIX terminals and Windows consoles.
   function Stdout_Is_Terminal return Boolean is
     (Hostkit.Descriptors.Is_Terminal (Hostkit.Descriptors.Standard_Output));

   --  A detected width of zero is unknown; any other width is held to the supported range, so a very narrow terminal
   --  gets the minimum layout rather than a width the renderer does not support.
   function Clamp (Value : Natural) return Positive is
     (if Value = 0 then Default_Width
      else Positive'Max (Options.Minimum_Width, Positive'Min (Value, Options.Maximum_Width)));

   function Detect_Width (Explicit : Natural) return Positive is
   begin
      if Explicit > 0 then
         return Clamp (Explicit);
      end if;
      if Stdout_Is_Terminal then
         declare
            Size : Hostkit.Terminal_Control.Window_Size;
         begin
            if Hostkit.Terminal_Control.Size (Hostkit.Descriptors.Standard_Output, Size) and then Size.Columns > 0
            then
               return Clamp (Size.Columns);
            end if;
         end;
      end if;
      if Ada.Environment_Variables.Exists ("COLUMNS") then
         declare
            Text : constant String := Ada.Environment_Variables.Value ("COLUMNS");
         begin
            if Text'Length in 1 .. 4 and then (for all C of Text => C in '0' .. '9') then
               return Clamp (Natural'Value (Text));
            end if;
         end;
      end if;
      return Default_Width;
   end Detect_Width;

   function Use_Color (Mode : Color_Mode) return Boolean is
   begin
      Terminal_Styles.Set_Color_Policy
        (case Mode is
            when Color_Auto => Terminal_Styles.Color_Auto,
            when Color_Always => Terminal_Styles.Color_Always,
            when Color_Never => Terminal_Styles.Color_Never);
      return Terminal_Styles.Color_Enabled (Destination_Is_Terminal => Stdout_Is_Terminal);
   end Use_Color;

   function Unicode_Locale return Boolean is
      function Names_UTF8 (Variable : String) return Boolean is
      begin
         if not Ada.Environment_Variables.Exists (Variable) then
            return False;
         end if;
         declare
            Value : constant String := Ada.Characters.Handling.To_Lower (Ada.Environment_Variables.Value (Variable));
         begin
            return Ada.Strings.Fixed.Index (Value, "utf-8") > 0 or else Ada.Strings.Fixed.Index (Value, "utf8") > 0;
         end;
      end Names_UTF8;

      function Set (Variable : String) return Boolean is
        (Ada.Environment_Variables.Exists (Variable) and then Ada.Environment_Variables.Value (Variable)'Length > 0);
   begin
      --  The first nonempty variable in POSIX precedence order decides.
      if Set ("LC_ALL") then
         return Names_UTF8 ("LC_ALL");
      elsif Set ("LC_CTYPE") then
         return Names_UTF8 ("LC_CTYPE");
      end if;
      return Names_UTF8 ("LANG");
   end Unicode_Locale;

   ------------------------------------------------------------------------------------------------------------------
   --  Display cells
   ------------------------------------------------------------------------------------------------------------------

   function Display_Width (Text : String) return Natural is (Humanize.Strings.ANSI_Display_Width (Text));

   function Fit (Text : String; Width : Natural; Unicode : Boolean) return String is
   begin
      if Display_Width (Text) <= Width then
         return Text;
      elsif Width = 0 then
         return "";
      elsif Width < 3 and then not Unicode then
         return [1 .. Width => '.'];
      end if;
      declare
         Result : constant Humanize.Status.Text_Result :=
           Humanize.Strings.Truncate_Display_Width (Text, Width, (if Unicode then Ellipsis else "..."));
      begin
         if Humanize.Status.Is_Ok (Result) and then Display_Width (To_String (Result.Text)) <= Width then
            return To_String (Result.Text);
         end if;
         return [1 .. Width => '.'];
      end;
   end Fit;

   function Pad (Text : String; Width : Natural; Right : Boolean := False) return String is
      Used : constant Natural := Display_Width (Text);
      Fill : constant String := (if Used >= Width then "" else [1 .. Width - Used => ' ']);
   begin
      return (if Right then Fill & Text else Text & Fill);
   end Pad;

   function Trimmed (Value : Long_Long_Integer) return String is
     (Ada.Strings.Fixed.Trim (Long_Long_Integer'Image (Value), Ada.Strings.Both));

   function Num (Value : Natural) return String is (Trimmed (Long_Long_Integer (Value)));

   function Basis_Points_Image (Value : Long_Long_Integer) return String is
      Magnitude : constant Long_Long_Integer := abs Value;
      Fraction  : constant Long_Long_Integer := Magnitude mod 100;
   begin
      return (if Value < 0 then "-" else "") & Trimmed (Magnitude / 100) & "." &
        (if Fraction < 10 then "0" else "") & Trimmed (Fraction) & "%";
   end Basis_Points_Image;

   ------------------------------------------------------------------------------------------------------------------
   --  Labels
   ------------------------------------------------------------------------------------------------------------------

   function L (Key : String) return String is (Ada_Quality_Summary.Text.Message ("label." & Key));

   function L (Key : String; Value : String) return String is
     (Ada_Quality_Summary.Text.Message ("label." & Key, [Ada_Quality_Summary.Text.Arg ("value", Value)]));

   function Quality_Label (State : Project_Quality_State; Short : Boolean := False) return String is
     (Ada_Quality_Summary.Text.Message ((if Short then "short." else "quality.") & Image (State)));

   function State_Label (State : Aggregation.Indicator_State) return String is
     (Ada_Quality_Summary.Text.Message ("state." & Aggregation.Image (State)));

   function Lower (Text : String) return String renames Ada.Characters.Handling.To_Lower;

   function Category_Label (Category : Ada_Quality.Indicators.Indicator_Category) return String is
     (Ada_Quality_Summary.Text.Message
        ("category." & Lower (Ada_Quality.Indicators.Indicator_Category'Image (Category))));

   function Severity_Label (Level : Severity) return String is
     (Ada.Characters.Handling.To_Upper (Severity'Image (Level)));

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

   function State_Role (State : Aggregation.Indicator_State) return Role_Kind is
     (case State is
         when Aggregation.Pass_State => Good_Role,
         when Aggregation.Violation_State => Bad_Role,
         when Aggregation.Unknown_State => Warn_Role,
         when Aggregation.Not_Applicable_State | Aggregation.Missing_State => Muted_Role);

   function Compliance_State (Value : Compliance_Status) return Aggregation.Indicator_State is
     (case Value is
         when Pass => Aggregation.Pass_State,
         when Violation => Aggregation.Violation_State,
         when Unknown => Aggregation.Unknown_State,
         when Compliance_Status'(Not_Applicable) => Aggregation.Not_Applicable_State);

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
               [Ada_Quality_Summary.Text.Arg ("registered", Long_Long_Integer (Item.Portfolio.Totals.Projects)),
                Ada_Quality_Summary.Text.Arg ("enabled", Long_Long_Integer (Item.Portfolio.Totals.Enabled))]),
            Indent => 0);
      if Out_Text.Style.Layout = Detailed_Layout then
         Note (Out_Text, L ("snapshot", To_String (Item.Metadata.Snapshot_Identity)), Indent => 0);
      end if;
   end Header;

   procedure Summary_Report (Out_Text : in out Writer; Item : Report) is
   begin
      Header (Out_Text, Item, L ("title"));
      Blank (Out_Text);
      Status_Section (Out_Text, Item.Portfolio.Totals);
      Blank (Out_Text);
      Heading (Out_Text, L ("projects"));
      Project_Table (Out_Text, Item.Portfolio.Projects);
      Shown_Note (Out_Text, Natural (Item.Portfolio.Projects.Length), Item.Row_Count);
      Blank (Out_Text);
      Heading (Out_Text, L ("common_violations"));
      if Item.Common.Is_Empty then
         Note (Out_Text, L ("none"));
      else
         declare
            Columns : Column_Vectors.Vector;
            Rows    : Row_Vectors.Vector;
         begin
            Columns.Append (Col (L ("indicator")));
            Columns.Append (Col (L ("projects_column"), Right => True));
            Columns.Append (Col (L ("name"), Shrink => True, Priority => 2, Minimum => 8));
            for Indicator of Item.Common loop
               declare
                  Row : Cell_Vectors.Vector;
               begin
                  Row.Append (C (Image (Indicator.Id)));
                  Row.Append (C (Num (Indicator.Totals.Violated)));
                  Row.Append (C (To_String (Indicator.Name)));
                  Rows.Append (Row);
               end;
            end loop;
            Table (Out_Text, Columns, Rows);
         end;
      end if;
      Blank (Out_Text);
      Heading (Out_Text, L ("regressions_heading"));
      Note (Out_Text, L ("projects_with_regressions", Num (Item.Projects_Affected)));
      Note (Out_Text, L ("regression_count", Num (Item.Regression_Total)));
      Blank (Out_Text);
      Heading (Out_Text, L ("activity"));
      Note (Out_Text, L ("newer_running", Num (Item.Portfolio.Totals.Newer_Running)));
      Note (Out_Text, L ("newer_unfinished", Num (Item.Portfolio.Totals.Newer_Unfinished)));
   end Summary_Report;

   procedure Projects_Report (Out_Text : in out Writer; Item : Report) is
   begin
      Header (Out_Text, Item, L ("projects"));
      Blank (Out_Text);
      Project_Table (Out_Text, Item.Portfolio.Projects);
      Shown_Note (Out_Text, Natural (Item.Portfolio.Projects.Length), Item.Row_Count);
      Blank (Out_Text);
      Note (Out_Text, Ada_Quality_Summary.Text.Message
              ("label.totals_line",
               [Ada_Quality_Summary.Text.Arg ("passing", Long_Long_Integer (Item.Portfolio.Totals.Passing)),
                Ada_Quality_Summary.Text.Arg ("violations", Long_Long_Integer (Item.Portfolio.Totals.Violations)),
                Ada_Quality_Summary.Text.Arg ("incomplete", Long_Long_Integer (Item.Portfolio.Totals.Incomplete)),
                Ada_Quality_Summary.Text.Arg ("unassessed", Long_Long_Integer (Item.Portfolio.Totals.Unassessed))]));
   end Projects_Report;

   procedure Finding_Table (Out_Text : in out Writer; Findings : Finding_Summary_Vectors.Vector;
                            Item : Report; With_Project : Boolean) is
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
            Row  : Cell_Vectors.Vector;
            Name : Unbounded_String := To_Unbounded_String (Num (F.Project_Id));
         begin
            for P of Item.Portfolio.Projects loop
               if P.Project_Id = F.Project_Id then
                  Name := P.Name;
               end if;
            end loop;
            if Item.Metadata.Kind = Model.Project_Report and then Item.Project.Project_Id = F.Project_Id then
               Name := Item.Project.Name;
            end if;
            Row.Append (C (Severity_Label (F.Level), (if F.Level >= High then Bad_Role else Warn_Role)));
            Row.Append (C (Image (F.Indicator)));
            Row.Append (C (To_String (Name)));
            Row.Append (C (if Length (F.Path) = 0 then "-"
                          elsif F.Line = 0 then To_String (F.Path)
                          else To_String (F.Path) & ":" & Num (F.Line)));
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
                               Item : Report) is
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
            Row  : Cell_Vectors.Vector;
            Name : Unbounded_String := To_Unbounded_String (Num (Change.Project_Id));
         begin
            for P of Item.Portfolio.Projects loop
               if P.Project_Id = Change.Project_Id then
                  Name := P.Name;
               end if;
            end loop;
            Row.Append (C (To_String (Name)));
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

   procedure Baseline_Lines (Out_Text : in out Writer; Info : Trends.Baseline_Info; Name : String) is
   begin
      case Info.Status is
         when Trends.No_Current_Assessment =>
            Note (Out_Text, Name & ": " & L ("baseline.no_current"));
         when Trends.No_Baseline =>
            Note (Out_Text, Name & ": " & L ("baseline.none"));
         when Trends.Compared =>
            Note (Out_Text, Name & ": " & L ("baseline.compared", Num (Info.Baseline_Run_Id)));
      end case;
      for Run of Info.Excluded loop
         Note (Out_Text, "  " & Ada_Quality_Summary.Text.Message
                 ("label.baseline.excluded",
                  [Ada_Quality_Summary.Text.Arg ("run", Long_Long_Integer (Run.Run_Id)),
                   Ada_Quality_Summary.Text.Arg ("reason", L ("reason." & Trends.Image (Run.Reason)))]));
      end loop;
   end Baseline_Lines;

   procedure Project_Report (Out_Text : in out Writer; Item : Report) is
      P : constant Project_Summary := Item.Project;
      Width : constant Natural := 14;
   begin
      Heading (Out_Text, L ("project_title", To_String (P.Name)));
      Note (Out_Text, L ("database", To_String (Item.Database_Label)), Indent => 0);
      Blank (Out_Text);
      Field (Out_Text, L ("id"), Num (P.Project_Id), Width, Number => True);
      Field (Out_Text, L ("path"), To_String (P.Project_Path), Width);
      Field (Out_Text, L ("enabled"), (if P.Enabled then L ("yes") else L ("no")), Width);
      if P.Removed then
         Field (Out_Text, L ("removed"), L ("yes"), Width);
      end if;
      Field (Out_Text, L ("quality"), Quality_Label (P.Quality), Width, Quality_Role (P.Quality));
      Field (Out_Text, L ("current_run"), Id_Text (P.Current_Run_Id), Width, Number => True);
      Field (Out_Text, L ("latest_run"), Id_Text (P.Latest_Run_Id), Width, Number => True);
      if P.Newer_Run /= No_Newer_Run then
         Field (Out_Text, L ("newer_run"), L ("newer." & Image (P.Newer_Run)), Width, Warn_Role);
      end if;
      if not Item.Has_Assessment then
         Blank (Out_Text);
         Note (Out_Text, L ("no_assessment"));
         return;
      end if;
      Field (Out_Text, L ("counts"), Ada_Quality_Summary.Text.Message
               ("label.counts_value",
                [Ada_Quality_Summary.Text.Arg ("passed", Long_Long_Integer (P.Totals.Passed)),
                 Ada_Quality_Summary.Text.Arg ("applicable", Long_Long_Integer (Applicable (P.Totals))),
                 Ada_Quality_Summary.Text.Arg ("violated", Long_Long_Integer (P.Totals.Violated)),
                 Ada_Quality_Summary.Text.Arg ("unknown", Long_Long_Integer (P.Totals.Unknown_Count)),
                 Ada_Quality_Summary.Text.Arg ("na", Long_Long_Integer (P.Totals.Not_Applicable))]), Width);
      Field (Out_Text, L ("finished"), Time_Text (Item.Assessment.Run.Finished_At), Width);
      if Out_Text.Style.Layout = Detailed_Layout then
         Field (Out_Text, L ("source"), To_String (Item.Assessment.Run.Source_Id), Width);
         Field (Out_Text, L ("policy"), To_String (Item.Assessment.Run.Policy_Id), Width);
         Field (Out_Text, L ("toolchain"), To_String (Item.Assessment.Run.Toolchain_Id), Width);
         Field (Out_Text, L ("evidence_format"),
                (if Item.Assessment.Run.Format = Ada_Quality.Reporting.Lossless_Evidence then L ("format.lossless")
                 else L ("format.legacy")), Width);
      end if;
      Blank (Out_Text);
      Heading (Out_Text, L ("indicators"));
      declare
         Columns : Column_Vectors.Vector;
         Rows    : Row_Vectors.Vector;
      begin
         Columns.Append (Col (L ("indicator")));
         Columns.Append (Col (L ("compliance")));
         Columns.Append (Col (L ("name"), Shrink => True, Priority => 2, Minimum => 8));
         Columns.Append (Col (L ("execution"), Priority => 2));
         Columns.Append (Col (L ("measurement"), Shrink => True, Priority => 2, Minimum => 8));
         Columns.Append (Col (L ("findings"), Right => True, Priority => 3));
         Columns.Append (Col (L ("summary"), Shrink => True, Priority => 3, Minimum => 10));
         for R of Item.Assessment.Results loop
            declare
               Row : Cell_Vectors.Vector;
            begin
               Row.Append (C (Image (R.Indicator)));
               Row.Append
                 (C (State_Label (Compliance_State (R.Compliance)), State_Role (Compliance_State (R.Compliance))));
               Row.Append (C (Ada_Quality.Indicators.Registry (R.Indicator).Name.all));
               Row.Append (C (Image (R.Execution)));
               Row.Append (C (Measurement_Text (R.Indicator, R.Measurement)));
               Row.Append (C (Num (Natural (R.Findings.Length))));
               Row.Append (C (To_String (R.Summary)));
               Rows.Append (Row);
            end;
         end loop;
         Table (Out_Text, Columns, Rows);
      end;
      if Out_Text.Style.Layout /= Compact_Layout then
         Blank (Out_Text);
         Heading (Out_Text, L ("findings_heading"));
         Finding_Table (Out_Text, Item.Findings, Item, With_Project => False);
         Shown_Note (Out_Text, Natural (Item.Findings.Length), Item.Finding_Total);
      end if;
      if Out_Text.Style.Layout = Detailed_Layout then
         Blank (Out_Text);
         Heading (Out_Text, L ("evidence_heading"));
         for R of Item.Assessment.Results loop
            Note (Out_Text, Image (R.Indicator) & "  " & To_String (R.Evidence));
         end loop;
      end if;
      Blank (Out_Text);
      Heading (Out_Text, L ("regressions_heading"));
      Baseline_Lines (Out_Text, Item.Baselines.First_Element, To_String (P.Name));
      Regression_Table (Out_Text, Item.Regressions, Item);
   end Project_Report;

   procedure Indicators_Report (Out_Text : in out Writer; Item : Report) is
      Columns : Column_Vectors.Vector;
      Rows    : Row_Vectors.Vector;
   begin
      Header (Out_Text, Item, L ("indicators"));
      Blank (Out_Text);
      Columns.Append (Col (L ("indicator")));
      Columns.Append (Col (L ("pass"), Right => True));
      Columns.Append (Col (L ("violation"), Right => True));
      Columns.Append (Col (L ("unknown"), Right => True));
      Columns.Append (Col (L ("not_applicable"), Right => True, Priority => 2));
      Columns.Append (Col (L ("missing"), Right => True, Priority => 2));
      Columns.Append (Col (L ("name"), Shrink => True, Priority => 2, Minimum => 8));
      Columns.Append (Col (L ("category"), Priority => 3));
      Columns.Append (Col (L ("version"), Right => True, Priority => 3));
      for Indicator of Item.Indicators loop
         declare
            Row : Cell_Vectors.Vector;
         begin
            Row.Append (C (Image (Indicator.Id)));
            Row.Append (C (Num (Indicator.Totals.Passed)));
            Row.Append
              (C (Num (Indicator.Totals.Violated), (if Indicator.Totals.Violated > 0 then Bad_Role else No_Role)));
            Row.Append (C (Num (Indicator.Totals.Unknown_Count),
                           (if Indicator.Totals.Unknown_Count > 0 then Warn_Role else No_Role)));
            Row.Append (C (Num (Indicator.Totals.Not_Applicable)));
            Row.Append (C (Num (Indicator.Totals.Missing)));
            Row.Append (C (To_String (Indicator.Name)));
            Row.Append (C (Category_Label (Indicator.Category)));
            Row.Append (C (Num (Indicator.Version)));
            Rows.Append (Row);
         end;
      end loop;
      Table (Out_Text, Columns, Rows);
      Shown_Note (Out_Text, Natural (Item.Indicators.Length), Item.Row_Count);
   end Indicators_Report;

   procedure Indicator_Report (Out_Text : in out Writer; Item : Report) is
      I       : constant Indicator_Summary := Item.Indicator;
      Columns : Column_Vectors.Vector;
      Rows    : Row_Vectors.Vector;
      Width   : constant Natural := 14;
   begin
      Heading (Out_Text, Image (I.Id) & "  " & To_String (I.Name));
      Note (Out_Text, L ("database", To_String (Item.Database_Label)), Indent => 0);
      Blank (Out_Text);
      Field (Out_Text, L ("category"), Category_Label (I.Category), Width);
      Field (Out_Text, L ("version"), Num (I.Version), Width, Number => True);
      Field (Out_Text, L ("unit"), Ada_Quality.Indicators.Measurement_Unit (I.Id), Width);
      Field (Out_Text, L ("projects_column"), Num (Item.Portfolio.Totals.Projects), Width, Number => True);
      Field (Out_Text, L ("pass"), Num (I.Totals.Passed), Width, Number => True);
      Field (Out_Text, L ("violation"), Num (I.Totals.Violated), Width, Number => True);
      Field (Out_Text, L ("unknown"), Num (I.Totals.Unknown_Count), Width, Number => True);
      Field (Out_Text, L ("not_applicable"), Num (I.Totals.Not_Applicable), Width, Number => True);
      Field (Out_Text, L ("missing"), Num (I.Totals.Missing), Width, Number => True);
      Blank (Out_Text);
      Heading (Out_Text, L ("projects"));
      Columns.Append (Col (L ("project"), Shrink => True, Minimum => 8));
      Columns.Append (Col (L ("state")));
      Columns.Append (Col (L ("measurement"), Shrink => True, Priority => 2, Minimum => 8));
      Columns.Append (Col (L ("findings"), Right => True, Priority => 2));
      Columns.Append (Col (L ("run"), Right => True, Priority => 3));
      Columns.Append (Col (L ("summary"), Shrink => True, Priority => 3, Minimum => 10));
      for Row_Item of Item.Indicator_Rows loop
         declare
            Row : Cell_Vectors.Vector;
         begin
            Row.Append (C (To_String (Row_Item.Project.Name)));
            Row.Append (C (State_Label (Row_Item.State), State_Role (Row_Item.State)));
            Row.Append (C (if Row_Item.Has_Result then Measurement_Text (I.Id, Row_Item.Result.Measurement) else "-"));
            Row.Append (C (if Row_Item.Has_Result then Num (Natural (Row_Item.Result.Findings.Length)) else "-"));
            Row.Append (C (Id_Text (Row_Item.Project.Current_Run_Id)));
            Row.Append (C (if Row_Item.Has_Result then To_String (Row_Item.Result.Summary) else "-"));
            Rows.Append (Row);
         end;
      end loop;
      if Rows.Is_Empty then
         Note (Out_Text, L ("no_projects"));
      else
         Table (Out_Text, Columns, Rows);
      end if;
      Shown_Note (Out_Text, Natural (Item.Indicator_Rows.Length), Item.Row_Count);
   end Indicator_Report;

   procedure Problems_Report (Out_Text : in out Writer; Item : Report) is
   begin
      Header (Out_Text, Item, L ("problems"));
      Blank (Out_Text);
      Note (Out_Text, L ("finding_total", Num (Item.Finding_Total)));
      for Level in reverse Severity loop
         Field (Out_Text, Severity_Label (Level), Pad (Num (Item.By_Severity (Level)), 6, True), 8, Number => True);
      end loop;
      Blank (Out_Text);
      Heading (Out_Text, L ("by_indicator"));
      if Item.Groups.Is_Empty then
         Note (Out_Text, L ("none"));
      else
         declare
            Columns : Column_Vectors.Vector;
            Rows    : Row_Vectors.Vector;
         begin
            Columns.Append (Col (L ("indicator")));
            Columns.Append (Col (L ("findings"), Right => True));
            Columns.Append (Col (L ("projects_column"), Right => True));
            Columns.Append (Col (L ("name"), Shrink => True, Priority => 2, Minimum => 8));
            for Group of Item.Groups loop
               declare
                  Row : Cell_Vectors.Vector;
               begin
                  Row.Append (C (Image (Group.Indicator)));
                  Row.Append (C (Num (Group.Findings)));
                  Row.Append (C (Num (Group.Projects)));
                  Row.Append (C (Ada_Quality.Indicators.Registry (Group.Indicator).Name.all));
                  Rows.Append (Row);
               end;
            end loop;
            Table (Out_Text, Columns, Rows);
         end;
      end if;
      Blank (Out_Text);
      Heading (Out_Text, L ("findings_heading"));
      Finding_Table (Out_Text, Item.Findings, Item, With_Project => True);
      Shown_Note (Out_Text, Natural (Item.Findings.Length), Item.Finding_Total);
   end Problems_Report;

   procedure Regressions_Report (Out_Text : in out Writer; Item : Report) is
   begin
      Header (Out_Text, Item, L ("regressions_heading"));
      Blank (Out_Text);
      Note (Out_Text, L ("projects_with_regressions", Num (Item.Projects_Affected)));
      Note (Out_Text, L ("regression_count", Num (Item.Regression_Total)));
      Blank (Out_Text);
      Regression_Table (Out_Text, Item.Regressions, Item);
      Shown_Note (Out_Text, Natural (Item.Regressions.Length), Item.Regression_Total);
      Blank (Out_Text);
      Heading (Out_Text, L ("baselines"));
      for Info of Item.Baselines loop
         declare
            Name : Unbounded_String := To_Unbounded_String (Num (Info.Project_Id));
         begin
            for P of Item.Portfolio.Projects loop
               if P.Project_Id = Info.Project_Id then
                  Name := P.Name;
               end if;
            end loop;
            if Info.Status /= Trends.Compared or else not Info.Excluded.Is_Empty or else
              Out_Text.Style.Layout = Detailed_Layout
            then
               Baseline_Lines (Out_Text, Info, To_String (Name));
            end if;
         end;
      end loop;
   end Regressions_Report;

   procedure Trends_Report (Out_Text : in out Writer; Item : Report) is
   begin
      Header (Out_Text, Item, L ("trends"));
      if Item.Undated > 0 then
         Note (Out_Text, L ("undated", Num (Item.Undated)));
      end if;
      Blank (Out_Text);
      Heading (Out_Text, L ("daily_states"));
      if Item.Daily.Is_Empty then
         Note (Out_Text, L ("no_dated_assessments"));
      else
         declare
            Columns : Column_Vectors.Vector;
            Rows    : Row_Vectors.Vector;
         begin
            Columns.Append (Col (L ("date")));
            Columns.Append (Col (Quality_Label (Passing, True), Right => True));
            Columns.Append (Col (Quality_Label (Violations, True), Right => True));
            Columns.Append (Col (Quality_Label (Incomplete, True), Right => True));
            Columns.Append (Col (Quality_Label (Unassessed, True), Right => True));
            Columns.Append (Col (L ("fail"), Right => True, Priority => 2));
            Columns.Append (Col (L ("unknown"), Right => True, Priority => 2));
            for Day of Item.Daily loop
               declare
                  Row : Cell_Vectors.Vector;
               begin
                  Row.Append (C (To_String (Day.Day)));
                  Row.Append (C (Num (Day.Totals.Passing)));
                  Row.Append (C (Num (Day.Totals.Violations)));
                  Row.Append (C (Num (Day.Totals.Incomplete)));
                  Row.Append (C (Num (Day.Totals.Unassessed)));
                  Row.Append (C (Num (Day.Totals.Indicator_Violations)));
                  Row.Append (C (Num (Day.Totals.Unknown_Results)));
                  Rows.Append (Row);
               end;
            end loop;
            Table (Out_Text, Columns, Rows);
         end;
      end if;
      for Series of Item.Series loop
         if not Series.Points.Is_Empty or else Out_Text.Style.Layout = Detailed_Layout then
            Blank (Out_Text);
            Heading (Out_Text, Image (Series.Indicator) & "  " &
                       Ada_Quality.Indicators.Registry (Series.Indicator).Name.all & " (" &
                       To_String (Series.Unit) & ")");
            Note (Out_Text, Ada_Quality_Summary.Text.Message
                    ("label.series_counts",
                     [Ada_Quality_Summary.Text.Arg ("included", Long_Long_Integer (Series.Projects_Included)),
                      Ada_Quality_Summary.Text.Arg ("excluded", Long_Long_Integer (Series.Projects_Excluded)),
                      Ada_Quality_Summary.Text.Arg
                        ("observations", Long_Long_Integer (Series.Excluded_Observations))]));
            if Series.Points.Is_Empty then
               Note (Out_Text, L ("no_numeric"));
            elsif Out_Text.Style.Layout /= Compact_Layout then
               declare
                  Columns : Column_Vectors.Vector;
                  Rows    : Row_Vectors.Vector;
               begin
                  Columns.Append (Col (L ("run"), Right => True));
                  Columns.Append (Col (L ("project"), Shrink => True, Minimum => 8));
                  Columns.Append (Col (L ("value"), Right => True));
                  Columns.Append (Col (L ("observed"), Priority => 2));
                  for Point of Series.Points loop
                     declare
                        Row  : Cell_Vectors.Vector;
                        Name : Unbounded_String := To_Unbounded_String (Num (Point.Project_Id));
                     begin
                        for P of Item.Portfolio.Projects loop
                           if P.Project_Id = Point.Project_Id then
                              Name := P.Name;
                           end if;
                        end loop;
                        Row.Append (C (Num (Point.Run_Id)));
                        Row.Append (C (To_String (Name)));
                        Row.Append (C (if Series.Kind = Decimal_Value then Basis_Points_Image (Point.Value)
                                       else Trimmed (Point.Value)));
                        Row.Append (C (Time_Text (Point.Observed)));
                        Rows.Append (Row);
                     end;
                  end loop;
                  Table (Out_Text, Columns, Rows);
               end;
            end if;
         end if;
      end loop;
   end Trends_Report;

   procedure History_Report (Out_Text : in out Writer; Item : Report) is
      Columns : Column_Vectors.Vector;
      Rows    : Row_Vectors.Vector;
   begin
      Heading (Out_Text, L ("history_title", To_String (Item.Project.Name)));
      Note (Out_Text, L ("database", To_String (Item.Database_Label)), Indent => 0);
      Blank (Out_Text);
      Note (Out_Text, Ada_Quality_Summary.Text.Message
              ("label.history_counts",
               [Ada_Quality_Summary.Text.Arg ("completed", Long_Long_Integer (Item.Completed_Count)),
                Ada_Quality_Summary.Text.Arg ("running", Long_Long_Integer (Item.Running_Count)),
                Ada_Quality_Summary.Text.Arg ("interrupted", Long_Long_Integer (Item.Interrupted_Count)),
                Ada_Quality_Summary.Text.Arg ("invalid", Long_Long_Integer (Item.Invalid_Count))]));
      if Item.Undated > 0 then
         Note (Out_Text, L ("undated", Num (Item.Undated)));
      end if;
      Blank (Out_Text);
      Columns.Append (Col (L ("run"), Right => True));
      Columns.Append (Col (L ("state")));
      Columns.Append (Col (L ("quality")));
      Columns.Append (Col (L ("finished"), Priority => 2));
      Columns.Append (Col (L ("started"), Priority => 3));
      Columns.Append (Col (L ("policy"), Shrink => True, Priority => 3, Minimum => 8));
      Columns.Append (Col (L ("toolchain"), Shrink => True, Priority => 3, Minimum => 8));
      for Run of Item.History loop
         declare
            Row : Cell_Vectors.Vector;
         begin
            Row.Append (C (Num (Run.Run_Id)));
            Row.Append (C (Run_State_Label (Run.State),
                           (if Run.State = Assessment_Completed then No_Role else Warn_Role)));
            Row.Append (if Run.Has_Quality then C (Quality_Label (Run.Quality), Quality_Role (Run.Quality))
                        else C ("-"));
            Row.Append (C (Time_Text (Run.Finished_At)));
            Row.Append (C (Time_Text (Run.Started_At)));
            Row.Append (C (To_String (Run.Policy_Id)));
            Row.Append (C (To_String (Run.Toolchain_Id)));
            Rows.Append (Row);
         end;
      end loop;
      if Rows.Is_Empty then
         Note (Out_Text, L ("no_runs"));
      else
         Table (Out_Text, Columns, Rows);
      end if;
      Shown_Note (Out_Text, Natural (Item.History.Length), Item.Row_Count);
   end History_Report;

   function Render (Item : Report; Style : Settings) return String is
      Out_Text : Writer := (Text => Null_Unbounded_String, Style => Style);
   begin
      Out_Text.Style.Width := Positive'Max (Options.Minimum_Width, Positive'Min (Style.Width, Options.Maximum_Width));
      case Item.Metadata.Kind is
         when Model.Summary_Report => Summary_Report (Out_Text, Item);
         when Model.Projects_Report => Projects_Report (Out_Text, Item);
         when Model.Project_Report => Project_Report (Out_Text, Item);
         when Model.Indicators_Report => Indicators_Report (Out_Text, Item);
         when Model.Indicator_Report => Indicator_Report (Out_Text, Item);
         when Model.Problems_Report => Problems_Report (Out_Text, Item);
         when Model.Regressions_Report => Regressions_Report (Out_Text, Item);
         when Model.Trends_Report => Trends_Report (Out_Text, Item);
         when Model.History_Report => History_Report (Out_Text, Item);
      end case;
      return To_String (Out_Text.Text);
   end Render;
end Ada_Quality_Summary.Terminal;
