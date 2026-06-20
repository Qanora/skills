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
/fw-audit                    # 5维度全量审计
```

无参数。始终跑满 5 个维度，不区分 focus。

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

# CI 绕过检测 — 是否存在 PR 在 CI 完成前被强制合入
echo "--- CI 绕过检测 ---"

MERGED_PRS=$(gh pr list --state merged --limit 20 --json number,mergedAt,mergeCommit \
  --jq '.[] | select(.mergeCommit.oid != null) | "\(.number)|\(.mergedAt)|\(.mergeCommit.oid)"')

CI_BYPASS=0
CI_DETAILS=""

while IFS='|' read -r num merged_at merge_sha; do
  [ -z "$merge_sha" ] && continue
  # 获取 merge commit 的 CI 状态
  STATE=$(gh api "repos/$REPO/commits/$merge_sha/status" --jq '.state' 2>/dev/null || echo "unknown")

  if [ "$STATE" != "success" ]; then
    CHECK_TOTAL=$(gh api "repos/$REPO/commits/$merge_sha/check-runs" --jq '.total_count' 2>/dev/null || echo "0")

    if [ "$CHECK_TOTAL" = "0" ]; then
      CI_BYPASS=$((CI_BYPASS + 1))
      CI_DETAILS="$CI_DETAILS\n    PR #$num (CI未运行)"
    elif [ "$STATE" = "failure" ]; then
      CI_BYPASS=$((CI_BYPASS + 1))
      CI_DETAILS="$CI_DETAILS\n    PR #$num (CI失败仍合入)"
    elif [ "$STATE" = "pending" ]; then
      CI_BYPASS=$((CI_BYPASS + 1))
      CI_DETAILS="$CI_DETAILS\n    PR #$num (CI未完成即合入)"
    fi
  fi
done <<< "$MERGED_PRS"

if [ "$CI_BYPASS" -gt 0 ]; then
  echo "FAIL: $CI_BYPASS 个 PR 在 CI 未通过时被合入:$CI_DETAILS"
else
  echo "PASS: 所有 PR 均通过 CI 后合入"
fi

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
| CI 绕过 (PR 未等 CI 通过即合入) | FAIL |
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

# issue 闭环检测 — 已合并 PR 的关联 issue 是否已关闭
echo "--- issue 闭环 ---"

MERGED_PRS=$(gh pr list --state merged --limit 30 --json number,body,headRefName \
  --jq '.[] | "\(.number)|\(.body)|\(.headRefName)"')

ORPHAN=0
ORPHAN_DETAILS=""

while IFS='|' read -r pr_num body branch; do
  [ -z "$pr_num" ] && continue

  ISSUE_NUM=""
  # 从分支名提取 issue-<num>
  if echo "$branch" | grep -qE 'issue-[0-9]+'; then
    ISSUE_NUM=$(echo "$branch" | grep -oE 'issue-[0-9]+' | grep -oE '[0-9]+' | head -1)
  fi
  # 从 PR body 提取 closes/fixes #<num>
  if [ -z "$ISSUE_NUM" ]; then
    ISSUE_NUM=$(echo "$body" | grep -oEi '(close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved)\s+#[0-9]+' | grep -oE '[0-9]+' | head -1)
  fi

  if [ -n "$ISSUE_NUM" ]; then
    STATE=$(gh issue view "$ISSUE_NUM" --json state -q '.state' 2>/dev/null)
    if [ "$STATE" = "OPEN" ]; then
      ORPHAN=$((ORPHAN + 1))
      ORPHAN_DETAILS="$ORPHAN_DETAILS\n    PR #$pr_num 已合并 → issue #$ISSUE_NUM 仍 OPEN"
    fi
  fi
done <<< "$MERGED_PRS"

if [ "$ORPHAN" -gt 0 ]; then
  echo "FAIL: $ORPHAN 个已合并 PR 的关联 issue 未关闭:$ORPHAN_DETAILS"
else
  echo "PASS: 所有已合并 PR 的关联 issue 均已关闭"
fi

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
| 已合并 PR 的关联 issue 未关闭 | FAIL |
| 无 commit-msg git hook | FAIL |

---

## A3. BEHAVIOR — 行为审计

**AI 是否出现了非预期行为？分两步：机械检查 + 会话审查。**

### 3.1 机械检查

```bash
echo "=== A3: 行为审计 ==="
cd "$(git rev-parse --show-toplevel)"

