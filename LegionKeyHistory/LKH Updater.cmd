@echo off
rem Legion Key History - leaderboard updater.
rem Keeps LeaderboardData.lua up to date with an hourly Windows scheduled task.
rem Double-click for the menu, or run with: install / update / addon / uninstall
setlocal
cd /d "%~dp0"
set "TASK=LKH Leaderboard Update"
if defined LKH_TASK set "TASK=%LKH_TASK%"

if not exist "%~dp0LegionKeyHistory.toc" (
  echo This file must stay inside the LegionKeyHistory addon folder:
  echo   ...\Interface\AddOns\LegionKeyHistory\
  pause
  exit /b 1
)

if /i "%~1"=="install" goto install
if /i "%~1"=="update" goto update
if /i "%~1"=="uninstall" goto uninstall
if /i "%~1"=="addon" goto addon

:menu
cls
echo  Legion Key History - leaderboard updater
echo  ========================================
echo.
schtasks /Query /TN "%TASK%" >nul 2>&1 && (echo  Hourly update service: INSTALLED) || (echo  Hourly update service: not installed)
echo.
echo   1. Install the hourly leaderboard update service
echo   2. Update the leaderboard now
echo   3. Update the addon to the newest version
echo   4. Uninstall the service
echo   5. Exit
echo.
choice /C 12345 /N /M " Choose 1-5: "
if errorlevel 5 exit /b 0
if errorlevel 4 (call :uninstall & pause & goto menu)
if errorlevel 3 goto addon
if errorlevel 2 (call :update & pause & goto menu)
call :install & pause & goto menu

:install
echo.
echo Downloading the newest leaderboard...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update.ps1"
echo.
schtasks /Create /TN "%TASK%" /SC HOURLY /F /TR "wscript.exe \"%~dp0update-hidden.vbs\"" >nul
if errorlevel 1 (
  echo Could not create the scheduled task.
  exit /b 1
)
echo Installed. Every hour, while you are logged in to Windows, the leaderboard is
echo updated in the background. In WoW, /reload or log in to load the newest one.
echo To stop it, run this file again and choose Uninstall.
exit /b 0

:update
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update.ps1"
exit /b %errorlevel%

:addon
rem The update replaces this file too, and Windows reads a running .cmd line by line,
rem so the update runs in its own PowerShell window and this one closes first.
start "Legion Key History - addon update" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update.ps1" -Addon -Pause
exit

:uninstall
echo.
schtasks /Query /TN "%TASK%" >nul 2>&1
if errorlevel 1 (
  echo The hourly update service is not installed.
  exit /b 0
)
schtasks /Delete /TN "%TASK%" /F >nul
echo Uninstalled. The leaderboard file you have stays; it just no longer updates by itself.
exit /b 0
