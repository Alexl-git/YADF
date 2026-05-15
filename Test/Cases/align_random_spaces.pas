unit align_random_spaces;

interface

implementation

procedure PaintCells(ACanvas: TCanvas);
begin
  ACanvas     .     Font    .    Color     :=  GlobalContentTextColor   ;  // ACanvas.Font.Color xor high(TColor);
  ACanvas   .      Brush   .      Color  :=     GlobalContentColor     ;   // ACanvas.Brush.Color xor high(TColor);
  ACanvas  .      Font   .    Color    :=   GlobalContentTextColor     ;     // ACanvas.Font.Color xor high(TColor);
  ACanvas    .   Brush  .    Color  :=   GlobalContentColor  ;   // ACanvas.Brush.Color xor high(TColor);
  ACanvas   .   Font    .      Color    :=   GlobalContentTextColor   ;      // ACanvas.Font.Color xor high(TColor);
  ACanvas   .      Brush   .   Color   :=  GlobalContentColor    ;   // ACanvas.Brush.Color xor high(TColor);
  ACanvas   .      Font    .      Color    :=  GlobalContentTextColor     ;    // ACanvas.Font.Color xor high(TColor);
  ACanvas     .    Brush   .      Color     :=     GlobalContentColor    ;   // ACanvas.Brush.Color xor high(TColor);
  ACanvas      .  Font   .     Color    :=    GlobalContentTextColor     ;   // ACanvas.Font.Color xor high(TColor);
  ACanvas      .   Brush   .  Color  :=      GlobalContentColor     ;   // ACanvas.Brush.Color xor high(TColor);
  ACanvas  .  Font     .     Color      :=  GlobalContentTextColor      ;     // ACanvas.Font.Color xor high(TColor);
  ACanvas     .   Brush      .    Color      :=   GlobalContentColor    ;     // ACanvas.Brush.Color xor high(TColor);
  ACanvas      .   Font    .     Color   :=    GlobalContentTextColor   ;  // ACanvas.Font.Color xor high(TColor);
  ACanvas    .    Brush    .  Color  :=  GlobalContentColor      ;   // ACanvas.Brush.Color xor high(TColor);
  ACanvas   .    Font    .  Color      :=  GlobalContentTextColor     ;    // ACanvas.Font.Color xor high(TColor);
  ACanvas      .      Brush    .    Color     :=     GlobalContentColor   ;      // ACanvas.Brush.Color xor high(TColor);
  ACanvas     .    Font      .   Color    :=  GlobalContentTextColor    ;  // ACanvas.Font.Color xor high(TColor);
  ACanvas     .      Brush    .      Color      :=      GlobalContentColor  ;   // ACanvas.Brush.Color xor high(TColor);
  ACanvas     .  Font      .   Color    :=      GlobalContentTextColor     ;    // ACanvas.Font.Color xor high(TColor);
  ACanvas     .      Brush   .   Color  :=      GlobalContentColor   ;      // ACanvas.Brush.Color xor high(TColor);
end;

end.
