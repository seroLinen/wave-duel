@echo off
rem Double-click to play. Finds Godot 4.3 in this order: godot_path.txt (one line, path to the exe; git-ignored),
rem the GODOT environment variable, then "godot" on PATH.
setlocal
cd /d "%~dp0"
set "G="
if exist godot_path.txt set /p G=<godot_path.txt
if not defined G if defined GODOT set "G=%GODOT%"
if not defined G set "G=godot"
start "" "%G%" --path "%~dp0"
