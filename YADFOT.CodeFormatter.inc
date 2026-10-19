{ YADFOT.CodeFormatter.inc -- the ONE compile-time gate for the Delphi 13.2
  IOTACodeFormatter / IOTACodeFormatterServices support.

  Include AFTER `uses ToolsAPI` (DECLARED looks at what is in scope at the
  include point). Defines YADF_HAS_CODEFORMATTER only when ToolsAPI declares
  IOTACodeFormatter -- VER370 cannot tell 13.0/13.1 from 13.2, the declaration
  can. Define YADF_NO_CODEFORMATTER (e.g. in the dproj DCC_Define) to force the
  old-IDE path for testing. }
{$IF DECLARED(IOTACodeFormatter) and not DEFINED(YADF_NO_CODEFORMATTER)}
  {$DEFINE YADF_HAS_CODEFORMATTER}
{$IFEND}
