separate (Aqs_Suite)
package body Integrity_Tests is
   procedure Integrity (Id : Test_Id) is
      Database : constant String := New_Database (Test_Id'Image (Id));
      Copy     : constant String := Parent (Database) & "/copy.db";
      Project  : Positive;
      Run_Id   : Positive;

      --  Damage the copy the way the case describes.
      procedure Damage is
      begin
         case Id is
            when T011 => Corrupt (Copy, Run_Id, Ada_Quality.Storage.Testing.Duplicate_Result);
            when T012 => Corrupt (Copy, Run_Id, Ada_Quality.Storage.Testing.Missing_Result);
            when T013 => Corrupt (Copy, Run_Id, Ada_Quality.Storage.Testing.Invalid_Measurement);
            when T038 => Corrupt (Copy, Run_Id, Ada_Quality.Storage.Testing.Malformed_Finding);
            when T036 => Set_Schema (Copy, 2);
            when T037 => Set_Schema (Copy, 99);
            when others => raise Program_Error with "unhandled " & Id'Image;
         end case;
      end Damage;

      --  The diagnostic the damage must produce.
      function Diagnosis return String is
        (case Id is
            when T011 => "duplicate result",
            when T012 => "contradicts result execution",
            when T013 => "noncanonical measurement",
            when T038 => "finding",
            when T036 => "migrate",
            when T037 => "unsupported schema version 99",
            when others => raise Program_Error with "unhandled " & Id'Image);
   begin
      Create (Database);
      Project := Register (Database, Parent (Database), "alpha");
      Run_Id := Publish (Database, Build (Project, Shape ("DOC-01")));
      Copy_Database (Database, Copy);
      Damage;
      declare
         Before : constant File_State_Vectors.Vector := Capture (Parent (Database));
         Result : constant Ada_Quality_Summary.CLI.Outcome := Report (Copy, "summary|--format|json");
      begin
         Expect (Exit_Of (Result) = 4, "integrity and schema failures exit with code 4");
         Expect (Output (Result) = "", "no partial report is written");
         Expect (Contains (Errors (Result), Diagnosis), "the failure is diagnosed: " & Diagnosis);
         Expect (Same (Before, Capture (Parent (Database))), "the database is unchanged");
      end;
   end Integrity;

   procedure Missing (Id : Test_Id) is
      Directory : constant String := Absolute (Dir (Test_Id'Image (Id)));
      Database  : constant String :=
        (if Id = T035 then Directory & "/absent.db" else Directory & "/no/such/dir/absent.db");
      Result    : constant Ada_Quality_Summary.CLI.Outcome := Report (Database, "summary");
   begin
      Expect (Exit_Of (Result) = 4, "a missing database is a database failure");
      Expect (Contains (Errors (Result), "database not found"), "the missing database is named");
      Expect (not Ada.Directories.Exists (Database), "the database is not created");
      Expect (not Ada.Directories.Exists (Directory & "/no"), "no directory is created");
      Expect (Capture (Directory).Is_Empty, "no file is created");
   end Missing;
end Integrity_Tests;
