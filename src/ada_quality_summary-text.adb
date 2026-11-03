with Ada.Strings.Fixed;
with Messages.Arguments;
with Messages.Result;
with Messages.Runtime;

package body Ada_Quality_Summary.Text is
   use Ada.Strings.Unbounded;
   use type Messages.Result.Render_Status;
   use type Messages.Runtime.Load_Status;

   LF : constant Character := Character'Val (10);

   --  Every user-visible diagnostic and label. ICU syntax: `{name}` is a placeholder.
   Catalog : constant String :=
     "default_locale=en" & LF &
     --  Argument diagnostics.
     "en.error.date_order = --since must not be later than --until" & LF &
     "en.error.duplicate_option = option {option} was given more than once" & LF &
     "en.error.empty_database = --database requires a nonempty path" & LF &
     "en.error.invalid_choice = invalid value {value} for {option}; expected one of: {choices}" & LF &
     "en.error.invalid_date = invalid date {value}; expected YYYY-MM-DD" & LF &
     "en.error.invalid_number = invalid number {value} for {option}" & LF &
     "en.error.json_only = option {option} applies only to --format json" & LF &
     "en.error.missing_indicator = command indicator requires an indicator ID such as TST-03" & LF &
     "en.error.missing_project = command {command} requires a PROJECT argument" & LF &
     "en.error.missing_value = option {option} requires a value" & LF &
     "en.error.option_not_allowed = option {option} is not accepted by command {command}" & LF &
     "en.error.sort_not_allowed = sort key {value} is not supported by command {command}" & LF &
     "en.error.terminal_only = option {option} applies only to terminal output" & LF &
     "en.error.unexpected_argument = unexpected argument {argument}" & LF &
     "en.error.unexpected_value = option {option} does not take a value" & LF &
     "en.error.unknown_command = unknown command {command}" & LF &
     "en.error.unknown_option = unknown option {option}" & LF &
     "en.error.unknown_sort = unknown sort key {value}" & LF &
     "en.error.width_range = --width must be between {minimum} and {maximum}" & LF &
     "en.error.version_alone = --version takes no other arguments" & LF &
     "en.error.unknown_project = unknown project {project}" & LF &
     "en.error.ambiguous_project = project name {project} is ambiguous; matching project IDs: {ids}" & LF &
     "en.error.unknown_indicator = unknown indicator {indicator}" & LF &
     --  Runtime diagnostics.
     "en.error.prefix = ada-quality-summary: {message}" & LF &
     "en.error.hint = run ada-quality-summary help for usage" & LF &
     "en.error.output = cannot write report output: {message}" & LF &
     "en.error.json_size = JSON report of {size} bytes exceeds the limit of {limit} bytes" & LF &
     "en.error.text_size = a text field exceeds the limit of {limit} display cells" & LF &
     "en.error.internal = internal error: {message}" & LF &
     "en.label.title = ADA QUALITY SUMMARY" & LF &
     "en.label.projects_column = Projects" & LF &
     "en.label.status.passing = Passing" & LF &
     "en.label.status.violations = Violations" & LF &
     "en.label.status.incomplete = Incomplete" & LF &
     "en.label.status.unassessed = Unassessed" & LF &
     "en.label.quality_status = QUALITY STATUS" & LF &
     "en.label.projects = PROJECTS" & LF &
     "en.label.common_violations = COMMON VIOLATIONS" & LF &
     "en.label.regressions_heading = REGRESSIONS" & LF &
     "en.label.activity = ASSESSMENT ACTIVITY" & LF &
     "en.label.indicators = INDICATORS" & LF &
     "en.label.problems = PROBLEMS" & LF &
     "en.label.trends = TRENDS" & LF &
     "en.label.baselines = BASELINES" & LF &
     "en.label.findings_heading = FINDINGS" & LF &
     "en.label.evidence_heading = EVIDENCE" & LF &
     "en.label.by_indicator = FINDINGS BY INDICATOR" & LF &
     "en.label.daily_states = LAST-KNOWN STATE BY DAY" & LF &
     "en.label.project_title = PROJECT {value}" & LF &
     "en.label.history_title = HISTORY {value}" & LF &
     "en.label.database = Database: {value}" & LF &
     "en.label.snapshot = Snapshot: {value}" & LF &
     "en.label.population = Projects: {registered} registered, {enabled} enabled" & LF &
     "en.label.totals_line = Passing {passing}, violations {violations}, incomplete {incomplete}," &
       " unassessed {unassessed}" & LF &
     "en.label.showing = Showing {shown} of {total} rows" & LF &
     "en.label.projects_with_regressions = Projects with regressions: {value}" & LF &
     "en.label.regression_count = Regressions: {value}" & LF &
     "en.label.newer_running = Newer running assessments: {value}" & LF &
     "en.label.newer_unfinished = Newer interrupted or invalid assessments: {value}" & LF &
     "en.label.finding_total = Findings: {value}" & LF &
     "en.label.undated = Runs without persisted timestamps excluded by the date filter: {value}" & LF &
     "en.label.counts_value = {passed}/{applicable} applicable passing, {violated} violated," &
       " {unknown} unknown, {na} not applicable" & LF &
     "en.label.series_counts = Projects included {included}, excluded {excluded}; excluded" &
       " observations {observations}" & LF &
     "en.label.history_counts = Completed {completed}, running {running}, interrupted {interrupted}," &
       " invalid {invalid}" & LF &
     "en.label.baseline.compared = compared with baseline run {value}" & LF &
     "en.label.baseline.none = no compatible baseline" & LF &
     "en.label.baseline.no_current = no completed assessment" & LF &
     "en.label.baseline.excluded = skipped run {run}: {reason}" & LF &
     "en.label.reason.missing_source_fingerprint = source fingerprint missing" & LF &
     "en.label.reason.policy_changed = policy fingerprint differs" & LF &
     "en.label.reason.toolchain_changed = toolchain fingerprint differs" & LF &
     "en.label.format.lossless = lossless" & LF &
     "en.label.format.legacy = legacy (no finding locations)" & LF &
     "en.label.newer.running = running" & LF &
     "en.label.newer.interrupted = interrupted" & LF &
     "en.label.newer.invalid = invalid" & LF &
     "en.label.newer.none = none" & LF &
     "en.label.no_projects = No projects selected." & LF &
     "en.label.no_findings = No findings." & LF &
     "en.label.no_regressions = No regressions." & LF &
     "en.label.no_runs = No runs." & LF &
     "en.label.no_assessment = No completed assessment exists for this project." & LF &
     "en.label.no_dated_assessments = No completed assessment with a persisted timestamp." & LF &
     "en.label.no_numeric = No comparable numeric measurements." & LF &
     "en.label.none = None." & LF &
     "en.label.unavailable = unavailable" & LF &
     "en.label.yes = yes" & LF &
     "en.label.no = no" & LF &
     "en.label.project = Project" & LF &
     "en.label.quality = Quality" & LF &
     "en.label.pass = Pass" & LF &
     "en.label.fail = Fail" & LF &
     "en.label.unknown = Unknown" & LF &
     "en.label.not_applicable = N/A" & LF &
     "en.label.findings = Findings" & LF &
     "en.label.id = ID" & LF &
     "en.label.run = Run" & LF &
     "en.label.regressions = Regr" & LF &
     "en.label.enabled = Enabled" & LF &
     "en.label.path = Path" & LF &
     "en.label.indicator = Indicator" & LF &
     "en.label.name = Name" & LF &
     "en.label.severity = Severity" & LF &
     "en.label.location = Location" & LF &
     "en.label.rule = Rule" & LF &
     "en.label.message = Message" & LF &
     "en.label.kind = Kind" & LF &
     "en.label.before = Before" & LF &
     "en.label.after = After" & LF &
     "en.label.baseline = Baseline" & LF &
     "en.label.removed = Removed" & LF &
     "en.label.current_run = Current run" & LF &
     "en.label.latest_run = Latest run" & LF &
     "en.label.newer_run = Newer run" & LF &
     "en.label.counts = Indicators" & LF &
     "en.label.finished = Finished" & LF &
     "en.label.started = Started" & LF &
     "en.label.source = Source" & LF &
     "en.label.policy = Policy" & LF &
     "en.label.toolchain = Toolchain" & LF &
     "en.label.evidence_format = Evidence" & LF &
     "en.label.compliance = Result" & LF &
     "en.label.execution = Execution" & LF &
     "en.label.measurement = Measurement" & LF &
     "en.label.summary = Summary" & LF &
     "en.label.violation = Violation" & LF &
     "en.label.missing = Missing" & LF &
     "en.label.category = Category" & LF &
     "en.label.version = Version" & LF &
     "en.label.unit = Unit" & LF &
     "en.label.state = State" & LF &
     "en.label.date = Date" & LF &
     "en.label.value = Value" & LF &
     "en.label.observed = Observed" & LF &
     "en.quality.passing = PASSING" & LF &
     "en.quality.violations = VIOLATIONS" & LF &
     "en.quality.incomplete = INCOMPLETE" & LF &
     "en.quality.unassessed = UNASSESSED" & LF &
     "en.short.passing = PASS" & LF &
     "en.short.violations = VIOL" & LF &
     "en.short.incomplete = INCP" & LF &
     "en.short.unassessed = NONE" & LF &
     "en.state.pass = PASS" & LF &
     "en.state.violation = VIOLATION" & LF &
     "en.state.unknown = UNKNOWN" & LF &
     "en.state.not_applicable = N/A" & LF &
     "en.state.missing = MISSING" & LF &
     "en.run.running = running" & LF &
     "en.run.completed = completed" & LF &
     "en.run.invalid = invalid" & LF &
     "en.run.interrupted = interrupted" & LF &
     "en.category.structure = Structure" & LF &
     "en.category.build = Build" & LF &
     "en.category.test = Testing" & LF &
     "en.category.source = Source" & LF &
     "en.category.documentation = Documentation" & LF &
     "en.category.dependency = Dependencies" & LF &
     "en.category.security = Security" & LF &
     "en.category.release = Release" & LF &
     "en.category.proof = Proof" & LF &
     "en.help.usage = Usage: ada-quality-summary [OPTIONS] [COMMAND]" & LF &
     "en.help.commands = Commands:" & LF &
     "en.help.options = Global options:" & LF &
     "en.help.command_usage = Usage: ada-quality-summary [OPTIONS] {usage}" & LF &
     "en.help.accepts = Accepted options:" & LF &
     "en.help.sort_keys = Sort keys: {keys}" & LF &
     "en.help.exit = Exit codes: 0 report generated, 2 invalid arguments, 3 reporting failure, 4" &
       " database failure." & LF &
     "en.help.cmd.summary = Overall quality overview (default)" & LF &
     "en.help.cmd.projects = Project status table" & LF &
     "en.help.cmd.project = Detailed project assessment" & LF &
     "en.help.cmd.indicators = Cross-project indicator summary" & LF &
     "en.help.cmd.indicator = Detailed indicator report" & LF &
     "en.help.cmd.problems = Outstanding quality findings" & LF &
     "en.help.cmd.regressions = Quality regressions" & LF &
     "en.help.cmd.trends = Historical quality trends" & LF &
     "en.help.cmd.history = Individual project history" & LF &
     "en.help.cmd.help = Help and usage" & LF &
     "en.help.opt.database = Assessment database path" & LF &
     "en.help.opt.format = Output format (default: terminal)" & LF &
     "en.help.opt.color = Terminal color selection" & LF &
     "en.help.opt.no_color = Alias for --color never" & LF &
     "en.help.opt.layout = Terminal layout" & LF &
     "en.help.opt.width = Override detected display width" & LF &
     "en.help.opt.include_removed = Include tombstoned projects" & LF &
     "en.help.opt.enabled_only = Include only enabled projects" & LF &
     "en.help.opt.project = Restrict collection reports to a project" & LF &
     "en.help.opt.status = Filter by project status" & LF &
     "en.help.opt.sort = Command-specific sorting" & LF &
     "en.help.opt.reverse = Reverse selected ordering" & LF &
     "en.help.opt.limit = Maximum result rows (0 means no limit)" & LF &
     "en.help.opt.since = Earliest history date (inclusive)" & LF &
     "en.help.opt.until = Latest history date (inclusive)" & LF &
     "en.help.opt.pretty = Indent JSON output" & LF &
     "en.help.opt.help = Show help" & LF &
     "en.help.opt.version = Show the version" & LF &
     "en.help.version = ada-quality-summary {version}" & LF;

   Runtime : Messages.Runtime.Instance;
   Loaded  : Boolean := False;
   Valid   : Boolean := False;

   procedure Ensure_Loaded is
      Result : Messages.Runtime.Load_Result;
   begin
      if not Loaded then
         Messages.Runtime.Load_Text (Runtime, "ada-quality-summary", Catalog, Result);
         Valid := Result.Status = Messages.Runtime.Loaded;
         Loaded := True;
      end if;
   end Ensure_Loaded;

   function Arg (Name, Value : String) return Argument is
     (Name => To_Unbounded_String (Name), Value => To_Unbounded_String (Value));

   function Arg (Name : String; Value : Long_Long_Integer) return Argument is
     (Arg (Name, Ada.Strings.Fixed.Trim (Long_Long_Integer'Image (Value), Ada.Strings.Both)));

   function Has_Message (Key : String) return Boolean is
     (Ada.Strings.Fixed.Index (Catalog, LF & "en." & Key & " = ") > 0);

   function Message (Key : String; Args : Argument_List := No_Arguments) return String is
      Values : Messages.Arguments.Arguments;
   begin
      Ensure_Loaded;
      if not Valid or else not Has_Message (Key) then
         raise Report_Error with "missing message " & Key;
      end if;
      for Item of Args loop
         Messages.Arguments.Set (Values, To_String (Item.Name), To_String (Item.Value));
      end loop;
      declare
         Rendered : constant Messages.Result.Render_Result := Messages.Runtime.Render (Runtime, "en", Key, Values);
      begin
         if Rendered.Status /= Messages.Result.Success then
            raise Report_Error with "cannot render message " & Key;
         end if;
         return Messages.Result.Output_Text (Rendered.Text);
      end;
   end Message;

   function Catalog_Is_Valid return Boolean is
   begin
      Ensure_Loaded;
      return Valid;
   end Catalog_Is_Valid;
end Ada_Quality_Summary.Text;
