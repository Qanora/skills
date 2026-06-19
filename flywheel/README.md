# 飞轮（Flywheel）开发体系

8 个 skill，从项目初始化到持续交付的全流程自动化。双层反馈环——**fwp-inspect** 巡检项目质量，**fw-audit** 审计 AI 安全治理。

## 架构总览

```
┌──────────────────────────────────────────────────────────────┐
│                    fwp-setup（项目初始化）                      │
│  仓库 → 保护 → CI → 质量工具 → 模板 → 标签 → 脚本              │
└────────────┬─────────────────────────────────────────────────┘
             ▼
┌──────────────────────────────────────────────────────────────┐
│                    双层反馈环                                  │
│                                                              │
│  fwp-inspect（项目巡检）          fw-audit（飞轮审计）          │
│  Tier1: 8项机械运行时检查         GATES   门禁完整性            │
│  Tier2: 5项LLM代码审查            GUARDS  约束有效性            │
│  发现: bug/架构/算法/开源/完备      BEHAVIOR 行为审计            │
│                                   COMMS   信息传递              │
│                                   EFFICIENCY 效率指标           │
└────────────┬──────────────────────────┬───────────────────────┘
             │ milestone (subagent)     │ milestone (subagent)
             ▼                          ▼
┌──────────────────────────────────────────────────────────────┐
│                    fwp-plan（需求拆解 → Issue 编排）            │
└────────────┬─────────────────────────────────────────────────┘
             │ Agent(fwp-ship)
             ▼
┌──────────────────────────────────────────────────────────────┐
│                    fwp-ship（MR 交付）                         │
│  开分支 → Agent(fwp-build) → commit+push+MR → 监控CI          │
│  CI fail → 收集日志 → Agent(fwp-build --fix) → push → 监控     │
│  CI green → squash merge → 清理                               │
└────────────┬─────────────────────────────────────────────────┘
             │ Agent(fwp-build)
             ▼
┌──────────────────────────────────────────────────────────────┐
│                    fwp-build（TDD 开发）                       │
│  TDD 红→绿→重构 → lint → test → simplify → HANDOFF            │
└──────────────────────────────────────────────────────────────┘
             │ merge
             ▼
         fwp-inspect（再巡检 → 验证修复 → 发现新问题 → ...）
         fw-audit（再审计 → 验证改进 → 发现新偏差 → ...）
```

## Skill 速查

| 类别 | Skill | 调用 | 职责 |
|------|-------|------|------|
| 项目 | fwp-setup | `/fwp-setup` | 初始化新项目（自动用目录名） |
| 项目 | fwp-plan | `/fwp-plan <需求>` | 需求拆解 → Issue → 派发 |
| 项目 | fwp-debug | `/fwp-debug <bug>` | Bug复现 → 证据 → 派发 |
| 项目 | fwp-inspect | `/fwp-inspect` | 13项全量巡检（T1机械+T2 LLM） |
| 项目 | fwp-resume | `/fwp-resume` | 继续中断的 milestone |
| 项目 | fwp-ship | Agent 调用 | MR 全生命周期（git/gh/CI） |
| 项目 | fwp-build | Agent 调用 | TDD 开发（红→绿→重构→HANDOFF） |
| 飞轮 | fw-audit | `/fw-audit` | AI 安全治理审计（5维度） |

## 核心设计

### 关注点分离

- **fwp-setup** — 只创建配置/模板/脚本，不写业务代码
- **fwp-inspect / fw-audit** — 只观察/分析/报告，不写代码
- **fwp-plan** — 只编排 issue，不操作 MR 或代码
- **fwp-ship** — 只操作 git/gh，通过 subagent 委托 fwp-build
- **fwp-build** — 只写代码+本地验证，不操作 git

### Subagent 隔离

全部跨层调用通过 subagent，0 同会话调用：

```
fwp-inspect → Agent(fwp-plan)    fw-audit → Agent(fwp-plan)
fwp-debug   → Agent(fwp-plan)    fwp-plan → Agent(fwp-ship)
fwp-ship    → Agent(fwp-build)   fwp-build → Agent(simplify)
```

### 文件传递协议

Prompt 永远轻量（~80字节），数据通过 `/tmp/fw-flywheel/$PROJECT/` 传递：

```
ctx-<N>.md   ← fwp-ship写, fwp-build读     (上下文+fix_round)
ci-<mr>.md   ← fwp-ship写, fwp-build读     (CI log, ≤200行)
result-<N>.md ← fwp-build写, fwp-ship读    (改动摘要)
status-<N>.md ← fwp-ship写, fwp-plan读     (MERGED/BLOCKED_CI)
milestone-*.md ← 上层写, fwp-plan读        (需求描述)
```

### 自动推进

- FAIL/WARN → 自动生成 milestone → Agent(fwp-plan)
- INFO → 记录 findings.json，连续3轮升级 WARNING
- 严禁 `AskUserQuestion`，所有决策由规则判定

## 安装

```bash
git clone https://github.com/Qanora/skills.git
cd skills
./install.sh
```

## 调用示例

```text
/fwp-setup                        # 初始化当前目录为 GitHub 项目
/fwp-plan 添加缓存层               # 需求→Issue→自动开发交付
/fwp-debug 启动时 KeyError         # Bug→复现→自动修复
/fwp-inspect                      # 13项全量巡检
/fw-audit                         # AI 安全治理审计
/fwp-resume                       # 继续中断的任务
```
