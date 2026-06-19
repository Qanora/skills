---
name: fwp-setup
description: [项目] 初始化——创建 GitHub 仓库、配置 CI/CD、分支保护、代码审查、Issue/PR 模板、标签、脚本，一键让飞轮体系就绪
---

# FWP-SETUP（项目初始化 · 用户级）

全新 GitHub 项目的完整初始化。创建仓库、配置 CI/CD 门禁、代码质量工具、模板、标签、辅助脚本。

> **用户级 skill**：在任何目录下运行，创建新项目并使其飞轮就绪。

## 调用方式

```text
/fwp-setup                 # 自动用当前目录名, 其余全部自动检测
```

无参数、无选项。repo 名 = 目录名，owner = gh 当前用户，Python 版本和分支自动检测。

## 初始化阶段

### 阶段 1：仓库创建（幂等）

```bash
OWNER="${OWNER:-$(gh auth status 2>&1 | grep -oP 'Logged in to github.com as \K\w+' || echo '')}"
REPO_NAME="${1:-$(basename "$(pwd)")}"
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

从 skill 模板复制（而非 LLM 生成，保证一致性）：

```bash
mkdir -p .github/workflows
cp ~/.claude/skills/fwp-setup/templates/test.yml .github/workflows/
cp ~/.claude/skills/fwp-setup/templates/auto-merge.yml .github/workflows/
# 按实际 Python 版本调整
sed -i "s/3\.11/${PYTHON_VERSION}/g" .github/workflows/test.yml
```

模板包含完整的三门禁：gitleaks → commit-msg 校验 → pytest，以及 squash auto-merge。

### 阶段 4：代码质量工具

从模板复制：

```bash
cp ~/.claude/skills/fwp-setup/templates/.coderabbit.yaml .
cp ~/.claude/skills/fwp-setup/templates/.gitleaks.toml .
mkdir -p .github
cp ~/.claude/skills/fwp-setup/templates/dependabot.yml .github/
```

### 阶段 5：模板

从模板复制：

```bash
cp ~/.claude/skills/fwp-setup/templates/PULL_REQUEST_TEMPLATE.md .github/
mkdir -p .github/ISSUE_TEMPLATE
cp ~/.claude/skills/fwp-setup/templates/.github/ISSUE_TEMPLATE/bug.yml .github/ISSUE_TEMPLATE/
cp ~/.claude/skills/fwp-setup/templates/.github/ISSUE_TEMPLATE/enhancement.yml .github/ISSUE_TEMPLATE/
```

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

从 skill 目录复制脚本到项目（脚本是 skill 的一部分，随目录软链自动可用）：

```bash
mkdir -p scripts
# fwp-ship 的脚本
cp ~/.claude/skills/fwp-ship/scripts/watch-pr.sh scripts/
cp ~/.claude/skills/fwp-ship/scripts/fwp-ship-cleanup.sh scripts/
cp ~/.claude/skills/fwp-ship/scripts/cleanup-merged-branches.sh scripts/
# fwp-setup 的脚本
cp ~/.claude/skills/fwp-setup/scripts/commit-msg scripts/
chmod +x scripts/*
```

| 脚本 | 来源 | 用途 |
|------|------|------|
| `watch-pr.sh` | fwp-ship | 轮询 PR CI 状态 |
| `fwp-ship-cleanup.sh` | fwp-ship | MR 合入后原子化清理 |
| `cleanup-merged-branches.sh` | fwp-ship | 批量清理残留分支 |
| `commit-msg` | fwp-setup | Git hook 校验 commit 含 issue 引用 |

### 阶段 8：项目配置文件

创建 `pyproject.toml`（ruff + pytest + uv）、`.gitignore`（Python + IDE + Data）、`CLAUDE.md`（飞轮表 + git 规范 + scripts 索引）。

**安装权限模板**（消除 dontAsk 模式下的权限暂停）：

```bash
mkdir -p .claude
cp ~/.claude/skills/fwp-setup/templates/settings.local.json .claude/
```

覆盖飞轮所有操作：git/gh/state/tmp/skill/bash 工具链，`defaultMode: "dontAsk"`。

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
echo "☐ 脚本: scripts/watch-pr.sh, fwp-ship-cleanup.sh, cleanup-merged-branches.sh, commit-msg"
echo "☐ Git hook: .git/hooks/commit-msg → scripts/commit-msg"
echo "☐ pyproject.toml  +  .gitignore  +  CLAUDE.md"
echo ""
echo "飞轮 skills 已全局安装，当前项目可直接使用:"
echo "  /fwp-plan <需求描述>"
echo "  /fwp-ship <issue-number>"
echo "  /fwp-build <issue-number>"
```

## 约束

- **幂等性**：所有阶段支持重复运行
- **权限要求**：分支保护需 admin，无权限时自动降级为手动清单
- **不初始化数据**：只创建配置文件，不创建业务代码
- **Python 优先**：CI/配置默认 Python + uv + ruff + pytest
- **不覆盖**：已存在的 pyproject.toml、CLAUDE.md、.gitignore 不覆盖
- **禁止用户交互**：严禁 `AskUserQuestion`；所有阶段自动执行，参数通过命令行提供；权限不足自动降级并打印手动清单
