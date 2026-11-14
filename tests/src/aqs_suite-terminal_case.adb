separate (Aqs_Suite)
procedure Terminal_Case (Id : Test_Id) is
   Database : constant String := Standard_Database (Test_Id'Image (Id));

   --  Every command and layout fits the requested width, and wider terminals show more columns.
   procedure Widths is
   begin
      declare
         Width : constant Positive := (case Id is when T026 => 40, when T027 => 80, when others => 120);
         Image : constant String := Ada.Strings.Fixed.Trim (Positive'Image (Width), Ada.Strings.Both);
      begin
         for Command of All_Commands loop
            for Layout of Layout_Names loop
               declare
                  Result : constant Ada_Quality_Summary.CLI.Outcome :=
                    Report (Database, Command.all & "|--width|" & Image & "|--layout|" & Layout.all);
               begin
                  Expect (Exit_Of (Result) = 0, Command.all & " renders: " & Errors (Result));
                  Expect (Fits (Output (Result), Width), Command.all & " " & Layout.all & " fits " & Image);
               end;
            end loop;
         end loop;
         declare
            Summary : constant String := Output (Report (Database, "summary|--width|" & Image));
         begin
            Expect (Contains (Summary, "VIOLATIONS"), "statuses are spelled out at every width");
            if Id = T027 then
               Expect (Contains (Summary, "Unknown") and then Contains (Summary, "N/A"),
                       "standard width shows indicator counts");
               Expect (not Contains (Summary, "  Path"), "standard width omits expanded columns");
            elsif Id = T028 then
               Expect (Contains (Summary, "Path") and then Contains (Summary, "Regr"),
                       "wide terminals show expanded columns");
            else
               Expect (Contains (Summary, "Fail"), "narrow tables keep essential columns");
            end if;
         end;
      end;
   end Widths;

   --  Wide characters are measured in display cells and kept whole in JSON.
   procedure Unicode_Paths is
   begin
      declare
         Unicode  : constant String := New_Database ("unicode");
         Name     : constant String :=
           "proj-" & Character'Val (16#C3#) & Character'Val (16#BC#) & Character'Val (16#E6#) &
           Character'Val (16#BC#) & Character'Val (16#A2#) & Character'Val (16#E5#) & Character'Val (16#AD#) &
           Character'Val (16#97#) & "-with-a-rather-long-directory-name";
         Project  : Positive;
         Ignored  : Positive;
      begin
         Create (Unicode);
         Project := Register (Unicode, Parent (Unicode), Name);
         Ignored := Publish (Unicode, Build (Project, Shape ("DOC-01")));
         for Width of Unicode_Widths loop
            declare
               Text : constant String := Output
                 (Report (Unicode, "summary|--width|" & Ada.Strings.Fixed.Trim (Integer'Image (Width),
                                                                              Ada.Strings.Both)));
               Decoded : constant Wide_Wide_String := Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Text);
            begin
               Expect (Decoded'Length > 0, "terminal output is valid UTF-8");
               Expect (Fits (Text, Width), "wide characters are measured in display cells");
            end;
         end loop;
         Expect_Equal (Value (Json (Unicode, "summary"), "data.projects[0].name"), """" & Name & """",
                       "JSON keeps the full Unicode name");
      end;
   end Unicode_Paths;

   --  NO_COLOR and --no-color disable styling; status words remain.
   procedure No_Color is
   begin
      Set_Env ("NO_COLOR", "1");
      Expect (not Has_Escape (Output (Report (Database, "summary|--color|auto"))), "NO_COLOR disables color");
      Expect (not Has_Escape (Output (Report (Database, "summary"))), "the default honors NO_COLOR");
      Expect (Has_Escape (Output (Report (Database, "summary|--color|always"))), "always overrides NO_COLOR");
      Expect (not Has_Escape (Output (Report (Database, "summary|--no-color"))), "--no-color disables color");
      Expect (not Has_Escape (Json (Database, "summary|--color|always")), "JSON is never styled");
      Clear_Env ("NO_COLOR");
      declare
         Colored : constant String := Output (Report (Database, "summary|--color|always"));
      begin
         Expect (Contains (Colored, "VIOLATIONS") and then Contains (Colored, "INCOMPLETE"),
                 "status text is present alongside color");
      end;
   end No_Color;

   --  Redirected output is unstyled unless color is forced.
   procedure Redirected is
   begin
      Clear_Env ("NO_COLOR");
      declare
         Result : constant Process_Result := Spawn ("--database|" & Database & "|summary");
      begin
         Expect (Result.Status = 0, "redirected report succeeds");
         Expect (not Has_Escape (To_String (Result.Output)), "redirected output has no automatic styling");
         Expect (Has_Escape (To_String (Spawn ("--database|" & Database & "|summary|--color|always").Output)),
                 "explicit color still applies when redirected");
      end;
   end Redirected;

begin
   case Id is
      when T026 | T027 | T028 => Widths;
      when T029 => Unicode_Paths;
      when T030 => No_Color;
      when T031 => Redirected;
      when others => null;
   end case;
end Terminal_Case;
