with Ada_Quality_Summary.Limits;
with Ada_Quality_Summary.Options;
with Ada_Quality_Summary.Reports;

--  Width-aware, noninteractive terminal rendering of report data.
--
--  Widths are measured in display cells through the humanize Unicode utilities. No line exceeds the selected
--  width, statuses are always spelled out, and colors come from terminal_styles. Rendering performs no database
--  access and no compliance calculation.
package Ada_Quality_Summary.Terminal is
   --  Width-aware, noninteractive terminal rendering of report data.

   Default_Width : constant := 80;
   --  Width used when none can be determined.

   Maximum_Field_Width : constant := Ada_Quality_Summary.Limits.Maximum_Field_Width;
   --  Largest displayed text field, in display cells.

   type Settings is record
      Width   : Positive := Default_Width;
      Color   : Boolean := False;
      Unicode : Boolean := False;
      Layout  : Ada_Quality_Summary.Options.Layout_Mode := Ada_Quality_Summary.Options.Normal_Layout;
   end record;
   --  Presentation settings.
   --  @field Width Display width in cells.
   --  @field Color Whether ANSI styling is emitted.
   --  @field Unicode Whether the ellipsis character may be used.
   --  @field Layout Compact, normal, or detailed layout.

   function Render (Item : Ada_Quality_Summary.Reports.Report; Style : Settings) return String;
   --  Render a complete report.
   --  @param Item Report data.
   --  @param Style Presentation settings.
   --  @return Text with line feeds; every line fits Style.Width display cells.

   function Stdout_Is_Terminal return Boolean;
   --  Test whether standard output is a terminal.
   --  @return True for a terminal device.

   function Detect_Width (Explicit : Natural) return Positive;
   --  Select the display width: explicit option, terminal size, COLUMNS, or 80, held to the supported range 20 .. 500.
   --  @param Explicit Width from `--width`, or zero.
   --  @return Width in display cells.

   function Use_Color (Mode : Ada_Quality_Summary.Options.Color_Mode) return Boolean;
   --  Apply the color mode through terminal_styles, honoring NO_COLOR and redirected output for `auto`.
   --  @param Mode Requested mode.
   --  @return Whether ANSI styling is emitted.

   function Unicode_Locale return Boolean;
   --  Test whether the locale environment selects UTF-8.
   --  @return True when LC_ALL, LC_CTYPE, or LANG names UTF-8.

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
end Ada_Quality_Summary.Terminal;
