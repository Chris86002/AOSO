@echo off
setlocal

title AOSO Watcher

echo.
echo ========================================
echo              AOSO WATCHER
echo ========================================
echo.
echo Leave this window open.
echo It checks GitHub and updates AOSO for you.
echo Close the window or press Ctrl+C to stop.
echo.

:: KSP lives under Program Files, so this may need elevation.
net session >nul 2>&1
if errorlevel 1 (
    echo If updates fail with Access Denied, right-click this file
    echo and choose "Run as administrator".
    echo.
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update-AOSO.ps1" -Watch
set "ERR=%ERRORLEVEL%"

echo.
if not "%ERR%"=="0" (
    echo Watcher exited with code %ERR%.
    echo.
    pause
)
endlocal & exit /b %ERR%
