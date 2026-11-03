with Ada.Command_Line;
with Ada.Text_IO;
with Ada_Quality.Storage;
with Aqs_Fixtures;

--  Separate-process database writer for concurrency tests.
--
--  Usage:
--    aqs_writer hold DATABASE SECONDS        hold the exclusive writer lock
--    aqs_writer publish DATABASE PROJECT N   publish N assessments, the K-th with TST-03 = 5000 + K basis points,
--                                            retrying while readers hold the lock
--    aqs_writer recover DATABASE             recover interrupted assessments
procedure Aqs_Writer is
   use Ada.Command_Line;

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
         delay Duration'Value (Argument (3));
         Ada_Quality.Storage.Close (Store);
      elsif Mode = "publish" and then Argument_Count = 4 then
         for Index in 1 .. Positive'Value (Argument (4)) loop
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
