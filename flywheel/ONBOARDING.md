# 新项目接入飞轮 — CLAUDE.md 指引

飞轮 skill 已是用户级安装（`~/.claude/skills/fwp-*/`、`fw-audit/`），在所有项目中直接可用。只需在项目的 `CLAUDE.md` 中引用即可让 Claude Code 主动使用飞轮。

---

## 推荐 CLAUDE.md 模板

```markdown
# <项目名>

<一句话描述>

## 飞轮开发

本项目使用飞轮体系进行全流程自动化开发。所有飞轮 skill 已安装为用户级。

| Skill | 用途 | 调用方 |
|-------|------|--------|
| `/fwp-setup` | 初始化项目（仅首次） | 你 |
| `/fwp-plan <需求>` | "我想做 X" → Issue → 自动交付 | 你 |
| `/fwp-debug <bug>` | "我发现 bug" → 复现 → 自动修复 | 你 |
| `/fwp-inspect` | 13 项全量巡检（运行时 + 代码审查） | 你 |
| `/fw-audit` | AI 安全治理审计（5 维度） | 你 |
| `/fwp-resume` | 继续中断的 milestone | 你 |
| `/fwp-help` | 查看所有飞轮命令 | 你 |
| `fwp-ship` | MR 交付（git/gh/CI） | fwp-plan 自动 |
| `fwp-build` | TDD 开发（红→绿→重构→HANDOFF） | fwp-ship 自动 |

**启动飞轮时，优先使用 `/fwp-plan`、`/fwp-debug`、`/fwp-inspect`，而非直接手写代码。**

## 命令接口

<CLI> <command>

## Scripts

| 脚本 | 用途 |
|------|------|
| `scripts/watch-pr.sh <N>` | 轮询 MR CI 状态 |
| `scripts/fwp-ship-cleanup.sh <N> <branch>` | MR 合入后原子化清理 |
| `scripts/cleanup-merged-branches.sh` | 批量清理已合并残留分支 |
| `scripts/commit-msg` | Git hook — 强制 commit 关联 issue |

## Git 规范

- **commit**: 必须关联 issue（`#N`、`closes #N`）
- **分支**: `feature/issue-<N>`，从 `origin/<默认分支>` 创建
- **流程**: feature 分支 → MR → squash merge
- **门禁**: CI 通过 → auto-merge
- **清理**: MR 合入后 fwp-ship 自动删除本地分支

## Triage Labels

`needs-triage` | `needs-info` | `ready-for-agent` | `ready-for-human` | `wontfix`
```

---

## 接入步骤

### 1. 确保飞轮已安装

```bash
ls ~/.claude/skills/fwp-help
# 若不存在:
git clone https://github.com/Qanora/skills.git /tmp/skills
cd /tmp/skills && ./install.sh
```

### 2. 编辑项目 CLAUDE.md

将上面的模板复制到 `<项目根目录>/CLAUDE.md`，替换 `<项目名>`、`<一句话描述>`、`<CLI>`。

### 3. 初始化项目（仅新项目）

```text
/fwp-setup
```

自动创建：GitHub 仓库、CI/CD、分支保护、CodeRabbit、Issue/PR 模板、Triage 标签、辅助脚本。

### 4. 安装 git hook

```bash
ln -sf ../../scripts/commit-msg .git/hooks/commit-msg
```

### 5. 开始使用

```text
/fwp-plan 添加第一个功能
/fwp-inspect
```

---

## 常见问题

**Q: fwp-ship 和 fwp-build 在 CLI 里敲了没反应？**

它们不是用户命令——由 fwp-plan 通过 subagent 自动调用。你只需要 `/fwp-plan <需求>`。

**Q: 不用飞轮，直接手写代码可以吗？**

可以，但会绕过所有安全检查（CI 门禁、commit 规范、fix_round 上限、HANDOFF 协议）。fw-audit 会发现并扣分。

**Q: 多项目同时用会冲突吗？**

不会。状态（`.claude/state/`）、临时文件（`/tmp/fw-flywheel/$PROJECT/`）、数据目录（`~/.$PROJECT/`）全部按项目隔离。
