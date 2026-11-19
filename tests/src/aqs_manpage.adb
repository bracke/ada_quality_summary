with Ada.Directories;
with Ada.Text_IO;
with Project_Tools.Files;
with Aqs_Manual;

--  Regenerate the committed manual page from the command and option tables; check_all fails while it is stale.
--
--  Usage: tests/bin/aqs_manpage
procedure Aqs_Manpage is
   Root : constant String :=
     Project_Tools.Files.Find_Root_Upward (Ada.Directories.Current_Directory, "ada_quality_summary.gpr");
   Path : constant String := Project_Tools.Files.Join (Root, Aqs_Manual.Page_Path);
begin
   Project_Tools.Files.Write_Raw_File (Path, Aqs_Manual.Page);
   Ada.Text_IO.Put_Line (Path);
end Aqs_Manpage;
