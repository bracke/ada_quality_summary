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
| `Resolve_Assessment (Item, Reference)` | Run identity of a decimal run ID or an assessment alias. |
| `Compare_Project (Item, Project_Id[, Current_Id])` | Baseline selection and regressions for the current assessment, or for a chosen one. |
| `Compare_Assessments (Item, Baseline_Id, Current_Id)` | Compatibility decision and regressions for exactly two chosen assessments. |
| `History_Items`, `Read_History_Evidence`, `All_Measurements` | Opaque rows for `Ada_Quality.History`. |
| `Optional_Timestamp`, `Image` | Persisted instant, absent for legacy runs. |
| `Load_Limits` | Project, run, and finding row limits. |

`Ada_Quality.Indicators.Measurement_Unit` returns the unit of each indicator's numeric measurement, or `none`.

## `Ada_Quality_Summary`

| Unit | Main declarations |
| ---- | ----------------- |
| `Ada_Quality_Summary` | `Version`, `Report_Format_Version`, `Database_Variable`, `Default_Database`, `Color_Variable`, `Width_Variable`, `Argument_Error`, `Report_Error`, `Data_Error`. |
| `.Limits` | `Maximum_Projects`, `Maximum_Runs`, `Maximum_Findings`, `Maximum_Width`, `Maximum_Field_Width`, `Maximum_Output_Bytes`, `Default_Load`. |
| `.Criteria` | `Sort_Key`, `Image`, `Date_Bound`, `Day_Start`, `Day_Image`, `Within`, `Gate_Condition`, `Gate_Set`, `Gate_Counts`. |
| `.Options` | `Options`, `Command_Kind`, `Named_Command`, `Option_Kind`, `Output_Format`, `Shell_Kind`, `Spelling`, `Value_Name`, `Usage`, `Help_Key`, `Accepts`, `Parse`, `Parse_Date`, `Allowed`, `Is_Collection`, `Is_Historical`, `Name`, `Report_Of`. |
| `.Rules` | `Quality_State`, `Newer_State`, `Result_State`, `Indicator_Totals`, `Portfolio_Totals`. |
| `.Rules.Counting` | `Total`, `Applicable`, `Sum`, `Tally`, `Classify`, `Priority`, `Classified`, `Consistent`, `Add_Classified`, `Add_Project` (SPARK, proved). |
| `.Model` | `Project_Quality_State`, `Indicator_State`, `State_Of`, `Indicator_Totals`, `Project_Summary`, `Portfolio_Totals`, `Portfolio_Summary`, `Indicator_Summary`, `Indicator_Row`, `Finding_Summary`, `Summary_Of`, `Regression_Summary`, `History_Summary`, `Trend_Summary`, `Baseline_Info`, `Pair_Comparison`, `State_Snapshot`, `Waiver_Rule`, `Is_Waiver`, `Waiver_Target`, `Waiver_Justification`, `Report_Kind`, `Report_Metadata`, `Basename`, stable images of severities, categories, and lifecycle states, `Classify`, `Count_Indicators`, `Quality_Priority`, images. |
| `.Repository` | `Repository`, `Snapshot`, `Open`, `Load`, indexed queries, `Assessment`, `Result_Of`, `Run_Facts`, `Facts`, `Resolve_Run`, `Compare`, `Compare_Runs`. |
| `.Filtering` | `Selection`, `Parse_Project_Id`, `Resolve_Project`, `Resolve_Indicator`, `Population`, sorting procedures, `Limit`. |
| `.Aggregation` | `Build_Project`, `Build_Projects`, `Build_Totals`, `Build_Portfolio`, `Build_Indicator`, `Build_Indicators`, `Build_Findings`, `Findings_Of`, `State_Of`. |
| `.Trends` | `Regressions`, `Compare_Pair`, `Run_Summary`, `History`, `Metric_Series`, `Undated_Runs`, `Daily_States`. |
| `.Reports` | `Report`, `Build`; the report-kind table in the specification lists the fields each kind fills. |
| `.Reports.Assembly` | `Context`, `Comparison`, `Comparison_Maps`, `Start`, `Select_Projects`, `Compare_Selected`, `Summarize_Population`, `Fill_Command`, `Count_Gate`. |
| `.Terminal` | `Settings` (including the Markdown mode), `Render`. |
| `.Terminal.Environment` | `Stdout_Is_Terminal`, `Clamp`, `Detect_Width`, `Use_Color`, `Unicode_Locale`. |
| `.Terminal.Cells` | `Display_Width`, `Fit`, `Pad`, `Basis_Points_Image`. |
| `.JSON` | `Render`, `Serialize`. |
| `.SARIF` | `Render (Item, Source_Root, ...)`, `Source_Root_Id`, `Relative`, `Is_Inside`, `File_URI`, `Encode`. |
| `.Completion` | `Script`, `Choices`. |
| `.CLI` | `Execute`, `Run`, `Outcome`, exit-code constants. |
| `.Text` | `Message`, `Arg`, `Decimal`, `Bounded`, `Catalog_Is_Valid`, `Has_Message`. |

Aggregation, filtering, trends, and report assembly are deterministic. Their only side effect is the memo of run
facts inside the snapshot, which changes no result. `Terminal.Environment.Use_Color` sets the process-wide
`terminal_styles` color policy. The renderers neither access the database nor compute compliance.

Generate the reference with `alr exec -- gnatdoc -P ada_quality_summary.gpr`.
