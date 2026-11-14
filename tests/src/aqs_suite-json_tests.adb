separate (Aqs_Suite)
package body JSON_Tests is
   function Schema_Name (Command : String) return String is
      Bar : constant Natural := Ada.Strings.Fixed.Index (Command, "|");
   begin
      return (if Bar = 0 then Command else Command (Command'First .. Bar - 1)) & ".schema.json";
   end Schema_Name;

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
                  when others => null;
               end case;
            end;
         end loop;
      end loop;
      if Id = T032 then
         Expect (Aqs_Schema.Validate (Schemas, "summary.schema.json", "{""schema_version"":1}") /= "",
                 "the validator rejects incomplete documents");
         Expect (Aqs_Schema.Matches ("^(STR|BLD)-[0-9]{2}$", "BLD-04"), "pattern alternation");
         Expect (not Aqs_Schema.Matches ("^[0-9]{2}$", "123"), "pattern anchoring");
      end if;
   end JSON_Case;

   procedure Parity is
      Database : constant String := Standard_Database ("T034");
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
      Expect (Contains (Terminal, "Projects: " & Value (Text, "data.totals.projects") & " registered"),
              "population parity");
   end Parity;
end JSON_Tests;
