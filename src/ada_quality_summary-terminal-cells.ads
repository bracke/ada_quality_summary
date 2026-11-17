--  Display-cell text measurement and fitting for terminal output, through the humanize Unicode utilities.
package Ada_Quality_Summary.Terminal.Cells is
   --  Display-cell measurement, truncation, and padding.

   function Display_Width (Text : String) return Natural;
   --  Return the display width of UTF-8 text, ignoring ANSI escape sequences.
   --  @param Text UTF-8 text.
   --  @return Display cells.

   function Fit (Text : String; Width : Natural; Unicode : Boolean) return String;
   --  Truncate text at a grapheme boundary so that it fits Width display cells.
   --  @param Text UTF-8 text without ANSI escapes.
   --  @param Width Available cells.
   --  @param Unicode Whether to use the ellipsis character instead of three periods.
   --  @return Text unchanged when it fits, otherwise truncated with an ellipsis.

   function Pad (Text : String; Width : Natural; Right : Boolean := False) return String;
   --  Pad text with spaces to Width display cells.
   --  @param Text UTF-8 text, possibly decorated.
   --  @param Width Target cells.
   --  @param Right Whether to align right.
   --  @return Padded text.

   function Basis_Points_Image (Value : Long_Long_Integer) return String;
   --  Render a basis-point value as an exact percentage with two decimals.
   --  @param Value Hundredths of a percent.
   --  @return Text such as `91.23%`.
end Ada_Quality_Summary.Terminal.Cells;
