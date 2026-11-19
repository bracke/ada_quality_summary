with Ada.Command_Line;
with Ada.Directories;
with Ada.Text_IO;
with Ada_Quality.Types;
with Aqs_Fixtures;

--  Create a demonstration database through the supported publication APIs.
--
--  Usage: aqs_demo DIRECTORY
--  Creates DIRECTORY/quality.db with passing, violating, incomplete, unassessed, disabled, and removed projects,
--  compatible and incompatible histories, and running and interrupted runs.
procedure Aqs_Demo is
   use Ada_Quality.Types;
   use Aqs_Fixtures;

   --  Demonstration assessments treat PRF-01 as not applicable unless told otherwise.
   function Demo
     (Violations : String := ""; Unknowns : String := ""; NA : String := "PRF-01"; Policy : String := "policy-a";
      Coverage : Long_Long_Integer := 9_500; Findings : Natural := 1; Level : Severity := Medium;
      Waivers : String := "") return Plan is
     (Aqs_Fixtures.Shape
        (Violations, Unknowns, NA, Policy, Coverage => Coverage, Findings => Findings, Level => Level,
         Waivers => Waivers));
begin
   if Ada.Command_Line.Argument_Count /= 1 then
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "usage: aqs_demo DIRECTORY");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;
   declare
      Directory : constant String := Ada.Command_Line.Argument (1);
      Database  : constant String := Directory & "/quality.db";
      Projects  : constant String := Directory & "/projects";
      Ids       : array (1 .. 7) of Positive;
      Run       : Positive;
      pragma Unreferenced (Run);
   begin
      Ada.Directories.Create_Path (Projects);
      if Ada.Directories.Exists (Database) then
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "database already exists: " & Database);
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;
      Create (Database);
      Ids (1) := Register (Database, Projects, "httpclient");
      Ids (2) := Register (Database, Projects, "backup");
      Ids (3) := Register (Database, Projects, "editor");
      Ids (4) := Register (Database, Projects, "version");
      Ids (5) := Register (Database, Projects, "archive");
      Ids (6) := Register (Database, Projects, "legacy");
      Ids (7) := Register (Database, Projects, "messages");
      Run := Publish (Database, Build (Ids (1), Demo (Waivers => "SRC-03")));
      Run := Publish (Database, Build (Ids (2), Demo (Coverage => 9_300)));
      Run := Publish (Database, Build (Ids (2), Demo ("TST-03 DOC-01", Coverage => 8_700, Findings => 2,
                                                       Level => High)));
      Run := Publish (Database, Build (Ids (3), Demo ("SRC-01 SRC-04 DOC-01", "BLD-02 TST-04",
                                                       Waivers => "SRC-03 SRC-06")));
      Run := Publish (Database, Build (Ids (4), Demo ("DOC-01")));
      Run := Publish (Database, Build (Ids (4), Demo ("DOC-01 REL-01", Policy => "policy-b")));
      Run := Start (Database, Ids (4));
      Run := Publish (Database, Build (Ids (7), Demo ("SEC-01", Level => Critical)));
      Interrupt (Database, Start (Database, Ids (7)));
      Set_Enabled (Database, Ids (6), False);
      Remove (Database, Ids (5));
      Ada.Text_IO.Put_Line (Database);
   end;
end Aqs_Demo;
