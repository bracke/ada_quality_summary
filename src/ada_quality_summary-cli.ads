with Ada.Strings.Unbounded;
with Ada_Quality_Summary.Options;

--  Command orchestration: parse, load one snapshot, build the report, render it completely, then write it.
package Ada_Quality_Summary.CLI is
   --  Command orchestration for ada-quality-summary.

   Success_Exit   : constant := 0;
   --  Report generated successfully, including reports that contain quality violations.
   Argument_Exit  : constant := 2;
   --  Invalid command, option, or filter.
   Report_Exit    : constant := 3;
   --  Reporting or serialization failure.
   Data_Exit      : constant := 4;
   --  Database, schema, locking, or data-integrity failure.

   type Outcome is record
      Exit_Code : Natural := Success_Exit;
      Output    : Ada.Strings.Unbounded.Unbounded_String;
      Errors    : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   --  Complete result of one invocation, produced before anything is written.
   --  @field Exit_Code Process exit code.
   --  @field Output Standard output text.
   --  @field Errors Standard error text.

   function Execute (Arguments : Ada_Quality_Summary.Options.String_Vectors.Vector) return Outcome;
   --  Parse arguments, load one snapshot, build the report, and render it completely, without any output.
   --  @param Arguments Command-line arguments without the program name.
   --  @return Exit code with the complete standard output and standard error text.

   function Run return Natural;
   --  Execute the command line of the current process and write its output.
   --  @return Process exit code; output-stream failures yield the reporting exit code.
end Ada_Quality_Summary.CLI;
