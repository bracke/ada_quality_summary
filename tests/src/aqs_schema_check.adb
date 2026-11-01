with Ada.Command_Line;
with Ada.Text_IO;
with Aqs_Schema;
with Project_Tools.Files;

--  Validate a JSON report file against a report schema.
--
--  Usage: aqs_schema_check SCHEMA_DIRECTORY SCHEMA_FILE DOCUMENT
procedure Aqs_Schema_Check is
   use Ada.Command_Line;
begin
   if Argument_Count /= 3 then
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error, "usage: aqs_schema_check SCHEMA_DIRECTORY SCHEMA_FILE DOCUMENT");
      Set_Exit_Status (Failure);
      return;
   end if;
   declare
      Problem : constant String :=
        Aqs_Schema.Validate (Argument (1), Argument (2), Project_Tools.Files.Read_Raw_File (Argument (3)));
   begin
      if Problem'Length > 0 then
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Problem);
         Set_Exit_Status (Failure);
      else
         Ada.Text_IO.Put_Line ("valid");
      end if;
   end;
end Aqs_Schema_Check;
