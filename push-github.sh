#!/usr/bin/env bash
# =========================================================================
# DEV DISK REPORT - AUTO COMMIT & PUSH TO GITHUB (SSH + CLOUD BUILD)
# =========================================================================
set -e
cd "$(dirname "$0")"

REPO_NAME="disk-report"
GH_USER="chinchindev"
SSH_URL="git@github.com:${GH_USER}/${REPO_NAME}.git"

GH_TOKEN="${GITHUB_TOKEN:-}"
if [ -z "$GH_TOKEN" ] && [ -f "$HOME/.config/gh/hosts.yml" ]; then
  GH_TOKEN=$(grep -m1 "oauth_token:" "$HOME/.config/gh/hosts.yml" | awk '{print $2}' | tr -d '\r\n')
fi

echo "=================================================================="
echo "  PUSHING TO GITHUB: https://github.com/${GH_USER}/${REPO_NAME}"
echo "=================================================================="

# 0. Kiem tra log build gan nhat tren GitHub Actions (neu co)
if [ -n "$GH_TOKEN" ]; then
  echo "[*] Kiem tra trang thai workflow gan nhat tren GitHub Actions..."
  python3 - "$GH_TOKEN" "$GH_USER" "$REPO_NAME" <<'PYEOF' || true
import sys, json, urllib.request

token, user, repo = sys.argv[1], sys.argv[2], sys.argv[3]
headers = {"Authorization": f"token {token}", "Accept": "application/vnd.github+json", "User-Agent": "wsl"}

try:
    req = urllib.request.Request(f"https://api.github.com/repos/{user}/{repo}/actions/runs?per_page=1", headers=headers)
    with urllib.request.urlopen(req, timeout=8) as resp:
        runs = json.loads(resp.read().decode()).get("workflow_runs", [])
    if runs:
        r = runs[0]
        print(f"  -> Run #{r.get('run_number')}: status={r.get('status')}, conclusion={r.get('conclusion')}")
        jobs_req = urllib.request.Request(r.get("jobs_url"), headers=headers)
        with urllib.request.urlopen(jobs_req, timeout=8) as jresp:
            jobs = json.loads(jresp.read().decode()).get("jobs", [])
        for j in jobs:
            print(f"     Job [{j.get('name')}]: {j.get('conclusion')}")
            for s in j.get("steps", []):
                if s.get("conclusion") == "failure":
                    print(f"       [FAILED STEP] #{s.get('number')}: {s.get('name')}")
except Exception as e:
    pass
PYEOF
fi

# 1. Commit moi thay doi
git add -A
if ! git diff --cached --quiet; then
  git commit -m "fix(ci): use official Tauri v2 prebuilt binaries, BMP-DIB icon.ico, and hdiutil DMG"
fi

# 2. Push qua SSH
SSH_KEY_FILE="$HOME/.ssh/id_ed25519"
if [ -f "$SSH_KEY_FILE" ]; then
  echo "[*] Dang push ban sua loi len nhanh 'main' qua SSH..."
  GIT_SSH_COMMAND="ssh -i $SSH_KEY_FILE -o IdentitiesOnly=yes -o StrictHostKeyChecking=no" git push -u "$SSH_URL" main --force
  echo ""
  echo "=================================================================="
  echo "  [HOAN TAT] DA PUSH BAN SUA LOI LEN GITHUB ACTIONS!"
  echo "  - Xem tien trinh Build: https://github.com/${GH_USER}/${REPO_NAME}/actions"
  echo "  - Trang Releases      : https://github.com/${GH_USER}/${REPO_NAME}/releases"
  echo "=================================================================="
else
  echo "[!] Khong tim thay SSH key tai $SSH_KEY_FILE"
  exit 1
fi
