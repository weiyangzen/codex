# DIR `.vscode` 研究报告

- 研究对象：`/home/sansha/Github/codex/.vscode`（DIR）
- 研究时间：2026-03-19
- 目录内容：`extensions.json`、`launch.json`、`settings.json`

## 场景与职责

`.vscode/` 是仓库级 VS Code 工作区配置层，职责不是“构建产物”或“运行时代码”，而是统一贡献者在 IDE 内的开发行为基线。

它在本仓库中承担三件事：

1. 统一 Rust/TOML 编辑体验
- 通过 `settings.json` 固定 rust-analyzer 检查命令、格式化参数、目标目录，以及 TOML 格式化行为，减少“每人本地配置不同”导致的格式/检查噪声（`.vscode/settings.json:1-19`）。

2. 提供可直接复用的 Rust 调试入口
- 通过 `launch.json` 预置 CodeLLDB 的“编译 codex-tui”与“附加到运行中的 codex CLI 进程”两类调试场景（`.vscode/launch.json:1-22`）。

3. 引导插件安装最小集合
- 通过 `extensions.json` 推荐 rust-analyzer、Even Better TOML、CodeLLDB，帮助新贡献者快速具备项目所需的基础 IDE 能力（`.vscode/extensions.json:1-11`）。

补充：仓库根 `.gitignore` 虽写了 `.vscode/`，但这 3 个文件已被 Git 跟踪，因此仍作为共享配置持续生效；忽略规则主要影响“新增未跟踪文件”（`.gitignore:19-23`，`git ls-files .vscode` 可见三文件被跟踪）。

## 功能点目的

### 1) `settings.json`

目标：把 IDE 内静态检查与格式化行为对齐仓库 Rust 规范与成本控制。

- `rust-analyzer.check.command = clippy` + `checkOnSave = true`
  - 保存即跑 clippy，尽早暴露 lint 问题（`.vscode/settings.json:2-3`）。
- `rust-analyzer.check.extraArgs = ["--tests"]`
  - 明确包含测试代码检查，同时避免 `--all-features` 带来的 `target/` 膨胀（`.vscode/settings.json:4`）。
  - 历史提交 `39f00f2a0` 明确说明移除 `--all-features` 是为避免磁盘占用膨胀。
- `rust-analyzer.rustfmt.extraArgs = ["--config", "imports_granularity=Item"]`
  - 与仓库 CI/rustfmt 参数一致，减少本地格式差异（`.vscode/settings.json:5`，`.github/workflows/rust-ci.yml:74`，`justfile:24-25`）。
- `rust-analyzer.cargo.targetDir = ${workspaceFolder}/codex-rs/target/rust-analyzer`
  - 把 IDE 分析产物隔离到专用目录，减少与常规构建互相污染（`.vscode/settings.json:6`）。
- TOML 格式器：`tamasfe.even-better-toml`
  - 禁止数组重排，保留 `~/.codex/config.toml` 中如 `notify`、MCP `args` 等顺序语义（`.vscode/settings.json:11-18`，`codex-rs/core/src/config/mod.rs:308-328`，`codex-rs/core/src/config/types.rs:119-123`）。

### 2) `launch.json`

目标：减少 Rust 调试的启动摩擦。

- `Cargo launch`
  - 在 `${workspaceFolder}/codex-rs` 里执行 `cargo build --bin=codex-tui`，用于调试前构建（`.vscode/launch.json:5-12`）。
- `Attach to running codex CLI`
  - 通过 `pickProcess` 选择 PID 后附加，适合排查“仅在真实运行态出现”的问题（`.vscode/launch.json:14-20`）。

### 3) `extensions.json`

目标：把“项目常用插件”声明为推荐而非强制依赖。

- 推荐：`rust-lang.rust-analyzer`、`tamasfe.even-better-toml`、`vadimcn.vscode-lldb`（`.vscode/extensions.json:3-5`）。
- 对 `.github/workflows` 的 YAML 插件仅注释提示，避免给多数不改 CI 的贡献者增加插件负担（`.vscode/extensions.json:7-9`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 数据结构

三文件均为 VS Code JSONC 配置对象（允许注释与尾逗号）：

1. `extensions.json`
- 顶层 `recommendations: string[]`，值为 Marketplace 扩展 ID。

2. `launch.json`
- 顶层 `version` 与 `configurations: LaunchConfig[]`。
- 配置字段含 `type=request=name`、`cargo.cwd`、`cargo.args`、`pid`、`sourceLanguages`。

3. `settings.json`
- 以键值映射表达“语言工具参数”：`rust-analyzer.*`、`[rust]`、`[toml]`、`evenBetterToml.*`。

### B. 关键流程（从 IDE 到命令执行）

1. 保存 Rust 文件
- VS Code 读取 `.vscode/settings.json` -> rust-analyzer 执行 clippy 检查。
- 命令语义对应：`cargo clippy --tests`（由 `check.command` + `check.extraArgs` 组合）。

2. Rust 格式化
- VS Code 调 rust-analyzer formatter -> 透传 `rustfmt --config imports_granularity=Item`。
- 与仓库统一命令保持一致：`just fmt` 最终也是 `cargo fmt -- --config imports_granularity=Item`（`justfile:24-25`）。

