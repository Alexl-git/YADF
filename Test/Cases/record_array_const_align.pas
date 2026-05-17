unit record_array_const_align;

interface

type
  REditField = record
    idx        : Integer;
    Field      : string ;
    Description: string ;
    DBField    : string ;
  end;

const
  EditFields0: array [1 .. 32] of REditField = (//
    (idx: 1; Field: 'edtNum'; Description: '#'; DBField: 'Num'), // 1	edtNum
    (idx: 2; Field: 'edtName'; Description: 'Name'; DBField: 'DimName'), // 2	edtName
    (idx: 3; Field: 'btnSpecDouble'; Description: 'Spec Limits Double'; DBField: 'SpecType'), // 3	btnSpecDouble
    (idx: 4; Field: 'btnSpecSingle'; Description: 'Spec Limits Single (Upper only)'; DBField: 'SpecType'), // 4	btnSpecSingle
    (idx: 5; Field: 'btnNotationSpec'; Description: 'Notatiuon Spec'; DBField: 'Notation'), // 5	btnNotationSpec
    (idx: 6; Field: 'btnNotationTolerance'; Description: 'Notation Tolerance'; DBField: 'Notation'), // 6	tnNotationTolerance
    (idx: 7; Field: 'edtUSL'; Description: 'USL'; DBField: 'USL'), // 7	edtUSL
    (idx: 8; Field: 'edtLSL'; Description: 'LSL'; DBField: 'LSL'), // 8	edtLSL
    (idx: 9; Field: 'edtNominal'; Description: 'Nominal'; DBField: 'Nominal'), // 9	edtNominal
    (idx: 10; Field: 'edtUpper'; Description: 'Upper Tolerance'; DBField: 'UpperTol'), // 10	edtUpper
    (idx: 11; Field: 'edtLower'; Description: 'Lower Tolerance '; DBField: 'LowerTol'), // 11	edtLower
    (idx: 12; Field: 'edtSuffix'; Description: 'Suffix'; DBField: 'FtrSuffix'), // 12	edtSuffix
    (idx: 13; Field: 'edtClass'; Description: 'Class'; DBField: 'FtrMClass'), // 13	edtClass
    (idx: 14; Field: 'edtOperOrder'; Description: 'Custom Order'; DBField: 'OperOrd'), // 14	edtOperOrder
    (idx: 15; Field: 'edtDecimals'; Description: 'Decimals'; DBField: 'Decimals'), // 15	edtDecimals
    (idx: 16; Field: 'edtUnits'; Description: 'Units '; DBField: 'DimUnits'), // 16	edtUnits
    (idx: 17; Field: 'edtAbbr'; Description: 'Abbreviation'; DBField: 'DimAbbr'), // 17	edtAbbr
    (idx: 18; Field: 'edtIndicator'; Description: 'Indicator'; DBField: 'FINDICATOR'), // 18	edtIndicator
    (idx: 19; Field: 'edtZeroAt'; Description: 'Set zero at'; DBField: 'ZeroAt'), // 19	edtZeroAt
    (idx: 20; Field: 'edtConvertReading'; Description: 'Convert Readings'; DBField: 'FCONVERT'), // 20	edtConvertReading
    (idx: 21; Field: 'edtMultBy'; Description: 'Multiply by'; DBField: 'MultBy'), // 21	edtMultBy
    (idx: 22; Field: 'edtAdd'; Description: 'Add'; DBField: 'Addto'), // 22	edtAdd
    (idx: 23; Field: 'edtUseAbsValue'; Description: 'Use absolute value'; DBField: 'AbsoluteValue'), // 23	edtUseAbsValue
    (idx: 24; Field: 'edtUseMathLine'; Description: 'Use MathLine'; DBField: 'UseMathLine'), // 24	edtUseMathLine
    (idx: 25; Field: 'edtMathLine'; Description: 'MathLine'; DBField: 'MathLine'), // 25	edtMathLine
    (idx: 26; Field: 'edtA'; Description: 'A'; DBField: 'MathA'), // 26	edtA
    (idx: 27; Field: 'edtB'; Description: 'B'; DBField: 'MathB'), // 27	edtB
    (idx: 28; Field: 'edtC'; Description: 'C'; DBField: 'MathC'), // 28	edtC
    (idx: 29; Field: 'edtD'; Description: 'D'; DBField: 'MathD'), // 29	edtD
    (idx: 30; Field: 'edtGagePort'; Description: 'Gage port'; DBField: 'GagePortNmbr'), // 30	edtGagePort
    (idx: 31; Field: 'edtDataChannel'; Description: 'Data channel'; DBField: 'DataChannel'), // 31	edtDataChannel
    (idx: 32; Field: 'edtNotes'; Description: 'Instructions'; DBField: 'Notes')// 32	edtNotes
  ); //

implementation

end.
