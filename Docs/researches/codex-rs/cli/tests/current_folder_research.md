# DIR `codex-rs/cli/tests` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/cli/tests`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 关联 crate：`codex-cli`（bin：`codex`）

## 场景与职责

`codex-rs/cli/tests` 是 `codex-cli` 的集成测试目录，职责是从“真实二进制调用”视角验证 CLI 子命令行为，而非只测函数级逻辑。

该目录重点覆盖 4 类高风险能力：

1. 记忆状态清理链路：`codex debug clear-memories` 是否同时影响 SQLite 与磁盘目录。  
   入口与断言在 `codex-rs/cli/tests/debug_clear_memories.rs:16-137`。
2. ExecPolicy JSON 协议输出：`codex execpolicy check` 的输出字段与语义稳定性。  
   入口在 `codex-rs/cli/tests/execpolicy.rs:8-119`。
3. 功能开关写入与展示：`codex features enable/disable/list` 的配置改写与排序输出。  
   入口在 `codex-rs/cli/tests/features.rs:14-91`。
4. MCP 配置 CRUD 与展示：`codex mcp add/remove/list/get` 的配置持久化、掩码展示、JSON 输出。  
   入口在 `codex-rs/cli/tests/mcp_add_remove.rs:16-228`、`codex-rs/cli/tests/mcp_list.rs:20-166`。

这些测试均通过 `assert_cmd` 直接拉起 `codex` 可执行文件，并显式设置 `CODEX_HOME` 指向临时目录，隔离真实用户环境（如 `codex-rs/cli/tests/features.rs:8-12`）。

## 功能点目的

### 1) `debug_clear_memories.rs`

目的：验证“清理记忆”是完整重置，而不是只删某一层数据。

- 预置：手动插入 `threads / stage1_outputs / jobs` 数据，并创建 `memories/` 目录与文件（`debug_clear_memories.rs:27-108`）。
- 执行：`codex debug clear-memories`（`debug_clear_memories.rs:110-114`）。
- 断言：
  - `stage1_outputs` 清空（`117-121`）
  - 记忆相关 job 清空（`122-127`）
  - `threads.memory_mode` 从 `enabled` 变 `disabled`（`129-134`）
  - `memories/` 目录被删（`134`）

### 2) `execpolicy.rs`

目的：锁定 `execpolicy check` 的输出协议，避免字段/命名漂移破坏上层调用方。

- 第一组测试验证 `decision + matchedRules.prefixRuleMatch.matchedPrefix`（`execpolicy.rs:8-61`）。
- 第二组测试验证 `justification` 字段在规则定义时会透传（`execpolicy.rs:63-119`）。

### 3) `features.rs`

目的：保证 feature 管理命令符合用户预期并与配置系统一致。

- `enable unified_exec` 会写入 `[features].unified_exec = true`（`features.rs:14-29`）。
- `disable shell_tool` 会写入 `[features].shell_tool = false`（`31-46`）。
- 启用 under-development 特性 `runtime_metrics` 会在 stderr 告警（`48-61`）。
- `features list` 输出按 feature 名字母序（`63-91`）。

### 4) `mcp_add_remove.rs`

目的：覆盖 MCP server 配置最核心“增删 + 传输类型 + 参数合法性”路径。

- `add/remove` 的全局配置落盘与幂等删除（`16-69`）。
- `--env KEY=VALUE` 写入 stdio transport（`71-105`）。
- `--url` 创建 `streamable_http`，并验证默认不会落地明文 token 文件（`107-139`）。
- `--bearer-token-env-var` 正确写入 env var 名称（`141-177`）。
- 已移除参数 `--with-bearer-token` 会失败（`179-201`）。
- 互斥参数（同时 URL 与命令）会失败（`203-228`）。

### 5) `mcp_list.rs`

目的：覆盖 MCP 展示层（文本 + JSON）和脱敏行为。

