with Ada.Command_Line;
with AUnit;
with AUnit.Reporter.Text;
with AUnit.Run;
with Aqs_Suite;

--  AUnit runner for every ada_quality_summary acceptance test.
procedure Ada_Quality_Summary_Tests is
   use type AUnit.Status;
   function Execute is new AUnit.Run.Test_Runner_With_Status (Aqs_Suite.Suite);
   Reporter : AUnit.Reporter.Text.Text_Reporter;
begin
   if Execute (Reporter) = AUnit.Failure then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Ada_Quality_Summary_Tests;
