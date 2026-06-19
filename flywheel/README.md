# 四层飞轮（Flywheel）开发体系

从项目初始化到持续交付的全流程自动化闭环。6 个 skill 组成——**lp-init** 一键创建标准化项目，**双层反馈环**（lp-up + lp-dp）持续发现和修复缺陷。

## 架构总览

```
┌──────────────────────────────────────────────────────────────┐
│                    lp-init（项目初始化）                        │
│  仓库 → 保护 → CI → 质量工具 → 模板 → 标签 → 脚本 → Skills     │
│  输出：飞轮就绪的标准化项目                                     │
└────────────┬─────────────────────────────────────────────────┘
             ▼
┌──────────────────────────────────────────────────────────────┐
│                    双层观察引擎（第零层）                       │
│                                                              │
│  lp-up（引擎观察）              lp-dp（飞轮自检）              │
│  执行 → 观察 → 分析 → 报告      观察飞轮 → 对照规范 → 发现偏差  │
│  发现：架构/实现/算法缺陷        发现：流程偏差/自动化机会/冗余  │
└────────────┬──────────────────────────┬───────────────────────┘
             │ milestone (subagent)     │ milestone (subagent)
             ▼                          ▼
┌──────────────────────────────────────────────────────────────┐
│                    lp-ms（第一层 · 编排）                      │
│                                                              │
│  需求拆解 → Issue 创建 → 依赖分析 → 批次规划 → 进度追踪        │
│  输出：有序的 issue 队列                                       │
└────────────┬─────────────────────────────────────────────────┘
             │ issue
             ▼
┌──────────────────────────────────────────────────────────────┐
│                    lp-mr（第二层 · 交付）                      │
│                                                              │
│  开分支 → subagent:lp-dev → commit+push+MR → 监控CI           │
│  CI fail → 收集日志 → subagent:lp-dev --fix → push → 监控      │
│  CI green → squash merge → 清理分支                           │
└────────────┬─────────────────────────────────────────────────┘
             │ branch (via subagent)
             ▼
┌──────────────────────────────────────────────────────────────┐
│                    lp-dev（第三层 · 开发）                      │
│                                                              │
│  TDD 红→绿→重构 → lint → test → simplify → HANDOFF            │
│  只写代码，不做任何 git 操作                                   │
└──────────────────────────────────────────────────────────────┘
             │ merge
             ▼
         lp-up（再执行 → 验证修复 → 发现新问题 → ...）
         lp-dp（再审计 → 验证优化 → 发现新偏差 → ...）
```

## 六层 Skill 速查

| 层 | Skill | 调用方式 | 职责 | Git 操作 |
|----|-------|---------|------|---------|
| — | `lp-init` | `/lp-init <repo-name> [--owner X] [--python 3.11] [--dry-run]` | 项目初始化：仓库、CI、分支保护、模板、标签、脚本 | 创建仓库 |
| 0A | `lp-up` | `/lp-up [--run quick\|full] [--focus <area>] [--resume]` | 引擎观察：执行+分析运行时数据，发现产品缺陷 | 无 |
| 0B | `lp-dp` | `/lp-dp [--skill <name>] [--audit]` | 飞轮自检：分析飞轮执行上下文，发现流程偏差/冗余 | 无 |
| 1 | `lp-ms` | `/lp-ms <需求描述>` 或 `--resume <milestone>` | Issue 生命周期：拆解、创建、依赖、批次、追踪 | 无 |
| 2 | `lp-mr` | `/lp-mr <issue-number> [--resume]` | MR 全生命周期：commit、push、监控、修复派发 | 全部 git/gh |
| 3 | `lp-dev` | `/lp-dev <issue> [--fix <mr>]` | 纯本地开发：TDD → 验证 → simplify → HANDOFF | 无 |

## 核心设计原则

### 1. 关注点分离

- **lp-init**：只创建配置、模板、脚本，不写业务代码
- **lp-up / lp-dp**：只观察、分析、报告，不写代码
- **lp-ms**：只编排 issue，不操作 MR 或代码
- **lp-mr**：只操作 git/gh，不写代码（通过 subagent 委托 lp-dev）
- **lp-dev**：只写代码和本地验证，不操作 git

### 2. Subagent 隔离

跨层调用全部通过 subagent，防止上下文污染：

```
lp-up  → Agent(lp-ms)   # 引擎发现 → 需求拆解
lp-dp  → Agent(lp-ms)   # 流程发现 → 需求拆解
lp-ms  → /lp-mr <N>     # skill 调用（同会话）
lp-mr  → Agent(lp-dev)  # 开发/修复
```

### 3. HANDOFF 信号协议

lp-dev 与 lp-mr 之间的唯一接口：

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
| CRITICAL / WARNING 发现 | 自动通过 subagent 启动 lp-ms |
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
├── lp-up/
│   ├── round.md           # 当前轮次、最后分析时间
│   └── findings.json      # 历史发现追踪
├── lp-dp/
│   ├── audit.md           # 最近审计报告
│   ├── findings.json      # 飞轮发现追踪
│   └── skill_scores.json  # 各 skill 健康度趋势
└── issue-<N>/
    ├── .status            # MERGED | BLOCKED_CI | CONFLICT | ...
    └── .fix_round         # CI 修复重试计数（上限 3）
```

## 兼容性

- **Python 项目**：开箱即用（自动检测 pyproject.toml, ruff, pytest, uv）
- **Node.js 项目**：lp-dev 自动适配（eslint + prettier + jest）
- **其他语言**：lp-mr / lp-ms / lp-dp 不受影响（基于 git + gh）；lp-up / lp-dev 需手动调整执行命令

## 迭代闭环

```
Round 1: lp-up 发现缺陷 → lp-ms 拆解 → lp-mr 交付 → lp-dev 实现 → 合入
Round 2: lp-up 验证修复 + 发现新缺陷 → ...（引擎持续改进）
         lp-dp 审计流程 + 发现偏差 → lp-ms 优化飞轮 → ...（流程持续进化）
```

每一轮都在上一轮的基础上推进，既验证历史修复效果，又发现新的改进空间。两个反馈环独立运行、互不阻塞。

## 如何使用

### 安装（一次性）

```bash
# 复制 6 个 skill 到用户级目录
cp -r /path/to/skills/flywheel/lp-* ~/.claude/skills/
```

安装后**跨所有项目**即刻生效——无需 `--repo` 参数、无需替换占位符。每个 skill 启动时自动从 `git remote`、`pyproject.toml` 检测当前项目上下文。

### 调用示例

```text
# 项目初始化（新项目一次性操作）
/lp-init my-new-project --owner Qanora

# 引擎观察（在任何项目目录下）
/lp-up                          # 纯分析模式
/lp-up --run quick              # 快速执行 + 分析

# 飞轮健康度审计
/lp-dp

# 需求拆解为 issue
/lp-ms 添加缓存层减少数据库查询延迟

# 开发单个 issue
/lp-mr 42

# 从断点恢复
/lp-ms --resume 3
/lp-mr 42 --resume
/lp-up --resume
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
