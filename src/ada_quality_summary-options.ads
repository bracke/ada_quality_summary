with Ada.Calendar;
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Unbounded;
with Ada_Quality_Summary.Limits;
with Ada_Quality_Summary.Model;

--  Strict, noninteractive command-line parsing.
package Ada_Quality_Summary.Options is
   --  Strict, noninteractive command-line parsing.
   subtype UString is Ada.Strings.Unbounded.Unbounded_String;
   --  Dynamically sized option text.

   package String_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => String);
   --  Command-line arguments.

   type Command_Kind is
     (Summary_Command, Projects_Command, Project_Command, Indicators_Command, Indicator_Command, Problems_Command,
      Regressions_Command, Trends_Command, History_Command, Help_Command, Version_Command);
   --  Selected command.
   --  @enum Summary_Command Portfolio overview (default).
   --  @enum Projects_Command Project status table.
   --  @enum Project_Command One project assessment.
   --  @enum Indicators_Command Cross-project indicator matrix.
   --  @enum Indicator_Command One indicator across projects.
   --  @enum Problems_Command Outstanding findings.
   --  @enum Regressions_Command Quality regressions.
   --  @enum Trends_Command Historical trends.
   --  @enum History_Command One project history.
   --  @enum Help_Command Usage text.
   --  @enum Version_Command Version text.

   subtype Report_Command is Command_Kind range Summary_Command .. History_Command;
   --  Commands that read the database.

   function Name (Command : Command_Kind) return String;
   --  Return the command-line spelling.
   --  @param Command Command.
   --  @return Lowercase command word.

   function Report_Of (Command : Report_Command) return Ada_Quality_Summary.Model.Report_Kind;
   --  Return the report produced by a command.
   --  @param Command Report command.
   --  @return Report kind.

   function Is_Collection (Command : Command_Kind) return Boolean;
   --  Test whether a command reports across projects and therefore accepts `--project` and `--status`.
   --  @param Command Command.
   --  @return True for summary, projects, indicators, indicator, problems, regressions, and trends.

   function Is_Historical (Command : Command_Kind) return Boolean;
   --  Test whether a command accepts `--since` and `--until`.
   --  @param Command Command.
   --  @return True for trends and history.

   type Output_Format is (Terminal_Format, JSON_Format);
   --  Output format.
   --  @enum Terminal_Format Human-readable text.
   --  @enum JSON_Format Versioned JSON document.

   type Color_Mode is (Color_Auto, Color_Always, Color_Never);
   --  Terminal color selection.
   --  @enum Color_Auto Color only for a terminal without NO_COLOR.
   --  @enum Color_Always Color for terminal-format output regardless of destination.
   --  @enum Color_Never No color.

   type Layout_Mode is (Compact_Layout, Normal_Layout, Detailed_Layout);
   --  Terminal layout.
   --  @enum Compact_Layout One record per line with minimal columns.
   --  @enum Normal_Layout Readable tables and aggregate sections.
   --  @enum Detailed_Layout Additional identities, descriptions, messages, and evidence.

   type Sort_Key is
     (Default_Sort, Sort_Name, Sort_Id, Sort_Path, Sort_Quality, Sort_Violations, Sort_Unknown, Sort_Findings,
      Sort_Affected, Sort_Severity, Sort_Indicator, Sort_Project, Sort_Kind, Sort_Run, Sort_State);
   --  Ordering selected by `--sort`.
   --  @enum Default_Sort Command-specific default order.
   --  @enum Sort_Name Project or indicator name.
   --  @enum Sort_Id Project or indicator identity.
   --  @enum Sort_Path Project path.
   --  @enum Sort_Quality Quality priority.
   --  @enum Sort_Violations Violation count, descending.
   --  @enum Sort_Unknown Unknown count, descending.
   --  @enum Sort_Findings Finding count, descending.
   --  @enum Sort_Affected Affected-project count, descending.
   --  @enum Sort_Severity Severity, descending.
   --  @enum Sort_Indicator Indicator registry order.
   --  @enum Sort_Project Project identity.
   --  @enum Sort_Kind Regression classification.
   --  @enum Sort_Run Run identity.
   --  @enum Sort_State Result or lifecycle state.

   function Image (Key : Sort_Key) return String;
   --  Return the command-line spelling.
   --  @param Key Sort key.
   --  @return Lowercase key, or `default`.

   function Allowed (Command : Command_Kind; Key : Sort_Key) return Boolean;
   --  Test whether a command supports a sort key.
   --  @param Command Command.
   --  @param Key Sort key.
   --  @return True when the key is supported.

   type Date_Bound (Present : Boolean := False) is record
      case Present is
         when True =>
            Value : Ada.Calendar.Time;
         when False =>
            null;
      end case;
   end record;
   --  Optional instant derived from an inclusive ISO date.
   --  @field Present Whether a date was supplied.
   --  @field Value UTC instant: start of day for `--since`, start of the following day for `--until`.

   Minimum_Width : constant := 20;
   --  Narrowest accepted `--width`.
   Maximum_Width : constant := Ada_Quality_Summary.Limits.Maximum_Width;
   --  Widest accepted or used terminal width.

   type Options is record
      Command         : Command_Kind := Summary_Command;
      Target          : UString;
      Has_Target      : Boolean := False;
      Database        : UString;
      Has_Database    : Boolean := False;
      Format          : Output_Format := Terminal_Format;
      Color           : Color_Mode := Color_Auto;
      Has_Color       : Boolean := False;
      Layout          : Layout_Mode := Normal_Layout;
      Has_Layout      : Boolean := False;
      Width           : Natural := 0;
      Include_Removed : Boolean := False;
      Enabled_Only    : Boolean := False;
      Project         : UString;
      Has_Project     : Boolean := False;
      Has_Status      : Boolean := False;
      Status          : Ada_Quality_Summary.Model.Project_Quality_State := Ada_Quality_Summary.Model.Passing;
      Sort            : Sort_Key := Default_Sort;
      Reverse_Order   : Boolean := False;
      Limit           : Natural := 0;
      Since           : Date_Bound;
      Until_Date      : Date_Bound;
      Pretty          : Boolean := False;
   end record;
   --  Validated invocation.
   --  @field Command Selected command.
   --  @field Target Positional PROJECT, indicator ID, or help topic.
   --  @field Has_Target Whether a positional argument was supplied.
   --  @field Database Explicit database path.
   --  @field Has_Database Whether `--database` was supplied.
   --  @field Format Output format.
   --  @field Color Color mode.
   --  @field Has_Color Whether a color option was supplied.
   --  @field Layout Terminal layout.
   --  @field Has_Layout Whether `--layout` was supplied.
   --  @field Width Explicit display width, or zero to detect.
   --  @field Include_Removed Whether tombstoned projects are included.
   --  @field Enabled_Only Whether only enabled projects are included.
   --  @field Project Collection restriction to one project.
   --  @field Has_Project Whether `--project` was supplied.
   --  @field Has_Status Whether `--status` was supplied.
   --  @field Status Quality-state filter.
   --  @field Sort Ordering.
   --  @field Reverse_Order Whether the ordering is reversed.
   --  @field Limit Maximum rows, or zero for no limit.
   --  @field Since Earliest included instant.
   --  @field Until_Date Exclusive upper instant.
   --  @field Pretty Whether JSON is indented.

   function Parse (Arguments : String_Vectors.Vector) return Options;
   --  Parse and validate a complete command line.
   --  @param Arguments Command-line arguments without the program name.
   --  @return Validated options.
   --  @exception Argument_Error Any unknown, duplicate, missing, malformed, or incompatible argument.

   function Parse_Date (Text : String) return Ada.Calendar.Time;
   --  Parse an ISO `YYYY-MM-DD` date as midnight UTC.
   --  @param Text Date text.
   --  @return Instant.
   --  @exception Argument_Error Text is not a valid calendar date.
end Ada_Quality_Summary.Options;
