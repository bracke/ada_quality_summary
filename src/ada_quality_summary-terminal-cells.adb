with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Humanize.Status;
with Humanize.Strings;

package body Ada_Quality_Summary.Terminal.Cells is
   use Ada.Strings.Unbounded;

   Ellipsis : constant String := Character'Val (16#E2#) & Character'Val (16#80#) & Character'Val (16#A6#);

   function Trimmed (Value : Long_Long_Integer) return String is
     (Ada.Strings.Fixed.Trim (Long_Long_Integer'Image (Value), Ada.Strings.Both));

   function Display_Width (Text : String) return Natural is (Humanize.Strings.ANSI_Display_Width (Text));

   function Fit (Text : String; Width : Natural; Unicode : Boolean) return String is
   begin
      if Display_Width (Text) <= Width then
         return Text;
      elsif Width = 0 then
         return "";
      elsif Width < 3 and then not Unicode then
         return [1 .. Width => '.'];
      end if;
      declare
         Result : constant Humanize.Status.Text_Result :=
           Humanize.Strings.Truncate_Display_Width (Text, Width, (if Unicode then Ellipsis else "..."));
      begin
         if Humanize.Status.Is_Ok (Result) and then Display_Width (To_String (Result.Text)) <= Width then
            return To_String (Result.Text);
         end if;
         return [1 .. Width => '.'];
      end;
   end Fit;

   function Pad (Text : String; Width : Natural; Right : Boolean := False) return String is
      Used : constant Natural := Display_Width (Text);
      Fill : constant String := (if Used >= Width then "" else [1 .. Width - Used => ' ']);
   begin
      return (if Right then Fill & Text else Text & Fill);
   end Pad;

   function Basis_Points_Image (Value : Long_Long_Integer) return String is
      Magnitude : constant Long_Long_Integer := abs Value;
      Fraction  : constant Long_Long_Integer := Magnitude mod 100;
   begin
      return (if Value < 0 then "-" else "") & Trimmed (Magnitude / 100) & "." &
        (if Fraction < 10 then "0" else "") & Trimmed (Fraction) & "%";
   end Basis_Points_Image;
end Ada_Quality_Summary.Terminal.Cells;
