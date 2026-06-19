# 迁移对照：pp_tracer vs alpha-screener → 通用版

> **2026-06-19 更新**：新增 `lp-init` — 全新项目的一键初始化 skill，两个源项目均无此 skill（初始化均靠手动）。

## 两个源项目的差异

| 维度 | pp_tracer | alpha-screener | 通用版处理 |
|------|-----------|----------------|-----------|
| 层编号 | 0A/0B/1/2/3 | 0a/0b/1/2/3 (CLAUDE.md) / 1/2/3/4 (SKILL.md) | **统一为 0A/0B/1/2/3** |
| 默认分支 | `main` | `master` | **`{DEFAULT_BRANCH}` 占位符** |
| 仓库 | `Qanora/pp_tracer` | `Qanora/alpha-screener` | **`{REPO}` 占位符** |
| 工作目录 | `/root/workspace/pp_tracer` | `/root/workspace/alpha-screener` | **`{WORKSPACE}` 占位符** |
| CLI | `pptracer` | `alphascreener` | **`{CLI}` 占位符** |
| 数据目录 | `~/.pptracer` | `~/.alphascreener` | **`{DATA_DIR}` 占位符** |
| 项目简称 | `pptracer` | `alphascreener` | **`{PROJECT}` 占位符** |
| lp-up 分析维度 | 网络追踪专用（延迟/跳/健康检查） | 量化筛选专用（因子IC/回测/成本） | **「附录 P」可插拔** |
| lp-dev 验证命令 | `ruff check . && ruff format --check .` + `python -m pytest tests/ -v` | 同左 | **「附录：项目特定命令」可插拔** |
| lp-mr 分支基址 | `origin/main` | `origin/master` | **`origin/{DEFAULT_BRANCH}`** |

## 两个版本的共性（核心不变）

以下部分两个项目完全一致，通用版直接保留：

1. **HANDOFF 信号协议** — `DEV_DONE`/`FIX_DONE`/`FAIL_DONE` 格式完全一致
2. **Subagent 隔离模式** — lp-mr → Agent(lp-dev)，lp-up/lp-dp → Agent(lp-ms)
3. **状态机** — fix_round 上限 3，BLOCKED_CI/CONFLICT/API_ERROR 状态标记
4. **TDD 红绿重构循环** — lp-dev 步骤 5 完全一致
5. **300 行约束** — soft constraint，不阻塞
6. **自动推进规则** — CRITICAL+WARNING 自动派发，INFO 记录待升级
7. **依赖图 + 环检测** — lp-ms 步骤 4 完全一致
8. **Triage labels** — 五种标签完全一致
9. **状态持久化结构** — `.claude/state/` 目录结构完全一致
10. **Resume 机制** — 所有层支持 `--resume`
11. **清理脚本** — watch-pr.sh / lp-mr-cleanup.sh / cleanup-merged-branches.sh
12. **分支命名规范** — `feature/issue-<N>`
13. **Commit 规范** — 关联 issue，修复 commit 不加 `closes`
14. **资源采样脚本** — psutil 包裹执行，采集 RSS/CPU/FD

## 从现有项目迁移

将现有项目的 skill 替换为通用版：

```bash
# 1. 复制通用 skill 到项目
cp -r skills/flywheel/lp-* /path/to/project/.claude/skills/

# 2. 全局替换占位符（以 pp_tracer 为例）
cd /path/to/project/.claude/skills/
for skill in lp-*/SKILL.md; do
  sed -i \
    -e 's|{REPO}|Qanora/pp_tracer|g' \
    -e 's|{WORKSPACE}|/root/workspace/pp_tracer|g' \
    -e 's|{DEFAULT_BRANCH}|main|g' \
    -e 's|{PROJECT}|pptracer|g' \
    -e 's|{CLI}|pptracer|g' \
    -e 's|{DATA_DIR}|~/.pptracer|g' \
    "$skill"
done

# 3. 补充 lp-up 的「附录 P」（项目特定分析维度）
# 补充 lp-dev 的「附录：项目特定命令」
```

## 通用版相比源项目的改进

1. **占位符机制** — 一套 skill 适配所有项目，无需手动改写 repo/branch/CLI
2. **可插拔分析引擎** — lp-up 的「附录 P」使不同领域的项目可自定义分析维度
3. **层级编号统一** — 消除了 pp_tracer (0A/0B/1/2/3) 和 alpha-screener (混乱的 1/2/3/4) 的不一致
4. **README 总览** — 新增架构图、速查表、设计原则、迁移指南
5. **项目特定命令附录** — lp-dev 不再硬编码 `ruff`/`pytest`，改为模板