# 1. 未提交改动 — 可能是直接 Edit/Write 绕过 fwp-build
echo "--- 未提交改动 ---"
DIRTY=$(git status --porcelain)
if [ -n "$DIRTY" ]; then
  # 检查是否有活跃的 fwp-build session（通过最近 result 文件判断）
  ACTIVE=$(find "/tmp/fw-flywheel/$PROJECT/" -name "result-*.md" -mmin -10 2>/dev/null | wc -l)
  [ "$ACTIVE" -eq 0 ] && echo "FAIL: 有未提交改动且无活跃 fwp-build" || echo "PASS: 有活跃 fwp-build"
else echo "PASS: 工作区干净"; fi

# 2. 分支基址 — feature 分支是否从正确的 base 创建
echo "--- 分支基址 ---"
CUR=$(git branch --show-current)
if echo "$CUR" | grep -q "feature/issue-"; then
  BASE=$(git merge-base "origin/$DEFAULT_BRANCH" "$CUR" 2>/dev/null)
  HEAD_BASE=$(git rev-parse "origin/$DEFAULT_BRANCH" 2>/dev/null)
  if [ "$BASE" != "$HEAD_BASE" ]; then
    echo "FAIL: $CUR 不基于 origin/$DEFAULT_BRANCH"
  else echo "PASS: $CUR 基于 origin/$DEFAULT_BRANCH"; fi
else echo "SKIP: 非 feature 分支"; fi

# 3. 约束声明完整性 — 所有 skill 是否有"禁止用户交互"
echo "--- 约束声明 ---"
MISSING=$(for s in ~/.claude/skills/fwp-*/SKILL.md ~/.claude/skills/fw-audit/SKILL.md; do
  grep -L "禁止用户交互" "$s" 2>/dev/null
done)
[ -z "$MISSING" ] && echo "PASS: 全部 skill 含禁止交互约束" || echo "WARN: 缺少约束: $(echo "$MISSING" | xargs basename)"

# 4. subagent 链路 — ctx 无对应 status = 链断裂
echo "--- subagent 链路 ---"
CTX_COUNT=$(ls "/tmp/fw-flywheel/$PROJECT/"ctx-*.md 2>/dev/null | wc -l)
STATUS_COUNT=$(ls "/tmp/fw-flywheel/$PROJECT/"status-*.md 2>/dev/null | wc -l)
[ "$CTX_COUNT" -eq "$STATUS_COUNT" ] && echo "PASS: ctx/status 成对" || echo "WARN: ctx=$CTX_COUNT vs status=$STATUS_COUNT (有断裂)"

# 5. git 操作频次 — 是否有异常高频操作
echo "--- git 操作 ---"
REFLOG_COUNT=$(git reflog --since="7 days ago" --format="%s" 2>/dev/null | wc -l)
echo "7日 reflog: $REFLOG_COUNT 条"
AMENDS=$(git reflog --since="7 days ago" --format="%s" 2>/dev/null | grep -c "amend" || echo 0)
[ "$AMENDS" -gt 5 ] && echo "WARN: 7日内 $AMENDS 次 amend (>5)" || echo "PASS: amend $AMENDS 次"
```

### 3.2 会话审查（LLM 补充）

机械检查覆盖了 5 项，剩余 1 项需要分析当前会话上下文：

| 检查项 | 判定标准 |
|--------|---------|
| AskUserQuestion | 回顾当前会话 tool call 历史，出现即 FAIL |

### 3.3 汇总

| 检查项 | 检测方式 | 判定 |
|--------|---------|------|
| 未提交改动 | bash: git status | 有改动且无活跃 fwp-build → FAIL |
| 分支基址 | bash: git merge-base | 非 origin/DEFAULT_BRANCH → FAIL |
| 约束声明 | bash: grep "禁止用户交互" | 缺失 → WARN |
| subagent 链路 | bash: ctx vs status 计数 | 不匹配 → WARN |
| git 操作频次 | bash: reflog | amend >5/7天 → WARN |
| AskUserQuestion | LLM: 会话审查 | 出现 → FAIL |

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
4. 所有 WARN → 生成低优先级 WARNING milestone → Agent(fwp-plan)（不等待升级，即时派发）
5. WARN 连续 2 轮未解决 → 升级为 FAIL

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
  Agent(description: "fwp-plan: 修复飞轮/${dim}", subagent_type: "general-purpose",
    prompt: "milestone: /tmp/fw-flywheel/$PROJECT/milestone-audit-${dim}.md")
done
```

## 约束

- **审计飞轮，不审计项目**：项目代码质量由 fwp-inspect Tier 2 负责
- **安全问题即时 FAIL**：门禁缺失/绕过 → 立即 FAIL，不等老化
- **A3 依赖会话上下文**：行为审计需分析当前对话 tool call 历史
- **禁止用户交互**：严禁 `AskUserQuestion`
