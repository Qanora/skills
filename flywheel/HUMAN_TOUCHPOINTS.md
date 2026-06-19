# 飞轮流程人工参与点分析

逐一审查 6 个 skill 的完整生命周期，按阻塞程度和可优化程度分类所有人工参与点。

---

## 总览

| 类别 | 数量 | 可消除 | 可减少 | 必须保留 |
|------|------|--------|--------|---------|
| 🔴 硬阻塞（权限/认证） | 5 | 0 | 0 | 5 |
| 🟡 软阻塞（默认不足） | 4 | 2 | 2 | 0 |
| 🟠 错误恢复（上限转人工） | 7 | 0 | 4 | 3 |
| 🔵 配置性（首次安装） | 5 | 1 | 3 | 1 |
| 🟢 触发式（需人启动） | 6 | 2 | 3 | 1 |
| **合计** | **27** | **5** | **12** | **10** |

---

## 🔴 硬阻塞 — 必须人工，无法自动化

这些点涉及平台权限、认证凭证、或需要人类做出不可逆决策。

### H1. GitHub 认证（lp-init 前置条件）

- **场景**: `gh auth login` 必须在运行 lp-init 前完成
- **为何无法自动化**: OAuth token / PAT 必须由人在浏览器中授权
- **影响范围**: lp-init 阶段 1、lp-ms、lp-mr 所有 gh 操作
- **改善空间**: 无。可在 lp-init 开头检测 `gh auth status`，未登录时给出清晰指引

### H2. 仓库创建权限（lp-init 阶段 1）

- **场景**: `gh repo create` 需要用户在 GitHub org 中有 create repo 权限
- **为何无法自动化**: GitHub org permissions 由管理员在 GitHub UI 中设置
- **影响范围**: 首次 lp-init
- **改善空间**: 无。权限不足时给出清晰错误信息 + org admin 联系方式

### H3. 分支保护配置权限（lp-init 阶段 2）

- **场景**: `gh api .../branches/.../protection` 需要 repo admin 权限
- **为何无法自动化**: GitHub 的 admin 权限层级设计，API 无法绕过
- **影响范围**: 首次 lp-init 阶段 2
- **改善空间**: 已有降级机制——API 失败时打印手动配置清单。可增加：检测当前用户权限级别，预判是否可自动配置

### H4. GitHub Secrets 配置（lp-init 阶段 3 隐式依赖）

- **场景**: auto-merge workflow 需要 `GITHUB_TOKEN`（Actions 默认提供），CodeRabbit 需要独立 token
- **为何无法自动化**: Secrets 写入仅限 repo admin，且敏感值不能由 AI 生成
- **影响范围**: CI auto-merge 是否生效
- **改善空间**: lp-init 终检清单中加入 "☐ 检查 Settings → Secrets 是否已配置"

### H5. 非 master 分支 CI 触发（CI 配置局限性）

- **场景**: test.yml 的 `push` 和 `pull_request` 都只监听 `{DEFAULT_BRANCH}`，推其他分支不触发 CI
- **为何无法自动化**: 这是 CI 配置的设计选择——只保护默认分支
- **影响范围**: 所有 feature 分支的 MR（通过 PR 触发，不通过 push 触发）
- **改善空间**: 当前设计已正确（PR 触发 CI），无需改动

---

## 🟡 软阻塞 — 可自动但当前需要人工

这些点有明确的默认答案或可从上下文推断，但当前实现仍询问用户或停止。

### S1. lp-up 附录 P 为空（lp-up 首次运行）

- **场景**: 新项目的 lp-up 附录 P 未填写项目特定分析维度（CLI 命令、DB 表、判定阈值），lp-up 无法执行 --run 模式
- **当前行为**: 附录 P 留空模板，需人工填写
- **改善方案**: lp-init 阶段 8 生成 pyproject.toml 后，**自动推断**附录 P 内容：
  - 从 pyproject.toml `[project.scripts]` 提取 CLI 名 → 生成 quick/full 命令骨架
  - 从 `[project.optional-dependencies]` 提取 dev 依赖 → 生成 lint/test 命令
  - 从 SQLAlchemy/models 扫描表名 → 生成 SQL 查询模板
  - **无法推断的部分**（判定阈值）保留人工填写，但给出合理默认值
