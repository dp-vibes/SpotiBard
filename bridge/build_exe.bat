@echo off
echo ============================================================
echo   Building SpotiBridge.exe
echo ============================================================
echo.
cd /d "%~dp0"
pyinstaller --onefile --noconsole --name SpotiBridge --icon=NONE --add-data ".spotify_cache;." spotibridge.py 2>nul
if %errorlevel% neq 0 (
    echo Trying without cache file...
    pyinstaller --onefile --noconsole --name SpotiBridge spotibridge.py
)
echo.
if exist dist\SpotiBridge.exe (
    echo SUCCESS! SpotiBridge.exe is in the dist\ folder.
    echo Copy it wherever you like.
) else (
    echo BUILD FAILED. Check errors above.
)
echo.
pause
