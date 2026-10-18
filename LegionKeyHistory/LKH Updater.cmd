@echo off
rem Legion Key History - updater.
rem Keeps LeaderboardData.lua up to date with an hourly Windows scheduled task (and, if you choose,
rem installs new addon versions the same way), and can update the addon by hand. Double-click for
rem the menu, or run with:
rem   install / installaddon / update / addon / uninstall
setlocal
cd /d "%~dp0"
rem A newer menu left next to this one (the window was closed before it was swapped in): switch to
rem it and run it instead. This all sits on one line, so cmd has read it before the file changes.
if exist "%~dp0LKH Updater.cmd.new" (move /y "%~dp0LKH Updater.cmd.new" "%~f0" >nul & "%~f0" %* & exit /b)
set "TASK=LKH Leaderboard Update"
if defined LKH_TASK set "TASK=%LKH_TASK%"
rem Present when the hourly task also installs new addon versions (read by update.ps1 -Auto).
set "AUTOADDON=%~dp0auto-addon.txt"
rem Present when finished keys are NOT shared with Keystone Tauri (read by update.ps1).
set "NOUPLOAD=%~dp0no-upload.txt"

if not exist "%~dp0LegionKeyHistory.toc" (
  echo This file must stay inside the LegionKeyHistory addon folder:
  echo   ...\Interface\AddOns\LegionKeyHistory\
  pause
  exit /b 1
)

if /i "%~1"=="install" goto installdata
if /i "%~1"=="installaddon" goto installboth
if /i "%~1"=="update" goto update
if /i "%~1"=="addon" goto addon
if /i "%~1"=="uninstall" goto uninstall

:menu
cls
echo  Legion Key History - updater
echo  ============================
echo.
schtasks /Query /TN "%TASK%" >nul 2>&1 && (
  if exist "%AUTOADDON%" (echo  Hourly update: leaderboard and addon) else (echo  Hourly update: leaderboard only)
) || (echo  Hourly update: not installed)
if exist "%NOUPLOAD%" (echo  Talents on Keystone Tauri: not shared) else (echo  Talents on Keystone Tauri: your finished keys are shared with each update)
call :writable || (echo  Note: Windows protects this folder - close this and run it as administrator.)
echo.
echo   1. Hourly update: leaderboard only
echo   2. Hourly update: leaderboard and addon (new versions install by themselves)
echo   3. Update the addon to the newest version now
echo   4. Update the leaderboard now
echo   5. Turn off the hourly update
if exist "%NOUPLOAD%" (echo   6. Share my keys and the group's talents with Keystone Tauri) else (echo   6. Stop sharing my keys with Keystone Tauri)
echo   7. Exit
echo.
choice /C 1234567 /N /M " Choose 1-7: "
if errorlevel 7 exit /b 0
if errorlevel 6 (call :sharing & pause & goto menu)
if errorlevel 5 (call :uninstall & pause & goto menu)
if errorlevel 4 (call :update & pause & goto menu)
if errorlevel 3 goto addon
if errorlevel 2 (call :install both & pause & goto menu)
call :install data & pause & goto menu

:installdata
call :install data
exit /b %errorlevel%

:installboth
call :install both
exit /b %errorlevel%

rem :install data   - the hourly task downloads the leaderboard
rem :install both   - ... and also installs new addon versions (only while WoW is closed)
:install
echo.
call :ensurewritable || exit /b 1
echo Downloading the newest leaderboard...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update.ps1"
if errorlevel 1 (
  echo.
  echo The download did not work, so the hourly update was NOT installed.
  echo Check your internet connection and try again.
  exit /b 1
)
schtasks /Create /TN "%TASK%" /SC HOURLY /F /TR "wscript.exe \"%~dp0update-hidden.vbs\"" >nul
if errorlevel 1 (
  echo Could not create the scheduled task.
  exit /b 1
)
if /i "%~1"=="both" (
  echo Hourly update with new addon versions> "%AUTOADDON%"
) else (
  if exist "%AUTOADDON%" del "%AUTOADDON%" >nul 2>&1
)
echo.
if /i "%~1"=="both" (
  echo Installed. Every hour, while you are logged in to Windows, the leaderboard is updated
  echo in the background, and a new version of the addon is installed when there is one.
  echo New versions are only installed while WoW is closed; start WoW again to load them.
) else (
  echo Installed. Every hour, while you are logged in to Windows, the leaderboard is
  echo updated in the background. In WoW, /reload or log in to load the newest one.
)
echo To stop it, run this file again and choose 5.
exit /b 0

:update
echo.
call :ensurewritable || exit /b 1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update.ps1"
exit /b 0

:addon
echo.
call :ensurewritable || (pause & goto menu)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update.ps1" -Addon
rem A new version of this file is saved next to it; swap it in and close in one step, since
rem Windows keeps reading a running .cmd from disk.
if exist "%~dp0LKH Updater.cmd.new" (echo. & echo Done. Run LKH Updater.cmd again for the new menu. & pause & move /y "%~dp0LKH Updater.cmd.new" "%~dp0LKH Updater.cmd" >nul & exit /b 0)
pause
goto menu

:uninstall
echo.
if exist "%AUTOADDON%" del "%AUTOADDON%" >nul 2>&1
schtasks /Query /TN "%TASK%" >nul 2>&1
if errorlevel 1 (
  echo The hourly update is not installed.
  exit /b 0
)
schtasks /Delete /TN "%TASK%" /F >nul
echo Turned off. The leaderboard file you have stays; it just no longer updates by itself.
exit /b 0

rem Keystone Tauri (keystone-tauri.vercel.app) shows each leaderboard run with the talents the group
rem used. update.ps1 sends it the keys you finish, as the addon saved them, unless this is turned off.
:sharing
echo.
if exist "%NOUPLOAD%" (
  del "%NOUPLOAD%" >nul 2>&1
  echo Sharing is on. Each update sends the keys you finish, with the group's talents, to
  echo Keystone Tauri, which checks them against the Tauri leaderboard and shows the talents
  echo next to the run.
) else (
  echo Not shared with Keystone Tauri> "%NOUPLOAD%"
  echo Sharing is off. Your keys stay on this computer.
)
exit /b 0

:writable
copy /y nul "%~dp0.lkh-write-test" >nul 2>&1 || exit /b 1
del "%~dp0.lkh-write-test" >nul 2>&1
exit /b 0

:ensurewritable
call :writable && exit /b 0
echo WoW is installed in a folder Windows protects (for example Program Files), so
echo the updater cannot change the addon files.
echo.
echo Close this window, then right-click "LKH Updater.cmd" and choose
echo "Run as administrator". You can also move WoW out of Program Files.
exit /b 1