- **可消除程度**: 80% 可自动生成，阈值需人工确认

### S2. lp-up INFO 发现无限积压

- **场景**: INFO 级发现记录到 findings.json 但不自动派发，只等下一轮升级。若永远不会升级则永远不处理
- **当前行为**: 静默积累
- **改善方案**: 增加 **INFO 老化机制**：
  - INFO 连续出现 3 轮未升级 → 自动升级为 WARNING
  - findings.json 超过 20 条 INFO → 下一轮必选一条升级
  - 每轮报告中增加 "INFO 积压: N 条，最老 X 天"
- **可消除程度**: 100% 自动处理，无需人工

### S3. lp-dp 飞轮健康度评分无动作

- **场景**: lp-dp 审计报告给出的 skill_scores.json 只记录趋势，评分 C+ 以下无自动改进动作
- **当前行为**: 记录 + 报告，靠人类阅读后手动改进
- **改善方案**: 
  - 评分 C+ 且连续 2 轮 → 自动生成 DESIGN 类 milestone
  - 同一 DEVIATION 连续 3 轮 → 自动升级为 CRITICAL
- **可消除程度**: 100% 自动触发改进

### S4. "是否继续" / "确认执行" 类询问

- **场景**: 两个源项目中 lp-ms 和 lp-mr 历史上存在向用户确认的交互点（已在 SKILL.md 中声明"不询问用户确认"，但实际 Agent 执行时可能仍触发 AskUserQuestion）
- **当前行为**: SKILL.md 写明了自动推进，但依赖 Agent 遵守
- **改善方案**: 
  - 在 SKILL.md 中增加更强的约束语言："严禁调用 AskUserQuestion"
  - 在 CLAUDE.md 的 guardrails 中声明该项目的飞轮 skill 禁止用户确认
- **可消除程度**: 100%（通过约束语言 + guardrails）

---

## 🟠 错误恢复 — 自动已达上限后转人工

这些是飞轮设计中有意设置的"重试上限"，超过上限后需要人类判断。

### E1. fix_round ≥ 3 → BLOCKED_CI（lp-mr 步骤 4/5）

- **场景**: 同一 issue 的 CI 修复连续失败 3 次
- **当前行为**: 写入 BLOCKED_CI 状态，exit 1，需人工介入
- **合理性**: ✅ 合理。3 次自动修复失败说明问题不是简单的 typo/config，需要人理解上下文
- **改善空间**: 
  - 修复失败时自动在 issue 下添加 comment，汇总 3 轮的 CI log 差异
  - 标记 issue 的 label 为 `needs-info` → `ready-for-human`
  - 减少人工排查时间：自动 diff 3 轮 fix 的改动，高亮未能解决的 CI error

### E2. SIMPLIFY_UNFIXABLE（lp-dev → lp-mr 错误处理）

- **场景**: simplify skill 发现了代码问题但无法自动修复
- **当前行为**: lp-dev 输出 `FAIL_DONE=SIMPLIFY_UNFIXABLE`，lp-mr 标记人工介入
- **合理性**: ✅ 合理。simplify 无法修复的问题通常是设计层面的
- **改善空间**:
  - lp-dev 输出 SIMPLIFY_UNFIXABLE 时附带具体文件路径和行号
  - lp-mr 收到后自动在 issue 下创建 comment 贴出问题代码片段

### E3. CONFLICT_UNRESOLVABLE（lp-dev --fix 步骤 1）

