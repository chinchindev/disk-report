use crate::models::{ArtifactItem, CacheItem, EnvIssue, ScanPayload, TargetSpec};
use chrono::{DateTime, Local};
use rayon::prelude::*;
use std::collections::{HashMap, HashSet};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{Instant, SystemTime};
use walkdir::WalkDir;

const GROUP_SAFE: &str = "Có thể xóa an toàn";
const GROUP_REVIEW: &str = "Cần xem lại trước khi xóa";

/// Tinh nhanh dung luong va so luong file cua 1 thu muc (bo qua symlink)
pub fn compute_folder_stats(path: &Path) -> (bool, u64, u64) {
    if !path.exists() {
        return (false, 0, 0);
    }
    let mut total_files = 0u64;
    let mut total_bytes = 0u64;

    for entry in WalkDir::new(path)
        .follow_links(false)
        .into_iter()
        .filter_map(|e| e.ok())
    {
        if entry.file_type().is_file() {
            if let Ok(meta) = entry.metadata() {
                total_files += 1;
                total_bytes += meta.len();
            }
        }
    }

    (true, total_files, total_bytes)
}

fn round2(val: f64) -> f64 {
    (val * 100.0).round() / 100.0
}

/// Lay danh sach cac thu muc Dev Caches, SDKs va Sessions cho Windows & macOS
pub fn build_dev_targets() -> Vec<TargetSpec> {
    let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("."));
    let is_mac = cfg!(target_os = "macos");

    let local_app = if is_mac {
        home.join("Library").join("Caches")
    } else {
        dirs::data_local_dir().unwrap_or_else(|| home.join("AppData").join("Local"))
    };

    let mut specs = vec![
        // --- Mobile & Android / Flutter ---
        TargetSpec {
            path: if is_mac {
                home.join("Library/Android/sdk")
            } else {
                local_app.join("Android/Sdk")
            },
            name: "Android SDK & Build Tools",
            category: "Mobile SDK",
            is_safe: false,
            clean_cmd_win: "sdkmanager --uninstall \"...\"",
            clean_cmd_mac: "sdkmanager --uninstall \"...\"",
            impact: "Xóa các phiên bản Android SDK, Build-tools, NDK và system images. Bạn sẽ phải tải lại từ Android Studio nếu cần compile app.",
        },
        TargetSpec {
            path: home.join(".android/avd"),
            name: "Android Virtual Devices (AVD Images)",
            category: "Mobile SDK",
            is_safe: false,
            clean_cmd_win: "Xóa qua Android Studio Device Manager",
            clean_cmd_mac: "rm -rf ~/.android/avd/*.avd",
            impact: "Xóa các máy ảo Android giả lập đã tạo và toàn bộ dữ liệu app đã cài trên máy ảo đó.",
        },
        TargetSpec {
            path: home.join(".gradle/caches"),
            name: "Gradle Dependency Caches",
            category: "Java / Android / Gradle",
            is_safe: true,
            clean_cmd_win: "gradle --stop; Remove-Item -Recurse -Force \"$HOME\\.gradle\\caches\"",
            clean_cmd_mac: "gradle --stop && rm -rf ~/.gradle/caches",
            impact: "Xóa cache dependencies và build artifacts của Gradle. Lần build Android/Java tiếp theo sẽ tự động tải lại.",
        },
        TargetSpec {
            path: home.join(".gradle/wrapper/dists"),
            name: "Gradle Wrapper Distributions",
            category: "Java / Android / Gradle",
            is_safe: true,
            clean_cmd_win: "Remove-Item -Recurse -Force \"$HOME\\.gradle\\wrapper\\dists\"",
            clean_cmd_mac: "rm -rf ~/.gradle/wrapper/dists/*",
            impact: "Xóa các bản phân phối Gradle cũ. Khi chạy ./gradlew sẽ tự tải lại đúng phiên bản cấu hình trong dự án.",
        },
        TargetSpec {
            path: if is_mac {
                home.join(".pub-cache")
            } else {
                local_app.join("Pub/Cache")
            },
            name: "Dart & Flutter Pub Cache",
            category: "Dart / Flutter",
            is_safe: true,
            clean_cmd_win: "dart pub cache clean -f",
            clean_cmd_mac: "dart pub cache clean -f",
            impact: "Xóa các package Dart/Flutter đã tải về từ pub.dev. Khi chạy flutter pub get ở dự án, package sẽ được tải lại.",
        },
        // --- Node.js / JS Ecosystem ---
        TargetSpec {
            path: if is_mac {
                home.join(".npm/_cacache")
            } else {
                local_app.join("npm-cache")
            },
            name: "NPM Global Cache",
            category: "Node.js / JS",
            is_safe: true,
            clean_cmd_win: "npm cache clean --force",
            clean_cmd_mac: "npm cache clean --force",
            impact: "Xóa cache các gói npm đã tải tạm thời. Dự án không bị ảnh hưởng; lần npm install tiếp theo sẽ tải lại.",
        },
        TargetSpec {
            path: if is_mac {
                home.join("Library/pnpm/store")
            } else {
                local_app.join("pnpm/store")
            },
            name: "PNPM Content-Addressable Store",
            category: "Node.js / JS",
            is_safe: true,
            clean_cmd_win: "pnpm store prune",
            clean_cmd_mac: "pnpm store prune",
            impact: "Dọn dẹp các gói không còn được tham chiếu bởi bất kỳ dự án nào trong PNPM store.",
        },
        TargetSpec {
            path: if is_mac {
                local_app.join("Yarn")
            } else {
                local_app.join("Yarn/Cache")
            },
            name: "Yarn Global Cache",
            category: "Node.js / JS",
            is_safe: true,
            clean_cmd_win: "yarn cache clean",
            clean_cmd_mac: "yarn cache clean",
            impact: "Xóa bộ nhớ đệm các package đã tải qua Yarn.",
        },
        TargetSpec {
            path: home.join(".bun/install/cache"),
            name: "Bun Package Cache",
            category: "Node.js / JS",
            is_safe: true,
            clean_cmd_win: "bun pm cache rm",
            clean_cmd_mac: "bun pm cache rm",
            impact: "Xóa cache các package đã tải của Bun runtime.",
        },
        // --- Python / AI / ML ---
        TargetSpec {
            path: if is_mac {
                local_app.join("pip")
            } else {
                local_app.join("pip/cache")
            },
            name: "Python Pip Cache",
            category: "Python / AI",
            is_safe: true,
            clean_cmd_win: "pip cache purge",
            clean_cmd_mac: "pip cache purge",
            impact: "Xóa các file wheel (.whl) và source archive mà pip đã lưu tạm khi cài thư viện Python.",
        },
        TargetSpec {
            path: if is_mac {
                local_app.join("uv")
            } else {
                local_app.join("uv/cache")
            },
            name: "Astral uv Package Cache",
            category: "Python / AI",
            is_safe: true,
            clean_cmd_win: "uv cache clean",
            clean_cmd_mac: "uv cache clean",
            impact: "Xóa cache các gói Python và môi trường ảo tạm của uv.",
        },
        TargetSpec {
            path: home.join(".cache/huggingface"),
            name: "HuggingFace Models & Datasets Cache",
            category: "Python / AI",
            is_safe: false,
            clean_cmd_win: "huggingface-cli delete-cache",
            clean_cmd_mac: "huggingface-cli delete-cache",
            impact: "Xóa các trọng số mô hình AI (LLM/Vision) và dataset đã tải về từ HuggingFace Hub.",
        },
        TargetSpec {
            path: home.join(".ollama/models"),
            name: "Ollama Local LLM Models",
            category: "Python / AI",
            is_safe: false,
            clean_cmd_win: "ollama list; # ollama rm <model>",
            clean_cmd_mac: "ollama list # ollama rm <model>",
            impact: "Xóa các mô hình ngôn ngữ lớn chạy cục bộ qua Ollama. Sẽ phải pull lại nhiều GB nếu cần dùng.",
        },
        TargetSpec {
            path: home.join(".conda/pkgs"),
            name: "Conda Package Tarballs & Cache",
            category: "Python / AI",
            is_safe: true,
            clean_cmd_win: "conda clean --all -y",
            clean_cmd_mac: "conda clean --all -y",
            impact: "Xóa các gói cài đặt và tarball không còn sử dụng của Anaconda/Miniconda.",
        },
        // --- Rust / Go / .NET / Java / Ruby / PHP ---
        TargetSpec {
            path: home.join(".cargo/registry"),
            name: "Rust Cargo Registry & Crates Cache",
            category: "Rust / Go / .NET",
            is_safe: true,
            clean_cmd_win: "Remove-Item -Recurse -Force \"$HOME\\.cargo\\registry\\cache\\*\", \"$HOME\\.cargo\\registry\\src\\*\"",
            clean_cmd_mac: "rm -rf ~/.cargo/registry/cache/* ~/.cargo/registry/src/*",
            impact: "Xóa mã nguồn và file nén các crate Rust đã tải về. Cargo sẽ tự tải lại khi build.",
        },
        TargetSpec {
            path: home.join(".rustup/toolchains"),
            name: "Rustup Installed Toolchains",
            category: "Rust / Go / .NET",
            is_safe: false,
            clean_cmd_win: "rustup toolchain list",
            clean_cmd_mac: "rustup toolchain list",
            impact: "Chứa trình biên dịch Rust (stable/nightly). Chỉ nên gỡ các toolchain cũ không còn dùng.",
        },
        TargetSpec {
            path: local_app.join("go-build"),
            name: "Go Build Artifact Cache",
            category: "Rust / Go / .NET",
            is_safe: true,
            clean_cmd_win: "go clean -cache",
            clean_cmd_mac: "go clean -cache",
            impact: "Xóa cache biên dịch tạm của Go. Lần go build tiếp theo sẽ biên dịch lại.",
        },
        TargetSpec {
            path: home.join("go/pkg/mod/cache"),
            name: "Go Module Download Cache",
            category: "Rust / Go / .NET",
            is_safe: true,
            clean_cmd_win: "go clean -modcache",
            clean_cmd_mac: "go clean -modcache",
            impact: "Xóa cache các Go modules đã tải về.",
        },
        TargetSpec {
            path: home.join(".nuget/packages"),
            name: ".NET NuGet Global Packages Cache",
            category: "Rust / Go / .NET",
            is_safe: true,
            clean_cmd_win: "dotnet nuget locals all --clear",
            clean_cmd_mac: "dotnet nuget locals all --clear",
            impact: "Xóa toàn bộ các gói thư viện .NET NuGet đã tải về máy. Khi build project C#/.NET sẽ tự restore lại.",
        },
        TargetSpec {
            path: home.join(".jdks"),
            name: "Downloaded Java JDKs",
            category: "Runtimes / SDK",
            is_safe: false,
            clean_cmd_win: "Remove-Item -Recurse -Force \"$HOME\\.jdks\"",
            clean_cmd_mac: "rm -rf ~/.jdks/*",
            impact: "Xóa các bộ cài OpenJDK đã tải qua IDE. Dự án cần JDK đó sẽ phải chỉ định lại đường dẫn.",
        },
        TargetSpec {
            path: home.join(".m2/repository"),
            name: "Maven Local Repository Cache",
            category: "Java / Maven",
            is_safe: true,
            clean_cmd_win: "Remove-Item -Recurse -Force \"$HOME\\.m2\\repository\"",
            clean_cmd_mac: "rm -rf ~/.m2/repository",
            impact: "Xóa các thư viện JAR đã tải về. Khi build Maven/Gradle, hệ thống sẽ tự tải lại từ kho lưu trữ.",
        },
        TargetSpec {
            path: home.join(".bundle/cache"),
            name: "Ruby Bundler Cache",
            category: "Ruby",
            is_safe: true,
            clean_cmd_win: "bundle clean --force",
            clean_cmd_mac: "bundle clean --force",
            impact: "Xóa các gem cũ không còn dùng trong Gemfile. Không ảnh hưởng đến các gem đang sử dụng.",
        },
        // --- Headless Browsers & E2E Testing ---
        TargetSpec {
            path: local_app.join("ms-playwright"),
            name: "Playwright Headless Browsers",
            category: "E2E / Testing",
            is_safe: true,
            clean_cmd_win: "npx playwright uninstall --all",
            clean_cmd_mac: "npx playwright uninstall --all",
            impact: "Xóa các trình duyệt phục vụ test tự động Playwright (~500MB - 2GB). Chạy npx playwright install để tải lại.",
        },
        TargetSpec {
            path: home.join(".cache/puppeteer"),
            name: "Puppeteer Browser Binaries Cache",
            category: "E2E / Testing",
            is_safe: true,
            clean_cmd_win: "npx puppeteer browsers clear",
            clean_cmd_mac: "npx puppeteer browsers clear",
            impact: "Xóa các bản Chromium tải về bởi Puppeteer.",
        },
        TargetSpec {
            path: if is_mac {
                local_app.join("Cypress")
            } else {
                local_app.join("Cypress/Cache")
            },
            name: "Cypress Binary Cache",
            category: "E2E / Testing",
            is_safe: true,
            clean_cmd_win: "npx cypress cache clear",
            clean_cmd_mac: "npx cypress cache clear",
            impact: "Xóa các phiên bản Cypress binary cũ đã lưu trong máy.",
        },
        // --- Docker, IDEs & Agent Sessions ---
        TargetSpec {
            path: if is_mac {
                home.join("Library/Containers/com.docker.docker")
            } else {
                local_app.join("Docker")
            },
            name: "Docker Desktop & VM Data",
            category: "Docker",
            is_safe: false,
            clean_cmd_win: "docker system prune -a --volumes",
            clean_cmd_mac: "docker system prune -a --volumes",
            impact: "XÓA TOÀN BỘ images, containers không chạy và volumes của Docker. Bạn sẽ phải pull/build lại images từ đầu.",
        },
        TargetSpec {
            path: local_app.join("JetBrains"),
            name: "JetBrains IDEs Caches & Indexes",
            category: "IDE Data",
            is_safe: false,
            clean_cmd_win: "Mở JetBrains IDE -> File -> Invalidate Caches",
            clean_cmd_mac: "rm -rf ~/Library/Caches/JetBrains/*",
            impact: "Xóa bộ chỉ mục mã nguồn (indexes) và cache của Android Studio / IntelliJ IDEA.",
        },
        TargetSpec {
            path: home.join(".vscode/extensions"),
            name: "VS Code Active Extensions",
            category: "IDE Extensions",
            is_safe: false,
            clean_cmd_win: "code --uninstall-extension <id>",
            clean_cmd_mac: "code --uninstall-extension <id>",
            impact: "Xóa các tiện ích mở rộng đã cài trên VS Code. Sẽ phải cài đặt lại.",
        },
        TargetSpec {
            path: home.join(".antigravity-ide/extensions"),
            name: "Antigravity IDE Active Extensions",
            category: "IDE Extensions",
            is_safe: false,
            clean_cmd_win: "Gỡ extension qua giao diện IDE Extensions",
            clean_cmd_mac: "Gỡ extension qua giao diện IDE Extensions",
            impact: "Xóa các tiện ích mở rộng đang hoạt động của IDE (Flutter, Python, Go...). Sẽ phải cài lại.",
        },
        TargetSpec {
            path: home.join(".cache"),
            name: "User Tools Cache (Firebase, CLI Tools)",
            category: "Cache",
            is_safe: true,
            clean_cmd_win: "Remove-Item -Recurse -Force \"$HOME\\.cache\\*\" -ErrorAction SilentlyContinue",
            clean_cmd_mac: "rm -rf ~/.cache/*",
            impact: "Xóa cache staging của các công cụ CLI (Firebase, DevTools...). Sẽ tự tạo lại khi dùng.",
        },
        TargetSpec {
            path: home.join(".gemini/antigravity-backup"),
            name: "Antigravity Migration Backup",
            category: "Antigravity",
            is_safe: true,
            clean_cmd_win: "Remove-Item -Recurse -Force \"$HOME\\.gemini\\antigravity-backup\"",
            clean_cmd_mac: "rm -rf ~/.gemini/antigravity-backup",
            impact: "Bản sao lưu cũ từ đợt migration. Hiện tại không còn sử dụng.",
        },
        TargetSpec {
            path: home.join(".gemini/antigravity/conversations"),
            name: "Antigravity Agent Sessions (CLI / Core)",
            category: "Sessions",
            is_safe: false,
            clean_cmd_win: "Remove-Item -Recurse -Force \"$HOME\\.gemini\\antigravity\\conversations\\*\"",
            clean_cmd_mac: "rm -rf ~/.gemini/antigravity/conversations/*",
            impact: "MẤT TOÀN BỘ lịch sử các cuộc hội thoại và ngữ cảnh trước đây với Antigravity Agent.",
        },
        TargetSpec {
            path: home.join(".gemini/antigravity-ide/conversations"),
            name: "Antigravity IDE Sessions (GUI Chat)",
            category: "Sessions",
            is_safe: false,
            clean_cmd_win: "Remove-Item -Recurse -Force \"$HOME\\.gemini\\antigravity-ide\\conversations\\*\"",
            clean_cmd_mac: "rm -rf ~/.gemini/antigravity-ide/conversations/*",
            impact: "Mất lịch sử các phiên chat bên trong giao diện Antigravity IDE.",
        },
        TargetSpec {
            path: home.join(".gemini/antigravity/brain"),
            name: "Antigravity Agent Brain & Logs",
            category: "Sessions",
            is_safe: false,
            clean_cmd_win: "Remove-Item -Recurse -Force \"$HOME\\.gemini\\antigravity\\brain\\*\"",
            clean_cmd_mac: "rm -rf ~/.gemini/antigravity/brain/*",
            impact: "Xóa toàn bộ logs các tác vụ nền, subagents và artifacts của Agent.",
        },
        TargetSpec {
            path: home.join(".gemini/antigravity-ide/brain"),
            name: "Antigravity IDE Brain & Task Logs",
            category: "Sessions",
            is_safe: false,
            clean_cmd_win: "Remove-Item -Recurse -Force \"$HOME\\.gemini\\antigravity-ide\\brain\\*\"",
            clean_cmd_mac: "rm -rf ~/.gemini/antigravity-ide/brain/*",
            impact: "Xóa dữ liệu tác vụ nền và lịch sử task của IDE.",
        },
    ];

    // Bo sung cac muc dac thu theo tung he dieu hanh (Windows vs macOS)
    if is_mac {
        specs.extend(vec![
            TargetSpec {
                path: home.join("Library/Developer/Xcode/DerivedData"),
                name: "Xcode DerivedData (Build Intermediates & Indexes)",
                category: "macOS / Xcode",
                is_safe: true,
                clean_cmd_win: "",
                clean_cmd_mac: "rm -rf ~/Library/Developer/Xcode/DerivedData/*",
                impact: "Xóa toàn bộ cache biên dịch trung gian của Xcode. Rất an toàn, Xcode sẽ tự build lại khi mở dự án iOS/macOS.",
            },
            TargetSpec {
                path: home.join("Library/Developer/Xcode/iOS DeviceSupport"),
                name: "Xcode iOS DeviceSupport Symbols",
                category: "macOS / Xcode",
                is_safe: true,
                clean_cmd_win: "",
                clean_cmd_mac: "rm -rf ~/Library/Developer/Xcode/iOS\\ DeviceSupport/*",
                impact: "Xóa debug symbols của các phiên bản iOS cũ khi cắm iPhone thật vào debug.",
            },
            TargetSpec {
                path: home.join("Library/Developer/CoreSimulator/Devices"),
                name: "iOS Simulator Devices & Runtimes",
                category: "macOS / Xcode",
                is_safe: false,
                clean_cmd_win: "",
                clean_cmd_mac: "xcrun simctl delete unavailable",
                impact: "Dọn dẹp các máy ảo iOS Simulator không còn tương thích với phiên bản Xcode hiện tại.",
            },
            TargetSpec {
                path: home.join("Library/Caches/CocoaPods"),
                name: "CocoaPods Specs & Pods Cache",
                category: "macOS / Xcode",
                is_safe: true,
                clean_cmd_win: "",
                clean_cmd_mac: "pod cache clean --all",
                impact: "Xóa cache các thư viện iOS CocoaPods đã tải về. Chạy pod install sẽ tự tải lại.",
            },
            TargetSpec {
                path: home.join("Library/Caches/Homebrew"),
                name: "Homebrew Formula & Cask Download Cache",
                category: "Package Manager",
                is_safe: true,
                clean_cmd_win: "",
                clean_cmd_mac: "brew cleanup -s",
                impact: "Xóa các file .tar.gz / .dmg đã tải về của Homebrew sau khi cài đặt.",
            },
            TargetSpec {
                path: home.join("Library/Logs/DiagnosticReports"),
                name: "macOS Application Crash & Diagnostic Reports",
                category: "System / Build Temp",
                is_safe: true,
                clean_cmd_win: "",
                clean_cmd_mac: "rm -rf ~/Library/Logs/DiagnosticReports/*",
                impact: "Xóa các file crash report (.ips / .crash) sinh ra khi ứng dụng hoặc IDE bị crash trên macOS.",
            },
        ]);
    } else {
        specs.extend(vec![
            TargetSpec {
                path: home.join("scoop/cache"),
                name: "Scoop Package Cache",
                category: "Package Manager",
                is_safe: true,
                clean_cmd_win: "scoop cache rm *",
                clean_cmd_mac: "",
                impact: "Xóa các bộ cài đặt (.zip, .exe) đã tải về sau khi cài ứng dụng qua Scoop.",
            },
            TargetSpec {
                path: local_app.join("Temp"),
                name: "Windows Temp (Dev / Build Temp)",
                category: "System / Build Temp",
                is_safe: true,
                clean_cmd_win: "Remove-Item -Path \"$env:LOCALAPPDATA\\Temp\\*\" -Recurse -Force -ErrorAction SilentlyContinue",
                clean_cmd_mac: "",
                impact: "Xóa các file tạm do trình biên dịch, IDE và hệ thống tạo ra. Các file đang mở sẽ được tự động bỏ qua an toàn.",
            },
            TargetSpec {
                path: local_app.join("CrashDumps"),
                name: "Windows Application Crash Dumps (.dmp)",
                category: "System / Build Temp",
                is_safe: true,
                clean_cmd_win: "Remove-Item -Path \"$env:LOCALAPPDATA\\CrashDumps\\*\" -Recurse -Force -ErrorAction SilentlyContinue",
                clean_cmd_mac: "",
                impact: "Xóa các file memory dump sinh ra khi ứng dụng hoặc IDE bị crash.",
            },
        ]);

        // Bo sung quet moi truong WSL2 (Ubuntu/Debian...) tren may Windows/WSL
        let mut wsl_homes: Vec<PathBuf> = Vec::new();
        if cfg!(target_os = "linux") {
            wsl_homes.push(home.clone());
        } else {
            // Tu Windows quet sang \\wsl.localhost\<Distro>\home\<user>
            for distro in ["Ubuntu", "Ubuntu-22.04", "Ubuntu-24.04", "Debian"] {
                let distro_home = PathBuf::from(format!(r"\\wsl.localhost\{}\home", distro));
                if let Ok(entries) = fs::read_dir(&distro_home) {
                    for e in entries.flatten() {
                        if e.path().is_dir() {
                            wsl_homes.push(e.path());
                        }
                    }
                }
            }
        }

        for wh in wsl_homes {
            specs.extend(vec![
                TargetSpec {
                    path: wh.join(".npm"),
                    name: "[WSL2] NPM Global Cache (~/.npm)",
                    category: "WSL2 / Linux",
                    is_safe: true,
                    clean_cmd_win: "wsl -e bash -c \"npm cache clean --force || rm -rf ~/.npm/_cacache\"",
                    clean_cmd_mac: "rm -rf ~/.npm/_cacache",
                    impact: "Xóa cache các gói npm bên trong môi trường WSL2 Linux. Không ảnh hưởng tới project.",
                },
                TargetSpec {
                    path: wh.join(".antigravity-server"),
                    name: "[WSL2] Antigravity Remote Server (~/.antigravity-server)",
                    category: "WSL2 / Linux",
                    is_safe: false,
                    clean_cmd_win: "wsl -e bash -c \"rm -rf ~/.antigravity-server/bin/*\"",
                    clean_cmd_mac: "rm -rf ~/.antigravity-server/bin/*",
                    impact: "Chứa nhân Antigravity Server chạy trong WSL2. Chỉ xóa khi muốn cài lại server mới.",
                },
                TargetSpec {
                    path: wh.join(".vscode-server"),
                    name: "[WSL2] VS Code Remote WSL Server (~/.vscode-server)",
                    category: "WSL2 / Linux",
                    is_safe: false,
                    clean_cmd_win: "wsl -e bash -c \"rm -rf ~/.vscode-server/bin/*\"",
                    clean_cmd_mac: "rm -rf ~/.vscode-server/bin/*",
                    impact: "Chứa VS Code Server và extensions cài trong WSL2.",
                },
                TargetSpec {
                    path: wh.join(".cache"),
                    name: "[WSL2] Linux Dev & CLI Cache (~/.cache: claude, copilot, pip, gh)",
                    category: "WSL2 / Linux",
                    is_safe: true,
                    clean_cmd_win: "wsl -e bash -c \"rm -rf ~/.cache/*\"",
                    clean_cmd_mac: "rm -rf ~/.cache/*",
                    impact: "Xóa bộ nhớ đệm các công cụ CLI bên trong WSL2 (Claude CLI, GitHub Copilot, pip, gh...). Tự tạo lại khi chạy.",
                },
                TargetSpec {
                    path: wh.join(".gemini"),
                    name: "[WSL2] Antigravity Agent Brain & Sessions (~/.gemini)",
                    category: "WSL2 / Linux",
                    is_safe: false,
                    clean_cmd_win: "wsl -e bash -c \"rm -rf ~/.gemini/antigravity/brain/*\"",
                    clean_cmd_mac: "rm -rf ~/.gemini/antigravity/brain/*",
                    impact: "Chứa dữ liệu phiên làm việc và logs của Antigravity bên trong WSL2.",
                },
                TargetSpec {
                    path: wh.join(".cargo/registry"),
                    name: "[WSL2] Rust Cargo Registry (~/.cargo/registry)",
                    category: "WSL2 / Linux",
                    is_safe: true,
                    clean_cmd_win: "wsl -e bash -c \"rm -rf ~/.cargo/registry/cache/* ~/.cargo/registry/src/*\"",
                    clean_cmd_mac: "rm -rf ~/.cargo/registry/cache/* ~/.cargo/registry/src/*",
                    impact: "Xóa cache crates của Rust bên trong WSL2.",
                },
            ]);
        }
    }

    specs
}

