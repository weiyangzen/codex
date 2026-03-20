# DIR `codex-rs/chatgpt/tests/suite` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/chatgpt/tests/suite`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 关联 crate：`codex-chatgpt`

## 场景与职责

`codex-rs/chatgpt/tests/suite` 是 `codex-chatgpt` 的集成测试套件目录，当前只承载一个端到端场景：验证 `codex apply` 的核心实现 `apply_diff_from_task` 能否把任务中的 unified diff 正确应用到本地 git 工作区，以及冲突时是否失败并产出冲突标记（`codex-rs/chatgpt/tests/suite/mod.rs:1-2`、`codex-rs/chatgpt/tests/suite/apply_command_e2e.rs:77-188`）。

它在测试分层中的职责是：

- 作为 `tests/all.rs` 的二级聚合模块，由单一 integration test binary 统一执行（`codex-rs/chatgpt/tests/all.rs:1-3`）。
- 覆盖“任务结构体 -> 取 PR diff -> git apply --3way -> 文件结果/错误语义”整条本地链路。
- 不覆盖真实网络请求与 CLI 参数解析；这些由上游模块负责（`codex-rs/chatgpt/src/get_task.rs:37-39`、`codex-rs/cli/src/main.rs:842-849`）。

## 功能点目的

### 1. 成功路径：任务 diff 可落地为目标文件

`test_apply_command_creates_fibonacci_file` 的目标是验证“有效 diff”会创建 `scripts/fibonacci.js` 且内容符合预期（函数、shebang、导出、行数 31）（`codex-rs/chatgpt/tests/suite/apply_command_e2e.rs:77-117`）。

该用例的价值是防止 `apply_diff_from_task` 在结构解析、diff 提取、git apply 环节出现“静默不生效”。

### 2. 冲突路径：冲突必须失败且可诊断

`test_apply_command_with_merge_conflicts` 先构造冲突文件并提交，再应用同路径 patch，要求返回 `Err`，并检查冲突标记 `<<<<<<< / ======= / >>>>>>>`（`codex-rs/chatgpt/tests/suite/apply_command_e2e.rs:119-188`）。

该用例保证“冲突不应被吞掉”，并验证 3-way 合并失败语义会反馈给调用方。

### 3. 测试资源解析路径的跨构建系统一致性

suite 通过 `find_resource!("tests/task_turn_fixture.json")` 加载 fixture（`codex-rs/chatgpt/tests/suite/apply_command_e2e.rs:70-73`），确保在 Cargo 与 Bazel 下都能定位资源；`codex_rust_crate` 也把 `tests/**` 放入 `data` 和 `compile_data`（`defs.bzl:237-251`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 关键流程

1. 仓库准备
- `create_temp_git_repo()` 创建临时目录并执行 `git init`、`git config user.*`、`git add`、`git commit`（`codex-rs/chatgpt/tests/suite/apply_command_e2e.rs:8-67`）。
- 为避免宿主机 git 配置干扰，关键命令显式设置 `GIT_CONFIG_GLOBAL=/dev/null` 与 `GIT_CONFIG_NOSYSTEM=1`（同文件 `:11-14`）。

2. 任务载荷准备
- 从 `tests/task_turn_fixture.json` 读取并反序列化为 `GetTaskResponse`（`codex-rs/chatgpt/tests/suite/apply_command_e2e.rs:70-75`）。
- fixture 里包含 `output_items` 的 `pr` 与 `message` 两类项，验证解析层仅提取 `pr.output_diff.diff`（`codex-rs/chatgpt/tests/task_turn_fixture.json:3-63`）。

3. 被测函数执行
- 测试直接调用 `apply_diff_from_task(task_response, Some(repo_path))`（`codex-rs/chatgpt/tests/suite/apply_command_e2e.rs:88-90,173`）。
- `apply_diff_from_task` 先检查 `current_diff_task_turn`，再从 `output_items` 找 `OutputItem::Pr`，最后下发 `apply_diff`（`codex-rs/chatgpt/src/apply_command.rs:44-55`）。

