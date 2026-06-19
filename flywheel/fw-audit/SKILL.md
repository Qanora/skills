---
name: fw-audit
description: [飞轮] AI安全治理审计——门禁/约束/行为/传递/效率 5维度，确保AI在秩序下稳步前进
---

# FW-AUDIT（AI 安全治理审计 · 用户级）

5 维度审计飞轮的 AI 安全治理。`/fw-audit` 直接回车。审计对象是飞轮自身，不是项目代码。

> 项目代码质量由 `/fwp-inspect` Tier 2 负责。

## 上下文检测

```bash
WORKSPACE=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$WORKSPACE"
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
DEFAULT_BRANCH=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's|.*/||' || echo "master")
PROJECT=$(grep -m1 '^name\s*=' pyproject.toml 2>/dev/null | sed 's/.*=\s*"\(.*\)".*/\1/' || basename "$PWD")
echo "[fw-audit] REPO=$REPO BRANCH=$DEFAULT_BRANCH"
```

## 调用方式

```text
/fw-audit                         # 全量审计
/fw-audit --focus <维度>          # gates | guards | behavior | comms | efficiency
/fw-audit --resume                # 中断恢复
```

---

## A1. GATES — 门禁完整性

**是否有足够的卡点防止 AI 强行合入有问题的代码？**

```bash
echo "=== A1: 门禁完整性 ==="
cd "$(git rev-parse --show-toplevel)"

# 分支保护
echo "--- 分支保护 ---"
gh api "repos/$REPO/branches/$DEFAULT_BRANCH/protection" --jq '{pr:.required_pull_request_reviews.required,checks:.required_status_checks.contexts}' 2>/dev/null || echo "FAIL: 无分支保护"

# CI 门禁
echo "--- CI 门禁 ---"
[ -f .github/workflows/test.yml ] && echo "PASS: test.yml" || echo "FAIL: 无 test.yml"
grep -c "gitleaks\|commit-msg\|test" .github/workflows/test.yml 2>/dev/null >/dev/null && echo "PASS: 含 gitleaks/commit-msg/test" || echo "WARN: CI 门禁不完整"

# Auto-merge 安全性
echo "--- Auto-merge ---"
[ -f .github/workflows/auto-merge.yml ] && echo "PASS: auto-merge.yml" || echo "FAIL: 无 auto-merge"
grep -q "squash" .github/workflows/auto-merge.yml 2>/dev/null && echo "PASS: squash merge" || echo "WARN: 非 squash"

# 代码审查
echo "--- 代码审查 ---"
[ -f .coderabbit.yaml ] && echo "PASS: CodeRabbit" || echo "WARN: 无 CodeRabbit"
[ -f .github/pr_agent.toml ] && echo "PASS: PR Agent" || echo "INFO: 无 PR Agent"

# 密钥检测
echo "--- 密钥检测 ---"
[ -f .gitleaks.toml ] && echo "PASS: Gitleaks" || echo "FAIL: 无 Gitleaks"
```

| 缺失项 | 严重度 |
|--------|--------|
| 分支保护 (require PR + status checks) | FAIL |
| CI 门禁缺一项 (gitleaks/commit-msg/tests) | FAIL |
| Auto-merge 非 squash | WARN |
| 无代码审查 (CodeRabbit/PR Agent) | WARN |
| 无密钥检测 (Gitleaks) | FAIL |

---

## A2. GUARDS — 约束有效性

**是否有足够的约束让 AI 在秩序下稳步前进？**

