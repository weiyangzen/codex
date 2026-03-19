# DIR `.github/codex` 研究报告

- 研究对象：`/home/sansha/Github/codex/.github/codex`
- 研究日期：2026-03-19
- 对象类型：目录（DIR）

## 场景与职责

`.github/codex` 是一个面向 GitHub 自动化 Agent 任务的“提示词与默认配置包”，职责可拆为两层：

1. 运行配置层（`home/config.toml`）
- 提供 Agent 运行时默认模型配置，当前固定为 `gpt-5.1`（`.github/codex/home/config.toml:1`）。
- 通过注释提示可以在同文件扩展 `[mcp_servers]`（`.github/codex/home/config.toml:3`）。

2. 任务模板层（`labels/*.md`）
- 以 label 语义划分 issue/PR 自动化任务模板：`codex-attempt`、`codex-triage`、`codex-review`、`codex-rust-review`。
- 模板内使用占位符注入事件上下文（如 issue 标题/正文、事件 JSON 路径），是“可参数化 prompt 模板”而非可执行脚本。

从仓库内可见证据看，这个目录更像“约定式输入目录”，用于 `openai/codex-action` 场景；但本仓库当前 workflow 已大量改为内联 prompt，导致 `.github/codex` 在本仓库内没有显式调用点（见后文“关键代码路径与文件引用”）。

## 功能点目的

### 1. `home/config.toml` 的目的

- 给自动化运行设定稳定默认模型，避免每个 workflow 单独维护模型参数。
- 给未来 MCP 能力扩展预留配置入口（`# Consider setting [mcp_servers] here!`）。

### 2. `labels/codex-attempt.md` 的目的

- 面向“尝试修复 issue”的执行任务。
- 明确要求：若需改代码则建分支、提交并开 PR（`.github/codex/labels/codex-attempt.md:3`）。
- 输入变量来自 issue 标题与正文（`.github/codex/labels/codex-attempt.md:7-9`）。

### 3. `labels/codex-triage.md` 的目的

- 面向“问题有效性排查（triage）”。
- 输出导向为简洁、尊重的结论评论（`.github/codex/labels/codex-triage.md:1-3`）。

### 4. `labels/codex-review.md` 的目的

- 面向通用 PR review。
- 要求输出结构：先 1-2 句摘要，再 1-2 句 review 与必要要点（`.github/codex/labels/codex-review.md:1-5`）。
- 明确输入来源为触发事件 JSON（包含 base/head refs）（`.github/codex/labels/codex-review.md:7`）。

### 5. `labels/codex-rust-review.md` 的目的

- 面向 Rust 专项 review，提供高约束审查清单（crate 职责、core 体积控制、测试断言风格、Cargo 依赖排序、PR 说明质量等）（`.github/codex/labels/codex-rust-review.md:9-135`）。
- 与 `codex-review.md` 相比，这是“领域化审查策略模板”。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1. 目录内实现形态

该目录无脚本、无二进制、无测试；技术实现完全基于两类静态文件：

1. TOML 配置对象
- `model = "gpt-5.1"`（`.github/codex/home/config.toml:1`）。

2. Markdown prompt 模板
- 使用 `{CODEX_ACTION_ISSUE_TITLE}`、`{CODEX_ACTION_ISSUE_BODY}`、`{CODEX_ACTION_GITHUB_EVENT_PATH}` 等占位符。
- 占位符由外部执行器在运行时替换；模板本身不包含替换逻辑。

### 2. 关键流程（基于仓库内证据 + 约定推断）

1. 事件触发（issue/PR/label）由 GitHub Actions 接管。
2. `openai/codex-action` 获得事件上下文与仓库内容。
3. 若 workflow 使用“约定模板目录”模式，则可按 label 名读取 `.github/codex/labels/<label>.md` 并注入变量；若 workflow使用内联 prompt 则跳过目录读取。
4. Agent 输出再由后续 step 解析并执行（打标签、评论、或其他动作）。

说明：步骤 3 在本仓库中缺少直接调用代码，属于基于目录结构和占位符命名的推断；可在未来通过引入显式 workflow 参数来消除不确定性。

### 3. 与当前 workflow 的对照实现

当前仓库里 `openai/codex-action` 的用法均为 **内联 prompt + JSON schema 输出**，非 `.github/codex` 模板模式：

- `.github/workflows/issue-labeler.yml:22-87`：直接在 `with.prompt` 内写完整标签分类策略。
- `.github/workflows/issue-deduplicator.yml:62-99` 与 `196-233`：两轮（all/open）去重 prompt 均内联。

对应的命令/协议特征：

1. 输入协议
- 通过 GitHub 表达式把 issue 字段注入 prompt（如 `${{ github.event.issue.title }}`，`.github/workflows/issue-labeler.yml:63-72`）。
- 去重工作流先用 `gh issue list/view + jq` 组装本地 JSON 输入文件（`.github/workflows/issue-deduplicator.yml:24-55`，`160-191`）。

