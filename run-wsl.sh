#!/usr/bin/env bash
# =========================================================================
# DEV DISK REPORT - WSL2 HYBRID RUNNER & BUILDER
# Cach dung ngay trong Terminal WSL2:
#   ./run-wsl.sh          -> Quet nhanh ca WSL2 (/home/chinchin) + Windows & cap nhat UI
#   ./run-wsl.sh --dev    -> Goi Tauri v2 Desktop App (cua so Windows) ngay tu WSL2
#   ./run-wsl.sh --build  -> Dong goi ra file .exe / .msi Windows ngay tu WSL2
# =========================================================================
set -e
cd "$(dirname "$0")"

MODE="${1:---scan}"

echo "=================================================================="
echo "  DEV DISK & ENVIRONMENT SCANNER (WSL2 + WINDOWS HYBRID MODE)"
echo "=================================================================="

# 1. Luon quet bo sung toan bo Dev Caches ben trong WSL2 (/home/$USER)
python3 - <<'PYEOF'
import os, json, csv, datetime
from concurrent.futures import ThreadPoolExecutor

wsl_home = os.path.expanduser("~")
now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

wsl_targets = [
    {
        "path": os.path.join(wsl_home, ".npm"),
        "name": "[WSL2] NPM Global Cache (~/.npm)",
        "category": "WSL2 / Linux",
        "safe": True,
        "cmd": 'wsl -e bash -c "npm cache clean --force"',
        "impact": "Xóa cache các gói npm bên trong môi trường WSL2 Linux (~250MB+). Không ảnh hưởng tới project."
    },
    {
        "path": os.path.join(wsl_home, ".antigravity-server"),
        "name": "[WSL2] Antigravity Remote Server (~/.antigravity-server)",
        "category": "WSL2 / Linux",
        "safe": False,
        "cmd": 'wsl -e bash -c "rm -rf ~/.antigravity-server/bin/*"',
        "impact": "Chứa nhân Antigravity Server chạy trong WSL2. Chỉ xóa khi muốn cài lại server mới."
    },
    {
        "path": os.path.join(wsl_home, ".vscode-server"),
        "name": "[WSL2] VS Code Remote WSL Server (~/.vscode-server)",
        "category": "WSL2 / Linux",
        "safe": False,
        "cmd": 'wsl -e bash -c "rm -rf ~/.vscode-server/bin/*"',
        "impact": "Chứa VS Code Server và extensions cài trong WSL2."
    },
    {
        "path": os.path.join(wsl_home, ".cache"),
        "name": "[WSL2] Linux Dev & CLI Cache (~/.cache: claude, copilot, gh, pip)",
        "category": "WSL2 / Linux",
        "safe": True,
        "cmd": 'wsl -e bash -c "rm -rf ~/.cache/*"',
        "impact": "Xóa bộ nhớ đệm các công cụ CLI bên trong WSL2 (Claude CLI, Copilot, GitHub CLI, pip...). Tự tạo lại khi dùng."
    },
    {
        "path": os.path.join(wsl_home, ".gemini"),
        "name": "[WSL2] Antigravity Brain & Sessions (~/.gemini)",
        "category": "WSL2 / Linux",
        "safe": False,
        "cmd": 'wsl -e bash -c "rm -rf ~/.gemini/antigravity/brain/*"',
        "impact": "Chứa dữ liệu phiên làm việc, brain logs và artifacts của Agent bên trong WSL2."
    },
    {
        "path": os.path.join(wsl_home, ".dotnet"),
        "name": "[WSL2] .NET SDK & Telemetry Cache (~/.dotnet)",
        "category": "WSL2 / Linux",
        "safe": False,
        "cmd": 'wsl -e bash -c "rm -rf ~/.dotnet/TieredPGO/*"',
        "impact": "Chứa cấu hình và cache của .NET SDK bên trong WSL2."
    },
    {
        "path": os.path.join(wsl_home, ".cargo/registry"),
        "name": "[WSL2] Rust Cargo Registry (~/.cargo/registry)",
        "category": "WSL2 / Linux",
        "safe": True,
        "cmd": 'wsl -e bash -c "rm -rf ~/.cargo/registry/cache/* ~/.cargo/registry/src/*"',
        "impact": "Xóa cache crates của Rust bên trong WSL2."
    },
]

def calc_dir(target):
    p = target["path"]
    if not os.path.exists(p):
        return None
    total_bytes = 0
    file_count = 0
    stack = [p]
    while stack:
        curr = stack.pop()
        try:
            with os.scandir(curr) as it:
                for entry in it:
                    try:
                        if entry.is_symlink():
                            continue
                        if entry.is_dir(follow_symlinks=False):
                            stack.append(entry.path)
                        elif entry.is_file(follow_symlinks=False):
                            file_count += 1
                            total_bytes += entry.stat(follow_symlinks=False).st_size
                    except OSError:
                        pass
        except OSError:
            pass
    if total_bytes == 0:
        return None
    mb = round(total_bytes / 1048576.0, 2)
    gb = round(total_bytes / 1073741824.0, 2)
    return {
        "Path": p,
        "Name": target["name"],
        "Category": target["category"],
        "Group": "Có thể xóa an toàn" if target["safe"] else "Cần xem lại trước khi xóa",
        "FileCount": file_count,
        "SizeBytes": total_bytes,
        "SizeMB": mb,
        "SizeGB": gb,
        "PreviousSizeMB": mb,
        "DeltaMB": 0.0,
        "Increased": False,
        "CleanCmd": target["cmd"],
        "Impact": target["impact"],
        "ScanTime": now_str
    }

