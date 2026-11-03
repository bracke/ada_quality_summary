with Ada.Strings.Fixed;
with Ada_Quality_Summary.Text;
with Terminal_Styles;

package body Ada_Quality_Summary.Terminal.Output is
   use Ada.Strings.Unbounded;
   use Ada_Quality_Summary.Options;

   LF : constant Character := Character'Val (10);

   function Decorate (Out_Text : Writer; Text : String; Role : Role_Kind) return String is
   begin
      if not Out_Text.Style.Color or else Role = No_Role then
         return Text;
      end if;
      return Terminal_Styles.Decorate
        (Text,
         (case Role is
             when Good_Role => Terminal_Styles.Role_Success,
             when Bad_Role => Terminal_Styles.Role_Error,
             when Warn_Role => Terminal_Styles.Role_Warning,
             when Muted_Role => Terminal_Styles.Role_Muted,
             when No_Role => Terminal_Styles.Role_Info),
         Destination_Is_Terminal => True);
   end Decorate;

   procedure Emit (Out_Text : in out Writer; Line : String) is
      Plain : constant Boolean := Ada.Strings.Fixed.Index (Line, [Character'Val (27)]) = 0;
   begin
      --  Every construction below already fits; this guard keeps the no-overflow contract unconditional.
      if Plain and then Display_Width (Line) > Out_Text.Style.Width then
         Append (Out_Text.Text, Fit (Line, Out_Text.Style.Width, Out_Text.Style.Unicode) & LF);
      else
         Append (Out_Text.Text, Ada.Strings.Fixed.Trim (Line, Ada.Strings.Right) & LF);
      end if;
   end Emit;

   procedure Blank (Out_Text : in out Writer) is
   begin
      Append (Out_Text.Text, LF);
   end Blank;

   procedure Heading (Out_Text : in out Writer; Text : String) is
      Fitted : constant String := Fit (Text, Out_Text.Style.Width, Out_Text.Style.Unicode);
   begin
      if Out_Text.Style.Color then
         Emit (Out_Text, Terminal_Styles.Decorate (Fitted, Terminal_Styles.Decoration_Bold, True));
      else
         Emit (Out_Text, Fitted);
      end if;
   end Heading;

   procedure Field
     (Out_Text    : in out Writer;
      Label       : String;
      Value       : String;
      Label_Width : Natural := 0;
      Role        : Role_Kind := No_Role;
      Number      : Boolean := False)
   is
      Prefix : constant String := "  " & Pad (Label, Label_Width) & "  ";
      Room   : constant Integer := Out_Text.Style.Width - Display_Width (Prefix);
      Shown  : constant String :=
        (if Number or else Room <= 0 then Value
         else Fit (Fit (Value, Maximum_Field_Width, Out_Text.Style.Unicode), Room, Out_Text.Style.Unicode));
   begin
      if Display_Width (Prefix) + Display_Width (Shown) > Out_Text.Style.Width then
         --  A very narrow width: label and value on separate lines.
         Emit (Out_Text, Fit ("  " & Label, Out_Text.Style.Width, Out_Text.Style.Unicode));
         Emit (Out_Text, "    " & Decorate (Out_Text, Fit (Value, Out_Text.Style.Width - 4, Out_Text.Style.Unicode),
                                           Role));
      else
         Emit (Out_Text, Prefix & Decorate (Out_Text, Shown, Role));
      end if;
   end Field;

   function Col
     (Header   : String;
      Right    : Boolean := False;
      Shrink   : Boolean := False;
      Priority : Positive := 1;
      Minimum  : Natural := 4) return Column is
     ((Header => To_Unbounded_String (Header), Right => Right, Shrink => Shrink, Priority => Priority,
       Minimum => Minimum));

   function C (Text : String; Role : Role_Kind := No_Role) return Cell is
     ((Text => To_Unbounded_String (Text), Role => Role));

   function Tier (Out_Text : Writer) return Positive is
     (case Out_Text.Style.Layout is
         when Compact_Layout => 1,
         when Normal_Layout => (if Out_Text.Style.Width < 80 then 1 elsif Out_Text.Style.Width < 120 then 2 else 3),
         when Detailed_Layout => 3);

   procedure Table (Out_Text : in out Writer; Columns : Column_Vectors.Vector; Rows : Row_Vectors.Vector) is
      Count   : constant Natural := Natural (Columns.Length);
      Visible : array (1 .. Count) of Boolean := [others => False];
      Widths  : array (1 .. Count) of Natural := [others => 0];
      Indent  : constant Natural := 2;
      Gap     : constant Natural := 2;
      Record_Tier : constant Positive :=
        (case Out_Text.Style.Layout is
            when Compact_Layout => 1,
            when Normal_Layout => 2,
            when Detailed_Layout => 3);

      function Floor (Index : Positive) return Natural is
        (Natural'Max (Columns (Index).Minimum, Display_Width (To_String (Columns (Index).Header))));

      function Total return Natural is
         Sum, Shown : Natural := 0;
      begin
         for Index in 1 .. Count loop
            if Visible (Index) then
               Sum := Sum + Widths (Index);
               Shown := Shown + 1;
            end if;
         end loop;
         return Indent + Sum + (if Shown > 1 then Gap * (Shown - 1) else 0);
      end Total;

      procedure Records is
      begin
         for Row of Rows loop
            for Index in 1 .. Count loop
               if Index = 1 then
                  Emit (Out_Text, Fit ("  " & To_String (Row (Index).Text), Out_Text.Style.Width,
                                       Out_Text.Style.Unicode));
               elsif Columns (Index).Priority <= Record_Tier then
                     declare
                        Label : constant String := To_String (Columns (Index).Header) & ": ";
                        Value : constant String := To_String (Row (Index).Text);
                        Room  : constant Integer := Out_Text.Style.Width - 4 - Display_Width (Label);
                     begin
                        if Room >= Display_Width (Value) or else (Room > 0 and then Columns (Index).Shrink) then
                           Emit (Out_Text, "    " & Label &
                                   Decorate (Out_Text, Fit (Value, Room, Out_Text.Style.Unicode), Row (Index).Role));
                        else
                           Emit (Out_Text, Fit ("    " & Label, Out_Text.Style.Width, Out_Text.Style.Unicode));
                           Emit (Out_Text, "      " & Decorate
                                   (Out_Text, Fit (Value, Out_Text.Style.Width - 6, Out_Text.Style.Unicode),
                                    Row (Index).Role));
                        end if;
                     end;
               end if;
            end loop;
         end loop;
      end Records;

      function Line_Of (Row : Cell_Vectors.Vector; Header : Boolean) return String is
         Result : Unbounded_String := To_Unbounded_String ([1 .. Indent => ' ']);
         First  : Boolean := True;
      begin
         for Index in 1 .. Count loop
            if Visible (Index) then
               if not First then
                  Append (Result, [1 .. Gap => ' ']);
               end if;
               First := False;
               declare
                  Raw    : constant String :=
                    (if Header then To_String (Columns (Index).Header) else To_String (Row (Index).Text));
                  Shown  : constant String := Fit (Raw, Widths (Index), Out_Text.Style.Unicode);
                  Padded : constant String := Pad (Shown, Widths (Index), Columns (Index).Right);
               begin
                  Append (Result, (if Header then Padded else Decorate (Out_Text, Padded, Row (Index).Role)));
               end;
            end if;
         end loop;
         return To_String (Result);
      end Line_Of;

      --  Start each visible column at the width of its widest content.
      procedure Measure is
      begin
         for Index in 1 .. Count loop
            Visible (Index) := Columns (Index).Priority <= Tier (Out_Text);
            Widths (Index) := Display_Width (To_String (Columns (Index).Header));
            for Row of Rows loop
               Widths (Index) := Natural'Max
                 (Widths (Index), Natural'Min (Maximum_Field_Width, Display_Width (To_String (Row (Index).Text))));
            end loop;
         end loop;
      end Measure;

      --  Shrink text columns, widest first, before dropping any column.
      procedure Shrink_Text is
      begin
         while Total > Out_Text.Style.Width loop
            declare
               Widest : Natural := 0;
            begin
               for Index in 1 .. Count loop
                  if Visible (Index) and then Columns (Index).Shrink and then Widths (Index) > Floor (Index)
                    and then (Widest = 0 or else Widths (Index) > Widths (Widest))
                  then
                     Widest := Index;
                  end if;
               end loop;
               exit when Widest = 0;
               Widths (Widest) := Widths (Widest) - Natural'Min (Widths (Widest) - Floor (Widest),
                                                                Natural'Max (1, Total - Out_Text.Style.Width));
            end;
         end loop;
      end Shrink_Text;

      --  Drop optional columns from the right, least essential first.
      procedure Drop_Optional is
      begin
         for Priority in reverse 2 .. 3 loop
            for Index in reverse 1 .. Count loop
               exit when Total <= Out_Text.Style.Width;
               if Visible (Index) and then Columns (Index).Priority = Priority then
                  Visible (Index) := False;
               end if;
            end loop;
         end loop;
      end Drop_Optional;
   begin
      if Out_Text.Style.Width < 40 then
         Records;
         return;
      end if;
      Measure;
      Shrink_Text;
      Drop_Optional;
      if Total > Out_Text.Style.Width then
         Records;
         return;
      end if;
      declare
         Header : constant String := Line_Of (Cell_Vectors.Empty_Vector, Header => True);
      begin
         Emit (Out_Text, Header);
         Emit (Out_Text, "  " & [1 .. Total - Indent => '-']);
      end;
      for Row of Rows loop
         Emit (Out_Text, Line_Of (Row, Header => False));
      end loop;
   end Table;

   procedure Note (Out_Text : in out Writer; Text : String; Indent : Natural := 2) is
      Line    : Unbounded_String;
      Used    : Natural := 0;
      Lead    : Natural := Indent;
      Start   : Positive := Text'First;

      procedure Flush is
      begin
         Emit (Out_Text, [1 .. Lead => ' '] & To_String (Line));
         Line := Null_Unbounded_String;
         Used := 0;
         Lead := Indent + 2;
      end Flush;

      procedure Add (Word : String) is
         Limit : constant Positive := Positive'Max (8, Out_Text.Style.Width - Lead);
         Cells : constant Natural := Display_Width (Word);
      begin
         if Used > 0 and then Used + 1 + Cells > Limit then
            Flush;
         end if;
         declare
            Fitted : constant String :=
              Fit (Word, Positive'Max (8, Out_Text.Style.Width - Lead), Out_Text.Style.Unicode);
         begin
            if Used > 0 then
               Append (Line, ' ');
               Used := Used + 1;
            end if;
            Append (Line, Fitted);
            Used := Used + Display_Width (Fitted);
         end;
      end Add;
   begin
      for Index in Text'First .. Text'Last + 1 loop
         if Index > Text'Last or else Text (Index) = ' ' then
            if Index > Start then
               Add (Text (Start .. Index - 1));
            end if;
            Start := Index + 1;
         end if;
      end loop;
      if Used > 0 or else Text'Length = 0 then
         Flush;
      end if;
   end Note;

   procedure Shown_Note (Out_Text : in out Writer; Shown, Total : Natural) is
   begin
      if Shown < Total then
         Note (Out_Text, Ada_Quality_Summary.Text.Message
                 ("label.showing", [Ada_Quality_Summary.Text.Arg ("shown", Long_Long_Integer (Shown)),
                                    Ada_Quality_Summary.Text.Arg ("total", Long_Long_Integer (Total))]));
      end if;
   end Shown_Note;
end Ada_Quality_Summary.Terminal.Output;
