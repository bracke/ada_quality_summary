with Ada.Strings.Fixed;
with Jsonlib.Documents;
with Jsonlib.Errors;
with Jsonlib.Parsers;
with Jsonlib.Serializers;
with Project_Tools.Files;

package body Aqs_Schema is
   use Jsonlib.Documents;
   use type Jsonlib.Errors.Error_Code;

   --  Match one pattern element at Text (Position); returns the next text position or 0 on mismatch.
   function Match_From (Pattern : String; P : Positive; Text : String; T : Positive) return Boolean is
   begin
      if P > Pattern'Last then
         return T > Text'Last;
      elsif Pattern (P) = '$' and then P = Pattern'Last then
         return T > Text'Last;
      end if;
      declare
         --  Parse one atom: a literal, a [class], or a (a|b) group.
         Atom_Last : Positive := P;
         Repeat    : Natural := 1;
         Next      : Positive;
      begin
         if Pattern (P) = '[' then
            Atom_Last := Ada.Strings.Fixed.Index (Pattern (P .. Pattern'Last), "]");
         elsif Pattern (P) = '(' then
            Atom_Last := Ada.Strings.Fixed.Index (Pattern (P .. Pattern'Last), ")");
         end if;
         Next := Atom_Last + 1;
         if Next <= Pattern'Last and then Pattern (Next) = '{' then
            declare
               Close : constant Natural := Ada.Strings.Fixed.Index (Pattern (Next .. Pattern'Last), "}");
            begin
               Repeat := Natural'Value (Pattern (Next + 1 .. Close - 1));
               Next := Close + 1;
            end;
         end if;
         declare
            Atom : constant String := Pattern (P .. Atom_Last);

            function One (Position : Positive; After : out Positive) return Boolean is
            begin
               if Atom (Atom'First) = '(' then
                  declare
                     Start : Positive := Atom'First + 1;
                  begin
                     for Index in Atom'First + 1 .. Atom'Last loop
                        if Atom (Index) in '|' | ')' then
                           declare
                              Choice : constant String := Atom (Start .. Index - 1);
                           begin
                              if Position + Choice'Length - 1 <= Text'Last and then
                                Text (Position .. Position + Choice'Length - 1) = Choice
                              then
                                 After := Position + Choice'Length;
                                 return True;
                              end if;
                           end;
                           Start := Index + 1;
                        end if;
                     end loop;
                     After := Position;
                     return False;
                  end;
               end if;
               After := Position + 1;
               if Position > Text'Last then
                  return False;
               elsif Atom (Atom'First) = '[' then
                  declare
                     Index : Positive := Atom'First + 1;
                  begin
                     while Index < Atom'Last loop
                        if Index + 2 < Atom'Last and then Atom (Index + 1) = '-' then
                           if Text (Position) in Atom (Index) .. Atom (Index + 2) then
                              return True;
                           end if;
                           Index := Index + 3;
                        else
                           if Text (Position) = Atom (Index) then
                              return True;
                           end if;
                           Index := Index + 1;
                        end if;
                     end loop;
                     return False;
                  end;
               end if;
               return Text (Position) = Atom (Atom'First);
            end One;

            Position : Positive := T;
            After    : Positive;
         begin
            for Count in 1 .. Repeat loop
               if not One (Position, After) then
                  return False;
               end if;
               Position := After;
            end loop;
            return Match_From (Pattern, Next, Text, Position);
         end;
      end;
   end Match_From;

   function Matches (Pattern, Text : String) return Boolean is
     (Pattern'Length > 0 and then Pattern (Pattern'First) = '^' and then
      Match_From (Pattern, Pattern'First + 1, Text, Text'First));

   type Document_Access is access Document;

   function Validate (Schema_Directory, Schema_File, Document : String) return String is
      Common   : constant Document_Access := new Jsonlib.Documents.Document;
      Primary  : constant Document_Access := new Jsonlib.Documents.Document;
      Instance : Jsonlib.Documents.Document;
      Error    : Jsonlib.Errors.Error_Info;

      function Load (Into : Document_Access; Name : String) return Boolean is
         Text : constant String := Project_Tools.Files.Read_Raw_File (Schema_Directory & "/" & Name);
      begin
         Jsonlib.Parsers.Parse (Text, Into.all, Error);
         return Error.Code = Jsonlib.Errors.No_Error;
      end Load;

      function Check
        (Schema : Document_Access; Rule : Node; Value : Node; Path : String) return String;

      function Resolve (Schema : Document_Access; Reference : String; Path : String) return String is
         Hash   : constant Natural := Ada.Strings.Fixed.Index (Reference, "#/$defs/");
         Name   : constant String := Reference (Hash + 8 .. Reference'Last);
         Target : constant Document_Access := (if Hash > Reference'First then Common else Schema);
         Defs   : constant Node := Target.Member (Target.Root, "$defs");
      begin
         if not Is_Present (Defs) or else not Target.Has_Member (Defs, Name) then
            return Path & ": unresolved reference " & Reference;
         end if;
         return "";
      end Resolve;

      function Kind_Name (Value : Node) return String is
        (case Instance.Kind (Value) is
            when Null_Value => "null",
            when Boolean_Value => "boolean",
            when Integer_Value => "integer",
            when Float_Value => "number",
            when String_Value => "string",
            when Array_Value => "array",
            when Object_Value => "object");

      function Same_Value (Schema : Document_Access; Expected : Node; Value : Node) return Boolean is
        (Jsonlib.Serializers.To_String (Schema.all, Expected) = Jsonlib.Serializers.To_String (Instance, Value));

      function Check
        (Schema : Document_Access; Rule : Node; Value : Node; Path : String) return String
      is
         S : Jsonlib.Documents.Document renames Schema.all;
      begin
         if S.Has_Member (Rule, "$ref") then
            declare
               Reference : constant String := S.As_String (S.Member (Rule, "$ref"));
               Problem   : constant String := Resolve (Schema, Reference, Path);
               Hash      : constant Natural := Ada.Strings.Fixed.Index (Reference, "#/$defs/");
               Target    : constant Document_Access := (if Hash > Reference'First then Common else Schema);
            begin
               if Problem'Length > 0 then
                  return Problem;
               end if;
               return Check
                 (Target, Target.Member (Target.Member (Target.Root, "$defs"), Reference (Hash + 8 .. Reference'Last)),
                  Value, Path);
            end;
         end if;
         if S.Has_Member (Rule, "oneOf") then
            declare
               Options : constant Node := S.Member (Rule, "oneOf");
               Passed  : Natural := 0;
            begin
               for Index in 1 .. S.Length (Options) loop
                  if Check (Schema, S.Element (Options, Index), Value, Path)'Length = 0 then
                     Passed := Passed + 1;
                  end if;
               end loop;
               if Passed /= 1 then
                  return Path & ": matches" & Natural'Image (Passed) & " oneOf alternatives";
               end if;
            end;
         end if;
         if S.Has_Member (Rule, "const") and then not Same_Value (Schema, S.Member (Rule, "const"), Value) then
            return Path & ": does not equal the required constant";
         end if;
         if S.Has_Member (Rule, "enum") then
            declare
               Choices : constant Node := S.Member (Rule, "enum");
               Found   : Boolean := False;
            begin
               for Index in 1 .. S.Length (Choices) loop
                  Found := Found or else Same_Value (Schema, S.Element (Choices, Index), Value);
               end loop;
               if not Found then
                  return Path & ": value " & Jsonlib.Serializers.To_String (Instance, Value) & " is not enumerated";
               end if;
            end;
         end if;
         if S.Has_Member (Rule, "type") then
            declare
               Wanted : constant String := S.As_String (S.Member (Rule, "type"));
            begin
               if Wanted /= Kind_Name (Value) then
                  return Path & ": expected " & Wanted & ", found " & Kind_Name (Value);
               end if;
            end;
         end if;
         case Instance.Kind (Value) is
            when Integer_Value =>
               if S.Has_Member (Rule, "minimum") and then
                 Instance.As_Integer (Value) < S.As_Integer (S.Member (Rule, "minimum"))
               then
                  return Path & ": below minimum";
               end if;
            when String_Value =>
               if S.Has_Member (Rule, "minLength") and then
                 Instance.As_String (Value)'Length < Natural (S.As_Integer (S.Member (Rule, "minLength")))
               then
                  return Path & ": string too short";
               elsif S.Has_Member (Rule, "pattern") and then
                 not Matches (S.As_String (S.Member (Rule, "pattern")), Instance.As_String (Value))
               then
                  return Path & ": " & Instance.As_String (Value) & " does not match " &
                    S.As_String (S.Member (Rule, "pattern"));
               end if;
            when Array_Value =>
               if S.Has_Member (Rule, "maxItems") and then
                 Instance.Length (Value) > Natural (S.As_Integer (S.Member (Rule, "maxItems")))
               then
                  return Path & ": too many items";
               end if;
               if S.Has_Member (Rule, "items") then
                  for Index in 1 .. Instance.Length (Value) loop
                     declare
                        Problem : constant String :=
                          Check (Schema, S.Member (Rule, "items"), Instance.Element (Value, Index),
                                 Path & "[" & Ada.Strings.Fixed.Trim (Natural'Image (Index - 1), Ada.Strings.Both) &
                                   "]");
                     begin
                        if Problem'Length > 0 then
                           return Problem;
                        end if;
                     end;
                  end loop;
               end if;
            when Object_Value =>
               if S.Has_Member (Rule, "required") then
                  declare
                     Required : constant Node := S.Member (Rule, "required");
                  begin
                     for Index in 1 .. S.Length (Required) loop
                        if not Instance.Has_Member (Value, S.As_String (S.Element (Required, Index))) then
                           return Path & ": missing " & S.As_String (S.Element (Required, Index));
                        end if;
                     end loop;
                  end;
               end if;
               for Index in 1 .. Instance.Length (Value) loop
                  declare
                     Member_Name : constant String := Instance.Name (Value, Index);
                     Properties  : constant Node :=
                       (if S.Has_Member (Rule, "properties") then S.Member (Rule, "properties") else No_Node);
                  begin
                     if Is_Present (Properties) and then S.Has_Member (Properties, Member_Name) then
                        declare
                           Problem : constant String :=
                             Check (Schema, S.Member (Properties, Member_Name), Instance.Element (Value, Index),
                                    Path & "." & Member_Name);
                        begin
                           if Problem'Length > 0 then
                              return Problem;
                           end if;
                        end;
                     elsif S.Has_Member (Rule, "additionalProperties") then
                        return Path & ": undocumented member " & Member_Name;
                     end if;
                  end;
               end loop;
            when others =>
               null;
         end case;
         return "";
      end Check;
   begin
      if not Load (Common, "common.schema.json") or else not Load (Primary, Schema_File) then
         return "schema cannot be parsed";
      end if;
      Jsonlib.Parsers.Parse (Document, Instance, Error);
      if Error.Code /= Jsonlib.Errors.No_Error then
         return "document is not valid JSON";
      end if;
      return Check (Primary, Primary.Root, Instance.Root, "$");
   end Validate;
end Aqs_Schema;
