with Ada.Command_Line;
with Ada.Directories;
with Ada.Text_IO;
with Ada_Quality.Storage;
with Aqs_Fixtures;

--  Separate-process database writer for concurrency tests.
--
--  Usage:
--    aqs_writer hold DATABASE RELEASE        hold the exclusive writer lock until the file RELEASE exists
--    aqs_writer publish DATABASE PROJECT N PAUSE
--                                            publish N assessments, the K-th with TST-03 = 5000 + K basis points,
--                                            retrying while readers hold the lock; after the first half, wait
--                                            until the file PAUSE exists
--
--  Waiting for a file the test creates replaces fixed delays, so the tests do not depend on machine speed. Each
--  wait is bounded by a minute, after which the writer fails.
--    aqs_writer recover DATABASE             recover interrupted assessments
procedure Aqs_Writer is
   use Ada.Command_Line;

   --  Wait until the test creates Path.
   procedure Await (Path : String) is
   begin
      for Attempt in 1 .. 6_000 loop
         if Ada.Directories.Exists (Path) then
            return;
         end if;
         delay 0.01;
      end loop;
      raise Program_Error with "no signal " & Path;
   end Await;

   procedure Usage is
   begin
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "usage: aqs_writer hold|publish|recover DATABASE ...");
      Set_Exit_Status (Failure);
   end Usage;
begin
   if Argument_Count < 2 then
      Usage;
      return;
   end if;
   declare
      Mode     : constant String := Argument (1);
      Database : constant String := Argument (2);
      Store    : Ada_Quality.Storage.Store;
   begin
      if Mode = "hold" and then Argument_Count = 3 then
         Ada_Quality.Storage.Open (Store, Database, Create_If_Missing => False);
         Ada.Text_IO.Put_Line ("locked");
         Ada.Text_IO.Flush;
         Await (Argument (3));
         Ada_Quality.Storage.Close (Store);
      elsif Mode = "publish" and then Argument_Count = 5 then
         for Index in 1 .. Positive'Value (Argument (4)) loop
            if Index = Positive'Value (Argument (4)) / 2 + 1 then
               Ada.Text_IO.Put_Line ("paused");
               Ada.Text_IO.Flush;
               Await (Argument (5));
            end if;
            for Attempt in 1 .. 2_000 loop
               begin
                  declare
                     Id : constant Positive :=
                       Aqs_Fixtures.Publish
                         (Database,
                          Aqs_Fixtures.Build
                            (Positive'Value (Argument (3)),
                             (Coverage => 5_000 + Long_Long_Integer (Index), others => <>)));
                     pragma Unreferenced (Id);
                  begin
                     --  Leave readers a window, as successive real assessments would.
                     delay 0.05;
                     exit;
                  end;
               exception
                  when Ada_Quality.Storage.Storage_Error =>
                     --  A reader holds the shared lock; retry shortly.
                     delay 0.005;
               end;
               if Attempt = 2_000 then
                  raise Program_Error with "writer starved";
               end if;
            end loop;
         end loop;
      elsif Mode = "recover" and then Argument_Count = 2 then
         for Attempt in 1 .. 2_000 loop
            declare
               Count : Natural;
            begin
               Ada_Quality.Storage.Open (Store, Database, Create_If_Missing => False);
               Ada_Quality.Storage.Recover (Store, Count);
               Ada_Quality.Storage.Close (Store);
               Ada.Text_IO.Put_Line (Natural'Image (Count));
               exit;
            exception
               when Ada_Quality.Storage.Storage_Error =>
                  --  A reader holds the shared lock; retry shortly.
                  delay 0.005;
            end;
            if Attempt = 2_000 then
               raise Program_Error with "recovery starved";
            end if;
         end loop;
      else
         Usage;
      end if;
   end;
end Aqs_Writer;
