param(
    [switch]$BuildOnly,
    [switch]$SyncCcb,
    [int]$Jobs = 8,
    [string]$LangPackDir = "d:\Project\ccb-windows-with-graphics-x64-2026-11-25-1727\lang"
)

$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$CcbDir = Join-Path $Root "Cataclysm-Cleanwater-Bomb"
$BuildRoot = Join-Path $Root "build"
$CcbBuild = Join-Path $BuildRoot "ccb_bridge"
$NativeBuild = Join-Path $BuildRoot "native"
$BinDir = Join-Path $Root "bin"
$ReleaseDir = Join-Path $Root "release"
$GodotDir = "C:\Users\ASUS\AppData\Local\CodexTools\Godot-4.5.1"
$GodotGui = Join-Path $GodotDir "Godot_v4.5.1-stable_win64.exe"
$GodotConsole = Join-Path $GodotDir "Godot_v4.5.1-stable_win64_console.exe"

# Ensure MSYS2 UCRT64 toolchain & ccache incremental settings are active
$env:PATH = "C:\msys64\ucrt64\bin;" + $env:PATH
$env:CCACHE_SLOPPINESS = "pch_defines,time_macros,include_file_mtime"
$env:CCACHE_NOHASHDIR = "1"

if ($SyncCcb) {
    Write-Host "=== [1/5] Syncing upstream Cataclysm-Cleanwater-Bomb (git pull --ff-only) ===" -ForegroundColor Cyan
    git -C $CcbDir pull --ff-only
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

# Safe DLL hot-move helper (prevents linker Permission Denied if an older game window is still running)
function Safe-MoveLockedDll([string]$DllPath, [string]$BackupDir) {
    if (Test-Path $DllPath) {
        try {
            $fs = [System.IO.File]::Open($DllPath, 'Open', 'ReadWrite', 'None')
            $fs.Close()
        } catch {
            New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
            $ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            $name = [System.IO.Path]::GetFileNameWithoutExtension($DllPath)
            Move-Item -Force $DllPath (Join-Path $BackupDir "$name.prev.$ts.dll") -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "=== [2/5] Incremental build: libccb_core.a + ccb_bridge.dll ===" -ForegroundColor Cyan
Safe-MoveLockedDll (Join-Path $BinDir "ccb_bridge.dll") (Join-Path $BuildRoot "ccb_bridge")
if (-not (Test-Path (Join-Path $CcbBuild "build.ninja"))) {
    cmake -S (Join-Path $Root "native\ccb_bridge") -B $CcbBuild -G Ninja -DCMAKE_BUILD_TYPE=Release
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} else {
    # Check if CCB_ROOT changed (e.g. after moving repo into cangling-city/)
    $cache = Get-Content (Join-Path $CcbBuild "CMakeCache.txt") -Raw -ErrorAction SilentlyContinue
    if ($cache -and ($cache -notmatch [regex]::Escape($CcbDir.Replace('\', '/')))) {
        Write-Host "Detected moved CCB_ROOT; reconfiguring $CcbBuild cleanly..." -ForegroundColor Yellow
        Remove-Item -Recurse -Force $CcbBuild
        cmake -S (Join-Path $Root "native\ccb_bridge") -B $CcbBuild -G Ninja -DCMAKE_BUILD_TYPE=Release
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
}
cmake --build $CcbBuild --target ccb_bridge -j $Jobs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "=== [3/5] Incremental build: cangling.dll ===" -ForegroundColor Cyan
Safe-MoveLockedDll (Join-Path $BinDir "cangling.dll") (Join-Path $BuildRoot "cangling_prev")
cmake --build $NativeBuild --target cangling -j $Jobs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($BuildOnly) {
    Write-Host "=== Incremental build complete! ===" -ForegroundColor Green
    Get-Item (Join-Path $BinDir "ccb_bridge.dll"), (Join-Path $BinDir "cangling.dll") | Select-Object Name, Length, LastWriteTime
    exit 0
}

Write-Host "=== [4/5] Packaging minimal zero-source release/ distribution ===" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $ReleaseDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $ReleaseDir "bin") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $ReleaseDir "runtime") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $ReleaseDir "ccb_data") | Out-Null
Set-Content -Path (Join-Path $ReleaseDir ".gdignore") -Value "" -NoNewline

# Copy only when missing or content differs (avoids file-lock errors if an older release/ window is currently running)
function Copy-IfChanged([string]$Src, [string]$Dst, [string]$BackupDir) {
    if (-not (Test-Path $Src)) { return }
    if (Test-Path $Dst) {
        $sItem = Get-Item $Src
        $dItem = Get-Item $Dst
        if (($sItem.Length -eq $dItem.Length) -and ($sItem.LastWriteTimeUtc -eq $dItem.LastWriteTimeUtc)) {
            return
        }
        $sHash = (Get-FileHash -Algorithm SHA256 $Src).Hash
        $dHash = (Get-FileHash -Algorithm SHA256 $Dst).Hash
        if ($sHash -eq $dHash) {
            return
        }
        if ($BackupDir) {
            Safe-MoveLockedDll $Dst $BackupDir
        }
    }
    Copy-Item -Force $Src $Dst
}

# 4a. Copy native DLLs + exact matching MSYS2 UCRT64 runtime dependency (libwinpthread-1.dll) so release/
# works on ANY Windows PC without MSYS2 installed and never collides with older PATH DLLs (Win32 error=127)!
$WinPthread = "C:\msys64\ucrt64\bin\libwinpthread-1.dll"
$ReleaseBackup = Join-Path $BuildRoot "release_prev"
if (Test-Path $WinPthread) {
    Copy-IfChanged $WinPthread (Join-Path $BinDir "libwinpthread-1.dll") (Join-Path $BuildRoot "cangling_prev")
    Copy-IfChanged $WinPthread (Join-Path $ReleaseDir "bin\libwinpthread-1.dll") $ReleaseBackup
}
Copy-IfChanged (Join-Path $BinDir "cangling.dll") (Join-Path $ReleaseDir "bin\cangling.dll") $ReleaseBackup
Copy-IfChanged (Join-Path $BinDir "ccb_bridge.dll") (Join-Path $ReleaseDir "bin\ccb_bridge.dll") $ReleaseBackup

# 4b. Compile minimal native Win32 GUI .exe launcher with embedded multi-res circular app icon & version info (zero console window!)
$AppExeName  = "Cataclysm-EmperorCOOP2.0.exe"
$AppPckName  = "Cataclysm-EmperorCOOP2.0.pck"
foreach ($legacy in @("CanglingCity.exe", "CanglingCity.pck")) {
    $legacyPath = Join-Path $ReleaseDir $legacy
    if (Test-Path $legacyPath) { Remove-Item -Force $legacyPath -ErrorAction SilentlyContinue }
}
$LauncherSrc = Join-Path $Root "tools\launcher_main.cpp"
$LauncherRc  = Join-Path $Root "tools\launcher.rc"
$LauncherIco = Join-Path $Root "tools\app_icon.ico"
$LauncherRes = Join-Path $BuildRoot "launcher_res.o"
$LauncherExe = Join-Path $ReleaseDir $AppExeName
$needLauncher = (-not (Test-Path $LauncherExe)) `
    -or ((Get-Item $LauncherSrc).LastWriteTime -gt (Get-Item $LauncherExe).LastWriteTime) `
    -or ((Test-Path $LauncherIco) -and ((Get-Item $LauncherIco).LastWriteTime -gt (Get-Item $LauncherExe).LastWriteTime)) `
    -or ((Test-Path $LauncherRc) -and ((Get-Item $LauncherRc).LastWriteTime -gt (Get-Item $LauncherExe).LastWriteTime))
if ($needLauncher) {
    $resArgs = @()
    if ((Test-Path $LauncherRc) -and (Test-Path $LauncherIco)) {
        windres $LauncherRc -O coff -o $LauncherRes
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        $resArgs = @($LauncherRes)
    }
    g++ -Os -s -std=c++17 -mwindows -municode -static -static-libgcc -static-libstdc++ $LauncherSrc @resArgs -o $LauncherExe
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

# 4c. Copy Godot 4.5.1 runtime engine (prefer official release template if installed, else bundled win64 runtime)
$ReleaseTemplate = Join-Path $env:APPDATA "Godot\export_templates\4.5.1.stable\windows_release_x86_64.exe"
$RuntimeSrc = if (Test-Path $ReleaseTemplate) { $ReleaseTemplate } else { $GodotGui }
$RuntimeDst = Join-Path $ReleaseDir "runtime\godot_runtime.exe"
if ((-not (Test-Path $RuntimeDst)) -or ((Get-Item $RuntimeSrc).Length -ne (Get-Item $RuntimeDst).Length)) {
    Copy-Item -Force $RuntimeSrc $RuntimeDst
}

# 4d. Pack runtime game scripts/shaders/scenes/fonts into Cataclysm-EmperorCOOP2.0.pck via Godot native PCKPacker
& $GodotConsole --headless --path $Root --script "res://tools/pack_release.gd"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# 4e. Mirror ONLY minimal runtime CCB data (data/, gfx/, lang/mo/) — ZERO src/, tests/, doc/, .git/, scripts!
# Prefer the full Chinese localization pack in $LangPackDir\mo if present, falling back cleanly to $CcbDir\lang\mo.
$LangMoSrc = Join-Path $LangPackDir "mo"
if (Test-Path $LangMoSrc) {
    Write-Host "  [Lang] Bundling localization pack from: $LangMoSrc" -ForegroundColor Green
} else {
    $LangMoSrc = Join-Path $CcbDir "lang\mo"
    Write-Host "  [Lang] External lang pack not found; falling back to: $LangMoSrc" -ForegroundColor Yellow
}
$mirrorPairs = @(
    @{ Src = (Join-Path $CcbDir "data"); Dst = (Join-Path $ReleaseDir "ccb_data\data") },
    @{ Src = (Join-Path $CcbDir "gfx");  Dst = (Join-Path $ReleaseDir "ccb_data\gfx") },
    @{ Src = $LangMoSrc;                 Dst = (Join-Path $ReleaseDir "ccb_data\lang\mo") }
)
foreach ($mp in $mirrorPairs) {
    if (Test-Path $mp.Src) {
        New-Item -ItemType Directory -Force -Path $mp.Dst | Out-Null
        robocopy $mp.Src $mp.Dst /MIR /NFL /NDL /NJH /NJS /NC /NS /NP /MT:8 /XD ".git" "screenshots" "reference" "string_extractor" "po" /XF "*.cpp" "*.hpp" "*.h" "*.c" "*.py" "*.sh" "*.ps1" "CMakeLists.txt" "Makefile" "AGENTS.md" | Out-Null
        if ($LASTEXITCODE -ge 8) {
            Write-Error "robocopy failed for $($mp.Src) with code $LASTEXITCODE"
            exit $LASTEXITCODE
        }
    }
}

Write-Host "=== [5/5] Verifying zero source leakage in release/ ===" -ForegroundColor Cyan
$leaks = Get-ChildItem $ReleaseDir -Recurse -File -Include *.cpp,*.hpp,*.h,*.c,*.py,*.ps1 -ErrorAction SilentlyContinue
if ($leaks) {
    Write-Error "Source files leaked into release/: $($leaks.FullName -join ', ')"
    exit 1
}
$pckSizeMB = [Math]::Round((Get-Item (Join-Path $ReleaseDir $AppPckName)).Length / 1MB, 2)
$exeSizeKB = [Math]::Round((Get-Item $LauncherExe).Length / 1KB, 1)
Write-Host "Release ready at: $ReleaseDir" -ForegroundColor Green
Write-Host "  - $AppExeName ($exeSizeKB KB) [double-click GUI launcher]"
Write-Host "  - $AppPckName ($pckSizeMB MB) [packed runtime game]"
Write-Host "  - bin/cangling.dll + bin/ccb_bridge.dll"
Write-Host "  - runtime/godot_runtime.exe"
Write-Host "  - ccb_data/{data,gfx,lang} [ZERO source files]"
exit 0
