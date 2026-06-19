# 四层飞轮（Flywheel）开发体系

从项目初始化到持续交付的全流程自动化闭环。7 个 skill 组成——**fw-setup** 一键创建标准化项目，**双层反馈环**（fw-inspect + fw-audit）持续发现和修复缺陷。

## 架构总览

```
┌──────────────────────────────────────────────────────────────┐
│                    fw-setup（项目初始化）                        │
│  仓库 → 保护 → CI → 质量工具 → 模板 → 标签 → 脚本 → Skills     │
│  输出：飞轮就绪的标准化项目                                     │
└────────────┬─────────────────────────────────────────────────┘
             ▼
┌──────────────────────────────────────────────────────────────┐
│                    双层观察引擎（第零层）                       │
│                                                              │
│  fw-inspect（引擎观察）              fw-audit（飞轮自检）              │
│  执行 → 观察 → 分析 → 报告      观察飞轮 → 对照规范 → 发现偏差  │
│  发现：架构/实现/算法缺陷        发现：流程偏差/自动化机会/冗余  │
└────────────┬──────────────────────────┬───────────────────────┘
             │ milestone (subagent)     │ milestone (subagent)
             ▼                          ▼
┌──────────────────────────────────────────────────────────────┐
│                    fw-plan（第一层 · 编排）                      │
│                                                              │
│  需求拆解 → Issue 创建 → 依赖分析 → 批次规划 → 进度追踪        │
│  输出：有序的 issue 队列                                       │
└────────────┬─────────────────────────────────────────────────┘
             │ issue
             ▼
┌──────────────────────────────────────────────────────────────┐
│                    fw-ship（第二层 · 交付）                      │
│                                                              │
│  开分支 → subagent:fw-build → commit+push+MR → 监控CI           │
│  CI fail → 收集日志 → subagent:fw-build --fix → push → 监控      │
│  CI green → squash merge → 清理分支                           │
└────────────┬─────────────────────────────────────────────────┘
             │ branch (via subagent)
             ▼
┌──────────────────────────────────────────────────────────────┐
│                    fw-build（第三层 · 开发）                      │
│                                                              │
│  TDD 红→绿→重构 → lint → test → simplify → HANDOFF            │
│  只写代码，不做任何 git 操作                                   │
└──────────────────────────────────────────────────────────────┘
             │ merge
             ▼
         fw-inspect（再执行 → 验证修复 → 发现新问题 → ...）
         fw-audit（再审计 → 验证优化 → 发现新偏差 → ...）
```

## 七层 Skill 速查

| 层 | Skill | 调用方式 | 职责 | Git 操作 |
|----|-------|---------|------|---------|
| — | `fw-setup` | `/fw-setup <repo-name> [--owner X] [--python 3.11] [--dry-run]` | 项目初始化：仓库、CI、分支保护、模板、标签、脚本 | 创建仓库 |
| 0A | `fw-inspect` | `/fw-inspect [--run quick\|full] [--focus <area>] [--resume]` | 引擎观察：执行+分析运行时数据，发现产品缺陷 | 无 |
| 0B | `fw-audit` | `/fw-audit [--skill <name>] [--audit]` | 飞轮自检：分析飞轮执行上下文，发现流程偏差/冗余 | 无 |
| 1 | `fw-plan` | `/fw-plan <需求描述>` 或 `--resume <milestone>` | Issue 生命周期：拆解、创建、依赖、批次、追踪 | 无 |
| 2 | `fw-ship` | `/fw-ship <issue-number> [--resume]` | MR 全生命周期：commit、push、监控、修复派发 | 全部 git/gh |
| 3 | `fw-build` | `/fw-build <issue> [--fix <mr>]` | 纯本地开发：TDD → 验证 → simplify → HANDOFF | 无 |

## 核心设计原则

### 1. 关注点分离

- **fw-setup**：只创建配置、模板、脚本，不写业务代码
- **fw-inspect / fw-audit**：只观察、分析、报告，不写代码
- **fw-plan**：只编排 issue，不操作 MR 或代码
- **fw-ship**：只操作 git/gh，不写代码（通过 subagent 委托 fw-build）
- **fw-build**：只写代码和本地验证，不操作 git

### 2. Subagent 隔离

跨层调用全部通过 subagent，防止上下文污染：

```
fw-inspect  → Agent(fw-plan)   # 引擎发现 → 需求拆解
fw-audit  → Agent(fw-plan)   # 流程发现 → 需求拆解
fw-plan  → Agent(fw-ship)   # issue 编号 + ctx 文件
fw-ship  → Agent(fw-build)  # 开发/修复
```

### 3. HANDOFF 信号协议

fw-build 与 fw-ship 之间的唯一接口：

```
---HANDOFF---
DEV_DONE=<branch>           # 开发完成
FIX_DONE=<branch>           # 修复完成
FAIL_DONE=<error-type>      # 失败（SIMPLIFY_UNFIXABLE | CONFLICT_UNRESOLVABLE | UNKNOWN）
---HANDOFF_END---
```

