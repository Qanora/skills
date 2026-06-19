# 飞轮架构全景图

## 用户入口（5 个命令）

```
/fwp-setup  <repo>       /fwp-plan  <需求>      /fwp-debug <bug>     /fwp-inspect [--run]   /fw-audit             /fwp-resume
    │                        │                      │                     │                      │                      │
    │ 输入: 仓库名            │ 输入: 一句话需求      │ 输入: 一句话bug       │ 输入: (可选--run)      │ 输入: 无              │ 输入: 无
    │                        │                      │                     │                      │                      │
    ▼                        ▼                      ▼                     ▼                      ▼                      ▼
┌──────────┐           ┌──────────┐           ┌──────────┐           ┌──────────┐           ┌──────────┐           ┌──────────┐
│ 9阶段初始化│           │ 需求→拆解 │           │ 复现→收集 │           │ 8项固定   │           │ 6项固定   │           │ 扫描state │
│ 仓库/CI/  │           │ Issue→依赖│           │ 证据→issue│           │ 巡检→PASS │           │ 审计→扣分 │           │ +GitHub   │
│ 标签/脚本 │           │ 批次→派发 │           │ →派发     │           │ /FAIL/WARN│           │ →评分     │           │ →继续执行 │
└─────┬─────┘           └─────┬─────┘           └─────┬─────┘           └─────┬─────┘           └─────┬─────┘           └─────┬─────┘
      │                       │                      │                     │                      │                      │
      │ 输出:                  │ 输出:                 │ 输出:                │ 输出:                 │ 输出:                 │ 输出:
      │ 飞轮就绪的仓库          │ milestone + issues    │ bug issue            │ 巡检报告               │ 审计报告+评分          │ 恢复计划+结果
      │                       │                      │                     │ FAIL/WARN →自动派发    │ C≤2轮/D →自动派发     │
      ▼                       ▼                      ▼                     ▼                      ▼                      ▼
    完成                    Agent(fwp-ship)        Agent(fwp-plan)      Agent(fwp-plan)        Agent(fwp-plan)        Agent(fwp-ship/fwp-plan)
                                │                      │                     │                      │                      │
                                └──────────────────────┴─────────────────────┴──────────────────────┘
                                                       │
                                                       ▼
```

## Agent 自动调用链（用户不可见）

```
                          fwp-plan 输出 milestone
                                │
                                │ 逐 issue 通过 subagent 调用
                                ▼
                    ┌──────────────────────┐
                    │      FWP-SHIP        │  ← Agent(fwp-ship)
                    │  MR 全生命周期         │
                    │                      │
                    │  [文件协议]            │
                    │  写 ctx-<N>.md        │
                    │  读 result-<N>.md     │
                    │  写 status-<N>.md     │
                    │  写 ci-<mr>.md(fix时) │
                    └──────────┬───────────┘
                               │
                               │ 开发/修复时通过 subagent 调用
                               ▼
                    ┌──────────────────────┐
                    │      FWP-BUILD       │  ← Agent(fwp-build)
                    │  TDD 红→绿→重构       │
                    │                      │
                    │  [文件协议]            │
                    │  读 ctx-<N>.md        │
                    │  读 ci-<mr>.md(fix时) │
                    │  写 result-<N>.md     │
                    │  写 diff-<N>.md       │
                    │                      │
                    │  子调用: simplify     │  ← Agent(claude)
                    └──────────────────────┘
```

## 文件传递协议

```
/tmp/fw-flywheel/$PROJECT/
├── milestone-<id>.md    fwp-inspect → fwp-plan   里程碑描述
├── milestone-audit-N.md fw-audit    → fwp-plan   审计发现
├── milestone-bug-N.md   fwp-debug   → fwp-plan   bug报告
├── ctx-<N>.md           fwp-ship    → fwp-build  开发上下文+issue内容+fix_round
├── ci-<mr>.md           fwp-ship    → fwp-build  CI失败日志(截断≤200行)
├── result-<N>.md        fwp-build   → fwp-ship   改动摘要+文件数+行数
├── status-<N>.md        fwp-ship    → fwp-plan   最终状态(MERGED/BLOCKED_CI/...)
├── diff-<N>.md          fwp-build   → simplify   当前diff
└── bug-body.md          fwp-debug   内部使用      bug issue body
└── rss_delta            fwp-inspect 内部使用      RSS采样
```

## 完整输入输出矩阵

| Skill | 调用者 | 输入来源 | 输入内容 | 输出内容 | 输出去向 |
|-------|--------|---------|---------|---------|---------|
| fwp-setup | 用户 | 命令行 | 仓库名 | GitHub仓库+CI+标签+脚本 | 文件系统 |
| fwp-plan | 用户/Agent | 命令行/文件 | 需求描述/milestone文件 | milestone + issues | GitHub + Agent(fwp-ship) |
| fwp-debug | 用户 | 命令行 | bug描述 | bug issue | GitHub + Agent(fwp-plan) |
| fwp-inspect | 用户 | (无/--run) | 项目运行时数据 | 巡检报告(8项PASS/FAIL) | Agent(fwp-plan) |
| fw-audit | 用户 | (无) | 会话上下文+state | 审计报告(6项评分) | Agent(fwp-plan) |
| fwp-resume | 用户 | (无) | .claude/state/ + GitHub | 恢复计划+继续执行 | Agent(fwp-ship/fwp-plan) |
| fwp-ship | fwp-plan/fwp-resume | ctx文件+GitHub | issue编号+上下文 | MR+merge+status文件 | GitHub + fwp-build + fwp-plan |
| fwp-build | fwp-ship | ctx/ci文件+GitHub | issue+CI log | 代码改动+HANDOFF+result文件 | 文件系统 + fwp-ship |
| simplify | fwp-build | diff文件 | 代码diff | 代码审查意见 | fwp-build |

## 跨项目并发隔离

```
会话A: /root/workspace/pp_tracer    会话B: /root/workspace/alpha-screener
      │                                    │
      ├─ .claude/state/         ✅独立       ├─ .claude/state/         ✅独立
      ├─ /tmp/fw-flywheel/pptracer/ ✅独立   ├─ /tmp/fw-flywheel/alpha-screener/ ✅独立
      ├─ ~/.pptracer/           ✅独立       ├─ ~/.alphascreener/     ✅独立
      ├─ gh → Qanora/pp_tracer  ✅独立       ├─ gh → Qanora/alpha-screener ✅独立
      └─ CWD 隔离               ✅独立       └─ CWD 隔离               ✅独立
```
