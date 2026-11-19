with Ada.Containers.Ordered_Maps;
with Ada.Strings.Unbounded;
with Ada_Quality.Indicators;
with Ada_Quality.Types;
with Jsonlib.Documents;

package body Ada_Quality_Summary.SARIF is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Types;
   use Ada_Quality_Summary.Model;
   use Jsonlib.Documents;

   Schema_URI      : constant String := "https://json.schemastore.org/sarif-2.1.0.json";
   Information_URI : constant String := "https://github.com/bracke/ada_quality_summary";
   Fingerprint_Key : constant String := "adaQualityFinding/v1";

   function Encode (Path : String) return String is
      Hex    : constant String := "0123456789ABCDEF";
      Result : Ada.Strings.Unbounded.Unbounded_String;
   begin
      for C of Path loop
         if C in 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '-' | '.' | '_' | '~' | '/' then
            Append (Result, C);
         else
            Append (Result, '%' & Hex (Character'Pos (C) / 16 + 1) & Hex (Character'Pos (C) mod 16 + 1));
         end if;
      end loop;
      return To_String (Result);
   end Encode;

   function File_URI (Path : String) return String is
     ("file://" & Encode (Path) & (if Path'Length > 0 and then Path (Path'Last) = '/' then "" else "/"));

   --  Root with exactly one trailing slash.
   function Directory_Of (Root : String) return String is
     (if Root'Length > 0 and then Root (Root'Last) = '/' then Root else Root & "/");

   function Is_Inside (Root, Path : String) return Boolean is
     (Path & "/" = Directory_Of (Root) or else Path = Directory_Of (Root) or else
      (Path'Length > Directory_Of (Root)'Length and then
       Path (Path'First .. Path'First + Directory_Of (Root)'Length - 1) = Directory_Of (Root)));

   function Relative (Root, Path : String) return String is
     (if not Is_Inside (Root, Path) then Path
      elsif Path'Length <= Directory_Of (Root)'Length then ""
      else Path (Path'First + Directory_Of (Root)'Length .. Path'Last));

   --  The project-relative file a finding points at: its path, or the project manifest when it has none.
   Manifest : constant String := "alire.toml";

   function Level_Of (Level : Severity) return String is
     (case Level is
         when Critical | High => "error",
         when Medium => "warning",
         when Low | Info => "note");

   package Rule_Maps is new Ada.Containers.Ordered_Maps (Indicator_Id, Natural);

   package Project_Maps is new Ada.Containers.Ordered_Maps (Positive, Project_Summary);

   function Render
     (Item : Ada_Quality_Summary.Reports.Report; Source_Root : String; Pretty : Boolean := False;
      Maximum_Bytes : Positive := Ada_Quality_Summary.JSON.Default_Maximum_Bytes) return String
   is
      Doc      : Document;
      Rules    : Rule_Maps.Map;
      Projects : Project_Maps.Map;

      function Str (Value : String) return Node is (Doc.New_String (Value));
      function Nat (Value : Natural) return Node is (Doc.New_Integer (Long_Long_Integer (Value)));

      procedure Put (Object : Node; Name : String; Value : Node) is
      begin
         Doc.Insert (Object, Name, Value);
      end Put;

      function Text_Object (Text : String) return Node is
         Object : constant Node := Doc.New_Object;
      begin
         Put (Object, "text", Str (Text));
         return Object;
      end Text_Object;

      --  One rule per indicator that has a finding, in registry order; Rules maps each to its index.
      function Rules_Array return Node is
         List : constant Node := Doc.New_Array;
      begin
         for Finding of Item.Findings loop
            Rules.Include (Finding.Indicator, 0);
         end loop;
         for Position in Rules.Iterate loop
            declare
               Id         : constant Indicator_Id := Rule_Maps.Key (Position);
               Descriptor : constant Ada_Quality.Indicators.Indicator_Descriptor :=
                 Ada_Quality.Indicators.Registry (Id);
               Rule       : constant Node := Doc.New_Object;
               Properties : constant Node := Doc.New_Object;
            begin
               Rules.Replace_Element (Position, Doc.Length (List));
               Put (Rule, "id", Str (Image (Id)));
               Put (Rule, "name", Str (Descriptor.Name.all));
               Put (Rule, "shortDescription", Text_Object (Descriptor.Name.all));
               Put (Properties, "category",
                    Str (Image (Descriptor.Category)));
               Put (Rule, "properties", Properties);
               Doc.Append (List, Rule);
            end;
         end loop;
         return List;
      end Rules_Array;

      --  The one location of a finding, relative to the source root when the project lies inside it.
      function Location_Array (Finding : Finding_Summary) return Node is
         List     : constant Node := Doc.New_Array;
         Location : constant Node := Doc.New_Object;
         Physical : constant Node := Doc.New_Object;
         Artifact : constant Node := Doc.New_Object;
         Project  : constant String := To_String (Projects.Element (Finding.Project_Id).Project_Path);
         File     : constant String := (if Length (Finding.Path) > 0 then To_String (Finding.Path) else Manifest);
         Inner    : constant String := Relative (Source_Root, Project);
      begin
         if Is_Inside (Source_Root, Project) then
            Put (Artifact, "uri", Str (Encode (if Inner = "" then File else Inner & "/" & File)));
            Put (Artifact, "uriBaseId", Str (Source_Root_Id));
         else
            Put (Artifact, "uri", Str (File_URI (Project) & Encode (File)));
         end if;
         Put (Physical, "artifactLocation", Artifact);
         if Finding.Line > 0 and then Length (Finding.Path) > 0 then
            declare
               Region : constant Node := Doc.New_Object;
            begin
               Put (Region, "startLine", Nat (Finding.Line));
               Put (Physical, "region", Region);
            end;
         end if;
         Put (Location, "physicalLocation", Physical);
         Doc.Append (List, Location);
         return List;
      end Location_Array;

      function Name_Of (Project_Id : Positive) return String is (To_String (Projects.Element (Project_Id).Name));

      function Result_Object (Finding : Finding_Summary) return Node is
         Result       : constant Node := Doc.New_Object;
         Fingerprints : constant Node := Doc.New_Object;
         Properties   : constant Node := Doc.New_Object;
      begin
         Put (Result, "ruleId", Str (Image (Finding.Indicator)));
         Put (Result, "ruleIndex", Nat (Rules.Element (Finding.Indicator)));
         Put (Result, "level", Str (Level_Of (Finding.Level)));
         Put (Result, "message",
              Text_Object (if Length (Finding.Message) > 0 then To_String (Finding.Message)
                           else To_String (Finding.Rule)));
         Put (Result, "locations", Location_Array (Finding));
         Put (Fingerprints, Fingerprint_Key, Str (To_String (Finding.Fingerprint)));
         Put (Result, "partialFingerprints", Fingerprints);
         if Is_Waiver (Finding) then
            declare
               Suppressions : constant Node := Doc.New_Array;
               Suppression  : constant Node := Doc.New_Object;
            begin
               Put (Suppression, "kind", Str ("inSource"));
               Put (Suppression, "justification", Str (Waiver_Justification (To_String (Finding.Message))));
               Doc.Append (Suppressions, Suppression);
               Put (Result, "suppressions", Suppressions);
            end;
         end if;
         Put (Properties, "project_id", Nat (Finding.Project_Id));
         Put (Properties, "project", Str (Name_Of (Finding.Project_Id)));
         Put (Properties, "run_id", Nat (Finding.Run_Id));
         Put (Properties, "rule", Str (To_String (Finding.Rule)));
         Put (Properties, "severity",
              Str (Image (Finding.Level)));
         Put (Result, "properties", Properties);
         return Result;
      end Result_Object;

      --  The source root that relative locations resolve against.
      function Bases_Object return Node is
         Object : constant Node := Doc.New_Object;
         Base   : constant Node := Doc.New_Object;
      begin
         Put (Base, "uri", Str (File_URI (Source_Root)));
         Put (Object, Source_Root_Id, Base);
         return Object;
      end Bases_Object;

      Root    : constant Node := Doc.New_Object;
      Runs    : constant Node := Doc.New_Array;
      Run     : constant Node := Doc.New_Object;
      Tool    : constant Node := Doc.New_Object;
      Driver  : constant Node := Doc.New_Object;
      Results : constant Node := Doc.New_Array;
   begin
      for Project of Item.Portfolio.Projects loop
         Projects.Include (Project.Project_Id, Project);
      end loop;
      Put (Root, "$schema", Str (Schema_URI));
      Put (Root, "version", Str (SARIF_Version));
      Put (Driver, "name", Str ("ada-quality-summary"));
      Put (Driver, "version", Str (Version));
      Put (Driver, "informationUri", Str (Information_URI));
      Put (Driver, "rules", Rules_Array);
      Put (Tool, "driver", Driver);
      Put (Run, "tool", Tool);
      Put (Run, "originalUriBaseIds", Bases_Object);
      for Finding of Item.Findings loop
         Doc.Append (Results, Result_Object (Finding));
      end loop;
      Put (Run, "results", Results);
      Doc.Append (Runs, Run);
      Put (Root, "runs", Runs);
      Doc.Set_Root (Root);
      return Ada_Quality_Summary.JSON.Serialize (Doc, Pretty, Maximum_Bytes);
   end Render;
end Ada_Quality_Summary.SARIF;