- **场景**: feature 分支 merge origin/master 时出现无法自动解决的冲突
- **当前行为**: lp-dev 尝试自动解决（识别 <<<===>>> 标记），失败则输出 FAIL_DONE
- **合理性**: ⚠️ 偏保守。当前实现只做逐文件 Read + Edit，可能放弃太早
- **改善空间**:
  - 增加 `git merge --abort` + `git rebase origin/master` 作为 fallback 策略
  - 冲突超过 5 个文件或 50 行时才转人工
  - 简单冲突（同一函数签名变更/import 语句）应能自动处理

### E4. watch-pr.sh timeout（lp-mr 步骤 3/4）

- **场景**: CI 轮询超时（最大 60 轮 × 30s = 30 分钟）
- **当前行为**: exit 2，若 CI green 则自动合入，否则人工介入
- **合理性**: ⚠️ timeout 上限 30 分钟可能不够（大型 monorepo CI 可能跑 1h+）
- **改善空间**:
  - 动态 timeout 已按 diff 大小调整，但上限 60 轮可提升到 120 轮（60 分钟）
  - timeout 时自动获取 CI job URL，贴到 issue comment
  - 增加 `--timeout-override` 参数允许人类指定更长等待

### E5. API_ERROR（lp-mr 状态机 / lp-init 各阶段）

- **场景**: gh api 调用返回 5xx / rate limit / 网络错误
- **当前行为**: 标记 API_ERROR，转人工
- **合理性**: ⚠️ 过于严格。大多数 API 错误是瞬时的
- **改善空间**:
  - 增加自动重试（指数退避，最多 3 次）
  - 只有 3 次重试后仍失败才转人工
  - rate limit 时自动等待 reset window

### E6. lp-ms 依赖环检测

- **场景**: issue 拆解后发现循环依赖
- **当前行为**: 立即停止，要求人重新拆解
- **合理性**: ✅ 合理。环检测意味着需求拆解逻辑有错误，需人重新思考
- **改善空间**: 自动建议"断环点"——指出删除哪条依赖边可以打破环

### E7. 数据不足跳过分析（lp-up 阶段 C）

- **场景**: monitoring_samples 不足 7 天 / trace_samples 为空
- **当前行为**: 标注跳过，不做强行推断
- **合理性**: ✅ 合理。数据不足时不应瞎猜
- **改善空间**: 自动在 findings.json 中创建 INFO 级发现："需要积累 N 天数据"，到期自动提醒

---

## 🔵 配置性 — 首次使用需人工

这些是一次性配置工作，完成后飞轮可自动运行。

### C1. 飞轮 Skills 安装（新项目接入）

- **场景**: 将通用 SKILL.md 复制到项目的 `.claude/skills/` 并替换占位符
- **当前方案**: lp-init 阶段 9 自动执行复制 + sed 替换
- **改善状态**: ✅ lp-init 已自动化。唯一需人工的是确认路径正确

### C2. lp-up 附录 P：项目特定分析维度

- **场景**: 每个项目的 CLI 命令、DB 表结构、日志路径各不相同
- **当前方案**: 附录 P 为模板，需人工填写
- **改善空间**: 见 S1 — 80% 可自动推断

### C3. lp-dev 附录：项目特定 lint/test 命令

- **场景**: 不同项目用不同工具（ruff/mypy/eslint/jest/...）
- **当前方案**: 附录为模板，给了 Python/Node.js 示例
- **改善空间**: lp-init 阶段 8 扫描 pyproject.toml / package.json 后自动填充

### C4. pyproject.toml 业务依赖

- **场景**: lp-init 生成的 pyproject.toml 只有 dev 依赖（pytest + ruff），业务依赖需手动添加
- **当前方案**: dependencies 数组为空
- **改善空间**: 无法自动推断业务依赖，但可提供常用组合的交互式选择（fastapi / sqlalchemy / pandas / ...）

### C5. CLAUDE.md 项目描述

- **场景**: CLAUDE.md 的第一行 `<项目一句话描述>` 需人工写
- **当前方案**: 留空模板
- **改善空间**: 从 repo description / README 首段自动填充，但最终还是需要人确认

---

## 🟢 触发式 — 需人启动或调度

### T1. lp-up 的执行触发