with ThreadPoolExecutor(max_workers=8) as ex:
    wsl_results = [r for r in ex.map(calc_dir, wsl_targets) if r is not None]

# Doc report-data.json hien tai va gop chung voi du lieu Windows Host
payload = {"ScanTime": now_str, "Caches": [], "Artifacts": [], "EnvIssues": []}
if os.path.exists("report-data.json"):
    try:
        with open("report-data.json", "r", encoding="utf-8-sig") as f:
            payload = json.load(f)
    except Exception:
        pass

existing_caches = [c for c in payload.get("Caches", []) if not str(c.get("Name", "")).startswith("[WSL2]")]
prev_wsl = {c.get("Path"): c.get("SizeMB", 0.0) for c in payload.get("Caches", []) if str(c.get("Name", "")).startswith("[WSL2]")}

for item in wsl_results:
    prev_mb = prev_wsl.get(item["Path"], item["SizeMB"])
    delta = round(item["SizeMB"] - prev_mb, 2)
    item["PreviousSizeMB"] = prev_mb
    item["DeltaMB"] = delta
    item["Increased"] = delta > 0.05

merged_caches = existing_caches + wsl_results
merged_caches.sort(key=lambda x: x.get("SizeBytes", 0), reverse=True)
payload["ScanTime"] = now_str
payload["Caches"] = merged_caches

# Sua cac muc Impact rong neu co trong EnvIssues
for env_it in payload.get("EnvIssues", []):
    if not isinstance(env_it.get("Impact"), str) or not env_it.get("Impact"):
        tv = env_it.get("TargetValue", "")
        vn = env_it.get("VarName", "PATH")
        env_it["Impact"] = f"Đường dẫn '{tv}' đã bị xóa hoặc gỡ cài đặt nhưng vẫn còn tồn tại trong {vn}."

json_str = json.dumps(payload, ensure_ascii=False, indent=2)
with open("report-data.json", "w", encoding="utf-8") as f:
    f.write(json_str)

# Cap nhat sizes.csv
if merged_caches:
    fieldnames = ["Path","Name","Category","Group","FileCount","SizeBytes","SizeMB","SizeGB","PreviousSizeMB","DeltaMB","Increased","CleanCmd","Impact","ScanTime"]
    with open("sizes.csv", "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in merged_caches:
            writer.writerow({k: row.get(k, "") for k in fieldnames})

# Nhung vao disk-report.html va ui/index.html
for html_file in ["disk-report.html", "ui/index.html"]:
    if os.path.exists(html_file):
        with open(html_file, "r", encoding="utf-8") as f:
            content = f.read()
        s_mark = "// === BEGIN_AUTO_DATA ==="
        e_mark = "// === END_AUTO_DATA ==="
        i1 = content.find(s_mark)
        i2 = content.find(e_mark)
        if i1 != -1 and i2 != -1 and i2 > i1:
            new_c = content[:i1] + f"{s_mark}\n    const scanPayload = {json_str};\n    {e_mark}" + content[i2+len(e_mark):]
            with open(html_file, "w", encoding="utf-8") as f:
                f.write(new_c)

total_wsl_mb = sum(x["SizeMB"] for x in wsl_results)
print(f"[OK] Da quet {len(wsl_results)} muc trong WSL2 ({total_wsl_mb:.2f} MB) + {len(existing_caches)} muc tren Windows Host!")
PYEOF

if [ "$MODE" = "--scan-only" ]; then
    exit 0
fi

PS_EXE="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
WIN_DIR=$(wslpath -w "$(pwd)" 2>/dev/null || echo 'C:\Users\chinh\disk-report')

if [ "$MODE" = "--dev" ]; then
    echo "[*] Dang goi Windows PowerShell tu WSL2 de mo cua so Tauri Desktop App..."
    "$PS_EXE" -ExecutionPolicy Bypass -File "${WIN_DIR}\\build-app.ps1" -Dev
elif [ "$MODE" = "--build" ]; then
    echo "[*] Dang goi Windows PowerShell tu WSL2 de dong goi file .exe / .msi..."
    "$PS_EXE" -ExecutionPolicy Bypass -File "${WIN_DIR}\\build-app.ps1"
else
    echo "[*] Dang mo giao dien Dashboard tren Windows..."
    if [ -x "/mnt/c/Windows/System32/cmd.exe" ]; then
        /mnt/c/Windows/System32/cmd.exe /c start "" "${WIN_DIR}\\disk-report.html" >/dev/null 2>&1 || true
    fi
    echo "[HOAN TAT] Da cap nhat disk-report.html voi du lieu Hybrid (Windows + WSL2)!"
fi
