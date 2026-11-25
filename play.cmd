@echo off
setlocal
set "ENGINE=%LOCALAPPDATA%\CodexTools\Godot-4.5.1\Godot_v4.5.1-stable_win64.exe"
if defined GODOT_EXE set "ENGINE=%GODOT_EXE%"
if not exist "%ENGINE%" (
    echo Open project.godot in Godot 4.5, or set GODOT_EXE to its full executable path.
    pause
    exit /b 1
)
pushd "%~dp0"
if not exist "bin\cangling.dll" (
    echo Missing bin\cangling.dll. Build the native CMake target before launching.
    popd
    pause
    exit /b 1
)
if not exist "art\undead_people\tile_config.json" (
    echo Missing the UNDEAD_PEOPLE tileset under art\undead_people.
    popd
    pause
    exit /b 1
)
start "" "%ENGINE%" --path "%CD%"
popd
