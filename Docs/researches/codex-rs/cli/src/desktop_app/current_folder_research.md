# codex-rs/cli/src/desktop_app 研究

## 场景与职责

`codex-rs/cli/src/desktop_app` 是 `codex app` 子命令在 macOS 上的实现目录，职责是把“打开 Codex Desktop”变成可执行的本机流程：

1. 如果本机已安装 `Codex.app`，直接拉起并打开指定工作区。
2. 如果未安装，自动下载 DMG、挂载、拷贝 `.app` 到 Applications 目录，再启动。

它不承担 CLI 参数解析、不承担跨平台分发决策，只承担“macOS Desktop App 的发现、安装、启动”。

上游入口链路：

- `MultitoolCli::Subcommand::App`（仅 macOS 编译）
- `app_cmd::run_app`
- `desktop_app::run_app_open_or_install`
- `desktop_app::mac::run_mac_app_open_or_install`

核心定位是“面向最终用户的一键体验兜底”：用户执行 `codex app` 时，不必先手动安装桌面端。

## 功能点目的

### 1. 子命令暴露与平台门控

- `main.rs` 中 `App(app_cmd::AppCommand)` 使用 `#[cfg(target_os = "macos")]` 门控，只在 macOS 编译并出现在 CLI 帮助里。
- 运行分发时，`Some(Subcommand::App(app_cli))` 分支先执行 `reject_remote_mode_for_subcommand(..., "app")`，禁止 `--remote` 与该命令组合，确保其只在本机执行。

目的：避免把桌面启动逻辑暴露到不支持的平台/模式。

### 2. 工作区路径接入

- `AppCommand` 的 `path` 默认值是 `.`，执行时先 `canonicalize`，失败时退回原始输入路径。

目的：尽可能把规范化路径传给桌面端，同时对不存在路径/权限问题保持容错，不提前硬失败。

### 3. 已安装优先

- 优先检查 `/Applications/Codex.app` 和 `$HOME/Applications/Codex.app`。
- 找到即调用 `open -a <app> <workspace>`。

目的：减少不必要下载，优先走最短路径。

### 4. 自动安装兜底

未找到已安装应用时：

1. 创建临时目录（`tempfile`）。
2. `curl -fL --retry 3 --retry-delay 1 -o Codex.dmg <url>` 下载安装包。
3. `hdiutil attach -nobrowse -readonly <dmg>` 挂载。
4. 在挂载点找 `Codex.app`（先固定名，再扫描任意 `.app`）。
5. 按顺序尝试安装到 `/Applications` 与 `$HOME/Applications`：
   - 若目的路径已存在目录，直接视为成功。
   - 否则用 `ditto <src.app> <dest.app>` 拷贝。
6. 无论安装成功与否，都尝试 `hdiutil detach <mount_point>`（detach 失败仅 warning，不覆盖主错误）。

目的：把安装流程做到“自动化+可回收+尽量不阻断主错误语义”。

### 5. 挂载点解析稳健性

- 对 `hdiutil attach` 输出支持两类解析：
  - tab 分隔行（取最后一列）
  - 含空格路径时的空白分词回退（匹配 `/Volumes/...`）
- 现有单测覆盖上述两种样例。

目的：兼容不同卷名格式（如 `Codex Installer`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 关键流程

#### A. 启动流程（主入口）

`run_mac_app_open_or_install(workspace, download_url)`：

1. 调用 `find_existing_codex_app_path()`。
2. 命中：打印提示并 `open_codex_app`。
3. 未命中：执行下载+安装流程，返回安装后的 `PathBuf`。
4. 再次 `open_codex_app` 打开工作区。

错误处理策略：

- 关键步骤使用 `anyhow::Context` 补充上下文。
- 外部命令 exit code 非 0 时 `bail!`，错误直接上抛。

#### B. 下载-挂载-安装流程

`download_and_install_codex_to_user_applications(dmg_url)`：

- 通过 `_temp_dir` 保持临时目录生命周期，避免中途被清理。
- 采用“先主操作、后 detach”的结构：
  - `result = {find app + install}`
  - `detach_result = detach_dmg(...)`
  - 返回 `result`，detach 失败只做 stderr 警告。

这是一个典型的“清理失败不吞主错误”模式。

### 关键数据结构

- 主要使用 `PathBuf`/`Path` 作为路径载体。
- `Option<PathBuf>`：用于“是否已安装”探测。
- `Vec<PathBuf>`：候选安装位置（系统/用户目录）与候选现有应用路径。

目录没有引入复杂状态机或结构体，逻辑由一组私有函数串联。

### 协议/命令交互

该目录不涉及网络 API 协议建模（无 JSON-RPC/HTTP 客户端库），而是通过系统命令完成集成：

- 下载：`curl -fL --retry 3 --retry-delay 1 -o <dest> <url>`
- 挂载：`hdiutil attach -nobrowse -readonly <dmg>`
- 卸载：`hdiutil detach <mount>`
- 安装复制：`ditto <src.app> <dest.app>`
- 启动：`open -a <app> <workspace>`

命令调用统一使用 `tokio::process::Command` 异步执行。

## 关键代码路径与文件引用

### 入口与分发

