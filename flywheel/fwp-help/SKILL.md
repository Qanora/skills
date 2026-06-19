---
name: fwp-help
description: 飞轮帮助——列出所有可用 skill、用途和调用方式
---

# FWP-HELP（飞轮帮助 · 用户级）

显示飞轮体系中所有可用 skill。`/fwp-help` 直接回车。

## 输出

```text
飞轮体系 (Flywheel) — 8 个 skill

你主动调用 (5个):
  /fwp-setup                    初始化项目 (自动用当前目录名)
  /fwp-plan    <需求>            "我想做 X" → Issue → 自动开发交付
  /fwp-debug   <bug 描述>       "我发现 bug" → 复现 → 自动修复
  /fwp-inspect                  13项全量巡检 (运行时+代码审查)
  /fwp-resume                   继续中断的 milestone

飞轮审计 (1个):
  /fw-audit                     AI 安全治理审计 (门禁/约束/行为/传递/效率)

Agent 自动调用 (2个, 你不需要手动调):
  fwp-ship                      MR 生命周期 (由 fwp-plan 触发)
  fwp-build                     TDD 开发 (由 fwp-ship 触发)

帮助:
  /fwp-help                     显示此帮助

跨项目: 在任意 git 项目目录下直接使用, 自动检测项目上下文
安装:   git clone https://github.com/Qanora/skills && cd skills && ./install.sh
```