```bash
echo "=== A2: 约束有效性 ==="
cd "$(git rev-parse --show-toplevel)"

# commit 规范
echo "--- commit 规范 ---"
TOTAL=$(git log --since="7 days ago" --oneline | grep -v "dependabot" | wc -l)
HAS_REF=$(git log --since="7 days ago" --format="%s" | grep -v "dependabot" | grep -ciE '#[0-9]+' || echo 0)
[ "$TOTAL" -gt 0 ] && [ "$HAS_REF" -lt "$TOTAL" ] && echo "FAIL: $((TOTAL - HAS_REF))/$TOTAL commit 缺少 issue 引用" || echo "PASS: 全部含 issue 引用 ($TOTAL)"

# 直接推送检测
echo "--- 直接推送 ---"
DIRECT=$(git log --since="30 days ago" --format="%h %s" --first-parent "origin/$DEFAULT_BRANCH" | grep -v "Merge\|Squash" | head -3)
[ -n "$DIRECT" ] && echo "FAIL: 疑似直接推送" || echo "PASS: 无直接推送"

# fix_round 上限
echo "--- fix_round ---"
OVER=$(find .claude/state/ -name "*.fix_round" -exec cat {} \; 2>/dev/null | awk '$1>=3' | wc -l)
[ "$OVER" -gt 0 ] && echo "WARN: $OVER 个 issue 已达 fix_round 上限" || echo "PASS: 无超限"

# 分支命名
echo "--- 分支命名 ---"
BAD=$(git branch | grep "feature/" | grep -v "feature/issue-" | wc -l)
[ "$BAD" -gt 0 ] && echo "WARN: $BAD 个分支命名不规范" || echo "PASS: 分支命名规范"

# git hook
echo "--- git hook ---"
[ -L .git/hooks/commit-msg ] && echo "PASS: commit-msg hook" || echo "FAIL: 无 commit-msg hook"
```

| 缺失/违反 | 严重度 |
|-----------|--------|
| commit 缺少 issue 引用 | FAIL |
| 直接推送到默认分支 | FAIL |
| fix_round 超限 (≥3) | WARN |
| 分支命名不规范 | WARN |
| 无 commit-msg git hook | FAIL |

---

## A3. BEHAVIOR — 行为审计

**AI 是否出现了非预期行为？**

> 此项审计当前会话上下文中的 tool call 历史，不由 bash 驱动。

逐项检查当前会话：

| 检查项 | 判定标准 |
|--------|---------|
| 代码编辑路径 | Edit/Write 不在 fwp-build subagent 内 → FAIL |
| AskUserQuestion | 飞轮 skill 严禁调用 → FAIL |
| 步骤完整性 | 对照 SKILL.md 预期步骤，跳过阻塞步骤 → WARN |
| git 操作归属 | git commit/push/merge 不在 fwp-ship 内 → FAIL |
| subagent 调用链 | fwp-build 被直接调用（非 fwp-ship 派发）→ WARN |
| 未授权分支操作 | 从非 origin/DEFAULT_BRANCH 创建 feature 分支 → FAIL |

---

## A4. COMMS — 信息传递健康度

**skill 间信息传递是否通畅合理？**

```bash
echo "=== A4: 信息传递 ==="
TMPDIR="/tmp/fw-flywheel/$PROJECT"

# milestone 文件完整性
echo "--- milestone ---"
for f in "$TMPDIR"/milestone-*.md 2>/dev/null; do
  SIZE=$(wc -c < "$f")
  grep -q "来源\|严重度" "$f" && echo "  $(basename $f): PASS ($SIZE bytes)" || echo "  $(basename $f): FAIL (格式不完整)"
done

# ctx/status 成对
echo "--- 文件成对 ---"
CTX=$(ls "$TMPDIR"/ctx-*.md 2>/dev/null | wc -l)
RESULT=$(ls "$TMPDIR"/result-*.md 2>/dev/null | wc -l)
STATUS=$(ls "$TMPDIR"/status-*.md 2>/dev/null | wc -l)
echo "ctx:$CTX result:$RESULT status:$STATUS"
[ "$CTX" -ne "$STATUS" ] && echo "WARN: ctx/status 数量不匹配 ($CTX vs $STATUS)"

# HANDOFF 格式
echo "--- HANDOFF ---"
for f in "$TMPDIR"/result-*.md 2>/dev/null; do
  grep -qE "DEV_DONE|FIX_DONE|FAIL_DONE" "$f" && echo "  $(basename $f): PASS" || echo "  $(basename $f): NON-STANDARD"
done

# 孤儿文件
echo "--- 孤儿 ---"
STALE=$(find "$TMPDIR" -name "*.md" -mtime +1 2>/dev/null | wc -l)
[ "$STALE" -gt 0 ] && echo "WARN: $STALE 个超1天临时文件" || echo "PASS: 无孤儿文件"
```

| 问题 | 严重度 |
|------|--------|
| milestone 文件格式不完整 | FAIL |
| ctx/status 数量不匹配 | WARN |
| HANDOFF 非标准 | FAIL |
| 孤儿临时文件 (>1天) | WARN |

