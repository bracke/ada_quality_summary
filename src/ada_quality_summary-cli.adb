with Ada.Command_Line;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.IO_Exceptions;
with Ada.Text_IO;
with Ada.Text_IO.Text_Streams;
with Ada_Quality_Summary.JSON;
with Ada_Quality_Summary.Reports;
with Ada_Quality_Summary.Repository;
with Ada_Quality_Summary.Terminal;
with Ada_Quality_Summary.Text;

package body Ada_Quality_Summary.CLI is
   use Ada.Strings.Unbounded;
   use Ada_Quality_Summary.Options;
   use Ada_Quality_Summary.Text;

   LF : constant Character := Character'Val (10);

   function Diagnostic (Text : String) return String is
     (Message ("error.prefix", [Arg ("message", Text)]) & LF);

   --  Write the complete, already rendered report as raw bytes and flush it.
   procedure Write (Text : String) is
      Stream : constant Ada.Text_IO.Text_Streams.Stream_Access :=
        Ada.Text_IO.Text_Streams.Stream (Ada.Text_IO.Standard_Output);
   begin
      String'Write (Stream, Text);
      Ada.Text_IO.Flush (Ada.Text_IO.Standard_Output);
   end Write;

   function Database_Path (Invocation : Options.Options) return String is
   begin
      if Invocation.Has_Database then
         return To_String (Invocation.Database);
      elsif Ada.Environment_Variables.Exists ("ADA_QUALITY_DATABASE") and then
        Ada.Environment_Variables.Value ("ADA_QUALITY_DATABASE")'Length > 0
      then
         return Ada.Environment_Variables.Value ("ADA_QUALITY_DATABASE");
      end if;
      return ".ada-quality.db";
   end Database_Path;

   function Column (Text : String; Width : Positive := 24) return String is
     ((if Text'Length >= Width then Text & " " else Text & [1 .. Width - Text'Length => ' ']));

   function Usage_Of (Command : Command_Kind) return String is
     (case Command is
         when Project_Command => "project PROJECT",
         when Indicator_Command => "indicator ID",
         when History_Command => "history PROJECT",
         when Help_Command => "help [COMMAND]",
         when others => Name (Command));

   type Text_Access is access constant String;

   type Option_Help is record
      Spelling : Text_Access;
      Key      : Text_Access;
   end record;

   Option_List : constant array (Positive range <>) of Option_Help :=
     [(new String'("--database PATH"), new String'("database")),
      (new String'("--format terminal|json"), new String'("format")),
      (new String'("--color auto|always|never"), new String'("color")),
      (new String'("--no-color"), new String'("no_color")),
      (new String'("--layout compact|normal|detailed"), new String'("layout")),
      (new String'("--width N"), new String'("width")),
      (new String'("--include-removed"), new String'("include_removed")),
      (new String'("--enabled-only"), new String'("enabled_only")),
      (new String'("--project PROJECT"), new String'("project")),
      (new String'("--status STATUS"), new String'("status")),
      (new String'("--sort KEY"), new String'("sort")),
      (new String'("--reverse"), new String'("reverse")),
      (new String'("--limit N"), new String'("limit")),
      (new String'("--since DATE"), new String'("since")),
      (new String'("--until DATE"), new String'("until")),
      (new String'("--pretty"), new String'("pretty")),
      (new String'("--help"), new String'("help")),
      (new String'("--version"), new String'("version"))];

   function Accepts (Command : Command_Kind; Key : String) return Boolean is
     (if Key in "project" | "status" then Is_Collection (Command)
      elsif Key in "since" | "until" then Is_Historical (Command)
      elsif Key = "sort" then (for some Sort in Sort_Name .. Sort_Key'Last => Allowed (Command, Sort))
      else True);

   function Help_Text (Invocation : Options.Options) return String is
      Result : Unbounded_String;
   begin
      if not Invocation.Has_Target then
         Append (Result, Message ("help.usage") & LF & LF & Message ("help.commands") & LF);
         for Command in Summary_Command .. Help_Command loop
            Append (Result, "  " & Column (Usage_Of (Command)) & Message ("help.cmd." & Name (Command)) & LF);
         end loop;
         Append (Result, LF & Message ("help.options") & LF);
         for Item of Option_List loop
            Append (Result, "  " & Column (Item.Spelling.all, 36) & Message ("help.opt." & Item.Key.all) & LF);
         end loop;
         Append (Result, LF & Message ("help.exit") & LF);
         return To_String (Result);
      end if;
      declare
         Topic : Command_Kind := Summary_Command;
         Keys  : Unbounded_String;
      begin
         for Command in Summary_Command .. Help_Command loop
            if Name (Command) = To_String (Invocation.Target) then
               Topic := Command;
            end if;
         end loop;
         Append (Result, Message ("help.command_usage", [Arg ("usage", Usage_Of (Topic))]) & LF & LF &
                   "  " & Message ("help.cmd." & Name (Topic)) & LF & LF & Message ("help.accepts") & LF);
         for Item of Option_List loop
            if Accepts (Topic, Item.Key.all) then
               Append (Result, "  " & Column (Item.Spelling.all, 36) & Message ("help.opt." & Item.Key.all) & LF);
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

   function Render_Report (Invocation : Options.Options) return String is
      Path  : constant String := Database_Path (Invocation);
      Store : Repository.Repository;
   begin
      Repository.Open (Store, Path);
      declare
         Data : constant Repository.Snapshot := Repository.Load (Store);
         Item : constant Reports.Report := Reports.Build (Data, Invocation, Path);
      begin
         Repository.Close (Store);
         case Invocation.Format is
            when JSON_Format =>
               return JSON.Render (Item, Invocation.Pretty);
            when Terminal_Format =>
               return Terminal.Render
                 (Item,
                  (Width   => Terminal.Detect_Width (Invocation.Width),
                   Color   => Terminal.Use_Color (Invocation.Color),
                   Unicode => Terminal.Unicode_Locale,
                   Layout  => Invocation.Layout));
         end case;
      end;
   end Render_Report;

   function Execute (Arguments : String_Vectors.Vector) return Outcome is
      Invocation : Options.Options;
   begin
      Invocation := Options.Parse (Arguments);
      return
        (Exit_Code => Success_Exit,
         Output    => To_Unbounded_String
           (case Invocation.Command is
               when Help_Command => Help_Text (Invocation),
               when Version_Command => Message ("help.version", [Arg ("version", Version)]) & LF,
               when Report_Command => Render_Report (Invocation)),
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
         if Length (Result.Errors) > 0 then
            Ada.Text_IO.Put (Ada.Text_IO.Standard_Error, To_String (Result.Errors));
         end if;
         --  Retrieval, aggregation, and serialization are complete before the first byte is written.
         if Length (Result.Output) > 0 then
            Write (To_String (Result.Output));
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
