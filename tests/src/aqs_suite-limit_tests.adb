separate (Aqs_Suite)
package body Limit_Tests is
   procedure Limits is
      Database : constant String := Standard_Database ("T042");
      Store    : Ada_Quality_Summary.Repository.Repository;
      Raised   : Boolean := False;
   begin
      Ada_Quality_Summary.Repository.Open (Store, Database, (Max_Findings => 1, others => <>));
      begin
         declare
            Data : constant Ada_Quality_Summary.Repository.Snapshot := Ada_Quality_Summary.Repository.Load (Store);
         begin
            Expect (Ada_Quality_Summary.Repository.Schema_Version (Data) = Ada_Quality.Reporting.Supported_Schema,
                    "unreachable");
         end;
      exception
         when Ada_Quality_Summary.Report_Error => Raised := True;
      end;
      Expect (Raised, "exceeding a resource limit is a typed reporting failure");
      declare
         Generous : Ada_Quality_Summary.Repository.Repository;
      begin
         Ada_Quality_Summary.Repository.Open (Generous, Database, (Max_Findings => 10, others => <>));
         declare
            Data : constant Ada_Quality_Summary.Repository.Snapshot := Ada_Quality_Summary.Repository.Load (Generous);
         begin
            Expect (Ada_Quality_Summary.Repository.Schema_Version (Data) = Ada_Quality.Reporting.Supported_Schema,
                    "a snapshot within the limit loads");
         end;
      end;
      declare
         Raised_JSON : Boolean := False;
      begin
         begin
            declare
               Ignored : constant String :=
                 Ada_Quality_Summary.JSON.Render (Ada_Quality_Summary.Reports.Report'(others => <>), False, 10);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Ada_Quality_Summary.Report_Error => Raised_JSON := True;
         end;
         Expect (Raised_JSON, "an oversized JSON document is a typed reporting failure");
      end;
      declare
         Raised : Boolean := False;
      begin
         begin
            Expect (Ada_Quality_Summary.Text.Bounded ("12345", 5) = "12345", "a report at the limit is kept");
            Expect (Ada_Quality_Summary.Text.Bounded ("123456", 5) = "", "unreachable");
         exception
            when Ada_Quality_Summary.Report_Error => Raised := True;
         end;
         Expect (Raised, "an oversized report in any format is a typed reporting failure");
      end;
   end Limits;

   procedure Large is
      Database : constant String := New_Database ("T043");
      Ignored  : Positive;
      Count    : constant := 40;
      Store    : Ada_Quality.Storage.Store;
   begin
      Ada_Quality.Storage.Open (Store, Database);
      for Index in 1 .. Count loop
         declare
            Name    : constant String := "p" & Ada.Strings.Fixed.Trim (Integer'Image (1_000 + Index), Ada.Strings.Both);
            Project : constant Positive := Register (Store, Parent (Database), Name);
         begin
            --  Distinct class sizes (16 passing, 12 violating, 8 incomplete, 4 unassessed), so a swapped total fails.
            case Index mod 10 is
               when 0 .. 3 => Ignored := Publish (Store, Build (Project, Shape));
               when 4 .. 6 => Ignored := Publish (Store, Build (Project, Shape ("DOC-01 SRC-0" &
                                                                   Character'Val (48 + Index mod 6 + 1))));
               when 7 .. 8 => Ignored := Publish (Store, Build (Project, Shape (Unknowns => "BLD-02")));
               when others => null;
            end case;
         end;
      end loop;
      Ada_Quality.Storage.Close (Store);
      declare
         First  : constant String := Json (Database, "summary");
         Second : constant String := Json (Database, "summary");
         Matrix : constant String := Json (Database, "indicators");
      begin
         Expect (First = Second, "large aggregation is deterministic");
         Expect_Equal (Value (First, "data.totals.projects"), "40", "every project is aggregated");
         Expect_Equal (Value (First, "data.totals.passing"), "16", "passing count");
         Expect_Equal (Value (First, "data.totals.violations"), "12", "violation count");
         Expect_Equal (Value (First, "data.totals.incomplete"), "8", "incomplete count");
         Expect_Equal (Value (First, "data.totals.unassessed"), "4", "unassessed count");
         Expect (Count_Of (First, "data.projects") = 40, "the overview lists every project without a limit");
         for Index in 0 .. 32 loop
            declare
               Row : constant String := "data.indicators[" & Ada.Strings.Fixed.Trim (Integer'Image (Index),
                                                                                    Ada.Strings.Both) & "].";
            begin
               Expect (Int (Value (Matrix, Row & "passed")) + Int (Value (Matrix, Row & "violated")) +
                         Int (Value (Matrix, Row & "unknown")) + Int (Value (Matrix, Row & "not_applicable")) +
                         Int (Value (Matrix, Row & "missing")) = 40, "indicator states sum to the population");
            end;
         end loop;
      end;
   end Large;

   procedure Registry_Grouping is
      Database : constant String := Standard_Database ("T044");
      Text     : constant String := Json (Database, "indicators");
      Counts   : array (Ada_Quality.Indicators.Indicator_Category) of Natural := [others => 0];
   begin
      Expect (Count_Of (Text, "data.indicators") = 33, "all 33 indicators are reported");
      for Id in Indicator_Id loop
         declare
            Row : constant String := "data.indicators[" &
              Ada.Strings.Fixed.Trim (Integer'Image (Indicator_Id'Pos (Id)), Ada.Strings.Both) & "].";
         begin
            Expect_Equal (Value (Text, Row & "id"), """" & Image (Id) & """", "registry order");
            Counts (Ada_Quality.Indicators.Registry (Id).Category) :=
              Counts (Ada_Quality.Indicators.Registry (Id).Category) + 1;
         end;
      end loop;
      Expect (Counts = [5, 4, 4, 6, 3, 3, 3, 4, 1], "registry grouping matches the fixed categories");
      Expect_Equal (Value (Text, "data.indicators[0].category"), """structure""", "categories come from the registry");
   end Registry_Grouping;

   procedure Unchanged is
      Database : constant String := Standard_Database ("T046");
      Before   : constant File_State_Vectors.Vector := Capture (Parent (Database));
   begin
      for Command of All_Commands loop
         for Format of Format_Names loop
            Expect (Exit_Of (Report (Database, Command.all & "|--format|" & Format.all)) = 0, Command.all);
         end loop;
      end loop;
      Expect (Same (Before, Capture (Parent (Database))), "no report changes any database artifact");
   end Unchanged;

   procedure Limit_Totals is
      Database : constant String := Standard_Database ("T048");
      Text     : constant String := Json (Database, "summary|--limit|1");
   begin
      Expect_Equal (Value (Text, "data.totals.projects"), "3", "totals are computed before the row limit");
      Expect (Count_Of (Text, "data.projects") = 1, "the limit applies to rows");
      Expect (Count_Of (Json (Database, "summary|--limit|0"), "data.projects") = 3, "--limit 0 means no limit");
      Expect (Contains (Output (Report (Database, "summary|--limit|1")), "Showing 1 of 3 rows"),
              "terminal output states that rows were limited");
   end Limit_Totals;

   procedure Unknown_Option is
      Result : constant Ada_Quality_Summary.CLI.Outcome := Run ("summary --frobnicate");
   begin
      Expect (Exit_Of (Result) = 2, "unknown options exit 2");
      Expect (Contains (Errors (Result), "unknown option --frobnicate"), "the option is named");
      Expect (Output (Result) = "", "nothing is written to standard output");
      Expect (Spawn ("--frobnicate").Status = 2, "the executable exits 2");
   end Unknown_Option;
end Limit_Tests;
