with Ada_Quality_Summary.Options;

--  Shell completion scripts generated from the command and option tables that parsing and help use, so completion
--  offers exactly the commands, options, and fixed choices the parser accepts.
package Ada_Quality_Summary.Completion is
   --  Shell completion scripts for bash, zsh, and fish.

   Program : constant String := "ada-quality-summary";
   --  Command name the scripts complete.

   function Choices (Option : Ada_Quality_Summary.Options.Option_Kind) return String;
   --  Return the fixed values an option accepts.
   --  @param Option Option.
   --  @return Space-separated values, or empty when the value is free text or the option is a flag.

   function Script (Shell : Ada_Quality_Summary.Options.Shell_Kind) return String;
   --  Return the completion script for a shell.
   --  @param Shell Shell.
   --  @return Script text ending with a line feed, to be sourced or installed in the shell's completion directory.
end Ada_Quality_Summary.Completion;
