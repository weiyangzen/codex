# DIR `codex-rs/chatgpt/tests` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/chatgpt/tests`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 关联 crate：`codex-chatgpt`

## 场景与职责

`codex-rs/chatgpt/tests` 是 `codex-chatgpt` crate 的集成测试入口目录，当前职责聚焦在 `codex apply` 的“任务 diff -> 本地 git apply”路径校验，而非 connectors 或网络层行为。

该目录采用“单测试二进制聚合”模式：

- `all.rs` 作为集成测试入口（`codex-rs/chatgpt/tests/all.rs:1-3`），仅声明 `mod suite;`。
- `suite/mod.rs` 继续聚合具体套件（`codex-rs/chatgpt/tests/suite/mod.rs:1-2`），目前仅 `apply_command_e2e`。
- 真实测试逻辑位于 `suite/apply_command_e2e.rs`，包含成功与冲突两个端到端用例。

从架构位置看，这些测试不直接走 CLI 参数解析，也不发起真实 HTTP 请求；它们通过 fixture 反序列化成 `GetTaskResponse` 后，直接调用 `apply_diff_from_task`，验证核心业务逻辑和 git 交互结果（`codex-rs/chatgpt/tests/suite/apply_command_e2e.rs:1-188`）。

## 功能点目的

### 1) 验证 diff 能被正确应用到临时仓库

目的：确保 `apply_diff_from_task` 在给定合法 `current_diff_task_turn.output_items[type=pr].output_diff.diff` 时，能成功把补丁落到工作树。

- 用例：`test_apply_command_creates_fibonacci_file`（`.../apply_command_e2e.rs:77-117`）。
- 断言：
  - 目标文件存在（`scripts/fibonacci.js`）。
  - 关键内容存在（函数定义、shebang、module export）。
  - 行数等于 fixture 声明的 31 行。

### 2) 验证冲突场景下失败语义

目的：确保 3-way apply 遇到同路径冲突时返回错误，并把冲突标记写回文件，避免“静默成功”。

- 用例：`test_apply_command_with_merge_conflicts`（`.../apply_command_e2e.rs:119-188`）。
- 构造：先写入并提交冲突版本 `scripts/fibonacci.js`，再应用 fixture diff。
- 断言：
  - `apply_diff_from_task` 返回 `Err`。
  - 目标文件包含 `<<<<<<<` / `=======` / `>>>>>>>` 冲突标记。

### 3) 验证测试资源定位策略

目的：保证 fixture 在 Cargo/Bazel 下都可定位。

- 测试使用 `find_resource!("tests/task_turn_fixture.json")`（`.../apply_command_e2e.rs:70-73`）。
- 该宏在 Bazel runfiles 与 Cargo manifest dir 间自动切换（`codex-rs/utils/cargo-bin/src/lib.rs:109-133`，`codex-rs/utils/cargo-bin/README.md:9-16`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 测试执行主流程

1. 创建隔离 git 仓库
- `create_temp_git_repo()` 使用 `tempfile::TempDir` 建立临时目录并执行：
  - `git init`
  - `git config user.email/user.name`
  - `git add README.md && git commit`
- 为了隔离宿主机 git 配置，设置了：
  - `GIT_CONFIG_GLOBAL=/dev/null`
  - `GIT_CONFIG_NOSYSTEM=1`
  （`.../apply_command_e2e.rs:8-67`）

2. 加载任务 fixture 并反序列化
- 读取 `tests/task_turn_fixture.json`，解析成 `GetTaskResponse`（`.../apply_command_e2e.rs:70-75`）。
- fixture 的关键 JSON 路径：`current_diff_task_turn.output_items[0].type="pr".output_diff.diff`（`codex-rs/chatgpt/tests/task_turn_fixture.json:2-22`）。

3. 直接调用被测函数
- `apply_diff_from_task(task_response, Some(repo_path))`（`.../apply_command_e2e.rs:88-90,173`）。
- 被测函数实现位于 `codex-rs/chatgpt/src/apply_command.rs:40-79`。