4. patch 应用
- `apply_diff` 构造 `codex_git::ApplyGitRequest { cwd, diff, revert:false, preflight:false }` 并调用 `codex_git::apply_git_patch`（`codex-rs/chatgpt/src/apply_command.rs:58-67`）。
- `apply_git_patch` 会执行 `git apply --3way <patch>`，并返回结构化结果：`exit_code/applied_paths/skipped_paths/conflicted_paths/stdout/stderr`（`codex-rs/utils/git/src/apply.rs:25-35,55,103-123`）。
- 非零退出码时 `apply_diff` 组装详细错误并 `bail!`（`codex-rs/chatgpt/src/apply_command.rs:67-76`）。

### 关键数据结构

- `GetTaskResponse { current_diff_task_turn: Option<AssistantTurn> }`（`codex-rs/chatgpt/src/get_task.rs:7-9`）。
- `AssistantTurn { output_items: Vec<OutputItem> }`（`codex-rs/chatgpt/src/get_task.rs:13-15`）。
- `OutputItem` 是带 `type` tag 的枚举，仅显式处理 `pr`，其他都归为 `Other`（`codex-rs/chatgpt/src/get_task.rs:17-25`）。
- `PrOutputItem { output_diff: OutputDiff { diff: String } }`（`codex-rs/chatgpt/src/get_task.rs:27-35`）。

### 协议与命令

- 上游协议：`get_task` 请求 `GET /wham/tasks/{task_id}`（`codex-rs/chatgpt/src/get_task.rs:37-39`）。
- HTTP 客户端：`chatgpt_get_request` 使用 `chatgpt_base_url + path`，附带 bearer token 和 `chatgpt-account-id` header（`codex-rs/chatgpt/src/chatgpt_client.rs:24-43`）。
- CLI 命令入口：`codex apply`（alias `a`）在主程序中注册，执行时进入 `run_apply_command`（`codex-rs/cli/src/main.rs:128-130,842-849`）。
- git 子命令（测试内显式调用）：`git init/config/add/commit`（`codex-rs/chatgpt/tests/suite/apply_command_e2e.rs:16-58,145-157`）。

## 关键代码路径与文件引用

### 目标目录

- `codex-rs/chatgpt/tests/suite/mod.rs:1-2`：suite 聚合入口。
- `codex-rs/chatgpt/tests/suite/apply_command_e2e.rs:8-67`：临时仓库与初始 commit 构建。
- `codex-rs/chatgpt/tests/suite/apply_command_e2e.rs:70-75`：fixture 加载反序列化。
- `codex-rs/chatgpt/tests/suite/apply_command_e2e.rs:77-117`：成功场景断言。
- `codex-rs/chatgpt/tests/suite/apply_command_e2e.rs:119-188`：冲突场景断言。

### 调用方与入口上下文

- `codex-rs/chatgpt/tests/all.rs:1-3`：integration test binary 入口，导入 `suite`。
- `codex-rs/cli/src/main.rs:128-130,842-849`：`codex apply` 子命令声明和转发执行。
- `codex-rs/chatgpt/src/apply_command.rs:21-38`：`run_apply_command`（加载配置、初始化 token、拉取任务并调用核心 apply）。

### 被调用方与下游依赖

- `codex-rs/chatgpt/src/apply_command.rs:40-79`：`apply_diff_from_task` / `apply_diff`。
- `codex-rs/chatgpt/src/get_task.rs:6-40`：任务响应模型和 `/wham/tasks/{task_id}` 获取逻辑。
- `codex-rs/chatgpt/src/chatgpt_client.rs:12-61`：HTTP 请求与错误处理。
- `codex-rs/utils/git/src/apply.rs:41-124`：git apply 封装。
- `codex-rs/utils/cargo-bin/src/lib.rs:109-133`：`find_resource!` 宏。

### 配置、脚本、文档

