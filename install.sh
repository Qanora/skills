#!/bin/bash
# 飞轮 skill 安装脚本 — 将当前仓库的 skill 软链到 ~/.claude/skills/
# 用法: ./install.sh [--dry-run] [--uninstall]
set -euo pipefail

DRY_RUN=false
UNINSTALL=false

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --uninstall) UNINSTALL=true; shift ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

# 源目录（脚本所在目录的 flywheel/ 子目录）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/flywheel"
DST="$HOME/.claude/skills"

SKILLS=("fwp-inspect" "fw-audit" "fwp-plan" "fwp-ship" "fwp-build" "fwp-setup" "fwp-debug" "fwp-resume" "fwp-help")
# 卸载时也清理旧 lp-* 名称
OLD_SKILLS=("lp-up" "lp-dp" "lp-ms" "lp-mr" "lp-dev" "lp-init" "fw-setup" "fw-plan" "fw-debug" "fw-inspect" "fw-build" "fw-ship" "fw-resume")

# ── 卸载 ──
if $UNINSTALL; then
  echo "=== 卸载飞轮 skills ==="
  ALL=("${SKILLS[@]}" "${OLD_SKILLS[@]}")
  for skill in "${ALL[@]}"; do
    link="$DST/$skill"
    if [ -L "$link" ]; then
      $DRY_RUN && echo "[DRY-RUN] rm $link" || rm "$link"
      echo "[REMOVE] $link (目录软链)"
    elif [ -d "$link" ]; then
      $DRY_RUN && echo "[DRY-RUN] rm -rf $link" || rm -rf "$link"
      echo "[REMOVE] $link (目录)"
    elif [ -f "$link/SKILL.md" ]; then
      $DRY_RUN && echo "[DRY-RUN] rm $link/SKILL.md && rmdir $link" || { rm "$link/SKILL.md"; rmdir "$link" 2>/dev/null || true; }
      echo "[REMOVE] $link (旧格式)"
    else
      echo "[SKIP]  $link (不存在)"
    fi
  done
  exit 0
fi

# ── 检查源目录 ──
echo "=== 飞轮 skill 安装 ==="
echo "源: $SRC"
echo "目标: $DST (目录级软链)"
echo ""

for skill in "${SKILLS[@]}"; do
  if [ ! -d "$SRC/$skill" ]; then
    echo "[ERROR] 源目录不存在: $SRC/$skill"
    exit 1
  fi
done

# ── 安装目录级软链 ──
for skill in "${SKILLS[@]}"; do
  link="$DST/$skill"
  src="$SRC/$skill"

  # 已存在且是正确的目录软链 → 跳过
  if [ -L "$link" ] && [ "$(readlink "$link")" = "$src" ]; then
    echo "  [OK]    $skill (已正确链接)"
    continue
  fi

  # 已存在但是文件/目录/错误链接 → 先删
  if [ -e "$link" ] || [ -L "$link" ]; then
    $DRY_RUN && echo "[DRY-RUN] rm -rf $link" || rm -rf "$link"
  fi

  if $DRY_RUN; then
    echo "[DRY-RUN] ln -s $src → $link"
  else
    ln -sf "$src" "$link"
    echo "  [LINK]  $skill → $src"
  fi
done

echo ""
echo "=== 安装完成 ==="
echo ""
echo "验证: ls -la ~/.claude/skills/fwp-* ~/.claude/skills/fw-audit"
echo "测试: /fwp-help"
