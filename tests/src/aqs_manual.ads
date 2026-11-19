--  The ada-quality-summary(1) manual page, generated from the command and option tables and the message catalog that
--  the parser and the help text use, so the manual cannot drift from the program.
package Aqs_Manual is
   --  The ada-quality-summary(1) manual page.

   Page_Path : constant String := "docs/ada-quality-summary.1";
   --  Committed manual page, relative to the project root.

   function Page return String;
   --  Return the manual page.
   --  @return roff text for man(7), without a date, so it is reproducible.
end Aqs_Manual;
