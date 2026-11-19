with Ada.Calendar;

--  Strict, noninteractive parsing behind Options.Parse and Options.Parse_Date: options are read with their values,
--  the command word is recognized, its positional arguments are assigned by name, and every option is checked
--  against the command it applies to.
private package Ada_Quality_Summary.Options.Parsing is
   --  Command-line parsing.

   function Parse (Arguments : String_Vectors.Vector) return Options;
   --  Parse and validate a complete command line.
   --  @param Arguments Command-line arguments without the program name.
   --  @return Validated options.
   --  @exception Argument_Error Any unknown, duplicate, missing, malformed, or incompatible argument.

   function Parse_Date (Text : String) return Ada.Calendar.Time;
   --  Parse an ISO `YYYY-MM-DD` date as midnight UTC.
   --  @param Text Date text.
   --  @return Instant.
   --  @exception Argument_Error Text is not a valid calendar date.
end Ada_Quality_Summary.Options.Parsing;
