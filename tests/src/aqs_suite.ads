with AUnit.Test_Suites;

--  Acceptance test catalog AQS_T001 to AQS_T050 plus property, concurrency, and unit tests.
package Aqs_Suite is
   --  Acceptance test catalog.

   function Suite return AUnit.Test_Suites.Access_Test_Suite;
   --  Return every test case.
   --  @return Suite.
end Aqs_Suite;