2. 输出协议
- 依赖 `output-schema` 强约束 Codex 输出 JSON 形状（`labels[]` 或 `issues[] + reason`）。
- Shell/JS 步骤用 `jq` 或 `JSON.parse` 做二次校验与容错（`.github/workflows/issue-labeler.yml:103-127`，`.github/workflows/issue-deduplicator.yml:101-143`，`345-392`）。

## 关键代码路径与文件引用

### 目录本体

- `.github/codex/home/config.toml:1-3`
- `.github/codex/labels/codex-attempt.md:1-9`
- `.github/codex/labels/codex-triage.md:1-7`
- `.github/codex/labels/codex-review.md:1-7`
- `.github/codex/labels/codex-rust-review.md:1-139`

### 主要调用方（同仓库）

1. 直接调用状态
- 全仓检索未发现 workflow/script 直接引用 `.github/codex/labels/*` 或 `.github/codex/home/config.toml` 路径。

2. 实际在线调用点（内联 Prompt）
- `openai/codex-action@main`：`.github/workflows/issue-labeler.yml:23`
- `openai/codex-action@main`：`.github/workflows/issue-deduplicator.yml:64`
- `openai/codex-action@main`：`.github/workflows/issue-deduplicator.yml:198`

3. 事件后处理链路
- 标签应用：`.github/workflows/issue-labeler.yml:103-133`
- 去重输出归一化与评论：`.github/workflows/issue-deduplicator.yml:101-143`、`235-277`、`279-402`

### 相关脚本/文档上下文

- `.ops/research_guard.sh:229-246`：当前研究任务模板与“使用 codex exec 非 REPL”要求来源。
- `.ops/generate_daily_research_todo.sh:15-42`：todo 由 checklist 派生。
- `Docs/researches/blueprint_checklist.md:25-27`：该目录及子目录被纳入研究基线对象。

## 依赖与外部交互

### 1. 外部依赖

1. GitHub Actions 运行环境
- 事件来源：issues opened/labeled。
- 权限对象：`contents:read`、`issues:write`（见相关 workflow）。

2. `openai/codex-action@main`
- 负责调用模型、传入 prompt、返回结构化输出。
- `.github/codex` 目录与其存在“命名约定耦合”（推断），但本仓库当前未显式启用该路径。

3. GitHub CLI / jq / github-script
- issue 去重流程依赖 `gh` 拉取 issue 数据并用 `jq` 规整；最终通过 `actions/github-script` 发评论。

### 2. 输入输出边界

1. 输入
- issue 标题、正文、仓库名、事件 payload。
- 去重时还包含最多 1000 条 issue 元数据快照（标题、截断正文、标签、状态、时间戳）。

2. 输出
- 结构化 JSON（labels 或 issues+reason）。
- 后续副作用：加标签、删触发标签、发评论。

### 3. 安全与合规面

- API 密钥来自 `secrets.CODEX_OPENAI_API_KEY`（仅主仓执行，fork 被 if 条件挡住）。
- 输出落地前有格式校验与容错，降低模型异常输出直接影响自动化操作的风险。

## 风险、边界与改进建议

### 风险

1. 目录“潜在闲置”风险
- `.github/codex` 在仓库内无显式调用点，容易与真实运行逻辑漂移，形成“看似生效但实际未生效”的维护错觉。

2. 模型版本老化风险
- `home/config.toml` 固定 `gpt-5.1`，若未来恢复调用该配置，可能与当前策略或预期能力不一致。

3. 占位符协议隐式化风险
- 模板中 `{CODEX_ACTION_*}` 完全依赖外部替换约定，缺少本仓自验证测试与契约文档。

4. Prompt 策略双轨风险
- 一部分策略在 `.github/codex/labels`，另一部分在 workflow 内联 prompt；双轨并存会增加审计与更新成本。

### 边界

1. 该目录不承担业务执行逻辑，仅提供提示词与默认配置。
2. 模板变量的解析和注入不在本目录实现。
3. 本目录无单元测试/集成测试覆盖，验证主要依赖 workflow 实际运行。

### 改进建议

1. 做一次“单轨化”决策
- 要么统一迁移到 workflow 内联 prompt（并删除 `.github/codex`），要么统一改为目录模板引用（并在 workflow 显式声明来源路径）。

2. 增加契约文档
- 在 `.github/` 下新增短文档说明 `{CODEX_ACTION_*}` 变量语义、必填项、示例替换结果。

3. 增加 CI 级静态校验
- 校验 `.github/codex/labels/*.md` 必含关键占位符，避免模板变更后运行时缺上下文。

4. 模型配置版本治理
- 若继续保留 `home/config.toml`，建议补充“何时生效、谁读取、升级策略”的注释或文档链接。

5. 补齐“调用可观测性”
- 在 workflow 中打印（或 artifact 化）最终使用的 prompt 来源（inline vs file），便于审计与回溯。
