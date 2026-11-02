with Ada.Command_Line;
with Ada_Quality_Summary.CLI;

--  Executable entry point for ada-quality-summary.
procedure Main
   --  Runs the CLI and returns its exit code.
is
begin
   Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Exit_Status (Ada_Quality_Summary.CLI.Run));
end Main;
