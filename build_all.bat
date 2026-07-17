@echo off
setlocal
cd /d "%~dp0"
rem ==== Single source of truth for the release version =================
set YADF_MAJOR=1
set YADF_MINOR=0
set YADF_RELEASE=12
set YADF_BUILD=0
set YADF_VER=%YADF_MAJOR%.%YADF_MINOR%.%YADF_RELEASE%.%YADF_BUILD%
rem NOTE: keep YADF.Version.inc YADF_VERSION in sync with the above.

call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"

rem Numeric FILEVERSION fields (drive the binary VS_FIXEDFILEINFO).
set VNUM=/p:VerInfo_AutoIncVersion=false /p:VerInfo_MajorVer=%YADF_MAJOR% /p:VerInfo_MinorVer=%YADF_MINOR% /p:VerInfo_Release=%YADF_RELEASE% /p:VerInfo_Build=%YADF_BUILD%
set COPY=Alexander Liberov, parts by Roman Yankovsky

echo === Building YADF.exe (Win64 Release) %YADF_VER% ===
msbuild /t:Build /p:Config=Release /p:Platform=Win64 %VNUM% /p:VerInfo_Keys="CompanyName=;FileDescription=YADF;FileVersion=%YADF_VER%;InternalName=Yet Another Delphi Formatter;LegalCopyright=%COPY%;LegalTrademarks=;OriginalFilename=YADF.exe;ProductName=YADF;ProductVersion=%YADF_VER%;Comments=" YADF.dproj /nologo /v:minimal || goto :err

echo === Building YADFSetup.exe (Win32 Release) %YADF_VER% ===
msbuild /t:Build /p:Config=Release /p:Platform=Win32 %VNUM% /p:VerInfo_Keys="CompanyName=;FileDescription=YADFSetup;FileVersion=%YADF_VER%;InternalName=YADF Settings Editor;LegalCopyright=%COPY%;LegalTrademarks=;OriginalFilename=YADFSetup.exe;ProductName=YADFSetup;ProductVersion=%YADF_VER%;Comments=" YADFSetup.dproj /nologo /v:minimal || goto :err

echo === Building YADFOT.bpl (Win32 Release) %YADF_VER% ===
msbuild /t:Build /p:Config=Release /p:Platform=Win32 %VNUM% /p:VerInfo_Keys="CompanyName=;FileDescription=YADFOT;FileVersion=%YADF_VER%;InternalName=YADF Open Tools;LegalCopyright=%COPY%;LegalTrademarks=;OriginalFilename=YADFOT.bpl;ProductName=YADFOT;ProductVersion=%YADF_VER%;Comments=" YADFOT.dproj /nologo /v:minimal || goto :err

echo === Building YADFOT.bpl (Win64 Release) %YADF_VER% ===
rem The 64-bit IDE (RAD Studio is a 64-bit app since Delphi 12) loads the Win64 bpl.
msbuild /t:Build /p:Config=Release /p:Platform=Win64 %VNUM% /p:VerInfo_Keys="CompanyName=;FileDescription=YADFOT;FileVersion=%YADF_VER%;InternalName=YADF Open Tools;LegalCopyright=%COPY%;LegalTrademarks=;OriginalFilename=YADFOT.bpl;ProductName=YADFOT;ProductVersion=%YADF_VER%;Comments=" YADFOT.dproj /nologo /v:minimal || goto :err

echo.
echo === All artifacts built at %YADF_VER% ===
goto :eof

:err
echo BUILD FAILED
exit /b 1
