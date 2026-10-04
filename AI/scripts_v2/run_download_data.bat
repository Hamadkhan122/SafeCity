@echo off
cd /d "%~dp0"
echo Installing packages...
where py >nul 2>nul && (set PY=py) || (set PY=python)
%PY% -m pip install --upgrade icrawler yt-dlp opencv-python pillow
if not exist "D:\Downloads\fight_data" mkdir "D:\Downloads\fight_data"
echo Downloading data (20-40 min)...
%PY% -u 20_download_fight_web_data.py > "D:\Downloads\fight_data\log.txt" 2>&1
type "D:\Downloads\fight_data\log.txt"
echo FINISHED
pause
