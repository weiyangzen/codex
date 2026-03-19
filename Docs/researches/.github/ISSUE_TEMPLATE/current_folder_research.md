# DIR `.github/ISSUE_TEMPLATE` 研究报告

- 研究对象：`/home/sansha/Github/codex/.github/ISSUE_TEMPLATE`（DIR）
- 研究日期：2026-03-19
- 研究范围：6 个 GitHub Issue Form 模板及其上下游（调用入口、自动化工作流、UI 深链、文档与校验链路）。

## 场景与职责

`.github/ISSUE_TEMPLATE` 是仓库的 Issue 入口分流层，核心职责是把“用户口头问题”转换为“可 triage 的结构化问题单”。

1. 场景分流
- 将问题分为 App、IDE Extension、CLI、Other Bug、Feature Request、Documentation Issue 六类，减少维护者初始分类成本（`.github/ISSUE_TEMPLATE/1-codex-app.yml:1-54`，`2-extension.yml:1-61`，`3-cli.yml:1-70`，`4-bug-report.yml:1-37`，`5-feature-request.yml:1-32`，`6-docs-issue.yml:1-27`）。

2. 首轮标签赋值
- 模板内 `labels` 在 issue 创建时即落库：例如 `app`、`extension`、`bug`、`enhancement`、`docs`（对应各模板 `labels` 字段）。

3. 收集结构化复现信息
- 通过 `id + validations.required` 强制采集版本、平台、复现步骤、预期行为等关键字段，改善后续自动标注和去重效果（`1-codex-app.yml:12-49`，`2-extension.yml:12-56`，`3-cli.yml:15-65`）。

4. 作为 CLI 内反馈出口
- TUI 与 `tui_app_server` 在反馈上传成功后会深链到 `3-cli.yml`，并预填 `steps` 字段，形成“产品内反馈 -> GitHub issue”闭环（`codex-rs/tui/src/bottom_pane/feedback_view.rs:32-33,395-411,772-775`；`codex-rs/tui_app_server/src/bottom_pane/feedback_view.rs:32-33,395-411,772-775`）。

## 功能点目的

### 1) 六个模板的功能定位

1. `1-codex-app.yml`
- 面向桌面 App 问题，默认打 `app`，强制采集版本/订阅/问题描述/复现步骤（`.github/ISSUE_TEMPLATE/1-codex-app.yml:1-44`）。

2. `2-extension.yml`
- 面向 IDE 扩展问题，默认打 `extension`，新增 IDE 类型字段（VS Code/Cursor/Windsurf 等）（`.github/ISSUE_TEMPLATE/2-extension.yml:1-50`）。

3. `3-cli.yml`
- 面向 CLI 问题，默认打 `bug + needs triage`，额外采集 `model` 与 `terminal` 信息，并提醒先升级到 npm 最新版本（`.github/ISSUE_TEMPLATE/3-cli.yml:1-70`）。

4. `4-bug-report.yml`
- 兜底“其他产品面”缺陷入口（Web/集成等），减少误投到 feature/docs 渠道（`.github/ISSUE_TEMPLATE/4-bug-report.yml:1-37`）。

5. `5-feature-request.yml`
- 面向新能力提案，默认 `enhancement`，强制说明使用的 Codex 变体（App/Extension/CLI/Web）（`.github/ISSUE_TEMPLATE/5-feature-request.yml:1-27`）。

6. `6-docs-issue.yml`
- 面向文档问题，默认 `docs`，通过多选下拉快速分类“缺失/错误/混乱/示例不可用”等（`.github/ISSUE_TEMPLATE/6-docs-issue.yml:1-27`）。

### 2) 与仓库治理目标的对应

- `docs/contributing.md` 明确要求用户通过 issue 提案或报 bug，这些模板就是该政策的执行入口（`docs/contributing.md:7-10,39-41,56`）。
- PR 模板要求关联 bug/enhancement issue，反向依赖这套 issue 分类质量（`.github/pull_request_template.md:1-8`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程

