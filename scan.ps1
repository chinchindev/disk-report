<#
.SYNOPSIS
    Dev Disk & Environment Scanner (Read-Only)
    Compatible with both Windows PowerShell 5.1 (powershell.exe) and PowerShell 7+ (pwsh.exe).
#>

param(
    [string[]]$CodeRoots = @(
        "$HOME\source\repos",
        "$HOME\Projects",
        "$HOME\Workspace",
        "$HOME\Code",
        "$HOME\dev",
        "$HOME\StudioProjects",
        "$HOME\IdeaProjects",
        "$HOME\Documents\GitHub"
    ),
    [int]$StaleDaysThreshold = 30,
    [int]$MinArtifactSizeMB = 5,
    [switch]$OpenReport = $true
)

$ErrorActionPreference = "SilentlyContinue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function U([string]$s) {
    return [regex]::Unescape($s)
}

$GroupSafe   = U "C\u00f3 th\u1ec3 x\u00f3a an to\u00e0n"
$GroupReview = U "C\u1ea7n xem l\u1ea1i tr\u01b0\u1edbc khi x\u00f3a"

$ReportDir = $PSScriptRoot
if (-not $ReportDir) { $ReportDir = "$HOME\disk-report" }
$CsvPath  = Join-Path $ReportDir "sizes.csv"
$JsonPath = Join-Path $ReportDir "report-data.json"
$HtmlPath = Join-Path $ReportDir "disk-report.html"
$ScanTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "  DEV DISK & ENVIRONMENT SCANNER (READ-ONLY)" -ForegroundColor Cyan
Write-Host "  Scan Time: $ScanTime" -ForegroundColor Gray
Write-Host "==================================================================" -ForegroundColor Cyan

# 1. Load previous history from sizes.csv
$PreviousMap = @{}
if (Test-Path -LiteralPath $CsvPath) {
    try {
        $oldRows = Import-Csv -LiteralPath $CsvPath -Encoding UTF8
        foreach ($row in $oldRows) {
            if ($row.Path) {
                $PreviousMap[$row.Path] = [double]$row.SizeMB
            }
        }
        Write-Host "[OK] Loaded history from sizes.csv ($($PreviousMap.Count) items)" -ForegroundColor Green
    } catch {
        Write-Host "[!] Could not read old sizes.csv, starting fresh." -ForegroundColor Yellow
    }
}

# Fast .NET folder size & file count scanner (handles locked subfolders safely)
function Get-FolderStats {
    param([string]$TargetPath)
    if (-not (Test-Path -LiteralPath $TargetPath)) {
        return @{ Exists = $false; FileCount = 0; SizeBytes = 0L }
    }
    [int64]$totalBytes = 0L
    [int]$totalFiles = 0
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push($TargetPath)

    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        try {
            $dirInfo = New-Object System.IO.DirectoryInfo($current)
            foreach ($f in $dirInfo.EnumerateFiles()) {
                $totalBytes += $f.Length
                $totalFiles++
            }
            foreach ($sub in $dirInfo.EnumerateDirectories()) {
                # Skip reparse points / symlinks to avoid infinite loops
                if (($sub.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
                    $stack.Push($sub.FullName)
                }
            }
        } catch {
            # Ignore locked/inaccessible subdirectories
        }
    }
    return @{ Exists = $true; FileCount = $totalFiles; SizeBytes = $totalBytes }
}

