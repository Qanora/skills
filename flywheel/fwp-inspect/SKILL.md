---
name: fwp-inspect
description: [项目] 全量巡检——运行时8项(机械)+代码5项(LLM审查)，覆盖稳定性/功能/bug/架构/算法/开源方案
---

# FWP-INSPECT（项目全量巡检 · 用户级）

两层 13 项检查。Tier 1 运行时巡检（机械，秒级），Tier 2 代码审查（LLM 驱动，每项独立 subagent）。

> **用户级 skill**：跨项目生效。`/fwp-inspect` 直接回车，输出统一报告。

## 上下文检测

```bash
WORKSPACE=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$WORKSPACE"
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
CLI=$(awk '/\[project\.scripts\]/{found=1;next} found && /=/ {print $1; exit}' pyproject.toml 2>/dev/null || basename "$WORKSPACE")
PROJECT=$(grep -m1 '^name\s*=' pyproject.toml 2>/dev/null | sed 's/.*=\s*"\(.*\)".*/\1/' || basename "$WORKSPACE")
LOG_DIR="$HOME/.$PROJECT/logs"
DB_PATH=$(find "$HOME/.$PROJECT/data/" -name "*.db" 2>/dev/null | head -1)
echo "[fwp-inspect] CLI=$CLI LOG_DIR=$LOG_DIR DB=$DB_PATH"
```

## 调用方式

```text
/fwp-inspect                 # 全量巡检：Tier1(8项机械) + Tier2(5项LLM)
/fwp-inspect --quick         # 仅 Tier1 (8项机械, ~10秒, 零token)
/fwp-inspect --resume        # 中断恢复
```

`--quick` 只跑机械检查，不消耗 LLM token，适合频繁运行。

---

# Tier 1：运行时巡检（8 项，机械执行，秒级）

每条一个确定命令，输出 `PASS` / `FAIL` / `WARN` / `SKIP`。

### R1. MEM-LEAK — 内存泄漏

```bash
if [ -z "$DB_PATH" ]; then echo "SKIP: 无数据库"
else
  SLOPE=$(sqlite3 "$DB_PATH" "
    WITH d AS (SELECT date(ts) as day, max(rss_mb) as peak FROM monitoring_samples WHERE ts>=date('now','-7 days') GROUP BY date(ts))
    SELECT CASE WHEN count(*)<4 THEN 'SKIP' ELSE round((count(*)*sum(julianday(day)*peak)-sum(julianday(day))*sum(peak))/(count(*)*sum(julianday(day)*julianday(day))-sum(julianday(day))*sum(julianday(day))),1) END FROM d;
  " 2>/dev/null || echo "SKIP")
  case "$SLOPE" in SKIP) echo "SKIP: <4天数据" ;; *) [ "$(echo "$SLOPE>50"|bc -l)" = "1" ] && echo "FAIL: ${SLOPE}MB/天" || echo "PASS: ${SLOPE}MB/天" ;; esac
fi
```

### R2. FD-LEAK — 文件描述符泄漏

同 R1 逻辑，阈值 >10/天。

### R3. ERR-CLUSTER — 错误聚类

```bash
LOGDIR="${LOG_DIR:-logs}"
[ -d "$LOGDIR" ] && TOP=$(find "$LOGDIR/" -name "*.log" -mtime -7 | xargs cat 2>/dev/null | jq -r 'select(.level=="ERROR")|"\(.module//"?")|\(.event//"?")"' 2>/dev/null | sort|uniq -c|sort -rn|head -1)
CNT=$(echo "$TOP"|awk '{print $1}'); [ -z "$CNT" ]&& echo "PASS: 无 ERROR" || [ "$CNT" -gt 10 ] && echo "FAIL: $(echo "$TOP"|cut -d' ' -f2-) ($CNT次)" || echo "PASS: $CNT次"
```

### R4. PIPELINE — 管道瓶颈

P95 vs P50 历史中位数，>2× = WARN。

### R5. HEALTH — 健康检查通过率

SQL→7日 pass_rate，<0.8 = FAIL。

### R6. SCHEDULER — 调度可靠性

今日 monitoring_samples 是否存在，交易日无 = FAIL。

### R7. EXIT-CODE — CLI 可用性

`$CLI --help` 退出码，≠0 = FAIL。

### R8. RSS-DELTA — 单次内存增量

psutil 采样 CLI 启动前后 RSS，>200MB = WARN。

> Tier 1 具体 bash 命令同之前版本，此处省略重复代码。

---

# Tier 2：代码审查（5 项，LLM 驱动，每项独立 subagent）

每项启动一个 subagent，聚焦一个维度做深度分析。subagent 使用 Read/WebSearch/WebFetch 工具。

### C1. BUG — 潜在 Bug 检测

```text
Agent(subagent_type="general-purpose",
  description="Bug scan",
  prompt="对当前项目进行 bug 扫描。重点检查:
1. 异常处理是否完整 (try/except, error propagation)
2. 边界条件 (None/空数组/零值/超范围)
3. 并发安全 (race condition, deadlock)
4. 资源泄漏 (未关闭的文件/连接/socket)
5. 类型安全 (可能的 TypeError/NoneType error)

输出格式: 每条 bug 一行, 严重度 CRITICAL/WARNING/INFO, 文件:行号, 简述")
```

### C2. ARCH — 架构合理性