1. 用户入口
- 手动：GitHub 新建 issue 页面选择模板。
- 程序化：TUI 在反馈场景直达 `https://github.com/openai/codex/issues/new?template=3-cli.yml`，并用 `&steps=Uploaded%20thread:%20{thread_id}` 预填复现步骤（`codex-rs/tui/src/bottom_pane/feedback_view.rs:32-33,410`）。

2. Issue 创建
- GitHub Issue Forms 读取 YAML，渲染字段并执行 `required` 校验。
- 提交后 issue body 变成结构化 Markdown，模板内 `labels` 自动附加。

3. 自动化消费
- `issue-labeler` 在 `issues.opened` 或人工加 `codex-label` 时触发，读取 issue title/body，经 `openai/codex-action` 产出 `{labels: string[]}`，再 `gh issue edit --add-label` 应用（`.github/workflows/issue-labeler.yml:3-8,13,22-27,74-87,103-127`）。
- `issue-deduplicator` 在 `issues.opened` 或人工加 `codex-deduplicate` 时触发，`gh issue list/view` 拉取上下文，模型输出 `{issues: string[], reason: string}`，最终自动评论候选重复单（`.github/workflows/issue-deduplicator.yml:3-8,13,35-55,85-99,335-392`）。

### 2) 数据结构/字段约定

1. 模板对象结构
- 顶层：`name`、`description`、`labels`、`body`。
- `body` 元素：`type`（`markdown/input/textarea/dropdown`）+ `attributes` + 可选 `id` + `validations.required`。

2. 字段 ID 的协议意义
- 例如 `version`、`plan`、`platform`、`steps`、`actual`、`expected`。
- `3-cli.yml` 的 `steps` 被 TUI 用 URL 参数预填，说明该 `id` 已成为跨模块约定（`.github/ISSUE_TEMPLATE/3-cli.yml:55-58` + `codex-rs/tui/src/bottom_pane/feedback_view.rs:410`）。

3. 标签协议
- 模板预置标签：`app`/`extension`/`bug`/`needs triage`/`enhancement`/`docs`。
- 自动化再补标签：`CLI`、`mcp`、`sandbox`、`documentation` 等（`.github/workflows/issue-labeler.yml:33-61`）。

### 3) 关键命令与脚本

issue 模板本身是声明式 YAML，不直接执行命令；命令面来自其下游工作流：

- `gh issue view/list/edit`：读取 issue 内容、打标签、移除触发标签（`.github/workflows/issue-labeler.yml:122-133`，`.github/workflows/issue-deduplicator.yml:35-55,171-191,401-402`）。
- `jq`：校验/归一化模型输出 JSON（`.github/workflows/issue-labeler.yml:111-117`，`.github/workflows/issue-deduplicator.yml:114-127,248-260`）。

## 关键代码路径与文件引用

### A. 目录内核心文件

- `.github/ISSUE_TEMPLATE/1-codex-app.yml`
- `.github/ISSUE_TEMPLATE/2-extension.yml`
- `.github/ISSUE_TEMPLATE/3-cli.yml`
- `.github/ISSUE_TEMPLATE/4-bug-report.yml`
- `.github/ISSUE_TEMPLATE/5-feature-request.yml`
- `.github/ISSUE_TEMPLATE/6-docs-issue.yml`

### B. 调用方（Who uses ISSUE_TEMPLATE）

1. 产品内深链调用
- `codex-rs/tui/src/bottom_pane/feedback_view.rs:32-33,395-411,772-775`
- `codex-rs/tui_app_server/src/bottom_pane/feedback_view.rs:32-33,395-411,772-775`

2. 社区流程与文档调用
- `docs/contributing.md:7-10,39-41,56`
- `.github/pull_request_template.md:8`

### C. 被调用方（What consumes template output）

- `.github/workflows/issue-labeler.yml:3-133`
- `.github/workflows/issue-deduplicator.yml:1-402`