4. `apply_diff_from_task` 内部行为
- 从 `GetTaskResponse.current_diff_task_turn` 取 diff turn，否则报 `No diff turn found`（`.../apply_command.rs:44-47`）。
- 在 `output_items` 查找 `OutputItem::Pr` 的 `output_diff.diff`，否则报 `No PR output item found`（`.../apply_command.rs:48-55`）。
- 调用 `codex_git::apply_git_patch` 执行 patch（`.../apply_command.rs:60-67`）。

5. git patch 机制
- `codex_git::apply_git_patch` 将 diff 写入临时文件后执行 `git apply --3way`（`codex-rs/utils/git/src/apply.rs:41-56,103-124`）。
- 返回结构化结果：`exit_code/applied_paths/skipped_paths/conflicted_paths/stdout/stderr`（`.../apply.rs:25-35`）。
- `apply_command` 仅接受 `exit_code == 0`，否则封装失败统计并返回错误（`codex-rs/chatgpt/src/apply_command.rs:67-76`）。

### B. 关键数据结构

1. 测试输入模型（最小任务模型）
- `GetTaskResponse { current_diff_task_turn: Option<AssistantTurn> }`
- `AssistantTurn { output_items: Vec<OutputItem> }`
- `OutputItem` 为 tagged enum，仅显式处理 `type = pr`
- `PrOutputItem { output_diff: OutputDiff { diff: String } }`
（`codex-rs/chatgpt/src/get_task.rs:6-35`）

2. fixture 内容特征
- 同时包含 `pr` 与 `message` 两种 `output_items`，测试了“只抽取 pr diff、忽略 message”的逻辑（`task_turn_fixture.json:3-63`）。
- `output_diff.diff` 为新增文件 patch，行数与测试断言一致（31 行）（`task_turn_fixture.json:12,18`）。

### C. 协议与命令语义

1. 线上协议（本目录测试的上游契约）
- 生产代码通过 `GET /wham/tasks/{task_id}` 获取 `GetTaskResponse`（`codex-rs/chatgpt/src/get_task.rs:37-39`）。
- 测试不打网络，但 fixture JSON 结构直接模拟该协议返回。

2. CLI 命令链路（测试对象的调用方）
- `codex apply` 子命令在 CLI 注册（`codex-rs/cli/src/main.rs:128-130`）。
- 执行分支调用 `run_apply_command`（`codex-rs/cli/src/main.rs:842-849`）。
- 本目录测试绕过 CLI，仅测核心逻辑函数。

3. 本地系统命令
- 测试用 `tokio::process::Command` 执行 git 命令构造仓库状态（`apply_command_e2e.rs:16-58,145-157`）。
- 被测路径间接执行 `git apply --3way`（`utils/git/src/apply.rs:55`）。

## 关键代码路径与文件引用

### A. 目标目录（直接研究对象）

- `codex-rs/chatgpt/tests/all.rs:1-3`：集成测试入口与模块聚合。
- `codex-rs/chatgpt/tests/suite/mod.rs:1-2`：suite 聚合点。
- `codex-rs/chatgpt/tests/suite/apply_command_e2e.rs:8-67`：临时仓库准备。
- `codex-rs/chatgpt/tests/suite/apply_command_e2e.rs:70-75`：fixture 加载与反序列化。
- `codex-rs/chatgpt/tests/suite/apply_command_e2e.rs:77-117`：成功路径断言。
- `codex-rs/chatgpt/tests/suite/apply_command_e2e.rs:119-188`：冲突路径断言。
- `codex-rs/chatgpt/tests/task_turn_fixture.json:1-65`：固定任务响应样本。

### B. 调用方（谁触发被测逻辑）

- `codex-rs/cli/src/main.rs:128-130,842-849`：`codex apply` 子命令注册与转发。
- `codex-rs/chatgpt/src/apply_command.rs:21-38`：CLI 层的 `run_apply_command`。

### C. 被调用方（测试覆盖链路下游）

- `codex-rs/chatgpt/src/apply_command.rs:40-79`：被测核心函数与错误路径。
- `codex-rs/chatgpt/src/get_task.rs:6-40`：任务响应结构及 `/wham/tasks/{task_id}` 请求函数。
- `codex-rs/utils/git/src/apply.rs:16-35,41-56,103-124`：git apply 实现与返回模型。
- `codex-rs/utils/cargo-bin/src/lib.rs:109-133`：`find_resource!` 资源解析宏。

### D. 配置、测试、脚本、文档相关上下文

