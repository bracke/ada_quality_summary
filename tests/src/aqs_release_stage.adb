with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Project_Tools.Alire_Manifests;
with Project_Tools.Files;
with Project_Tools.Processes;
with Project_Tools.Release_Checks;

--  Staged release check: the published manifest must not carry the development pins.
--
--  The root alire.toml ends with `[[pins]]` tables that link every dependency to a sibling checkout. This tool stages
--  the release payload under obj/release-stage with those tables removed, validates the staged manifest and sources
--  with project_tools, and builds the stage through a temporary overlay that pins the same siblings by absolute path.
--  The staged alire.toml is the manifest to publish.
--
--  Usage: tests/bin/aqs_release_stage
procedure Aqs_Release_Stage is
   use Ada.Strings.Unbounded;

   LF : constant Character := ASCII.LF;

   Root  : constant String :=
     Project_Tools.Files.Find_Root_Upward (Ada.Directories.Current_Directory, "ada_quality_summary.gpr");
   Stage : constant String := Project_Tools.Files.Join (Root, "obj/release-stage");
   Alr   : constant String := Project_Tools.Processes.Locate_Command ("alr");

   Release_Manifest : Unbounded_String;
   Build_Pins       : Unbounded_String := To_Unbounded_String (LF & "[[pins]]" & LF);
   Pinned           : Project_Tools.Alire_Manifests.String_List (1 .. 32);
   Pin_Count        : Natural := 0;

   function Trimmed (Line : String) return String is (Ada.Strings.Fixed.Trim (Line, Ada.Strings.Both));

   function Is_Filler (Line : String) return Boolean is
     (Trimmed (Line)'Length = 0 or else Trimmed (Line) (Trimmed (Line)'First) = '#');

   --  Split the development manifest into the release part and absolute build pins.
   procedure Split_Manifest is
      Text      : constant String := Project_Tools.Files.Read_Raw_File (Project_Tools.Files.Join (Root, "alire.toml"));
      Kept      : Unbounded_String;
      Held      : Unbounded_String;
      In_Pins   : Boolean := False;
      Start     : Positive := Text'First;
   begin
      while Start <= Text'Last loop
         declare
            Stop : constant Natural :=
              (if Ada.Strings.Fixed.Index (Text (Start .. Text'Last), [1 => LF]) = 0 then Text'Last
               else Ada.Strings.Fixed.Index (Text (Start .. Text'Last), [1 => LF]) - 1);
            Line : constant String := Text (Start .. Stop);
         begin
            if Trimmed (Line) = "[[pins]]" then
               In_Pins := True;
            elsif In_Pins and then not Is_Filler (Line) then
               declare
                  Equals : constant Natural := Ada.Strings.Fixed.Index (Line, "=");
                  Open   : constant Natural := Ada.Strings.Fixed.Index (Line, "path = """);
               begin
                  if Equals = 0 or else Open = 0 or else Ada.Strings.Fixed.Index (Line, """ }") = 0
                    or else Pin_Count = Pinned'Last
                  then
                     Project_Tools.Release_Checks.Fail
                       ("alire.toml: only path pins may follow the first [[pins]] table: " & Line);
                  end if;
                  declare
                     Name     : constant String := Trimmed (Line (Line'First .. Equals - 1));
                     Relative : constant String :=
                       Line (Open + 8 .. Ada.Strings.Fixed.Index (Line, """ }") - 1);
                     Absolute : constant String :=
                       Ada.Directories.Full_Name (Project_Tools.Files.Join (Root, Relative));
                  begin
                     Pin_Count := Pin_Count + 1;
                     Pinned (Pin_Count) := To_Unbounded_String (Name & " = { path = """ & Absolute & """ }");
                     Append (Build_Pins, To_String (Pinned (Pin_Count)) & LF);
                  end;
               end;
            elsif not In_Pins then
               --  Comment and blank lines are held back so the comment introducing the pins is dropped with them.
               if Is_Filler (Line) then
                  Append (Held, Line & LF);
               else
                  Append (Kept, Held);
                  Held := Null_Unbounded_String;
                  Append (Kept, Line & LF);
               end if;
            end if;
            Start := Stop + 2;
         end;
      end loop;
      if Pin_Count = 0 then
         Project_Tools.Release_Checks.Fail ("alire.toml has no development pins to strip");
      end if;
      Release_Manifest := Kept;
   end Split_Manifest;

   procedure Copy_Payload is
      type Text_Access is access constant String;
      type Text_List is array (Positive range <>) of Text_Access;
      No_Names : constant Project_Tools.Files.Name_List (1 .. 0) := [others => Null_Unbounded_String];
      Files    : constant Text_List :=
        [new String'("ada_quality_summary.gpr"), new String'("README.md"), new String'("LICENSE")];
      Trees    : constant Text_List := [new String'("src"), new String'("schemas"), new String'("docs")];
   begin
      if Project_Tools.Files.Directory_Exists (Stage) then
         Project_Tools.Files.Delete_Tree (Stage);
      end if;
      Ada.Directories.Create_Path (Stage);
      for Name of Files loop
         Project_Tools.Files.Copy_File
           (Project_Tools.Files.Join (Root, Name.all), Project_Tools.Files.Join (Stage, Name.all));
      end loop;
      for Name of Trees loop
         Project_Tools.Files.Copy_Filtered_Tree
           (Project_Tools.Files.Join (Root, Name.all), Project_Tools.Files.Join (Stage, Name.all), No_Names, No_Names);
      end loop;
      Project_Tools.Files.Write_Raw_File (Project_Tools.Files.Join (Stage, "alire.toml"), To_String (Release_Manifest));
   end Copy_Payload;

   Staged_Manifest : constant String := Project_Tools.Files.Join (Stage, "alire.toml");
begin
   if Root'Length = 0 then
      Project_Tools.Release_Checks.Fail ("cannot locate the ada_quality_summary project root");
   end if;
   Split_Manifest;
   Copy_Payload;
   Project_Tools.Alire_Manifests.Require_Staged_Crate_Source (Stage, "ada_quality_summary", "ada_quality_summary.gpr");
   Project_Tools.Alire_Manifests.Require_Release_Dependencies
     (Staged_Manifest,
      [To_Unbounded_String ("ada_quality"), To_Unbounded_String ("project_tools"),
       To_Unbounded_String ("terminal_styles"), To_Unbounded_String ("messages"), To_Unbounded_String ("jsonlib"),
       To_Unbounded_String ("humanize")]);
   Project_Tools.Alire_Manifests.Write_Build_Manifest_Overlay
     (Staged_Manifest, Project_Tools.Files.Join (Stage, "alire.build.toml"), To_String (Build_Pins));
   Project_Tools.Alire_Manifests.Require_Build_Overlay
     (Project_Tools.Files.Join (Stage, "alire.build.toml"), Staged_Manifest, Pinned (1 .. Pin_Count));
   Project_Tools.Alire_Manifests.Activate_Build_Manifest (Stage);
   begin
      Project_Tools.Release_Checks.Run
        ("staged dependency solution", Stage, Alr, [new String'("--non-interactive"), new String'("update")]);
      Project_Tools.Release_Checks.Run
        ("staged release build", Stage, Alr, [new String'("--non-interactive"), new String'("build")]);
   exception
      when others =>  --  AQ: audited exception boundary -- restores the publish manifest and re-raises
         Project_Tools.Alire_Manifests.Restore_Publish_Manifest (Stage);
         raise;
   end;
   Project_Tools.Alire_Manifests.Restore_Publish_Manifest (Stage);
   Project_Tools.Alire_Manifests.Require_Pin_Free_Crate_Manifest (Staged_Manifest, "ada_quality_summary");
   Ada.Text_IO.Put_Line ("ada_quality_summary staged release: OK (" & Staged_Manifest & ")");
exception
   when Program_Error =>
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Aqs_Release_Stage;
