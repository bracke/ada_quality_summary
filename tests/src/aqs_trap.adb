with Ada.Command_Line;
with Ada.Environment_Variables;
with Ada.Text_IO;

--  Stand-in for an external measurement tool. Each invocation appends its name to the file named by
--  AQS_TRAP_LOG and fails, so a test can prove that reporting spawns no assessment tool.
procedure Aqs_Trap is
   Log : Ada.Text_IO.File_Type;
begin
   if Ada.Environment_Variables.Exists ("AQS_TRAP_LOG") then
      begin
         Ada.Text_IO.Open (Log, Ada.Text_IO.Append_File, Ada.Environment_Variables.Value ("AQS_TRAP_LOG"));
      exception
         when Ada.Text_IO.Name_Error =>
            Ada.Text_IO.Create (Log, Ada.Text_IO.Out_File, Ada.Environment_Variables.Value ("AQS_TRAP_LOG"));
      end;
      Ada.Text_IO.Put_Line (Log, Ada.Command_Line.Command_Name);
      Ada.Text_IO.Close (Log);
   end if;
   Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Aqs_Trap;
