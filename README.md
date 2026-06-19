# Skills

通用 Claude Code Agent Skill 集合。

## 飞轮体系

6 个用户级 skill 组成从项目初始化到持续交付的全流程自动化闭环。

| 类别 | Skill | 用途 |
|------|-------|------|
| 项目 | fwp-setup | 初始化新项目：仓库、CI、标签、脚本 |
| 项目 | fwp-plan | "我想做 X" → 需求拆解 → Issue → 派发 |
| 项目 | fwp-debug | "我发现 bug Y" → 复现 → 收集证据 → 派发 |
| 项目 | fwp-inspect | 自动巡检项目运行时 → 8 项检查 → 发现问题 |
| 项目 | fwp-resume | 继续之前中断的 milestone |
| 飞轮 | fw-audit | 审计飞轮自身执行质量 → 6 项扣分 → 改进 |
| — | fwp-build | TDD 开发（Agent 自动调用） |
| — | fwp-ship | MR 交付（Agent 自动调用） |

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

