---
name: lp-mr
description: 第二层飞轮——MR 全生命周期管理：提交、创建、监控、分配修复
---

# LP-MR（第二层 · 用户级）

MR (Merge Request) 生命周期管理。负责所有 git 和 MR 操作，不直接写代码。

> **用户级 skill**：跨所有项目生效。`gh` 命令自动检测当前仓库。顺序开发模式，不使用 worktree。

## 上下文检测

```bash
WORKSPACE=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$WORKSPACE"
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
DEFAULT_BRANCH=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's|.*/||' || echo "master")
echo "[lp-mr] WORKSPACE=$WORKSPACE REPO=$REPO BRANCH=$DEFAULT_BRANCH"
```

## 调用方式

```text
/lp-mr <issue-number>
/lp-mr <issue-number> --resume
```

**`--resume`**: 从 GitHub 状态恢复。查询 PR 状态、fix_round，决定恢复动作。可恢复：`BLOCKED_CI` 且 `fix_round < 3`；不可恢复：`CONFLICT`、`API_ERROR`。

## 流程

### 1. 启动开发

**1a. 准备干净的开发基址** — 始终从 `origin/<默认分支>` 最新 commit 创建 feature 分支：

```bash
cd "$(git rev-parse --show-toplevel)"
DEFAULT_BRANCH=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's|.*/||' || echo "master")
git checkout "$DEFAULT_BRANCH"
git fetch origin "$DEFAULT_BRANCH"
git pull --ff-only origin "$DEFAULT_BRANCH"
# 检查依赖 issue 是否已合入
for dep in <依赖 issue 编号列表>; do
  state=$(gh issue view "$dep" --json state --jq '.state')
  if [ "$state" != "CLOSED" ]; then echo "WARNING: dependency #$dep is still $state"; fi
done
git checkout -b feature/issue-<N>
```

> **规则**：feature 分支**只能**从 `origin/<默认分支>` 创建，禁止从其他 feature 分支派生。

**1b. 写入上下文文件 + 通过 subagent 调用第三层**：

```bash
# 写入开发上下文文件（供 lp-dev 读取）
mkdir -p /tmp/lp-flywheel
FIX_ROUND=$(cat .claude/state/issue-<N>.fix_round 2>/dev/null || echo 0)
cat > "/tmp/lp-flywheel/ctx-<N>.md" << EOF
# Issue #<N> 开发上下文

| 字段 | 值 |
|------|-----|
| issue | #<N> |
| 分支 | feature/issue-<N> |
| 基址 | origin/$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's|.*/||' || echo master) |
| fix_round | $FIX_ROUND |
$(if [ "$FIX_ROUND" -gt 0 ]; then echo "| 上次 commit | $(git log -1 --format='%h (%s)') |"; fi)
$(if [ "$FIX_ROUND" -gt 0 ]; then echo "| 上次改动 | $(git diff --stat HEAD~1 | tail -1) |"; fi)

## Issue 内容

$(gh issue view <N> 2>/dev/null || echo "(无法获取)")
EOF
```

```text
Agent(subagent_type="general-purpose", description="Dev issue #<N>",
  prompt="/lp-dev <N>

上下文文件: /tmp/lp-flywheel/ctx-<N>.md
分支: feature/issue-<N>（已从 origin/<默认分支> 创建）。请在此分支上开发，不要切回主分支。")
```

subagent 退出后：
1. 检查终端输出中的 `---HANDOFF---` ... `---HANDOFF_END---` 信号块
2. 读取 `/tmp/lp-flywheel/result-<N>.md` 获取改动摘要
3. `DEV_DONE=<branch>` → 继续步骤 2；`FAIL_DONE=<error-type>` → 错误处理

### 2. commit + push + 创建 MR

```bash
cd "$(git rev-parse --show-toplevel)"
BRANCH="feature/issue-<N>"
git add -A
git commit -m "<type>: <description> (closes #<N>)"
git push origin "$BRANCH"
MR_URL=$(gh pr create --title "<type>: <description> (closes #<N>)" --body "$(cat <<'EOF'
Closes #<N>

## Summary

## Test plan

- [ ] lint check passes
- [ ] tests pass
EOF
)")
MR_NUMBER=$(echo "$MR_URL" | grep -oE '[0-9]+$')
bash scripts/watch-pr.sh "$MR_NUMBER" && gh pr merge "$MR_NUMBER" --squash --delete-branch
```

