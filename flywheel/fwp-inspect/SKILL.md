---
name: fwp-inspect
description: [项目] 引擎巡检——8 条固定检查项，每条输出 PASS/FAIL/WARN，FAIL/WARN 自动生成 milestone 派发 fw-plan
---

# FWP-INSPECT（引擎巡检 · 用户级）

执行 8 条固定检查项，逐条输出确定结论。FAIL/WARN 自动写 milestone 文件并通过 subagent 派发 fw-plan。

> **用户级 skill**：跨项目生效。每条检查项有固定命令和阈值，不由 LLM 即兴判断。

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
/fwp-inspect                 # 执行 8 项巡检（能做就做，不能就 SKIP）
/fwp-inspect --resume        # 中断恢复
```

无模式切换——始终执行全部 8 项检查。有数据就查数据，有 CLI 就测 CLI，不区分"纯分析"和"执行"模式。

## 8 条固定检查项

3 种结论：`PASS` / `FAIL`（自动派发 CRITICAL milestone）/ `WARN`（自动派发 WARNING milestone）/ `SKIP`（数据不足）

---

### 1. MEM-LEAK — 内存泄漏

```bash
if [ -z "$DB_PATH" ]; then echo "SKIP: 无数据库"
else
  SLOPE=$(sqlite3 "$DB_PATH" "
    WITH d AS (
      SELECT date(ts) as day, max(rss_mb) as peak
      FROM monitoring_samples WHERE ts >= date('now','-7 days')
      GROUP BY date(ts)
    )
    SELECT CASE WHEN count(*)<4 THEN 'SKIP' ELSE
      round((count(*)*sum(julianday(day)*peak)-sum(julianday(day))*sum(peak))/
      (count(*)*sum(julianday(day)*julianday(day))-sum(julianday(day))*sum(julianday(day))),1)
    END FROM d;
  " 2>/dev/null || echo "SKIP")
  case "$SLOPE" in
    SKIP) echo "SKIP: monitoring_samples < 4 天" ;;
    *) if [ "$(echo "$SLOPE > 50" | bc -l 2>/dev/null)" = "1" ]; then
         echo "FAIL: RSS 日增 ${SLOPE}MB (阈值 50)"; else echo "PASS: ${SLOPE}MB/天 (阈值 50)"; fi ;;
  esac
fi
```

---

### 2. FD-LEAK — 文件描述符泄漏

```bash
if [ -z "$DB_PATH" ]; then echo "SKIP: 无数据库"
else
  SLOPE=$(sqlite3 "$DB_PATH" "
    WITH d AS (
      SELECT date(ts) as day, max(open_fds) as peak
      FROM monitoring_samples WHERE ts >= date('now','-7 days')
      GROUP BY date(ts)
    )
    SELECT CASE WHEN count(*)<4 THEN 'SKIP' ELSE
      round((count(*)*sum(julianday(day)*peak)-sum(julianday(day))*sum(peak))/
      (count(*)*sum(julianday(day)*julianday(day))-sum(julianday(day))*sum(julianday(day))),1)
    END FROM d;
  " 2>/dev/null || echo "SKIP")
  case "$SLOPE" in
    SKIP) echo "SKIP: 数据不足" ;;
    *) if [ "$(echo "$SLOPE > 10" | bc -l 2>/dev/null)" = "1" ]; then
         echo "FAIL: FD 日增 ${SLOPE} (阈值 10)"; else echo "PASS: ${SLOPE}/天 (阈值 10)"; fi ;;
  esac
fi
```

---

### 3. ERR-CLUSTER — 错误聚类

```bash
LOGDIR="${LOG_DIR:-logs}"
if [ -d "$LOGDIR" ]; then
  TOP=$(find "$LOGDIR/" -name "*.log" -mtime -7 | xargs cat 2>/dev/null | \
    jq -r 'select(.level=="ERROR")|"\(.module//"?")|\(.event//.message//"?")"' 2>/dev/null | \
    sort | uniq -c | sort -rn | head -1)
  CNT=$(echo "$TOP" | awk '{print $1}')
  if [ -z "$CNT" ]||[ "$CNT" -eq 0 ]; then echo "PASS: 无 ERROR"
  elif [ "$CNT" -gt 10 ]; then echo "FAIL: $(echo "$TOP"|cut -d' ' -f2-) ($CNT 次/7天)"
  else echo "PASS: 最高 $CNT 次/7天 (阈值 10)"; fi
else echo "SKIP: 无日志目录"; fi
```

---

### 4. PIPELINE — 管道瓶颈

```bash
LOGDIR="${LOG_DIR:-logs}"
if [ -d "$LOGDIR" ]; then
  P95=$(find "$LOGDIR/" -name "*.log" -mtime -30 | xargs cat 2>/dev/null | \
    jq -r 'select(.data.elapsed_s!=null)|.data.elapsed_s' 2>/dev/null | sort -n | \
    awk '{a[NR]=$1}END{print a[int(NR*0.95)]}' 2>/dev/null || echo "0")
  P50=$(find "$LOGDIR/" -name "*.log" -mtime -60 | xargs cat 2>/dev/null | \
    jq -r 'select(.data.elapsed_s!=null)|.data.elapsed_s' 2>/dev/null | sort -n | \
    awk '{a[NR]=$1}END{print a[int(NR*0.50)]}' 2>/dev/null || echo "0")
  if [ "$P95" = "0" ]||[ "$P50" = "0" ]; then echo "SKIP: 无耗时数据"
  elif [ "$(echo "$P95 > $P50 * 2"|bc -l 2>/dev/null)" = "1" ]; then
    echo "WARN: P95=${P95}s > 2× P50=${P50}s"; else echo "PASS: P95=${P95}s P50=${P50}s"; fi
