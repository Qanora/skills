---
name: lp-up
description: 第零层·A——执行引擎+分析运行时数据，持续发现架构/实现/算法缺陷，通过 subagent 启动 lp-ms 驱动迭代改进
---

# LP-UP（第零层·A · 用户级）

主动执行引擎、观察运行过程、发现缺陷、提出 milestone，通过 **subagent** 启动 lp-ms 驱动整个飞轮迭代。

> **用户级 skill**：跨所有项目生效。自动检测当前项目的 CLI、日志路径、数据库位置。

## 上下文检测

```bash
WORKSPACE=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$WORKSPACE"
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
# 检测项目 CLI
if [ -f pyproject.toml ]; then
  CLI=$(awk '/\[project\.scripts\]/{found=1;next} found && /=/ {print $1; exit}' pyproject.toml || basename "$WORKSPACE")
else
  CLI=$(basename "$WORKSPACE")
fi
PROJECT=$(grep -m1 '^name\s*=' pyproject.toml 2>/dev/null | sed 's/.*=\s*"\(.*\)".*/\1/' || basename "$WORKSPACE")
DATA_DIR="$HOME/.$PROJECT"
echo "[lp-up] WORKSPACE=$WORKSPACE CLI=$CLI PROJECT=$PROJECT DATA_DIR=$DATA_DIR"
```

```
┌─────────────────────────────────────────────────────┐
│                  lp-up (第零层·A)                     │
│  执行 → 观察 → 分析 → 报告 → subagent:lp-ms（自动）   │
└────────┬────────────────────────────────────────────┘
         │ milestone (via subagent)
         ▼
    lp-ms (需求拆解 → issue) → lp-mr (MR 生命周期) → lp-dev (写代码)
         │ merge
         ▼
    lp-up (再执行 → 验证修复 → 发现新问题 → ...)
```

## 调用方式

```text
/lp-up                           # 纯分析模式（不执行，只分析已有数据）
/lp-up --run quick               # 快速轮：执行 + 分析
/lp-up --run full                # 完整轮：全量执行 + 深度分析
/lp-up --focus <area>            # 聚焦：performance | cost | accuracy | reliability
/lp-up --since <date>            # 只分析指定日期之后的数据
/lp-up --resume                  # 从中断恢复
```

## 核心概念：持续改进循环

```text
Round N:   执行 → 观察 → 发现 F₁, F₂, F₃ → subagent:lp-ms → 飞轮实现
Round N+1: 执行 → 观察 → 验证 F₁ 已修复 ✓, F₂ 部分改善 ~ → 发现新问题 F₄ → ...
```

每一轮都在上一轮的基础上推进，既验证历史修复效果，又发现新的改进空间。

## 流程

### 阶段 A：执行引擎（--run 模式）

#### A.1 Quick Round

执行项目 CLI 快速检查。**根据项目类型自动适配**：

```bash
cd "$(git rev-parse --show-toplevel)"
# 检测 CLI 并执行快速检查
CLI=$(awk '/\[project\.scripts\]/{found=1;next} found && /=/ {print $1; exit}' pyproject.toml 2>/dev/null)
if [ -n "$CLI" ]; then
  $CLI run --quick 2>/dev/null || $CLI --help 2>/dev/null || echo "[INFO] CLI 不支持 --quick，跳过执行"
fi
```

#### A.2 Full Round

```bash
cd "$(git rev-parse --show-toplevel)"
# 完整管道（按项目 CLI 实际能力执行）
$CLI collect --full 2>/dev/null || true
$CLI analyze --all 2>/dev/null || true
$CLI health-check 2>/dev/null || true
$CLI report --full 2>/dev/null || true
```

> **无 CLI 时**：跳过执行，自动切为纯分析模式。

#### A.3 执行期间实时观察

每个命令执行时同步采集：

| 观察维度 | 采集方式 |
|----------|---------|
| 退出码 | `$?` |
| 耗时 | `time` 包裹 |
| stdout/stderr | 完整捕获 |
| 资源峰值 | 执行前后各采样 `psutil`：RSS、CPU%、open FDs |
| 错误计数 | stderr 行数 + 日志中 ERROR 级别行数 |

