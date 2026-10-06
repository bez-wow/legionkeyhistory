@echo off
rem Legion Key History - updater.
rem Keeps LeaderboardData.lua up to date with an hourly Windows scheduled task, and can
rem install new addon versions. Double-click for the menu, or run with:
rem   install / update / addon / uninstall / fixpermission
setlocal
cd /d "%~dp0"
set "TASK=LKH Leaderboard Update"
if defined LKH_TASK set "TASK=%LKH_TASK%"
set "ADDON=%~dp0"
set "ADDON=%ADDON:~0,-1%"

if not exist "%~dp0LegionKeyHistory.toc" (
  echo This file must stay inside the LegionKeyHistory addon folder:
  echo   ...\Interface\AddOns\LegionKeyHistory\
  pause
  exit /b 1
)

if /i "%~1"=="install" goto install
if /i "%~1"=="update" goto update
if /i "%~1"=="addon" goto addon
if /i "%~1"=="uninstall" goto uninstall
if /i "%~1"=="fixpermission" goto fixpermission

:menu
cls
echo  Legion Key History - updater
echo  ============================
echo.
schtasks /Query /TN "%TASK%" >nul 2>&1 && (echo  Hourly leaderboard update: INSTALLED) || (echo  Hourly leaderboard update: not installed)
call :writable || (echo  Note: Windows protects this folder - choose 1 or 2 and it will offer a fix.)
echo.
echo   1. Install the hourly leaderboard update
echo   2. Update the leaderboard now
echo   3. Update the addon to the newest version
echo   4. Uninstall the hourly update
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
echo.
echo Installed. Every hour, while you are logged in to Windows, the leaderboard is
echo updated in the background. In WoW, /reload or log in to load the newest one.
echo To stop it, run this file again and choose Uninstall.
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
schtasks /Query /TN "%TASK%" >nul 2>&1
if errorlevel 1 (
  echo The hourly leaderboard update is not installed.
  exit /b 0
)
schtasks /Delete /TN "%TASK%" /F >nul
echo Uninstalled. The leaderboard file you have stays; it just no longer updates by itself.
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
echo It can fix this once: your Windows user gets permission to change THIS addon
echo folder only. Windows will ask for administrator approval.
echo.
choice /C YN /M "Fix it now"
if errorlevel 2 (
  echo.
  echo Not changed. You can also move WoW out of Program Files, or run this file as administrator.
  exit /b 1
)
call :fixpermission
call :writable && (echo Fixed. & echo. & exit /b 0)
echo Still not writable. Try running this file as administrator ^(right-click, Run as administrator^).
exit /b 1

:fixpermission
set "FIX=%TEMP%\lkh-fix-permission.cmd"
> "%FIX%" echo @icacls "%ADDON%" /grant "%USERDOMAIN%\%USERNAME%:(OI)(CI)M" /T /Q
powershell -NoProfile -Command "Start-Process -FilePath $env:FIX -Verb RunAs -Wait -WindowStyle Hidden" 2>nul
del "%FIX%" >nul 2>&1
exit /b 0
