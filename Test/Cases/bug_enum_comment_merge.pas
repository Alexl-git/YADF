unit bug_enum_comment_merge;

interface

type
  TCharMClass = (// 0 .. 9;
    CMC_Safety = 0, //
    CMC_None = 1,//
    Empty2 = 2, Empty3, Empty4, Empty5,
    CMC_Critical = 6, //
    Empty7,
    CMC_Major = 8, //
    CMC_Minor = 9 //
  );

  TSpecType = (
    {$REGION 'Documentation'}
    /// <summary>
    /// Not used yet
    /// </summary>
    {$ENDREGION}
    SpecType_Undefined = 0,
    SpecType_Double = 1 // Bilateral
  );

implementation

end.
