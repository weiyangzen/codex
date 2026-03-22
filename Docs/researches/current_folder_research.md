# DIR `.` 研究报告（仓库根目录）

- 研究对象：`/home/sansha/Github/codex`（DIR `.`）
- 研究日期：2026-03-22
- 研究范围：根目录作为多子系统单仓的"总入口层"，覆盖调用关系、配置与构建、测试与发布、脚本自动化与外部交互。

---

## 场景与职责

根目录的职责不是承载单一业务逻辑，而是作为"多运行时产品矩阵"的编排层：

### 1. 对外产品入口与定位

- 根 README 明确仓库同时服务 CLI、本地 IDE 集成、桌面/网页体验，CLI 安装方式覆盖 npm、Homebrew、release 二进制（`README.md:1-60`）。
- 产品矩阵包括：
  - **Codex CLI**: 本地运行的编码代理（主要入口）
  - **IDE 扩展**: VS Code、Cursor、Windsurf 等
  - **桌面应用**: `codex app` 命令启动
  - **云端代理**: Codex Web（chatgpt.com/codex）

### 2. 多技术栈聚合

- **Rust 主实现**位于 `codex-rs/`，是一个大型 workspace，包含 60+ crate（`codex-rs/Cargo.toml:1-157`）。
- **Node/PNPM 工作区**承载 npm 分发封装、TypeScript SDK、shell-tool-mcp（`pnpm-workspace.yaml:1-12`）。
- 根 `package.json` 负责仓库级格式化与辅助脚本，而非业务主逻辑（`package.json:2-25`）。

### 3. 构建与发布控制面

- `justfile` 默认工作目录指向 `codex-rs`，统一了常用开发命令（fmt/fix/test/schema/bazel）（`justfile:1-96`）。
- Bazel 与 Cargo 共存，根 `BUILD.bazel`/`MODULE.bazel`负责跨平台工具链和外部依赖注入（`BUILD.bazel:1-35`，`MODULE.bazel:1-185`）。
- GitHub Actions 在根目录统一编排 JS/Rust CI、发布、签名、产物打包（例如 `ci.yml`、`rust-ci.yml`、`rust-release.yml`）。

### 4. 文档与运维自动化承接层

- `docs/` 提供安装、贡献、配置等入口（`docs/install.md:1-64`，`docs/contributing.md:1-97`）。
- `.ops/` 脚本维护研究 checklist/todo 与自动任务分发（`.ops/generate_research_blueprint_checklist.sh:1-73`，`.ops/generate_daily_research_todo.sh:1-42`，`.ops/research_guard.sh:131-205`）。

---

## 功能点目的

从根目录视角可抽象为 8 个目的：

### 1. 将"安装体验"与"原生二进制执行"解耦

- `@openai/codex` 的 JS 入口仅负责平台探测与二进制转发，业务逻辑在 Rust 二进制中（`codex-cli/bin/codex.js:15-229`，`codex-cli/package.json:2-22`）。
- 支持的平台包括：Linux x64/arm64、macOS x64/arm64、Windows x64/arm64。

### 2. 将"交互模式"与"执行模式"统一在一个 CLI 门面

- `codex-rs/cli` 的 `Subcommand` 同时承载 TUI、exec、mcp、app-server、sandbox、cloud 等模式（`codex-rs/cli/src/main.rs:87-152`）。
- 主要子命令包括：`exec`、`review`、`login`、`logout`、`mcp`、`app-server`、`app`（macOS）、`completion`、`sandbox`、`debug`、`apply`、`resume`、`fork`、`cloud`、`responses-api-proxy` 等。

### 3. 将"协议层"与"业务层"分离

- `codex-protocol` 约束为类型层，尽量避免业务逻辑（`codex-rs/protocol/README.md:1-5`）。
- app-server 通过 JSON-RPC 双向协议提供线程/turn/item 抽象，承担 IDE/SDK 的稳定接口（`codex-rs/app-server/README.md:20-185`）。

### 4. 支持多消费端（CLI/IDE/SDK）共享同一核心能力

- **TypeScript SDK** 通过拉起 `codex` 二进制交换 JSONL 事件（`sdk/typescript/README.md:5-149`）。
- **Python SDK** 对接 app-server v2，使用 schema 生成模型并维持线协议兼容（`sdk/python/README.md:3-103`）。

### 5. 发布产物覆盖多平台、多封装形式

