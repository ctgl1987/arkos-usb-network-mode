@echo off
REM ============================================================
REM   ArkOS USB Network - Windows setup helper
REM   ArkOS handheld (R36S and clones) over a USB cable
REM ============================================================
title ArkOS USB Network - Windows
color 0B

echo.
echo  ============================================================
echo    ArkOS USB Network  -  Windows setup
echo  ============================================================
echo.
echo   This script changes NOTHING on your PC. It is a guide
echo   plus a connection test. Anything that needs setting up
echo   is done by you, and it says where.
echo.
echo   FILE MODE (ssh / web / copy ROMs)
echo   ---------------------------------
echo   Nothing to configure on Windows.
echo.
echo    1. On the handheld: Options - USB Network Mode
echo       Run option 1 first to check compatibility,
echo       then option 2 (universal)
echo    2. Plug the USB cable into the OTG port (DATA cable)
echo    3. Windows installs the RNDIS driver by itself
echo    4. Open in a browser:    http://10.44.44.1
echo       or in Explorer:       \\10.44.44.1
echo       user / password:  ark / ark
echo.
echo  ------------------------------------------------------------
echo   INTERNET MODE (share the PC's connection with the handheld)
echo  ------------------------------------------------------------
echo   This one needs a one-time setup in Windows (ICS):
echo.
echo    1. The Network Connections window will open
echo    2. Right-click the adapter that HAS internet (Wi-Fi)
echo    3. Properties - "Sharing" tab
echo    4. Tick "Allow other network users to connect..."
echo    5. Pick the handheld's RNDIS adapter from the list
echo    6. OK
echo    7. On the handheld, use option 3
echo.
echo  ============================================================
echo.
set /p open=Open Network Connections now? (y/n): 
if /i "%open%"=="y" start ncpa.cpl

echo.
echo  QUICK DIAGNOSTIC
echo  ----------------
echo  Looking for the handheld on the USB network...
ping -n 2 10.44.44.1 >nul 2>&1
if %errorlevel%==0 (
  color 0A
  echo   [OK] The handheld answers at 10.44.44.1
  echo        Web:   http://10.44.44.1
  echo        Files: \\10.44.44.1     ^(ark / ark^)
  echo        SSH:   ssh ark@10.44.44.1
) else (
  color 0E
  echo   [--] No answer at 10.44.44.1
  echo        Check:
  echo          - Handheld in Options - USB Network Mode - option 2
  echo          - DATA USB cable ^(not charge-only^)
  echo          - Cable in the OTG port, not the charging one
  echo          - In internet mode the IP is different ^(192.168.137.x^)
  echo          - Run option 1 on the handheld: some clones simply
  echo            cannot do USB device mode at all
)
echo.
echo  ============================================================
pause
