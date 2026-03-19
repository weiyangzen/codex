# codex-rs/.config 研究（当前目录）

## 场景与职责

`codex-rs/.config` 当前仅包含一个文件：`nextest.toml`。该目录承担的是 **Rust 工作区测试执行策略配置**，而不是业务代码配置。

它的核心职责是：

- 为 `cargo nextest` 提供默认超时与重试终止策略。
- 对少量慢测/易波动测试做定向超时放宽。
- 对特定测试集合施加并发上限（test group），降低竞争与抖动。
- 作为本地开发与 CI 的统一测试调度约束入口。

从调用链看，`nextest.toml` 是被动配置文件，主要由以下入口读取：

- 本地：`just test` -> `cargo nextest run --no-fail-fast`（仓库根 `justfile` 已将工作目录固定为 `codex-rs`）。
- CI：`rust-ci` workflow 安装 `nextest` 后执行 `cargo nextest run --all-features --no-fail-fast ...`。

## 功能点目的

### 1) 默认慢测阈值（全局）

`[profile.default]` 配置：

- `slow-timeout.period = 15s`
- `terminate-after = 2`

目的是在默认情况下对“卡住/异常慢”的测试快速施压，避免无界等待（`codex-rs/.config/nextest.toml:1-3`）。

### 2) 慢测白名单（定向放宽）

对两个名称模式放宽至 `1m x4`：

- `test(rmcp_client)`
- `test(humanlike_typing_1000_chars_appears_live_no_placeholder)`

并明确注释“不要新增此列表”，表明该列表被视为例外机制而非常态（`codex-rs/.config/nextest.toml:12-15`）。

对 `approval_matrix_covers_all_modes` 放宽到 `30s x2`（`codex-rs/.config/nextest.toml:17-19`）。

### 3) 测试分组并发限制

定义两个 test group：

- `app_server_protocol_codegen`：`max-threads = 1`
- `app_server_integration`：`max-threads = 1`

并通过 filter 将对应测试绑定到组，达到“仅该组串行，其他测试保持并行”的目标（`codex-rs/.config/nextest.toml:5-9,21-29`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 配置数据结构

`nextest.toml` 使用的是 nextest profile + override + test-group 组合：

- `profile.default`：全局默认。
- `profile.default.overrides[]`：基于过滤表达式的局部覆盖。
- `test-groups.<name>.max-threads`：组内并发上限。
- override 中 `test-group = '...'`：将匹配测试加入组。

### B. 过滤表达式（filter DSL）

当前配置实际使用了如下过滤原语组合：

- `test(name_substring)`：按测试名匹配。
- `package(crate-name)`：按 crate/package 匹配。
- `kind(test)`：限定 integration test 类型（结合注释用于避免把库内单元测试也串行化）。
- `|` 与 `&`：并集与交集组合。

示例：

- `package(codex-app-server) & kind(test)`
- `package(codex-app-server-protocol) & (test(...) | test(...))`

### C. 执行流程（本地 + CI）

1. 本地开发执行 `just test`。
2. 根 `justfile` 将工作目录切到 `codex-rs`，命令为 `cargo nextest run --no-fail-fast`。
3. `cargo nextest` 在工作区目录读取 `.config/nextest.toml`，应用 profile/override/group。
4. CI 在 `.github/workflows/rust-ci.yml` 中同样运行 nextest（含 `--all-features`、`--target`、`--cargo-profile ci-test`、`--timings`），并设置 `NEXTEST_STATUS_LEVEL=leak` 强化泄漏可见性。

### D. 关键受控测试实例

- 慢测白名单：
  - `rmcp_client_can_list_and_read_resources`（会拉起 stdio 测试服务并进行资源读写握手）。
  - `humanlike_typing_1000_chars_appears_live_no_placeholder`（在 `tui` 与 `tui_app_server` 各有一份同名测试）。
  - `approval_matrix_covers_all_modes`（多场景审批矩阵，含网络前置判断）。
- 串行组：
  - `codex-app-server-protocol` 的 schema/codegen 一组测试。
  - `codex-app-server` integration test 全量（注释说明其每个 case 都会拉起 app-server 子进程）。

## 关键代码路径与文件引用

- 目标目录与配置文件
  - `codex-rs/.config/nextest.toml:1-29`

- 本地入口（调用方）
  - `justfile:1`（`working-directory = "codex-rs"`）
  - `justfile:40-47`（`just test` -> `cargo nextest run --no-fail-fast`）

- CI 入口（调用方）
  - `.github/workflows/rust-ci.yml:629-632`（安装 nextest）
  - `.github/workflows/rust-ci.yml:645-650`（执行 nextest + `NEXTEST_STATUS_LEVEL=leak`）

- 被约束测试（被调用方）
  - `codex-rs/rmcp-client/tests/resources.rs:56-150`
  - `codex-rs/tui/src/bottom_pane/chat_composer.rs:9376-9396`
  - `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs:9426-9446`
  - `codex-rs/core/tests/suite/approvals.rs:1626-1634`
  - `codex-rs/app-server-protocol/tests/schema_fixtures.rs:11-49`
  - `codex-rs/app-server-protocol/src/export.rs:2042-2261,2274-2307,2693-2747`
  - `codex-rs/app-server/tests/common/mcp_process.rs:622-631`（注释直接提到 nextest 的 `LEAK`）

- 文档/脚本上下文
  - `docs/install.md:29-45`（说明安装 cargo-nextest、使用 `just test`）
  - `docs/contributing.md:57`（建议统一使用 `just` 测试入口）

## 依赖与外部交互

### 依赖

- 工具依赖：`cargo-nextest`（本地可选，CI 固定安装）。
- 构建与测试运行时：Cargo、Rust toolchain、workspace crate graph。

### 外部交互形态

- 进程级交互：
  - app-server integration tests 会频繁拉起子进程（由 nextest 分组串行约束）。
  - rmcp-client 相关测试通过 stdio 与测试服务进程交互。
- 文件系统交互：
  - app-server-protocol schema 相关测试会读取仓库内 fixture 并在临时目录生成对比。
- CI 平台交互：
  - GitHub Actions 使用 `taiki-e/install-action` 安装 nextest，并上传 timings 工件。

## 风险、边界与改进建议

### 风险与边界

1. **白名单扩散风险**：`Do not add new tests here` 仅靠注释约束，缺少自动守卫。
2. **过滤表达式漂移风险**：基于测试名字符串匹配，重命名后可能静默失效或意外命中。
3. **并发策略可见性不足**：`app_server_protocol_codegen` 串行原因未在配置内详细解释，后续维护者难判断是否还能放宽。
4. **目录边界单一**：当前 `.config` 仅服务 nextest；若后续加入更多工具配置，缺少聚合文档会提升认知成本。

### 改进建议

1. 为每条 override 增加“触发条件 + 退出条件”注释（例如：何时可移出慢测白名单）。
2. 在 CI 新增轻量校验：确保关键 filter 至少命中一个测试（避免重命名后配置失效）。
3. 将 `test(rmcp_client)` 这类宽匹配逐步收敛到更明确的测试集合，降低误命中。
4. 在 `codex-rs/docs` 增补一页 “测试调度与 nextest 配置约定”，把 `just test`、`nextest.toml`、`LEAK` 排障路径串起来。