- Rust release 工作流构建多 target、签名并打包（`.github/workflows/rust-release.yml:8-689`）。
- npm staging 脚本根据 release 工件二次拼装 `codex`、平台包、responses proxy、sdk（`scripts/stage_npm_packages.py:16-206`，`codex-cli/scripts/build_npm_package.py:21-340`）。

### 6. 安全基线前置

- sandbox 与 approvals 在文档中作为核心安全模型（`docs/sandbox.md:1-3`）。
- shell-escalation 与 responses proxy 分别解决命令拦截升级、API key 最小暴露（`codex-rs/shell-escalation/README.md:3-28`，`codex-rs/responses-api-proxy/README.md:3-80`）。

### 7. 让 schema 与测试联动，防止协议漂移

- app-server-protocol 测试直接比对 vendored schema 与生成结果（`codex-rs/app-server-protocol/tests/schema_fixtures.rs:11-143`），并提供重生成功能入口（`codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs:6-42`）。

### 8. 通过研究自动化持续覆盖仓库对象

- `.ops/research_guard.sh` 会读取 checklist 首个待办并下发标准化研究任务模板（`.ops/research_guard.sh:140-250`）。

---

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 根入口到执行内核的调用链

**用户安装并执行 `codex`：**

1. npm 包入口 `codex-cli/bin/codex.js` 根据 `process.platform/process.arch` 解析目标 triple（`codex-cli/bin/codex.js:24-67`）。
2. 解析对应可选依赖包，定位 `vendor/<triple>/codex/{codex|codex.exe}`（`codex-cli/bin/codex.js:73-119`）。
3. 将 `vendor/<triple>/path` 注入 PATH（用于 bundled `rg` 等），`spawn` 原生二进制并转发信号（`codex-cli/bin/codex.js:161-229`）。

**Rust `codex` 统一分派：**

- `MultitoolCli` + `Subcommand` 统一解析（`codex-rs/cli/src/main.rs:55-152`）。
- `cli_main` 对各子命令分流到 `codex_exec::run_main`、`codex_app_server::run_main_with_transport`、`codex_mcp_server::run_main` 等（`codex-rs/cli/src/main.rs:590-917`）。

**非交互执行路径：**

- `codex-exec` 主入口支持 arg0 分派（可兼容 `codex-linux-sandbox` 模式），并将顶层 `--config` 注入内层 CLI（`codex-rs/exec/src/main.rs:1-40`）。

### 2) 协议与会话模型

**app-server 协议：**

- **传输**：stdio JSONL（默认）或 websocket（实验）`codex app-server --listen ...`（`codex-rs/app-server/README.md:22-35`）。
- **生命周期**：`initialize -> initialized -> thread/start|resume|fork -> turn/start -> item/turn 事件流 -> turn/completed`（`codex-rs/app-server/README.md:67-78`）。
- **数据模型**：Thread / Turn / Item（三层会话实体）（`codex-rs/app-server/README.md:57-65`）。

**MCP server 路径：**

- `codex-mcp-server` 在 `run_main` 中加载 config + 初始化 otel + 建立有界 channel，拆分 stdin reader / processor / stdout writer 三任务（`codex-rs/mcp-server/src/lib.rs:54-175`）。

**shell-tool-mcp 协同：**

- 声明 `codex/sandbox-state` capability，支持由 Codex harness 下发 sandbox policy 更新（`shell-tool-mcp/README.md:52-96`）。

### 3) 构建/测试/发布命令面

**开发命令聚合（just）：**

- `just fmt`, `just fix`, `just test`, `just write-config-schema`, `just write-app-server-schema`, `just bazel-lock-update`（`justfile:26-92`）。

**Rust workspace 结构：**

- 60+ crate，覆盖 core/exec/tui/app-server/protocol/sandbox/connectors 等（`codex-rs/Cargo.toml:1-157`）。

**JS/PNPM 结构：**

- workspace 包：`codex-cli`、`responses-api-proxy/npm`、`sdk/typescript`、`shell-tool-mcp`（`pnpm-workspace.yaml:1-5`）。
- 根 engines 锁定 Node>=22/PNPM>=10.29.3（`package.json:21-25`），但分发包可用更低 Node 版本（如 `codex-cli/package.json:9-11` 为 >=16）。

**CI 与 release：**