- `codex-rs/cli/src/main.rs:37-40`：`app_cmd`、`desktop_app` 模块仅在 macOS 编译。
- `codex-rs/cli/src/main.rs:111-113`：`Subcommand::App` 定义。
- `codex-rs/cli/src/main.rs:684-688`：`codex app` 分支执行 remote 检查并调用 `app_cmd::run_app`。
- `codex-rs/cli/src/main.rs:1032-1038`：`reject_remote_mode_for_subcommand`。

### 命令参数与桥接

- `codex-rs/cli/src/app_cmd.rs:4`：默认 DMG 下载 URL。
- `codex-rs/cli/src/app_cmd.rs:7-15`：`AppCommand`（`path` + `--download-url`）。
- `codex-rs/cli/src/app_cmd.rs:17-20`：路径规范化后进入 `desktop_app`。
- `codex-rs/cli/src/desktop_app/mod.rs:1-10`：平台实现转发到 `mac.rs`。

### macOS 实现细节

- `codex-rs/cli/src/desktop_app/mac.rs:7-29`：总流程入口。
- `codex-rs/cli/src/desktop_app/mac.rs:31-43`：已安装应用探测。
- `codex-rs/cli/src/desktop_app/mac.rs:45-67`：`open -a` 启动。
- `codex-rs/cli/src/desktop_app/mac.rs:69-101`：下载并安装的顶层编排（含 detach 兜底）。
- `codex-rs/cli/src/desktop_app/mac.rs:104-134`：安装目标目录轮询与复制。
- `codex-rs/cli/src/desktop_app/mac.rs:142-160`：下载命令。
- `codex-rs/cli/src/desktop_app/mac.rs:163-185`：挂载与挂载点解析。
- `codex-rs/cli/src/desktop_app/mac.rs:187-199`：卸载。
- `codex-rs/cli/src/desktop_app/mac.rs:201-224`：挂载卷内 `.app` 发现。
- `codex-rs/cli/src/desktop_app/mac.rs:226-237`：`ditto` 复制。
- `codex-rs/cli/src/desktop_app/mac.rs:245-281`：`hdiutil` 输出解析与测试。

### 文档与契约

- `README.md:8`：公开文档承诺用户可直接执行 `codex app` 获取桌面体验。

## 依赖与外部交互

### Rust 依赖（crate）

来自 `codex-rs/cli/Cargo.toml`：

- `anyhow`：错误上下文与快速失败。
- `tokio`（含 `process` 特性）：异步子进程执行。
- `tempfile`：临时目录管理。
- `clap`：`AppCommand` 参数解析。
- `pretty_assertions`（dev）：测试断言。

### OS / 环境依赖

- 环境变量：`HOME`（用于 `$HOME/Applications` 推导）。
- 系统命令：`open`、`curl`、`hdiutil`、`ditto`。
- 系统路径：`/Applications`、`$HOME/Applications`、`/Volumes/*`。

### 调用方 / 被调用方

- 调用方：CLI 主分发（`main.rs`）和 `app_cmd`。
- 被调用方：macOS 命令行工具链（见上）。
- 无内部跨 crate 回调，无协议层 RPC。

### 测试与脚本现状

- 目录内测试仅覆盖 `parse_hdiutil_attach_mount_point`（2 个单测）。
- `codex-rs/cli/tests` 目前未覆盖 `codex app` 行为。
- 仓库脚本（`.ops/*`）与该目录运行时逻辑无直接耦合，仅影响研究流程文档产出。

## 风险、边界与改进建议

### 风险与边界

1. 平台边界明确但单一：只支持 macOS 编译；Linux/Windows 无等价实现。
2. 外部命令可用性风险：依赖 `curl/hdiutil/ditto/open`，缺失或行为变化会直接失败。
3. 已安装探测过于“目录存在”导向：`dest_app.is_dir()` 即判成功，未校验 bundle 完整性。
4. 安装并发风险：多个 `codex app` 并发执行时，可能在同一目标目录上竞争复制。
5. 可观测性有限：主要依赖 `eprintln!`，缺少结构化日志字段（阶段、耗时、命令 stderr 分类）。
6. 测试覆盖不足：缺少下载失败、挂载失败、复制失败、detach 失败、`HOME` 缺失等关键路径测试。
7. 安全边界：`--download-url` 可任意覆盖，适合高级用户调试，但也扩大了供应链输入面。

### 改进建议（按优先级）

1. 增加可测试抽象层：把命令执行封装为 trait，允许在单测中注入 fake runner，覆盖完整安装状态机。
2. 增加集成测试最小集合：
   - 已安装直接打开
   - 下载失败
   - attach 成功但未找到 `.app`
   - `/Applications` 失败后回退 `$HOME/Applications`
   - detach 失败不覆盖主错误
3. 提升完整性校验：对已存在 `Codex.app` 增加最小可执行性检查（例如主可执行文件是否存在）。
4. 改善并发安全：在目标安装路径增加文件锁或原子目录切换策略，降低并发写冲突概率。
5. 加强下载来源约束：默认 URL 维持不变，同时可考虑加入可选签名/校验摘要机制。
6. 文档补充：在 `docs/` 下加入 `codex app` 的行为说明（依赖命令、失败排查、`--download-url` 用途与风险）。
