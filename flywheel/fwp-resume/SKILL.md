---
name: fwp-resume
description: 恢复中断——自动检测未完成的 milestone/issue/state，继续飞轮执行
---

# FWP-RESUME（恢复中断 · 用户级）

自动检测当前项目中未完成的飞轮任务，从中断点继续。

> **用户级 skill**：跨项目生效。替代各 skill 的 `--resume` 参数，统一入口。

## 上下文检测

```bash
WORKSPACE=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$WORKSPACE"
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
echo "[fwp-resume] WORKSPACE=$WORKSPACE REPO=$REPO"
```

## 调用方式

```text
/fwp-resume                       # 自动检测并继续
/fwp-resume --status              # 只查看状态，不继续
/fwp-resume --milestone <N>       # 恢复指定 milestone
```

## 流程

### 1. 扫描未完成任务

```bash
cd "$(git rev-parse --show-toplevel)"
echo "=== 飞轮状态扫描 ==="

# 1a. 检查 .claude/state/ 中的中断状态
echo "--- 本地 state ---"
find .claude/state/ -name "*.status" -exec echo "{}: $(cat {})" \; 2>/dev/null || echo "(无)"

# 1b. 检查 fix_round 非零的进行中 issue
echo "--- 进行中修复 ---"
find .claude/state/ -name "*.fix_round" -exec sh -c 'v=$(cat {}); [ "$v" -gt 0 ] 2>/dev/null && echo "{}: fix_round=$v"' \; 2>/dev/null || echo "(无)"

# 1c. 检查 fwp-inspect findings
echo "--- fw-inspect ---"
cat .claude/state/fwp-inspect/findings.json 2>/dev/null | jq '[.findings[] | select(.status=="open")] | length' 2>/dev/null || echo "0 条 open"

# 1d. 检查 fw-audit scores
echo "--- fw-audit ---"
cat .claude/state/fw-audit/skill_scores.json 2>/dev/null | jq '.skills // {}' 2>/dev/null || echo "(无)"

# 1e. 检查 GitHub 上未关闭的 milestone
echo "--- GitHub milestones ---"
gh api "repos/$REPO/milestones" --jq '.[] | select(.state=="open") | "milestone #\(.number): \(.title) (\(.open_issues) open)"' 2>/dev/null || echo "(无)"

# 1f. 检查残留 feature 分支
echo "--- 残留分支 ---"
git branch | grep "feature/issue-" | sed 's/^[* ]*//' || echo "(无)"
```

### 2. 生成恢复计划

根据扫描结果，按优先级排列待恢复任务：

```text
## 恢复计划

### 🔴 阻塞项（需立即处理）
| 类型 | ID | 状态 | 恢复动作 |
|------|-----|------|---------|
| issue | #42 | BLOCKED_CI, fix_round=2 | fwp-ship 42 --resume |
| issue | #28 | .fix_round=1, 无 .status | fwp-ship 28 --resume |

### 🟡 进行中
| 类型 | ID | 状态 | 恢复动作 |
|------|-----|------|---------|
| milestone | #3 | 3/5 issues open | fwp-plan --resume 3 |

### 🟢 可清理
| 类型 | 详情 | 动作 |
|------|------|------|
| 分支 | feature/issue-15 (已 merged) | git branch -D |
| state | issue-15.fix_round (7 天前) | rm |
```

### 3. 执行恢复

按优先级顺序，对每个待恢复项启动对应的 subagent：

```text
# 对每个 BLOCKED_CI issue
Agent(subagent_type="fwp-ship", prompt="/fwp-ship <N> --resume")

# 对每个 open milestone
Agent(subagent_type="fwp-plan", prompt="/fwp-plan --resume <M>")
```

串行执行，一个完成后读取 status 文件确认结果再继续下一个。

### 4. 恢复完成报告

```text
## FW-RESUME 完成报告

| 任务 | 状态 | 结果 |
|------|------|------|
| issue #42 | ✅ | CI fixed, MR merged |
| issue #28 | ✅ | 开发完成, MR #67 created |
| milestone #3 | ⏳ | 2/5 issues 已恢复, 3 个 pending |
```

## 约束

- **只恢复，不新建**：不创建新的 issue/milestone，只继续未完成的
- **串行恢复**：按优先级逐个处理，避免上下文冲突
- **幂等**：重复运行不会重复操作（通过 state 文件判断）
- **禁止用户交互**：严禁 `AskUserQuestion`；扫描结果直接执行
