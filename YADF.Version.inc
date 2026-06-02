{ Single source of truth for the YADF family version string (display only).
  The numeric FILEVERSION is stamped at build time by build_all.bat via
  /p:VerInfo_* properties using the same value. When releasing, bump BOTH
  this constant and the version variables at the top of build_all.bat. }
const
  YADF_VERSION = '1.0.4.0';