# 2. Dev Caches, SDKs, Runtimes & Sessions
$DevTargets = @(
    # --- Mobile & Android / Flutter ---
    @{
        Path = "$env:LOCALAPPDATA\Android\Sdk"
        Name = "Android SDK & Build Tools"
        Category = "Mobile SDK"
        Group = $GroupReview
        CleanCmd = 'sdkmanager --uninstall "..."'
        Impact = (U "X\u00f3a c\u00e1c phi\u00ean b\u1ea3n Android SDK, Build-tools, NDK v\u00e0 system images. B\u1ea1n s\u1ebd ph\u1ea3i t\u1ea3i l\u1ea1i t\u1eeb Android Studio n\u1ebfu c\u1ea7n compile app.")
    },
    @{
        Path = "$HOME\.android\avd"
        Name = "Android Virtual Devices (AVD Images)"
        Category = "Mobile SDK"
        Group = $GroupReview
        CleanCmd = (U "X\u00f3a qua Android Studio Device Manager")
        Impact = (U "X\u00f3a c\u00e1c m\u00e1y \u1ea3o Android gi\u1ea3 l\u1eadp \u0111\u00e3 t\u1ea1o v\u00e0 to\u00e0n b\u1ed9 d\u1eef li\u1ec7u app \u0111\u00e3 c\u00e0i tr\u00ean m\u00e1y \u1ea3o \u0111\u00f3.")
    },
    @{
        Path = "$HOME\.gradle\caches"
        Name = "Gradle Dependency Caches"
        Category = "Java / Android / Gradle"
        Group = $GroupSafe
        CleanCmd = 'gradle --stop; Remove-Item -Recurse -Force "$HOME\.gradle\caches"'
        Impact = (U "X\u00f3a cache dependencies v\u00e0 build artifacts c\u1ee7a Gradle. L\u1ea7n build Android/Java ti\u1ebfp theo s\u1ebd t\u1ef1 \u0111\u1ed9ng t\u1ea3i l\u1ea1i.")
    },
    @{
        Path = "$HOME\.gradle\wrapper\dists"
        Name = "Gradle Wrapper Distributions"
        Category = "Java / Android / Gradle"
        Group = $GroupSafe
        CleanCmd = 'Remove-Item -Recurse -Force "$HOME\.gradle\wrapper\dists"'
        Impact = (U "X\u00f3a c\u00e1c b\u1ea3n ph\u00e2n ph\u1ed1i Gradle c\u0169. Khi ch\u1ea1y ./gradlew s\u1ebd t\u1ef1 t\u1ea3i l\u1ea1i \u0111\u00fang phi\u00ean b\u1ea3n c\u1ea5u h\u00ecnh trong d\u1ef1 \u00e1n.")
    },
    @{
        Path = "$env:LOCALAPPDATA\Pub\Cache"
        Name = "Dart & Flutter Pub Cache"
        Category = "Dart / Flutter"
        Group = $GroupSafe
        CleanCmd = 'dart pub cache clean -f'
        Impact = (U "X\u00f3a c\u00e1c package Dart/Flutter \u0111\u00e3 t\u1ea3i v\u1ec1 t\u1eeb pub.dev. Khi ch\u1ea1y flutter pub get \u1edf d\u1ef1 \u00e1n, package s\u1ebd \u0111\u01b0\u1ee3c t\u1ea3i l\u1ea1i.")
    },

    # --- Node.js / JS Ecosystem ---
    @{
        Path = "$env:LOCALAPPDATA\npm-cache"
        Name = "NPM Global Cache"
        Category = "Node.js / JS"
        Group = $GroupSafe
        CleanCmd = 'npm cache clean --force'
        Impact = (U "X\u00f3a cache c\u00e1c g\u00f3i npm \u0111\u00e3 t\u1ea3i t\u1ea1m th\u1eddi. D\u1ef1 \u00e1n kh\u00f4ng b\u1ecb \u1ea3nh h\u01b0\u1edfng; l\u1ea7n npm install ti\u1ebfp theo s\u1ebd t\u1ea3i l\u1ea1i.")
    },
    @{
        Path = "$env:LOCALAPPDATA\pnpm\store"
        Name = "PNPM Content-Addressable Store"
        Category = "Node.js / JS"
        Group = $GroupSafe
        CleanCmd = 'pnpm store prune'
        Impact = (U "D\u1ecdn d\u1eb9p c\u00e1c g\u00f3i kh\u00f4ng c\u00f2n \u0111\u01b0\u1ee3c tham chi\u1ebfu b\u1edfi b\u1ea5t k\u1ef3 d\u1ef1 \u00e1n n\u00e0o trong PNPM store.")
    },
    @{
        Path = "$env:LOCALAPPDATA\pnpm-cache"
        Name = "PNPM Metadata & DLX Cache"
        Category = "Node.js / JS"
        Group = $GroupSafe
        CleanCmd = 'Remove-Item -Recurse -Force "$env:LOCALAPPDATA\pnpm-cache\*"'
        Impact = (U "X\u00f3a cache metadata v\u00e0 c\u00e1c g\u00f3i ch\u1ea1y t\u1ea1m qua pnpm dlx.")
    },
    @{
        Path = "$env:LOCALAPPDATA\Yarn\Cache"
        Name = "Yarn Global Cache"
        Category = "Node.js / JS"
        Group = $GroupSafe
        CleanCmd = 'yarn cache clean'
        Impact = (U "X\u00f3a b\u1ed9 nh\u1edb \u0111\u1ec7m c\u00e1c package \u0111\u00e3 t\u1ea3i qua Yarn.")
    },
    @{
        Path = "$HOME\.bun\install\cache"
        Name = "Bun Package Cache"
        Category = "Node.js / JS"
        Group = $GroupSafe
        CleanCmd = 'bun pm cache rm'
        Impact = (U "X\u00f3a cache c\u00e1c package \u0111\u00e3 t\u1ea3i c\u1ee7a Bun runtime.")
    },

    # --- Python / AI / ML ---
    @{
        Path = "$env:LOCALAPPDATA\pip\cache"
        Name = "Python Pip Cache"
        Category = "Python / AI"
        Group = $GroupSafe
        CleanCmd = 'pip cache purge'
        Impact = (U "X\u00f3a c\u00e1c file wheel (.whl) v\u00e0 source archive m\u00e0 pip \u0111\u00e3 l\u01b0u t\u1ea1m khi c\u00e0i th\u01b0 vi\u1ec7n Python.")
    },
    @{
        Path = "$env:LOCALAPPDATA\uv\cache"
        Name = "Astral uv Package Cache"
        Category = "Python / AI"
        Group = $GroupSafe
        CleanCmd = 'uv cache clean'
        Impact = (U "X\u00f3a cache c\u00e1c g\u00f3i Python v\u00e0 m\u00f4i tr\u01b0\u1eddng \u1ea3o t\u1ea1m c\u1ee7a uv.")
    },
    @{
        Path = "$HOME\.cache\huggingface"
        Name = "HuggingFace Models & Datasets Cache"
        Category = "Python / AI"
        Group = $GroupReview
        CleanCmd = 'huggingface-cli delete-cache'
        Impact = (U "X\u00f3a c\u00e1c tr\u1ecdng s\u1ed1 m\u00f4 h\u00ecnh AI (LLM/Vision) v\u00e0 dataset \u0111\u00e3 t\u1ea3i v\u1ec1 t\u1eeb HuggingFace Hub.")
    },
    @{
        Path = "$HOME\.ollama\models"
        Name = "Ollama Local LLM Models"
        Category = "Python / AI"
        Group = $GroupReview
        CleanCmd = 'ollama list; # ollama rm <model>'
        Impact = (U "X\u00f3a c\u00e1c m\u00f4 h\u00ecnh ng\u00f4n ng\u1eef l\u1edbn ch\u1ea1y c\u1ee5c b\u1ed9 qua Ollama. S\u1ebd ph\u1ea3i pull l\u1ea1i nhi\u1ec1u GB n\u1ebfu c\u1ea7n d\u00f9ng.")
    },
    @{
        Path = "$HOME\.conda\pkgs"
        Name = "Conda Package Tarballs & Cache"
        Category = "Python / AI"
        Group = $GroupSafe
        CleanCmd = 'conda clean --all -y'
        Impact = (U "X\u00f3a c\u00e1c g\u00f3i c\u00e0i \u0111\u1eb7t v\u00e0 tarball kh\u00f4ng c\u00f2n s\u1eed d\u1ee5ng c\u1ee7a Anaconda/Miniconda.")
    },

    # --- Rust / Go / .NET / Java / Ruby / PHP ---
    @{
        Path = "$HOME\.cargo\registry"
        Name = "Rust Cargo Registry & Crates Cache"
        Category = "Rust / Go / .NET"
        Group = $GroupSafe
        CleanCmd = 'Remove-Item -Recurse -Force "$HOME\.cargo\registry\cache\*", "$HOME\.cargo\registry\src\*"'
        Impact = (U "X\u00f3a m\u00e3 ngu\u1ed3n v\u00e0 file n\u00e9n c\u00e1c crate Rust \u0111\u00e3 t\u1ea3i v\u1ec1. Cargo s\u1ebd t\u1ef1 t\u1ea3i l\u1ea1i khi build.")
    },
    @{
        Path = "$HOME\.rustup\toolchains"
        Name = "Rustup Installed Toolchains"
        Category = "Rust / Go / .NET"
        Group = $GroupReview
        CleanCmd = 'rustup toolchain list'
        Impact = (U "Ch\u1ee9a tr\u00ecnh bi\u00ean d\u1ecbch Rust (stable/nightly). Ch\u1ec9 n\u00ean g\u1ee1 c\u00e1c toolchain c\u0169 kh\u00f4ng c\u00f2n d\u00f9ng.")
    },
    @{
        Path = "$env:LOCALAPPDATA\go-build"
        Name = "Go Build Artifact Cache"
        Category = "Rust / Go / .NET"
        Group = $GroupSafe
        CleanCmd = 'go clean -cache'
        Impact = (U "X\u00f3a cache bi\u00ean d\u1ecbch t\u1ea1m c\u1ee7a Go. L\u1ea7n go build ti\u1ebfp theo s\u1ebd bi\u00ean d\u1ecbch l\u1ea1i.")
    },
    @{
        Path = "$HOME\go\pkg\mod\cache"
        Name = "Go Module Download Cache"
        Category = "Rust / Go / .NET"
        Group = $GroupSafe
        CleanCmd = 'go clean -modcache'
        Impact = (U "X\u00f3a cache c\u00e1c Go modules \u0111\u00e3 t\u1ea3i v\u1ec1.")
    },
    @{
        Path = "$HOME\.nuget\packages"
        Name = ".NET NuGet Global Packages Cache"
        Category = "Rust / Go / .NET"
        Group = $GroupSafe
        CleanCmd = 'dotnet nuget locals all --clear'
        Impact = (U "X\u00f3a to\u00e0n b\u1ed9 c\u00e1c g\u00f3i th\u01b0 vi\u1ec7n .NET NuGet \u0111\u00e3 t\u1ea3i v\u1ec1 m\u00e1y. Khi build project C#/.NET s\u1ebd t\u1ef1 restore l\u1ea1i.")
    },
    @{
        Path = "$HOME\.jdks"
        Name = "Downloaded Java JDKs"
        Category = "Runtimes / SDK"
        Group = $GroupReview
        CleanCmd = 'Remove-Item -Recurse -Force "$HOME\.jdks"'
        Impact = (U "X\u00f3a c\u00e1c b\u1ed9 c\u00e0i OpenJDK \u0111\u00e3 t\u1ea3i qua IDE. D\u1ef1 \u00e1n c\u1ea7n JDK \u0111\u00f3 s\u1ebd ph\u1ea3i ch\u1ec9 \u0111\u1ecbnh l\u1ea1i \u0111\u01b0\u1eddng d\u1eabn.")
    },
    @{
        Path = "$HOME\.m2\repository"
        Name = "Maven Local Repository Cache"
        Category = "Java / Maven"
        Group = $GroupSafe
        CleanCmd = 'Remove-Item -Recurse -Force "$HOME\.m2\repository"'
        Impact = (U "X\u00f3a c\u00e1c th\u01b0 vi\u1ec7n JAR \u0111\u00e3 t\u1ea3i v\u1ec1. Khi build Maven/Gradle, h\u1ec7 th\u1ed1ng s\u1ebd t\u1ef1 t\u1ea3i l\u1ea1i t\u1eeb kho l\u01b0u tr\u1eef.")
    },
    @{
        Path = "$HOME\.bundle\cache"
        Name = "Ruby Bundler Cache"
        Category = "Ruby"
        Group = $GroupSafe
        CleanCmd = 'bundle clean --force'
        Impact = (U "X\u00f3a c\u00e1c gem c\u0169 kh\u00f4ng c\u00f2n d\u00f9ng trong Gemfile. Kh\u00f4ng \u1ea3nh h\u01b0\u1edfng \u0111\u1ebfn c\u00e1c gem \u0111ang s\u1eed d\u1ee5ng.")
    },
    @{
        Path = "$env:LOCALAPPDATA\Composer\cache"
        Name = "PHP Composer Cache"
        Category = "PHP"
        Group = $GroupSafe
        CleanCmd = 'composer clear-cache'
        Impact = (U "X\u00f3a cache c\u00e1c g\u00f3i th\u01b0 vi\u1ec7n PHP Composer \u0111\u00e3 t\u1ea3i v\u1ec1.")
    },

    # --- Headless Browsers & E2E Testing ---
    @{
        Path = "$env:LOCALAPPDATA\ms-playwright"
        Name = "Playwright Headless Browsers (Chromium/Firefox/WebKit)"
        Category = "E2E / Testing"
        Group = $GroupSafe
        CleanCmd = 'npx playwright uninstall --all'
        Impact = (U "X\u00f3a c\u00e1c tr\u00ecnh duy\u1ec7t ph\u1ee5c v\u1ee5 test t\u1ef1 \u0111\u1ed9ng Playwright (~500MB - 2GB). Ch\u1ea1y npx playwright install \u0111\u1ec3 t\u1ea3i l\u1ea1i.")
    },
    @{
        Path = "$HOME\.cache\puppeteer"
        Name = "Puppeteer Browser Binaries Cache"
        Category = "E2E / Testing"
        Group = $GroupSafe
        CleanCmd = 'npx puppeteer browsers clear'
        Impact = (U "X\u00f3a c\u00e1c b\u1ea3n Chromium t\u1ea3i v\u1ec1 b\u1edfi Puppeteer.")
    },
    @{
        Path = "$env:LOCALAPPDATA\Cypress\Cache"
        Name = "Cypress Binary Cache"
        Category = "E2E / Testing"
        Group = $GroupSafe
        CleanCmd = 'npx cypress cache clear'
        Impact = (U "X\u00f3a c\u00e1c phi\u00ean b\u1ea3n Cypress binary c\u0169 \u0111\u00e3 l\u01b0u trong m\u00e1y.")
    },

    # --- Containers, Package Managers & System Temp ---
    @{
        Path = "$env:LOCALAPPDATA\Docker"
        Name = "Docker Desktop & WSL Data"
        Category = "Docker"
        Group = $GroupReview
        CleanCmd = 'docker system prune -a --volumes'
        Impact = (U "X\u00d3A TO\u00c0N B\u1ed8 images, containers kh\u00f4ng ch\u1ea1y v\u00e0 volumes c\u1ee7a Docker. B\u1ea1n s\u1ebd ph\u1ea3i pull/build l\u1ea1i images t\u1eeb \u0111\u1ea7u.")
    },
    @{
        Path = "$HOME\scoop\cache"
        Name = "Scoop Package Cache"
        Category = "Package Manager"
        Group = $GroupSafe
        CleanCmd = 'scoop cache rm *'
        Impact = (U "X\u00f3a c\u00e1c b\u1ed9 c\u00e0i \u0111\u1eb7t (.zip, .exe) \u0111\u00e3 t\u1ea3i v\u1ec1 sau khi c\u00e0i \u1ee9ng d\u1ee5ng qua Scoop. Kh\u00f4ng \u1ea3nh h\u01b0\u1edfng \u0111\u1ebfn \u1ee9ng d\u1ee5ng \u0111ang ch\u1ea1y.")
    },
    @{
        Path = "$env:LOCALAPPDATA\Temp"
        Name = "Windows Temp (Dev / Build Temp)"
        Category = "System / Build Temp"
        Group = $GroupSafe
        CleanCmd = 'Remove-Item -Path "$env:LOCALAPPDATA\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue'
        Impact = (U "X\u00f3a c\u00e1c file t\u1ea1m do tr\u00ecnh bi\u00ean d\u1ecbch, IDE v\u00e0 h\u1ec7 th\u1ed1ng t\u1ea1o ra. C\u00e1c file \u0111ang m\u1edf s\u1ebd \u0111\u01b0\u1ee3c t\u1ef1 \u0111\u1ed9ng b\u1ecf qua an to\u00e0n.")
    },
    @{
        Path = "$env:LOCALAPPDATA\CrashDumps"
        Name = "Application Crash Dumps (.dmp)"
        Category = "System / Build Temp"
        Group = $GroupSafe
        CleanCmd = 'Remove-Item -Path "$env:LOCALAPPDATA\CrashDumps\*" -Recurse -Force -ErrorAction SilentlyContinue'
        Impact = (U "X\u00f3a c\u00e1c file memory dump sinh ra khi \u1ee9ng d\u1ee5ng ho\u1eb7c IDE b\u1ecb crash.")
    },
    @{
        Path = "$HOME\.cache"
        Name = "User Tools Cache (Firebase, CLI Tools)"
        Category = "Cache"
        Group = $GroupSafe
        CleanCmd = 'Remove-Item -Recurse -Force "$HOME\.cache\*" -ErrorAction SilentlyContinue'
        Impact = (U "X\u00f3a cache staging c\u1ee7a c\u00e1c c\u00f4ng c\u1ee5 CLI (Firebase, DevTools...). S\u1ebd t\u1ef1 t\u1ea1o l\u1ea1i khi d\u00f9ng.")
    },

    # --- IDEs & Agent Sessions ---
    @{
        Path = "$env:LOCALAPPDATA\JetBrains"
        Name = "JetBrains IDEs Caches & Indexes"
        Category = "IDE Data"
        Group = $GroupReview
        CleanCmd = (U "M\u1edf JetBrains IDE -> File -> Invalidate Caches")
        Impact = (U "X\u00f3a b\u1ed9 ch\u1ec9 m\u1ee5c m\u00e3 ngu\u1ed3n (indexes) v\u00e0 plugins c\u1ee7a Android Studio / IntelliJ IDEA.")
    },
    @{
        Path = "$HOME\.vscode\extensions"
        Name = "VS Code Active Extensions"
        Category = "IDE Extensions"
        Group = $GroupReview
        CleanCmd = 'code --uninstall-extension <id>'
        Impact = (U "X\u00f3a c\u00e1c ti\u1ec7n \u00edch m\u1edf r\u1ed9ng \u0111\u00e3 c\u00e0i tr\u00ean VS Code. S\u1ebd ph\u1ea3i c\u00e0i \u0111\u1eb7t l\u1ea1i.")
    },
    @{
        Path = "$HOME\.antigravity-ide\extensions"
        Name = "Antigravity IDE Active Extensions"
        Category = "IDE Extensions"
        Group = $GroupReview
        CleanCmd = (U "G\u1ee1 extension qua giao di\u1ec7n IDE Extensions")
        Impact = (U "X\u00f3a c\u00e1c ti\u1ec7n \u00edch m\u1edf r\u1ed9ng \u0111ang ho\u1ea1t \u0111\u1ed9ng c\u1ee7a IDE (Flutter, Python, Go...). S\u1ebd ph\u1ea3i c\u00e0i l\u1ea1i.")
    },
    @{
        Path = "$HOME\.gemini\antigravity-backup"
        Name = "Antigravity Migration Backup (June 2026)"
        Category = "Antigravity"
        Group = $GroupSafe
        CleanCmd = 'Remove-Item -Recurse -Force "$HOME\.gemini\antigravity-backup"'
        Impact = (U "B\u1ea3n sao l\u01b0u c\u0169 t\u1eeb \u0111\u1ee3t migration th\u00e1ng 6/2026 (~121 MB). Hi\u1ec7n t\u1ea1i kh\u00f4ng c\u00f2n s\u1eed d\u1ee5ng.")
    },
    @{
        Path = "$HOME\.gemini\antigravity\conversations"
        Name = "Antigravity Agent Sessions (CLI / Core)"
        Category = "Sessions"
        Group = $GroupReview
        CleanCmd = 'Remove-Item -Recurse -Force "$HOME\.gemini\antigravity\conversations\*"'
        Impact = (U "M\u1ea4T TO\u00c0N B\u1ed8 l\u1ecbch s\u1eed c\u00e1c cu\u1ed9c h\u1ed9i tho\u1ea1i v\u00e0 ng\u1eef c\u1ea3nh tr\u01b0\u1edbc \u0111\u00e2y v\u1edbi Antigravity Agent.")
    },
    @{
        Path = "$HOME\.gemini\antigravity-ide\conversations"
        Name = "Antigravity IDE Sessions (GUI Chat)"
        Category = "Sessions"
        Group = $GroupReview
        CleanCmd = 'Remove-Item -Recurse -Force "$HOME\.gemini\antigravity-ide\conversations\*"'
        Impact = (U "M\u1ea5t l\u1ecbch s\u1eed c\u00e1c phi\u00ean chat b\u00ean trong giao di\u1ec7n Antigravity IDE.")
    },
    @{
        Path = "$HOME\.gemini\antigravity\brain"
        Name = "Antigravity Agent Brain & Logs"
        Category = "Sessions"
        Group = $GroupReview
        CleanCmd = 'Remove-Item -Recurse -Force "$HOME\.gemini\antigravity\brain\*"'
        Impact = (U "X\u00f3a to\u00e0n b\u1ed9 logs c\u00e1c t\u00e1c v\u1ee5 n\u1ec1n, subagents v\u00e0 artifacts c\u1ee7a Agent.")
    },
    @{
        Path = "$HOME\.gemini\antigravity-ide\brain"
        Name = "Antigravity IDE Brain & Task Logs"
        Category = "Sessions"
        Group = $GroupReview
        CleanCmd = 'Remove-Item -Recurse -Force "$HOME\.gemini\antigravity-ide\brain\*"'
        Impact = (U "X\u00f3a d\u1eef li\u1ec7u t\u00e1c v\u1ee5 n\u1ec1n v\u00e0 l\u1ecbch s\u1eed task c\u1ee7a IDE.")
    }
)

