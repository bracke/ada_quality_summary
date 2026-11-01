with Ada.Calendar;
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Unbounded;
with Ada_Quality.Storage;
with Ada_Quality.Types;
with Ada_Quality_Summary.CLI;

--  Fixture builder: databases are produced only through supported Ada Quality publication APIs; corruption is
--  applied only to disposable copies.
package Aqs_Fixtures is
   --  Fixture builder for ada_quality_summary tests.
   use Ada_Quality.Types;

   subtype UString is Ada.Strings.Unbounded.Unbounded_String;
   --  Fixture text.

   Root : constant String := "obj/fixtures";
   --  Directory holding every disposable fixture, relative to the tests crate.

   function Dir (Name : String) return String;
   --  Return a fresh, empty fixture directory.
   --  @param Name Fixture name.
   --  @return Directory path.

   function Absolute (Path : String) return String;
   --  Return an absolute path.
   --  @param Path Relative or absolute path.
   --  @return Absolute path.

   type Indicator_Set is array (Indicator_Id) of Boolean;
   --  Membership set.

   No_Indicators : constant Indicator_Set := [others => False];
   --  Empty set.

   type Plan is record
      Violations     : Indicator_Set := No_Indicators;
      Unknowns       : Indicator_Set := No_Indicators;
      Not_Applicable : Indicator_Set := No_Indicators;
      Findings       : Natural := 1;
      Fingerprint    : UString;
      Level          : Severity := Medium;
      Coverage       : Long_Long_Integer := 9_500;
      Source         : UString := Ada.Strings.Unbounded.To_Unbounded_String ("source-a");
      Policy         : UString := Ada.Strings.Unbounded.To_Unbounded_String ("policy-a");
      Toolchain      : UString := Ada.Strings.Unbounded.To_Unbounded_String ("toolchain-a");
      Status         : Assessment_Status := Assessment_Completed;
   end record;
   --  Shape of a synthetic assessment that satisfies the 33-indicator publication invariants.
   --  @field Violations Indicators that violate their requirement.
   --  @field Unknowns Indicators whose execution is blocked.
   --  @field Not_Applicable Indicators that do not apply.
   --  @field Findings Findings recorded for each violated indicator.
   --  @field Fingerprint Fingerprint suffix; empty derives one from the indicator and index.
   --  @field Level Finding severity.
   --  @field Coverage TST-03 basis points.
   --  @field Source Source fingerprint.
   --  @field Policy Policy fingerprint.
   --  @field Toolchain Toolchain fingerprint.
   --  @field Status Terminal lifecycle state.

   function Build (Project_Id : Positive; Shape : Plan) return Assessment;
   --  Build a publishable assessment.
   --  @param Project_Id Owning project.
   --  @param Shape Assessment shape.
   --  @return Assessment.

   function Make_Crate (Directory, Name : String) return String;
   --  Create a minimal Alire crate.
   --  @param Directory Parent directory.
   --  @param Name Crate directory and crate name.
   --  @return Canonical crate path.

   procedure Create (Database : String);
   --  Create an empty database through the storage API.
   --  @param Database Database path.

   function Register (Database, Directory, Name : String) return Positive;
   --  Register a new crate.
   --  @param Database Database path.
   --  @param Directory Parent directory of the crate.
   --  @param Name Crate name.
   --  @return Project identity.

   function Register (Store : in out Ada_Quality.Storage.Store; Directory, Name : String) return Positive;
   --  Register a new crate through an open store.
   --  @param Store Open store.
   --  @param Directory Parent directory of the crate.
   --  @param Name Crate name.
   --  @return Project identity.

   function Publish (Store : in out Ada_Quality.Storage.Store; Value : Assessment) return Positive;
   --  Publish a terminal assessment through an open store.
   --  @param Store Open store.
   --  @param Value Assessment.
   --  @return Run identity.

   function Publish (Database : String; Value : Assessment) return Positive;
   --  Publish a terminal assessment.
   --  @param Database Database path.
   --  @param Value Assessment.
   --  @return Run identity.

   function Start (Database : String; Project_Id : Positive) return Positive;
   --  Start a running assessment.
   --  @param Database Database path.
   --  @param Project_Id Project.
   --  @return Run identity.

   procedure Interrupt (Database : String; Run_Id : Positive);
   --  Interrupt a running assessment.
   --  @param Database Database path.
   --  @param Run_Id Run.

   procedure Set_Enabled (Database : String; Project_Id : Positive; Enabled : Boolean);
   --  Change the enabled flag.
   --  @param Database Database path.
   --  @param Project_Id Project.
   --  @param Enabled New flag.

   procedure Remove (Database : String; Project_Id : Positive);
   --  Tombstone a project.
   --  @param Database Database path.
   --  @param Project_Id Project.

   procedure Set_Schema (Database : String; Version : Positive);
   --  Overwrite schema metadata of a disposable database.
   --  @param Database Database path.
   --  @param Version Schema version.

   procedure Copy_Database (Source, Target : String);
   --  Copy a database and its sidecars.
   --  @param Source Existing database.
   --  @param Target New path.

   procedure Corrupt (Database : String; Run_Id : Positive; Kind : Ada_Quality.Storage.Testing_Corruption);
   --  Damage a disposable database copy.
   --  @param Database Disposable database.
   --  @param Run_Id Published run.
   --  @param Kind Damage.

   type File_State is record
      Name     : UString;
      Content  : UString;
      Modified : Ada.Calendar.Time;
   end record;
   --  Byte-level file state.
   --  @field Name File name.
   --  @field Content Raw content.
   --  @field Modified Modification time.

   package File_State_Vectors is new Ada.Containers.Indefinite_Vectors (Positive, File_State);
   --  Directory state.

   function Capture (Directory : String) return File_State_Vectors.Vector;
   --  Capture every regular file of a directory, sorted by name.
   --  @param Directory Directory.
   --  @return File states.

   function Same (Left, Right : File_State_Vectors.Vector) return Boolean;
   --  Compare two captures byte for byte, including names and modification times.
   --  @param Left First capture.
   --  @param Right Second capture.
   --  @return True when identical.

   function Run (Arguments : String) return Ada_Quality_Summary.CLI.Outcome;
   --  Execute the CLI in-process with space-separated arguments.
   --  @param Arguments Arguments; a `|` separates arguments that contain spaces.
   --  @return Outcome.

   function Output (Item : Ada_Quality_Summary.CLI.Outcome) return String;
   --  Return standard output text.
   --  @param Item Outcome.
   --  @return Text.

   function Errors (Item : Ada_Quality_Summary.CLI.Outcome) return String;
   --  Return standard error text.
   --  @param Item Outcome.
   --  @return Text.

   function Contains (Text, Pattern : String) return Boolean;
   --  Test for a substring.
   --  @param Text Haystack.
   --  @param Pattern Needle.
   --  @return True when present.

   function Set_Of (Items : String) return Indicator_Set;
   --  Parse a space-separated indicator list such as `TST-03 DOC-01`.
   --  @param Items Identifiers.
   --  @return Set.
end Aqs_Fixtures;
