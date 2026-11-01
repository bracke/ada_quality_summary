with Ada.Strings.Unbounded;

--  User-visible message catalog rendered through the messages library.
package Ada_Quality_Summary.Text is
   --  User-visible message catalog rendered through the messages library.

   type Argument is record
      Name  : Ada.Strings.Unbounded.Unbounded_String;
      Value : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   --  One named message argument.
   --  @field Name Placeholder name.
   --  @field Value Substituted text.

   type Argument_List is array (Positive range <>) of Argument;
   --  Message arguments.

   No_Arguments : constant Argument_List (1 .. 0) := [others => <>];
   --  Empty argument list.

   function Arg (Name, Value : String) return Argument;
   --  Build one message argument.
   --  @param Name Placeholder name.
   --  @param Value Substituted text.
   --  @return Argument.

   function Arg (Name : String; Value : Long_Long_Integer) return Argument;
   --  Build one integer message argument.
   --  @param Name Placeholder name.
   --  @param Value Integer rendered without leading space.
   --  @return Argument.

   function Message (Key : String; Args : Argument_List := No_Arguments) return String;
   --  Render one catalog message in the default locale.
   --  @param Key Catalog key.
   --  @param Args Placeholder values.
   --  @return Rendered text.
   --  @exception Report_Error The key is unknown or an argument is missing.

   function Catalog_Is_Valid return Boolean;
   --  Validate the embedded catalog.
   --  @return True when every entry parses.

   function Has_Message (Key : String) return Boolean;
   --  Test whether a key exists in the catalog.
   --  @param Key Catalog key.
   --  @return True when Key is defined.
end Ada_Quality_Summary.Text;