Write-Host "`n[1/3] Scanning Dev Caches, SDKs & Sessions..." -ForegroundColor Cyan
$ScannedCaches = @()
foreach ($t in $DevTargets) {
    $stats = Get-FolderStats -TargetPath $t.Path
    if (-not $stats.Exists -or $stats.SizeBytes -le 0) { continue }

    $sizeMB = [math]::Round($stats.SizeBytes / 1MB, 2)
    $sizeGB = [math]::Round($stats.SizeBytes / 1GB, 2)
    $prevMB = if ($PreviousMap.ContainsKey($t.Path)) { $PreviousMap[$t.Path] } else { $sizeMB }
    $deltaMB = [math]::Round($sizeMB - $prevMB, 2)
    $increased = ($deltaMB -gt 0.05)

    $item = [PSCustomObject]@{
        Path           = $t.Path
        Name           = $t.Name
        Category       = $t.Category
        Group          = $t.Group
        FileCount      = $stats.FileCount
        SizeBytes      = $stats.SizeBytes
        SizeMB         = $sizeMB
        SizeGB         = $sizeGB
        PreviousSizeMB = $prevMB
        DeltaMB        = $deltaMB
        Increased      = $increased
        CleanCmd       = $t.CleanCmd
        Impact         = $t.Impact
        ScanTime       = $ScanTime
    }
    $ScannedCaches += $item
    Write-Host ("  * {0,-44} {1,10} MB" -f $t.Name, $sizeMB) -ForegroundColor Gray
}
$ScannedCaches = @($ScannedCaches | Sort-Object -Property SizeBytes -Descending)