### D. 配置与校验覆盖

1. 目录配置
- 当前无 `.github/ISSUE_TEMPLATE/config.yml`（目录仅 6 个模板文件）。

2. 格式化覆盖现状
- 根 `package.json` 的 `format` 只覆盖 `.github/workflows/*.yml`，未包含 `.github/ISSUE_TEMPLATE/*.yml`（`package.json:6-7`）。

### E. 相关测试

1. 链接构造测试（高相关）
- `codex-rs/tui/src/bottom_pane/feedback_view.rs:733-776`
- `codex-rs/tui_app_server/src/bottom_pane/feedback_view.rs:733-776`

2. 覆盖内容
- 验证外部用户链接确实指向 `template=3-cli.yml`，并预填 `steps=Uploaded thread: ...`。

## 依赖与外部交互

1. GitHub Issue Forms 运行时
- 模板由 GitHub 平台解释与渲染，不在仓库内执行；仓库侧仅维护 YAML 声明。

2. GitHub Actions 自动化
- `issue-labeler` / `issue-deduplicator` 读取 issue 标题与正文并调用 `openai/codex-action`；Issue 模板质量直接影响模型判别与去重准确性（`.github/workflows/issue-labeler.yml:28-69`，`.github/workflows/issue-deduplicator.yml:69-84,203-217`）。

3. CLI/TUI 用户链路
- 应用内反馈上传后将用户导向 `3-cli.yml`，把 thread id 带入 issue 草稿，缩短 support 回溯路径（`codex-rs/tui/src/bottom_pane/feedback_view.rs:117-149,395-413`）。

4. 标签生态交互
- 模板静态标签 + 工作流动态标签共同决定 triage 路由；若标签名策略不统一，会影响看板和自动规则可预测性。

## 风险、边界与改进建议

### 风险

1. YAML 重复键风险
- `3-cli.yml` 的 `terminal` 字段存在重复 `description` 键，后者可能覆盖前者，导致意图信息丢失（`.github/ISSUE_TEMPLATE/3-cli.yml:44-46`）。

2. 缺少模板级自动校验
- 现有 `pnpm run format` 不检查 `.github/ISSUE_TEMPLATE/*.yml`，错误更依赖人工审查或线上创建 issue 时暴露（`package.json:6-7`）。

3. 标签语义可能分叉
- 文档模板默认标签为 `docs`，而 labeler 的主类型标签为 `documentation`。若仓库治理规则只识别其一，可能造成统计/自动化偏差（`.github/ISSUE_TEMPLATE/6-docs-issue.yml:3`，`.github/workflows/issue-labeler.yml:33-37`）。

4. 深链目前只覆盖 CLI 模板
- App/Extension/Web 问题在产品内缺少对等深链入口，用户可能默认走 CLI 模板，增加人工重分类负担。

### 边界

1. 本目录只负责 issue 提交入口与字段采集，不负责 triage 决策逻辑。
2. 不包含可执行脚本与单测；其行为验证主要依赖：
- GitHub 平台渲染结果；
- 下游 workflow 成功率；
- TUI 对模板 URL 的单元测试。

### 改进建议

1. 修复 `3-cli.yml` 重复键
- 合并为单一 `description`，避免 YAML 解析器覆盖行为不一致。

2. 增加模板 CI 校验
- 在 `format`/CI 加入 `.github/ISSUE_TEMPLATE/*.yml` 的格式检查，并加一条轻量 schema/lint（至少检测重复键）。

3. 统一文档标签命名策略
- 在 `docs` 与 `documentation` 之间选定主标签，或在工作流里做映射，确保报表与自动化一致。

4. 引入 `config.yml`（若策略允许）
- 可显式配置联系入口、空白 issue 开关、默认提示，降低用户误选模板概率。

5. 为非 CLI 场景补齐深链
- 若 App/Extension/Web 内也有反馈入口，可按场景直达对应模板，提高 issue 首次分类准确度。
