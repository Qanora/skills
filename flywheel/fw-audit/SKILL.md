---
name: fw-audit
description: [飞轮] 审计自身——6 条固定审计检查项，扣分制评分，≤C 自动生成 DESIGN milestone 派发 fw-plan
---

# FW-AUDIT（飞轮审计 · 用户级）

执行 6 条固定审计检查项，扣分制评分（满分 100）。评分 ≤ C（<75）自动生成 DESIGN milestone 并通过 subagent 派发 fw-plan。

> **用户级 skill**：跨项目生效。每条检查项有固定的扣分规则，不由 LLM 主观评分。

## 上下文检测

```bash
WORKSPACE=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$WORKSPACE"
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
echo "[fw-audit] WORKSPACE=$WORKSPACE REPO=$REPO"
```

## 调用方式

```text
/fw-audit                          # 审计当前会话 + 7 天历史
/fw-audit --since <date>           # 指定起始日期
/fw-audit --resume                 # 从上一轮恢复
```

## 6 条固定审计检查项

每项有确定扣分值，初始 100 分，逐项扣减。

---

### 1. STEP-GAP — 流程步骤缺失（权重 40%）

逐 skill 对照 SKILL.md 预期步骤与实际 tool call 序列，缺一步扣 15%。

```bash
# 检测方法：对比当前会话中的 tool calls 序列与各 skill 的 SKILL.md 流程步骤
echo "=== STEP-GAP 检查 ==="
echo "检查各 skill: fw-plan(1-8), fw-ship(1a-7), fw-build(1-9), fw-inspect(A-H), fw-audit(1-6)"
```

| 缺失步骤 | 扣分 |
|---------|------|
| fw-ship 跳过步骤 3 (监控 MR) | -15 |
| fw-build 跳过步骤 7 (本地验证) | -15 |
| fw-plan 跳过步骤 4 (依赖分析) | -15 |
| fw-inspect 跳过步骤 4 (自动派发) | -15 |
| fw-audit 跳过步骤 2 (对照检查) | -15 |

---

### 2. ASK-USER — 冗余用户交互（权重 20%）

统计当前会话中 AskUserQuestion 的调用次数，每次扣 10%。

```bash
echo "=== ASK-USER 检查 ==="
# 检查会话中是否存在 AskUserQuestion
# 飞轮 skill 严格禁止 AskUserQuestion
```

| 交互次数 | 扣分 |
|---------|------|
| 0 | 0 |
| 1 | -10 |
| 2+ | -20（直接归零此项） |

---

### 3. CLEANUP-MISS — 分支清理遗漏（权重 15%）

检查 GitHub 上已 merged 的 PR 是否仍有残留 feature 分支。

```bash
echo "=== CLEANUP-MISS 检查 ==="
cd "$(git rev-parse --show-toplevel)"
git fetch --prune
# 获取已合并 PR 的分支列表
MERGED=$(gh pr list --state merged --limit 50 --json headRefName --jq '.[].headRefName' | sort -u)
# 检查本地残留
LOCAL=$(git branch | grep "feature/" | sed 's/^[* ]*//' | sort)
LOCAL_LEAK=$(comm -12 <(echo "$MERGED") <(echo "$LOCAL") 2>/dev/null | wc -l)
# 检查远程残留
REMOTE=$(git branch -r | grep "origin/feature/" | sed 's/.*origin\///' | sort)
REMOTE_LEAK=$(comm -12 <(echo "$MERGED") <(echo "$REMOTE") 2>/dev/null | wc -l)
echo "本地残留: $LOCAL_LEAK, 远程残留: $REMOTE_LEAK"
```

| 残留分支数 | 扣分 |
|-----------|------|
| 0 | 0 |
| 1-2 | -5 |
| 3-5 | -10 |
| >5 | -15（直接归零此项） |

---

### 4. FIX-LIMIT — 修复重试命中上限（权重 15%）

统计 `.claude/state/` 中 fix_round >= 3 的 issue 数量。

```bash
echo "=== FIX-LIMIT 检查 ==="
cd "$(git rev-parse --show-toplevel)"
HIT=$(find .claude/state/ -name "*.fix_round" -exec cat {} \; 2>/dev/null | awk '$1>=3' | wc -l)
echo "fix_round >= 3 的 issue: $HIT 个"
```

| 命中上限数 | 扣分 |
|-----------|------|
| 0 | 0 |
| 1 | -5 |
| 2 | -10 |
| >=3 | -15（直接归零此项） |