# 3. Scan Project Build Artifacts (node_modules, .next, target, build, .dart_tool, .venv...)
Write-Host "`n[2/3] Scanning Project Build Artifacts in code workspaces..." -ForegroundColor Cyan
$ArtifactPatterns = @{
    "node_modules" = @{
        Category = "Node.js / JS"
        Impact   = (U "Th\u01b0 m\u1ee5c dependencies c\u1ee7a d\u1ef1 \u00e1n JS/TS. C\u00f3 th\u1ec3 kh\u00f4i ph\u1ee5c b\u1ea5t c\u1ee9 l\u00fac n\u00e0o b\u1eb1ng npm/pnpm/yarn install.")
    }
    ".next" = @{
        Category = "Next.js Build"
        Impact   = (U "Cache build c\u1ee7a Next.js. T\u1ef1 \u0111\u1ed9ng t\u1ea1o l\u1ea1i khi ch\u1ea1y next dev ho\u1eb7c next build.")
    }
    ".nuxt" = @{
        Category = "Nuxt Build"
        Impact   = (U "Cache build c\u1ee7a Nuxt. T\u1ef1 t\u1ea1o l\u1ea1i khi ch\u1ea1y dev/build.")
    }
    "target" = @{
        Category = "Rust / Maven"
        Impact   = (U "Th\u01b0 m\u1ee5c bi\u00ean d\u1ecbch c\u1ee7a Cargo (Rust) ho\u1eb7c Maven (Java). T\u1ef1 t\u1ea1o l\u1ea1i khi cargo build / mvn package.")
    }
    ".dart_tool" = @{
        Category = "Dart / Flutter"
        Impact   = (U "Cache bi\u00ean d\u1ecbch v\u00e0 codegen c\u1ee7a Dart/Flutter. T\u1ef1 t\u1ea1o l\u1ea1i khi ch\u1ea1y flutter pub get.")
    }
    "build" = @{
        Category = "Mobile / Gradle"
        Impact   = (U "Th\u01b0 m\u1ee5c ch\u1ee9a file APK/AAB/binaries trung gian khi build d\u1ef1 \u00e1n.")
    }
    ".gradle" = @{
        Category = "Java / Android / Gradle"
        Impact   = (U "Cache Gradle c\u1ee5c b\u1ed9 b\u00ean trong th\u01b0 m\u1ee5c d\u1ef1 \u00e1n.")
    }
    ".venv" = @{
        Category = "Python / AI"
        Impact   = (U "M\u00f4i tr\u01b0\u1eddng \u1ea3o Python c\u1ee5c b\u1ed9 c\u1ee7a d\u1ef1 \u00e1n. C\u00f3 th\u1ec3 t\u1ea1o l\u1ea1i t\u1eeb requirements.txt / pyproject.toml.")
    }
    "venv" = @{
        Category = "Python / AI"
        Impact   = (U "M\u00f4i tr\u01b0\u1eddng \u1ea3o Python c\u1ee5c b\u1ed9 c\u1ee7a d\u1ef1 \u00e1n. C\u00f3 th\u1ec3 t\u1ea1o l\u1ea1i t\u1eeb requirements.txt / pyproject.toml.")
    }
}

