# =========================================================================
# DEV DISK REPORT - TAURI v2 DESKTOP APP BUILDER (WINDOWS)
# Cach dung:
#   1. Chay thu cua so App ngay (Dev Mode):
#      powershell -ExecutionPolicy Bypass -File "$HOME\disk-report\build-app.ps1" -Dev
#   2. Dong goi ra bo cai .msi / .exe (Release Build):
#      powershell -ExecutionPolicy Bypass -File "$HOME\disk-report\build-app.ps1"
# =========================================================================

param(
    [switch]$Dev
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "  DEV DISK REPORT - TAURI v2 DESKTOP BUILDER (WINDOWS)" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

# 1. Kiem tra Cargo / Rust
$cargoBinDir = "$HOME\.cargo\bin"
if (Test-Path "$cargoBinDir\cargo.exe") {
    if ($env:PATH -notlike "*$cargoBinDir*") {
        $env:PATH = "$cargoBinDir;$env:PATH"
    }
}
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    Write-Host "[!] Chua tim thay Rust (cargo) tren may! Dang cai dat Rustup..." -ForegroundColor Yellow
    & winget install Rustlang.Rustup --accept-source-agreements --accept-package-agreements
    if (Test-Path "$cargoBinDir\cargo.exe") {
        $env:PATH = "$cargoBinDir;$env:PATH"
    } else {
        Write-Host "[!] Vui long khoi dong lai PowerShell sau khi cai Rustup!" -ForegroundColor Red
        exit 1
    }
}

# 2. Tim vcvars64.bat & link.exe cua Visual Studio C++ Build Tools
function Find-VcVars64 {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
        if ($vsPath) {
            $candidate = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"
            if (Test-Path $candidate) { return $candidate }
        }
    }

    $searchRoots = @(
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio",
        "${env:ProgramFiles}\Microsoft Visual Studio"
    )
    foreach ($root in $searchRoots) {
        if (Test-Path $root) {
            $found = Get-ChildItem -Path $root -Filter "vcvars64.bat" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                # Kiem tra xem thu muc VC\Tools\MSVC co link.exe that su chua
                $vcRoot = Split-Path (Split-Path $found.DirectoryName -Parent) -Parent
                $msvcTools = Join-Path $vcRoot "Tools\MSVC"
                if (Test-Path $msvcTools) {
                    $linkCheck = Get-ChildItem -Path $msvcTools -Filter "link.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($linkCheck) { return $found.FullName }
                }
            }
        }
    }
    return $null
}

