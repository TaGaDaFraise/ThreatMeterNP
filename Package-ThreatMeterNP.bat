@echo off
setlocal enabledelayedexpansion

rem Packages ThreatMeterNP/ into a distributable zip containing only the
rem addon itself (no repo/dev files like requirements.md, infos.md,
rem README.md, or the deploy/package scripts) — ready for a GitHub
rem release asset or CurseForge upload.

set "SOURCE_DIR=%~dp0ThreatMeterNP"
set "OUTPUT_DIR=%~dp0dist"

if not exist "%SOURCE_DIR%" (
    echo Source folder not found: %SOURCE_DIR%
    exit /b 1
)

set "TOC_FILE=%SOURCE_DIR%\ThreatMeterNP.toc"
set "VERSION=unknown"
for /f "tokens=2 delims=:" %%V in ('findstr /b /c:"## Version:" "%TOC_FILE%"') do (
    set "VERSION=%%V"
)
set "VERSION=%VERSION: =%"

if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

set "ZIP_PATH=%OUTPUT_DIR%\ThreatMeterNP-%VERSION%.zip"
if exist "%ZIP_PATH%" del /f /q "%ZIP_PATH%"

echo Packaging ThreatMeterNP %VERSION% ...
powershell -NoProfile -Command "Compress-Archive -Path '%SOURCE_DIR%' -DestinationPath '%ZIP_PATH%' -Force"
if errorlevel 1 (
    echo Failed to create zip.
    exit /b 1
)

echo Created "%ZIP_PATH%"
endlocal