$ScannedArtifacts = @()
$VisitedProjects = @{}

$ExcludedHomeDirs = @(
    "AppData", "Pictures", "Photos", "Music", "Videos", "Downloads",
    "OneDrive", "Contacts", "Favorites", "Links", "Saved Games", "Searches",
    ".ssh", ".gemini", ".android", ".gradle", ".jdks", ".m2", ".vscode",
    ".antigravity-ide", ".cache", ".bundle", "scoop", "disk-report"
)

$HomeSubDirs = Get-ChildItem -LiteralPath $HOME -Directory -ErrorAction SilentlyContinue | Where-Object {
    $ExcludedHomeDirs -notcontains $_.Name -and -not $_.Name.StartsWith(".")
}
foreach ($d in $HomeSubDirs) {
    $isProjectOrContainer = (Test-Path (Join-Path $d.FullName ".git")) -or
                            (Test-Path (Join-Path $d.FullName "package.json")) -or
                            (Test-Path (Join-Path $d.FullName "pubspec.yaml")) -or
                            (Test-Path (Join-Path $d.FullName "Cargo.toml")) -or
                            (Test-Path (Join-Path $d.FullName "pyproject.toml"))
    if ($isProjectOrContainer -and ($CodeRoots -notcontains $d.FullName)) {
        $CodeRoots += $d.FullName
    }
}

