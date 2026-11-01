with Ada.Command_Line;
with Ada_Quality_Summary.CLI;

procedure Main is
   --  Executable entry point for ada-quality-summary.
begin
   Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Exit_Status (Ada_Quality_Summary.CLI.Run));
end Main;
