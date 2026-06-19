---
name: flywheel-universal-skills
description: 通用四层飞轮开发体系 — 从 pp_tracer 和 alpha-screener 提炼的项目无关 skill 组合
metadata:
  type: project
---

# 通用四层飞轮开发体系

将 pp_tracer 和 alpha-screener 中各自维护的四层飞轮 skill 提炼为一套项目无关的通用版本，通过占位符 `{REPO}`、`{WORKSPACE}`、`{DEFAULT_BRANCH}`、`{PROJECT}`、`{CLI}`、`{DATA_DIR}` 适配任意项目。

## 五个 Skill

| 层 | Skill | 职责 |
|----|-------|------|
| 0A | lp-up | 引擎观察：执行+分析运行时数据 → 发现产品缺陷 |
| 0B | lp-dp | 飞轮自检：分析飞轮执行行为 → 发现流程偏差 |
| 1 | lp-ms | Issue 生命周期：拆解 → 依赖分析 → 批次规划 |
| 2 | lp-mr | MR 生命周期：git/gh 操作 → CI 监控 → 修复派发 |
| 3 | lp-dev | 本地开发：TDD → 验证 → simplify → HANDOFF |

**Why:** 两个项目各自维护几乎相同的 skill 文件，仅 repo/branch/CLI 不同。统一后可减少维护负担，新项目接入只需替换占位符 + 补充项目特定附录。

**How to apply:** 新项目接入时：(1) 复制 flywheel/ 下所有 SKILL.md (2) 全局替换 6 个占位符 (3) 补充 lp-up 附录 P（分析维度）(4) 补充 lp-dev 附录（lint/test 命令）。

[[flywheel-migration-notes]]
