with Ada.Calendar;
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Unbounded;
with Ada_Quality_Summary.Criteria;
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
      Waivers_Command, Regressions_Command, Compare_Command, Trends_Command, History_Command, Help_Command,
      Completion_Command, Version_Command);
   --  Selected command.
   --  @enum Summary_Command Portfolio overview (default).
   --  @enum Projects_Command Project status table.
   --  @enum Project_Command One project assessment.
   --  @enum Indicators_Command Cross-project indicator matrix.
   --  @enum Indicator_Command One indicator across projects.
   --  @enum Problems_Command Outstanding findings.
   --  @enum Waivers_Command Review waivers recorded in current assessments.
   --  @enum Regressions_Command Quality regressions.
   --  @enum Compare_Command Regressions between two chosen assessments.
   --  @enum Trends_Command Historical trends.
   --  @enum History_Command One project history.
   --  @enum Help_Command Usage text.
   --  @enum Completion_Command Shell completion script.
   --  @enum Version_Command Version text.

   subtype Report_Command is Command_Kind range Summary_Command .. History_Command;
   --  Commands that read the database.

   subtype Named_Command is Command_Kind range Summary_Command .. Completion_Command;
   --  Commands selected by a command word; `version` is selected by `--version`.

   function Name (Command : Command_Kind) return String;
   --  Return the command-line spelling.
   --  @param Command Command.
   --  @return Lowercase command word.

   function Usage (Command : Command_Kind) return String;
   --  Return the command word with its positional arguments, as help and the manual show it.
   --  @param Command Command.
   --  @return Text such as `compare BASELINE CURRENT`.

   function Report_Of (Command : Report_Command) return Ada_Quality_Summary.Model.Report_Kind;
   --  Return the report produced by a command.
   --  @param Command Report command.
   --  @return Report kind.

   function Is_Collection (Command : Command_Kind) return Boolean;
   --  Test whether a command reports across projects and therefore accepts `--project` and `--status`.
   --  @param Command Command.
   --  @return True for summary, projects, indicators, indicator, problems, waivers, regressions, and trends.

   function Is_Historical (Command : Command_Kind) return Boolean;
   --  Test whether a command accepts `--since` and `--until`.
   --  @param Command Command.
   --  @return True for trends and history.

   type Output_Format is (Terminal_Format, JSON_Format, Markdown_Format, SARIF_Format);
   --  Output format.
   --  @enum Terminal_Format Human-readable text.
   --  @enum JSON_Format Versioned JSON document.
   --  @enum Markdown_Format GitHub-flavored Markdown with the terminal report's content.
   --  @enum SARIF_Format SARIF 2.1.0 log of the problems report, for code-scanning tools.

   type Shell_Kind is (Bash_Shell, Zsh_Shell, Fish_Shell);
   --  Shell whose completion script `completion` writes.
   --  @enum Bash_Shell Bash.
   --  @enum Zsh_Shell Zsh.
   --  @enum Fish_Shell Fish.

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

   type Option_Kind is
     (Database_Option, Format_Option, Color_Option, No_Color_Option, Layout_Option, Width_Option,
      Include_Removed_Option, Enabled_Only_Option, Project_Option, Status_Option, Sort_Option, Reverse_Option,
      Limit_Option, Since_Option, Until_Option, Pretty_Option, Fail_On_Option, Help_Option, Version_Option);
   --  Every command-line option, in help order.
   --  @enum Database_Option `--database PATH`.
   --  @enum Format_Option `--format terminal|json|markdown|sarif`.
   --  @enum Color_Option `--color auto|always|never`.
   --  @enum No_Color_Option `--no-color`.
   --  @enum Layout_Option `--layout compact|normal|detailed`.
   --  @enum Width_Option `--width N`.
   --  @enum Include_Removed_Option `--include-removed`.
   --  @enum Enabled_Only_Option `--enabled-only`.
   --  @enum Project_Option `--project PROJECT`.
   --  @enum Status_Option `--status STATUS`.
   --  @enum Sort_Option `--sort KEY`.
   --  @enum Reverse_Option `--reverse`.
   --  @enum Limit_Option `--limit N`.
   --  @enum Since_Option `--since DATE`.
   --  @enum Until_Option `--until DATE`.
   --  @enum Pretty_Option `--pretty`.
   --  @enum Fail_On_Option `--fail-on CONDITIONS`.
   --  @enum Help_Option `--help`.
   --  @enum Version_Option `--version`.

   function Spelling (Option : Option_Kind) return String;
   --  Return the option as written on the command line.
   --  @param Option Option.
   --  @return Text such as `--database`.

   function Value_Name (Option : Option_Kind) return String;
   --  Return the placeholder or choices of the option's value.
   --  @param Option Option.
   --  @return Text such as `PATH` or `terminal|json`, or empty for a flag.

   function Help_Key (Option : Option_Kind) return String;
   --  Return the message-catalog key suffix of the option's help line.
   --  @param Option Option.
   --  @return Spelling without the leading dashes, with underscores for dashes.

   function Usage (Option : Option_Kind) return String;
   --  Return the option with its value placeholder, as help and the manual show it.
   --  @param Option Option.
   --  @return Text such as `--database PATH`.

   function Accepts (Command : Command_Kind; Option : Option_Kind) return Boolean;
   --  Test whether a command accepts an option; the parser and the help text both apply this one rule.
   --  @param Command Command.
   --  @param Option Option.
   --  @return True when the option is allowed with the command.

   function Allowed (Command : Command_Kind; Key : Ada_Quality_Summary.Criteria.Sort_Key) return Boolean;
   --  Test whether a command supports a sort key.
   --  @param Command Command.
   --  @param Key Sort key.
   --  @return True when the key is supported.

   Minimum_Width : constant := 20;
   --  Narrowest accepted `--width`.
   Maximum_Width : constant := Ada_Quality_Summary.Limits.Maximum_Width;
   --  Widest accepted or used terminal width.

   type Options is record
      Command         : Command_Kind := Summary_Command;
      Target          : UString;
      Has_Target      : Boolean := False;
      Second          : UString;
      Has_Second      : Boolean := False;
      Shell           : Shell_Kind := Bash_Shell;
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
      Sort            : Ada_Quality_Summary.Criteria.Sort_Key := Ada_Quality_Summary.Criteria.Default_Sort;
      Reverse_Order   : Boolean := False;
      Limit           : Natural := 0;
      Since           : Ada_Quality_Summary.Criteria.Date_Bound;
      Until_Date      : Ada_Quality_Summary.Criteria.Date_Bound;
      Pretty          : Boolean := False;
      Fail_On         : Ada_Quality_Summary.Criteria.Gate_Set := Ada_Quality_Summary.Criteria.No_Gate;
   end record;
   --  Validated invocation.
   --  @field Command Selected command.
   --  @field Target Positional PROJECT, indicator ID, baseline assessment, shell, or help topic.
   --  @field Has_Target Whether a positional argument was supplied.
   --  @field Second Positional current assessment of `compare`.
   --  @field Has_Second Whether a second positional argument was supplied.
   --  @field Shell Shell named by `completion`.
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
   --  @field Fail_On Conditions that make a generated report exit with the gate status.

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