- 配置：`chatgpt_base_url` 默认 `https://chatgpt.com/backend-api/`（`codex-rs/core/src/config/mod.rs:2744-2747`）。
- Bazel 测试装配：`codex_rust_crate` 为 `tests/*.rs` 生成 `rust_test` 并附带 `tests/**` 资源（`defs.bzl:237-251`）。
- 日常研究维护脚本：`.ops/generate_daily_research_todo.sh` 基于 `blueprint_checklist.md` 生成当日 TODO（`.ops/generate_daily_research_todo.sh:5-7,15-39`）。
- crate 文档：`codex-rs/chatgpt/README.md` 仅描述职责边界，未细化 `apply` 测试范围（`codex-rs/chatgpt/README.md:1-5`）。

## 依赖与外部交互

### 内部依赖

- `codex-chatgpt`：`apply_command`、`get_task` 模块。
- `codex-git`：实际 patch 应用能力（`apply_git_patch`）。
- `codex-utils-cargo-bin`：测试资源路径解析（Cargo/Bazel 双兼容）。
- `tokio`：异步测试与异步进程调用。
- `tempfile`、`serde_json`：临时环境与 fixture 反序列化。

### 外部交互

- 文件系统：创建临时仓库、写入/读取 `scripts/fibonacci.js`。
- 进程：调用系统 `git`。
- 网络：suite 本身不发网络请求，但验证的数据模型与线上 `/wham/tasks/{id}` 协议耦合。

### 契约耦合点

- 与后端任务 schema 的耦合：测试依赖 `pr.output_diff.diff` 路径。
- 与 git 行为的耦合：冲突场景依赖 `git apply --3way` 的冲突标记产物与退出码。
- 与测试运行器的耦合：fixture 定位依赖 `find_resource!` 与 Bazel runfiles 机制。

## 风险、边界与改进建议

### 风险与边界

1. 覆盖面集中在“有 diff”的两条路径
- 未覆盖 `current_diff_task_turn=None`、无 `pr` item、空 diff、`cwd=None` fallback 等分支（`codex-rs/chatgpt/src/apply_command.rs:44-59`）。

2. 全局 cwd 改写可能引入并发干扰
- 冲突用例调用了 `std::env::set_current_dir`（`codex-rs/chatgpt/tests/suite/apply_command_e2e.rs:159-167`），而 `current_dir` 是进程级全局状态，理论上会与并发测试互相影响。

3. 断言偏“关键字存在”
- 成功路径主要断言 `contains` 和行数，未校验完整文件内容，因此对局部文本偏差敏感度有限（`codex-rs/chatgpt/tests/suite/apply_command_e2e.rs:97-116`）。

4. fixture 与后端演进存在漂移风险
- `GetTaskResponse` 只保留最小字段；如果服务端未来迁移 diff 挂载位置，当前 suite 无法提前体现兼容策略差异（`codex-rs/chatgpt/src/get_task.rs:11-35`）。

5. 路径覆盖边界
- suite 只测核心函数，不测 `run_apply_command` 的配置加载与 token 初始化失败路径（`codex-rs/chatgpt/src/apply_command.rs:21-37`、`codex-rs/chatgpt/src/chatgpt_token.rs:22-35`）。

### 改进建议

1. 增加负向用例矩阵
- 新增 `No diff turn found`、`No PR output item found`、空 diff 等 case，直接断言错误文本与分支行为。

2. 避免进程级 cwd 依赖
- 优先依赖 `apply_diff_from_task(..., Some(repo_path))` 参数，不再修改全局 `current_dir`，降低并发噪声。

3. 强化结果断言
- 成功用例改为完整文本比对（或快照）；
- 失败用例补充 `Git apply failed (applied/skipped/conflicts)` 统计字段断言。

4. 补充入口级集成测试
- 在可控注入条件下增加 `run_apply_command` 级别测试，覆盖配置与 token 初始化链路。

5. 文档补齐
- 在 `codex-rs/chatgpt/README.md` 增加一段 `apply` 测试覆盖范围说明，降低后续维护者理解成本。