### 3. 监控 MR

```bash
bash scripts/watch-pr.sh <mr-number>
```

> 若项目无 `scripts/watch-pr.sh`，使用内联轮询：每 30 秒 `gh pr view <N> --json statusCheckRollup,mergedAt` 直到 CI green/timeout。

### 4. 响应状态

| 退出码 | 含义 | 动作 |
|--------|------|------|
| 0 | CI green | `gh pr merge --squash --delete-branch` → 清理本地分支 → `ISSUE_DONE` |
| 1 | CI failure | 写 `BLOCKED_CI` → 收集 CI 日志 → 检查 fix_round |
| 2 | timeout | CI green → 合入；否则 → 人工介入 |

**重试上限**：

```bash
fix_round=$(cat .claude/state/issue-<N>.fix_round 2>/dev/null || echo 0)
if [ "$fix_round" -ge 3 ]; then
  echo "BLOCKED_CI" > .claude/state/issue-<N>.status
  echo "ERROR: fix_round 已达上限 (3 次)，需人工介入"
  exit 1
fi
```

### 5. 收集 CI 日志 + 分配修复

拉取 CI 失败日志，**写入文件**（截断 ≤ 200 行），递增 fix_round：

```bash
mkdir -p /tmp/lp-flywheel
FIX_ROUND=$(( $(cat .claude/state/issue-<N>.fix_round 2>/dev/null || echo 0) + 1 ))
echo "$FIX_ROUND" > .claude/state/issue-<N>.fix_round

# 拉取 CI 失败详情
FAILING=$(gh pr view <mr-number> --json statusCheckRollup --jq '
  [.statusCheckRollup[] | select(.status == "COMPLETED" and
    (.conclusion == "FAILURE" or .conclusion == "TIMED_OUT"))] |
  .[] | "\(.name): \(.conclusion)"
')

# 写入 CI 文件（截断保护：≤200 行）
LINES=$(echo "$FAILING" | wc -l)
if [ "$LINES" -gt 200 ]; then
  echo "$FAILING" | head -100 > "/tmp/lp-flywheel/ci-<mr-number>.md"
  echo "" >> "/tmp/lp-flywheel/ci-<mr-number>.md"
  echo "... (省略 $((LINES - 200)) 行) ..." >> "/tmp/lp-flywheel/ci-<mr-number>.md"
  echo "" >> "/tmp/lp-flywheel/ci-<mr-number>.md"
  echo "$FAILING" | tail -50 >> "/tmp/lp-flywheel/ci-<mr-number>.md"
else
  echo "$FAILING" > "/tmp/lp-flywheel/ci-<mr-number>.md"
fi

# 更新上下文文件附加 fix_round 信息
cat >> "/tmp/lp-flywheel/ctx-<N>.md" << EOF

## CI 修复轮次 $FIX_ROUND/3

CI 失败详情见 /tmp/lp-flywheel/ci-<mr-number>.md
EOF
```

通过 subagent 调用修复（prompt 只传文件路径，不传 CI log）：

```text
Agent(subagent_type="general-purpose", description="Fix MR #<mr>",
  prompt="/lp-dev <N> --fix <mr-number>

上下文: /tmp/lp-flywheel/ctx-<N>.md
CI 日志: /tmp/lp-flywheel/ci-<mr-number>.md")
```

等待 `FIX_DONE=<BRANCH>` 信号 + 读取 `/tmp/lp-flywheel/result-<N>.md`，进入步骤 6。

### 6. commit fix + push 同一分支

```bash
BRANCH="feature/issue-<N>"
rm -f .claude/state/issue-<N>.status
echo 0 > .claude/state/issue-<N>.fix_round
git add -A
git commit -m "fix: address CI failure (#<N>)"  # 不加 closes，避免重复关闭
git push origin "$BRANCH"
```

### 7. 回到监控

回到步骤 3。

## 状态机