/// Quet song song (Multi-threaded) tat ca Dev Caches & SDKs
pub fn scan_dev_caches(
    previous_map: &HashMap<String, f64>,
    scan_time: &str,
) -> Vec<CacheItem> {
    let specs = build_dev_targets();
    let is_mac = cfg!(target_os = "macos");

    let mut items: Vec<CacheItem> = specs
        .into_par_iter()
        .filter_map(|spec| {
            let (exists, file_count, size_bytes) = compute_folder_stats(&spec.path);
            if !exists || size_bytes == 0 {
                return None;
            }
            let path_str = spec.path.to_string_lossy().to_string();
            let size_mb = round2(size_bytes as f64 / 1_048_576.0);
            let size_gb = round2(size_bytes as f64 / 1_073_741_824.0);
            let prev_mb = previous_map.get(&path_str).copied().unwrap_or(size_mb);
            let delta_mb = round2(size_mb - prev_mb);
            let increased = delta_mb > 0.05;

            Some(CacheItem {
                path: path_str,
                name: spec.name.to_string(),
                category: spec.category.to_string(),
                group: if spec.is_safe {
                    GROUP_SAFE.to_string()
                } else {
                    GROUP_REVIEW.to_string()
                },
                file_count,
                size_bytes,
                size_m_b: size_mb,
                size_g_b: size_gb,
                previous_size_m_b: prev_mb,
                delta_m_b: delta_mb,
                increased,
                clean_cmd: if is_mac {
                    spec.clean_cmd_mac.to_string()
                } else {
                    spec.clean_cmd_win.to_string()
                },
                impact: spec.impact.to_string(),
                scan_time: scan_time.to_string(),
            })
        })
        .collect();

    items.sort_by(|a, b| b.size_bytes.cmp(&a.size_bytes));
    items
}

