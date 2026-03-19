# DIR `.github/codex/labels` 研究报告

- 研究对象：`/home/sansha/Github/codex/.github/codex/labels`
- 研究日期：2026-03-19
- 对象类型：目录（DIR）

## 场景与职责

`.github/codex/labels` 是一组按 GitHub Label 命名的 Prompt 模板目录。目录中的每个 `*.md` 文件，对应一个自动化任务语义：

- `codex-attempt.md`：尝试修复 issue，并在需要时建分支/提交/开 PR（`.github/codex/labels/codex-attempt.md:1-9`）。
- `codex-triage.md`：判断 issue 是否有效，输出简洁结论（`.github/codex/labels/codex-triage.md:1-7`）。
- `codex-review.md`：通用 PR review 模板（`.github/codex/labels/codex-review.md:1-7`）。
- `codex-rust-review.md`：Rust 专项 review 模板（crate 职责、测试断言、PR 说明等）（`.github/codex/labels/codex-rust-review.md:1-139`）。

该目录本身不包含可执行逻辑，职责是“被外部执行器读取并注入事件上下文”。

当前仓库现状：

- 全仓未发现对 `.github/codex/labels/*` 的直接引用（`rg` 检索结果为空）。
- 现行 issue 自动化 workflow (`issue-labeler.yml`, `issue-deduplicator.yml`) 使用 `openai/codex-action@main` + 内联 `prompt`，不读取本目录（`.github/workflows/issue-labeler.yml:23-87`，`.github/workflows/issue-deduplicator.yml:60-99,196-233`）。

因此，本目录在主线中属于“保留的提示词资产”，而非当前在线执行链路。

## 功能点目的

### 1) 目录级目的

1. 将“任务类型 -> Prompt”做文件化映射，便于按 label 维护策略。  
2. 用占位符（如 `{CODEX_ACTION_ISSUE_TITLE}`）让模板复用不同事件上下文。  
3. 让 review/triage/attempt 等行为语义可审计、可版本化。

### 2) 文件级目的

1. `codex-attempt.md`
- 目标是推动“问题到修复 PR”的闭环，明确包含建分支、提交、开 PR 的行动要求。

2. `codex-triage.md`
- 目标是低成本有效性筛查，输出简洁且礼貌的结论评论。

3. `codex-review.md`
- 目标是统一普通 PR review 输出结构（摘要 + review）。

4. `codex-rust-review.md`
- 目标是把 Rust 团队偏好的审查准则固化为可复用清单，减少风格漂移。

### 3) 演进目的（历史）

- 初次导入（`baa92f37e`）：把 label 驱动的 Codex Action 机制纳入仓库。  
- 新增 Rust 专项 label（`35010812c`）：强化 Rust PR 自动审查。  
- 补充 Rust review 细则（`7b3ab968a`）：增强可执行性。  
- 移除旧 action/workflow（`aa5fc5855`）：停止仓内那套 label 执行器，目录保留但调用链删除。

## 具体技术实现（关键流程/数据结构/协议/命令）

> 说明：本节分“历史完整实现链路（已删除）”与“当前仓库实现状态（仍在运行）”。

### A. 历史完整实现链路（证据来自 `aa5fc5855^`）

1. 事件触发与 label 过滤
- 旧 workflow `codex.yml` 只在特定 label 时运行：
  - issues: `codex-attempt` / `codex-triage`
  - pull_request: `codex-review` / `codex-rust-review`
- 见 `git show aa5fc5855^:.github/workflows/codex.yml` 第 19-24 行。

2. 模板发现与配置装配
- `load-config.ts` 扫描 `.github/codex/labels/*.md`，文件名去后缀作为 label key。  
- 缺失目录时回退到默认内建配置。  
- 见 `git show aa5fc5855^:.github/actions/codex/src/load-config.ts` 第 18-48 行。

3. 标签状态机
- `process-label.ts` 执行 `label -> label-in-progress -> label-completed`。  
- 若已存在 `-in-progress/-completed` 则跳过并清理触发标签，避免重复执行。  
- 见同文件第 37-86 行。

4. Prompt 渲染协议
- 正则匹配变量：`{CODEX_ACTION_[A-Z0-9_]+}`。  
- 变量值来自 `GITHUB_EVENT_PATH` 解析后的 JSON，含 issue title/body、PR refs 等。  
- 对 PR 还可拉取 diff（`git diff base..head`）。  
- 见 `prompt-template.ts` 第 53-102、217-247 行。

5. Review 额外约束注入
- 对 label 名包含 `review` 的任务，执行器会在模板前注入“PR Diff Scope”指导（要求基于 merge-base 范围审查）。  
- 见 `process-label.ts` 第 95-123 行。

6. Codex 执行命令
- 调用：`/usr/local/bin/codex exec ... --output-last-message <tmpfile> <prompt>`。  
- 若传 `INPUT_CODEX_HOME`，会映射到 `CODEX_HOME`。  
- 见 `run-codex.ts` 第 23-36、38-58 行。

7. Issue 修复分支与 PR（attempt/fix）
- label 名含 `attempt|fix` 时，尝试 `git add -A -> commit -> push -> create PR`。  
- 见 `process-label.ts` 第 130-155 行与 `git-helpers.ts`。

### B. 当前仓库实现状态（仍在运行）

