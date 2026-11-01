# Public Ada API

Every public declaration carries GNATdoc comments; this page summarizes the units and their contracts.

## `Ada_Quality.Reporting` (in `ada_quality`)

| Declaration | Contract |
| ----------- | -------- |
| `Session` | Limited controlled, immutable in-memory snapshot; never holds a database handle after `Open`. |
| `Open (Item, Path, Limits)` | Loads one coherent read-only snapshot; raises `Reporting_Error`, `Busy_Error`, `Schema_Error`, `Integrity_Error`, or `Limit_Error`. |
| `Close`, `Is_Open` | Discard and test the snapshot. |
| `Projects (Item, Include_Removed)` | Registry entries in ascending ID order. |
| `Runs (Item, Project_Id)` | Run metadata in every lifecycle state, ascending ID order, with optional UTC timestamps and evidence format. |
| `Read_Assessment (Item, Run_Id)` | Fully decoded completed assessment with 33 results in registry order. |
| `Supported_Schema_Version`, `Snapshot_Identity` | Provenance. |
| `History_Items`, `Read_History_Evidence`, `All_Measurements` | Opaque rows for `Ada_Quality.History`. |
| `Optional_Timestamp`, `Image` | Persisted instant, absent for legacy runs. |
| `Load_Limits` | Project, run, and finding row limits. |

`Ada_Quality.Indicators.Measurement_Unit` returns the unit of each indicator's numeric measurement, or `none`.

## `Ada_Quality_Summary`

| Unit | Main declarations |
| ---- | ----------------- |
| `Ada_Quality_Summary` | `Version`, `Report_Format_Version`, `Argument_Error`, `Report_Error`, `Data_Error`. |
| `.Options` | `Options`, `Command_Kind`, `Sort_Key`, `Parse`, `Parse_Date`, `Allowed`, `Is_Collection`, `Is_Historical`. |
| `.Model` | `Project_Quality_State`, `Indicator_Totals`, `Project_Summary`, `Portfolio_Totals`, `Portfolio_Summary`, `Indicator_Summary`, `Finding_Summary`, `Regression_Summary`, `History_Summary`, `Trend_Summary`, `Report_Metadata`, `Classify`, `Count_Indicators`. |
| `.Repository` | `Repository`, `Snapshot`, `Open`, `Load`, indexed queries, `Assessment`. |
| `.Filtering` | `Selection`, `Resolve_Project`, `Resolve_Indicator`, `Population`, sorting procedures, generic `Limit`. |
| `.Aggregation` | `Build_Project`, `Build_Projects`, `Build_Totals`, `Build_Portfolio`, `Build_Indicator`, `Build_Indicators`, `Build_Findings`, `State_Of`. |
| `.Trends` | `Regressions`, `History`, `Metric_Series`, `Daily_States`, `Baseline_Info`. |
| `.Reports` | `Report`, `Build`. |
| `.Terminal` | `Settings`, `Render`, `Detect_Width`, `Use_Color`, `Display_Width`, `Fit`, `Pad`, `Basis_Points_Image`. |
| `.JSON` | `Render`. |
| `.CLI` | `Execute`, `Run`, `Outcome`, exit-code constants. |
| `.Text` | `Message`, `Arg`, `Catalog_Is_Valid`, `Has_Message`. |

Aggregation, filtering, trends, and report assembly are deterministic and side-effect-free. The renderers neither
access the database nor compute compliance.

Generate the reference with `alr exec -- gnatdoc -P ada_quality_summary.gpr`.
