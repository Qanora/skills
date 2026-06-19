---
name: fwp-setup
description: [项目] 初始化——创建 GitHub 仓库、配置 CI/CD、分支保护、代码审查、Issue/PR 模板、标签、脚本，一键让飞轮体系就绪
---

# FWP-SETUP（项目初始化 · 用户级）

全新 GitHub 项目的完整初始化。创建仓库、配置 CI/CD 门禁、代码质量工具、模板、标签、辅助脚本。

> **用户级 skill**：在任何目录下运行，创建新项目并使其飞轮就绪。

## 调用方式

```text
/fwp-setup <repo-name> [--owner <owner>] [--python <3.11|3.12>] [--branch <main|master>] [--dry-run]
/fwp-setup --resume              # 从断点恢复
```

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `<repo-name>` | (必填) | GitHub 仓库名，同时作为项目目录名和 package 名 |
| `--owner` | 当前 `gh` 登录用户 | GitHub org 或用户名 |
| `--python` | `3.11` | Python 版本 |
| `--branch` | `master` | 默认分支名 |
| `--dry-run` | — | 只输出计划，不执行 |

## 初始化阶段

### 阶段 1：仓库创建（幂等）

```bash
OWNER="${OWNER:-$(gh auth status 2>&1 | grep -oP 'Logged in to github.com as \K\w+' || echo '')}"
REPO_NAME="<repo-name>"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-master}"

if ! gh repo view "$OWNER/$REPO_NAME" >/dev/null 2>&1; then
  gh repo create "$OWNER/$REPO_NAME" --private --clone
else
  echo "[SKIP] 仓库已存在"
  gh repo clone "$OWNER/$REPO_NAME" .
fi
cd "$REPO_NAME"

# 初始化默认分支（空仓库时）
if [ -z "$(git log 2>/dev/null)" ]; then
  git checkout -b $DEFAULT_BRANCH
  echo "# $REPO_NAME" > README.md
  git add README.md && git commit -m "chore: initial commit" && git push -u origin $DEFAULT_BRANCH
fi
```

### 阶段 2：分支保护

```bash
REPO="$OWNER/$REPO_NAME"
gh api "repos/$REPO/branches/$DEFAULT_BRANCH/protection" -X PUT \
  -F required_pull_request_reviews='{"dismiss_stale_reviews":false,"require_code_owner_reviews":false,"required_approving_review_count":0}' \
  -F required_status_checks='{"strict":true,"contexts":["gitleaks","commit-msg","tests"]}' \
  -F enforce_admins=false -F restrictions=null \
  2>/dev/null || echo "[WARN] 无 admin 权限，请手动配置分支保护"
```

### 阶段 3：CI/CD 工作流

创建 `.github/workflows/test.yml`（gitleaks → commit-msg 校验 → pytest）和 `.github/workflows/auto-merge.yml`（自动 squash merge）。

> 完整内容见源模板 `~/.claude/skills/fwp-setup/SKILL.md` 的阶段 3。

### 阶段 4：代码质量工具

创建 `.coderabbit.yaml`、`.gitleaks.toml`、`.github/dependabot.yml`。

### 阶段 5：模板

创建 `.github/PULL_REQUEST_TEMPLATE.md`、`.github/ISSUE_TEMPLATE/bug.yml`、`.github/ISSUE_TEMPLATE/enhancement.yml`。

### 阶段 6：Triage 标签

```bash
LABELS=(
  "needs-triage:#8B5CF6:Issue needs maintainer assessment"
  "needs-info:#3B82F6:Waiting for more information"
  "ready-for-agent:#10B981:Well-defined, ready for AFK agent"
  "ready-for-human:#F59E0B:Requires human implementation"
  "wontfix:#6B7280:Will not be addressed"
  "bug:#EF4444:Bug report"
  "enhancement:#22C55E:Feature request"
  "dependencies:#8B5CF6:Dependency updates"
)
for label_spec in "${LABELS[@]}"; do
  name="${label_spec%%:*}"
  color="${label_spec#*:}"; color="${color%%:*}"
  desc="${label_spec##*:}"
  gh label list --json name --jq '.[].name' | grep -qx "$name" && echo "[SKIP] $name" || \
    gh label create "$name" --color "$color" --description "$desc"
done
```

### 阶段 7：辅助脚本

创建 `scripts/` 目录并写入四个脚本：`watch-pr.sh`、`fw-ship-cleanup.sh`、`cleanup-merged-branches.sh`、`commit-msg`。全部执行 `chmod +x scripts/*.sh`。

> 完整脚本内容见源模板。

### 阶段 8：项目配置文件

创建 `pyproject.toml`（ruff + pytest + uv）、`.gitignore`（Python + IDE + Data）、`CLAUDE.md`（飞轮表 + git 规范 + scripts 索引）。

### 阶段 9：验证 + 安装 git hook

```bash
# 安装 commit-msg hook
ln -sf ../../scripts/commit-msg .git/hooks/commit-msg

# 初始化 .claude 目录
mkdir -p .claude/state/fwp-inspect .claude/state/fw-audit

# 不需要复制 skills — 飞轮 skills 已是用户级（~/.claude/skills/），全局可用

# 终检清单
echo "=== 初始化验证 ==="
echo "☐ 仓库: gh repo view $OWNER/$REPO_NAME"
echo "☐ 分支保护: Settings → Branches"
echo "☐ CI: .github/workflows/test.yml (gitleaks + commit-msg + tests)"
echo "☐ Auto-merge: .github/workflows/auto-merge.yml"
echo "☐ CodeRabbit: .coderabbit.yaml"
echo "☐ 标签: needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix"
echo "☐ 脚本: scripts/watch-pr.sh, fw-ship-cleanup.sh, cleanup-merged-branches.sh, commit-msg"
echo "☐ Git hook: .git/hooks/commit-msg → scripts/commit-msg"
echo "☐ pyproject.toml  +  .gitignore  +  CLAUDE.md"
echo ""
echo "飞轮 skills 已全局安装 (~/.claude/skills/lp-*/)，当前项目可直接使用:"
echo "  /fwp-plan <需求描述>"
echo "  /fwp-ship <issue-number>"
echo "  /fwp-build <issue-number>"
```

## Resume 机制

`/fwp-setup --resume` 逐阶段检查已有文件，从第一个缺失的阶段继续。所有阶段独立幂等。

## 约束

- **幂等性**：所有阶段支持重复运行
- **权限要求**：分支保护需 admin，无权限时自动降级为手动清单
- **不初始化数据**：只创建配置文件，不创建业务代码
- **Python 优先**：CI/配置默认 Python + uv + ruff + pytest
- **不覆盖**：已存在的 pyproject.toml、CLAUDE.md、.gitignore 不覆盖
- **禁止用户交互**：严禁 `AskUserQuestion`；所有阶段自动执行，参数通过命令行提供；权限不足自动降级并打印手动清单
