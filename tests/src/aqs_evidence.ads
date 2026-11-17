--  Coverage-evidence identity shared by the coverage gate that writes the evidence and the release gate that checks
--  it: the inventory format and the toolchain fingerprint, computed the way Ada Quality's TST-03 computes them.
package Aqs_Evidence is
   --  Coverage-evidence format and toolchain identity.

   Inventory : constant String := "gcov-production-lines-v3";
   --  Evidence format Ada Quality's TST-03 requires.

   function Digest (Text : String) return String;
   --  Return the FNV-1a digest Ada Quality applies to toolchain output.
   --  @param Text Tool output.
   --  @return Sixteen lowercase hexadecimal digits.

   function Toolchain_Fingerprint (Root : String) return String;
   --  Return the digest of `alr exec -- gnatls --version` in Root.
   --  @param Root Crate root.
   --  @return Fingerprint, or empty when alr or gnatls is unavailable.
end Aqs_Evidence;
