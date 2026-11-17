with Ada.Strings.Unbounded;
with Interfaces;
with Project_Tools.Processes;

package body Aqs_Evidence is
   function Digest (Text : String) return String is
      use type Interfaces.Unsigned_64;
      Hash   : Interfaces.Unsigned_64 := 16#CBF29CE484222325#;
      Hex    : constant String := "0123456789abcdef";
      Result : String (1 .. 16);
   begin
      for C of Text loop
         Hash := (Hash xor Interfaces.Unsigned_64 (Character'Pos (C))) * 16#100000001B3#;
      end loop;
      for J in reverse Result'Range loop
         Result (J) := Hex (Natural (Hash and 15) + 1);
         Hash := Interfaces.Shift_Right (Hash, 4);
      end loop;
      return Result;
   end Digest;

   function Toolchain_Fingerprint (Root : String) return String is
      package P renames Project_Tools.Processes;
      Alr : constant String := P.Locate_Command ("alr");
   begin
      if Alr'Length = 0 then
         return "";
      end if;
      declare
         Version : constant P.Captured_Process :=
           P.Capture ("toolchain", Root, Alr,
                      P.Arguments ([P.Argument ("exec"), P.Argument ("--"), P.Argument ("gnatls"),
                                    P.Argument ("--version")]),
                      Quiet => True);
      begin
         return (if Version.Status = 0 then Digest (Ada.Strings.Unbounded.To_String (Version.Output)) else "");
      end;
   end Toolchain_Fingerprint;
end Aqs_Evidence;
