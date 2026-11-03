with Ada.Containers;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Finalization;
with Ada.Strings.Fixed;
with Ada_Quality.Indicators;
with Ada_Quality_Summary.Options;
with GNAT.OS_Lib;
with Project_Tools.Files;

package body Aqs_Fixtures is
   use Ada.Strings.Unbounded;

   LF : constant Character := Character'Val (10);

   Fixture_Root : constant String :=
     Project_Tools.Files.Join
       (Project_Tools.Files.Temp_Dir,
        "aqs-fixtures-" & Ada.Strings.Fixed.Trim
          (Integer'Image (GNAT.OS_Lib.Pid_To_Integer (GNAT.OS_Lib.Current_Process_Id)), Ada.Strings.Left));

   function Root return String is (Fixture_Root);

   --  Removes the fixture directory when the test program finalizes its library units.
   type Fixture_Cleanup is new Ada.Finalization.Limited_Controlled with null record;

   overriding procedure Finalize (Item : in out Fixture_Cleanup);

   overriding procedure Finalize (Item : in out Fixture_Cleanup) is
      pragma Unreferenced (Item);
   begin
      if not Ada.Environment_Variables.Exists ("AQS_KEEP_FIXTURES") and then Ada.Directories.Exists (Fixture_Root)
      then
         Ada.Directories.Delete_Tree (Fixture_Root);
      end if;
   exception
      when others =>  --  AQ: audited exception boundary -- cleanup at program exit must not mask the test result
         null;
   end Finalize;

   Cleanup : Fixture_Cleanup;
   pragma Unreferenced (Cleanup);

   function Dir (Name : String) return String is
      Path : constant String := Root & "/" & Name;
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_Tree (Path);
      end if;
      Ada.Directories.Create_Path (Path);
      return Path;
   end Dir;

   function Absolute (Path : String) return String is (Ada.Directories.Full_Name (Path));

   function Measurement_For (Id : Indicator_Id; Shape : Plan; Violated : Boolean) return Measurement_Value is
      Count : constant Long_Long_Integer := (if Violated then Long_Long_Integer (Shape.Findings) else 0);
   begin
      if Id = TST_03 then
         return (Kind => Decimal_Value, Basis_Points => Shape.Coverage);
      elsif Id = TST_02 then
         return (Kind => Integer_Value, Integer_Data => 12);
      elsif Ada_Quality.Indicators.Measurement_Unit (Id) /= "none" then
         return (Kind => Integer_Value, Integer_Data => Count);
      end if;
      return (Kind => Boolean_Value, Boolean_Data => not Violated);
   end Measurement_For;

   function Build (Project_Id : Positive; Shape : Plan) return Assessment is
      Result : Assessment;
   begin
      Result.Project_Id := Project_Id;
      Result.Status := Shape.Status;
      Result.Source_Fingerprint := Shape.Source;
      Result.Policy_Fingerprint := Shape.Policy;
      Result.Toolchain_Fingerprint := Shape.Toolchain;
      for Id in Indicator_Id loop
         declare
            Item : Indicator_Result;
         begin
            Item.Indicator := Id;
            Item.Evidence := To_Unbounded_String ("evidence for " & Image (Id));
            if Shape.Not_Applicable (Id) then
               Item.Execution := Not_Applicable;
               Item.Compliance := Ada_Quality.Types.Not_Applicable;
               Item.Applicable := False;
               Item.Summary := To_Unbounded_String ("not applicable");
               Item.Measurement := (Kind => Unavailable_Value, Reason => To_Unbounded_String ("not applicable"));
            elsif Shape.Unknowns (Id) then
               Item.Execution := Blocked;
               Item.Compliance := Unknown;
               Item.Summary := To_Unbounded_String ("evidence unavailable");
               Item.Measurement := (Kind => Unavailable_Value, Reason => To_Unbounded_String ("tool unavailable"));
            else
               Item.Execution := Succeeded;
               Item.Compliance := (if Shape.Violations (Id) then Violation else Pass);
               Item.Summary := To_Unbounded_String (if Shape.Violations (Id) then "violated" else "passes");
               Item.Measurement := Measurement_For (Id, Shape, Shape.Violations (Id));
               if Shape.Violations (Id) then
                  for Index in 1 .. Shape.Findings loop
                     declare
                        Suffix : constant String :=
                          (if Length (Shape.Fingerprint) > 0 then To_String (Shape.Fingerprint)
                           else "rule-" & Ada.Strings.Fixed.Trim (Natural'Image (Index), Ada.Strings.Both));
                     begin
                        Item.Findings.Append
                          (Finding'(Indicator => Id, Rule => To_Unbounded_String ("rule"), Level => Shape.Level,
                            Message => To_Unbounded_String ("finding" & Natural'Image (Index)),
                            Relative_Path => To_Unbounded_String ("src/file.adb"), Line => Index,
                            Fingerprint => To_Unbounded_String (Image (Id) & ":" & Suffix)));
                     end;
                  end loop;
               end if;
            end if;
            Result.Results.Append (Item);
         end;
      end loop;
      return Result;
   end Build;

   function Make_Crate (Directory, Name : String) return String is
      Path : constant String := Directory & "/" & Name;
   begin
      Ada.Directories.Create_Path (Path);
      Project_Tools.Files.Write_Text_File
        (Path & "/alire.toml", "name = ""fixture""" & LF & "version = ""0.1.0""" & LF);
      return Ada.Directories.Full_Name (Path);
   end Make_Crate;

   procedure Create (Database : String) is
      Store : Ada_Quality.Storage.Store;
   begin
      Ada_Quality.Storage.Open (Store, Database);
      Ada_Quality.Storage.Close (Store);
   end Create;

   function Register (Database, Directory, Name : String) return Positive is
      Store : Ada_Quality.Storage.Store;
      Id    : Positive;
   begin
      Ada_Quality.Storage.Open (Store, Database);
      Id := Ada_Quality.Storage.Add_Project (Store, Make_Crate (Directory, Name));
      Ada_Quality.Storage.Close (Store);
      return Id;
   end Register;

   function Register (Store : in out Ada_Quality.Storage.Store; Directory, Name : String) return Positive is
     (Ada_Quality.Storage.Add_Project (Store, Make_Crate (Directory, Name)));

   function Publish (Store : in out Ada_Quality.Storage.Store; Value : Assessment) return Positive is
     (Ada_Quality.Storage.Publish (Store, Value));

   function Publish (Database : String; Value : Assessment) return Positive is
      Store : Ada_Quality.Storage.Store;
      Id    : Positive;
   begin
      Ada_Quality.Storage.Open (Store, Database, Create_If_Missing => False);
      Id := Ada_Quality.Storage.Publish (Store, Value);
      Ada_Quality.Storage.Close (Store);
      return Id;
   end Publish;

   function Start (Database : String; Project_Id : Positive) return Positive is
      Store : Ada_Quality.Storage.Store;
      Id    : Positive;
   begin
      Ada_Quality.Storage.Open (Store, Database, Create_If_Missing => False);
      Id := Ada_Quality.Storage.Start_Assessment (Store, Project_Id, "source-a", "policy-a");
      Ada_Quality.Storage.Close (Store);
      return Id;
   end Start;

   procedure Interrupt (Database : String; Run_Id : Positive) is
      Store : Ada_Quality.Storage.Store;
   begin
      Ada_Quality.Storage.Open (Store, Database, Create_If_Missing => False);
      Ada_Quality.Storage.Interrupt_Assessment (Store, Run_Id, "fixture interruption");
      Ada_Quality.Storage.Close (Store);
   end Interrupt;

   procedure Set_Enabled (Database : String; Project_Id : Positive; Enabled : Boolean) is
      Store : Ada_Quality.Storage.Store;
   begin
      Ada_Quality.Storage.Open (Store, Database, Create_If_Missing => False);
      Ada_Quality.Storage.Set_Enabled (Store, Project_Id, Enabled);
      Ada_Quality.Storage.Close (Store);
   end Set_Enabled;

   procedure Remove (Database : String; Project_Id : Positive) is
      Store : Ada_Quality.Storage.Store;
   begin
      Ada_Quality.Storage.Open (Store, Database, Create_If_Missing => False);
      Ada_Quality.Storage.Remove_Project (Store, Project_Id);
      Ada_Quality.Storage.Close (Store);
   end Remove;

   procedure Set_Schema (Database : String; Version : Positive) is
      Store : Ada_Quality.Storage.Store;
   begin
      Ada_Quality.Storage.Open (Store, Database, Create_If_Missing => False);
      Ada_Quality.Storage.Testing_Set_Schema_Version (Store, Version);
      Ada_Quality.Storage.Close (Store);
   end Set_Schema;

   procedure Copy_Database (Source, Target : String) is
   begin
      Ada.Directories.Copy_File (Source, Target);
      if Ada.Directories.Exists (Source & ".fts") then
         Ada.Directories.Copy_File (Source & ".fts", Target & ".fts");
      end if;
   end Copy_Database;

   procedure Corrupt (Database : String; Run_Id : Positive; Kind : Ada_Quality.Storage.Testing_Corruption) is
      Store : Ada_Quality.Storage.Store;
   begin
      Ada_Quality.Storage.Open (Store, Database, Create_If_Missing => False);
      Ada_Quality.Storage.Testing_Corrupt (Store, Run_Id, Kind);
      Ada_Quality.Storage.Close (Store);
   end Corrupt;

   function Capture (Directory : String) return File_State_Vectors.Vector is
      Search : Ada.Directories.Search_Type;
      Item   : Ada.Directories.Directory_Entry_Type;
      Result : File_State_Vectors.Vector;
   begin
      Ada.Directories.Start_Search
        (Search, Directory, "*", [Ada.Directories.Ordinary_File => True, others => False]);
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Item);
         Result.Append
           (File_State'(Name => To_Unbounded_String (Ada.Directories.Simple_Name (Item)),
             Content => To_Unbounded_String (Project_Tools.Files.Read_Raw_File (Ada.Directories.Full_Name (Item))),
             Modified => Ada.Directories.Modification_Time (Item)));
      end loop;
      Ada.Directories.End_Search (Search);
      return Result;
   end Capture;

   function Same (Left, Right : File_State_Vectors.Vector) return Boolean is
      use type Ada.Calendar.Time;
      use type Ada.Containers.Count_Type;
   begin
      if Left.Length /= Right.Length then
         return False;
      end if;
      for L of Left loop
         declare
            Found : Boolean := False;
         begin
            for R of Right loop
               if R.Name = L.Name then
                  Found := R.Content = L.Content and then R.Modified = L.Modified;
               end if;
            end loop;
            if not Found then
               return False;
            end if;
         end;
      end loop;
      return True;
   end Same;

   function Run (Arguments : String) return Ada_Quality_Summary.CLI.Outcome is
      Items : Ada_Quality_Summary.Options.String_Vectors.Vector;
      Start : Positive := Arguments'First;
      Split : constant Character := (if Ada.Strings.Fixed.Index (Arguments, "|") > 0 then '|' else ' ');
   begin
      for Index in Arguments'Range loop
         if Arguments (Index) = Split then
            if Index > Start then
               Items.Append (Arguments (Start .. Index - 1));
            end if;
            Start := Index + 1;
         end if;
      end loop;
      if Start <= Arguments'Last then
         Items.Append (Arguments (Start .. Arguments'Last));
      end if;
      return Ada_Quality_Summary.CLI.Execute (Items);
   end Run;

   function Output (Item : Ada_Quality_Summary.CLI.Outcome) return String is (To_String (Item.Output));

   function Errors (Item : Ada_Quality_Summary.CLI.Outcome) return String is (To_String (Item.Errors));

   function Contains (Text, Pattern : String) return Boolean is (Ada.Strings.Fixed.Index (Text, Pattern) > 0);

   function Set_Of (Items : String) return Indicator_Set is
      Result : Indicator_Set := No_Indicators;
      Start  : Positive := Items'First;
      Id     : Indicator_Id;
   begin
      for Index in Items'First .. Items'Last + 1 loop
         if Index > Items'Last or else Items (Index) = ' ' then
            if Index > Start then
               if not Ada_Quality.Indicators.Parse (Items (Start .. Index - 1), Id) then
                  raise Constraint_Error with "bad indicator " & Items (Start .. Index - 1);
               end if;
               Result (Id) := True;
            end if;
            Start := Index + 1;
         end if;
      end loop;
      return Result;
   end Set_Of;
end Aqs_Fixtures;
