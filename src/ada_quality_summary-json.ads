with Ada_Quality_Summary.Reports;

--  Versioned JSON serialization of report data; no aggregation, database access, or terminal formatting.
package Ada_Quality_Summary.JSON is
   --  Versioned JSON serialization of report data.

   Default_Maximum_Bytes : constant := 256 * 1024 * 1024;
   --  Largest JSON document emitted.

   function Render
     (Item : Ada_Quality_Summary.Reports.Report; Pretty : Boolean := False;
      Maximum_Bytes : Positive := Default_Maximum_Bytes) return String;
   --  Serialize a complete report envelope.
   --  @param Item Report data.
   --  @param Pretty Whether to indent.
   --  @param Maximum_Bytes Size limit.
   --  @return UTF-8 JSON text ending with a line feed.
   --  @exception Report_Error The document exceeds Maximum_Bytes.
end Ada_Quality_Summary.JSON;
