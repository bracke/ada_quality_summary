with Ada_Quality_Summary.JSON;
with Ada_Quality_Summary.Model;
with Ada_Quality_Summary.Reports;

--  SARIF 2.1.0 serialization of the problems report, for code-scanning tools such as GitHub code scanning.
--
--  Each finding becomes one result whose rule is its indicator. As code-scanning services expect, a location inside
--  the source root (the working directory of the invocation) is relative to it through the `%SRCROOT%` base; a
--  location outside it is an absolute `file:` URI. A finding without a path is located at its project's
--  `alire.toml`, so every result has a location. The stored finding fingerprint is the result's partial fingerprint,
--  and a review-waiver finding is reported as suppressed in source with its justification.
package Ada_Quality_Summary.SARIF is
   --  SARIF 2.1.0 serialization of the problems report.

   SARIF_Version : constant String := "2.1.0";
   --  SARIF specification version written.

   Source_Root_Id : constant String := "%SRCROOT%";
   --  Name of the source-root base in `originalUriBaseIds`.

   function Render
     (Item : Ada_Quality_Summary.Reports.Report; Source_Root : String; Pretty : Boolean := False;
      Maximum_Bytes : Positive := Ada_Quality_Summary.JSON.Default_Maximum_Bytes) return String
   with Pre => Ada_Quality_Summary.Model."=" (Item.Metadata.Kind, Ada_Quality_Summary.Model.Problems_Report);
   --  Serialize the findings of a problems report as a SARIF log with one run; other reports have no SARIF form.
   --  @param Item Problems report data.
   --  @param Source_Root Absolute directory that relative locations are resolved against.
   --  @param Pretty Whether to indent.
   --  @param Maximum_Bytes Size limit.
   --  @return UTF-8 SARIF text ending with a line feed.
   --  @exception Report_Error The document exceeds Maximum_Bytes.

   function File_URI (Path : String) return String;
   --  Return the `file:` URI of a directory, percent-encoded and ending with a slash.
   --  @param Path Absolute directory path.
   --  @return URI such as `file:///home/user/alpha/`.

   function Relative (Root, Path : String) return String;
   --  Return Path relative to Root.
   --  @param Root Absolute directory, with or without a trailing slash.
   --  @param Path Absolute path.
   --  @return The part of Path below Root, empty for Root itself, or Path unchanged when it is not inside Root.

   function Is_Inside (Root, Path : String) return Boolean;
   --  Test whether Path is Root or lies below it.
   --  @param Root Absolute directory, with or without a trailing slash.
   --  @param Path Absolute path.
   --  @return True when Path is inside Root.

   function Encode (Path : String) return String;
   --  Percent-encode a path for a URI, keeping slashes and unreserved characters.
   --  @param Path Relative or absolute path.
   --  @return URI path.
end Ada_Quality_Summary.SARIF;
