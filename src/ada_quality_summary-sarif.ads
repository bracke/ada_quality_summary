with Ada_Quality_Summary.JSON;
with Ada_Quality_Summary.Reports;

--  SARIF 2.1.0 serialization of the problems report, for code-scanning tools such as GitHub code scanning.
--
--  Each finding becomes one result whose rule is its indicator. Locations are project-relative and resolved through
--  one `originalUriBaseIds` entry per project, so findings of several projects stay distinguishable. The stored
--  finding fingerprint is the result's partial fingerprint, and a review-waiver finding is reported as suppressed in
--  source with its justification.
package Ada_Quality_Summary.SARIF is
   --  SARIF 2.1.0 serialization of the problems report.

   SARIF_Version : constant String := "2.1.0";
   --  SARIF specification version written.

   function Render
     (Item : Ada_Quality_Summary.Reports.Report; Pretty : Boolean := False;
      Maximum_Bytes : Positive := Ada_Quality_Summary.JSON.Default_Maximum_Bytes) return String;
   --  Serialize the findings of a problems report as a SARIF log with one run.
   --  @param Item Problems report data.
   --  @param Pretty Whether to indent.
   --  @param Maximum_Bytes Size limit.
   --  @return UTF-8 SARIF text ending with a line feed.
   --  @exception Report_Error The document exceeds Maximum_Bytes.

   function File_URI (Path : String) return String;
   --  Return the `file:` URI of a directory, percent-encoded and ending with a slash.
   --  @param Path Absolute directory path.
   --  @return URI such as `file:///home/user/alpha/`.

   function Encode (Path : String) return String;
   --  Percent-encode a path for a URI, keeping slashes and unreserved characters.
   --  @param Path Relative or absolute path.
   --  @return URI path.
end Ada_Quality_Summary.SARIF;
