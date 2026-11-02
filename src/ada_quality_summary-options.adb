with Ada.Calendar.Formatting;
with Ada.Strings.Fixed;
with Ada_Quality_Summary.Text;

package body Ada_Quality_Summary.Options is
   use Ada.Strings.Unbounded;
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
         when Regressions_Command => "regressions",
         when Trends_Command => "trends",
         when History_Command => "history",
         when Help_Command => "help",
         when Version_Command => "version");

   function Report_Of (Command : Report_Command) return Ada_Quality_Summary.Model.Report_Kind is
     (case Command is
         when Summary_Command => Ada_Quality_Summary.Model.Summary_Report,
         when Projects_Command => Ada_Quality_Summary.Model.Projects_Report,
         when Project_Command => Ada_Quality_Summary.Model.Project_Report,
         when Indicators_Command => Ada_Quality_Summary.Model.Indicators_Report,
         when Indicator_Command => Ada_Quality_Summary.Model.Indicator_Report,
         when Problems_Command => Ada_Quality_Summary.Model.Problems_Report,
         when Regressions_Command => Ada_Quality_Summary.Model.Regressions_Report,
         when Trends_Command => Ada_Quality_Summary.Model.Trends_Report,
         when History_Command => Ada_Quality_Summary.Model.History_Report);

   function Is_Collection (Command : Command_Kind) return Boolean is
     (Command in Summary_Command | Projects_Command | Indicators_Command | Indicator_Command | Problems_Command |
                 Regressions_Command | Trends_Command);

   function Is_Historical (Command : Command_Kind) return Boolean is
     (Command in Trends_Command | History_Command);

   function Image (Key : Sort_Key) return String is
     (case Key is
         when Default_Sort => "default",
         when Sort_Name => "name",
         when Sort_Id => "id",
         when Sort_Path => "path",
         when Sort_Quality => "quality",
         when Sort_Violations => "violations",
         when Sort_Unknown => "unknown",
         when Sort_Findings => "findings",
         when Sort_Affected => "affected",
         when Sort_Severity => "severity",
         when Sort_Indicator => "indicator",
         when Sort_Project => "project",
         when Sort_Kind => "kind",
         when Sort_Run => "run",
         when Sort_State => "state");

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
         when Regressions_Command =>
            return Key in Sort_Project | Sort_Indicator | Sort_Kind;
         when Trends_Command =>
            return Key in Sort_Run | Sort_Project;
         when History_Command =>
            return Key = Sort_Run;
         when Help_Command | Version_Command =>
            return False;
      end case;
   end Allowed;

   procedure Fail (Key : String; Args : Argument_List := No_Arguments) is
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
         declare
            Result : constant Ada.Calendar.Time :=
              Ada.Calendar.Formatting.Time_Of (Year, Month, Day, 0, 0, 0, Time_Zone => 0);
         begin
            --  Time_Of normalizes nothing, but reject dates such as 2026-02-30 explicitly by round trip.
            if Ada.Calendar.Formatting.Image (Result, Time_Zone => 0) (1 .. 10) /= Text then
               Fail ("error.invalid_date", [Arg ("value", Text)]);
            end if;
            return Result;
         end;
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

   function Parse_Command (Text : String; Command : out Command_Kind) return Boolean is
   begin
      for Candidate in Summary_Command .. Help_Command loop
         if Name (Candidate) = Text then
            Command := Candidate;
            return True;
         end if;
      end loop;
      Command := Summary_Command;
      return False;
   end Parse_Command;

   function Parse (Arguments : String_Vectors.Vector) return Options is
      Result       : Options;
      Has_Command  : Boolean := False;
      Help_Flag    : Boolean := False;
      Version_Flag : Boolean := False;
      Has_Format, Has_Width, Has_Sort, Has_Limit, Has_Since, Has_Until : Boolean := False;
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
      begin
         if Option = "--help" then
            No_Inline;
            Help_Flag := True;
         elsif Option = "--version" then
            No_Inline;
            Version_Flag := True;
         elsif Option = "--database" then
            Once (Result.Has_Database, Option);
            Result.Database := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
            if Length (Result.Database) = 0 then
               Fail ("error.empty_database");
            end if;
         elsif Option = "--format" then
            Once (Has_Format, Option);
            declare
               Value : constant String := Value_Of (Option, Inline, Has_Inline);
            begin
               if Value = "terminal" then
                  Result.Format := Terminal_Format;
               elsif Value = "json" then
                  Result.Format := JSON_Format;
               else
                  Fail ("error.invalid_choice", [Arg ("option", Option), Arg ("value", Value),
                        Arg ("choices", "terminal, json")]);
               end if;
            end;
         elsif Option = "--color" or else Option = "--no-color" then
            Once (Result.Has_Color, "--color");
            if Option = "--no-color" then
               No_Inline;
               Result.Color := Color_Never;
            else
               declare
                  Value : constant String := Value_Of (Option, Inline, Has_Inline);
               begin
                  if Value = "auto" then
                     Result.Color := Color_Auto;
                  elsif Value = "always" then
                     Result.Color := Color_Always;
                  elsif Value = "never" then
                     Result.Color := Color_Never;
                  else
                     Fail ("error.invalid_choice", [Arg ("option", Option), Arg ("value", Value),
                           Arg ("choices", "auto, always, never")]);
                  end if;
               end;
            end if;
         elsif Option = "--layout" then
            Once (Result.Has_Layout, Option);
            declare
               Value : constant String := Value_Of (Option, Inline, Has_Inline);
            begin
               if Value = "compact" then
                  Result.Layout := Compact_Layout;
               elsif Value = "normal" then
                  Result.Layout := Normal_Layout;
               elsif Value = "detailed" then
                  Result.Layout := Detailed_Layout;
               else
                  Fail ("error.invalid_choice", [Arg ("option", Option), Arg ("value", Value),
                        Arg ("choices", "compact, normal, detailed")]);
               end if;
            end;
         elsif Option = "--width" then
            Once (Has_Width, Option);
            Result.Width := Parse_Natural (Option, Value_Of (Option, Inline, Has_Inline));
            if Result.Width not in Minimum_Width .. Maximum_Width then
               Fail ("error.width_range", [Arg ("minimum", Minimum_Width), Arg ("maximum", Maximum_Width)]);
            end if;
         elsif Option = "--include-removed" then
            No_Inline;
            Flag (1, Option);
            Result.Include_Removed := True;
         elsif Option = "--enabled-only" then
            No_Inline;
            Flag (2, Option);
            Result.Enabled_Only := True;
         elsif Option = "--reverse" then
            No_Inline;
            Flag (3, Option);
            Result.Reverse_Order := True;
         elsif Option = "--pretty" then
            No_Inline;
            Flag (4, Option);
            Result.Pretty := True;
         elsif Option = "--project" then
            Once (Result.Has_Project, Option);
            Result.Project := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
         elsif Option = "--status" then
            Once (Result.Has_Status, Option);
            declare
               Value : constant String := Value_Of (Option, Inline, Has_Inline);
            begin
               if not Ada_Quality_Summary.Model.Parse (Value, Result.Status) then
                  Fail ("error.invalid_choice", [Arg ("option", Option), Arg ("value", Value),
                        Arg ("choices", "passing, violations, incomplete, unassessed")]);
               end if;
            end;
         elsif Option = "--sort" then
            Once (Has_Sort, Option);
            declare
               Value : constant String := Value_Of (Option, Inline, Has_Inline);
               Found : Boolean := False;
            begin
               for Key in Sort_Name .. Sort_Key'Last loop
                  if Image (Key) = Value then
                     Result.Sort := Key;
                     Found := True;
                  end if;
               end loop;
               if not Found then
                  Fail ("error.unknown_sort", [Arg ("value", Value)]);
               end if;
            end;
         elsif Option = "--limit" then
            Once (Has_Limit, Option);
            Result.Limit := Parse_Natural (Option, Value_Of (Option, Inline, Has_Inline));
         elsif Option = "--since" then
            Once (Has_Since, Option);
            Result.Since := (Present => True, Value => Parse_Date (Value_Of (Option, Inline, Has_Inline)));
         elsif Option = "--until" then
            Once (Has_Until, Option);
            Result.Until_Date :=
              (Present => True, Value => Parse_Date (Value_Of (Option, Inline, Has_Inline)) + 86_400.0);
         else
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
           Result.Command in Project_Command | Indicator_Command | History_Command | Help_Command
         then
            Result.Target := To_Unbounded_String (Item);
            Result.Has_Target := True;
         else
            Fail ("error.unexpected_argument", [Arg ("argument", Item)]);
         end if;
      end Handle_Positional;
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

      if Version_Flag then
         Result.Command := Version_Command;
         return Result;
      elsif Help_Flag then
         if Has_Command and then Result.Command /= Help_Command then
            Result.Target := To_Unbounded_String (Name (Result.Command));
            Result.Has_Target := True;
         end if;
         Result.Command := Help_Command;
      end if;

      if Result.Command = Help_Command then
         if Result.Has_Target then
            declare
               Topic : Command_Kind;
            begin
               if not Parse_Command (To_String (Result.Target), Topic) then
                  Fail ("error.unknown_command", [Arg ("command", To_String (Result.Target))]);
               end if;
            end;
         end if;
         return Result;
      end if;

      if Result.Command in Project_Command | History_Command and then not Result.Has_Target then
         Fail ("error.missing_project", [Arg ("command", Name (Result.Command))]);
      elsif Result.Command = Indicator_Command and then not Result.Has_Target then
         Fail ("error.missing_indicator");
      elsif Result.Has_Project and then not Is_Collection (Result.Command) then
         Fail ("error.option_not_allowed", [Arg ("option", "--project"), Arg ("command", Name (Result.Command))]);
      elsif Result.Has_Status and then not Is_Collection (Result.Command) then
         Fail ("error.option_not_allowed", [Arg ("option", "--status"), Arg ("command", Name (Result.Command))]);
      elsif (Has_Since or else Has_Until) and then not Is_Historical (Result.Command) then
         Fail ("error.option_not_allowed",
               [Arg ("option", (if Has_Since then "--since" else "--until")), Arg ("command", Name (Result.Command))]);
      elsif Result.Since.Present and then Result.Until_Date.Present and then
        Result.Since.Value >= Result.Until_Date.Value
      then
         Fail ("error.date_order");
      elsif Result.Format = JSON_Format and then (Result.Has_Layout or else Has_Width) then
         Fail ("error.terminal_only", [Arg ("option", (if Result.Has_Layout then "--layout" else "--width"))]);
      elsif Result.Format = Terminal_Format and then Result.Pretty then
         Fail ("error.json_only", [Arg ("option", "--pretty")]);
      elsif not Allowed (Result.Command, Result.Sort) then
         Fail ("error.sort_not_allowed", [Arg ("value", Image (Result.Sort)), Arg ("command", Name (Result.Command))]);
      elsif Result.Reverse_Order and then Result.Command = Help_Command then
         Fail ("error.option_not_allowed", [Arg ("option", "--reverse"), Arg ("command", Name (Result.Command))]);
      end if;
      return Result;
   end Parse;
end Ada_Quality_Summary.Options;
