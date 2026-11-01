--  Read-only reporting over persisted Ada Quality assessments.
--
--  The application selects, aggregates, filters, and renders data obtained through
--  Ada_Quality.Reporting. Assessment semantics, storage, and history comparison remain owned by Ada Quality.
package Ada_Quality_Summary is
   --  Read-only reporting over persisted Ada Quality assessments.

   Version : constant String := "0.1.0";
   --  Application version.

   Report_Format_Version : constant := 1;
   --  Version of the JSON report envelope and every report-specific schema.

   Argument_Error : exception;
   --  Raised for an invalid command, option, filter, project, or indicator; exit code 2.

   Report_Error : exception;
   --  Raised for a reporting, serialization, unsupported-data, or output failure; exit code 3.

   Data_Error : exception;
   --  Raised for a database, schema, locking, resource-limit, or data-integrity failure; exit code 4.
end Ada_Quality_Summary;
