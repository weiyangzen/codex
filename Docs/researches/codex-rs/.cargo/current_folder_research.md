# DIR `codex-rs/.cargo` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/.cargo`
- 目标类型：`DIR`
- 研究日期：2026-03-19
- 目录文件清单：
  - `codex-rs/.cargo/config.toml`
  - `codex-rs/.cargo/audit.toml`

## 场景与职责

`codex-rs/.cargo` 是 Rust 工作区级的构建与安全审计补充配置目录，职责非常聚焦：

1. 为 Windows 目标统一注入链接参数（主线程栈大小、ARM64 特定 linker 参数），降低跨工具链（MSVC/GNU）构建时的行为漂移。
2. 为 `cargo-audit` 提供 advisory 忽略列表，避免已知“上游无修复/暂不可升级”的告警在日常审计中阻塞流水线。
3. 作为 `codex-rs` 工作区“运行目录约束”的一部分，被本仓库 `just` 和 CI 的 `working-directory: codex-rs` 约定隐式消费。

从边界看，这个目录不承载业务代码、不直接被 crate `use`，而是通过 Cargo/cargo-audit 的配置发现机制生效。

## 功能点目的

### 1) `config.toml`（构建链路）

目的：统一 Windows 目标的链接参数。

- 对 `cfg(all(windows, target_env = "msvc"))` 注入 `/STACK:8388608`（8 MiB）以提高默认栈空间上限（`codex-rs/.cargo/config.toml:1-2`）。
- 对 `aarch64-pc-windows-msvc` 额外注入 `/arm64hazardfree`，并在注释中说明是为规避 LLVM 触发的 Cortex-A53 相关 warning（`codex-rs/.cargo/config.toml:4-8`）。
- 对 `cfg(all(windows, target_env = "gnu"))` 注入 GNU 链接器等价参数 `-Wl,--stack,8388608`（`codex-rs/.cargo/config.toml:10-11`）。

### 2) `audit.toml`（供应链审计链路）

目的：控制 `cargo audit` 的可接受风险集合。

- 通过 `[advisories].ignore` 忽略 3 个 RUSTSEC 条目（`RUSTSEC-2024-0388`、`RUSTSEC-2025-0057`、`RUSTSEC-2024-0436`），每项附带来源说明（`codex-rs/.cargo/audit.toml:1-6`）。
- 与 `cargo audit --deny warnings` 配合，减少“已知但暂不可修复”问题造成的持续红灯。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 关键流程

1. 本地开发命令进入 `codex-rs` 目录执行。根 `justfile` 全局设置 `working-directory := "codex-rs"`，后续 `cargo run/build/fmt/clippy/nextest` 都在该目录下触发（`justfile:1`, `justfile:10-47`）。
2. Cargo 在该工作目录解析 `.cargo/config.toml`，对匹配目标追加 `rustflags`（`codex-rs/.cargo/config.toml:1-11`）。
3. Windows 相关 CI（含 release）也以 `working-directory: codex-rs` 调用 `cargo build --target ...`，同样会吃到这些 target rustflags（`.github/workflows/rust-release-windows.yml:30-33`, `.github/workflows/rust-release-windows.yml:89-93`, `.github/workflows/rust-ci.yml:140-143`）。
4. 安全审计链路中，`cargo-audit` workflow 在 `codex-rs` 目录运行 `cargo audit --deny warnings`（`codex-rs/.github/workflows/cargo-audit.yml:15-17`, `codex-rs/.github/workflows/cargo-audit.yml:25-26`）；`audit.toml` 通过 cargo-audit 默认配置发现规则参与。

### 数据结构与配置协议

1. Cargo target 配置结构：
- TOML table key 使用 `target.'cfg(...)'` 与具体 triple（如 `target.aarch64-pc-windows-msvc`）。
- `rustflags` 为字符串数组，按 `-C link-arg=...` 形式透传给 rustc/linker（`codex-rs/.cargo/config.toml:1-11`）。

2. RustSec advisory 配置结构：
- `audit.toml` 使用 `[advisories].ignore = ["RUSTSEC-..."]`。
- advisory ID 采用 `RUSTSEC-YYYY-NNNN` 命名约定（`codex-rs/.cargo/audit.toml:1-6`）。

3. 对比配置（同域不同工具）：
- `cargo-deny` 使用的是 `codex-rs/deny.toml`，其 `[advisories].ignore` 为对象数组（含 `reason`），并且忽略项多于 `audit.toml`（`codex-rs/deny.toml:65-81`, `.github/workflows/cargo-deny.yml:22-26`）。

### 关键命令

- 本地开发入口：`just fmt` / `just fix` / `just test` / `cargo build`（`justfile:27-47`）。
- 安全审计：`cargo audit --deny warnings`（`codex-rs/.github/workflows/cargo-audit.yml:25-26`）。
- 依赖策略审计：`cargo-deny-action` + `manifest-path: ./codex-rs/Cargo.toml`（`.github/workflows/cargo-deny.yml:23-26`）。

## 关键代码路径与文件引用

### 目标目录（直接对象）

1. `codex-rs/.cargo/config.toml`
- Windows MSVC 栈参数：`/STACK:8388608`（第 1-2 行）。
- Windows ARM64 hazard 参数：`/arm64hazardfree`（第 4-8 行）。
- Windows GNU 栈参数：`-Wl,--stack,8388608`（第 10-11 行）。

2. `codex-rs/.cargo/audit.toml`
- Advisory 忽略清单（第 1-6 行）。

### 调用方（谁触发它）

