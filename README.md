# Skills

通用 Claude Code Agent Skill 集合。

## 飞轮体系

6 个用户级 skill 组成从项目初始化到持续交付的全流程自动化闭环。

| Skill | 用途 |
|-------|------|
| fw-setup | 项目初始化：仓库、CI、标签、脚本 |
| fw-inspect | 引擎巡检：8 条固定检查项 → PASS/FAIL/WARN |
| fw-audit | 飞轮审计：6 条固定审计项 → 扣分制评分 |
| fw-plan | Issue 编排：拆解 → 依赖分析 → 批次规划 |
| fw-ship | MR 交付：git/gh → CI 监控 → 修复派发 |
| fw-debug | Bug 入口：复现→收集证据→创建 issue→派发 |
| fw-build | TDD 开发：红→绿→重构 → simplify → HANDOFF |

## 安装

```bash
git clone https://github.com/Qanora/skills.git
cd skills
./install.sh                 # 软链安装
./install.sh --dry-run       # 预览
./install.sh --uninstall     # 卸载
```

软链 `~/.claude/skills/lp-*/SKILL.md` → `skills/flywheel/lp-*/SKILL.md`。修改任一端自动同步。

## 目录结构

- `install.sh` — 一键软链安装/卸载
- `flywheel/README.md` — 架构总览 + 设计原则
- `flywheel/lp-*/SKILL.md` — 各层 skill 定义
- `flywheel/MIGRATION.md` — 从项目级迁移到用户级的对照
- `flywheel/HUMAN_TOUCHPOINTS.md` — 27 个人工参与点分析

