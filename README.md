# 🚀 DevDiskReport — Bản đồ Dung lượng & Môi trường Dev (Windows / macOS / WSL2)

[![Build Windows & macOS Desktop App](https://github.com/chinchindev/disk-report/actions/workflows/build-release.yml/badge.svg)](https://github.com/chinchindev/disk-report/actions/workflows/build-release.yml)

Công cụ phân tích chuyên sâu **Dev Caches**, **Project Build Artifacts** (`node_modules`, `target`, `build`, `.dart_tool`, `.next`, `.venv`) và **Dead `PATH` / Biến môi trường Dev** dành cho lập trình viên trên **Windows**, **macOS** và **WSL2**, được xây dựng bằng **Rust (Rayon + WalkDir)** và **Tauri v2**.

---

## ✨ Tính năng nổi bật

- **⚡ Quét đa luồng siêu tốc (Rust + Rayon)**: Quét song song hơn 35+ mục Dev Caches (`Android SDK`, `AVD`, `Gradle`, `NPM`, `PNPM`, `Yarn`, `Bun`, `Pip`, `uv`, `HuggingFace`, `Ollama`, `Cargo`, `Rustup`, `Go`, `NuGet`, `Playwright`, `Docker`, `Xcode DerivedData`, `CocoaPods`, `Homebrew`...) và môi trường **WSL2 (`/home/<user>`)**.
- **🏗️ Phát hiện Project Build Artifacts**: Tự động tìm `node_modules`, `target`, `build`, `.gradle`, `.dart_tool`, `.next`, `.nuxt`, `.venv` và đánh dấu các dự án cũ không hoạt động (`> 30 ngày`).
- **🔗 Kiểm tra Dead `PATH` & Biến môi trường bị hỏng**: Phát hiện đường dẫn mồ côi đã bị xóa hoặc trùng lặp trong `PATH` (`User` & `System`) và các biến `JAVA_HOME`, `ANDROID_HOME`, `FLUTTER_ROOT`, `GOPATH`, `NVM_SYMLINK`...
- **🗺️ Bản đồ nhiệt Treemap cân bằng & PowerShell / Bash Cleanup Studio**:
  - Chế độ hiển thị **Cân bằng (`Sqrt`)** và **Tỷ lệ tuyệt đối (`Linear`)**.
  - Tự động sinh script dọn dẹp an toàn cho cả **Windows (`.ps1`)** và **macOS / Linux (`.sh`)**, kèm chế độ chạy thử `-WhatIf` (Dry-run), tự dừng `gradle`/`adb` daemon và sao lưu biến `PATH` trước khi sửa.

---

## 📦 Tải bản cài đặt dựng sẵn từ GitHub Actions / Releases

Mỗi khi push code lên nhánh `main`, **GitHub Actions** ([`.github/workflows/build-release.yml`](.github/workflows/build-release.yml)) sẽ tự động biên dịch trên máy chủ đám mây của GitHub (không cần cài Visual Studio C++ Build Tools trên máy cá nhân) và xuất ra:

1. **Windows (`x64`)**:
   - `DevDiskReport-Portable-win-x64.exe` (Chạy trực tiếp không cần cài đặt)
   - `DevDiskReport_2.0.0_x64-setup.exe` & `.msi` (Bộ cài đặt chuẩn Windows)
2. **macOS (`Apple Silicon ARM64`)**:
   - `DevDiskReport_2.0.0_aarch64.dmg` & `DevDiskReport.app`

👉 Vào mục **[Actions](https://github.com/chinchindev/disk-report/actions)** hoặc **[Releases](https://github.com/chinchindev/disk-report/releases)** trên GitHub để tải về trực tiếp.

---

## 🛠️ Chạy nhanh tại máy (Local)

### 1. Từ môi trường WSL2 (Quét Hybrid cả WSL2 + Windows):
```bash
./run-wsl.sh
```

### 2. Từ Windows PowerShell (Không cần cài Rust):
```powershell
powershell -ExecutionPolicy Bypass -File "$HOME\disk-report\scan.ps1"
```

### 3. Build Tauri v2 Desktop App tại máy:
- **Windows**: `powershell -ExecutionPolicy Bypass -File "$HOME\disk-report\build-app.ps1"`
- **macOS**: `./build-app.sh`
