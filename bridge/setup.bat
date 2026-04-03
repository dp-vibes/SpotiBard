@echo off
echo ============================================================
echo   SpotiBard Setup
echo ============================================================
echo.

REM Check if Python is installed
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Python is not installed or not in your PATH.
    echo.
    echo Please install Python 3.8 or newer from:
    echo   https://www.python.org/downloads/
    echo.
    echo IMPORTANT: During installation, check the box that says
    echo   "Add Python to PATH"
    echo.
    echo After installing Python, run this setup script again.
    echo.
    pause
    exit /b 1
)

echo Python found:
python --version
echo.

echo Installing required packages...
echo.
pip install -r "%~dp0requirements.txt"
if %errorlevel% neq 0 (
    echo.
    echo ERROR: Failed to install packages. Check the errors above.
    pause
    exit /b 1
)

echo.
echo Packages installed! Now setting up Spotify...
echo.

REM Run in setup mode (prompts for creds, does auth, then exits)
python "%~dp0spotibridge.py" --setup
if %errorlevel% neq 0 (
    echo.
    echo Setup failed. Check the errors above.
    pause
    exit /b 1
)

echo.
echo ============================================================
echo   SpotiBridge is starting in the background...
echo ============================================================
echo.
echo   GLOBAL HOTKEYS (work anytime, even in-game):
echo     Ctrl+Alt+Right    Next track
echo     Ctrl+Alt+Left     Previous track
echo     Ctrl+Alt+Space    Play / Pause
echo     Ctrl+Alt+Up       Volume up
echo     Ctrl+Alt+Down     Volume down
echo.
echo   In LOTRO type: /plugins load SpotiBard
echo.
echo   A Windows permission prompt will appear — click Yes.
echo   (SpotiBridge needs admin access for hotkeys to work in-game)
echo.
echo   This window will close in 10 seconds.
echo   SpotiBridge will be running in your system tray (green icon).
echo ============================================================

REM Launch the bridge properly (admin + no terminal)
call "%~dp0run_spotibridge.bat"

timeout /t 10 >nul
