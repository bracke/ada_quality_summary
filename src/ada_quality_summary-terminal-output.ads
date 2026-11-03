with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

--  Width-bounded line output for the terminal renderer: an output buffer, styled fields, wrapped notes, and tables
--  that shrink text, drop optional columns, or fall back to records to fit the terminal width.
private package Ada_Quality_Summary.Terminal.Output is
   --  Width-bounded line output for the terminal renderer.

   subtype Unbounded_String is Ada.Strings.Unbounded.Unbounded_String;
   --  Dynamically sized text.

   type Role_Kind is (No_Role, Good_Role, Bad_Role, Warn_Role, Muted_Role);
   --  Semantic color of a value.
   --  @enum No_Role Plain text.
   --  @enum Good_Role Success styling.
   --  @enum Bad_Role Error styling.
   --  @enum Warn_Role Warning styling.
   --  @enum Muted_Role Muted styling.

   type Writer is record
      Text  : Unbounded_String;
      Style : Settings;
   end record;
   --  Output buffer and the presentation settings it is written with.
   --  @field Text Lines written so far, each ending with a line feed.
   --  @field Style Presentation settings.

   function Decorate (Out_Text : Writer; Text : String; Role : Role_Kind) return String;
   --  Apply the color of Role when color output is enabled.
   --  @param Out_Text Writer whose settings decide coloring.
   --  @param Text Text to style.
   --  @param Role Semantic color.
   --  @return Text, styled when color is enabled and Role is not No_Role.

   procedure Emit (Out_Text : in out Writer; Line : String);
   --  Append one line, shortened to the terminal width when it is plain text.
   --  @param Out_Text Writer.
   --  @param Line Line without its line feed.

   procedure Blank (Out_Text : in out Writer);
   --  Append an empty line.
   --  @param Out_Text Writer.

   procedure Heading (Out_Text : in out Writer; Text : String);
   --  Append a section heading, bold when color is enabled.
   --  @param Out_Text Writer.
   --  @param Text Heading text.

   procedure Field
     (Out_Text    : in out Writer;
      Label       : String;
      Value       : String;
      Label_Width : Natural := 0;
      Role        : Role_Kind := No_Role;
      Number      : Boolean := False);
   --  Append `  Label  Value`, truncating only the value; at very narrow widths label and value take one line each.
   --  @param Out_Text Writer.
   --  @param Label Field label.
   --  @param Value Field value.
   --  @param Label_Width Width the label is padded to.
   --  @param Role Semantic color of the value.
   --  @param Number Whether the value is a number, which is never truncated.

   type Column is record
      Header   : Unbounded_String;
      Right    : Boolean := False;
      Shrink   : Boolean := False;
      Priority : Positive := 1;
      Minimum  : Natural := 4;
   end record;
   --  Table column.
   --  @field Header Column header.
   --  @field Right Whether values are right-aligned.
   --  @field Shrink Whether values may be truncated to fit.
   --  @field Priority One for essential columns; two and three are dropped first at narrower widths.
   --  @field Minimum Narrowest width a shrinking column is truncated to.

   package Column_Vectors is new Ada.Containers.Vectors (Positive, Column);
   --  Table columns.

   type Cell is record
      Text : Unbounded_String;
      Role : Role_Kind := No_Role;
   end record;
   --  Table cell.
   --  @field Text Cell text.
   --  @field Role Semantic color of the cell.

   package Cell_Vectors is new Ada.Containers.Vectors (Positive, Cell);
   --  Cells of one row.

   package Row_Vectors is new Ada.Containers.Vectors (Positive, Cell_Vectors.Vector, Cell_Vectors."=");
   --  Table rows.

   function Col
     (Header   : String;
      Right    : Boolean := False;
      Shrink   : Boolean := False;
      Priority : Positive := 1;
      Minimum  : Natural := 4) return Column;
   --  Build a column.
   --  @param Header Column header.
   --  @param Right Whether values are right-aligned.
   --  @param Shrink Whether values may be truncated to fit.
   --  @param Priority Column priority.
   --  @param Minimum Narrowest truncated width.
   --  @return Column.

   function C (Text : String; Role : Role_Kind := No_Role) return Cell;
   --  Build a cell.
   --  @param Text Cell text.
   --  @param Role Semantic color.
   --  @return Cell.

   function Tier (Out_Text : Writer) return Positive;
   --  Return the highest column priority shown for the layout and width.
   --  @param Out_Text Writer.
   --  @return One, two, or three.

   procedure Table (Out_Text : in out Writer; Columns : Column_Vectors.Vector; Rows : Row_Vectors.Vector);
   --  Render rows as aligned columns, shrinking text and dropping optional columns to fit; fall back to records.
   --  @param Out_Text Writer.
   --  @param Columns Columns.
   --  @param Rows Rows, each with one cell per column.

   procedure Note (Out_Text : in out Writer; Text : String; Indent : Natural := 2);
   --  Append prose wrapped at word boundaries; continuation lines are indented two further cells, and a single
   --  word wider than the line is truncated rather than split.
   --  @param Out_Text Writer.
   --  @param Text Prose.
   --  @param Indent Indentation of the first line.

   procedure Shown_Note (Out_Text : in out Writer; Shown, Total : Natural);
   --  Append a note that only Shown of Total rows are listed, when a row limit applied.
   --  @param Out_Text Writer.
   --  @param Shown Rows listed.
   --  @param Total Rows before the limit.
end Ada_Quality_Summary.Terminal.Output;