- 配置：`chatgpt_base_url` 默认 `https://chatgpt.com/backend-api/`（`codex-rs/core/src/config/mod.rs:2744-2747`）。
- 测试：当前目录仅覆盖 apply 场景；connectors 测试在 `codex-rs/chatgpt/src/connectors.rs` 内联单元测试。
- 脚本/命令：
  - 常规执行：`cargo test -p codex-chatgpt`
  - 资源定位依赖 runfiles 策略（`codex-rs/utils/cargo-bin/README.md:1-16`）。
- 文档：
  - crate 说明：`codex-rs/chatgpt/README.md:1-5`
  - runfiles 说明：`codex-rs/utils/cargo-bin/README.md:1-20`

## 依赖与外部交互

### 1) 内部依赖

- `codex-chatgpt` 导出的业务函数：`apply_diff_from_task`。
- `codex-git`：实际 patch 应用引擎。
- `codex-utils-cargo-bin`：fixture 路径解析。
- `tokio`：异步测试 + 异步进程。
- `tempfile`：隔离临时仓库环境。
- `serde_json`：fixture -> `GetTaskResponse` 反序列化。

### 2) 外部交互

- 文件系统：创建临时仓库、写入冲突文件、读取结果文件。
- 子进程：执行 `git init/config/add/commit`。
- 网络：本目录测试不访问网络；通过本地 fixture 模拟服务端响应。

### 3) 与相邻模块的契约关系

- 与 `chatgpt/src/get_task.rs` 契约绑定：fixture 必须保持兼容 `GetTaskResponse` 结构。
- 与 `utils/git/src/apply.rs` 契约绑定：冲突行为依赖 `git apply --3way` 的输出与文件写入语义。
- 与 CLI 契约关系：测试覆盖核心 apply 逻辑，但未覆盖 `run_apply_command` 中配置加载与 token 初始化路径（`chatgpt_token` / `chatgpt_client`）。

## 风险、边界与改进建议

### 风险与边界

1. 覆盖面偏窄：
- 仅覆盖 `apply_diff_from_task` 成功/冲突两条路径。
- 未覆盖：`No diff turn found`、`No PR output item found`、`cwd=None` fallback、`git` 不可用等异常。

2. 断言粒度较粗：
- 当前成功用例主要用 `contains` + 行数断言，未校验完整文件文本一致性。
- 这会降低对局部错误修改（例如 shebang 位置变化、缩进误差）的敏感度。

3. 冲突断言依赖 git 文本标记：
- 通过检查 `<<<<<<<` 等关键字判定冲突，跨 git 版本虽通常稳定，但仍属于间接信号。
- 可以增加对 `Git apply failed (...)` 错误内容中 `conflicts` 计数的断言来增强稳定性。

4. fixture 与后端演进可能漂移：
- `GetTaskResponse` 是最小模型，后端若调整 diff 携带位置（例如从 `pr.output_diff` 迁移到其他 item）时，当前测试不会提前暴露兼容策略差距。

5. Bazel 资源可见性潜在风险：
- 当前 `chatgpt/BUILD.bazel` 未显式声明测试资源（`codex-rs/chatgpt/BUILD.bazel:1-6`）。
- 目录目前依赖 runfiles 体系工作，若后续引入 compile-time 文件读取模式，需补充 Bazel data 声明。

### 改进建议

1. 补充失败路径测试：
- 新增 fixture：
  - 无 `current_diff_task_turn`
  - `output_items` 不含 `pr`
  - `pr` 存在但 `diff` 为空
- 分别断言错误消息，提升行为契约清晰度。

2. 增加结构化错误断言：
- 对 `apply_result.unwrap_err().to_string()` 断言包含 `applied/skipped/conflicts` 统计字段。

3. 提升成功用例确定性：
- 将当前 `contains` 检查升级为“整体文本等值”或快照断言（保存期望文件模板）。

4. 增加一次“入口函数级”集成测试：
- mock/注入配置与 auth 后执行 `run_apply_command`，验证 CLI 入口链路与核心逻辑之间没有参数传递退化。

5. 文档同步建议：
- 在 `codex-rs/chatgpt/README.md` 增加简短“tests scope”说明，明确该目录当前只覆盖 apply 主路径，便于后续贡献者理解测试边界。