3. 启动/附加调试
- 触发 `Cargo launch` 时由 CodeLLDB 执行 `cargo build --bin=codex-tui`（工作目录 `codex-rs`）。
- 触发 `Attach` 时用 `${command:pickProcess}` 选取本机进程并附加。

### C. 仓库内“被验证的行为”

虽然 `.vscode` 本身不是 Rust 代码，但仓库有两类测试覆盖其边界语义：

1. 文件搜索对 `.vscode` + `.gitignore` 白名单行为
- `codex-rs/file-search` 测试验证：
  - `settings.json` 可被白名单放行。
  - `extensions.json` 在规则下可被忽略。
- 证据：`codex-rs/file-search/src/lib.rs:1030-1174`。

2. Git ghost commit 恢复时保留忽略目录 `.vscode`
- `codex-rs/utils/git` 测试验证恢复操作不误删已忽略 `.vscode/settings.json`。
- 证据：`codex-rs/utils/git/src/ghost_commits.rs:1544-1667`。

这两类测试共同说明：`.vscode` 在仓库工具链里被视作“可能被忽略但对开发体验重要的目录”。

## 关键代码路径与文件引用

### 目录内（直接对象）

- `.vscode/extensions.json:1-11`
- `.vscode/launch.json:1-22`
- `.vscode/settings.json:1-19`

### 上下文调用方（谁消费 `.vscode`）

- VS Code 本体：自动加载工作区 `.vscode/*.json`。
- rust-analyzer 扩展：消费 `rust-analyzer.*` 与 `[rust]` 项。
- Even Better TOML 扩展：消费 `[toml]` 与 `evenBetterToml.*` 项。
- CodeLLDB 扩展：消费 `launch.json` 的 `lldb` 配置。
- devcontainer 的 VS Code 自定义：并行声明了部分相同扩展（`.devcontainer/devcontainer.json:20-26`）。

### 被调用方（`.vscode` 触发到哪里）

- `cargo build --bin=codex-tui`（`.vscode/launch.json:10`，`codex-rs/tui/Cargo.toml:6-9`）。
- `cargo clippy --tests` 语义（`.vscode/settings.json:2-4`，与 `justfile:30-34`、`AGENTS.md` 测试建议一致）。
- `rustfmt --config imports_granularity=Item` 语义（`.vscode/settings.json:5`，`.github/workflows/rust-ci.yml:74`）。

### 文档/脚本/研究流程关联

- `.ops/research_guard.sh` 定义 DIR 研究文档命名和 checklist 行号勾选逻辑（`.ops/research_guard.sh:192-230`）。
- `Docs/researches/blueprint_checklist.md:31` 是本次对象对应的 checklist 项。
- `bash .ops/generate_daily_research_todo.sh` 会基于 checklist 生成每日 todo（`.ops/generate_daily_research_todo.sh:1-42`）。

## 依赖与外部交互

### 本地工具依赖

- Rust toolchain：`cargo`、`clippy`、`rustfmt`。
- VS Code 扩展：
  - `rust-lang.rust-analyzer`
  - `tamasfe.even-better-toml`
  - `vadimcn.vscode-lldb`

### 外部系统交互

- VS Code Marketplace（安装推荐扩展时）。
- LLDB 调试器（本机进程附加）。
- 本地进程枚举接口（`pickProcess` 依赖）。

### 与仓库其他配置的耦合

- 与 `.devcontainer/devcontainer.json` 中扩展推荐有重复，存在漂移风险（`.devcontainer/devcontainer.json:20-26`）。
- 与 `.gitignore` 的 `.vscode/` 忽略规则存在“跟踪文件 + 忽略目录”混合策略（`.gitignore:19-23`）。
- 与 Rust CI/justfile 的格式参数需保持同步（`imports_granularity=Item`）。

## 风险、边界与改进建议

### 风险

1. 配置漂移风险
- `.vscode/settings.json`、`justfile`、CI（`rust-ci.yml`）的参数若不一致，会导致“IDE 通过但 CI 失败”或反之。

2. 调试配置语义误解
- `Cargo launch` 当前仅 `build` 不 `run`，新贡献者可能误以为会直接启动 `codex-tui`。

3. `.gitignore` 与已跟踪文件并存带来的认知成本
- 新增 `.vscode/*` 文件默认被忽略，团队容易误以为“所有 `.vscode` 内容都会共享”。

4. 缺少自动校验
- 仓库没有专门校验 `.vscode/*.json` 的 CI 任务；JSONC 语法错误可能在 IDE 外难以及时发现。

### 边界

1. `.vscode` 仅影响 VS Code 使用者，对 JetBrains/Zed/Neovim 用户不直接生效。
2. 该目录不是业务逻辑，不参与产线运行时；价值集中在开发效率与一致性。
3. 实际执行效果依赖本机已安装对应扩展与调试工具链。

### 改进建议

1. 在 `docs/install.md` 或 `docs/contributing.md` 增加一段“VS Code 开发基线”说明，明确这三文件的作用与推荐插件。
2. 为 `launch.json` 增加一个显式 `run` 配置（例如 `cargo run --bin codex` 或 `codex-tui`），降低调试入口理解成本。
3. 把 `.devcontainer/devcontainer.json` 与 `.vscode/extensions.json` 的扩展列表做注释对齐，减少重复维护漂移。
4. 在研究/维护脚本中加入轻量 JSONC lint（可选），在提交前早发现配置语法问题。
