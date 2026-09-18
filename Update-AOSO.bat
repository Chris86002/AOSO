@echo off
setlocal

title AOSO Updater

echo.
echo ========================================
echo              AOSO UPDATER
echo ========================================
echo.

:: KSP lives under Program Files, so this may need elevation.
net session >nul 2>&1
if errorlevel 1 (
    echo If the update fails with Access Denied, right-click this file
    echo and choose "Run as administrator".
    echo.
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update-AOSO.ps1"
set "ERR=%ERRORLEVEL%"

echo.
echo ========================================
echo.
if not "%ERR%"=="0" (
    echo Updater exited with code %ERR%.
    echo.
)
pause
endlocal & exit /b %ERR%
