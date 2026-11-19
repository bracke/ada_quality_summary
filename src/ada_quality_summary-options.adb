with Ada_Quality_Summary.Options.Parsing;

package body Ada_Quality_Summary.Options is
   use Ada_Quality_Summary.Criteria;

   --  Report commands and report kinds are declared in the same order, so a report command is its report kind's
   --  position, and the command word is the report type's spelling.
   pragma Compile_Time_Error
     (Report_Command'Pos (Report_Command'Last) - Report_Command'Pos (Report_Command'First) /=
        Ada_Quality_Summary.Model.Report_Kind'Pos (Ada_Quality_Summary.Model.Report_Kind'Last),
      "every report command needs exactly one report kind");

   function Report_Of (Command : Report_Command) return Ada_Quality_Summary.Model.Report_Kind is
     (Ada_Quality_Summary.Model.Report_Kind'Val (Command_Kind'Pos (Command) - Command_Kind'Pos (Report_Command'First)));

   function Name (Command : Command_Kind) return String is
     (case Command is
         when Report_Command => Ada_Quality_Summary.Model.Image (Report_Of (Command)),
         when Help_Command => "help",
         when Completion_Command => "completion",
         when Version_Command => "version");

   function Usage (Command : Command_Kind) return String is
     (case Command is
         when Project_Command => "project PROJECT",
         when Indicator_Command => "indicator ID",
         when History_Command => "history PROJECT",
         when Compare_Command => "compare BASELINE CURRENT",
         when Help_Command => "help [COMMAND]",
         when Completion_Command => "completion SHELL",
         when others => Name (Command));

   function Is_Collection (Command : Command_Kind) return Boolean is
     (Command in Summary_Command | Projects_Command | Indicators_Command | Indicator_Command | Problems_Command |
                 Waivers_Command | Regressions_Command | Trends_Command);

   function Is_Historical (Command : Command_Kind) return Boolean is
     (Command in Trends_Command | History_Command);

   type Text_Access is access constant String;

   type Option_Text is record
      Spelling : Text_Access;
      Value    : Text_Access;
   end record;

   Option_Texts : constant array (Option_Kind) of Option_Text :=
     [Database_Option        => (new String'("--database"), new String'("PATH")),
      Format_Option          => (new String'("--format"), new String'("terminal|json|markdown|sarif")),
      Color_Option           => (new String'("--color"), new String'("auto|always|never")),
      No_Color_Option        => (new String'("--no-color"), new String'("")),
      Layout_Option          => (new String'("--layout"), new String'("compact|normal|detailed")),
      Width_Option           => (new String'("--width"), new String'("N")),
      Include_Removed_Option => (new String'("--include-removed"), new String'("")),
      Enabled_Only_Option    => (new String'("--enabled-only"), new String'("")),
      Project_Option         => (new String'("--project"), new String'("PROJECT")),
      Status_Option          => (new String'("--status"), new String'("STATUS")),
      Sort_Option            => (new String'("--sort"), new String'("KEY")),
      Reverse_Option         => (new String'("--reverse"), new String'("")),
      Limit_Option           => (new String'("--limit"), new String'("N")),
      Since_Option           => (new String'("--since"), new String'("DATE")),
      Until_Option           => (new String'("--until"), new String'("DATE")),
      Pretty_Option          => (new String'("--pretty"), new String'("")),
      Fail_On_Option         => (new String'("--fail-on"), new String'("CONDITIONS")),
      Help_Option            => (new String'("--help"), new String'("")),
      Version_Option         => (new String'("--version"), new String'(""))];

   function Spelling (Option : Option_Kind) return String is (Option_Texts (Option).Spelling.all);

   function Value_Name (Option : Option_Kind) return String is (Option_Texts (Option).Value.all);

   function Usage (Option : Option_Kind) return String is
     (if Value_Name (Option) = "" then Spelling (Option) else Spelling (Option) & " " & Value_Name (Option));

   function Help_Key (Option : Option_Kind) return String is
      Text : constant String := Spelling (Option);
      Key  : String := Text (Text'First + 2 .. Text'Last);
   begin
      for C of Key loop
         if C = '-' then
            C := '_';
         end if;
      end loop;
      return Key;
   end Help_Key;

   function Accepts (Command : Command_Kind; Option : Option_Kind) return Boolean is
     (case Option is
         when Help_Option | Version_Option => True,
         when Project_Option | Status_Option | Enabled_Only_Option => Is_Collection (Command),
         when Since_Option | Until_Option => Is_Historical (Command),
         when Sort_Option => (for some Key in Sort_Name .. Sort_Key'Last => Allowed (Command, Key)),
         when others => Command in Report_Command);

   function Allowed (Command : Command_Kind; Key : Sort_Key) return Boolean is
   begin
      if Key = Default_Sort then
         return True;
      end if;
      case Command is
         when Summary_Command =>
            return Key in Sort_Name | Sort_Id | Sort_Quality | Sort_Violations;
         when Projects_Command =>
            return Key in Sort_Name | Sort_Id | Sort_Path | Sort_Quality | Sort_Violations | Sort_Unknown |
                          Sort_Findings;
         when Project_Command =>
            return Key in Sort_Indicator | Sort_State;
         when Indicators_Command =>
            return Key in Sort_Id | Sort_Name | Sort_Violations | Sort_Unknown | Sort_Affected;
         when Indicator_Command =>
            return Key in Sort_Name | Sort_Id | Sort_State;
         when Problems_Command =>
            return Key in Sort_Severity | Sort_Indicator | Sort_Project;
         when Waivers_Command =>
            return Key in Sort_Indicator | Sort_Project;
         when Regressions_Command =>
            return Key in Sort_Project | Sort_Indicator | Sort_Kind;
         when Compare_Command =>
            return Key in Sort_Indicator | Sort_Kind;
         when Trends_Command =>
            return Key in Sort_Run | Sort_Project;
         when History_Command =>
            return Key = Sort_Run;
         when Help_Command | Completion_Command | Version_Command =>
            return False;
      end case;
   end Allowed;

   function Parse (Arguments : String_Vectors.Vector) return Options renames Parsing.Parse;

   function Parse_Date (Text : String) return Ada.Calendar.Time renames Parsing.Parse_Date;
end Ada_Quality_Summary.Options;