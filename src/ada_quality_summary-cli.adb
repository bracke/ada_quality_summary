with Ada.Command_Line;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.IO_Exceptions;
with Ada.Text_IO;
with Ada.Text_IO.Text_Streams;
with Ada_Quality_Summary.Completion;
with Ada_Quality_Summary.Criteria;
with Ada_Quality_Summary.JSON;
with Ada_Quality_Summary.Limits;
with Ada_Quality_Summary.Reports;
with Ada_Quality_Summary.Repository;
with Ada_Quality_Summary.SARIF;
with Ada_Quality_Summary.Terminal;
with Ada_Quality_Summary.Terminal.Environment;
with Ada_Quality_Summary.Text;

package body Ada_Quality_Summary.CLI is
   use Ada.Strings.Unbounded;
   use Ada_Quality_Summary.Criteria;
   use Ada_Quality_Summary.Options;
   use Ada_Quality_Summary.Text;

   LF : constant Character := Character'Val (10);

   function Diagnostic (Text : String) return String is
     (Message ("error.prefix", [Arg ("message", Text)]) & LF);

   --  Write the complete, already rendered report as raw bytes and flush it. The text is streamed in slices, so
   --  writing does not need another copy of a report that may be as large as the JSON size limit.
   procedure Write (Text : Unbounded_String) is
      Chunk  : constant := 65_536;
      Stream : constant Ada.Text_IO.Text_Streams.Stream_Access :=
        Ada.Text_IO.Text_Streams.Stream (Ada.Text_IO.Standard_Output);
      First  : Positive := 1;
   begin
      while First <= Length (Text) loop
         declare
            Last : constant Natural := Natural'Min (Length (Text), First + Chunk - 1);
         begin
            String'Write (Stream, Slice (Text, First, Last));
            First := Last + 1;
         end;
      end loop;
      Ada.Text_IO.Flush (Ada.Text_IO.Standard_Output);
   end Write;

   function Database_Path (Invocation : Options.Options) return String is
   begin
      if Invocation.Has_Database then
         return To_String (Invocation.Database);
      elsif Ada.Environment_Variables.Exists (Database_Variable) and then
        Ada.Environment_Variables.Value (Database_Variable)'Length > 0
      then
         return Ada.Environment_Variables.Value (Database_Variable);
      end if;
      return Default_Database;
   end Database_Path;

   function Column (Text : String; Width : Positive := 26) return String is
     ((if Text'Length >= Width then Text & " " else Text & [1 .. Width - Text'Length => ' ']));

   function Option_Line (Option : Option_Kind) return String is
     ("  " & Column (Usage (Option), 40) & Message ("help.opt." & Help_Key (Option)) & LF);

   function Help_Text (Invocation : Options.Options) return String is
      Result : Unbounded_String;
   begin
      if not Invocation.Has_Topic then
         Append (Result, Message ("help.usage") & LF & LF & Message ("help.commands") & LF);
         for Command in Named_Command loop
            Append (Result, "  " & Column (Usage (Command)) & Message ("help.cmd." & Name (Command)) & LF);
         end loop;
         Append (Result, LF & Message ("help.options") & LF);
         for Option in Option_Kind loop
            Append (Result, Option_Line (Option));
         end loop;
         Append (Result, LF & Message ("help.exit") & LF);
         return To_String (Result);
      end if;
      declare
         Topic : constant Command_Kind := Invocation.Topic;
         Keys  : Unbounded_String;
      begin
         Append (Result, Message ("help.command_usage", [Arg ("usage", Usage (Topic))]) & LF & LF &
                   "  " & Message ("help.cmd." & Name (Topic)) & LF & LF & Message ("help.accepts") & LF);
         for Option in Option_Kind loop
            if Accepts (Topic, Option) then
               Append (Result, Option_Line (Option));
            end if;
         end loop;
         for Sort in Sort_Name .. Sort_Key'Last loop
            if Allowed (Topic, Sort) then
               Append (Keys, (if Length (Keys) = 0 then "" else ", ") & Image (Sort));
            end if;
         end loop;
         if Length (Keys) > 0 then
            Append (Result, LF & Message ("help.sort_keys", [Arg ("keys", To_String (Keys))]) & LF);
         end if;
         return To_String (Result);
      end;
   end Help_Text;

   function Render (Item : Reports.Report; Invocation : Options.Options) return String is
     (case Invocation.Format is
         when JSON_Format => JSON.Render (Item, Invocation.Pretty),
         when SARIF_Format => SARIF.Render (Item, Ada.Directories.Current_Directory, Invocation.Pretty),
         when Terminal_Format =>
            Bounded (Terminal.Render
                       (Item,
                        (Width    => Terminal.Environment.Detect_Width (Invocation.Width),
                         Color    => Terminal.Environment.Use_Color (Invocation.Color),
                         Unicode  => Terminal.Environment.Unicode_Locale,
                         Layout   => Invocation.Layout,
                         Markdown => False)),
                     Limits.Maximum_Output_Bytes),
         when Markdown_Format =>
            Bounded (Terminal.Render (Item, (Layout => Invocation.Layout, Markdown => True, others => <>)),
                     Limits.Maximum_Output_Bytes));

   --  The --fail-on conditions that hold, as `regressions (2), violations (1)`, or empty when none holds.
   function Gate_Failures (Item : Reports.Report; Invocation : Options.Options) return String is
      Result : Unbounded_String;
   begin
      for Condition in Gate_Condition loop
         if Invocation.Fail_On (Condition) and then Item.Gate (Condition) > 0 then
            Append (Result, (if Length (Result) = 0 then "" else ", ") & Image (Condition) & " (" &
                      Decimal (Long_Long_Integer (Item.Gate (Condition))) & ")");
         end if;
      end loop;
      return To_String (Result);
   end Gate_Failures;

   function Render_Report (Invocation : Options.Options) return Outcome is
      Path  : constant String := Database_Path (Invocation);
      Store : Repository.Repository;
   begin
      Repository.Open (Store, Path);
      declare
         Data     : constant Repository.Snapshot := Repository.Load (Store);
         Item     : constant Reports.Report := Reports.Build (Data, Invocation, Path);
         Failures : constant String := Gate_Failures (Item, Invocation);
      begin
         Repository.Close (Store);
         --  A failing gate still writes the complete report; only the exit status and a diagnostic differ.
         return (Exit_Code => (if Failures = "" then Success_Exit else Gate_Exit),
                 Output    => To_Unbounded_String (Render (Item, Invocation)),
                 Errors    => (if Failures = "" then Null_Unbounded_String
                               else To_Unbounded_String
                                 (Diagnostic (Message ("error.gate_failed", [Arg ("conditions", Failures)])))));
      end;
   end Render_Report;

   function Execute (Arguments : String_Vectors.Vector) return Outcome is
      Invocation : Options.Options;
   begin
      Invocation := Options.Parse (Arguments);
      if Invocation.Command in Report_Command then
         return Render_Report (Invocation);
      end if;
      return
        (Exit_Code => Success_Exit,
         Output    => To_Unbounded_String
           (case Invocation.Command is
               when Help_Command => Help_Text (Invocation),
               when Completion_Command => Completion.Script (Invocation.Shell),
               when others => Message ("help.version", [Arg ("version", Version)]) & LF),
         Errors    => Null_Unbounded_String);
   exception
      when Error : Argument_Error =>
         return (Argument_Exit, Null_Unbounded_String,
                 To_Unbounded_String (Diagnostic (Ada.Exceptions.Exception_Message (Error)) &
                                      Message ("error.hint") & LF));
      when Error : Data_Error =>
         return (Data_Exit, Null_Unbounded_String,
                 To_Unbounded_String (Diagnostic (Ada.Exceptions.Exception_Message (Error))));
      when Error : Report_Error =>
         return (Report_Exit, Null_Unbounded_String,
                 To_Unbounded_String (Diagnostic (Ada.Exceptions.Exception_Message (Error))));
      when Error : others =>  --  AQ: audited exception boundary
         return (Report_Exit, Null_Unbounded_String,
                 To_Unbounded_String
                   (Diagnostic
                      (Message ("error.internal", [Arg ("message", Ada.Exceptions.Exception_Message (Error))]))));
   end Execute;

   function Run return Natural is
      Arguments : String_Vectors.Vector;
   begin
      for Index in 1 .. Ada.Command_Line.Argument_Count loop
         Arguments.Append (Ada.Command_Line.Argument (Index));
      end loop;
      declare
         Result : constant Outcome := Execute (Arguments);
      begin
         --  Retrieval, aggregation, and serialization are complete before the first byte is written. A diagnostic
         --  follows the report, so a failing quality gate is explained after the report it judged.
         if Length (Result.Output) > 0 then
            Write (Result.Output);
         end if;
         if Length (Result.Errors) > 0 then
            Ada.Text_IO.Put (Ada.Text_IO.Standard_Error, To_String (Result.Errors));
         end if;
         return Result.Exit_Code;
      exception
         when Error : Ada.IO_Exceptions.Device_Error | Ada.IO_Exceptions.Use_Error |
              Ada.IO_Exceptions.End_Error | Ada.IO_Exceptions.Status_Error =>
            Ada.Text_IO.Put
              (Ada.Text_IO.Standard_Error,
               Diagnostic (Message ("error.output", [Arg ("message", Ada.Exceptions.Exception_Message (Error))])));
            return Report_Exit;
      end;
   end Run;
end Ada_Quality_Summary.CLI;