---

## A5. EFFICIENCY — 效率与计划性

**飞轮是否有效率、有计划地完成工作？**

```bash
echo "=== A5: 效率指标 ==="
cd "$(git rev-parse --show-toplevel)"

# Milestone 统计
echo "--- Milestone ---"
OPEN=$(gh api "repos/$REPO/milestones" --jq '[.[]|select(.state=="open")]|length' 2>/dev/null || echo "?")
CLOSED=$(gh api "repos/$REPO/milestones" --jq '[.[]|select(.state=="closed")]|length' 2>/dev/null || echo "?")
echo "open:$OPEN closed:$CLOSED"

# 平均 fix_round
echo "--- fix_round ---"
VALUES=$(find .claude/state/ -name "*.fix_round" -exec cat {} \; 2>/dev/null)
if [ -n "$VALUES" ]; then
  AVG=$(echo "$VALUES" | awk '{s+=$1;n++} END{printf "%.1f", s/n}')
  echo "平均: $AVG"
  [ "$(echo "$AVG > 2"|bc -l 2>/dev/null)" = "1" ] && echo "WARN: 平均 fix_round > 2"
else echo "INFO: 无 fix_round 数据"; fi

# 分支泄漏率
echo "--- 分支泄漏 ---"
MERGED_BR=$(gh pr list --state merged --limit 50 --json headRefName --jq '.[].headRefName' | wc -l)
LOCAL_BR=$(git branch | grep -c "feature/issue-" || echo 0)
LEAK=$(( LOCAL_BR * 100 / (MERGED_BR + 1) ))
echo "merged PR:$MERGED_BR 本地残留:$LOCAL_BR 泄漏率:${LEAK}%"
[ "$LEAK" -gt 25 ] && echo "FAIL: 泄漏率 > 25%"

# 状态文件时效
echo "--- state 时效 ---"
STALE=$(find .claude/state/ -type f -mtime +7 2>/dev/null | wc -l)
[ "$STALE" -gt 5 ] && echo "WARN: $STALE 个超7天状态文件" || echo "PASS: $STALE 个"

# Milestone 交付周期
echo "--- 交付周期 ---"
gh api "repos/$REPO/milestones" --jq '.[]|select(.state=="closed")|"\(.title): \(.closed_at)[:10] - \(.created_at)[:10]"' 2>/dev/null | head -5
```

| 指标 | 判定 |
|------|------|
| Milestone 完成率 | 长期 open > closed → WARN |
| 平均 fix_round > 2 | WARN |
| 分支泄漏率 > 25% | FAIL |
| 状态文件 > 5 个超 7 天 | WARN |
| Milestone 交付 > 7 天 | INFO |

---

## 执行流程

1. A1→A5 依次执行，每维度先跑 bash 再分析会话
2. 汇总各维度 FAIL/WARN/PASS/INFO
3. 所有 FAIL → 生成 CRITICAL DESIGN milestone → Agent(fwp-plan)
4. WARN 连续 2 轮 → 升级为 FAIL

```bash
for dim in GATES GUARDS BEHAVIOR COMMS EFFICIENCY; do
  [ "${RESULT[$dim]}" = "FAIL" ] && cat > "/tmp/fw-flywheel/$PROJECT/milestone-audit-${dim}.md" << EOF
# [fw-audit][${dim}] ${DESC[$dim]}
| 字段 | 值 |
|------|-----|
| 来源 | fw-audit |
| 维度 | ${dim} |
| 严重度 | CRITICAL |
| 证据 | ${EVIDENCE[$dim]} |
| 建议 | ${FIX[$dim]} |
EOF
  Agent(description: "fwp-plan: 修复飞轮/${dim}", subagent_type: "fwp-plan",
    prompt: "milestone: /tmp/fw-flywheel/$PROJECT/milestone-audit-${dim}.md")
done
```

## 约束

- **审计飞轮，不审计项目**：项目代码质量由 fwp-inspect Tier 2 负责
- **安全问题即时 FAIL**：门禁缺失/绕过 → 立即 FAIL，不等老化
- **A3 依赖会话上下文**：行为审计需分析当前对话 tool call 历史
- **禁止用户交互**：严禁 `AskUserQuestion`
