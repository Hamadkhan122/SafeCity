@echo off
cd /d "%~dp0"
where py >nul 2>nul && (set PY=py) || (set PY=python)
if not exist "D:\Downloads\fight_data" mkdir "D:\Downloads\fight_data"
echo Downloading screen photos (about 10 min)...
%PY% -u 21_download_screen_photos.py > "D:\Downloads\fight_data\log_screen.txt" 2>&1
type "D:\Downloads\fight_data\log_screen.txt"
echo FINISHED
pause
