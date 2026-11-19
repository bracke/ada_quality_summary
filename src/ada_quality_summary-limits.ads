with Ada_Quality.Reporting;

--  Every reporting resource limit, in one place.
--
--  The repository, option parser, terminal renderer, and JSON serializer take their limits from this package. Tests
--  configure smaller limits through the parameters that accept them, such as Repository.Open's Limits and
--  JSON.Render's Maximum_Bytes. Exceeding a load or JSON limit is a typed error; machine-readable output is never
--  truncated.
package Ada_Quality_Summary.Limits is
   --  Every reporting resource limit, in one place.

   Maximum_Projects : constant := 10_000;
   --  Largest number of project registry rows loaded.

   Maximum_Runs : constant := 1_000_000;
   --  Largest number of assessment runs loaded.

   Maximum_Findings : constant := 2_000_000;
   --  Largest number of finding records loaded.

   Maximum_Width : constant := 500;
   --  Widest accepted terminal width, in columns.

   Maximum_Field_Width : constant := 4_096;
   --  Largest displayed terminal text field, in display cells.

   Maximum_Output_Bytes : constant := 256 * 1024 * 1024;
   --  Largest report in any output format, in bytes.

   Default_Load : constant Ada_Quality.Reporting.Load_Limits :=
     (Max_Projects => Maximum_Projects, Max_Runs => Maximum_Runs, Max_Findings => Maximum_Findings, others => <>);
   --  Load limits passed to Ada_Quality.Reporting when a report opens a database. The row limits not named here
   --  (results, measurements, executions, events, total rows, and text bytes) keep Ada Quality's defaults. Every
   --  completed assessment stores 33 results, so the result-row limit admits fewer completed runs than Maximum_Runs.
end Ada_Quality_Summary.Limits;
