@echo off
setlocal

rem Deploys the ThreatMeterNP addon source into a WoW client's AddOns folder.
rem To target a different client/install later, change WOW_ADDONS_DIR below.

set "SOURCE_DIR=%~dp0ThreatMeterNP"
set "WOW_ADDONS_DIR=D:\World of Warcraft\_classic_beta_\Interface\AddOns"
set "DEST_DIR=%WOW_ADDONS_DIR%\ThreatMeterNP"

if not exist "%SOURCE_DIR%" (
    echo Source folder not found: %SOURCE_DIR%
    exit /b 1
)

if not exist "%WOW_ADDONS_DIR%" (
    echo AddOns folder not found: %WOW_ADDONS_DIR%
    exit /b 1
)

echo Deploying ThreatMeterNP to "%DEST_DIR%" ...
robocopy "%SOURCE_DIR%" "%DEST_DIR%" /MIR /NFL /NDL /NJH /NJS
if %ERRORLEVEL% GEQ 8 (
    echo robocopy failed with exit code %ERRORLEVEL%
    exit /b 1
)

echo Done.
endlocal
