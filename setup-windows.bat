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
echo   This one needs a one-time setup in Windows (ICS).
echo.
echo   IMPORTANT: the handheld goes FIRST. Windows only lists the
echo   RNDIS adapter once the handheld is running and plugged in,
echo   so there is nothing to pick until you do steps 1 and 2.
echo.
echo    1. On the handheld: Options - USB Network Mode - option 3
echo    2. Plug the USB cable into the OTG port (DATA cable)
echo       Wait for Windows to install the RNDIS driver
echo    3. The Network Connections window will open
echo    4. Right-click the adapter that HAS internet (Wi-Fi)
echo    5. Properties - "Sharing" tab
echo    6. Tick "Allow other network users to connect..."
echo    7. Pick the handheld's RNDIS adapter from the list
echo       (it shows up as Remote NDIS or Ethernet 2/3/...)
echo    8. OK
echo    9. On the handheld, run option 3 again so it picks up
echo       the address Windows now hands out
echo.
echo  ============================================================
echo.
set /p open=Open Network Connections now? (y/n): 
if /i "%open%"=="y" start ncpa.cpl

echo.
echo  QUICK DIAGNOSTIC
echo  ----------------
echo  Looking for the handheld on the USB network...
echo.

set found=0

ping -n 2 10.44.44.1 >nul 2>&1
if %errorlevel%==0 (
  set found=1
  color 0A
  echo   [OK] UNIVERSAL MODE - the handheld answers at 10.44.44.1
  echo        Web:   http://10.44.44.1
  echo        Files: \\10.44.44.1     ^(ark / ark^)
  echo        SSH:   ssh ark@10.44.44.1
)

ping -n 2 192.168.137.2 >nul 2>&1
if %errorlevel%==0 (
  set found=1
  color 0A
  echo   [OK] INTERNET MODE - the handheld answers at 192.168.137.2
  echo        SSH:   ssh ark@192.168.137.2
  echo        Internet sharing is working.
)

if %found%==0 (
  color 0E
  echo   [--] No answer yet.
  echo.
  echo        In internet mode Windows may hand out a different
  echo        address. The handheld shows its own IP on screen
  echo        right after you run option 3 - use that one.
  echo.
  echo        Otherwise check:
  echo          - Handheld in Options - USB Network Mode
  echo          - DATA USB cable ^(not charge-only^)
  echo          - Cable in the OTG port, not the charging one
  echo          - For internet mode, ICS must be enabled on the
  echo            Wi-Fi adapter and pointed at the RNDIS one
  echo          - Run option 1 on the handheld: some clones simply
  echo            cannot do USB device mode at all
)
echo.
echo  ============================================================
pause