- 空配置提示（`20-31`）。
- `list` 文本模式展示表头、状态、认证列，并对 secrets 打码（`66-80`）。
- `list --json` 输出结构与字段值校验（`81-115`）。
- `get` 文本模式展示 transport 细节与 remove 指令（`117-130`）。
- `get --json` 基础字段校验（`131-137`）。
- disabled server 使用单行简化格式（`141-166`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 测试执行模型

1. 通过 `codex_utils_cargo_bin::cargo_bin("codex")` 定位可执行文件，再用 `assert_cmd` 拉起进程（例如 `features.rs:8-12`）。
2. `codex-utils-cargo-bin` 同时兼容 `cargo test` 与 `bazel test` 的二进制定位差异：
   - `CARGO_BIN_EXE_*` 读取与回退逻辑：`codex-rs/utils/cargo-bin/src/lib.rs:33-69`
   - Bazel runfiles 解析：`lib.rs:84-107,135-161`
3. 全部测试通过 `TempDir + CODEX_HOME` 保证本地隔离，避免污染真实 `~/.codex`。

### B. CLI 分发到被测命令的主链路

`codex` 入口由 `cli_main` 分发：`codex-rs/cli/src/main.rs:590-916`。

- `mcp` 分支：`main.rs:636-640` -> `McpCli::run` -> `run_add/run_remove/run_list/run_get`（`mcp_cmd.rs:158-187`）。
- `features` 分支：`main.rs:861-913` -> `enable_feature_in_config/disable_feature_in_config`（`919-942`）。
- `debug clear-memories`：`main.rs:831-834` -> `run_debug_clear_memories_command`（`970-1019`）。
- `execpolicy check`：`main.rs:836-840` -> `ExecPolicyCheckCommand::run`（`codex-rs/execpolicy/src/execpolicycheck.rs:41-57`）。

### C. `debug clear-memories` 关键实现

1. 加载配置后计算状态库路径：`main.rs:974-985`。  
2. 若状态库存在，则初始化 `StateRuntime` 并调用 `reset_memory_data_for_fresh_start()`：`986-991`。  
   - `StateRuntime::init` 负责打开并迁移 sqlite：`codex-rs/state/src/runtime.rs:83-145`。  
   - `reset_memory_data_for_fresh_start` 事务内删除 `stage1_outputs` + 相关 `jobs`，并把 `threads.memory_mode` 置 `disabled`：`codex-rs/state/src/runtime/memories.rs:42-83`。
3. 删除磁盘 `memories/` 目录（不存在则容错）：`main.rs:994-999`。
4. 汇总打印结果字符串：`main.rs:1001-1017`。

对应 schema 来源：

- `threads` 表：`codex-rs/state/migrations/0001_threads.sql:1-19`
- `stage1_outputs/jobs`：`codex-rs/state/migrations/0006_memories.sql:1-31`
- `memory_mode` 列：`codex-rs/state/migrations/0018_phase2_selection_snapshot.sql:1-3`

### D. `features` 关键实现

1. 特性名校验：`FeatureToggles::validate_feature` -> `is_known_feature_key`（`main.rs:541-547`，`codex-rs/core/src/features.rs:502-505`）。
2. `features enable/disable` 通过 `ConfigEditsBuilder::set_feature_enabled` 改写 `config.toml`（`main.rs:919-942`，`codex-rs/core/src/config/edit.rs:861-892`）。
3. `features list`：遍历 `FEATURES` 注册表后按 key 排序输出（`main.rs:888-903`），对应测试 `features.rs:63-91`。
4. under-development 告警：`maybe_print_under_development_feature_warning`（`main.rs:944-968`），`runtime_metrics` 在注册表里确认为 under-development（`codex-rs/core/src/features.rs:608-613`）。

### E. `mcp` 关键实现

#### 1) 配置读写与数据结构

- 全局 MCP 读取：`load_global_mcp_servers(codex_home)`（`codex-rs/core/src/config/mod.rs:1019-1052`）。
- 明文 `bearer_token` 被显式拒绝：`ensure_no_inline_bearer_tokens`（`config/mod.rs:1054-1072`）。
- 数据结构：
  - `McpServerConfig`：`codex-rs/core/src/config/types.rs:67-111`
  - `McpServerTransportConfig::{Stdio, StreamableHttp}`：`types.rs:247-277`
