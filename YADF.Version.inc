{ Single source of truth for the YADF family version string (display only).
  The numeric FILEVERSION is stamped at build time by build_all.bat via
  /p:VerInfo_* properties using the same value. Bump with
  `pwsh sync_version.ps1 -Version N.N.N.N` (build_all.bat lines, this constant,
  the Demo\Sample.pas stamp and YADFSample.RES); build_all.bat re-syncs on every run. }
const
  YADF_VERSION = '1.0.21.0';