```bash
python -c "
import time, psutil, os, sys, subprocess, json
pid = os.getpid()
before = {'rss_mb': psutil.Process(pid).memory_info().rss / 1024**2}
t0 = time.monotonic()
result = subprocess.run(sys.argv[1:], capture_output=True, text=True)
elapsed = time.monotonic() - t0
after = {'rss_mb': psutil.Process(pid).memory_info().rss / 1024**2}
print(json.dumps({
    'exit_code': result.returncode, 'elapsed_s': round(elapsed, 1),
    'rss_before_mb': round(before['rss_mb'], 1), 'rss_after_mb': round(after['rss_mb'], 1),
    'rss_delta_mb': round(after['rss_mb'] - before['rss_mb'], 1),
    'stdout_lines': len(result.stdout.splitlines()), 'stderr_lines': len(result.stderr.splitlines()),
}))
" -- <command>
```

### 阶段 B：数据采集

#### B.1 本轮执行数据（仅 --run 模式）

退出码、耗时、stdout/stderr、资源采样、新产生的日志行。

#### B.2 历史运行时数据（所有模式）

**结构化日志**（自动检测 `$DATA_DIR/logs/` 或 `logs/`）：

```bash
cd "$(git rev-parse --show-toplevel)"
PROJECT=$(grep -m1 '^name\s*=' pyproject.toml 2>/dev/null | sed 's/.*=\s*"\(.*\)".*/\1/' || basename "$PWD")
LOG_DIR="$HOME/.$PROJECT/logs"
[ -d "$LOG_DIR" ] || LOG_DIR="logs"

# 按级别和模块统计
cat "$LOG_DIR"/*.log 2>/dev/null | jq -r '[.level, .module] | @tsv' | sort | uniq -c | sort -rn
# 提取 ERROR（最近 30 天）
find "$LOG_DIR/" -name "*.log" -mtime -30 | xargs cat 2>/dev/null | jq 'select(.level == "ERROR")'
```

**SQLite 运行时指标**（自动检测 `$DATA_DIR/data/*.db`）：

```bash
DB=$(find "$HOME/.$PROJECT/data/" -name "*.db" 2>/dev/null | head -1)
[ -z "$DB" ] && DB=$(find data/ -name "*.db" 2>/dev/null | head -1)
if [ -n "$DB" ]; then
  # 列出所有表
  sqlite3 "$DB" ".tables"
  # monitoring_samples 表（若存在）
  sqlite3 "$DB" "SELECT date(ts) as day, max(rss_mb) as peak_rss FROM monitoring_samples WHERE ts >= date('now', '-30 days') GROUP BY date(ts) ORDER BY day;" 2>/dev/null
fi
```

**Parquet/文件批量数据**（自动检测 `$DATA_DIR/data/`）：

```bash
find "$HOME/.$PROJECT/data/" -name "*.parquet" -type f 2>/dev/null | head -20
```

### 阶段 C：多维度分析

#### C.1 架构缺陷（ARCHITECTURE）

**A1. 内存泄漏** — 7 日 RSS 线性回归斜率 > 50MB/天 且工作负载持平 → 疑似泄漏
**A2. FD 泄漏** — 7 日 FD 计数斜率 > 10/天 → 疑似泄漏
**A3. 管道瓶颈** — P95 耗时 > 2× 历史中位数 → 瓶颈
**A4. 调度可靠性** — 预期时段无 monitoring_samples 记录 → 调度可能未运行

#### C.2 实现缺陷（IMPLEMENTATION）

**I1. 错误聚类** — 单一 error > 10 次/天 → 系统性 bug
**I2. 数据缺口** — 某时间窗口记录数 < 中位数 50% → 采集不完整
**I3. 延迟异常** — P99 延迟 > 历史 P99 × 3 → 异常 spike
**I4. 本轮执行异常（仅 --run）** — exit code ≠ 0 → CRITICAL；RSS delta > 200MB → 内存异常

#### C.3 算法缺陷（ALGORITHM）

**G1. 指标漂移** — 20 日滚动 P50 斜率持续恶化 → 系统性退化
**G2. 单点瓶颈** — 特定环节耗时 > 总量 50% → 单点瓶颈
**G3. 健康检查通过率下降** — pass_rate < 0.8 → 系统健康度下降

### 阶段 D：发现分类

每个发现包含：严重度（`CRITICAL`/`WARNING`/`INFO`）、类别（`ARCHITECTURE`/`IMPLEMENTATION`/`ALGORITHM`）、证据、根因假设、建议范围。

### 阶段 E：报告生成

```text
## LP-UP 分析报告 — Round <N>
**分析时间**: <ISO timestamp>
**执行模式**: quick | full | passive
**数据范围**: <start> → <end>

### 上一轮修复验证
| #1 内存泄漏 | ✓ 已修复 | RSS 7 日斜率从 +45MB/天 降至 +3MB/天 |

### 本轮发现汇总
| # | 严重度 | 类别 | 简述 | 建议 milestone |
|---|--------|------|------|----------------|
| 1 | CRITICAL | IMPLEMENTATION | 某命令 exit code=1 | 修复命令异常 |
| 2 | WARNING | ALGORITHM | P99 延迟上升 | 排查延迟瓶颈 |

### INFO 积压: 12 条（最老 14 天，3 条已达老化阈值）
```