foreach ($root in $CodeRoots) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    $dirs = Get-ChildItem -LiteralPath $root -Directory -Depth 3 -ErrorAction SilentlyContinue | Where-Object {
        $ArtifactPatterns.ContainsKey($_.Name) -and $_.FullName -notmatch "\\node_modules\\.+\\node_modules"
    }
    foreach ($dir in $dirs) {
        if ($VisitedProjects.ContainsKey($dir.FullName)) { continue }
        $VisitedProjects[$dir.FullName] = $true

        $stats = Get-FolderStats -TargetPath $dir.FullName
        $sizeMB = [math]::Round($stats.SizeBytes / 1MB, 2)
        if ($sizeMB -lt $MinArtifactSizeMB) { continue }

        $parentDir = $dir.Parent
        $projectName = if ($parentDir) { $parentDir.Name } else { $dir.Name }
        $lastWrite = if ($parentDir) { $parentDir.LastWriteTime } else { $dir.LastWriteTime }
        $daysIdle = [math]::Max(0, [int]((Get-Date) - $lastWrite).TotalDays)
        $isStale = ($daysIdle -ge $StaleDaysThreshold)

        $meta = $ArtifactPatterns[$dir.Name]
        $groupName = if ($isStale) { $GroupSafe } else { $GroupReview }
        $impactText = $meta.Impact + " (" + (U "C\u1eadp nh\u1eadt l\u1ea7n cu\u1ed1i: ") + "$daysIdle " + (U "ng\u00e0y tr\u01b0\u1edbc") + ")."

        $ScannedArtifacts += [PSCustomObject]@{
            Path         = $dir.FullName
            Name         = "$projectName ($($dir.Name))"
            ProjectName  = $projectName
            ArtifactType = $dir.Name
            Category     = $meta.Category
            Group        = $groupName
            FileCount    = $stats.FileCount
            SizeBytes    = $stats.SizeBytes
            SizeMB       = $sizeMB
            SizeGB       = [math]::Round($stats.SizeBytes / 1GB, 2)
            DaysIdle     = $daysIdle
            IsStale      = $isStale
            LastModified = $lastWrite.ToString("yyyy-MM-dd")
            CleanCmd     = "Remove-Item -LiteralPath `"$($dir.FullName)`" -Recurse -Force"
            Impact       = $impactText
            ScanTime     = $ScanTime
        }
        Write-Host ("  * [Artifact] {0,-36} {1,8} MB ({2}d idle)" -f "$projectName/$($dir.Name)", $sizeMB, $daysIdle) -ForegroundColor Gray
    }
}
$ScannedArtifacts = @($ScannedArtifacts | Sort-Object -Property SizeBytes -Descending)

# 4. Scan Dead PATH & Broken Dev Environment Variables (WinTrash-inspired)
Write-Host "`n[3/3] Scanning Dead PATH & Broken Dev Environment Variables..." -ForegroundColor Cyan
$EnvIssues = @()

function Test-PathEntries {
    param([string]$ScopeLabel, [System.EnvironmentVariableTarget]$Target)
    $rawPath = [Environment]::GetEnvironmentVariable("Path", $Target)
    if (-not $rawPath) { return }
    $entries = $rawPath -split ";" | Where-Object { $_.Trim() -ne "" }
    $seen = @{}

    foreach ($entry in $entries) {
        $trimmed = $entry.Trim().Trim('"')
        if (-not $trimmed) { continue }
        $expanded = [Environment]::ExpandEnvironmentVariables($trimmed)
        $norm = $expanded.ToLowerInvariant().TrimEnd('\')

        if ($seen.ContainsKey($norm)) {
            $script:EnvIssues += [PSCustomObject]@{
                Id          = "PATH-DUP-$ScopeLabel-$($script:EnvIssues.Count)"
                Type        = "Duplicate PATH"
                Scope       = $ScopeLabel
                VarName     = "PATH ($ScopeLabel)"
                TargetValue = $trimmed
                Status      = (U "Tr\u00f9ng l\u1eb7p \u0111\u01b0\u1eddng d\u1eabn")
                Group       = $GroupSafe
                Impact      = (U "\u0110\u01b0\u1eddng d\u1eabn n\u00e0y b\u1ecb khai b\u00e1o l\u1eb7p l\u1ea1i nhi\u1ec1u l\u1ea7n trong bi\u1ebfn PATH ($ScopeLabel).")
                CleanCmd    = "# Duplicate entry '$trimmed' in $ScopeLabel PATH"
            }
            continue
        }
        $seen[$norm] = $true

        if (-not (Test-Path -LiteralPath $expanded)) {
            $impactMsg = (U "\u0110\u01b0\u1eddng d\u1eabn '") + $trimmed + (U "' trong PATH ($ScopeLabel) tr\u1ecf t\u1edbi th\u01b0 m\u1ee5c \u0111\u00e3 b\u1ecb x\u00f3a.")
            $script:EnvIssues += [PSCustomObject]@{
                Id          = "PATH-DEAD-$ScopeLabel-$($script:EnvIssues.Count)"
                Type        = "Dead PATH"
                Scope       = $ScopeLabel
                VarName     = "PATH ($ScopeLabel)"
                TargetValue = $trimmed
                Status      = (U "Th\u01b0 m\u1ee5c kh\u00f4ng t\u1ed3n t\u1ea1i")
                Group       = $GroupSafe
                Impact      = $impactMsg
                CleanCmd    = "`$p = [Environment]::GetEnvironmentVariable('Path', '$Target'); `$newP = (`$p -split ';' | Where-Object { `$_.Trim().Trim('`"') -ne '$trimmed' }) -join ';'; [Environment]::SetEnvironmentVariable('Path', `$newP, '$Target')"
            }
            Write-Host "  * [Dead PATH - $ScopeLabel] $trimmed" -ForegroundColor Yellow
        }
    }
}

Test-PathEntries -ScopeLabel "User" -Target ([System.EnvironmentVariableTarget]::User)
Test-PathEntries -ScopeLabel "System" -Target ([System.EnvironmentVariableTarget]::Machine)

$DevEnvVars = @(
    "JAVA_HOME", "ANDROID_HOME", "ANDROID_SDK_ROOT", "ANDROID_AVD_HOME",
    "FLUTTER_ROOT", "PUB_CACHE", "GRADLE_USER_HOME", "MAVEN_HOME", "M2_HOME",
    "GOPATH", "GOROOT", "CARGO_HOME", "RUSTUP_HOME",
    "NVM_HOME", "NVM_SYMLINK", "PNPM_HOME", "VOLTA_HOME", "BUN_INSTALL",
    "PYENV", "PYENV_ROOT", "PYENV_HOME", "CONDA_PREFIX", "VIRTUAL_ENV", "UV_CACHE_DIR"
)

foreach ($varName in $DevEnvVars) {
    foreach ($scope in @("User", "Machine")) {
        $target = [System.EnvironmentVariableTarget]::$scope
        $val = [Environment]::GetEnvironmentVariable($varName, $target)
        if (-not $val) { continue }
        $expanded = [Environment]::ExpandEnvironmentVariables($val.Trim().Trim('"'))
        if (-not (Test-Path -LiteralPath $expanded)) {
            $scopeLabel = if ($scope -eq "Machine") { "System" } else { "User" }
            $impactMsg = (U "Bi\u1ebfn m\u00f4i tr\u01b0\u1eddng '$varName' ($scopeLabel) \u0111ang tr\u1ecf t\u1edbi '") + $val + (U "' kh\u00f4ng c\u00f2n t\u1ed3n t\u1ea1i.")
            $EnvIssues += [PSCustomObject]@{
                Id          = "ENV-DEAD-$scopeLabel-$varName"
                Type        = "Broken Dev Variable"
                Scope       = $scopeLabel
                VarName     = $varName
                TargetValue = $val
                Status      = (U "Tr\u1ecf t\u1edbi \u0111\u01b0\u1eddng d\u1eabn \u0111\u00e3 x\u00f3a")
                Group       = $GroupSafe
                Impact      = $impactMsg
                CleanCmd    = "[Environment]::SetEnvironmentVariable('$varName', `$null, '$scope')"
            }
            Write-Host "  * [Broken ENV - $scopeLabel] $varName = $val" -ForegroundColor Yellow
        }
    }
}

# 5. Save sizes.csv and report-data.json
$ScannedCaches | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8
Write-Host "`n[OK] Updated $CsvPath" -ForegroundColor Green

$CombinedPayload = [PSCustomObject]@{
    ScanTime  = $ScanTime
    Caches    = @($ScannedCaches)
    Artifacts = @($ScannedArtifacts)
    EnvIssues = @($EnvIssues)
}
$JsonString = $CombinedPayload | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText($JsonPath, $JsonString, [System.Text.Encoding]::UTF8)
Write-Host "[OK] Updated $JsonPath" -ForegroundColor Green

# 6. Inject directly into disk-report.html
if (Test-Path -LiteralPath $HtmlPath) {
    $htmlContent = [System.IO.File]::ReadAllText($HtmlPath, [System.Text.Encoding]::UTF8)
    $startMarker = "// === BEGIN_AUTO_DATA ==="
    $endMarker   = "// === END_AUTO_DATA ==="
    $idxStart = $htmlContent.IndexOf($startMarker)
    $idxEnd   = $htmlContent.IndexOf($endMarker)
    if ($idxStart -ge 0 -and $idxEnd -gt $idxStart) {
        $before = $htmlContent.Substring(0, $idxStart)
        $after  = $htmlContent.Substring($idxEnd + $endMarker.Length)
        $injected = "$startMarker`r`n    const scanPayload = $JsonString;`r`n    $endMarker"
        $newHtml = $before + $injected + $after
        [System.IO.File]::WriteAllText($HtmlPath, $newHtml, [System.Text.Encoding]::UTF8)
        Write-Host "[OK] Synced data directly into disk-report.html" -ForegroundColor Green
    }
}

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "  SCAN COMPLETE! Opening disk-report.html..." -ForegroundColor Green
Write-Host "==================================================================" -ForegroundColor Cyan

if ($OpenReport -and (Test-Path -LiteralPath $HtmlPath)) {
    Start-Process $HtmlPath
}
