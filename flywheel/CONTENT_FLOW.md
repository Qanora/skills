# 飞轮层间内容传递机制分析

逐条审查 7 个跨层数据通道的传递方式、数据量、效率和风险。

---

## 传递拓扑

```
lp-up ──① milestone 描述 → lp-ms ──② issue 编号 → lp-mr ──③ prompt → lp-dev ──⑥ HANDOFF → lp-mr
lp-dp ──① milestone 描述 → lp-ms                                                    │
                                                                                    ⑦ /simplify → Agent(claude)
                                                                                    │
                                                                                    ▼
                                                                               simplify
```

---

## 通道 ①：lp-up / lp-dp → lp-ms

**方式**：`Agent(subagent_type="lp-ms", prompt="...")` — subagent 调用

**传入内容**：

```text
[lp-up][ARCHITECTURE] 内存泄漏：RSS 7 日增长 +320MB

**来源**: lp-up Round 3 分析报告
**严重度**: CRITICAL
**类别**: ARCHITECTURE
**证据摘要**: RSS 7 日斜率 +45MB/天，monitoring_samples 表 30 天数据
**根因假设**: collector 模块未释放 trace buffer
**预期收益**: 消除 OOM，稳定长期运行
**建议范围**: ppt/collector.py, ppt/tracer.py
```

**数据量**：~200-500 字符，结构化 markdown

**评估**：✅ 轻量。lp-up 的分析原始数据（日志、DB 查询结果）**不传入** lp-ms——只传分析结论。lp-ms 拿到的是纯粹的需求描述。

**风险**：无。subagent 隔离保证 lp-up 的日志上下文不污染 lp-ms。

---

## 通道 ②：lp-ms → lp-mr

**方式**：`/lp-mr <issue-number>` — **同会话 skill 调用**（非 subagent）

**传入内容**：只有一个数字 `42`

**实际传递流程**：
1. lp-ms 在同一个 Claude 会话中调用 `/lp-mr 42`
2. lp-mr 的 SKILL.md 被注入当前会话
3. lp-mr 步骤 1a 自己 `gh issue view 42` 获取需求
4. lp-mr 步骤 1b 启动 subagent 调 lp-dev

**数据量**：传入参数极简（一个 int）。但 lp-mr 通过 gh 重新拉取 issue body。

**评估**：⚠️ 传入参数极简是好的，但**同会话调用是关键缺陷**：
- 多个 issue 串行执行时，每个 lp-mr 的 git/CI/分支操作上下文会**持续累积**
- 批次 3 个 issue → context 里有 3 轮 lp-mr 的完整执行记录
- lp-ms 自身不感知 issue 执行进度——它依赖于同会话的 lp-mr 输出来判断成功/失败

**改进方向**：lp-ms → lp-mr 也改为 subagent，通过 state 文件（`.claude/state/issue-<N>.status`）回传结果。

---

## 通道 ③：lp-mr → lp-dev（开发模式）

**方式**：`Agent(subagent_type="general-purpose", prompt="/lp-dev <N> ...")` — subagent 调用

**传入内容**：

```text
/lp-dev 42

当前开发分支：feature/issue-42（已从 origin/master 创建）。
请在此分支上开发，不要切回 master。
```

**数据量**：~100 字符

**评估**：⚠️ 两个问题：

1. **subagent_type 是 `general-purpose`**，不是专门的 `lp-dev`。这意味着 subagent 带着 general-purpose 的 system prompt 启动，然后才读取 lp-dev 的 SKILL.md。浪费 token 且语义不匹配。

2. **只传了 issue 编号**。lp-dev 步骤 1 自己调 `gh issue view <N>` 获取需求——这是正确的（避免 lp-mr 的上下文污染 lp-dev）。但有个边界情况：如果 issue body 很长（包含大段需求描述、技术方案），lp-dev 的 subagent 需要自己承担这些 token。

**自我拉取模式的优劣**：
- ✅ 优点：lp-mr 不污染 lp-dev，每次 dev 都是干净上下文
- ⚠️ 缺点：如果同一 issue 多次 fix，每次都重新 gh 拉取

---

## 通道 ④：lp-mr → lp-dev（修复模式）

**方式**：`Agent(subagent_type="general-purpose", prompt="/lp-dev <N> --fix <mr> ...")` — subagent 调用

**传入内容**：

```text
/lp-dev 42 --fix 58

## CI 失败
gitleaks: FAILURE
tests: FAILURE
  FAILED tests/test_collector.py::test_trace_buffer - AssertionError: ...
```

**数据量**：~500-5000 字符（取决于 CI log 长度）

**评估**：⚠️ **这是最大的 token 风险点**。CI log 可能非常大：
- pytest 全量输出可能上万行
- linter 错误列表可能几百行
- 如果 CI 有多个 job 全部失败，日志可能超过 10KB