```text
Agent(subagent_type="general-purpose",
  description="Architecture review",
  prompt="审查当前项目的架构。重点:
1. 模块耦合度 — 是否存在循环依赖、过深的调用链
2. 职责单一性 — 是否有 God Class / 万能模块
3. 接口设计 — 是否有泄漏的抽象、不稳定的公开 API
4. 可测试性 — 是否难以单元测试 (硬编码依赖、全局状态)
5. 扩展性 — 新增功能是否需要大量改动

输出: 每条问题一行, 严重度 WARNING/INFO, 涉及模块, 简述+建议")
```

### C3. ALGO — 算法与理论优化

```text
Agent(subagent_type="general-purpose",
  description="Algorithm review",
  prompt="审查当前项目核心算法的优化空间:
1. 时间复杂度 — 是否存在 O(n²) 可降为 O(n log n) 的热路径
2. 空间复杂度 — 是否存在不必要的大对象拷贝
3. 数据结构选择 — 是否用对了容器 (list vs set vs dict vs deque)
4. 缓存策略 — 是否有重复计算可以缓存

然后 WebSearch 搜索该领域最近 2 年的最新算法/论文/技术方案,
对比当前实现是否有可替代的更优方案。

输出: 每条发现一行, 严重度 WARNING/INFO, 涉及代码位置, 简述+改进建议+文献链接(如有)")
```

### C4. OSS — 开源方案对比

```text
Agent(subagent_type="general-purpose",
  description="OSS alternatives scan",
  prompt="搜索当前项目所解决问题的开源替代方案和可复用库:
1. PyPI/npm 上是否有直接可替代的成熟库
2. GitHub 上是否有类似功能且更活跃的项目
3. 是否有可以集成的子模块 (如用 pydantic 替代手写校验, 用 rich 替代自绘 UI)
4. 对比: stars/维护活跃度/许可证/API 设计

输出: 每条一个候选方案, 严重度 INFO, 库名+链接, 可替代的功能模块, 集成成本评估")
```

### C5. COMPLETE — 功能性完备性

```text
Agent(subagent_type="general-purpose",
  description="Completeness check",
  prompt="检查当前项目功能性完备性:
1. 对照 README/CLAUDE.md 中声明的功能, 是否全部实现
2. 对照同类成熟项目的功能矩阵, 是否有明显缺失
3. CLI/API 参数是否完整 (--help 中声明的选项是否都有效)
4. 错误信息是否清晰 (用户输错参数时能否给出有用提示)
5. 文档/注释覆盖率 (关键函数是否有 docstring)

输出: 每条缺失一行, 严重度 WARNING/INFO, 缺失项, 建议")
```

---

## 执行流程

### 1. 执行 Tier 1（机械）

8 项依次执行，每项秒级完成。

### 2. 并行执行 Tier 2（LLM）

5 个 subagent 并行启动，各自独立分析。每个约 1-3 分钟。

### 3. 汇总报告

```text
## FWP-INSPECT 全量巡检报告

### Tier 1: 运行时 (8项)
| # | 检查项 | 结论 | 详情 |
|---|--------|------|------|
| R1 | MEM-LEAK  | PASS   | 3MB/天 |
| R2 | FD-LEAK   | PASS   | 1/天 |
| R3 | ERR-CLUSTER | FAIL | KeyError (23次) |
| R4 | PIPELINE  | SKIP   | 无日志 |
| R5 | HEALTH    | SKIP   | 无数据 |
| R6 | SCHEDULER | PASS   | 144条 |
| R7 | EXIT-CODE | PASS   | CLI 可用 |
| R8 | RSS-DELTA | PASS   | 12MB |

### Tier 2: 代码审查 (5项)
| # | 检查项 | 发现 | 严重度 | 简述 |
|---|--------|------|--------|------|
| C1 | BUG     | 3    | 2W+1C | phase2.py:145 KeyError, collector.py:89 未关闭连接 |
| C2 | ARCH    | 2    | WARN   | phase1/phase2 循环依赖, God Class: AlphaScreener |
| C3 | ALGO    | 1    | INFO   | CUSUM 可换用 Bayesian Online Changepoint (Adams 2024) |
| C4 | OSS     | 2    | INFO   | hdbscan→faiss, backtrader→vectorbt |
| C5 | COMPLETE| 1    | WARN   | --output json 参数声明但未实现 |

FAIL:1  WARN:3  INFO:3  PASS:5  SKIP:2
```

### 4. 自动派发

- 所有 FAIL → CRITICAL milestone → Agent(fwp-plan)
- 所有 WARN → WARNING milestone → Agent(fwp-plan)
- INFO → 记录到 findings.json，连续 3 轮未处理自动升级

```bash
mkdir -p /tmp/fw-flywheel/$PROJECT
for finding in "${FINDINGS[@]}"; do
  cat > "/tmp/fw-flywheel/$PROJECT/milestone-${id}.md" << EOF
# [fwp-inspect][${tier}/${check}] ${title}
| 字段 | 值 |
|------|-----|
| 来源 | fwp-inspect |
| 检查项 | ${check} |
| 严重度 | ${severity} |
| 证据 | ${detail} |
| 建议 | ${suggestion} |
EOF
  # 派发
  Agent(description: "fwp-plan: ${title}", subagent_type: "general-purpose",
    prompt: "milestone: /tmp/fw-flywheel/$PROJECT/milestone-${id}.md")
done
```

## 约束

- **Tier 1 固定命令**：8 项机械检查，确定阈值，不依赖 LLM
- **Tier 2 独立 subagent**：5 项并行，各自隔离上下文
- **FAIL/WARN 自动派发**：生成 milestone → Agent(fwp-plan)
- **INFO 老化**：连续 3 轮 → 自动升级 WARNING
- **禁止用户交互**：严禁 `AskUserQuestion`
