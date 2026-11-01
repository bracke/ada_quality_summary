with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Ada_Quality.Types;
with Aqs_Fixtures;

--  Create a demonstration database through the supported publication APIs.
--
--  Usage: aqs_demo DIRECTORY
--  Creates DIRECTORY/quality.db with passing, violating, incomplete, unassessed, disabled, and removed projects,
--  compatible and incompatible histories, and running and interrupted runs.
procedure Aqs_Demo is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Types;
   use Aqs_Fixtures;

   function Shape
     (Violations : String := ""; Unknowns : String := ""; NA : String := "PRF-01"; Policy : String := "policy-a";
      Coverage : Long_Long_Integer := 9_500; Findings : Natural := 1; Level : Severity := Medium) return Plan is
     ((Violations => Set_Of (Violations), Unknowns => Set_Of (Unknowns), Not_Applicable => Set_Of (NA),
       Findings => Findings, Fingerprint => Null_Unbounded_String, Level => Level, Coverage => Coverage,
       Source => To_Unbounded_String ("source-a"), Policy => To_Unbounded_String (Policy),
       Toolchain => To_Unbounded_String ("toolchain-a"), Status => Assessment_Completed));
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
      Run := Publish (Database, Build (Ids (1), Shape));
      Run := Publish (Database, Build (Ids (2), Shape (Coverage => 9_300)));
      Run := Publish (Database, Build (Ids (2), Shape ("TST-03 DOC-01", Coverage => 8_700, Findings => 2,
                                                       Level => High)));
      Run := Publish (Database, Build (Ids (3), Shape ("SRC-01 SRC-04 DOC-01", "BLD-02 TST-04")));
      Run := Publish (Database, Build (Ids (4), Shape ("DOC-01")));
      Run := Publish (Database, Build (Ids (4), Shape ("DOC-01 REL-01", Policy => "policy-b")));
      Run := Start (Database, Ids (4));
      Run := Publish (Database, Build (Ids (7), Shape ("SEC-01", Level => Critical)));
      Interrupt (Database, Start (Database, Ids (7)));
      Set_Enabled (Database, Ids (6), False);
      Remove (Database, Ids (5));
      Ada.Text_IO.Put_Line (Database);
   end;
end Aqs_Demo;
