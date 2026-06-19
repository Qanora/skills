# 飞轮层间内容传递机制分析

逐条审查 7 个跨层数据通道的传递方式、数据量、效率和风险。

---

## 传递拓扑（全部 subagent 隔离）

```
lp-up ──① milestone 文件 → lp-ms ──② ctx 文件 → lp-mr ──③ ctx 文件 → lp-dev ──⑥ HANDOFF + result 文件 → lp-mr
lp-dp ──① milestone 文件 → lp-ms                                                       │
                                 ② status 文件 ↩ (回传)                                 ④ ci 文件 (fix 模式)
                                                                                       ⑦ diff 文件 → simplify
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

**评估**：✅ **已修复**。lp-ms → lp-mr 改为 subagent 调用。lp-ms 写 `ctx-<N>.md` → Agent(lp-mr) → lp-mr 结束时写 `status-<N>.md` → lp-ms 读取判断是否继续下一个 issue。

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

| 通道 | 调用方式 | 数据量 | 隔离 | 状态 |
|------|---------|--------|------|------|
| ① lp-up/lp-dp → lp-ms | subagent + milestone 文件 | ~300B | ✅ | ✅ |
| ② lp-ms → lp-mr | **subagent + status 文件** | ctx 文件 | ✅ | ✅ 已斩断 |
| ③ lp-mr → lp-dev (dev) | subagent + ctx 文件 | ~200B | ✅ | ✅ |
| ④ lp-mr → lp-dev (fix) | subagent + ci 文件 | ≤200 行 | ✅ | ✅ 已截断 |
| ⑤ 元数据传递 | ctx 文件 | ~200B | ✅ | ✅ 已包含 fix_round |
| ⑥ lp-dev → lp-mr | HANDOFF + result 文件 | ~50B + 200B | ✅ | ✅ 含改动摘要 |
| ⑦ lp-dev → simplify | subagent + diff 文件 | diff 文件 | ✅ | ✅ |

## Token 风险排名（修复后）

```
🟢 通道 ①⑥⑦ — 设计良好，Prompt 永远 ~80 字节
🟢 通道 ② — 已斩断：subagent + status-<N>.md 回传
🟢 通道 ③④⑤ — 已修复：ctx/ci/result 文件协议
```

**全部 7 个通道现在都是 subagent 隔离 + 文件传递。Prompt 不再承载数据。**

## 关键发现

1. **HANDOFF + 文件双通道是最佳模式** — HANDOFF 传控制信号（~50B），文件传数据（≤200 行），各司其职。

2. **lp-ms → lp-mr 已斩断** — 飞轮中最后一条同会话调用链路已消除。lp-ms 通过 `status-<N>.md` 判断 issue 完成状态，保持串行依赖的同时实现完全隔离。

3. **`general-purpose` 是合理的 workaround** — lp-dev 和 lp-mr 作为 skill 没有独立的 subagent type。通过 `general-purpose` + `/lp-xx` prompt 是正确的调用方式。
