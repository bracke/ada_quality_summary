with Ada.Characters.Handling;
with Ada.Strings.Unbounded;
with Ada_Quality_Summary.Options;
with Ada_Quality_Summary.Text;

package body Aqs_Manual is
   use Ada.Strings.Unbounded;
   use Ada_Quality_Summary.Options;

   LF : constant Character := Character'Val (10);

   --  Text safe in roff: backslashes and hyphens are escaped, and a line cannot start a request.
   function Roff (Text : String) return String is
      Result : Unbounded_String;
   begin
      for C of Text loop
         case C is
            when '\' => Append (Result, "\e");
            when '-' => Append (Result, "\-");
            when others => Append (Result, C);
         end case;
      end loop;
      if Length (Result) > 0 and then Element (Result, 1) in '.' | ''' then
         return "\&" & To_String (Result);
      end if;
      return To_String (Result);
   end Roff;

   function Message (Key : String) return String is (Ada_Quality_Summary.Text.Message (Key));

   procedure Tagged_Paragraph (Result : in out Unbounded_String; Tag, Text : String) is
   begin
      Append (Result, ".TP" & LF & Tag & LF & Roff (Text) & LF);
   end Tagged_Paragraph;

   type Name_Access is access constant String;

   Environment : constant array (1 .. 3) of Name_Access :=
     [new String'("ADA_QUALITY_DATABASE"), new String'("NO_COLOR"), new String'("COLUMNS")];

   function Page return String is
      Result : Unbounded_String;
   begin
      Append (Result, ".TH ADA\-QUALITY\-SUMMARY 1 """" ""ada\-quality\-summary " &
                Roff (Ada_Quality_Summary.Version) & """ ""User Commands""" & LF &
                ".SH NAME" & LF &
                "ada\-quality\-summary \- " & Roff (Message ("manual.name")) & LF &
                ".SH SYNOPSIS" & LF &
                ".B ada\-quality\-summary" & LF & "[\fIOPTIONS\fR] [\fICOMMAND\fR [\fIARGUMENTS\fR]]" & LF &
                ".SH DESCRIPTION" & LF &
                Roff (Message ("manual.description")) & LF &
                ".SH COMMANDS" & LF);
      for Command in Named_Command loop
         Tagged_Paragraph (Result, ".B " & Roff (Usage (Command)), Message ("help.cmd." & Name (Command)));
      end loop;
      Append (Result, ".SH OPTIONS" & LF);
      for Option in Option_Kind loop
         Tagged_Paragraph
           (Result,
            (if Value_Name (Option) = "" then ".B " & Roff (Spelling (Option))
             else ".BI " & Roff (Spelling (Option)) & " "" " & Roff (Value_Name (Option)) & """"),
            Message ("help.opt." & Help_Key (Option)));
      end loop;
      Append (Result, ".SH ENVIRONMENT" & LF);
      for Variable of Environment loop
         Tagged_Paragraph (Result, ".B " & Variable.all,
                           Message ("manual.env." & Ada.Characters.Handling.To_Lower (Variable.all)));
      end loop;
      Append (Result, ".SH EXIT STATUS" & LF & Roff (Message ("help.exit")) & LF &
                ".SH SEE ALSO" & LF & ".BR ada\-quality (1)" & LF);
      return To_String (Result);
   end Page;
end Aqs_Manual;