/// Quet song song Project Build Artifacts (node_modules, target, build, .dart_tool, .next, .venv)
pub fn scan_project_artifacts(scan_time: &str, stale_days: u64, min_mb: f64) -> Vec<ArtifactItem> {
    let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("."));
    let is_mac = cfg!(target_os = "macos");

    let mut roots = vec![
        home.join("source/repos"),
        home.join("Projects"),
        home.join("Workspace"),
        home.join("Code"),
        home.join("dev"),
        home.join("Developer"),
        home.join("StudioProjects"),
        home.join("IdeaProjects"),
        home.join("Documents/GitHub"),
    ];

    let excluded: HashSet<&str> = [
        "AppData", "Library", "Pictures", "Photos", "Music", "Videos", "Movies",
        "Downloads", "OneDrive", "Contacts", "Favorites", "Links", "Saved Games",
        "Searches", "Public", "Applications", "scoop", "disk-report",
    ]
    .into_iter()
    .collect();

    if let Ok(entries) = fs::read_dir(&home) {
        for entry in entries.flatten() {
            let path = entry.path();
            if !path.is_dir() {
                continue;
            }
            let name = entry.file_name().to_string_lossy().to_string();
            if name.starts_with('.') || excluded.contains(name.as_str()) {
                continue;
            }
            let is_project = path.join(".git").exists()
                || path.join("package.json").exists()
                || path.join("pubspec.yaml").exists()
                || path.join("Cargo.toml").exists()
                || path.join("pyproject.toml").exists();
            if is_project && !roots.contains(&path) {
                roots.push(path);
            }
        }
    }

    let artifact_types: HashMap<&str, (&str, &str)> = [
        (
            "node_modules",
            (
                "Node.js / JS",
                "Thư mục dependencies của dự án JS/TS. Có thể khôi phục bằng npm/pnpm/yarn install.",
            ),
        ),
        (
            ".next",
            (
                "Next.js Build",
                "Cache build của Next.js. Tự động tạo lại khi chạy next dev hoặc next build.",
            ),
        ),
        (
            ".nuxt",
            (
                "Nuxt Build",
                "Cache build của Nuxt. Tự tạo lại khi chạy dev/build.",
            ),
        ),
        (
            "target",
            (
                "Rust / Maven",
                "Thư mục biên dịch của Cargo (Rust) hoặc Maven (Java). Tự tạo lại khi cargo build / mvn package.",
            ),
        ),
        (
            ".dart_tool",
            (
                "Dart / Flutter",
                "Cache biên dịch và codegen của Dart/Flutter. Tự tạo lại khi chạy flutter pub get.",
            ),
        ),
        (
            "build",
            (
                "Mobile / Gradle",
                "Thư mục chứa file APK/AAB/binaries trung gian khi build dự án.",
            ),
        ),
        (
            ".gradle",
            (
                "Java / Android / Gradle",
                "Cache Gradle cục bộ bên trong thư mục dự án.",
            ),
        ),
        (
            ".venv",
            (
                "Python / AI",
                "Môi trường ảo Python cục bộ của dự án. Có thể tạo lại từ requirements.txt / pyproject.toml.",
            ),
        ),
        (
            "venv",
            (
                "Python / AI",
                "Môi trường ảo Python cục bộ của dự án. Có thể tạo lại từ requirements.txt / pyproject.toml.",
            ),
        ),
    ]
    .into_iter()
    .collect();

    let mut candidate_dirs: Vec<PathBuf> = Vec::new();
    let mut visited = HashSet::new();

    for root in roots {
        if !root.exists() {
            continue;
        }
        let mut it = WalkDir::new(&root).max_depth(4).follow_links(false).into_iter();
        while let Some(Ok(entry)) = it.next() {
            if !entry.file_type().is_dir() {
                continue;
            }
            let dir_name = entry.file_name().to_string_lossy();
            if artifact_types.contains_key(dir_name.as_ref()) {
                let full_path = entry.path().to_path_buf();
                if visited.insert(full_path.clone()) {
                    candidate_dirs.push(full_path);
                }
                // Khong di sau vao ben trong node_modules / target / build da tim thay
                it.skip_current_dir();
            }
        }
    }

    let now = SystemTime::now();
    let mut results: Vec<ArtifactItem> = candidate_dirs
        .into_par_iter()
        .filter_map(|dir_path| {
            let dir_name = dir_path.file_name()?.to_string_lossy().to_string();
            let (category, base_impact) = artifact_types.get(dir_name.as_str())?;

            let (exists, file_count, size_bytes) = compute_folder_stats(&dir_path);
            if !exists {
                return None;
            }
            let size_mb = round2(size_bytes as f64 / 1_048_576.0);
            if size_mb < min_mb {
                return None;
            }

            let parent = dir_path.parent().unwrap_or(&dir_path);
            let project_name = parent
                .file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_else(|| dir_name.clone());

            let modified_sys = fs::metadata(parent)
                .and_then(|m| m.modified())
                .unwrap_or(now);
            let days_idle = now
                .duration_since(modified_sys)
                .map(|d| d.as_secs() / 86400)
                .unwrap_or(0);
            let is_stale = days_idle >= stale_days;

            let dt: DateTime<Local> = modified_sys.into();
            let last_modified = dt.format("%Y-%m-%d").to_string();
            let path_str = dir_path.to_string_lossy().to_string();

            let clean_cmd = if is_mac {
                format!("rm -rf \"{}\"", path_str)
            } else {
                format!("Remove-Item -LiteralPath \"{}\" -Recurse -Force", path_str)
            };

            Some(ArtifactItem {
                path: path_str,
                name: format!("{} ({})", project_name, dir_name),
                project_name,
                artifact_type: dir_name,
                category: (*category).to_string(),
                group: if is_stale {
                    GROUP_SAFE.to_string()
                } else {
                    GROUP_REVIEW.to_string()
                },
                file_count,
                size_bytes,
                size_m_b: size_mb,
                size_g_b: round2(size_bytes as f64 / 1_073_741_824.0),
                days_idle,
                is_stale,
                last_modified,
                clean_cmd,
                impact: format!(
                    "{} (Cập nhật lần cuối: {} ngày trước).",
                    base_impact, days_idle
                ),
                scan_time: scan_time.to_string(),
            })
        })
        .collect();

    results.sort_by(|a, b| b.size_bytes.cmp(&a.size_bytes));
    results
}