### 4. 自动推进，零人工中断

| 场景 | 行为 |
|------|------|
| Issue 拆解完成 | 自动创建，不询问确认 |
| CRITICAL / WARNING 发现 | 自动通过 subagent 启动 fw-plan |
| INFO 发现 | 记录到 findings.json，连续 3 轮未消除自动升级 WARNING |
| INFO 积压 > 20 条 | 每轮强制升级 1 条最老的 INFO |
| 飞轮评分 ≤ C+ 连续 2 轮 | 自动生成 DESIGN 类 milestone 并派发 |
| 飞轮评分 D | 立即生成 CRITICAL DESIGN milestone |
| 分支冲突 | 自动删除旧分支，不询问 |
| 可自动决策的问题 | 直接决策，不询问用户 |

> **硬约束**：所有飞轮 skill 严禁调用 `AskUserQuestion`。所有决策由规则引擎自动判定。

### 5. 状态持久化 + 断电恢复

所有层支持 `--resume`，从 GitHub/state 文件反推当前状态继续执行。

```
.claude/state/
├── fw-inspect/
│   ├── round.md           # 当前轮次、最后分析时间
│   └── findings.json      # 历史发现追踪
├── fw-audit/
│   ├── audit.md           # 最近审计报告
│   ├── findings.json      # 飞轮发现追踪
│   └── skill_scores.json  # 各 skill 健康度趋势
└── issue-<N>/
    ├── .status            # MERGED | BLOCKED_CI | CONFLICT | ...
    └── .fix_round         # CI 修复重试计数（上限 3）
```

## 兼容性

- **Python 项目**：开箱即用（自动检测 pyproject.toml, ruff, pytest, uv）
- **Node.js 项目**：fw-build 自动适配（eslint + prettier + jest）
- **其他语言**：fw-ship / fw-plan / fw-audit 不受影响（基于 git + gh）；fw-inspect / fw-build 需手动调整执行命令

## 迭代闭环

```
Round 1: fw-inspect 发现缺陷 → fw-plan 拆解 → fw-ship 交付 → fw-build 实现 → 合入
Round 2: fw-inspect 验证修复 + 发现新缺陷 → ...（引擎持续改进）
         fw-audit 审计流程 + 发现偏差 → fw-plan 优化飞轮 → ...（流程持续进化）
```

每一轮都在上一轮的基础上推进，既验证历史修复效果，又发现新的改进空间。两个反馈环独立运行、互不阻塞。

## 如何使用

### 安装（一次性）

```bash
# 复制 7 个 skill 到用户级目录
# 运行 ./install.sh 即可 ~/.claude/skills/
```

安装后**跨所有项目**即刻生效——无需 `--repo` 参数、无需替换占位符。每个 skill 启动时自动从 `git remote`、`pyproject.toml` 检测当前项目上下文。

### 调用示例

```text
# 项目初始化（新项目一次性操作）
/fw-setup my-new-project --owner Qanora

# 引擎观察（在任何项目目录下）
/fw-inspect                          # 纯分析模式
/fw-inspect --run quick              # 快速执行 + 分析

# 飞轮健康度审计
/fw-audit

# 需求拆解为 issue
/fw-plan 添加缓存层减少数据库查询延迟

# 开发单个 issue
/fw-ship 42

# 从断点恢复
/fw-plan --resume 3
/fw-ship 42 --resume
/fw-inspect --resume
```

### 上下文检测机制

每个 skill 启动时自动执行：

| 变量 | 检测方式 |
|------|---------|
| `WORKSPACE` | `git rev-parse --show-toplevel` |
| `REPO` | `gh repo view --json nameWithOwner -q .nameWithOwner` |
| `DEFAULT_BRANCH` | `git symbolic-ref refs/remotes/origin/HEAD` |
| `PROJECT` | `pyproject.toml` → `[project].name` |
| `CLI` | `pyproject.toml` → `[project.scripts]` 第一个入口 |
| `DATA_DIR` | `~/.$PROJECT` |

`gh issue/pr/label` 命令**无需 `--repo`** — `gh` CLI 自动从 git remote 检测。

### 与项目级安装的对比

| 维度 | 旧：项目级 | 新：用户级 |
|------|-----------|-----------|
| 安装位置 | `<project>/.claude/skills/` | `~/.claude/skills/` |
| 安装次数 | 每个项目一次 | 全局一次 |
| 占位符 | `{REPO}` 等 6 个需替换 | 无占位符，运行时检测 |
| `--repo` 参数 | 所有 gh 命令需显式指定 | gh 自动检测 |
| 新项目接入 | 运行 install.sh 或手动复制 | 开箱即用 |
| 更新 | 每个项目单独更新 | 全局一处更新 |
