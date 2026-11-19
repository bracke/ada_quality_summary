with Ada.Calendar;

--  Report selection criteria shared by parsing, selection, history, and rendering: sort keys and calendar days.
--
--  These are domain values, not command-line syntax. Options produces them from arguments; Filtering, Trends, and
--  the renderers consume them without depending on the command-line layer.
package Ada_Quality_Summary.Criteria is
   --  Sort keys and UTC calendar-day bounds.

   type Sort_Key is
     (Default_Sort, Sort_Name, Sort_Id, Sort_Path, Sort_Quality, Sort_Violations, Sort_Unknown, Sort_Findings,
      Sort_Affected, Sort_Severity, Sort_Indicator, Sort_Project, Sort_Kind, Sort_Run, Sort_State);
   --  Ordering selected by `--sort`.
   --  @enum Default_Sort Command-specific default order.
   --  @enum Sort_Name Project or indicator name.
   --  @enum Sort_Id Project or indicator identity.
   --  @enum Sort_Path Project path.
   --  @enum Sort_Quality Quality priority.
   --  @enum Sort_Violations Violation count, descending.
   --  @enum Sort_Unknown Unknown count, descending.
   --  @enum Sort_Findings Finding count, descending.
   --  @enum Sort_Affected Affected-project count, descending.
   --  @enum Sort_Severity Severity, descending.
   --  @enum Sort_Indicator Indicator registry order.
   --  @enum Sort_Project Project identity.
   --  @enum Sort_Kind Regression classification.
   --  @enum Sort_Run Run identity.
   --  @enum Sort_State Result or lifecycle state.

   function Image (Key : Sort_Key) return String;
   --  Return the command-line spelling.
   --  @param Key Sort key.
   --  @return Lowercase key, or `default`.

   type Date_Bound (Present : Boolean := False) is record
      case Present is
         when True =>
            Value : Ada.Calendar.Time;
         when False =>
            null;
      end case;
   end record;
   --  Optional inclusive UTC calendar day, held as the start of that day.
   --  @field Present Whether a day is set.
   --  @field Value Midnight UTC at the start of the day.

   function Day_Start (Time : Ada.Calendar.Time) return Ada.Calendar.Time;
   --  Return midnight UTC at the start of the day containing Time.
   --  @param Time Instant.
   --  @return Start of its UTC day.

   function Day_Image (Time : Ada.Calendar.Time) return String;
   --  Return the UTC calendar day of Time as `YYYY-MM-DD`.
   --  @param Time Instant.
   --  @return Ten-character day.

   function Within (Time : Ada.Calendar.Time; Since, Until_Date : Date_Bound) return Boolean;
   --  Test whether Time falls on or after the Since day and on or before the Until_Date day, each when present.
   --  Days are compared, so the last representable day needs no exclusive upper bound past the calendar's range.
   --  @param Time Instant.
   --  @param Since Inclusive first day.
   --  @param Until_Date Inclusive last day.
   --  @return True when both present bounds admit Time.

   type Gate_Condition is (Gate_Regressions, Gate_Violations, Gate_Incomplete, Gate_Unassessed);
   --  A condition that `--fail-on` turns into a failing exit status.
   --  @enum Gate_Regressions A selected project regressed against its baseline, or the compared pair regressed.
   --  @enum Gate_Violations A selected project's current assessment violates an indicator.
   --  @enum Gate_Incomplete A selected project's current assessment has unknown results.
   --  @enum Gate_Unassessed A selected project has no completed assessment.

   type Gate_Set is array (Gate_Condition) of Boolean;
   --  Conditions requested with `--fail-on`.

   No_Gate : constant Gate_Set := [others => False];
   --  No condition requested.

   type Gate_Counts is array (Gate_Condition) of Natural;
   --  How often each condition holds in a report.

   function Image (Condition : Gate_Condition) return String;
   --  Return the command-line spelling.
   --  @param Condition Condition.
   --  @return `regressions`, `violations`, `incomplete`, or `unassessed`.
end Ada_Quality_Summary.Criteria;
