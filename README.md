# Skills

通用 Claude Code Agent Skill 集合。`fw-*` 飞轮审计 + `fwp-*` 项目开发。

## 飞轮体系

8 个用户级 skill，从项目初始化到持续交付的全流程自动化。

| 类别 | Skill | 用途 |
|------|-------|------|
| 项目 | fwp-setup | 初始化新项目（自动用当前目录名） |
| 项目 | fwp-plan | "我想做 X" → 拆解 → Issue → 派发 |
| 项目 | fwp-debug | "我发现 bug" → 复现 → 证据 → 派发 |
| 项目 | fwp-inspect | 全量巡检：运行时 8 项 + 代码审查 5 项 |
| 项目 | fwp-resume | 继续中断的 milestone |
| 项目 | fwp-help | 列出所有 skill 和调用方式 |
| 飞轮 | fw-audit | AI 安全治理审计：门禁/约束/行为/传递/效率 |
| — | fwp-build | TDD 开发（Agent 自动调用） |
| — | fwp-ship | MR 交付（Agent 自动调用） |

## 安装

```bash
git clone https://github.com/Qanora/skills.git
cd skills
./install.sh
```

软链安装，修改任一端自动同步。

## 目录

- `install.sh` — 一键软链安装/卸载/清理旧版本
- `flywheel/README.md` — 架构总览
- `flywheel/ARCHITECTURE.md` — 8 skill 关系/输入输出/调用全景图
- `flywheel/FILE_PROTOCOL.md` — `/tmp/fw-flywheel/` 跨层文件传递协议
- `flywheel/fw-audit/SKILL.md` — AI 安全治理审计
- `flywheel/fwp-*/SKILL.md` — 项目 skill 定义
