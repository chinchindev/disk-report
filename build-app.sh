#!/usr/bin/env bash
# =========================================================================
# DEV DISK REPORT - TAURI v2 DESKTOP APP BUILDER (macOS)
# Cách dùng:
#   ./build-app.sh --dev   (Chạy cửa sổ App trực tiếp)
#   ./build-app.sh         (Đóng gói ra .app và .dmg)
# =========================================================================
set -e
cd "$(dirname "$0")"

echo "=================================================================="
echo "  DEV DISK REPORT - TAURI v2 DESKTOP BUILDER (macOS)"
echo "=================================================================="

if ! command -v cargo >/dev/null 2>&1; then
  if [ -f "$HOME/.cargo/env" ]; then
    source "$HOME/.cargo/env"
  else
    echo "[!] Chưa cài đặt Rust. Hãy chạy: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    exit 1
  fi
fi

mkdir -p ui
cp disk-report.html ui/index.html
echo "[1/3] Đã đồng bộ disk-report.html -> ui/index.html"

if ! cargo tauri --version >/dev/null 2>&1; then
  echo "[2/3] Đang cài đặt tauri-cli v2..."
  cargo install tauri-cli --version "^2.0.0" --locked
else
  echo "[2/3] Đã sẵn sàng $(cargo tauri --version)"
fi

if [ "$1" = "--dev" ]; then
  echo "[3/3] Đang mở cửa sổ ứng dụng macOS (cargo tauri dev)..."
  cargo tauri dev
else
  echo "[3/3] Đang đóng gói ứng dụng macOS (.app / .dmg)..."
  cargo tauri build
  echo "=================================================================="
  echo "  HOÀN TẤT ĐÓNG GÓI TRÊN macOS!"
  echo "  - App Bundle (.app): target/release/bundle/macos/DevDiskReport.app"
  echo "  - Bộ cài (.dmg)    : target/release/bundle/dmg/"
  echo "=================================================================="
fi