- **场景**: lp-up 是被动工具，需要人运行 `/lp-up --run quick` 或 `/lp-up --run full`
- **当前行为**: 完全手动
- **改善空间**: 
  - 集成 CronCreate 自动调度（每日 quick、每周 full）
  - lp-init 阶段 9 可自动创建建议的 cron schedule 并询问用户是否启用

### T2. lp-dp 的执行触发

- **场景**: 同上，需要人运行 `/lp-dp` 或 `/lp-dp --audit`
- **改善空间**: 可绑定到 lp-mr 流程结束——每次 MR 合入后自动触发一次轻量 lp-dp 检查

### T3. lp-ms 从 lp-up/lp-dp 的派发需要 Agent 工具

- **场景**: lp-up 阶段 F 的 `Agent(subagent_type="lp-ms", ...)` 调用依赖 Agent 工具可用
- **当前行为**: subagent 模式
- **改善空间**: 若 Agent 工具因权限/配额不可用，应 fallback 到直接输出 milestone 描述让人手动 `/lp-ms`

### T4. --resume 需要人判断何时恢复

- **场景**: 飞轮中断后（session 断开 / API 错误），--resume 由人手动触发
- **当前行为**: 完全手动
- **改善空间**: 
  - 在 session 启动时自动检测 `.claude/state/` 中未完成的 issue/milestone
  - 在 CLAUDE.md 或 startup hook 中加入恢复检查

### T5. Milestone 关闭（lp-ms 步骤 7）

- **场景**: 所有 issue 合入后关闭 milestone
- **当前行为**: lp-ms 自动执行（步骤 7）
- **改善状态**: ✅ 已自动化

### T6. lp-mr 的 /lp-mr 调用（lp-ms 步骤 5）

- **场景**: lp-ms 步骤 5 逐个调用 `/lp-mr <issue-number>`
- **当前行为**: skill 调用（同会话），串行执行
- **改善空间**: 同一批次的独立 issue 可并行派发（多个 Agent 同时 lp-mr），但当前串行设计是出于安全考虑

---

## 总结矩阵

```
                    可消除  可减少  必须保留
─────────────────────────────────────────────
🔴 硬阻塞(5)           0       0       5
🟡 软阻塞(4)           2       2       0
🟠 错误恢复(7)         0       4       3
🔵 配置性(5)           1       3       1
🟢 触发式(6)           2       3       1
─────────────────────────────────────────────
合计(27)              5      12      10
```

**可立即消除的 5 项**（✅ 已全部应用）：
1. S2 — INFO 积压自动老化升级 ✅ **已实现**：lp-up 阶段 F + findings.json consecutive_rounds 计数器
2. S3 — 飞轮低分自动生成优化 milestone ✅ **已实现**：lp-dp 3.1 健康度评分规则 + skill_scores.json
3. S4 — 强化"禁止询问用户"约束 ✅ **已实现**：全部 6 个 skill 的约束章节加入严禁 AskUserQuestion
4. C1 — 已在 lp-init 阶段 9 自动化 ✅ **已实现**：复制 + sed 替换占位符
5. T5 — 已自动化 ✅ **已实现**：lp-ms 步骤 7 自动关闭 milestone

**建议优先改进的 12 项**（按影响面排序）：
1. E5 — API 调用增加自动重试（减少 90% 的 API_ERROR 转人工）
2. E4 — watch-pr timeout 提升上限到 60 分钟
3. T1 — lp-up 集成 CronCreate 自动调度
4. T4 — session 启动自动检测未完成任务
5. S1 — lp-up 附录 P 自动推断
6. E1 — CI 失败时自动汇总 3 轮 diff
7. E3 — merge conflict 增加 rebase fallback
8. C3 — lint/test 命令自动检测
9. E6 — 依赖环自动建议断环点
10. T2 — lp-dp 绑定到 MR 合入事件
11. E2 — SIMPLIFY_UNFIXABLE 附带代码片段
12. E7 — 数据不足自动创建监控提醒
