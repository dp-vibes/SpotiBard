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
echo ============================================================
echo   Packages installed successfully!
echo ============================================================
echo.
echo   Now launching SpotiBridge for first-time Spotify login...
echo.
echo   A browser window will open. Log in with your Spotify
echo   account and click "Allow" to authorize SpotiBard.
echo   (You only need to do this once!)
echo.
echo   GLOBAL HOTKEYS (work anytime, even in-game):
echo     Ctrl+Alt+Right    Next track
echo     Ctrl+Alt+Left     Previous track
echo     Ctrl+Alt+Space    Play / Pause
echo     Ctrl+Alt+Up       Volume up
echo     Ctrl+Alt+Down     Volume down
echo.
echo   After this, just use "Run SpotiBridge.bat" for daily use.
echo ============================================================
echo.

python "%~dp0spotibridge.py"

pause
