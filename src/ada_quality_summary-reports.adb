with Ada_Quality_Summary.Reports.Assembly;

package body Ada_Quality_Summary.Reports is
   function Build
     (Data : Repository.Snapshot; Invocation : Options.Options; Database_Label : String) return Report
   is
      State : Assembly.Context;
   begin
      Assembly.Start (Data, Invocation, Database_Label, State);
      Assembly.Select_Projects (Data, Invocation, State);
      Assembly.Compare_Selected (Data, Invocation, State);
      Assembly.Summarize_Population (State);
      Assembly.Fill_Command (Data, Invocation, State);
      Assembly.Count_Gate (Invocation, State);
      return State.Item;
   end Build;
end Ada_Quality_Summary.Reports;
