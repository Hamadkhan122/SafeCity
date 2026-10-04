@echo off
cd /d "%~dp0"
where py >nul 2>nul && (set PY=py) || (set PY=python)
if not exist "D:\Downloads\fight_data2" mkdir "D:\Downloads\fight_data2"
echo Downloading more fight data (about 30 min) - keep this window open...
%PY% -u 26_download_more_fight_data.py > "D:\Downloads\fight_data2\log.txt" 2>&1
type "D:\Downloads\fight_data2\log.txt"
echo FINISHED
pause
