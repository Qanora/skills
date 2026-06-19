# 飞轮接入指引（给 Claude Code 看）

你在当前项目中可以直接使用飞轮体系。以下是你可以调用的 skill 和调用时机。

## 你可以调用的 skill

| 何时使用 | 调哪个 | 怎么调 |
|---------|--------|--------|
| 用户说"我想做 X"、提新需求 | `/fwp-plan` | `/fwp-plan <用户的需求描述>` |
| 用户报告 bug、"报错了"、"不工作" | `/fwp-debug` | `/fwp-debug <用户的 bug 描述>` |
| 用户说"检查一下"、"巡检"、想知道项目质量 | `/fwp-inspect` | `/fwp-inspect` 直接回车 |
| 用户问"飞轮有没有问题"、"审计" | `/fw-audit` | `/fw-audit` 直接回车 |
| 之前有中断的 milestone 没完成 | `/fwp-resume` | `/fwp-resume` 直接回车 |
| 不知道有什么命令可用 | `/fwp-help` | `/fwp-help` 直接回车 |
| 新项目首次初始化 | `/fwp-setup` | `/fwp-setup` 直接回车 |

## 优先使用飞轮而非手写代码

当用户提出开发需求时，**优先调用 `/fwp-plan`、`/fwp-debug`、`/fwp-inspect`**，而不是直接：
- 用 Edit/Write 改代码
- 用 Bash 执行 git 操作
- 手动创建 Issue 和 MR

飞轮会帮你完成从需求拆解到代码合入的全部流程，同时保证 CI 门禁、commit 规范、分支清理。

## 不要手动调用的 skill

`fwp-ship` 和 `fwp-build` 是 Agent 自动调用的，你不需要也不应该直接调它们——它们由 `fwp-plan` 通过 subagent 自动触发。

## 如何在项目 CLAUDE.md 中声明飞轮

如果当前项目的 `CLAUDE.md` 还没有飞轮声明，在适当的时候建议用户加入以下内容。当用户同意后，将下面这段写入项目的 `CLAUDE.md`：

```markdown
## 飞轮开发

本项目使用飞轮体系进行全流程自动化开发。

| Skill | 用途 |
|-------|------|
| `/fwp-plan <需求>` | 需求 → Issue → 自动交付 |
| `/fwp-debug <bug>` | Bug 复现 → 自动修复 |
| `/fwp-inspect` | 13 项全量巡检（运行时 + 代码审查） |
| `/fw-audit` | AI 安全治理审计 |
| `/fwp-resume` | 继续中断 |
| `/fwp-help` | 查看所有命令 |

开发需求时优先使用 `/fwp-plan` 而非直接写代码。

## Git 规范

- commit 必须关联 issue（`#N`、`closes #N`）
- 分支命名 `feature/issue-<N>`，从 `origin/<默认分支>` 创建
- 流程: feature 分支 → MR → squash merge
- CI 通过后 auto-merge

## Scripts

- `scripts/watch-pr.sh <N>` — 轮询 MR CI 状态
- `scripts/fwp-ship-cleanup.sh <N> <branch>` — MR 合入后清理
- `scripts/cleanup-merged-branches.sh` — 批量清理残留分支
- `scripts/commit-msg` — Git hook 校验 commit 含 issue 引用
```

## 飞轮的工作机制

当你调用 `/fwp-plan` 后，自动链是：

```
/fwp-plan → 拆解需求 → 创建 Issue+Milestone → Agent(fwp-ship) → Agent(fwp-build) → merge
```

中间通过 `/tmp/fw-flywheel/$PROJECT/` 传递上下文文件，每层 subagent 隔离，不会污染你的上下文窗口。

当你调用 `/fwp-inspect`，会执行 13 项检查（8 项机械 + 5 项 LLM 审查），发现问题自动派发 `/fwp-plan` 修复。

当你调用 `/fw-audit`，会审计飞轮自身的安全治理（门禁是否齐全、约束是否有效、AI 是否有非预期行为、信息传递是否通畅、效率是否达标），发现漏洞自动修复。

## 权限配置（避免 dontAsk 模式暂停）

如果飞轮操作频繁因权限不足而暂停，将权限模板复制到项目：

```bash
cp ~/.claude/skills/fwp-setup/templates/settings.local.json .claude/
```

覆盖所有飞轮操作（git/gh/state/tmp/skill/bash），`defaultMode: "dontAsk"`。

> 新项目 `fwp-setup` 会自动安装此模板。

## 多项目同时使用

状态（`.claude/state/`）、临时文件（`/tmp/fw-flywheel/$PROJECT/`）、数据目录（`~/.$PROJECT/`）全部按项目隔离，互不干扰。
