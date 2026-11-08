#!/usr/bin/env bash
# =========================================================================
# DEV DISK REPORT - AUTO CREATE & PUSH TO GITHUB (TRIGGERS CLOUD BUILD)
# Cach dung trong WSL2 Terminal:
#   ./push-github.sh                 (Tao repo Public: chinchindev/disk-report & push)
#   ./push-github.sh --private       (Tao repo Private: chinchindev/disk-report & push)
# =========================================================================
set -e
cd "$(dirname "$0")"

REPO_NAME="disk-report"
GH_USER="chinchindev"
PRIVATE_FLAG="false"

if [ "$1" = "--private" ]; then
  PRIVATE_FLAG="true"
fi

# Lay token tu ~/.config/gh/hosts.yml neu co
GH_TOKEN="${GITHUB_TOKEN:-}"
if [ -z "$GH_TOKEN" ] && [ -f "$HOME/.config/gh/hosts.yml" ]; then
  GH_TOKEN=$(grep -m1 "oauth_token:" "$HOME/.config/gh/hosts.yml" | awk '{print $2}' | tr -d '\r\n')
fi

if [ -z "$GH_TOKEN" ]; then
  echo "[!] Khong tim thay token trong ~/.config/gh/hosts.yml."
  echo "    Hay dat bien GITHUB_TOKEN=<token> hoac dang nhap git truoc khi push."
  exit 1
fi

echo "=================================================================="
echo "  PUSHING TO GITHUB: https://github.com/${GH_USER}/${REPO_NAME}"
echo "=================================================================="

# 1. Tao repo tren GitHub qua REST API (neu chua ton tai)
echo "[1/3] Kiem tra / Khoi tao repository '${GH_USER}/${REPO_NAME}' tren GitHub..."
HTTP_CODE=$(curl -s -o /tmp/gh_repo_resp.json -w "%{http_code}" \
  -H "Authorization: token ${GH_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/user/repos \
  -d "{\"name\":\"${REPO_NAME}\",\"description\":\"Cross-platform Dev Disk & Environment Scanner (Rust + Tauri v2)\",\"private\":${PRIVATE_FLAG}}")

if [ "$HTTP_CODE" = "201" ]; then
  echo "  -> Da tao moi repository https://github.com/${GH_USER}/${REPO_NAME} thanh cong!"
elif [ "$HTTP_CODE" = "422" ]; then
  echo "  -> Repository https://github.com/${GH_USER}/${REPO_NAME} da ton tai, tiep tuc cap nhat..."
else
  echo "  -> Phan hoi tu GitHub API (HTTP $HTTP_CODE)."
fi

# 2. Commit moi thay doi moi nhat (neu co)
git add .
if ! git diff --cached --quiet; then
  git commit -m "chore: update GitHub Actions workflow and helper scripts"
fi

# 3. Cau hinh remote va push len nhanh main
echo "[2/3] Dang push code len nhanh 'main'..."
REMOTE_URL="https://${GH_USER}:${GH_TOKEN}@github.com/${GH_USER}/${REPO_NAME}.git"
CLEAN_URL="https://github.com/${GH_USER}/${REPO_NAME}.git"

if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$REMOTE_URL"
else
  git remote add origin "$REMOTE_URL"
fi

git push -u origin main --force

# Dat lai URL sach (khong luu token trong .git/config)
git remote set-url origin "$CLEAN_URL"

echo ""
echo "=================================================================="
echo "  [3/3] PUSH THANH CONG LEN GITHUB!"
echo "  - Repo URL   : https://github.com/${GH_USER}/${REPO_NAME}"
echo "  - Cloud Build: https://github.com/${GH_USER}/${REPO_NAME}/actions"
echo "  - Releases   : https://github.com/${GH_USER}/${REPO_NAME}/releases"
echo "=================================================================="
