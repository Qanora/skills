---
name: fwp-help
description: 飞轮帮助——列出所有可用 skill、用途和调用方式
---

# FWP-HELP（飞轮帮助 · 用户级）

显示飞轮体系中所有可用 skill。`/fwp-help` 直接回车。

全部 skill 无参数、无选项、无 flag。每个命令只有一个调用方式。

## 输出

```text
飞轮体系 (Flywheel) — 8 个 skill, 全部无参数

你主动调用 (6个):
  /fwp-setup                    初始化项目 (自动用当前目录名)
  /fwp-plan    <需求>           "我想做 X" → Issue → 自动交付
  /fwp-debug   <bug 描述>       "我发现 bug" → 复现 → 自动修复
  /fwp-inspect                  项目全量巡检 (自动按需Tier1+Tier2)
  /fwp-resume                   继续中断的 milestone (新session首选)
  /fwp-help                     显示此帮助

飞轮审计 (1个):
  /fw-audit                     AI 安全治理审计 (5维度全量)

Agent 自动调用 (2个, 不手动调):
  fwp-ship                      MR 生命周期 (由 fwp-plan 触发)
  fwp-build                     TDD 开发 (由 fwp-ship 触发)

跨项目: 在任意 git 项目目录下直接使用
安装:   git clone https://github.com/Qanora/skills && cd skills && ./install.sh
```
