with Ada_Quality_Summary.Options;

--  The terminal environment of one invocation: whether standard output is a terminal, its width, color policy, and
--  locale. Detection goes through hostkit, which answers portably for POSIX terminals and Windows consoles.
package Ada_Quality_Summary.Terminal.Environment is
   --  Terminal detection, width, color policy, and locale.

   function Stdout_Is_Terminal return Boolean;
   --  Test whether standard output is a terminal.
   --  @return True for a terminal device.

   function Clamp (Width : Natural) return Positive;
   --  Hold a width to the supported range 20 .. 500; zero, meaning unknown, selects Default_Width.
   --  @param Width Requested or detected width.
   --  @return Supported width.

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

end Ada_Quality_Summary.Terminal.Environment;