- `ci.yml`：Node/PNPM 流程 + staging npm 包 + README 规则检查 + prettier（`.github/workflows/ci.yml:7-66`）。
- `rust-ci.yml`：变更路径检测后按矩阵运行 format/lint/build/test/argument-comment-lint 等（`.github/workflows/rust-ci.yml:12-741`）。
- `rust-release.yml`：tag 校验、跨平台构建、签名、打包发布（`.github/workflows/rust-release.yml:19-689`）。

**schema 一致性机制：**

- 测试失败提示直接要求执行 `just write-app-server-schema`（`codex-rs/app-server-protocol/tests/schema_fixtures.rs:75-100`）。

### 4) 研究自动化流程（本仓库特有）

**checklist 生成：**

- 遍历目录/文件生成 `Docs/researches/blueprint_checklist.md`，保留历史完成状态（`.ops/generate_research_blueprint_checklist.sh:10-73`）。

**当日 todo：**

- 从 checklist 中抽取未完成项，生成 `Docs/researches/todos_YYYYMMDD.md`（`.ops/generate_daily_research_todo.sh:15-42`）。

**守护执行：**

- `research_guard.sh` 自动读取首个 pending 项，拼装中文任务模板并调用 `codex --yolo exec`（`.ops/research_guard.sh:140-250`）。

---

## 关键代码路径与文件引用

以下为根目录级"关键路径地图"（调用方 -> 被调用方）：

### 1. 产品与安装入口

- `README.md:1-60`
- `docs/install.md:15-50`

### 2. Node 包装入口（调用本地原生二进制）

- `codex-cli/bin/codex.js:15-229`
- `codex-cli/package.json:2-22`

### 3. Rust 主入口与子命令分派

- `codex-rs/cli/src/main.rs:55-152`
- `codex-rs/cli/src/main.rs:590-917`
- `codex-rs/exec/src/main.rs:1-40`

### 4. 协议与服务端接口

- `codex-rs/app-server/README.md:20-185`
- `codex-rs/protocol/README.md:1-5`
- `codex-rs/mcp-server/src/lib.rs:54-175`

### 5. 构建系统与工具链

- `justfile:1-96`
- `BUILD.bazel:1-35`
- `MODULE.bazel:1-185`
- `codex-rs/Cargo.toml:1-157`

### 6. 发布与打包脚本

- `scripts/stage_npm_packages.py:16-206`
- `codex-cli/scripts/build_npm_package.py:21-340`
- `.github/workflows/ci.yml:33-66`
- `.github/workflows/rust-release.yml:19-689`

### 7. SDK 与下游消费端

- `sdk/typescript/README.md:5-149`
- `sdk/python/README.md:3-103`

### 8. 安全扩展路径

- `shell-tool-mcp/README.md:5-106`
- `codex-rs/shell-escalation/README.md:3-28`
- `codex-rs/responses-api-proxy/README.md:3-80`

### 9. 研究运维自动化

- `.ops/generate_research_blueprint_checklist.sh:27-66`
- `.ops/generate_daily_research_todo.sh:20-42`
- `.ops/research_guard.sh:151-250`
- `Docs/researches/blueprint_checklist.md:9-11`

---

## 依赖与外部交互

### 1) 外部平台/服务

**OpenAI/Codex 线上文档与服务**

- 多数功能文档跳转 `developers.openai.com/codex/*`（`docs/config.md:3-25`，`docs/exec.md:1-3`，`docs/sandbox.md:1-3`）。

**OpenAI Responses API**

- `codex-responses-api-proxy` 默认上游 `https://api.openai.com/v1/responses`（`codex-rs/responses-api-proxy/README.md:3-50`）。

**GitHub Actions / Releases / GH CLI**

- npm staging 脚本通过 `gh run list` 查找 release workflow 工件（`scripts/stage_npm_packages.py:81-110`）。

**npm/pnpm 与 Python packaging**

- npm 包：`@openai/codex` / `@openai/codex-sdk` / `@openai/codex-shell-tool-mcp`。
- Python 包：`codex-app-server-sdk`（`sdk/python/pyproject.toml:1-60`）。

### 2) 关键运行时依赖

**Rust**：Cargo workspace + 多 crate 内部依赖（`codex-rs/Cargo.toml:86-157`）。

**JS**：Node + PNPM workspace（`package.json:21-25`，`pnpm-workspace.yaml:1-12`）。

**Bazel**：rules_rs + llvm + platform toolchain（`MODULE.bazel:3-64`）。

### 3) 配置面外部输入

**用户配置**：`~/.codex/config.toml`（`docs/config.md:11-13`）。

**环境变量**：

