---
name: fwp-debug
description: [项目] Bug 修复入口——复现→收集证据→创建 bug issue→派发 fw-plan，用户只需一句话描述
---

# FWP-DEBUG（Bug 修复入口 · 用户级）

用户报告 bug → 自动复现 → 收集证据 → 创建结构化 bug issue → 派发 fw-plan 驱动修复。

> **用户级 skill**：跨项目生效。用户只需一句话描述 bug，其余全部自动。

## 上下文检测

```bash
WORKSPACE=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$WORKSPACE"
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
CLI=$(awk '/\[project\.scripts\]/{found=1;next} found && /=/ {print $1; exit}' pyproject.toml 2>/dev/null || basename "$WORKSPACE")
echo "[fwp-debug] WORKSPACE=$WORKSPACE CLI=$CLI"
```

## 调用方式

```text
/fwp-debug <bug 描述>                           # 一句话描述
/fwp-debug <bug 描述> --repro "<复现命令>"       # 指定复现步骤
/fwp-debug <bug 描述> --log "<日志文件路径>"      # 指定日志文件
```

| 参数 | 说明 |
|------|------|
| `<bug 描述>` | 必填，一句话说明什么现象 |
| `--repro` | 可选，触发 bug 的命令（不提供则自动推断） |
| `--log` | 可选，相关日志文件路径（不提供则自动搜索） |

## 固定流程（5 步）

### 1. 理解 bug

从用户描述中提取：

```text
现象: <用户描述的关键词>
模块: <涉及的模块/文件>
严重度: CRASH(崩溃) | WRONG(结果错误) | SLOW(性能) | COSMETIC(展示问题)
```

### 2. 尝试复现

```bash
cd "$(git rev-parse --show-toplevel)"
CLI=$(awk '/\[project\.scripts\]/{f=1;next} f&&/=/ {print $1;exit}' pyproject.toml 2>/dev/null)

# 用户指定了复现命令 → 直接执行
if [ -n "${REPRO_CMD:-}" ]; then
  echo "=== 复现: $REPRO_CMD ==="
  $REPRO_CMD 2>&1 | tail -50
  EXIT_CODE=$?
else
  # 自动推断：尝试运行 CLI 的常见命令
  echo "=== 自动复现 ==="
  $CLI --help >/dev/null 2>&1 && echo "CLI 可用" || echo "CLI 不可用"
  # 搜索最近的 ERROR 日志
  LOGDIR="${LOG_DIR:-$HOME/.$(grep -m1 '^name\s*=' pyproject.toml 2>/dev/null | sed 's/.*=\\s*\"\\(.*\\)\".*/\\1/' || basename "$PWD")/logs}"
  if [ -d "$LOGDIR" ]; then
    echo "=== 最近 ERROR ==="
    find "$LOGDIR/" -name "*.log" -mtime -1 | xargs grep -i "error\|exception\|traceback" 2>/dev/null | tail -20
  fi
fi
```

### 3. 收集证据

```bash
# 收集以下证据
echo "=== Bug 证据 ==="
echo "**时间**: $(date -Iseconds)"
echo "**分支**: $(git branch --show-current)"
echo "**最近 commit**: $(git log -1 --format='%h %s')"

# Python 项目：收集依赖版本
if [ -f pyproject.toml ]; then
  echo "**Python**: $(python --version 2>&1)"
  pip freeze 2>/dev/null | grep -i "$(basename "$PWD")" || true
fi

# 搜索相关测试
echo "**相关测试**:"
grep -rl "$(echo "${BUG_DESC}" | grep -oP '\w+_\w+|\w+Error|\w+Exception' | head -1)" tests/ 2>/dev/null | head -5 || echo "(未找到)"
```

### 4. 创建 bug issue

```bash
cd "$(git rev-parse --show-toplevel)"
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)

# 构建 issue body
cat > /tmp/fw-flywheel/bug-body.md << EOF
## 现象

${BUG_DESC}

## 复现步骤

\`\`\`bash
${REPRO_CMD:-（自动复现未成功，需手动补充）}
\`\`\`

## 环境

- 分支: $(git branch --show-current)
- 最近 commit: $(git log -1 --format='%h %s')
- 时间: $(date -Iseconds)

## 日志/输出

$(cat /tmp/fw-flywheel/bug-log.txt 2>/dev/null || echo "(无)")

## 预期行为

<Bug 修复后的正确行为>
EOF

# 创建 issue
ISSUE_URL=$(gh issue create \
  --title "bug: ${BUG_DESC}" \
  --body "$(cat /tmp/fw-flywheel/bug-body.md)" \
  --label "bug,needs-triage")

ISSUE_NUM=$(echo "$ISSUE_URL" | grep -oE '[0-9]+$')
echo "[fwp-debug] 已创建 issue #$ISSUE_NUM"
```

### 5. 派发 fw-plan

```bash
mkdir -p /tmp/fw-flywheel
cat > "/tmp/fw-flywheel/milestone-bug-${ISSUE_NUM}.md" << EOF
# [fwp-debug][BUG] ${BUG_DESC}

| 字段 | 值 |
|------|-----|
| 来源 | fw-debug 用户报告 |
| 严重度 | ${SEVERITY} |
| issue | #${ISSUE_NUM} |
| 复现状态 | $([ "${REPRODUCED:-}" = "yes" ] && echo "已复现" || echo "待确认") |
| 建议范围 | ${MODULE:-待分析} |
EOF
```

```text
Agent(description: "fw-plan: 修复 bug #${ISSUE_NUM}", subagent_type: "fwp-plan",
  prompt: "milestone: /tmp/fw-flywheel/milestone-bug-${ISSUE_NUM}.md")
```

---

## 输出示例

```text
## FW-DEBUG 报告

| 字段 | 值 |
|------|-----|
| 现象 | KeyError: 'breakout_score' |
| 严重度 | CRASH |
| 复现 | ✅ 已复现: `alphascreener screen --top 20` |
| 模块 | alphascreener/phase2.py:145 |
| Issue | #58 (bug, needs-triage) |
| 下一步 | 已派发 fw-plan → fw-ship → fw-build |
```

## 约束

- **固定流程**：5 步机械执行，不依赖 LLM 主观判断 bug 原因
- **只收集证据，不修复**：fw-debug 不写代码，不分析根因，只创建 issue 并移交 fw-plan
- **自动派发**：issue 创建后自动通过 subagent 派发 fw-plan
- **禁止用户交互**：严禁 `AskUserQuestion`