- 持久化：`ConfigEditsBuilder::replace_mcp_servers`（`codex-rs/core/src/config/edit.rs:843-847`）。

#### 2) `mcp add/remove`

- transport 互斥由 clap `ArgGroup` 保证（`mcp_cmd.rs:83-98`）。
- `add` 分支构造 stdio 或 streamable_http 配置并落盘（`mcp_cmd.rs:238-319`）。
- `remove` 删除并输出幂等提示（`352-382`）。

#### 3) OAuth 与 Auth 状态

- `add` 后若远端声明支持 OAuth，触发登录流程并在 provider 拒绝 discovered scopes 时回退重试（`mcp_cmd.rs:321-347`，`194-236`）。
- `mcp login/logout` 仅适用于 streamable_http（`385-464`）。
- `list` 的 `Auth` 列与 JSON `auth_status` 来源于 `compute_auth_statuses`（`466-489`，`codex-rs/core/src/mcp/auth.rs:126-179`）。
- 协议枚举在 `McpAuthStatus`：`codex-rs/protocol/src/protocol.rs:2881-2900`。

#### 4) 展示与脱敏

- 文本 `list` 会把 env/header 值掩码后输出（`mcp_cmd.rs:562-603,837-863`）。
- `get` disabled server 使用单行摘要（`776-783`）。
- `list/get --json` 使用固定 JSON 结构输出（`481-537`, `729-773`）。

### F. `execpolicy check` 关键实现

1. 命令参数：`--rules`（可重复）、`--pretty`、`--resolve-host-executables` + trailing command（`execpolicycheck.rs:17-39`）。
2. 执行：加载并合并 rules -> 匹配 -> 输出 JSON（`41-71`）。
3. 输出 shape：`matchedRules + decision`（`88-95`）。
4. `RuleMatch` 结构包含 `prefixRuleMatch.matchedPrefix/decision/resolvedProgram/justification`（`codex-rs/execpolicy/src/rule.rs:62-82`）。
5. README 明确了 CLI 语义与 response shape（`codex-rs/execpolicy/README.md:49-96`），与集成测试断言保持一致。

## 关键代码路径与文件引用

### 目录内（目标对象）

- `codex-rs/cli/tests/debug_clear_memories.rs:16-137`
- `codex-rs/cli/tests/execpolicy.rs:8-119`
- `codex-rs/cli/tests/features.rs:14-91`
- `codex-rs/cli/tests/mcp_add_remove.rs:16-228`
- `codex-rs/cli/tests/mcp_list.rs:20-166`

### 调用方（谁触发这些行为）

1. `cargo test -p codex-cli` / Bazel 等测试入口（目录整体）。
2. 每个集成测试通过 `assert_cmd` 启动 `codex` 二进制（例如 `features.rs:8-12`）。
3. `codex` 主分发将子命令路由到被测逻辑：`codex-rs/cli/src/main.rs:590-916`。

### 被调用方（测试间接验证到的实现）

- MCP 逻辑：`codex-rs/cli/src/mcp_cmd.rs:158-912`
- 功能开关逻辑：`codex-rs/cli/src/main.rs:919-968`
- 清理记忆逻辑：`codex-rs/cli/src/main.rs:970-1019`
- ExecPolicy 检查：`codex-rs/execpolicy/src/execpolicycheck.rs:41-95`
- 状态库与记忆重置：
  - `codex-rs/state/src/runtime.rs:83-158`
  - `codex-rs/state/src/runtime/memories.rs:42-83`
- 配置结构与编辑：
  - `codex-rs/core/src/config/mod.rs:1019-1072`
  - `codex-rs/core/src/config/types.rs:67-277`
  - `codex-rs/core/src/config/edit.rs:757-892`

### 配置、脚本、文档上下文