### 阶段 F：自动派发 lp-ms

报告生成后**自动推进，不询问用户**：

| 严重度 | 动作 |
|--------|------|
| CRITICAL | 立即通过 subagent 启动 lp-ms |
| WARNING | 立即通过 subagent 启动 lp-ms |
| INFO | 记录到 findings.json；同一 INFO 连续 3 轮未消除 → 自动升级 WARNING 并派发 |
| INFO 积压 > 20 条 | 每轮强制升级 1 条最老的 INFO |

**派发前先写 milestone 文件**：

```bash
mkdir -p /tmp/lp-flywheel
cat > "/tmp/lp-flywheel/milestone-<finding-id>.md" << 'EOF'
# [lp-up][<类别>] <简述>

| 字段 | 值 |
|------|-----|
| 来源 | lp-up Round <N> |
| 严重度 | CRITICAL | WARNING | INFO |
| 类别 | ARCHITECTURE | IMPLEMENTATION | ALGORITHM |
| 证据摘要 | <关键数据点> |
| 根因假设 | <分析判断> |
| 预期收益 | <修复后的改善> |
| 建议范围 | <涉及模块/文件> |
EOF
```

然后通过 subagent 启动 lp-ms（prompt 只传文件路径）：

```text
Agent(description: "lp-ms: <简述>", subagent_type: "lp-ms",
  prompt: "milestone 文件: /tmp/lp-flywheel/milestone-<finding-id>.md")
```

串行派发：CRITICAL → WARNING → INFO 老化升级。每个 milestone 完成后清理对应文件。

### 阶段 G：状态持久化

```text
.claude/state/lp-up/
  round.md           # 当前 round 编号、最后分析日期、执行模式
  findings.json      # 历史发现追踪
```

**findings.json 结构**：

```json
{
  "round": 3, "last_run": "2026-05-23T08:00:00Z", "info_backlog": 12,
  "findings": [{
    "id": "F-001", "title": "...", "severity": "CRITICAL", "category": "ARCHITECTURE",
    "status": "resolved", "milestone_url": "...",
    "round_discovered": 1, "round_resolved": 2,
    "consecutive_rounds": 0, "auto_escalated": false
  }]
}
```

| 字段 | 用途 |
|------|------|
| `consecutive_rounds` | 连续未消除轮数，≥3 自动升级 WARNING |
| `auto_escalated` | 是否由 INFO 老化自动升级 |
| `info_backlog` | INFO 积压总数 |

### 阶段 H：下一轮预告

```text
## 本轮总结
- 发现总数: 3  |  已推进: 2  |  INFO 积压: 12 条
- INFO 自动升级: 1 条（F-003，连续 3 轮 → WARNING）

## 下一轮建议
建议 milestone 合入后运行: /lp-up --run quick
重点验证: F-001 (内存泄漏), F-002 (命令异常)
```

## 约束

- **只读分析**：除 `--run` 中的引擎执行外，不修改代码/配置/数据
- **自动推进**：CRITICAL/WARNING 自动派发；INFO 连续 3 轮自动升级
- **INFO 老化机制**：同一 INFO 连续 3 轮 → 自动升级 WARNING；积压 > 20 条时强制升级最老 1 条
- **串行派发**：按严重度排序依次启动 subagent
- **数据采样上限**：单次分析 ≤ 30 天数据或 10 万行日志
- **证据驱动**：每个发现必须有可追溯的数据证据
- **数据不足跳过**：标注 `⏭ [维度] — 跳过：数据不足`，不做强行推断
- **禁止用户交互**：严禁 `AskUserQuestion`；所有决策由规则自动判定

## 数据不足处理

```text
⏭ [ARCHITECTURE] 内存泄漏检测 — 跳过：monitoring_samples 仅有 3 天数据，需至少 7 天
⏭ [ALGORITHM] 延迟漂移检测 — 跳过：trace_samples 无数据
```

## 附录：状态恢复

```text
/lp-up --resume
```

1. 读取 `.claude/state/lp-up/round.md` 和 `findings.json`
2. 检查上一轮 milestone 完成情况
3. 标记 resolved，继续未完成的派发
4. 增量分析（不重复执行引擎命令）

报告保存至 `$DATA_DIR/reports/lp-up-round-<N>-<YYYY-MM-DD>.md`，保留最近 10 份。