1. 根 `justfile`：将绝大多数 Rust 命令固定在 `codex-rs` 目录执行，间接触发 `.cargo/config.toml`（`justfile:1`, `justfile:10-47`）。
2. `.github/workflows/rust-ci.yml`：多个 job 在 `working-directory: codex-rs` 运行 `cargo clippy`、`cargo nextest` 等（`.github/workflows/rust-ci.yml:67`, `.github/workflows/rust-ci.yml:142`, `.github/workflows/rust-ci.yml:436-437`, `.github/workflows/rust-ci.yml:507`, `.github/workflows/rust-ci.yml:645-647`）。
3. `.github/workflows/rust-release-windows.yml`：Windows 构建矩阵直接运行 `cargo build --target ...`（`.github/workflows/rust-release-windows.yml:32`, `.github/workflows/rust-release-windows.yml:41-49`, `.github/workflows/rust-release-windows.yml:89-93`）。
4. `codex-rs/.github/workflows/cargo-audit.yml`：在 `codex-rs` 内执行 `cargo audit --deny warnings`，间接触发 `.cargo/audit.toml`（`codex-rs/.github/workflows/cargo-audit.yml:17`, `codex-rs/.github/workflows/cargo-audit.yml:26`）。

### 相关上下文（同功能域配置/脚本/文档）

1. `codex-rs/deny.toml`：`cargo-deny` 的 advisory 策略（忽略项与 `audit.toml` 不完全一致）（`codex-rs/deny.toml:65-81`）。
2. `codex-rs/scripts/setup-windows.ps1`：构建前显式清空 `RUSTFLAGS`，避免外部约束污染本地 Windows 构建（`codex-rs/scripts/setup-windows.ps1:237-240`）。
3. `codex-rs/README.md`：强调在 `codex-rs` 顶层运行 workspace，以对齐共享配置与构建脚本（`codex-rs/README.md:95-102`）。
4. `.github/workflows/cargo-deny.yml`：当前主仓库活跃的供应链审计路径（`.github/workflows/cargo-deny.yml:1-26`）。

## 依赖与外部交互

### 内部依赖关系（调用方/被调用方）

1. 调用方：本地 `just` 命令、`rust-ci`/`rust-release-windows` 工作流、`cargo-audit` 工作流。
2. 被调用方：Cargo 配置系统（读取 `.cargo/config.toml`），cargo-audit（读取 `.cargo/audit.toml`），链接器（MSVC/GNU）执行具体 link-arg。
3. 同域协作：`cargo-deny` 读取 `deny.toml`，与 cargo-audit 共同形成供应链审计面，但配置文件分离。

### 外部交互

1. 与工具链交互：`rustc`/linker 参数透传到 `link.exe` 或 `ld`。
2. 与安全数据库交互：`cargo-audit`/`cargo-deny` 都会涉及 RustSec advisory 数据库同步（`codex-rs/deny.toml:67-69` 注释已体现 db-path/db-urls 语义）。
3. 与 CI 环境变量交互：
- musl job 使用 hermetic `CARGO_HOME` 并创建空 `config.toml`（用于隔离 runner 全局 Cargo 配置，非替代项目 `.cargo/config.toml`）（`.github/workflows/rust-ci.yml:250-259`）。
- musl job 清空多组 `RUSTFLAGS` 相关 env，防止 sanitizer 污染（`.github/workflows/rust-ci.yml:397-405`）。

### 测试与验证关系

1. 目标目录本身无 Rust 单元测试；其正确性主要依赖 CI 构建/测试流水线“间接验证”。
2. Windows 仅在 MSVC 目标矩阵中持续验证；`windows-gnu` 参数当前缺少 CI 覆盖（`.github/workflows/rust-ci.yml:533-541`, `.github/workflows/rust-release-windows.yml:40-49`）。

## 风险、边界与改进建议

### 风险

1. 双审计配置漂移风险：
- `audit.toml` 忽略 3 项；`deny.toml` 忽略 6 项，策略不一致可能导致两类工具输出分裂（`codex-rs/.cargo/audit.toml:1-6`, `codex-rs/deny.toml:72-81`）。

2. CI 覆盖盲区：
- `config.toml` 含 `windows-gnu` 分支，但当前工作流矩阵无 `*-pc-windows-gnu` 构建，存在“长期未执行配置”风险（`codex-rs/.cargo/config.toml:10-11`, `.github/workflows/rust-ci.yml:533-541`）。

3. 审计 workflow 可见性风险：
- `cargo-audit.yml` 位于 `codex-rs/.github/workflows/`（子目录），主仓库默认只执行根 `.github/workflows` 下工作流；如果没有额外接线，该审计可能并未在主 CI 中实际执行。

### 边界

1. `.cargo` 只负责 Cargo/cargo-audit 的工具链配置，不描述运行时 `~/.codex/config.toml` 等应用配置。
2. 目录内没有业务逻辑与协议代码，不直接参与 crate 编译单元。
3. 风险处置主要发生在上游依赖升级、CI 目标矩阵维护、以及安全策略文件统一上。

### 改进建议

1. 统一安全审计策略源：
- 评估将 `audit.toml` 与 `deny.toml` 的忽略项对齐，或明确“哪个工具是准入门禁”，避免同一 PR 在不同审计器得到冲突结论。

2. 补齐 `windows-gnu` 最小验证：
- 即便不常规发布，也建议增加轻量 compile-check（例如仅 build 关键二进制）确保该 target 配置不会失效。

3. 给 `.cargo` 增加维护说明文档：
- 在 `codex-rs/README.md` 或 `docs/install.md` 增加一段“工作区 Cargo 配置说明”（Windows link-arg 与 audit ignore 的维护规则、更新流程、移除条件）。

4. 明确 `cargo-audit` 工作流归属：
- 若该 workflow 需要持续生效，建议迁移到根 `.github/workflows/` 或在根 workflow 中显式复用；若不再使用，建议删除以免产生“存在但不执行”的误导。
