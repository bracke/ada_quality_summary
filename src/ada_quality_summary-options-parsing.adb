with Ada.Calendar.Formatting;
with Ada.Strings.Fixed;
with Ada_Quality_Summary.Text;

package body Ada_Quality_Summary.Options.Parsing is
   use Ada.Strings.Unbounded;
   use Ada_Quality_Summary.Criteria;
   use Ada_Quality_Summary.Text;
   use type Ada.Calendar.Time;

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

   type Given_Set is array (Option_Kind) of Boolean;

   type Parser is record
      Arguments    : String_Vectors.Vector;
      Index        : Positive := 1;
      Result       : Options;
      Given        : Given_Set := [others => False];
      Has_Command  : Boolean := False;
      Help_Flag    : Boolean := False;
      Version_Flag : Boolean := False;
      Positionals  : String_Vectors.Vector;
   end record;
   --  The state of one parse: the arguments, the position in them, the options given so far, and the positional
   --  arguments after the command word, which are assigned once the command is known.

   --  Read the option at P.Index, and its value from `--name=value` or the following argument.
   procedure Handle_Option (P : in out Parser; Item : String) is
      Arguments    : String_Vectors.Vector renames P.Arguments;
      Index        : Positive renames P.Index;
      Result       : Options renames P.Result;
      Given        : Given_Set renames P.Given;
      Help_Flag    : Boolean renames P.Help_Flag;
      Version_Flag : Boolean renames P.Version_Flag;

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

      --  Record that Option was given; every option except --help and --version may be given once.
      procedure Once (Option : Option_Kind) is
      begin
         if Given (Option) then
            Fail ("error.duplicate_option", [Arg ("option", Spelling (Option))]);
         end if;
         Given (Option) := True;
      end Once;

      --  `--color` and `--no-color` select one setting, so together they are a duplicate of the one given second.
      procedure Once_Color (Option : Option_Kind) is
      begin
         if Given (Color_Option) or else Given (No_Color_Option) then
            Fail ("error.duplicate_option", [Arg ("option", Spelling (Option))]);
         end if;
         Given (Option) := True;
      end Once_Color;

      procedure Read_Option (Item : String) is
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
               Once (Include_Removed_Option);
               Result.Include_Removed := True;
            elsif Option = Spelling (Enabled_Only_Option) then
               Once (Enabled_Only_Option);
               Result.Enabled_Only := True;
            elsif Option = Spelling (Reverse_Option) then
               Once (Reverse_Option);
               Result.Reverse_Order := True;
            elsif Option = Spelling (Pretty_Option) then
               Once (Pretty_Option);
               Result.Pretty := True;
            elsif Option = Spelling (No_Color_Option) then
               Once_Color (No_Color_Option);
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
               Once (Format_Option);
               Result.Format := Parse_Format (Option, Value);
            elsif Option = Spelling (Color_Option) then
               Once_Color (Color_Option);
               Result.Color := Parse_Color (Option, Value);
            elsif Option = Spelling (Layout_Option) then
               Once (Layout_Option);
               Result.Layout := Parse_Layout (Option, Value);
            elsif Option = Spelling (Width_Option) then
               Once (Width_Option);
               Result.Width := Parse_Natural (Option, Value);
               if Result.Width not in Minimum_Width .. Maximum_Width then
                  Fail ("error.width_range", [Arg ("minimum", Minimum_Width), Arg ("maximum", Maximum_Width)]);
               end if;
            elsif Option = Spelling (Sort_Option) then
               Once (Sort_Option);
               Result.Sort := Parse_Sort (Value);
            elsif Option = Spelling (Limit_Option) then
               Once (Limit_Option);
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
               Once (Database_Option);
               Result.Database := To_Unbounded_String (Value);
               if Length (Result.Database) = 0 then
                  Fail ("error.empty_database");
               end if;
            elsif Option = Spelling (Project_Option) then
               Once (Project_Option);
               Result.Project := To_Unbounded_String (Value);
            elsif Option = Spelling (Status_Option) then
               Once (Status_Option);
               Result.Status := Parse_Status (Option, Value);
            elsif Option = Spelling (Since_Option) then
               Once (Since_Option);
               Result.Since := (Present => True, Value => Parse_Date (Value));
            elsif Option = Spelling (Until_Option) then
               Once (Until_Option);
               Result.Until_Date := (Present => True, Value => Parse_Date (Value));
            elsif Option = Spelling (Fail_On_Option) then
               Once (Fail_On_Option);
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
      end Read_Option;
   begin
      Read_Option (Item);
   end Handle_Option;

   --  Read every argument: options, the command word, and the positional arguments after it.
   procedure Read_Arguments (P : in out Parser) is
   begin
      while P.Index <= Natural (P.Arguments.Length) loop
         declare
            Item : constant String := P.Arguments (P.Index);
         begin
            if Item'Length >= 2 and then Item (Item'First .. Item'First + 1) = "--" then
               Handle_Option (P, Item);
            elsif Item'Length > 1 and then Item (Item'First) = '-' then
               Fail ("error.unknown_option", [Arg ("option", Item)]);
            elsif P.Has_Command then
               P.Positionals.Append (Item);
            elsif Parse_Command (Item, P.Result.Command) then
               P.Has_Command := True;
            else
               Fail ("error.unknown_command", [Arg ("command", Item)]);
            end if;
         end;
         P.Index := P.Index + 1;
      end loop;
      P.Result.Has_Database := P.Given (Database_Option);
      P.Result.Has_Project := P.Given (Project_Option);
      P.Result.Has_Status := P.Given (Status_Option);
   end Read_Arguments;

   --  Turn `--version` and `--help` into their commands; return True when the command's own positional arguments
   --  no longer apply.
   function Resolve_Help_And_Version (P : in out Parser) return Boolean is
   begin
      if P.Version_Flag then
         if Natural (P.Arguments.Length) > 1 then
            Fail ("error.version_alone");
         end if;
         P.Result.Command := Version_Command;
         return True;
      elsif P.Help_Flag and then P.Has_Command and then P.Result.Command /= Help_Command then
         P.Result.Topic := P.Result.Command;
         P.Result.Has_Topic := True;
         P.Result.Command := Help_Command;
         return True;
      elsif P.Help_Flag then
         P.Result.Command := Help_Command;
      end if;
      return False;
   end Resolve_Help_And_Version;

   --  Assign the positional arguments to the fields the command names; too many or too few is an argument error.
   procedure Assign_Positionals (P : in out Parser) is
      Command : constant Command_Kind := P.Result.Command;
      Count   : constant Natural := Natural (P.Positionals.Length);
      Wanted  : constant Natural :=
        (case Command is
            when Project_Command | History_Command | Indicator_Command | Completion_Command => 1,
            when Compare_Command => 2,
            when Help_Command => Natural'Min (Count, 1),
            when others => 0);

      function Positional (Index : Positive) return UString is (To_Unbounded_String (P.Positionals (Index)));
   begin
      if Count > Wanted then
         Fail ("error.unexpected_argument", [Arg ("argument", P.Positionals (Wanted + 1))]);
      elsif Count < Wanted and then Command in Project_Command | History_Command then
         Fail ("error.missing_project", [Arg ("command", Name (Command))]);
      elsif Count < Wanted then
         Fail (case Command is
                  when Indicator_Command => "error.missing_indicator",
                  when Compare_Command => "error.missing_assessments",
                  when others => "error.missing_shell");
      end if;
      case Command is
         when Project_Command | History_Command =>
            P.Result.Target_Project := Positional (1);
         when Indicator_Command =>
            P.Result.Indicator := Positional (1);
         when Compare_Command =>
            P.Result.Baseline_Run := Positional (1);
            P.Result.Current_Run := Positional (2);
         when Completion_Command =>
            P.Result.Shell := Parse_Shell (Name (Completion_Command), P.Positionals (1));
         when Help_Command =>
            if Count = 1 then
               if not Parse_Command (P.Positionals (1), P.Result.Topic) then
                  Fail ("error.unknown_command", [Arg ("command", P.Positionals (1))]);
               end if;
               P.Result.Has_Topic := True;
            end if;
         when others =>
            null;
      end case;
   end Assign_Positionals;

   --  Reject every given option Command does not accept, by the one rule help applies too.
   procedure Check_Scope (P : Parser; Command : Command_Kind) is
   begin
      for Option in Option_Kind loop
         if P.Given (Option) and then not Accepts (Command, Option) then
            Fail ("error.option_not_allowed", [Arg ("option", Spelling (Option)), Arg ("command", Name (Command))]);
         end if;
      end loop;
   end Check_Scope;

   --  Reject an empty date range.
   procedure Check_Dates (P : Parser) is
   begin
      if P.Result.Since.Present and then P.Result.Until_Date.Present and then
        P.Result.Since.Value > P.Result.Until_Date.Value
      then
         Fail ("error.date_order");
      end if;
   end Check_Dates;

   --  Reject presentation options that the output format or Command does not accept.
   procedure Check_Presentation (P : Parser; Command : Command_Kind) is
      Result : Options renames P.Result;
   begin
      if Result.Format /= Terminal_Format and then P.Given (Width_Option) then
         Fail ("error.terminal_only", [Arg ("option", Spelling (Width_Option))]);
      elsif Result.Format in JSON_Format | SARIF_Format and then P.Given (Layout_Option) then
         Fail ("error.text_only", [Arg ("option", Spelling (Layout_Option))]);
      elsif Result.Format in Terminal_Format | Markdown_Format and then Result.Pretty then
         Fail ("error.json_only", [Arg ("option", Spelling (Pretty_Option))]);
      elsif Result.Format = SARIF_Format and then Command in Report_Command and then Command /= Problems_Command then
         Fail ("error.sarif_command", [Arg ("command", Name (Command))]);
      elsif not Allowed (Command, Result.Sort) then
         Fail ("error.sort_not_allowed", [Arg ("value", Image (Result.Sort)), Arg ("command", Name (Command))]);
      end if;
   end Check_Presentation;

   --  Validate the options against Command: for help, the command it describes, or help itself without a topic,
   --  so a misplaced or misspelled option is reported rather than silently ignored.
   procedure Check_Options (P : Parser; Command : Command_Kind) is
   begin
      Check_Scope (P, Command);
      Check_Dates (P);
      Check_Presentation (P, Command);
   end Check_Options;

   function Parse (Arguments : String_Vectors.Vector) return Options is
      P : Parser;
   begin
      P.Arguments := Arguments;
      Read_Arguments (P);
      if not Resolve_Help_And_Version (P) then
         Assign_Positionals (P);
      end if;
      case P.Result.Command is
         when Version_Command =>
            null;
         when Help_Command =>
            Check_Options (P, (if P.Result.Has_Topic then P.Result.Topic else Help_Command));
         when others =>
            Check_Options (P, P.Result.Command);
      end case;
      return P.Result;
   end Parse;
end Ada_Quality_Summary.Options.Parsing;