- `CODEX_CA_CERTIFICATE` / `SSL_CERT_FILE`：自定义 CA 证书
- `CODEX_SQLITE_HOME`：SQLite 状态数据库位置
- `RUST_LOG`：日志级别控制
- `OPENAI_API_KEY`：API 认证

**跨进程/系统能力**：

- sandbox（Seatbelt/Landlock/bwrap/Windows）与 shell wrapper 协议（`codex-rs/core/README.md:9-80`，`codex-rs/shell-escalation/README.md:6-16`）。

---

## 风险、边界与改进建议

### 风险

#### 1. 多构建系统并存导致认知成本高

- Cargo/Just/Bazel/PNPM/Nix/GitHub Actions 共存，排障路径容易分叉。

#### 2. 版本约束可能出现"根与子包不一致"

- 根 Node>=22（`package.json:21-23`）与某些分发包 Node>=16（`codex-cli/package.json:9-11`）存在体验差异风险。

#### 3. 协议面持续扩展导致客户端兼容压力

- app-server API 面非常广，新增字段/方法若没有严格 schema fixture 约束，易引入 SDK 破坏性变更。

#### 4. 安全边界依赖运行环境正确配置

- proxy/mcp/sandbox 等组件对"特权用户、环境变量、系统工具可用性"有前置假设，不满足时可能退化为不可用或策略旁路。

#### 5. 自动化脚本的"全局 add/commit"风险

- 研究守护和任务模板中存在 `git add -A` 模式，若工作区有非目标变更，可能误纳入提交（见 `.ops/research_guard.sh` 的 checkpoint 逻辑）。

### 边界

1. **根目录主要是编排层，不是业务算法层**。具体 agent 推理/执行策略在 `codex-rs/core` 与相关 crate，而非根脚本本身。
2. **文档中有大量跳转到官方站点**，仓库内文档偏"索引式"。
3. **外部贡献受限**：根据 `docs/contributing.md`，目前仅接受邀请制的外部贡献。

### 改进建议

#### 1. 建议增加"单页架构地图"

- 在根 `docs/` 补充一份从 `codex` 命令到 `core/app-server/mcp/sdk` 的调用拓扑图，降低新贡献者认知切换成本。

#### 2. 建议统一并显式化版本策略

- 在根 README 或 `docs/install.md` 增加"开发时 Node 版本 vs 分发包运行时版本"的对照表。

#### 3. 建议为 `.ops` 自动提交增加白名单

- 将 `git add -A` 收敛为目标路径白名单（例如 `Docs/researches/**`），避免误提交工作区噪音。

#### 4. 建议把 schema 变更流程写成固定检查清单

- 在 `docs/contributing.md` 增补 app-server 协议变更时"生成 + 测试 + SDK 同步"的步骤模板（目前规则分散在 AGENTS 与测试报错信息中）。

#### 5. 建议补充"根目录职责"文档

- 当前用户容易误以为 `codex-cli`（legacy TS）仍是主实现；可在根 docs 明确"Rust 主实现 + JS 仅分发/包装"的状态与边界。

#### 6. 建议完善 Bazel 构建文档

- MODULE.bazel 中定义了复杂的跨平台工具链配置，但缺乏面向开发者的详细说明，建议补充 Bazel 构建的最佳实践文档。

#### 7. 建议统一错误处理与日志规范

- 当前不同 crate 间的错误处理和日志格式存在差异，建议制定统一的错误码和日志结构化规范。

---

## 附录：核心 crate 职责速查

| Crate | 职责 |
|-------|------|
| `codex-core` | 核心代理逻辑、配置管理、特性标志 |
| `codex-cli` | 主 CLI 入口、子命令分派 |
| `codex-tui` | 交互式终端界面 |
| `codex-exec` | 非交互式执行模式 |
| `codex-app-server` | JSON-RPC 服务端（IDE/SDK 接口） |
| `codex-app-server-protocol` | 协议类型定义、schema 生成 |
| `codex-protocol` | 底层协议类型 |
| `codex-mcp-server` | MCP 协议服务端 |
| `codex-sandbox-*` | 各平台沙箱实现（Linux/macOS/Windows） |
| `codex-shell-escalation` | Shell 命令权限升级协议 |
| `codex-responses-api-proxy` | API 代理（安全密钥管理） |
| `codex-state` | 会话状态持久化（SQLite） |
| `codex-connectors` | 外部服务连接器 |
| `codex-skills` | 技能系统实现 |