/// Quet Dead PATH va Bien moi truong Dev bi hong tren Windows & macOS
pub fn scan_env_issues() -> Vec<EnvIssue> {
    let mut issues = Vec::new();
    let is_mac = cfg!(target_os = "macos");
    let sep = if cfg!(windows) { ';' } else { ':' };

    if let Ok(raw_path) = env::var("PATH") {
        let mut seen = HashSet::new();
        for (idx, raw_entry) in raw_path.split(sep).enumerate() {
            let trimmed = raw_entry.trim().trim_matches('"');
            if trimmed.is_empty() {
                continue;
            }
            let norm = if cfg!(windows) {
                trimmed.to_lowercase().trim_end_matches('\\').to_string()
            } else {
                trimmed.trim_end_matches('/').to_string()
            };

            if !seen.insert(norm) {
                issues.push(EnvIssue {
                    id: format!("PATH-DUP-{}", idx),
                    issue_type: "Duplicate PATH".to_string(),
                    scope: "Current Env".to_string(),
                    var_name: "PATH".to_string(),
                    target_value: trimmed.to_string(),
                    status: "Trùng lặp đường dẫn".to_string(),
                    group: GROUP_SAFE.to_string(),
                    impact: format!(
                        "Đường dẫn '{}' bị khai báo lặp lại nhiều lần trong biến PATH.",
                        trimmed
                    ),
                    clean_cmd: if is_mac {
                        format!("# Gỡ bản trùng '{}' trong ~/.zshrc hoặc ~/.bash_profile", trimmed)
                    } else {
                        format!("# Xóa bản trùng '{}' trong User/System PATH", trimmed)
                    },
                });
                continue;
            }

            if !Path::new(trimmed).exists() {
                let clean_cmd = if is_mac {
                    format!(
                        "# Kiểm tra và xóa dòng chứa '{}' trong ~/.zshrc hoặc /etc/paths.d",
                        trimmed
                    )
                } else {
                    format!(
                        "$p = [Environment]::GetEnvironmentVariable('Path', 'User'); $newP = ($p -split ';' | Where-Object {{ $_.Trim().Trim('\"') -ne '{}' }}) -join ';'; [Environment]::SetEnvironmentVariable('Path', $newP, 'User')",
                        trimmed
                    )
                };

                issues.push(EnvIssue {
                    id: format!("PATH-DEAD-{}", idx),
                    issue_type: "Dead PATH".to_string(),
                    scope: "User / System".to_string(),
                    var_name: "PATH".to_string(),
                    target_value: trimmed.to_string(),
                    status: "Thư mục không tồn tại".to_string(),
                    group: GROUP_SAFE.to_string(),
                    impact: format!(
                        "Đường dẫn '{}' trong PATH trỏ tới thư mục đã bị xóa (thường do gỡ SDK/IDE cũ).",
                        trimmed
                    ),
                    clean_cmd,
                });
            }
        }
    }

    let dev_vars = [
        "JAVA_HOME",
        "ANDROID_HOME",
        "ANDROID_SDK_ROOT",
        "ANDROID_AVD_HOME",
        "FLUTTER_ROOT",
        "PUB_CACHE",
        "GRADLE_USER_HOME",
        "MAVEN_HOME",
        "GOPATH",
        "GOROOT",
        "CARGO_HOME",
        "RUSTUP_HOME",
        "NVM_HOME",
        "NVM_DIR",
        "PNPM_HOME",
        "BUN_INSTALL",
        "PYENV_ROOT",
        "CONDA_PREFIX",
    ];

    for var_name in dev_vars {
        if let Ok(val) = env::var(var_name) {
            let trimmed = val.trim().trim_matches('"');
            if !trimmed.is_empty() && !Path::new(trimmed).exists() {
                let clean_cmd = if is_mac {
                    format!("unset {} # Và xóa export {} trong ~/.zshrc", var_name, var_name)
                } else {
                    format!("[Environment]::SetEnvironmentVariable('{}', $null, 'User')", var_name)
                };

                issues.push(EnvIssue {
                    id: format!("ENV-DEAD-{}", var_name),
                    issue_type: "Broken Dev Variable".to_string(),
                    scope: "User".to_string(),
                    var_name: var_name.to_string(),
                    target_value: trimmed.to_string(),
                    status: "Trỏ tới đường dẫn đã xóa".to_string(),
                    group: GROUP_SAFE.to_string(),
                    impact: format!(
                        "Biến môi trường '{}' đang trỏ tới '{}' không còn tồn tại.",
                        var_name, trimmed
                    ),
                    clean_cmd,
                });
            }
        }
    }

    issues
}

pub fn run_full_scan(previous_map: &HashMap<String, f64>) -> ScanPayload {
    let start = Instant::now();
    let scan_time = Local::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let platform = if cfg!(target_os = "macos") {
        "macOS".to_string()
    } else if cfg!(windows) {
        "Windows".to_string()
    } else {
        std::env::consts::OS.to_string()
    };

    let (caches, artifacts) = rayon::join(
        || scan_dev_caches(previous_map, &scan_time),
        || scan_project_artifacts(&scan_time, 30, 5.0),
    );
    let env_issues = scan_env_issues();
    let duration_ms = start.elapsed().as_millis() as u64;

    ScanPayload {
        scan_time,
        platform,
        scan_duration_ms: duration_ms,
        caches,
        artifacts,
        env_issues,
    }
}
