unit polarity_pack_align;

// PackStatements ON (SPEC-2026-11-01 task 5b): statements written with column
// padding (cfgML_STR_AXISZ     .Text   :=, what the shape alignment emits) must
// be packed exactly as the same statements written plain. The padding kept a
// blank before the member ., so the next format packed one more statement
// per line (ORM3 uSetupDefaultsFrm).

interface

procedure Load;

implementation

type
  TEd = class
  public
    Text: string;
    Checked: Boolean;
  end;
  TRec = record
    DefaultUnits: string;
    ML_STR_ID: string;
    ML_STR_OD: string;
    ML_STR_GDTPOS: string;
    ML_STR_AXISX: string;
    ML_STR_AXISY: string;
    ML_STR_AXISZ: string;
    ML_STR_DATUM1: string;
    SetValuetoZeroUSL: Boolean;
    UseAbbrML: Boolean;
    SaveCMMImportFiles: Boolean;
  end;

var
  cfgDefaultUnits: TEd;
  cfgML_STR_ID: TEd;
  cfgML_STR_OD: TEd;
  cfgML_STR_GDTPOS: TEd;
  cfgML_STR_AXISX: TEd;
  cfgML_STR_AXISY: TEd;
  cfgML_STR_AXISZ: TEd;
  cfgML_STR_DATUM1: TEd;
  cfgSetValuetoZeroUSL: TEd;
  cfgUseAbbrML: TEd;
  cfgSaveCMMImportFiles: TEd;
  SetupDefaultsRec: TRec;

procedure Load;
begin
  cfgDefaultUnits                    .Text   := SetupDefaultsRec.DefaultUnits;
  cfgML_STR_ID                       .Text   := SetupDefaultsRec.ML_STR_ID;
  cfgML_STR_OD                       .Text   := SetupDefaultsRec.ML_STR_OD;
  cfgML_STR_GDTPOS                   .Text   := SetupDefaultsRec.ML_STR_GDTPOS;
  cfgML_STR_AXISX                    .Text   := SetupDefaultsRec.ML_STR_AXISX;
  cfgML_STR_AXISY                    .Text   := SetupDefaultsRec.ML_STR_AXISY;
  cfgML_STR_AXISZ                    .Text   := SetupDefaultsRec.ML_STR_AXISZ;
  cfgML_STR_DATUM1                   .Text   := SetupDefaultsRec.ML_STR_DATUM1;
  cfgSetValuetoZeroUSL               .Checked:= SetupDefaultsRec.SetValuetoZeroUSL;
  cfgUseAbbrML                       .Checked:= SetupDefaultsRec.UseAbbrML;
  cfgSaveCMMImportFiles              .Checked:= SetupDefaultsRec.SaveCMMImportFiles;
end;

end.