1. 当前 `openai/codex-action` 使用模式
- `issue-labeler.yml`、`issue-deduplicator.yml` 均采用 workflow 内联 `prompt` + `output-schema`。  
- 不再依赖 `.github/codex/labels` 目录扫描。

2. 当前输入/输出协议
- 输入：`github.event.issue.*` 字段或本地生成 JSON 文件（`gh issue list/view + jq`）。
- 输出：受 `output-schema` 约束为结构化 JSON，再由 shell 步骤解析并执行打标签/评论。

### C. 数据结构与命名约定

1. 模板文件名即行为 key（历史机制）
- `codex-review.md` -> label `codex-review`。

2. 占位符命名（历史机制）
- 统一前缀 `CODEX_ACTION_`，例如：
  - `CODEX_ACTION_ISSUE_TITLE`
  - `CODEX_ACTION_ISSUE_BODY`
  - `CODEX_ACTION_GITHUB_EVENT_PATH`

3. 状态标签命名（历史机制）
- `<label>-in-progress` / `<label>-completed`。

## 关键代码路径与文件引用

### 1) 研究目标目录（当前）

- `.github/codex/labels/codex-attempt.md`
- `.github/codex/labels/codex-triage.md`
- `.github/codex/labels/codex-review.md`
- `.github/codex/labels/codex-rust-review.md`

### 2) 当前调用方与邻接链路（仓内）

- `.github/workflows/issue-labeler.yml:23-87`（内联 prompt 调用 `openai/codex-action@main`）
- `.github/workflows/issue-deduplicator.yml:60-99`
- `.github/workflows/issue-deduplicator.yml:196-233`

### 3) 历史调用方/被调用方（已删除，但定义目录语义）

- `git show aa5fc5855^:.github/workflows/codex.yml`（label 触发条件与 `codex_home` 输入）
- `git show aa5fc5855^:.github/actions/codex/src/load-config.ts`（扫描 `.github/codex/labels`）
- `git show aa5fc5855^:.github/actions/codex/src/process-label.ts`（状态标签、渲染、评论、尝试建 PR）
- `git show aa5fc5855^:.github/actions/codex/src/prompt-template.ts`（占位符协议）
- `git show aa5fc5855^:.github/actions/codex/src/run-codex.ts`（`codex exec` 命令）
- `git show aa5fc5855^:.github/actions/codex/README.md`（label 文件约定文档）

### 4) 配置、脚本、文档、测试上下文

- 配置：`.github/codex/home/config.toml`（历史执行链通过 `CODEX_HOME` 消费）。
- 脚本：`.ops/generate_daily_research_todo.sh`（研究任务清单生成）。
- 文档：`Docs/researches/blueprint_checklist.md`（研究覆盖清单）。
- 测试：当前仓库无针对 `.github/codex/labels` 的自动化测试；历史 action 的 `package.json` 虽有 `bun test` 脚本，但仓内未看到对应测试文件。

## 依赖与外部交互

### 1) 平台与服务依赖

1. GitHub Actions 事件与权限模型（issues/pull_request、labels、comments）。  
2. `openai/codex-action`（当前 workflow 使用外部 action）。  
3. OpenAI API key（`CODEX_OPENAI_API_KEY`）用于模型调用。

### 2) 运行时交互（历史链路）

1. GitHub API（Octokit）
- 读取当前 labels、增删标签、发评论、创建 PR。

2. Git 命令
- `git fetch`（确保 PR base/head 可用）
- `git diff`（生成 PR 差异）
- `git add/commit/push`（attempt/fix 时发布修复分支）

3. 事件载荷文件
- `GITHUB_EVENT_PATH` 被当作模板数据源。

### 3) 与当前工作流的关系

- 当前 issue 自动化使用内联 prompt，不消费本目录；因此本目录对当前线上行为的直接影响为 0。  
- 但目录仍是“可复用 prompt 资产”，未来可被重新接入文件化 prompt 流程。

## 风险、边界与改进建议

### 风险

1. 闲置资产漂移风险  
- 文件继续演进但未被调用，团队容易误以为“改了就会生效”。

2. 协议失配风险  
- 模板占位符依赖特定执行器语义；若未来接入的 action 不支持同名变量，会出现静默失效。

3. 缺少回归保护  
- 无静态校验/测试验证模板必需变量、文件命名与 label 约定。

4. 文档断层  
- 当前仓内运行链路已转为内联 prompt，但目录仍保留，易造成维护认知分裂。

### 边界

1. 本目录仅包含静态 Markdown Prompt，不承担执行逻辑。  
2. 是否生效取决于外部 workflow/action 是否显式读取该目录。  
3. 当前主干自动化逻辑以 workflow 内联 prompt 为主。

### 改进建议

1. 做“单轨化”选择
- 方案 A：继续内联 prompt，则将本目录标记为 deprecated 或删除。  
- 方案 B：恢复文件化 prompt，则在 workflow 显式声明并加校验，避免隐式约定。

2. 增加模板静态检查
- 校验 `.github/codex/labels/*.md` 文件名与允许 label 集一致；
- 校验关键占位符集合（至少 issue/PR 模板必须字段）和空文件。

3. 增加生效可观测性
- 在 workflow 日志输出“本次 prompt 来源（inline/file）+ 模板路径 + 渲染变量摘要”。

4. 补一份目录契约文档
- 明确“谁读取、何时读取、占位符列表、失败行为”，降低跨团队误解成本。