```text
[开始] → 从 origin/<默认分支> 开分支 → /lp-dev → commit+push+mr create
    → watch-pr
        ├─ CI green → gh pr merge --squash → 切回主分支 → 删除本地分支 → [done]
        ├─ CI fail → 写 BLOCKED_CI → fix_round < 3? → 收集日志 → /lp-dev --fix → [WAIT: FIX_DONE] → 清除状态 → commit+push → watch-pr
        │         └─ fix_round >= 3 → 写 BLOCKED_CI → [人工介入]
        └─ timeout → CI green → 合入; 否则 → 人工介入
```

## 重试上限

| 计数器 | 上限 | 触发条件 | 超限状态 | 重置时机 |
|--------|------|---------|---------|---------|
| `fix_round` | 3 | CI-failure → lp-dev --fix | `BLOCKED_CI` | 修复成功 push 后 |

## 约束

- 负责**所有** git 操作和 gh 操作
- **禁止直接修改代码**：所有代码修改必须通过 `/lp-dev` subagent 完成
- **CI failure 交给 lp-dev**：调用 `/lp-dev <N> --fix` 修复
- **feature 分支必须从 origin/<默认分支> 创建**（步骤 1a），禁止从其他分支派生
- **禁止用户交互**：严禁 `AskUserQuestion`；分支/MR/CI/merge 全流程自动执行

## 状态管理

状态文件存储在 `.claude/state/`（项目目录下）：

| 文件 | 用途 |
|------|------|
| `.claude/state/issue-<N>.status` | `MERGED` / `BLOCKED_CI` / `CONFLICT` / `ABANDONED` / `API_ERROR` |
| `.claude/state/issue-<N>.fix_round` | CI 修复重试计数 |

### --resume 逻辑

```bash
cd "$(git rev-parse --show-toplevel)"
# 1. 获取关联 PR
PR_NUMBER=$(gh pr list --state all --json number,headRefName --jq ".[] | select(.headRefName == \"feature/issue-<N>\") | .number" | head -1)
# 2. 获取 PR 状态
PR_STATE=$(gh pr view "$PR_NUMBER" --json state,statusCheckRollup --jq '{state, checks: [.statusCheckRollup[] | select(.status == "COMPLETED" and .conclusion == "FAILURE")]}')
# 3. 推断当前状态: NO_MR | MERGED | BLOCKED_CI | PENDING
# 4. 推断 fix_round: PR 中 "fix:" 开头的 commit 数量
```

### 清理流程

MR merged 后执行（分支清理 + 状态写入 + **临时文件清理**）：

```bash
cd "$(git rev-parse --show-toplevel)"
DEFAULT_BRANCH=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's|.*/||' || echo "master")
git checkout "$DEFAULT_BRANCH"
git fetch origin "$DEFAULT_BRANCH"
git reset --hard "origin/$DEFAULT_BRANCH"
git fetch --prune
# 删除远程残留分支
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
gh api "repos/$REPO/git/refs/heads/feature/issue-<N>" -X DELETE 2>/dev/null || true
# 删除本地分支
git branch -D feature/issue-<N> 2>/dev/null || true
# 写入状态
mkdir -p .claude/state
echo "MERGED" > .claude/state/issue-<N>.status
rm -f .claude/state/issue-<N>.fix_round
# 清理 /tmp/lp-flywheel 临时文件
rm -f "/tmp/lp-flywheel/ctx-<N>.md" \
      "/tmp/lp-flywheel/ci-<mr-number>.md" \
      "/tmp/lp-flywheel/result-<N>.md" \
      "/tmp/lp-flywheel/diff-<N>.md"
echo "[CLEANUP] /tmp/lp-flywheel/issue-<N> 临时文件已清理"
```

## 错误处理

当 lp-dev 返回 `FAIL_DONE=<error-type>` 信号时：

| Error type | 含义 | 处理方式 |
|-----------|------|---------|
| SIMPLIFY_UNFIXABLE | simplify 无法自动修复 | 人工介入，记录到 issue |
| CONFLICT_UNRESOLVABLE | merge conflict 无法解决 | 写 `CONFLICT`，人工介入 |
| UNKNOWN | 其他异常 | 记录日志，人工介入 |
