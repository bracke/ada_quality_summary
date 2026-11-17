separate (Aqs_Suite)
package body JSON_Tests is
   function Schema_Name (Command : String) return String is
      Bar : constant Natural := Ada.Strings.Fixed.Index (Command, "|");
   begin
      return (if Bar = 0 then Command else Command (Command'First .. Bar - 1)) & ".schema.json";
   end Schema_Name;

   --  One violation per keyword the validator implements, so a validator that ignores a keyword fails here.
   procedure Schema_Mutations is
      Database : constant String := Standard_Database ("mutations");
      Summary  : constant String := Json (Database, "summary");
      Scratch  : constant String := Absolute (Dir ("schemas"));

      --  Summary with the first occurrence of Old replaced by New.
      function Mutated (Old, New_Text : String) return String is
         Position : constant Natural := Ada.Strings.Fixed.Index (Summary, Old);
      begin
         Assert (Position > 0, "the summary contains " & Old);
         return Summary (Summary'First .. Position - 1) & New_Text & Summary (Position + Old'Length .. Summary'Last);
      end Mutated;

      procedure Rejects (Old, New_Text, Keyword : String) is
      begin
         Expect (Aqs_Schema.Validate (Schemas, "summary.schema.json", Mutated (Old, New_Text)) /= "",
                 "the validator enforces " & Keyword);
      end Rejects;

      --  Validate Document against a one-off schema, to reach keywords the report schemas use only deep inside.
      function Against (Schema, Document : String) return String is
      begin
         Project_Tools.Files.Write_Text_File (Scratch & "/common.schema.json", "{""$defs"":{}}");
         Project_Tools.Files.Write_Text_File (Scratch & "/probe.schema.json", Schema);
         return Aqs_Schema.Validate (Scratch, "probe.schema.json", Document);
      end Against;
   begin
      Expect (Aqs_Schema.Validate (Schemas, "summary.schema.json", Summary) = "", "the unmutated summary validates");
      Rejects ("""quality"":""violations""", """quality"":""nonsense""", "enum");
      Rejects ("{""schema_version"":1", "{""extra"":1,""schema_version"":1", "additionalProperties");
      Rejects ("""schema_version"":1", """schema_version"":2", "const");
      Rejects ("""project_id"":1,", """project_id"":0,", "minimum");
      Rejects ("""enabled"":true", """enabled"":""yes""", "type");
      Rejects ("""indicator_id"":""TST-03""", """indicator_id"":""TST-3""", "pattern");
      Expect (Against ("{""type"":""array"",""maxItems"":1}", "[1,2]") /= "", "maxItems");
      Expect (Against ("{""type"":""string"",""minLength"":2}", """a""") /= "", "minLength");
      Expect (Against ("{""oneOf"":[{""type"":""string""},{""type"":""integer""}]}", "true") /= "", "oneOf");
      Expect (Against ("{""type"":""array"",""items"":{""type"":""integer""}}", "[1,""x""]") /= "", "items");
      Expect (Against ("{""type"":""object"",""required"":[""a""]}", "{}") /= "", "required");
      Expect (Contains (Against ("{""type"":""object"",""frobnicate"":1}", "{}"), "unsupported"),
              "an unknown keyword is reported, not ignored");
      Expect (Contains (Against ("{""type"":""object"",""additionalProperties"":true}", "{}"), "only"),
              "additionalProperties other than false is reported");
      Expect (Contains (Against ("{""type"":[""string"",""null""]}", "null"), "only"),
              "a list of types is reported");
   end Schema_Mutations;

   procedure JSON_Case (Id : Test_Id) is
      Database : constant String := Standard_Database (Test_Id'Image (Id));
      Ignored  : Positive;
   begin
      --  A running run, an interrupted run, and a removed project exercise nullable and enumerated fields.
      Ignored := Start (Database, 3);
      for Command of All_Commands loop
         for Variant of Variants loop
            declare
               Text : constant String := Json (Database, Command.all & Variant.all);
            begin
               case Id is
                  when T032 =>
                     declare
                        Problem : constant String := Aqs_Schema.Validate (Schemas, Schema_Name (Command.all), Text);
                     begin
                        Expect (Problem = "", Command.all & Variant.all & " validates: " & Problem);
                     end;
                     Expect_Equal (Value (Text, "schema_version"), "1", "versioned envelope");
                     Expect (not Contains (Text, "quality.db"), "the database filename is not embedded");
                  when T033 =>
                     Expect (Text = Json (Database, Command.all & Variant.all), "byte-identical repeated export");
                  when X_Round_Trip =>
                     declare
                        Doc   : Jsonlib.Documents.Document;
                        Error : Jsonlib.Errors.Error_Info;
                     begin
                        Jsonlib.Parsers.Parse (Text, Doc, Error);
                        if Variant.all /= "|--pretty" then
                           Expect (Jsonlib.Serializers.To_String (Doc) & LF = Text,
                                   "parsing and serializing preserve every field");
                        end if;
                     end;
                  when others => raise Program_Error with "unhandled " & Id'Image;
               end case;
            end;
         end loop;
      end loop;
      if Id = T032 then
         Expect (Aqs_Schema.Validate (Schemas, "summary.schema.json", "{""schema_version"":1}") /= "",
                 "the validator rejects incomplete documents");
         Expect (Aqs_Schema.Matches ("^(STR|BLD)-[0-9]{2}$", "BLD-04"), "pattern alternation");
         Expect (not Aqs_Schema.Matches ("^[0-9]{2}$", "123"), "pattern anchoring");
         Schema_Mutations;
      end if;
   end JSON_Case;

   --  A population with distinct class sizes, so a terminal label paired with the wrong total cannot match:
   --  one passing, two violating, three incomplete, and four unassessed projects, two of them with regressions.
   function Parity_Database return String is
      Database : constant String := New_Database ("T034");
      Ignored  : Positive;
   begin
      Create (Database);
      for Index in 1 .. 10 loop
         declare
            Project : constant Positive :=
              Register (Database, Parent (Database), "p" & Ada.Strings.Fixed.Trim (Index'Image, Ada.Strings.Left));
         begin
            case Index is
               when 1 => Ignored := Publish (Database, Build (Project, Shape));
               when 2 .. 3 =>
                  Ignored := Publish (Database, Build (Project, Shape));
                  Ignored := Publish (Database, Build (Project, Shape ("DOC-01")));
               when 4 .. 6 => Ignored := Publish (Database, Build (Project, Shape (Unknowns => "TST-04")));
               when others => null;
            end case;
         end;
      end loop;
      return Database;
   end Parity_Database;

   procedure Parity is
      Database : constant String := Parity_Database;
      Text     : constant String := Json (Database, "summary");
      Terminal : constant String := Output (Report (Database, "summary|--width|100"));

      function Line_Value (Label : String) return String is
         Position : constant Natural := Ada.Strings.Fixed.Index (Terminal, LF & "  " & Label);
         Stop     : constant Natural := Ada.Strings.Fixed.Index (Terminal (Position + 1 .. Terminal'Last), [LF]);
      begin
         return Ada.Strings.Fixed.Trim (Terminal (Position + 3 + Label'Length .. Stop - 1), Ada.Strings.Both);
      end Line_Value;
   begin
      Expect_Equal (Line_Value ("Passing"), Value (Text, "data.totals.passing"), "passing parity");
      Expect_Equal (Line_Value ("Violations"), Value (Text, "data.totals.violations"), "violation parity");
      Expect_Equal (Line_Value ("Incomplete"), Value (Text, "data.totals.incomplete"), "incomplete parity");
      Expect_Equal (Line_Value ("Unassessed"), Value (Text, "data.totals.unassessed"), "unassessed parity");
      Expect (Contains (Terminal, "Projects with regressions: " &
                          Value (Text, "data.regression_summary.projects_with_regressions")),
              "regression parity");
      Expect (Contains (Terminal, "Projects: " & Value (Text, "data.totals.projects") & " selected"),
              "population parity");
      Expect_Equal (Value (Text, "data.totals.passing") & Value (Text, "data.totals.violations") &
                      Value (Text, "data.totals.incomplete") & Value (Text, "data.totals.unassessed"), "1234",
                    "the fixture's distinct class sizes");
      Expect_Equal (Value (Text, "data.regression_summary.projects_with_regressions"), "2", "two regressed projects");
   end Parity;
end JSON_Tests;
