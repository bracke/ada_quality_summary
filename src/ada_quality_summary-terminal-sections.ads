with Ada.Containers.Ordered_Maps;
with Ada.Strings.Unbounded;
with Ada_Quality.History;
with Ada_Quality.Indicators;
with Ada_Quality.Reporting;
with Ada_Quality.Types;
with Ada_Quality_Summary.Model;
with Ada_Quality_Summary.Reports;
with Ada_Quality_Summary.Terminal.Output;

--  Building blocks the report layouts share: value and label spellings, semantic roles, project names, and the
--  sections several reports contain. Like Output, every section renders as terminal text or Markdown.
private package Ada_Quality_Summary.Terminal.Sections is
   --  Shared building blocks of the report layouts.
   use Ada_Quality_Summary.Model;
   use Ada_Quality_Summary.Terminal.Output;

   function Trimmed (Value : Long_Long_Integer) return String;
   --  Return an integer without a leading space.
   --  @param Value Integer.
   --  @return Decimal digits with an optional minus sign.

   function Num (Value : Natural) return String;
   --  Return a count without a leading space.
   --  @param Value Count.
   --  @return Decimal digits.

   function L (Key : String) return String;
   --  Return a catalog label.
   --  @param Key Key below `label.`.
   --  @return Label text.

   function L (Key : String; Value : String) return String;
   --  Return a catalog label with its `{value}` placeholder filled.
   --  @param Key Key below `label.`.
   --  @param Value Placeholder value.
   --  @return Label text.

   function Quality_Label (State : Project_Quality_State; Short : Boolean := False) return String;
   --  Return the spelled-out project classification.
   --  @param State Classification.
   --  @param Short Whether to use the compact four-letter form.
   --  @return Label such as `VIOLATIONS`.

   function State_Label (State : Indicator_State) return String;
   --  Return the spelled-out result state.
   --  @param State Result state.
   --  @return Label such as `PASS`.

   function Category_Label (Category : Ada_Quality.Indicators.Indicator_Category) return String;
   --  Return the display name of an indicator category.
   --  @param Category Category.
   --  @return Label such as `Testing`.

   function Severity_Label (Level : Ada_Quality.Types.Severity) return String;
   --  Return the display spelling of a severity.
   --  @param Level Severity.
   --  @return Uppercase severity.

   function Kind_Label (Kind : Ada_Quality.History.Regression_Kind) return String;
   --  Return Ada Quality's spelling of a regression classification.
   --  @param Kind Classification.
   --  @return Label such as `new-violation`.

   function Run_State_Label (State : Ada_Quality.Types.Assessment_Status) return String;
   --  Return the display spelling of a lifecycle state.
   --  @param State Lifecycle state.
   --  @return Label such as `completed`.

   function Id_Text (Value : Natural) return String;
   --  Return an optional identity.
   --  @param Value Identity, or zero when absent.
   --  @return Digits, or `-` when absent.

   function Time_Text (Value : Ada_Quality.Reporting.Optional_Timestamp) return String;
   --  Return an optional timestamp.
   --  @param Value Timestamp.
   --  @return ISO 8601 UTC text, or `-` when absent.

   function Measurement_Text
     (Id : Ada_Quality.Types.Indicator_Id; Value : Ada_Quality.Types.Measurement_Value) return String;
   --  Return a measurement with its unit.
   --  @param Id Measured indicator.
   --  @param Value Measurement.
   --  @return Display text.

   function Quality_Role (State : Project_Quality_State) return Role_Kind;
   --  Return the color role of a classification.
   --  @param State Classification.
   --  @return Role.

   function State_Role (State : Indicator_State) return Role_Kind;
   --  Return the color role of a result state.
   --  @param State Result state.
   --  @return Role.

   package Name_Maps is new Ada.Containers.Ordered_Maps
     (Key_Type => Positive, Element_Type => Ada.Strings.Unbounded.Unbounded_String,
      "=" => Ada.Strings.Unbounded."=");
   --  Project names by identity.

   function Names_Of (Item : Ada_Quality_Summary.Reports.Report) return Name_Maps.Map;
   --  Return the names of a report's projects, built once for the tables that label rows by project.
   --  @param Item Report.
   --  @return Names by identity.

   function Name_Of (Names : Name_Maps.Map; Project_Id : Positive) return String;
   --  Return a project's name.
   --  @param Names Names by identity.
   --  @param Project_Id Project.
   --  @return Name, or the identity when the report does not name the project.

   function Location_Of (F : Finding_Summary) return String;
   --  Return a finding's location.
   --  @param F Finding.
   --  @return `path:line`, `path`, or `-`.

   function Pair_Run_Text (Run : History_Summary) return String;
   --  Return one run of a compared pair with its classification and finish time.
   --  @param Run Run.
   --  @return Display text.

   procedure Project_Table (Out_Text : in out Writer; Projects : Project_Vectors.Vector);
   --  Write the project table, or a note when there are no projects.
   --  @param Out_Text Writer.
   --  @param Projects Rows.

   procedure Status_Section (Out_Text : in out Writer; Totals : Portfolio_Totals);
   --  Write the classification counts.
   --  @param Out_Text Writer.
   --  @param Totals Portfolio totals.

   procedure Header
     (Out_Text : in out Writer; Item : Ada_Quality_Summary.Reports.Report; Title : String);
   --  Write a collection report's title, database, and population.
   --  @param Out_Text Writer.
   --  @param Item Report.
   --  @param Title Title.

   procedure Finding_Table
     (Out_Text : in out Writer; Findings : Finding_Summary_Vectors.Vector; Names : Name_Maps.Map;
      With_Project : Boolean);
   --  Write the finding table, or a note when there are no findings.
   --  @param Out_Text Writer.
   --  @param Findings Rows.
   --  @param Names Project names.
   --  @param With_Project Whether the project column is essential.

   procedure Regression_Table
     (Out_Text : in out Writer; Changes : Regression_Summary_Vectors.Vector; Names : Name_Maps.Map);
   --  Write the regression table, or a note when there are no regressions.
   --  @param Out_Text Writer.
   --  @param Changes Rows.
   --  @param Names Project names.

   procedure Baseline_Lines (Out_Text : in out Writer; Info : Baseline_Info; Name : String);
   --  Write a project's baseline decision and the runs it skipped.
   --  @param Out_Text Writer.
   --  @param Info Baseline selection.
   --  @param Name Project name.
end Ada_Quality_Summary.Terminal.Sections;
