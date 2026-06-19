---
name: lp-dev
description: 第三层飞轮——纯本地开发：实现/修复 → 本地验证 → simplify。不做任何 git 或 MR 操作。
---

# LP-DEV（第三层 · 用户级）

纯本地开发管理。只负责写代码和验证，**不做 commit/push/MR 等任何 git 操作**（全部由第二层负责）。

> **用户级 skill**：跨所有项目生效。自动检测当前项目上下文，无需安装配置。

## 上下文检测

执行前首先检测当前项目：

```bash
WORKSPACE=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$WORKSPACE"
DEFAULT_BRANCH=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's|.*/||' || echo "master")
echo "[lp-dev] WORKSPACE=$WORKSPACE BRANCH=$DEFAULT_BRANCH"
```

## 调用方式

```text
/lp-dev <issue-number> [--fix <mr-number>]
```

## 开发模式 (无 `--fix` flag)

### 1. 获取需求

```bash
cd "$(git rev-parse --show-toplevel)"
gh issue view <N>
```

### 2. 强制同步默认分支（阻塞步骤）

```bash
cd "$(git rev-parse --show-toplevel)"
BRANCH=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's|.*/||' || echo "master")
git fetch origin "$BRANCH"
git checkout "$BRANCH"
git reset --hard "origin/$BRANCH"
git log -1 --oneline "origin/$BRANCH"
```

### 3. 检查分支冲突（阻塞步骤，自动清理）

```bash
cd "$(git rev-parse --show-toplevel)"
BRANCH="feature/issue-<N>"
# 自动清理本地旧分支
if git branch | grep -q "$BRANCH"; then git branch -D "$BRANCH"; fi
# 自动清理远程旧分支
if git branch -r | grep -q "origin/$BRANCH"; then
  gh api "repos/$(gh repo view --json nameWithOwner -q .nameWithOwner)/git/refs/heads/$BRANCH" -X DELETE
fi
```

### 4. 创建新分支

```bash
BRANCH="feature/issue-<N>"
git checkout -b "$BRANCH"
git log -1 --oneline
```

### 5. TDD 实现（红→绿→重构）

严格遵循 TDD：

- **RED**: 先写失败测试覆盖正常路径、边界条件、异常情况
- **GREEN**: 最小实现使测试通过，运行全量测试确认全绿
- **REFACTOR**: 消除重复、改善可读性，保持测试全绿

### 6. 300 行约束检查

```bash
BRANCH=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's|.*/||' || echo "master")
git diff --shortstat "origin/$BRANCH"
```

超过 300 行输出 `⚠️ 当前改动超过 300 行，建议考虑拆分为多个 issue`（soft constraint，不阻塞）。

### 7. 本地验证（全部阻塞步骤）

```bash
# 代码质量 — 检测项目使用的 linter
cd "$(git rev-parse --show-toplevel)"
if command -v ruff &>/dev/null && [ -f pyproject.toml ]; then
  ruff check . && ruff format --check .
elif command -v eslint &>/dev/null; then
  npx eslint . && npx prettier --check .
fi

# 全量测试 — 检测项目使用的测试框架
if [ -f pyproject.toml ]; then
  python -m pytest tests/ -v
elif [ -f package.json ]; then
  npx jest --verbose
fi
```

### 8. Simplify（启动新 agent）

```
Agent(subagent_type="claude", prompt="执行 /simplify 对当前改动进行代码审查")
```

修复所有发现的问题，重复直到 simplify 返回无问题。

### 9. 输出 Handoff

成功：
```text
---HANDOFF---
DEV_DONE=feature/issue-<N>
---HANDOFF_END---
```

失败：
```text
---HANDOFF---
FAIL_DONE=<error-type>
---HANDOFF_END---
```

| Error type | 含义 |
|-----------|------|
| SIMPLIFY_UNFIXABLE | simplify 发现问题无法修复 |
| CONFLICT_UNRESOLVABLE | merge conflict 无法解决 |
| UNKNOWN | 其他异常 |

---

## 修复模式 (`--fix <mr-number>`)

由 `/lp-mr` 调用。获取上下文→修复→验证→simplify→退出。**不 commit，不 push。**

### 1. 切换已有分支 + 同步

```bash
cd "$(git rev-parse --show-toplevel)"
BRANCH="feature/issue-<N>"
BRANCH_NAME=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's|.*/||' || echo "master")
git checkout "$BRANCH"
git fetch origin "$BRANCH_NAME"
git merge "origin/$BRANCH_NAME" --no-edit
```

若冲突，自动解决：逐个 Read 冲突文件→识别 `<<<===>>>` 标记→Edit 解决→`git add . && git merge --continue`。无法解决则输出 `FAIL_DONE=CONFLICT_UNRESOLVABLE`。

### 2-6. 修复→验证→Simplify→输出（同开发模式 3-9）

修复模式只修问题，不新增功能，不重构。成功输出 `FIX_DONE=feature/issue-<N>`。

## 约束

- **顺序开发**：一次只处理一个 issue，在主仓库直接开发
- **不做任何 git 操作**：不 add、不 commit、不 push
- **TDD 开发**：严格红→绿→重构
- **全量测试阻塞**：必须全部通过才能 HANDOFF
- **Simplify 阻塞**：问题必须全部修复
- **自动清理分支**：同名旧分支自动删除，不询问
- **零人工中断**：只有 `SIMPLIFY_UNFIXABLE` / `CONFLICT_UNRESOLVABLE` / `UNKNOWN` 才停止
- **禁止用户交互**：严禁 `AskUserQuestion`；测试失败自动重试修复（最多 3 次）