- CLI crate 依赖与测试依赖：`codex-rs/cli/Cargo.toml:18-69`
- 测试二进制路径工具：`codex-rs/utils/cargo-bin/src/lib.rs:33-107`
- MCP 配置文档入口：`docs/config.md:9-13`
- MCP 接口文档里对 `codex mcp` 的定位：`codex-rs/docs/codex_mcp_interface.md:49`
- ExecPolicy CLI 文档：`codex-rs/execpolicy/README.md:49-96`
- 当日研究 todo 生成脚本：`.ops/generate_daily_research_todo.sh:1-42`

## 依赖与外部交互

### 1) 进程与文件系统交互

- 测试直接拉起 `codex` 子进程（`assert_cmd`），验证 stdout/stderr 与退出码。
- 通过 `TempDir` + `CODEX_HOME` 隔离配置与状态文件。
- `debug clear-memories` 会触达：
  - SQLite 状态库（`state_db_path`）
  - `CODEX_HOME/memories` 目录删除

### 2) 配置系统交互

- MCP 与 features 都经由 `ConfigEditsBuilder` 原子改写 `config.toml`。
- MCP 读取使用 merged config 图层，但 `load_global_mcp_servers` 明确不包含 repo 内 `.codex/`（`config/mod.rs:1030-1032`）。

### 3) 协议/数据交互

- ExecPolicy 输出是机器可消费 JSON（`execpolicycheck.rs:60-95`）。
- MCP `list/get --json` 输出结构包含 transport/auth/status 字段，供自动化工具读取。

### 4) 潜在网络交互

- 当前 `cli/tests` 主要覆盖本地路径；`mcp add` 在实现层可能触发 OAuth 探测与登录（`mcp_cmd.rs:321-347`），但现有测试通过 `example.com` + 不触发 OAuth 成功路径来避免网络依赖。

## 风险、边界与改进建议

### 主要风险

1. 输出格式回归风险（文本模式）
- `mcp list/get` 与 `features list` 的文本输出使用 `contains`/简单 split 断言，难以捕捉列宽、空格、顺序等细节回归。

2. Schema 演进耦合风险
- `debug_clear_memories.rs` 直接手写 SQL 插入多列（`debug_clear_memories.rs:29-99`），一旦 state schema 演进，测试容易因列变化脆断。

3. 覆盖盲区
- `mcp login/logout`、OAuth 失败分支、`Auth` 状态多态（NotLoggedIn/BearerToken/OAuth）在该目录未覆盖。
- `debug clear-memories` 未覆盖“state db 不存在但 memories 存在/不存在”双分支 message 文案完整断言。

4. 名称与断言语义不完全一致
- `add_with_env_preserves_key_order_and_values` 名称强调顺序，但底层 `HashMap` 不保证顺序，测试实际只校验键值存在。

### 边界说明

- 本目录是集成测试，不追求覆盖所有内部 helper；很多参数解析边界已在 `main.rs` 内联单测覆盖（如 remote 限制、feature toggle 校验，`codex-rs/cli/src/main.rs:1273-1742`）。
- MCP 配置读取是“全局配置视角”，不会自动覆盖 repo 局部 `.codex/`。

### 改进建议

1. 为文本输出引入 snapshot 测试
- 对 `mcp list/get`、`features list` 增加快照测试，降低纯 `contains` 断言漏检风险。

2. 为记忆清理增加负路径/幂等覆盖
- 增加无 state db、无 memories 目录时的输出与行为断言，确保运维命令在“空状态”也稳定。

3. MCP OAuth 交互可引入可控 mock
- 通过本地 mock server 覆盖 `oauth_login_support` 的 Supported/Unknown 分支和 `retry_without_scopes` 回退逻辑。

4. 统一测试构造器
- 抽离 `CODEX_HOME + codex_command` fixture helper（当前 4 个文件重复），减少样板和维护成本。

5. 修正测试命名或断言
- `add_with_env_preserves_key_order_and_values` 建议改名为“stores_env_pairs_correctly”，或补上可验证顺序的数据结构断言。
