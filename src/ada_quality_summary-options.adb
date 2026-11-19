with Ada.Calendar.Formatting;
with Ada.Strings.Fixed;
with Ada_Quality_Summary.Text;

package body Ada_Quality_Summary.Options is
   use Ada.Strings.Unbounded;
   use Ada_Quality_Summary.Criteria;
   use Ada_Quality_Summary.Text;
   use type Ada.Calendar.Time;

   function Name (Command : Command_Kind) return String is
     (case Command is
         when Summary_Command => "summary",
         when Projects_Command => "projects",
         when Project_Command => "project",
         when Indicators_Command => "indicators",
         when Indicator_Command => "indicator",
         when Problems_Command => "problems",
         when Waivers_Command => "waivers",
         when Regressions_Command => "regressions",
         when Compare_Command => "compare",
         when Trends_Command => "trends",
         when History_Command => "history",
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

   function Report_Of (Command : Report_Command) return Ada_Quality_Summary.Model.Report_Kind is
     (case Command is
         when Summary_Command => Ada_Quality_Summary.Model.Summary_Report,
         when Projects_Command => Ada_Quality_Summary.Model.Projects_Report,
         when Project_Command => Ada_Quality_Summary.Model.Project_Report,
         when Indicators_Command => Ada_Quality_Summary.Model.Indicators_Report,
         when Indicator_Command => Ada_Quality_Summary.Model.Indicator_Report,
         when Problems_Command => Ada_Quality_Summary.Model.Problems_Report,
         when Waivers_Command => Ada_Quality_Summary.Model.Waivers_Report,
         when Regressions_Command => Ada_Quality_Summary.Model.Regressions_Report,
         when Compare_Command => Ada_Quality_Summary.Model.Compare_Report,
         when Trends_Command => Ada_Quality_Summary.Model.Trends_Report,
         when History_Command => Ada_Quality_Summary.Model.History_Report);

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
         when Project_Option | Status_Option => Is_Collection (Command),
         when Since_Option | Until_Option => Is_Historical (Command),
         when Fail_On_Option => Command in Report_Command,
         when Sort_Option => (for some Key in Sort_Name .. Sort_Key'Last => Allowed (Command, Key)),
         when others => True);

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

   procedure Fail (Key : String; Args : Argument_List := No_Arguments) with No_Return is
   begin
      raise Argument_Error with Message (Key, Args);
   end Fail;

   function Parse_Date (Text : String) return Ada.Calendar.Time is
      function Digits_Of (First, Last : Positive) return Natural is
         Result : Natural := 0;
      begin
         for Index in First .. Last loop
            if Text (Index) not in '0' .. '9' then
               Fail ("error.invalid_date", [Arg ("value", Text)]);
            end if;
            Result := Result * 10 + (Character'Pos (Text (Index)) - Character'Pos ('0'));
         end loop;
         return Result;
      end Digits_Of;
   begin
      if Text'Length /= 10 or else Text (Text'First + 4) /= '-' or else Text (Text'First + 7) /= '-' then
         Fail ("error.invalid_date", [Arg ("value", Text)]);
      end if;
      declare
         F     : constant Positive := Text'First;
         Year  : constant Natural := Digits_Of (F, F + 3);
         Month : constant Natural := Digits_Of (F + 5, F + 6);
         Day   : constant Natural := Digits_Of (F + 8, F + 9);
      begin
         if Year not in Ada.Calendar.Year_Number or else Month not in Ada.Calendar.Month_Number or else
           Day not in Ada.Calendar.Day_Number
         then
            Fail ("error.invalid_date", [Arg ("value", Text)]);
         end if;
         --  Time_Of raises Time_Error for a day the month does not have, such as 2026-02-30.
         return Ada.Calendar.Formatting.Time_Of (Year, Month, Day, 0, 0, 0, Time_Zone => 0);
      end;
   exception
      when Ada.Calendar.Time_Error =>
         raise Argument_Error with Message ("error.invalid_date", [Arg ("value", Text)]);
   end Parse_Date;

   function Parse_Natural (Option, Text : String) return Natural is
   begin
      if Text'Length = 0 or else Text'Length > 9 then
         Fail ("error.invalid_number", [Arg ("option", Option), Arg ("value", Text)]);
      end if;
      for C of Text loop
         if C not in '0' .. '9' then
            Fail ("error.invalid_number", [Arg ("option", Option), Arg ("value", Text)]);
         end if;
      end loop;
      return Natural'Value (Text);
   end Parse_Natural;

   --  Parse the value of an option that takes one of a fixed set of spellings.
   generic
      type Choice is (<>);
      Names : access constant String;
      --  Spellings in the order of Choice, separated by ", ".
   function Parse_Choice (Option, Value : String) return Choice;

   function Parse_Choice (Option, Value : String) return Choice is
      Start : Positive := Names'First;
   begin
      for Candidate in Choice loop
         declare
            Stop : constant Natural := Ada.Strings.Fixed.Index (Names.all, ", ", From => Start);
            Last : constant Natural := (if Stop = 0 then Names'Last else Stop - 1);
         begin
            if Names (Start .. Last) = Value then
               return Candidate;
            end if;
            Start := Last + 3;
         end;
      end loop;
      Fail ("error.invalid_choice", [Arg ("option", Option), Arg ("value", Value), Arg ("choices", Names.all)]);
   end Parse_Choice;

   Format_Names : aliased constant String := "terminal, json, markdown, sarif";
   Color_Names  : aliased constant String := "auto, always, never";
   Layout_Names : aliased constant String := "compact, normal, detailed";
   Shell_Names  : aliased constant String := "bash, zsh, fish";
   Gate_Names   : aliased constant String := "regressions, violations, incomplete, unassessed";

   function Parse_Format is new Parse_Choice (Output_Format, Format_Names'Access);
   function Parse_Color is new Parse_Choice (Color_Mode, Color_Names'Access);
   function Parse_Layout is new Parse_Choice (Layout_Mode, Layout_Names'Access);
   function Parse_Shell is new Parse_Choice (Shell_Kind, Shell_Names'Access);
   function Parse_Gate is new Parse_Choice (Gate_Condition, Gate_Names'Access);

   --  Parse a comma-separated list of `--fail-on` conditions; naming a condition twice is harmless.
   function Parse_Gates (Option, Value : String) return Gate_Set is
      Result : Gate_Set := No_Gate;
      Start  : Positive := Value'First;
   begin
      for Index in Value'First .. Value'Last + 1 loop
         if Index > Value'Last or else Value (Index) = ',' then
            Result (Parse_Gate (Option, Value (Start .. Index - 1))) := True;
            Start := Index + 1;
         end if;
      end loop;
      return Result;
   end Parse_Gates;

   function Parse_Command (Text : String; Command : out Command_Kind) return Boolean is
   begin
      for Candidate in Named_Command loop
         if Name (Candidate) = Text then
            Command := Candidate;
            return True;
         end if;
      end loop;
      Command := Summary_Command;
      return False;
   end Parse_Command;

   function Parse_Sort (Value : String) return Sort_Key is
   begin
      for Key in Sort_Name .. Sort_Key'Last loop
         if Image (Key) = Value then
            return Key;
         end if;
      end loop;
      Fail ("error.unknown_sort", [Arg ("value", Value)]);
   end Parse_Sort;

   function Parse_Status (Option, Value : String) return Ada_Quality_Summary.Model.Project_Quality_State is
      Status : Ada_Quality_Summary.Model.Project_Quality_State;
   begin
      if not Ada_Quality_Summary.Model.Parse (Value, Status) then
         Fail ("error.invalid_choice", [Arg ("option", Option), Arg ("value", Value),
               Arg ("choices", "passing, violations, incomplete, unassessed")]);
      end if;
      return Status;
   end Parse_Status;

   function Parse (Arguments : String_Vectors.Vector) return Options is
      Result       : Options;
      Has_Command  : Boolean := False;
      Help_Flag    : Boolean := False;
      Version_Flag : Boolean := False;
      Has_Format, Has_Width, Has_Sort, Has_Limit, Has_Since, Has_Until, Has_Fail_On : Boolean := False;
      Seen_Flags   : array (1 .. 4) of Boolean := [others => False];
      Index        : Positive := 1;

      --  Return the option value from `--name=value` or the following argument. A following argument that is itself
      --  an option is not taken as the value; a value starting with `--` must use the `--name=value` form.
      function Value_Of (Option : String; Inline : String; Has_Inline : Boolean) return String is
      begin
         if Has_Inline then
            return Inline;
         elsif Index >= Natural (Arguments.Length)
           or else Ada.Strings.Fixed.Head (Arguments (Index + 1), 2) = "--"
         then
            Fail ("error.missing_value", [Arg ("option", Option)]);
         end if;
         Index := Index + 1;
         return Arguments (Index);
      end Value_Of;

      procedure Once (Seen : in out Boolean; Option : String) is
      begin
         if Seen then
            Fail ("error.duplicate_option", [Arg ("option", Option)]);
         end if;
         Seen := True;
      end Once;

      procedure Flag (Slot : Positive; Option : String) is
      begin
         Once (Seen_Flags (Slot), Option);
      end Flag;

      procedure Handle_Option (Item : String) is
         Equals     : constant Natural := Ada.Strings.Fixed.Index (Item, "=");
         Option     : constant String := (if Equals = 0 then Item else Item (Item'First .. Equals - 1));
         Inline     : constant String := (if Equals = 0 then "" else Item (Equals + 1 .. Item'Last));
         Has_Inline : constant Boolean := Equals /= 0;

         procedure No_Inline is
         begin
            if Has_Inline then
               Fail ("error.unexpected_value", [Arg ("option", Option)]);
            end if;
         end No_Inline;

         function Value return String is (Value_Of (Option, Inline, Has_Inline));

         --  Handle a flag without a value; return False when Option is not a flag.
         function Flag_Option return Boolean is
         begin
            if Option = Spelling (Help_Option) then
               Help_Flag := True;
            elsif Option = Spelling (Version_Option) then
               Version_Flag := True;
            elsif Option = Spelling (Include_Removed_Option) then
               Flag (1, Option);
               Result.Include_Removed := True;
            elsif Option = Spelling (Enabled_Only_Option) then
               Flag (2, Option);
               Result.Enabled_Only := True;
            elsif Option = Spelling (Reverse_Option) then
               Flag (3, Option);
               Result.Reverse_Order := True;
            elsif Option = Spelling (Pretty_Option) then
               Flag (4, Option);
               Result.Pretty := True;
            elsif Option = Spelling (No_Color_Option) then
               Once (Result.Has_Color, Spelling (Color_Option));
               Result.Color := Color_Never;
            else
               return False;
            end if;
            No_Inline;
            return True;
         end Flag_Option;

         --  Handle an option that selects output presentation; return False when Option is not one.
         function Output_Option return Boolean is
         begin
            if Option = Spelling (Format_Option) then
               Once (Has_Format, Option);
               Result.Format := Parse_Format (Option, Value);
            elsif Option = Spelling (Color_Option) then
               Once (Result.Has_Color, Option);
               Result.Color := Parse_Color (Option, Value);
            elsif Option = Spelling (Layout_Option) then
               Once (Result.Has_Layout, Option);
               Result.Layout := Parse_Layout (Option, Value);
            elsif Option = Spelling (Width_Option) then
               Once (Has_Width, Option);
               Result.Width := Parse_Natural (Option, Value);
               if Result.Width not in Minimum_Width .. Maximum_Width then
                  Fail ("error.width_range", [Arg ("minimum", Minimum_Width), Arg ("maximum", Maximum_Width)]);
               end if;
            elsif Option = Spelling (Sort_Option) then
               Once (Has_Sort, Option);
               Result.Sort := Parse_Sort (Value);
            elsif Option = Spelling (Limit_Option) then
               Once (Has_Limit, Option);
               Result.Limit := Parse_Natural (Option, Value);
            else
               return False;
            end if;
            return True;
         end Output_Option;

         --  Handle an option that selects the database or the reported population; return False when Option is
         --  not one.
         function Selection_Option return Boolean is
         begin
            if Option = Spelling (Database_Option) then
               Once (Result.Has_Database, Option);
               Result.Database := To_Unbounded_String (Value);
               if Length (Result.Database) = 0 then
                  Fail ("error.empty_database");
               end if;
            elsif Option = Spelling (Project_Option) then
               Once (Result.Has_Project, Option);
               Result.Project := To_Unbounded_String (Value);
            elsif Option = Spelling (Status_Option) then
               Once (Result.Has_Status, Option);
               Result.Status := Parse_Status (Option, Value);
            elsif Option = Spelling (Since_Option) then
               Once (Has_Since, Option);
               Result.Since := (Present => True, Value => Parse_Date (Value));
            elsif Option = Spelling (Until_Option) then
               Once (Has_Until, Option);
               Result.Until_Date := (Present => True, Value => Parse_Date (Value));
            elsif Option = Spelling (Fail_On_Option) then
               Once (Has_Fail_On, Option);
               Result.Fail_On := Parse_Gates (Option, Value);
            else
               return False;
            end if;
            return True;
         end Selection_Option;
      begin
         if not (Flag_Option or else Output_Option or else Selection_Option) then
            Fail ("error.unknown_option", [Arg ("option", Option)]);
         end if;
      end Handle_Option;

      procedure Handle_Positional (Item : String) is
      begin
         if not Has_Command then
            if not Parse_Command (Item, Result.Command) then
               Fail ("error.unknown_command", [Arg ("command", Item)]);
            end if;
            Has_Command := True;
         elsif not Result.Has_Target and then
           Result.Command in Project_Command | Indicator_Command | History_Command | Help_Command |
                             Compare_Command | Completion_Command
         then
            Result.Target := To_Unbounded_String (Item);
            Result.Has_Target := True;
            if Result.Command = Completion_Command then
               Result.Shell := Parse_Shell (Name (Completion_Command), Item);
            end if;
         elsif not Result.Has_Second and then Result.Command = Compare_Command then
            Result.Second := To_Unbounded_String (Item);
            Result.Has_Second := True;
         else
            Fail ("error.unexpected_argument", [Arg ("argument", Item)]);
         end if;
      end Handle_Positional;

      --  A detail command needs its PROJECT or ID.
      procedure Check_Target is
      begin
         if Result.Command in Project_Command | History_Command and then not Result.Has_Target then
            Fail ("error.missing_project", [Arg ("command", Name (Result.Command))]);
         elsif Result.Command = Indicator_Command and then not Result.Has_Target then
            Fail ("error.missing_indicator");
         elsif Result.Command = Compare_Command and then not Result.Has_Second then
            Fail ("error.missing_assessments");
         elsif Result.Command = Completion_Command and then not Result.Has_Target then
            Fail ("error.missing_shell");
         end if;
      end Check_Target;

      procedure Check_Scope is
      begin
         if Result.Has_Project and then not Accepts (Result.Command, Project_Option) then
            Fail ("error.option_not_allowed",
                  [Arg ("option", Spelling (Project_Option)), Arg ("command", Name (Result.Command))]);
         elsif Result.Has_Status and then not Accepts (Result.Command, Status_Option) then
            Fail ("error.option_not_allowed",
                  [Arg ("option", Spelling (Status_Option)), Arg ("command", Name (Result.Command))]);
         elsif Has_Fail_On and then not Accepts (Result.Command, Fail_On_Option) then
            Fail ("error.option_not_allowed",
                  [Arg ("option", Spelling (Fail_On_Option)), Arg ("command", Name (Result.Command))]);
         end if;
      end Check_Scope;

      --  Reject a date range the command does not accept or that is empty.
      procedure Check_Dates is
      begin
         if (Has_Since or else Has_Until) and then not Accepts (Result.Command, Since_Option) then
            Fail ("error.option_not_allowed",
                  [Arg ("option", Spelling (if Has_Since then Since_Option else Until_Option)),
                   Arg ("command", Name (Result.Command))]);
         elsif Result.Since.Present and then Result.Until_Date.Present and then
           Result.Since.Value > Result.Until_Date.Value
         then
            Fail ("error.date_order");
         end if;
      end Check_Dates;

      --  Reject presentation options that the output format or command does not accept.
      procedure Check_Presentation is
         Command : constant String := Name (Result.Command);
      begin
         if Result.Format /= Terminal_Format and then Has_Width then
            Fail ("error.terminal_only", [Arg ("option", Spelling (Width_Option))]);
         elsif Result.Format in JSON_Format | SARIF_Format and then Result.Has_Layout then
            Fail ("error.text_only", [Arg ("option", Spelling (Layout_Option))]);
         elsif Result.Format in Terminal_Format | Markdown_Format and then Result.Pretty then
            Fail ("error.json_only", [Arg ("option", Spelling (Pretty_Option))]);
         elsif Result.Format = SARIF_Format and then Result.Command in Report_Command and then
           Result.Command /= Problems_Command
         then
            Fail ("error.sarif_command", [Arg ("command", Command)]);
         elsif not Allowed (Result.Command, Result.Sort) then
            Fail ("error.sort_not_allowed", [Arg ("value", Image (Result.Sort)), Arg ("command", Command)]);
         elsif Result.Reverse_Order and then Result.Command = Help_Command then
            Fail ("error.option_not_allowed", [Arg ("option", Spelling (Reverse_Option)), Arg ("command", Command)]);
         end if;
      end Check_Presentation;

      procedure Read_Arguments is
      begin
         while Index <= Natural (Arguments.Length) loop
            declare
               Item : constant String := Arguments (Index);
            begin
               if Item'Length >= 2 and then Item (Item'First .. Item'First + 1) = "--" then
                  Handle_Option (Item);
               elsif Item'Length > 1 and then Item (Item'First) = '-' then
                  Fail ("error.unknown_option", [Arg ("option", Item)]);
               else
                  Handle_Positional (Item);
               end if;
            end;
            Index := Index + 1;
         end loop;
      end Read_Arguments;

      --  Turn `--version` and `--help` into their commands; return True when no further validation applies.
      function Resolve_Help_And_Version return Boolean is
      begin
         if Version_Flag then
            if Natural (Arguments.Length) > 1 then
               Fail ("error.version_alone");
            end if;
            Result.Command := Version_Command;
            return True;
         elsif Help_Flag then
            if Has_Command and then Result.Command /= Help_Command then
               Result.Target := To_Unbounded_String (Name (Result.Command));
               Result.Has_Target := True;
            end if;
            Result.Command := Help_Command;
         end if;
         if Result.Command = Help_Command and then Result.Has_Target then
            declare
               Topic : Command_Kind;
            begin
               if not Parse_Command (To_String (Result.Target), Topic) then
                  Fail ("error.unknown_command", [Arg ("command", To_String (Result.Target))]);
               end if;
            end;
         end if;
         return Result.Command = Help_Command;
      end Resolve_Help_And_Version;
      --  Help validates its options against the command it describes, or against help itself without a topic, so a
      --  misplaced or misspelled option is reported rather than silently ignored.
      procedure Check_Help_Options is
         Topic : Command_Kind := Help_Command;
      begin
         if Result.Has_Target and then not Parse_Command (To_String (Result.Target), Topic) then
            Topic := Help_Command;
         end if;
         Result.Command := Topic;
         Check_Scope;
         Check_Dates;
         Check_Presentation;
         Result.Command := Help_Command;
      end Check_Help_Options;
   begin
      Read_Arguments;
      if Resolve_Help_And_Version then
         if Result.Command = Help_Command then
            Check_Help_Options;
         end if;
         return Result;
      end if;
      Check_Target;
      Check_Scope;
      Check_Dates;
      Check_Presentation;
      return Result;
   end Parse;
end Ada_Quality_Summary.Options;
