# Skills

通用 Claude Code Agent Skill 集合。

## 飞轮体系

6 个用户级 skill 组成从项目初始化到持续交付的全流程自动化闭环。

| Skill | 用途 |
|-------|------|
| lp-init | 项目初始化：仓库、CI、标签、脚本 |
| lp-up | 引擎观察：执行+分析 → 发现产品缺陷 |
| lp-dp | 飞轮自检：审计飞轮执行 → 发现流程偏差 |
| lp-ms | Issue 编排：拆解 → 依赖分析 → 批次规划 |
| lp-mr | MR 生命周期：git/gh → CI 监控 → 修复派发 |
| lp-dev | 本地开发：TDD → 验证 → simplify → HANDOFF |

## 安装

```bash
cp -r flywheel/lp-* ~/.claude/skills/
```

跨所有项目即刻生效，无需额外配置。

## 目录结构

- `flywheel/README.md` — 架构总览 + 设计原则
- `flywheel/lp-*/SKILL.md` — 各层 skill 定义
- `flywheel/MIGRATION.md` — 从项目级迁移到用户级的对照
- `flywheel/HUMAN_TOUCHPOINTS.md` — 27 个人工参与点分析

