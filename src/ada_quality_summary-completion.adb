with Ada.Strings.Unbounded;
with Ada_Quality_Summary.Criteria;
with Ada_Quality_Summary.Model;
with Ada_Quality_Summary.Text;

package body Ada_Quality_Summary.Completion is
   use Ada.Strings.Unbounded;
   use Ada_Quality_Summary.Options;

   LF : constant Character := Character'Val (10);

   procedure Add (List : in out Unbounded_String; Word : String; Separator : String := " ") is
   begin
      Append (List, (if Length (List) = 0 then "" else Separator) & Word);
   end Add;

   function Choices (Option : Option_Kind) return String is
      Result : Unbounded_String;
   begin
      case Option is
         when Status_Option =>
            for State in Ada_Quality_Summary.Model.Project_Quality_State loop
               Add (Result, Ada_Quality_Summary.Model.Image (State));
            end loop;
         when Sort_Option =>
            for Key in Ada_Quality_Summary.Criteria.Sort_Name .. Ada_Quality_Summary.Criteria.Sort_Key'Last loop
               Add (Result, Ada_Quality_Summary.Criteria.Image (Key));
            end loop;
         when Fail_On_Option =>
            for Condition in Ada_Quality_Summary.Criteria.Gate_Condition loop
               Add (Result, Ada_Quality_Summary.Criteria.Image (Condition));
            end loop;
         when others =>
            --  A value name with alternatives, such as `auto|always|never`, lists the choices.
            if (for some C of Value_Name (Option) => C = '|') then
               for C of Value_Name (Option) loop
                  Append (Result, (if C = '|' then ' ' else C));
               end loop;
            end if;
      end case;
      return To_String (Result);
   end Choices;

   function Sort_Keys (Command : Command_Kind) return String is
      Result : Unbounded_String;
   begin
      for Key in Ada_Quality_Summary.Criteria.Sort_Name .. Ada_Quality_Summary.Criteria.Sort_Key'Last loop
         if Allowed (Command, Key) then
            Add (Result, Ada_Quality_Summary.Criteria.Image (Key));
         end if;
      end loop;
      return To_String (Result);
   end Sort_Keys;

   function Takes_Value (Option : Option_Kind) return Boolean is (Value_Name (Option) /= "");

   function Is_Path (Option : Option_Kind) return Boolean is (Value_Name (Option) = "PATH");

   function Help (Option : Option_Kind) return String is
     (Ada_Quality_Summary.Text.Message ("help.opt." & Help_Key (Option)));

   function Help (Command : Command_Kind) return String is
     (Ada_Quality_Summary.Text.Message ("help.cmd." & Name (Command)));

   --  Text inside single quotes: a quote ends the string, so it is closed, escaped, and reopened.
   function Quoted (Text : String) return String is
      Result : Unbounded_String;
   begin
      for C of Text loop
         Append (Result, (if C = ''' then "'\''" else [C]));
      end loop;
      return To_String (Result);
   end Quoted;

   function Command_Words return String is
      Result : Unbounded_String;
   begin
      for Command in Named_Command loop
         Add (Result, Name (Command));
      end loop;
      return To_String (Result);
   end Command_Words;

   --  The options whose value is the next word, as a shell case pattern such as `--database|--format`.
   function Value_Options return String is
      Result : Unbounded_String;
   begin
      for Option in Option_Kind loop
         if Takes_Value (Option) then
            Add (Result, Spelling (Option), "|");
         end if;
      end loop;
      return To_String (Result);
   end Value_Options;

   function Shell_Words return String is ("bash zsh fish");

   --  Shell code shared by bash and zsh that sets `command` to the command word among Words, skipping options and
   --  their values; without one, the default command. Open and Close delimit a case pattern.
   function Command_Loop (Words, Open, Close : String) return String is
     ("    local word skip= command=" & Name (Summary_Command) & LF &
      "    for word in " & Words & "; do" & LF &
      "        if [[ -n ""$skip"" ]]; then skip=; continue; fi" & LF &
      "        case ""$word"" in" & LF &
      "            " & Open & Value_Options & Close & " skip=1 ;;" & LF &
      "            " & Open & "-*" & Close & " ;;" & LF &
      "            " & Open & "*" & Close & " command=""$word""; break ;;" & LF &
      "        esac" & LF &
      "    done" & LF);

   type Offer_Function is access function (Keys : String) return String;

   --  A case statement that offers each command's sort keys through Offer.
   function Sort_Cases (Open, Close : String; Offer : Offer_Function) return String is
      Result : Unbounded_String := To_Unbounded_String ("    case ""$command"" in" & LF);
   begin
      for Command in Named_Command loop
         if Sort_Keys (Command) /= "" then
            Append (Result, "        " & Open & Name (Command) & Close & " " & Offer (Sort_Keys (Command)) & " ;;" &
                      LF);
         end if;
      end loop;
      return To_String (Result) & "    esac" & LF;
   end Sort_Cases;

   function Bash_Offer (Keys : String) return String is
     ("COMPREPLY=($(compgen -W '" & Keys & "' -- ""$cur""))");

   function Zsh_Offer (Keys : String) return String is ("compadd -- " & Keys);

   function Bash_Script return String is
      Result       : Unbounded_String;
      Option_Words : Unbounded_String;
   begin
      Append (Result, "# bash completion for " & Program & LF &
                "_ada_quality_summary_sort_keys() {" & LF &
                Command_Loop ("""${COMP_WORDS[@]:1:COMP_CWORD-1}""", "", ")") &
                Sort_Cases ("", ")", Bash_Offer'Access) & "}" & LF &
                "_ada_quality_summary() {" & LF &
                "    local cur=""${COMP_WORDS[COMP_CWORD]}"" prev=""${COMP_WORDS[COMP_CWORD-1]}""" & LF &
                "    case ""$prev"" in" & LF);
      for Option in Option_Kind loop
         Add (Option_Words, Spelling (Option));
         if Option = Sort_Option then
            Append (Result, "        " & Spelling (Option) & ") _ada_quality_summary_sort_keys; return ;;" & LF);
         elsif Is_Path (Option) then
            Append (Result, "        " & Spelling (Option) & ") COMPREPLY=($(compgen -f -- ""$cur"")); return ;;" &
                      LF);
         elsif Choices (Option) /= "" then
            Append (Result, "        " & Spelling (Option) & ") " & Bash_Offer (Choices (Option)) & "; return ;;" &
                      LF);
         elsif Takes_Value (Option) then
            Append (Result, "        " & Spelling (Option) & ") return ;;" & LF);
         end if;
      end loop;
      Append (Result,
              "        completion) " & Bash_Offer (Shell_Words) & "; return ;;" & LF &
                "        help) " & Bash_Offer (Command_Words) & "; return ;;" & LF &
                "    esac" & LF &
                "    if [[ ""$cur"" == -* ]]; then" & LF &
                "        " & Bash_Offer (To_String (Option_Words)) & LF &
                "    else" & LF &
                "        " & Bash_Offer (Command_Words) & LF &
                "    fi" & LF &
                "}" & LF &
                "complete -F _ada_quality_summary " & Program & LF);
      return To_String (Result);
   end Bash_Script;

   --  `[` and `]` delimit a zsh option description, so they are escaped inside it.
   function Zsh_Help (Text : String) return String is
      Result : Unbounded_String;
   begin
      for C of Quoted (Text) loop
         Append (Result, (if C in '[' | ']' then "\" & C else [C]));
      end loop;
      return To_String (Result);
   end Zsh_Help;

   function Zsh_Script return String is
      Result : Unbounded_String;
   begin
      Append (Result, "#compdef " & Program & LF &
                "_ada_quality_summary_sort_keys() {" & LF &
                Command_Loop ("""${(@)words[2,CURRENT-1]}""", "(", ")") &
                Sort_Cases ("(", ")", Zsh_Offer'Access) & "}" & LF &
                "_ada_quality_summary() {" & LF & "    _arguments -s \" & LF);
      for Option in Option_Kind loop
         Append (Result, "        '" & Spelling (Option) & "[" & Zsh_Help (Help (Option)) & "]" &
                   (if Option = Sort_Option then ":key:_ada_quality_summary_sort_keys"
                    elsif Is_Path (Option) then ":path:_files"
                    elsif Choices (Option) /= "" then ":" & Help_Key (Option) & ":(" & Choices (Option) & ")"
                    elsif Takes_Value (Option) then ":" & Value_Name (Option) & ": "
                    else "") & "' \" & LF);
      end loop;
      Append (Result, "        '1:command:(" & Command_Words & ")' \" & LF &
                "        '2:argument: '" & LF & "}" & LF & "_ada_quality_summary ""$@""" & LF);
      return To_String (Result);
   end Zsh_Script;

   function Fish_Script return String is
      Prefix : constant String := "complete -c " & Program;
      Result : Unbounded_String :=
        To_Unbounded_String ("# fish completion for " & Program & LF & Prefix & " -f" & LF);

      function Long (Option : Option_Kind) return String is
        (Spelling (Option) (Spelling (Option)'First + 2 .. Spelling (Option)'Last));
   begin
      for Command in Named_Command loop
         Append (Result, Prefix & " -n __fish_use_subcommand -a " & Name (Command) & " -d '" &
                   Quoted (Help (Command)) & "'" & LF);
      end loop;
      Append (Result, Prefix & " -n '__fish_seen_subcommand_from completion' -a '" & Shell_Words & "'" & LF &
                Prefix & " -n '__fish_seen_subcommand_from help' -a '" & Command_Words & "'" & LF);
      for Option in Option_Kind loop
         if Option /= Sort_Option then
            Append (Result, Prefix & " -l " & Long (Option) &
                      (if Is_Path (Option) then " -r -F"
                       elsif Choices (Option) /= "" then " -x -a '" & Choices (Option) & "'"
                       elsif Takes_Value (Option) then " -x"
                       else "") & " -d '" & Quoted (Help (Option)) & "'" & LF);
         end if;
      end loop;
      --  Sort keys depend on the command; before any command word, the default command's keys apply.
      for Command in Named_Command loop
         if Sort_Keys (Command) /= "" then
            Append (Result, Prefix & " -n '" &
                      (if Command = Summary_Command then "__fish_use_subcommand"
                       else "__fish_seen_subcommand_from " & Name (Command)) &
                      "' -l " & Long (Sort_Option) & " -x -a '" & Sort_Keys (Command) & "' -d '" &
                      Quoted (Help (Sort_Option)) & "'" & LF);
         end if;
      end loop;
      return To_String (Result);
   end Fish_Script;

   function Script (Shell : Shell_Kind) return String is
     (case Shell is
         when Bash_Shell => Bash_Script,
         when Zsh_Shell => Zsh_Script,
         when Fish_Shell => Fish_Script);
end Ada_Quality_Summary.Completion;