function Import-VcVars([string]$vcvarsPath) {
    Write-Host "[*] Dang nap moi truong MSVC C++ tu: $vcvarsPath" -ForegroundColor DarkCyan
    $tempBat = Join-Path $env:TEMP "load_vcvars_env.cmd"
    "@echo off`r`ncall `"$vcvarsPath`" >nul 2>&1`r`nset" | Out-File -FilePath $tempBat -Encoding ASCII
    $envLines = & cmd.exe /c $tempBat
    Remove-Item -Force $tempBat -ErrorAction SilentlyContinue
    foreach ($line in $envLines) {
        if ($line -match "^([^=]+)=(.*)$") {
            $k = $matches[1]
            $v = $matches[2]
            [System.Environment]::SetEnvironmentVariable($k, $v, "Process")
        }
    }
}

$vcvarsPath = Find-VcVars64
if (-not $vcvarsPath) {
    Write-Host ""
    Write-Host "[!] Chua tim thay Visual C++ Build Tools (link.exe & Windows SDK) tren may!" -ForegroundColor Yellow
    Write-Host "    Dang tai trinh cai dat chinh thuc vs_buildtools.exe tu Microsoft (~3.5 MB)..." -ForegroundColor Cyan

    $vsBootstrapper = Join-Path $env:TEMP "vs_buildtools.exe"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vs_buildtools.exe" -OutFile $vsBootstrapper -UseBasicParsing

    Write-Host "[*] Dang mo trinh cai dat Visual C++ Build Tools (Tu dong chon C++ VCTools & Windows SDK)..." -ForegroundColor Yellow
    Write-Host "    -> Vui long nhan 'Yes' (UAC) neu Windows hoi quyen Admin va doi cua so cai dat hoan tat!" -ForegroundColor Green

    $proc = Start-Process -FilePath $vsBootstrapper -ArgumentList "--wait --passive --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended" -Wait -PassThru

    $vcvarsPath = Find-VcVars64
    if (-not $vcvarsPath) {
        Write-Host ""
        Write-Host "[!] Chua phat hien duoc link.exe sau khi chay trinh cai dat (Exit code: $($proc.ExitCode))." -ForegroundColor Red
        Write-Host "    Hay dam bao qua trinh cai dat Visual Studio Build Tools da chay xong 100%, sau do chay lai lenh nay!" -ForegroundColor Yellow
        exit 1
    }
}

Import-VcVars $vcvarsPath
$linkCmd = Get-Command link.exe -ErrorAction SilentlyContinue
if ($linkCmd) {
    Write-Host "[OK] Da kich hoat MSVC Linker: $($linkCmd.Source)" -ForegroundColor Green
}

# 3. Dong bo disk-report.html sang ui\index.html
if (-not (Test-Path "$PSScriptRoot\ui")) {
    New-Item -ItemType Directory -Path "$PSScriptRoot\ui" | Out-Null
}
Copy-Item -Path "$PSScriptRoot\disk-report.html" -Destination "$PSScriptRoot\ui\index.html" -Force
Write-Host "[1/3] Da dong bo giao dien disk-report.html -> ui\index.html" -ForegroundColor Green

# 4. Kiem tra hoac tai nhanh cargo-tauri.exe (Prebuilt Binary - Chi mat 3 giay, KHONG can compile!)
$hasTauri = $false
try {
    $tauriVer = & cargo tauri --version 2>$null
    if ($LASTEXITCODE -eq 0 -and $tauriVer) {
        $hasTauri = $true
    }
} catch {}

if (-not $hasTauri) {
    Write-Host "[2/3] Dang tai ban prebuilt cargo-tauri.exe v2 tu GitHub Releases (chi mat ~3-5 giay)..." -ForegroundColor Yellow
    $zipUrl = "https://github.com/tauri-apps/tauri/releases/latest/download/cargo-tauri-x86_64-pc-windows-msvc.zip"
    $tempZip = Join-Path $env:TEMP "cargo-tauri-win64.zip"
    $tempExtract = Join-Path $env:TEMP "cargo-tauri-extract"

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -UseBasicParsing
        if (Test-Path $tempExtract) { Remove-Item -Recurse -Force $tempExtract }
        Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force

        $exeFound = Get-ChildItem -Path $tempExtract -Filter "cargo-tauri.exe" -Recurse | Select-Object -First 1
        if ($exeFound) {
            if (-not (Test-Path $cargoBinDir)) { New-Item -ItemType Directory -Path $cargoBinDir | Out-Null }
            Copy-Item -Path $exeFound.FullName -Destination (Join-Path $cargoBinDir "cargo-tauri.exe") -Force
            Write-Host "[2/3] Da cai dat xong cargo-tauri.exe (Prebuilt) vao $cargoBinDir!" -ForegroundColor Green
            $hasTauri = $true
        }
    } catch {
        Write-Host "[!] Khong the tai ban prebuilt ($($_.Exception.Message)), chuyen sang cargo install..." -ForegroundColor Yellow
        & cargo install tauri-cli --version "^2.0.0" --locked
        if ($LASTEXITCODE -eq 0) { $hasTauri = $true }
    } finally {
        if (Test-Path $tempZip) { Remove-Item -Force $tempZip -ErrorAction SilentlyContinue }
        if (Test-Path $tempExtract) { Remove-Item -Recurse -Force $tempExtract -ErrorAction SilentlyContinue }
    }
} else {
    Write-Host "[2/3] Da san sang $tauriVer" -ForegroundColor Green
}

if (-not $hasTauri) {
    Write-Host "[!] Chua the cai dat cargo-tauri CLI." -ForegroundColor Red
    exit 1
}

# 5. Chay Dev hoac Build Installer (.msi / .exe)
if ($Dev) {
    Write-Host "[3/3] Dang khoi chay cua so Desktop App (cargo tauri dev)..." -ForegroundColor Cyan
    & cargo tauri dev
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[!] Lenh 'cargo tauri dev' gap loi (Exit code: $LASTEXITCODE)." -ForegroundColor Red
        exit $LASTEXITCODE
    }
} else {
    Write-Host "[3/3] Dang dong goi ung dung Desktop (.exe / .msi)..." -ForegroundColor Cyan
    & cargo tauri build
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[!] Lenh 'cargo tauri build' gap loi (Exit code: $LASTEXITCODE)." -ForegroundColor Red
        exit $LASTEXITCODE
    }
    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor Green
    Write-Host "  HOAN TAT DONG GOI UNG DUNG DESKTOP!" -ForegroundColor Green
    Write-Host "  - File chay truc tiep (.exe): target\release\dev-disk-report.exe" -ForegroundColor White
    Write-Host "  - Bo cai dat (.msi / .exe)  : target\release\bundle\" -ForegroundColor White
    Write-Host "==================================================================" -ForegroundColor Green
}
