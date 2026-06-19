# /tmp/fw-flywheel 文件传递协议

飞轮跨层数据传递通过 `/tmp/fw-flywheel/$PROJECT/` 目录下的临时 markdown 文件完成。Agent prompt 只传文件路径，subagent 启动后自己读文件。

## 核心原则

1. **Prompt 永远轻量** — Agent prompt 只含文件路径引用，不含实际数据
2. **消费者自取** — subagent 启动后自己 `Read` 所需的上下文文件
3. **生产者截断** — 大日志/输出写入前截断（≤200 行或 10KB）
4. **HANDOFF 仍用于触发信号** — 文件用于传递数据，HANDOFF 用于传递控制信号
5. **fw-ship 负责清理** — merge 或 abandon 后在 cleanup 步骤删除相关临时文件

## 文件格式

### milestone-<finding-id>.md
**生产者**: fwp-inspect, fw-audit
**消费者**: fwp-plan

```markdown
# [fwp-inspect][ARCHITECTURE] 内存泄漏：RSS 7 日增长 +320MB

| 字段 | 值 |
|------|-----|
| 来源 | fwp-inspect Round 3 |
| 严重度 | CRITICAL |
| 类别 | ARCHITECTURE |
| 证据 | RSS 7 日斜率 +45MB/天，monitoring_samples 30 天数据 |
| 根因假设 | collector 模块未释放 trace buffer |
| 预期收益 | 消除 OOM，稳定长期运行 |
| 建议范围 | ppt/collector.py, ppt/tracer.py |
```

### ctx-<issue-number>.md
**生产者**: fwp-ship
**消费者**: fwp-build

```markdown
# Issue #42 开发上下文

| 字段 | 值 |
|------|-----|
| issue | #42 |
| 分支 | feature/issue-42 |
| 基址 | origin/master |
| fix_round | 0（首次开发） |
| 前次 commit | — |
| 前次改动文件 | — |

## Issue 内容

<gh issue view 42 的输出>
```

fix_round > 0 时：
```markdown
| fix_round | 2/3 |
| 前次 commit | abc123 ("fix: address CI failure (#42)") |
| 前次改动 | tests/test_x.py (+12,-3), src/x.py (+5,-0) |
```

### ci-<mr-number>.md
**生产者**: fwp-ship
**消费者**: fwp-build (仅 --fix 模式)

```markdown
# MR #58 CI 失败日志

| 字段 | 值 |
|------|-----|
| MR | #58 |
| fix_round | 2/3 |
| 失败检查 | gitleaks:FAILURE, tests:FAILURE |

## 失败详情（截断 ≤200 行）

<gh pr view 输出的 CI log，截断处理>
```

### result-<issue-number>.md
**生产者**: fwp-build
**消费者**: fwp-ship

```markdown
# Issue #42 开发结果

| 字段 | 值 |
|------|-----|
| 状态 | DEV_DONE |
| 分支 | feature/issue-42 |
| 改动文件 | 3 |
| 改动行数 | +45, -12 |
| 摘要 | 添加 trace buffer 释放逻辑，修复 collector 内存泄漏 |
```

失败时：
```markdown
| 状态 | FAIL_DONE=SIMPLIFY_UNFIXABLE |
| 失败文件 | src/x.py:120-145 |
| 失败原因 | 循环依赖无法解开，需重新设计模块边界 |
```

## 生命周期

```
1. 生产者: Write 文件到 /tmp/fw-flywheel/$PROJECT/
2. 生产者: Agent(prompt="读 /tmp/fw-flywheel/$PROJECT/<file> 获取上下文")
3. 消费者: Read /tmp/fw-flywheel/$PROJECT/<file>
4. 消费者: 执行任务
5. 消费者: Write 结果到 /tmp/fw-flywheel/$PROJECT/result-<N>.md + HANDOFF
6. 生产者: Read /tmp/fw-flywheel/$PROJECT/result-<N>.md
7. fwp-ship cleanup: rm /tmp/fw-flywheel/$PROJECT/{ctx,ci,result}-<N>.md
```

## 截断规则

| 文件 | 上限 | 超出处理 |
|------|------|---------|
| ci-<mr>.md | 200 行 / 10KB | 保留前 100 行 + 后 50 行，中间标注 `... (省略 N 行) ...` |
| ctx-<N>.md | 100 行 | issue body 超过 80 行时只保留标题+前 3 段 |
| result-<N>.md | 50 行 | diff 摘要只保留文件列表+行数统计，不传完整 diff |

## 与 HANDOFF 的关系

| 数据 | 传递方式 |
|------|---------|
| 控制信号（成功/失败） | HANDOFF（终端输出） |
| 详细上下文（issue、CI log、diff） | /tmp/fw-flywheel/$PROJECT/ 文件 |
| 改动摘要 | result-<N>.md + HANDOFF |
