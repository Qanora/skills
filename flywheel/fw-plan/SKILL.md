---
name: fw-plan
description: [项目] 需求拆解——需求拆解、Issue 创建、依赖分析、批次编排、进度追踪
---

# FW-PLAN（第一层 · 用户级）

Issue 生命周期管理。只负责 issue 层面编排，不直接操作代码或 MR。

> **用户级 skill**：跨所有项目生效。`gh` 命令自动检测当前仓库，无需 `--repo` 参数。

## 上下文检测

```bash
WORKSPACE=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$WORKSPACE"
DEFAULT_BRANCH=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's|.*/||' || echo "master")
echo "[fw-plan] WORKSPACE=$WORKSPACE BRANCH=$DEFAULT_BRANCH"
```

**从文件读取 milestone**（由 fw-inspect 或 fw-audit 写入）：

```bash
# 查找是否有待处理的 milestone 文件
ls /tmp/fw-flywheel/milestone-*.md 2>/dev/null && \
  echo "[fw-plan] 发现 milestone 文件:" && \
  cat /tmp/fw-flywheel/milestone-*.md
```

若存在 `/tmp/fw-flywheel/milestone-*.md`，以此作为需求来源；否则使用用户直接输入的 `<需求描述>`。

## 调用方式

```text
/fw-plan <需求描述>
/fw-plan --resume <milestone-number>
```

## 流程

### 1. 分析需求

优先读取 `/tmp/fw-flywheel/milestone-*.md`，若存在则使用文件中的结构化需求；否则分析用户直接输入的 `<需求描述>`。

### 2. 拆解 Issue

将需求拆成独立、可独立验证的 issue。拆解完成后**自动创建，不询问用户确认**：

```text
## 需求拆解
### Issue #1: <标题>
- 描述: <1-2句话>
- 类型: feature / fix
- 依赖: 无 / 依赖 #N

### Issue #2: ...
---
正在创建 Issue 并开始执行...
```

> **300 行约束（soft）**：单个 issue 预计改动超过 300 行时，在 issue body 中标注 `⚠️ large diff`。不强制拆分，不阻塞执行。

### 3. 创建 Issue + Milestone

**每个需求对应一个 milestone**，issue 创建时关联 milestone。`gh` 自动检测当前仓库：

```bash
cd "$(git rev-parse --show-toplevel)"
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)

# 创建或获取 milestone
MILESTONE=$(gh api "repos/$REPO/milestones" --paginate --jq '.[] | select(.title == "<需求标题>").number' | head -1)
if [ -z "$MILESTONE" ]; then
  MILESTONE=$(gh api "repos/$REPO/milestones" -f title="<需求标题>" -f state="open" --jq '.number')
fi

# 创建 issue 并关联 milestone
gh issue create --title "<title>" --body "<body>" --label "<bug|enhancement>" --milestone "$MILESTONE"
```

### 4. 依赖分析 + 批次规划

#### 4.1 构建依赖图

```text
节点 = Issue 编号
边 A → B = Issue A 依赖 Issue B
```

#### 4.2 环检测

DFS 检测环。若发现环**立即停止**：

```text
❌ 检测到依赖环: Issue #A → Issue #B → Issue #C → Issue #A
请重新拆解需求，消除循环依赖。
```

#### 4.3 批次规划（无环时）

- 无依赖 → 第 1 批次
- 仅依赖第 1 批的 → 第 2 批次
- 以此类推

### 5. 派发执行

批次内 **串行执行**，每个 issue 通过 subagent 交给第二层（完全隔离，不累积上下文）：

```bash
# 写 issue 上下文文件
mkdir -p /tmp/fw-flywheel
cat > "/tmp/fw-flywheel/ctx-<N>.md" << EOF
# Issue #<N>

| 字段 | 值 |
|------|-----|
| issue | #<N> |
| milestone | #<M> |
| 依赖 | <依赖 issue 列表> |
EOF
```

```text
Agent(subagent_type="general-purpose", description="MR issue #<N>",
  prompt="/fw-ship <N>

上下文: /tmp/fw-flywheel/ctx-<N>.md")
```

subagent 退出后，读取状态文件判断结果：

```bash
STATUS=$(cat "/tmp/fw-flywheel/status-<N>.md" 2>/dev/null | grep "状态" | sed 's/.*| //;s/ |.*//')
case "$STATUS" in
  MERGED)     echo "[fw-plan] #<N> 已合入 ✓" ;;
  BLOCKED_CI) echo "[fw-plan] #<N> CI 阻塞，fix_round 超限，需人工介入" && break ;;
  *)          echo "[fw-plan] #<N> 异常: $STATUS" && break ;;
esac
```

状态正常（MERGED）→ 继续下一个 issue；异常 → 停止批次，记录到 milestone comment。

### 6. 查看进度

```bash
gh issue list --state open --limit 20
gh pr list --state open
```

### 7. 关闭 Milestone

所有 issues 已合入 → 关闭 milestone：

```bash
cd "$(git rev-parse --show-toplevel)"
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
gh issue list --state all --milestone "<N>" --json number,state
# 若全部 closed
gh api -X PATCH "repos/$REPO/milestones/<N>" -f state=closed
```

### 8. 交付报告

```text
## 交付报告
- 需求: <原始需求>
- Issue 总数: <N>
- 已合入: <list>
- MR 列表: <list>
- Milestone: #<N> (closed)
```

## 约束

- 仅做 issue 层面编排和追踪
- 不写代码（第三层负责）
- 不操作 MR（第二层负责）
- **禁止用户交互**：Issue 拆解完成后自动创建并派发，严禁 `AskUserQuestion`

---

## 附录 A: Issue Tracker 操作

`gh` CLI 自动检测仓库，无需 `--repo` 参数：

| 操作 | 命令 |
|------|------|
| 创建 issue | `gh issue create --title "..." --body "..."` |
| 查看 issue | `gh issue view <number> --comments` |
| 列出 issues | `gh issue list --state open --json number,title,body,labels` |
| 评论 issue | `gh issue comment <number> --body "..."` |
| 添加/删除 label | `gh issue edit <number> --add-label "..."` / `--remove-label "..."` |
| 关闭 issue | `gh issue close <number> --comment "..."` |

---

## 附录 B: Triage Labels

| Label | 含义 |
|-------|------|
| `needs-triage` | Maintainer 需要评估 |
| `needs-info` | 等待更多信息 |
| `ready-for-agent` | 完整定义，可交给 AFK agent |
| `ready-for-human` | 需要人工实现 |
| `wontfix` | 不处理 |

---

## 附录 C: 状态恢复机制

```text
/fw-plan --resume <milestone-number>
```

查询 milestone 下所有 issues，根据状态推断恢复动作：

| Issue 状态 | MR 状态 | 恢复动作 |
|-----------|---------|---------|
| open, 无 MR | — | 启动 subagent: `/fw-ship <issue>` |
| open, 有 MR | CI_FAILURE | 收集 CI log → subagent: `/fw-ship --resume` |
| open, 有 MR | PENDING | 继续监控 (`watch-pr.sh`) |
| closed | MR merged | 跳过 |
| closed | 无 MR | 跳过 |

恢复流程：

```bash
cd "$(git rev-parse --show-toplevel)"
gh issue list --state all --milestone "<milestone-number>" --json number,state,title
gh pr list --state all --json number,headRefName,state,statusCheckRollup
```
