# 飞轮架构全景图

## 用户入口

```
/fwp-setup             /fwp-plan <需求>    /fwp-debug <bug>    /fwp-inspect        /fw-audit           /fwp-resume
    │                      │                    │                    │                   │                    │
    │ 输入: 无(自动目录名)  │ 输入: 一句话需求    │ 输入: 一句话bug      │ 输入: 无           │ 输入: 无           │ 输入: 无
    │                      │                    │                    │                   │                    │
    ▼                      ▼                    ▼                    ▼                   ▼                    ▼
┌──────────┐         ┌──────────┐         ┌──────────┐         ┌──────────┐        ┌──────────┐         ┌──────────┐
│ 9阶段初始化│         │ 需求→拆解 │         │ 复现→收集 │         │ 13项巡检  │        │ 5维度审计 │         │ 扫描state │
│ 仓库/CI/  │         │ Issue→依赖│         │ 证据→issue│         │ T1:8项机械│        │ GATES     │         │ +GitHub   │
│ 标签/脚本 │         │ 批次→派发 │         │ →派发     │         │ T2:5项LLM │        │ GUARDS    │         │ →继续执行 │
└─────┬─────┘         └─────┬─────┘         └─────┬─────┘         └─────┬─────┘        │ BEHAVIOR  │         └─────┬─────┘
      │                     │                    │                     │                │ COMMS     │               │
      │ 输出:                │ 输出:               │ 输出:                │ 输出:           │ EFFICIENCY│               │ 输出:
      │ 飞轮就绪的仓库        │ milestone+issues    │ bug issue            │ 巡检报告         └─────┬─────┘               │ 恢复结果
      │                     │                    │                     │ FAIL/WARN→派发        │                      │
      ▼                     ▼                    ▼                     ▼                      ▼                      ▼
    完成                Agent(fwp-ship)      Agent(fwp-plan)      Agent(fwp-plan)        Agent(fwp-plan)        Agent(fwp-ship/fwp-plan)
                            │                    │                     │                      │                      │
                            └────────────────────┴─────────────────────┴──────────────────────┘
                                                 │
                                                 ▼
```

## Agent 自动调用链

```
                        fwp-plan / fwp-inspect / fw-audit / fwp-debug 输出 milestone
                              │
                              │ 逐 issue 通过 subagent 调用
                              ▼
                  ┌──────────────────────┐
                  │      FWP-SHIP        │  ← Agent(fwp-ship)
                  │  MR 全生命周期        │
                  │                      │
                  │  [文件协议]           │
                  │  写 ctx-<N>.md       │
                  │  读 result-<N>.md    │
                  │  写 status-<N>.md    │
                  │  写 ci-<mr>.md(fix)  │
                  └──────────┬───────────┘
                             │
                             │ subagent 调用
                             ▼
                  ┌──────────────────────┐
                  │      FWP-BUILD       │  ← Agent(fwp-build)
                  │  TDD 红→绿→重构       │
                  │                      │
                  │  读 ctx-<N>.md       │
                  │  读 ci-<mr>.md(fix)  │
                  │  写 result-<N>.md    │
                  │  写 diff-<N>.md      │
                  │                      │
                  │  子调用: simplify     │
                  └──────────────────────┘
```

## 文件传递协议

```
/tmp/fw-flywheel/$PROJECT/
├── milestone-<id>.md     fwp-inspect → fwp-plan   巡检发现
├── milestone-audit-*.md  fw-audit    → fwp-plan   审计发现
├── milestone-bug-*.md    fwp-debug   → fwp-plan   bug报告
├── ctx-<N>.md            fwp-ship    → fwp-build  开发上下文+fix_round
├── ci-<mr>.md            fwp-ship    → fwp-build  CI失败日志(≤200行)
├── result-<N>.md         fwp-build   → fwp-ship   改动摘要
├── status-<N>.md         fwp-ship    → fwp-plan   最终状态
├── diff-<N>.md           fwp-build   → simplify   diff
├── bug-body.md           fwp-debug   内部          bug issue body
└── rss_delta             fwp-inspect 内部          RSS采样
```

## 输入输出矩阵

| Skill | 调用者 | 输入 | 输出 | 去向 |
|-------|--------|------|------|------|
| fwp-setup | 用户 | 仓库名(可选,默认目录名) | GitHub仓库+CI+标签+脚本 | 文件系统 |
| fwp-plan | 用户/Agent | 需求描述/milestone文件 | milestone+issues | GitHub + Agent(fwp-ship) |
| fwp-debug | 用户 | bug描述 | bug issue | GitHub + Agent(fwp-plan) |
| fwp-inspect | 用户 | (无) | 13项巡检报告 | Agent(fwp-plan) |
| fw-audit | 用户 | (无) | 5维度审计报告 | Agent(fwp-plan) |
| fwp-resume | 用户 | (无) | 恢复计划 | Agent(fwp-ship/fwp-plan) |
| fwp-ship | Agent | ctx文件+issue编号 | MR+merge+status文件 | GitHub+fwp-build+fwp-plan |
| fwp-build | Agent | ctx/ci文件+issue | 代码+HANDOFF+result文件 | fwp-ship |
| simplify | fwp-build | diff文件 | 审查意见 | fwp-build |

## 跨项目并发隔离

```
会话A: /root/workspace/project-a    会话B: /root/workspace/project-b
      │                                    │
      ├─ .claude/state/         ✅独立       ├─ .claude/state/         ✅独立
      ├─ /tmp/fw-flywheel/<a>/  ✅独立       ├─ /tmp/fw-flywheel/<b>/  ✅独立
      ├─ ~/.<a>/                ✅独立       ├─ ~/.<b>/                ✅独立
      ├─ gh → owner/a           ✅独立       ├─ gh → owner/b           ✅独立
      └─ CWD 隔离               ✅独立       └─ CWD 隔离               ✅独立
```