当前做法是把完整 CI log 直接塞进 subagent prompt。应该：
1. 按错误类型聚类后只传摘要
2. CI log > 1000 行时只传前 50 + 后 20 行
3. 或者让 lp-dev 自己 `gh pr view <mr> --json statusCheckRollup` 拉取（自我拉取模式）

---

## 通道 ⑤：lp-mr → lp-dev 之间缺少的状态传递

**当前缺失**：lp-mr 和 lp-dev 之间没有**结构化的上下文传递**。

lp-dev 不知道：
- 这是第几次 fix（fix_round）→ 无法针对性调整策略
- 上一次 fix 改了哪些文件 → 可能重复改同一处
- 原始 issue 的依赖关系 → 可能引入不必要的改动

改进：在 prompt 中附加结构化元数据：

```text
/lp-dev 42 --fix 58

## 元数据
- fix_round: 2/3
- 上一轮 fix: commit abc123 ("fix: address CI failure (#42)")
- 上一轮改动: tests/test_collector.py (+12, -3), ppt/collector.py (+5, -0)

## CI 失败（摘要）
- gitleaks: FAILURE (1 处泄露)
- tests: FAILURE (2/45 失败)
```

---

## 通道 ⑥：lp-dev → lp-mr（HANDOFF 返回）

**方式**：subagent 终端输出的 `---HANDOFF---` 信号块

**传入内容**：

成功：
```text
---HANDOFF---
DEV_DONE=feature/issue-42
---HANDOFF_END---
```

失败：
```text
---HANDOFF---
FAIL_DONE=SIMPLIFY_UNFIXABLE
---HANDOFF_END---
```

**数据量**：~40-60 字节

**评估**：✅ 极简。这是整个飞轮中设计最好的接口——只传一个成功/失败信号 + 分支名。

**但缺少的内容**：
- 成功时：没有改动摘要（改了多少文件、多少行、关键变更是什么）
- 失败时：没有失败详情（哪个文件、什么原因）
- 修复时：没有 CI 修复验证结果

改进：HANDOFF 增加可选的摘要字段：

```text
---HANDOFF---
DEV_DONE=feature/issue-42
FILES=3
DELTA=+45,-12
SUMMARY=添加 trace buffer 释放逻辑，修复 collector 内存泄漏
---HANDOFF_END---
```

---

## 通道 ⑦：lp-dev → simplify

**方式**：`Agent(subagent_type="claude", prompt="/simplify ...")` — subagent 调用

**传入内容**：

```text
执行 /simplify 对当前改动进行代码审查
```

**数据量**：~30 字符

**评估**：✅ 极简。simplify 的 subagent 在当前工作目录的 git 状态下运行，自动检测改动。不需要显式传 diff。

**注意**：simplify 可能重复运行多次（"重复直到 simplify 返回无问题"）。每次都是独立 subagent，不累积上下文。

---

## 总结矩阵

| 通道 | 调用方式 | 数据量 | 隔离 | 问题 |
|------|---------|--------|------|------|
| ① lp-up/lp-dp → lp-ms | subagent | ~300B | ✅ | — |
| ② lp-ms → lp-mr | **同会话 skill** | 1 个 int | ❌ | 批次串行 context 累积 |
| ③ lp-mr → lp-dev (dev) | subagent | ~100B | ✅ | general-purpose 类型不匹配 |
| ④ lp-mr → lp-dev (fix) | subagent | ~500-5000B | ✅ | CI log 可能超大 |
| ⑤ 元数据传递 | **缺失** | 0 | — | lp-dev 不知道 fix_round/历史改动 |
| ⑥ lp-dev → lp-mr | HANDOFF 信号 | ~50B | ✅ | 缺少改动摘要/失败详情 |
| ⑦ lp-dev → simplify | subagent | ~30B | ✅ | — |

## Token 风险排名

```
🔴 通道 ④ — CI log 直接塞 prompt（可能 > 10KB）
🟡 通道 ② — 同会话串行累积（3 个 issue ≈ 3× lp-mr context）
🟡 通道 ⑤ — 缺失元数据导致 lp-dev 盲目修复、重复改动
🟢 通道 ①⑥⑦ — 设计良好，数据量可控
```

## 关键发现

1. **HANDOFF 是设计最好的接口** — 极简、结构化、可解析。应作为跨层通信的唯一标准格式。

2. **自我拉取模式是正确的** — lp-dev 自己 `gh issue view`、lp-mr 自己检测上下文。避免了跨层传递大段数据。

3. **通道 ② 的同会话调用是刻意的** — 为了保证串行依赖。但这意味着 lp-ms 必须感知所有下层操作的成败。改为 subagent + state 文件模式可以同时保持串行和隔离。

4. **没有一处使用了 `subagent_type="lp-dev"`** — 因为 lp-dev 不是注册的 subagent type（它只是一个 skill）。lp-mr 用 `general-purpose` 然后 prompt 里写 `/lp-dev`，是 workaround。
