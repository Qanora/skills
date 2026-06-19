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

SKILLS=("lp-up" "lp-dp" "lp-ms" "lp-mr" "lp-dev" "lp-init")

# ── 卸载 ──
if $UNINSTALL; then
  echo "=== 卸载飞轮 skills ==="
  for skill in "${SKILLS[@]}"; do
    link="$DST/$skill/SKILL.md"
    target=$(readlink "$link" 2>/dev/null || true)
    if [ -L "$link" ]; then
      $DRY_RUN && echo "[DRY-RUN] rm $link" || rm "$link"
      echo "[REMOVE] $link"
    else
      echo "[SKIP]  $link (非软链，跳过)"
    fi
    # 清理空目录
    $DRY_RUN || rmdir "$DST/$skill" 2>/dev/null || true
  done
  exit 0
fi

# ── 检查源文件 ──
echo "=== 飞轮 skill 安装 ==="
echo "源: $SRC"
echo "目标: $DST"
echo ""

for skill in "${SKILLS[@]}"; do
  if [ ! -f "$SRC/$skill/SKILL.md" ]; then
    echo "[ERROR] 源文件不存在: $SRC/$skill/SKILL.md"
    exit 1
  fi
done

# ── 安装软链 ──
echo "已安装 skills:"
echo ""

for skill in "${SKILLS[@]}"; do
  link="$DST/$skill/SKILL.md"
  src="$SRC/$skill/SKILL.md"

  # 已存在且已是正确软链 → 跳过
  if [ -L "$link" ] && [ "$(readlink "$link")" = "$src" ]; then
    echo "  [OK]    $skill (已正确链接)"
    continue
  fi

  # 已存在但是文件/错误链接 → 先删
  if [ -e "$link" ] || [ -L "$link" ]; then
    $DRY_RUN && echo "[DRY-RUN] rm $link" || rm -f "$link"
  fi

  if $DRY_RUN; then
    echo "[DRY-RUN] ln -s $src → $link"
  else
    mkdir -p "$DST/$skill"
    ln -sf "$src" "$link"
    echo "  [LINK]  $skill → $src"
  fi
done

echo ""
echo "=== 安装完成 ==="
echo ""
echo "验证: ls -la ~/.claude/skills/lp-*/SKILL.md"
echo "测试: 在任意项目目录下输入 /lp-ms 测试需求"