else echo "SKIP: 无日志目录"; fi
```

---

### 5. HEALTH — 健康检查通过率

```bash
if [ -n "$DB_PATH" ]; then
  RATE=$(sqlite3 "$DB_PATH" "
    SELECT round(1.0*sum(CASE WHEN passed THEN 1 ELSE 0 END)/count(*),2)
    FROM health_checks WHERE ts>=date('now','-7 days');
  " 2>/dev/null || echo "SKIP")
  if [ "$RATE" = "SKIP" ]; then echo "SKIP: 无数据"
  elif [ "$(echo "$RATE < 0.8"|bc -l 2>/dev/null)" = "1" ]; then
    echo "FAIL: 通过率=$RATE (阈值 0.8)"; else echo "PASS: 通过率=$RATE"; fi
else echo "SKIP: 无数据库"; fi
```

---

### 6. SCHEDULER — 调度可靠性

```bash
if [ -n "$DB_PATH" ]&&[ "$(date +%u)" -le 5 ]; then
  HAS=$(sqlite3 "$DB_PATH" "SELECT count(*) FROM monitoring_samples WHERE date(ts)=date('now');" 2>/dev/null||echo "0")
  if [ "$HAS" -eq 0 ]; then echo "FAIL: 今日无 monitoring_samples"
  else echo "PASS: 今日 $HAS 条"; fi
else echo "SKIP: 无数据库或非交易日"; fi
```

---

### 7. EXIT-CODE — CLI 可用性

```bash
cd "$(git rev-parse --show-toplevel)"
CLI=$(awk '/\[project\.scripts\]/{f=1;next} f&&/=/ {print $1;exit}' pyproject.toml 2>/dev/null)
if [ -z "$CLI" ]; then echo "SKIP: 无 CLI 定义"
elif $CLI --help >/dev/null 2>&1; then echo "PASS: CLI 可用"
else echo "FAIL: CLI 不可用 ($CLI --help 失败)"; fi
```

---

### 8. RSS-DELTA — 单次内存增量

```bash
cd "$(git rev-parse --show-toplevel)"
CLI=$(awk '/\[project\.scripts\]/{f=1;next} f&&/=/ {print $1;exit}' pyproject.toml 2>/dev/null)
if [ -z "$CLI" ]; then echo "SKIP: 无 CLI"
else
  DELTA=$(python -c "
import psutil, os, subprocess
pid = os.getpid()
before = psutil.Process(pid).memory_info().rss / 1024**2
subprocess.run('$CLI --help', shell=True, capture_output=True)
after = psutil.Process(pid).memory_info().rss / 1024**2
print(round(after - before, 1))
" 2>/dev/null || echo "SKIP")
  if [ "$DELTA" = "SKIP" ]; then echo "SKIP: psutil 不可用"
  elif [ "$(echo "$DELTA > 200" | bc -l 2>/dev/null)" = "1" ]; then
    echo "WARN: RSS 增量 ${DELTA}MB (阈值 200)"
  else echo "PASS: ${DELTA}MB (阈值 200)"; fi
fi
```

---

## 执行流程

### 1. 逐条执行 8 项检查
按编号顺序，每条输出一行结论。

### 2. 汇总报告

```text
## FW-INSPECT 巡检报告 — Round <N>

| # | 检查项     | 结论   | 详情 |
|---|-----------|--------|------|
| 1 | MEM-LEAK  | PASS   | 3MB/天 |
| 2 | FD-LEAK   | PASS   | 1/天 |
| 3 | ERR-CLUSTER | FAIL | KeyError (23次/7天) |
| 4 | PIPELINE  | SKIP   | 无数据 |
| 5 | HEALTH    | SKIP   | 无数据 |
| 6 | SCHEDULER | PASS   | 今日 144 条 |
| 7 | EXIT-CODE | SKIP   | 无 CLI |
| 8 | RSS-DELTA | SKIP   | 无 CLI |

FAIL:1  WARN:0  SKIP:4  PASS:3
```

### 4. 自动派发

每项 FAIL/WARN 生成 milestone 文件并通过 subagent 派发：

```bash
mkdir -p /tmp/fw-flywheel/$PROJECT
cat > "/tmp/fw-flywheel/$PROJECT/milestone-${CHECK_ID}.md" << EOF
# [fwp-inspect][${CHECK_ID}] ${TITLE}

| 字段 | 值 |
|------|-----|
| 来源 | fw-inspect Round <N> |
| 检查项 | ${CHECK_ID} |
| 严重度 | $( [ "${RESULT}" = "FAIL" ] && echo "CRITICAL" || echo "WARNING" ) |
| 证据 | ${DETAIL} |
| 判定阈值 | ${THRESHOLD} |
EOF
```

```text
Agent(description: "fw-plan: ${TITLE}", subagent_type: "fwp-plan",
  prompt: "milestone: /tmp/fw-flywheel/$PROJECT/milestone-${CHECK_ID}.md")
```

### 5. 状态持久化

```text
.claude/state/fwp-inspect/
  round.md
  findings.json    # [{id, check_id, result, consecutive_rounds, auto_escalated}]
```

## 约束

- **固定检查项**：8 条，每条有确定的命令+阈值，不依赖 LLM 主观判断
- **结论二值化**：只有 PASS/FAIL/WARN/SKIP 四种
- **自动派发**：FAIL→CRITICAL, WARN→WARNING，通过 subagent 派发 fw-plan
- **SKIP 不阻塞**：数据不足时标注 SKIP，记录到 findings 等待下一轮
- **禁止用户交互**：严禁 `AskUserQuestion`
