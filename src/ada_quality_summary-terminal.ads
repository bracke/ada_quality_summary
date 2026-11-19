with Ada_Quality_Summary.Limits;
with Ada_Quality_Summary.Options;
with Ada_Quality_Summary.Reports;

--  Width-aware, noninteractive terminal rendering of report data, and the same content as Markdown.
--
--  Widths are measured in display cells through the humanize Unicode utilities. No line exceeds the selected
--  width, statuses are always spelled out, and colors come from terminal_styles. Rendering performs no database
--  access and no compliance calculation. In Markdown mode the same sections become headings, bullet lists, and
--  pipe tables without width limits, colors, or truncation, so both outputs always show the same facts.
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
      Markdown : Boolean := False;
   end record;
   --  Presentation settings.
   --  @field Width Display width in cells.
   --  @field Color Whether ANSI styling is emitted.
   --  @field Unicode Whether the ellipsis character may be used.
   --  @field Layout Compact, normal, or detailed layout.
   --  @field Markdown Whether to write GitHub-flavored Markdown instead of width-bounded text; Width, Color, and
   --  Unicode are then ignored.

   function Render (Item : Ada_Quality_Summary.Reports.Report; Style : Settings) return String;
   --  Render a complete report.
   --  @param Item Report data.
   --  @param Style Presentation settings.
   --  @return Text with line feeds; every line fits Style.Width display cells unless Style.Markdown is set.

end Ada_Quality_Summary.Terminal;
