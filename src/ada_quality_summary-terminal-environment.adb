with Ada.Characters.Handling;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Hostkit.Descriptors;
with Hostkit.Terminal_Control;
with Terminal_Styles;

package body Ada_Quality_Summary.Terminal.Environment is
   use Ada_Quality_Summary.Options;

   --  Terminal detection and size come from hostkit, which answers portably for POSIX terminals and Windows consoles.
   function Stdout_Is_Terminal return Boolean is
     (Hostkit.Descriptors.Is_Terminal (Hostkit.Descriptors.Standard_Output));

   --  A detected width of zero is unknown; any other width is held to the supported range, so a very narrow terminal
   --  gets the minimum layout rather than a width the renderer does not support.
   function Clamp (Width : Natural) return Positive is
     (if Width = 0 then Default_Width
      else Positive'Max (Options.Minimum_Width, Positive'Min (Width, Options.Maximum_Width)));

   function Detect_Width (Explicit : Natural) return Positive is
   begin
      if Explicit > 0 then
         return Clamp (Explicit);
      end if;
      if Stdout_Is_Terminal then
         declare
            Size : Hostkit.Terminal_Control.Window_Size;
         begin
            if Hostkit.Terminal_Control.Size (Hostkit.Descriptors.Standard_Output, Size) and then Size.Columns > 0
            then
               return Clamp (Size.Columns);
            end if;
         end;
      end if;
      if Ada.Environment_Variables.Exists ("COLUMNS") then
         declare
            Text : constant String := Ada.Environment_Variables.Value ("COLUMNS");
         begin
            if Text'Length in 1 .. 4 and then (for all C of Text => C in '0' .. '9') then
               return Clamp (Natural'Value (Text));
            end if;
         end;
      end if;
      return Default_Width;
   end Detect_Width;

   function Use_Color (Mode : Color_Mode) return Boolean is
   begin
      Terminal_Styles.Set_Color_Policy
        (case Mode is
            when Color_Auto => Terminal_Styles.Color_Auto,
            when Color_Always => Terminal_Styles.Color_Always,
            when Color_Never => Terminal_Styles.Color_Never);
      return Terminal_Styles.Color_Enabled (Destination_Is_Terminal => Stdout_Is_Terminal);
   end Use_Color;

   function Unicode_Locale return Boolean is
      function Names_UTF8 (Variable : String) return Boolean is
      begin
         if not Ada.Environment_Variables.Exists (Variable) then
            return False;
         end if;
         declare
            Value : constant String := Ada.Characters.Handling.To_Lower (Ada.Environment_Variables.Value (Variable));
         begin
            return Ada.Strings.Fixed.Index (Value, "utf-8") > 0 or else Ada.Strings.Fixed.Index (Value, "utf8") > 0;
         end;
      end Names_UTF8;

      function Set (Variable : String) return Boolean is
        (Ada.Environment_Variables.Exists (Variable) and then Ada.Environment_Variables.Value (Variable)'Length > 0);
   begin
      --  The first nonempty variable in POSIX precedence order decides.
      if Set ("LC_ALL") then
         return Names_UTF8 ("LC_ALL");
      elsif Set ("LC_CTYPE") then
         return Names_UTF8 ("LC_CTYPE");
      end if;
      return Names_UTF8 ("LANG");
   end Unicode_Locale;
end Ada_Quality_Summary.Terminal.Environment;