---

### 5. STATE-STALE — 状态文件残留（权重 5%）

检查 `.claude/state/` 是否有超过 7 天未更新的文件（可能是已放弃的 issue 残留）。

```bash
echo "=== STATE-STALE 检查 ==="
cd "$(git rev-parse --show-toplevel)"
STALE=$(find .claude/state/ -type f -mtime +7 2>/dev/null | wc -l)
echo "超 7 天残留文件: $STALE 个"
```

| 残留文件 | 扣分 |
|---------|------|
| 0 | 0 |
| 1-3 | -3 |
| >3 | -5（直接归零此项） |

---

### 6. HANDOFF-FMT — HANDOFF 信号规范（权重 5%）

检查最近的 result 文件中的 HANDOFF 格式是否标准。

```bash
echo "=== HANDOFF-FMT 检查 ==="
# 检查 /tmp/fw-flywheel/$PROJECT/result-*.md 中是否有非标准状态
NONSTD=$(grep -r "状态" /tmp/fw-flywheel/$PROJECT/result-*.md 2>/dev/null | \
  grep -v "DEV_DONE\|FIX_DONE\|FAIL_DONE" | wc -l)
echo "非标准 HANDOFF: $NONSTD 个"
```

| 非标准数 | 扣分 |
|---------|------|
| 0 | 0 |
| 1+ | -5（直接归零此项） |

---

## 执行流程

### 1. 逐条执行 6 项检查

按编号顺序，每项输出扣分和原因。

### 2. 计算总分

```text
初始: 100
STEP-GAP:     -X  (权重 40%, 扣分上限 40)
ASK-USER:     -X  (权重 20%, 扣分上限 20)
CLEANUP-MISS: -X  (权重 15%, 扣分上限 15)
FIX-LIMIT:    -X  (权重 15%, 扣分上限 15)
STATE-STALE:  -X  (权重  5%, 扣分上限  5)
HANDOFF-FMT:  -X  (权重  5%, 扣分上限  5)
─────────────────────
总分: XX  →  A(90+)/B(75-89)/C(60-74)/D(<60)
```

### 3. 汇总报告

```text
## FW-AUDIT 审计报告

| # | 检查项       | 扣分 | 详情 |
|---|-------------|------|------|
| 1 | STEP-GAP    | -15  | fw-ship 跳过步骤 3 (监控) |
| 2 | ASK-USER    | 0    | 无冗余交互 |
| 3 | CLEANUP-MISS | -5  | 本地残留 1 分支 |
| 4 | FIX-LIMIT   | 0    | 无命中上限 |
| 5 | STATE-STALE | 0    | 无残留 |
| 6 | HANDOFF-FMT | 0    | 全部标准 |

总分: 80 → B
```

### 4. 评分触发

| 评分 | 动作 |
|------|------|
| A (≥90) / B (75-89) | 记录，不派发 |
| **C (60-74) 连续 2 轮** | 自动生成 WARNING DESIGN milestone → fw-plan |
| **D (<60)** | 立即生成 CRITICAL DESIGN milestone → fw-plan |

```bash
mkdir -p /tmp/fw-flywheel/$PROJECT/$PROJECT
cat > "/tmp/fw-flywheel/$PROJECT/milestone-audit-${ROUND}.md" << EOF
# [fw-audit][DESIGN] 飞轮健康度 ${SCORE}分 (${GRADE})

| 字段 | 值 |
|------|-----|
| 来源 | fw-audit Round ${ROUND} |
| 评分 | ${SCORE} → ${GRADE} |
| 连续低分轮数 | ${CONSECUTIVE} |
| 主要失分项 | ${TOP_LOSSES} |
| 建议方向 | ${SUGGESTIONS} |
EOF
```

```text
Agent(description: "fw-plan: 飞轮优化", subagent_type: "fwp-plan",
  prompt: "milestone: /tmp/fw-flywheel/$PROJECT/milestone-audit-${ROUND}.md")
```

### 5. 状态持久化

```text
.claude/state/fw-audit/
  audit.md              # 最近审计报告
  skill_scores.json     # 评分历史 + consecutive_low 计数
```

## 约束

- **固定检查项**：6 条，每条有确定的扣分规则
- **机械评分**：扣分由固定规则计算，不由 LLM 主观判断
- **自动派发**：C 连续 2 轮或 D 立即生成 DESIGN milestone → fw-plan
- **禁止用户交互**：严禁 `AskUserQuestion`
