with Ada.Strings.Unbounded;
with Ada_Quality_Summary.Criteria;
with Ada_Quality_Summary.Model;
with Ada_Quality_Summary.Text;

package body Ada_Quality_Summary.Completion is
   use Ada.Strings.Unbounded;
   use Ada_Quality_Summary.Options;

   LF : constant Character := Character'Val (10);

   function Choices (Option : Option_Kind) return String is
      Result : Unbounded_String;

      procedure Add (Word : String) is
      begin
         Append (Result, (if Length (Result) = 0 then "" else " ") & Word);
      end Add;
   begin
      case Option is
         when Status_Option =>
            for State in Ada_Quality_Summary.Model.Project_Quality_State loop
               Add (Ada_Quality_Summary.Model.Image (State));
            end loop;
         when Sort_Option =>
            for Key in Ada_Quality_Summary.Criteria.Sort_Name .. Ada_Quality_Summary.Criteria.Sort_Key'Last loop
               Add (Ada_Quality_Summary.Criteria.Image (Key));
            end loop;
         when Fail_On_Option =>
            for Condition in Ada_Quality_Summary.Criteria.Gate_Condition loop
               Add (Ada_Quality_Summary.Criteria.Image (Condition));
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
         Append (Result, (if Length (Result) = 0 then "" else " ") & Name (Command));
      end loop;
      return To_String (Result);
   end Command_Words;

   function Shell_Words return String is ("bash zsh fish");

   function Bash_Script return String is
      Result       : Unbounded_String;
      Option_Words : Unbounded_String;
   begin
      Append (Result, "# bash completion for " & Program & LF &
                "_ada_quality_summary() {" & LF &
                "    local cur=""${COMP_WORDS[COMP_CWORD]}"" prev=""${COMP_WORDS[COMP_CWORD-1]}""" & LF &
                "    case ""$prev"" in" & LF);
      for Option in Option_Kind loop
         Append (Option_Words, (if Length (Option_Words) = 0 then "" else " ") & Spelling (Option));
         if Is_Path (Option) then
            Append (Result, "        " & Spelling (Option) & ") COMPREPLY=($(compgen -f -- ""$cur"")); return ;;" &
                      LF);
         elsif Choices (Option) /= "" then
            Append (Result, "        " & Spelling (Option) & ") COMPREPLY=($(compgen -W '" & Choices (Option) &
                      "' -- ""$cur"")); return ;;" & LF);
         elsif Takes_Value (Option) then
            Append (Result, "        " & Spelling (Option) & ") return ;;" & LF);
         end if;
      end loop;
      Append (Result,
              "        completion) COMPREPLY=($(compgen -W '" & Shell_Words & "' -- ""$cur"")); return ;;" & LF &
                "        help) COMPREPLY=($(compgen -W '" & Command_Words & "' -- ""$cur"")); return ;;" & LF &
                "    esac" & LF &
                "    if [[ ""$cur"" == -* ]]; then" & LF &
                "        COMPREPLY=($(compgen -W '" & To_String (Option_Words) & "' -- ""$cur""))" & LF &
                "    else" & LF &
                "        COMPREPLY=($(compgen -W '" & Command_Words & "' -- ""$cur""))" & LF &
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
      Append (Result, "#compdef " & Program & LF & "_ada_quality_summary() {" & LF & "    _arguments -s \" & LF);
      for Option in Option_Kind loop
         Append (Result, "        '" & Spelling (Option) & "[" & Zsh_Help (Help (Option)) & "]" &
                   (if Is_Path (Option) then ":path:_files"
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
      Result : Unbounded_String := To_Unbounded_String ("# fish completion for " & Program & LF & Prefix & " -f" & LF);
   begin
      for Command in Named_Command loop
         Append (Result, Prefix & " -n __fish_use_subcommand -a " & Name (Command) & " -d '" &
                   Quoted (Help (Command)) & "'" & LF);
      end loop;
      Append (Result, Prefix & " -n '__fish_seen_subcommand_from completion' -a '" & Shell_Words & "'" & LF &
                Prefix & " -n '__fish_seen_subcommand_from help' -a '" & Command_Words & "'" & LF);
      for Option in Option_Kind loop
         declare
            Long : constant String := Spelling (Option);
         begin
            Append (Result, Prefix & " -l " & Long (Long'First + 2 .. Long'Last) &
                      (if Is_Path (Option) then " -r -F"
                       elsif Choices (Option) /= "" then " -x -a '" & Choices (Option) & "'"
                       elsif Takes_Value (Option) then " -x"
                       else "") & " -d '" & Quoted (Help (Option)) & "'" & LF);
         end;
      end loop;
      return To_String (Result);
   end Fish_Script;

   function Script (Shell : Shell_Kind) return String is
     (case Shell is
         when Bash_Shell => Bash_Script,
         when Zsh_Shell => Zsh_Script,
         when Fish_Shell => Fish_Script);
end Ada_Quality_Summary.Completion;
