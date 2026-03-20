# DIR `codex-rs/artifacts` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/artifacts`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- crate：`codex-artifacts`（lib: `codex_artifacts`）

## 场景与职责

`codex-rs/artifacts` 是 Codex 在 Rust 侧提供的“Artifact JS 执行基础设施层”，核心职责不是实现 PPT/表格编辑逻辑本身，而是为上层工具调用提供稳定运行环境：

1. 解析并管理 artifact runtime 的发布地址、缓存路径和安装状态（可下载、可校验、可复用缓存）。
2. 校验本地已安装 runtime 的合法性（`package.json` 包名、导出入口、入口文件存在性）。
3. 选择可执行 JavaScript 运行时（Node / Electron / Codex Desktop App 内置 Electron）。
4. 将上层传入的自由 JavaScript 源码包装后执行，并返回标准化的 `exit_code/stdout/stderr`。

在系统分层里，它位于：
- 上游调用：`codex-rs/core/src/tools/handlers/artifacts.rs`（工具 handler）
- 下游依赖：`codex-rs/package-manager`（下载、校验、解压、安装原子切换）

该 crate 的 README 对定位描述与代码实现一致（`codex-rs/artifacts/README.md`）。

## 功能点目的

1. Runtime 定位与下载（`ArtifactRuntimeManager`）
- 目的：在执行 artifacts 工具前，确保与当前版本兼容的 `@oai/artifact-tool` runtime 可用。
- 默认下载基址为 GitHub Releases：`https://github.com/openai/codex/releases/download/`（`codex-rs/artifacts/src/runtime/manager.rs:23`）。
- 默认 tag 前缀：`artifact-runtime-v`（`codex-rs/artifacts/src/runtime/manager.rs:17`）。

2. 本地缓存加载（`load_cached_runtime`）
- 目的：优先复用 `codex_home/packages/artifacts/<version>/<platform>`，避免重复下载。
- 直接用于 core 测试验证固定缓存路径契约（`codex-rs/core/src/tools/handlers/artifacts_tests.rs:45`）。

3. JS Runtime 可用性探测
- 目的：判断机器是否具备执行 artifacts JS 的能力。
- 策略：优先系统 `node`，其次系统 `electron`，再尝试 Codex Desktop 安装路径候选（`codex-rs/artifacts/src/runtime/js_runtime.rs:83`）。

4. JS 代码执行（`ArtifactsClient::execute_build`）
- 目的：将上层自由文本 JS 与 runtime 入口拼接执行，隔离 stdout/stderr，输出统一结构。
- 默认超时 30s（`codex-rs/artifacts/src/client.rs:16`），支持请求级覆盖。

5. Core 工具接入
- 目的：把模型工具调用（freeform JS）转成 artifacts crate 可执行输入。
- 在 `core` 中由 `Feature::Artifact` + 平台能力双重门控决定是否暴露工具（`codex-rs/core/src/tools/spec.rs:336`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 端到端关键流程

1. 模型触发 `artifacts` 工具（freeform）。
- ToolSpec 在 `create_artifacts_tool()` 定义 grammar 与描述（`codex-rs/core/src/tools/spec.rs:2069`）。
- 仅当 `config.artifact_tools` 为 true 时注册 handler（`codex-rs/core/src/tools/spec.rs:2922`）。

2. Handler 解析输入与 pragma。
- `parse_freeform_args` 支持首行 `// codex-artifact-tool: timeout_ms=...`（`codex-rs/core/src/tools/handlers/artifacts.rs:123`）。
- 拒绝 JSON 包裹、字符串包裹、markdown fence（`codex-rs/core/src/tools/handlers/artifacts.rs:190`）。

3. 构造 runtime manager。
- `default_runtime_manager` 使用 `versions::ARTIFACT_RUNTIME`（当前 `2.5.6`）和默认 release 基址（`codex-rs/core/src/tools/handlers/artifacts.rs:214`, `codex-rs/core/src/packages/versions.rs:2`）。

4. 确保 runtime 安装。
- `ArtifactsClient` 在 `execute_build` 前调用 `resolve_runtime()`，managed 模式下进入 `manager.ensure_installed()`（`codex-rs/artifacts/src/client.rs:47`）。
- 底层 `PackageManager::ensure_installed()`：
  - 缓存快路径
  - 文件锁防并发安装
  - 拉取 manifest 与 archive
  - 校验 size + sha256
  - 安全解压
  - staging -> 原子提升 -> 最终路径复校验
  （`codex-rs/package-manager/src/manager.rs:55`）

5. 运行 JS。
- 构建临时脚本 `artifact-build.mjs`，先 `import(file://<runtime entrypoint>)`，再将导出拷贝到 `globalThis`，最后拼接用户源码（`codex-rs/artifacts/src/client.rs:141`）。
- spawn Node/Electron；若 Electron 则设置 `ELECTRON_RUN_AS_NODE=1`（`codex-rs/artifacts/src/client.rs:75`）。
- 读取 stdout/stderr、等待退出或超时 kill（`codex-rs/artifacts/src/client.rs:165`）。

### 2) 关键数据结构

1. `ArtifactRuntimeReleaseLocator`
- 字段：`base_url/runtime_version/release_tag_prefix`。
- 作用：生成 `manifest_url` 与 release tag 文件名。
- 位置：`codex-rs/artifacts/src/runtime/manager.rs:27`。

2. `ArtifactRuntimeManagerConfig`
- 封装 package-manager 配置 + release locator。
- 支持 `with_cache_root` 覆盖缓存根目录。
- 位置：`codex-rs/artifacts/src/runtime/manager.rs:93`。

3. `ReleaseManifest`
- 字段：`schema_version/runtime_version/release_tag/node_version/platforms`。
- `platforms` 的 value 是 `PackageReleaseArchive`（含 `archive/sha256/format/size_bytes`）。
- 位置：`codex-rs/artifacts/src/runtime/manifest.rs:8`。

4. `InstalledArtifactRuntime`
- 字段：`root_dir/runtime_version/platform/build_js_path`。
- 作用：作为“通过校验的已安装 runtime”对象返回给执行层。
- 位置：`codex-rs/artifacts/src/runtime/installed.rs:36`。

5. `ArtifactBuildRequest` / `ArtifactCommandOutput`
- 入参：`source/cwd/timeout/env`。
- 出参：`exit_code/stdout/stderr` + `success()`。
- 位置：`codex-rs/artifacts/src/client.rs:104`, `codex-rs/artifacts/src/client.rs:113`。

### 3) 协议与命令约定

1. Release URL 约定
- manifest：`<base>/<tag>/<tag>-manifest.json`
- archive：`<base>/<tag>/<archive_name>`
- 构建逻辑：`manifest_url()` 和 `archive_url()`（`codex-rs/artifacts/src/runtime/manager.rs:70`, `codex-rs/artifacts/src/runtime/manager.rs:207`）。

2. Runtime 包结构约定
- 包名必须是 `@oai/artifact-tool`。
- `package.json` 里 `exports["."]` 必须指向 JS 入口。
- 入口路径必须是相对路径且不可越界（禁止绝对路径、`..` 等）。
- 校验逻辑：`load_package_metadata` + `resolve_relative_runtime_path`（`codex-rs/artifacts/src/runtime/installed.rs:217`, `codex-rs/artifacts/src/runtime/installed.rs:126`）。

3. Freeform 输入约定（core -> artifacts）
- 输入必须是原始 JS 文本，允许首行 pragma。
- 支持键：`timeout_ms`。
- 无 JSON schema，使用 grammar + 运行时检查共同约束。
- 位置：`codex-rs/core/src/tools/spec.rs:2069`, `codex-rs/core/src/tools/handlers/artifacts.rs:123`。

### 4) 关键命令与执行行为

1. runtime 下载：`reqwest` GET manifest + archive（`codex-rs/package-manager/src/manager.rs:327`）。
2. archive 验证：size + sha256（`codex-rs/package-manager/src/archive.rs:70`, `codex-rs/package-manager/src/archive.rs:83`）。
3. archive 解压：支持 `zip`/`tar.gz`，限制危险 entry 类型与路径逃逸（`codex-rs/package-manager/src/archive.rs:93`）。
4. JS 执行命令：`<node_or_electron> <tmp>/artifact-build.mjs`（`codex-rs/artifacts/src/client.rs:73`）。

## 关键代码路径与文件引用

### A. 本目录核心实现

1. `codex-rs/artifacts/src/client.rs`
- 执行入口：`ArtifactsClient::execute_build`（`:47`）
- 包装脚本拼接：`build_wrapped_script`（`:141`）
- 子进程超时与输出采集：`run_command`（`:165`）

2. `codex-rs/artifacts/src/runtime/manager.rs`
- release 定位器与 URL 组装（`:27`, `:70`）
- manager 对 package-manager 的适配（`:137`）
- `ManagedPackage` 实现（`:190`）

3. `codex-rs/artifacts/src/runtime/installed.rs`
- 缓存加载入口：`load_cached_runtime`（`:16`）
- runtime 目录/元数据校验：`load`（`:61`）
- 包元数据解析：`load_package_metadata`（`:217`）

4. `codex-rs/artifacts/src/runtime/js_runtime.rs`
- 可用性判断：`is_js_runtime_available`（`:58`）
- 平台能力判断：`can_manage_artifact_runtime`（`:71`）
- Node/Electron/Codex App 候选合并（`:83`）

5. `codex-rs/artifacts/src/tests.rs`
- URL 生成、缓存加载、zip/tar.gz 下载安装、执行行为等回归测试（`codex-rs/artifacts/src/tests.rs:35` 起）。

### B. 上游调用方（直接依赖该目录行为）

1. `codex-rs/core/src/tools/handlers/artifacts.rs`
- Tool handler 主流程、输入校验、输出格式化、事件上报（`:34`, `:123`, `:214`）。

2. `codex-rs/core/src/tools/spec.rs`
- tool 暴露条件（feature + 平台能力）与 grammar 描述（`:336`, `:2069`, `:2922`）。

3. `codex-rs/core/src/packages/versions.rs`
- 固定 runtime 版本常量（`:2`）。

### C. 下游被调用方（该目录向外调用）

1. `codex-rs/package-manager/src/manager.rs`
- 安装主流程、并发锁、staging/promote/recover（`:55`）。

2. `codex-rs/package-manager/src/archive.rs`
- checksum/size 校验、安全解压（`:70`, `:83`, `:93`）。

3. `codex-rs/package-manager/src/platform.rs`
- 平台识别与标准化平台字符串（`:16`, `:37`）。

### D. 配置、测试、文档、脚本上下文

1. 配置
- feature gate：`Feature::Artifact`（`codex-rs/core/src/features.rs:809`）。
- runtime pin：`ARTIFACT_RUNTIME = "2.5.6"`（`codex-rs/core/src/packages/versions.rs:2`）。
- cache root 默认：`packages/artifacts`（`codex-rs/artifacts/src/runtime/manager.rs:20`）。

2. 测试
- crate 级测试：`codex-rs/artifacts/src/tests.rs`（含 wiremock 下载流程）。
- core 接入测试：`codex-rs/core/src/tools/handlers/artifacts_tests.rs`、`codex-rs/core/src/tools/spec_tests.rs:615`。

3. 文档
- crate README：`codex-rs/artifacts/README.md`。
- 工具行为文案：`codex-rs/core/src/tools/spec.rs` 中 `create_artifacts_tool()` 描述。

4. 脚本
- 未发现该目录专属发布/维护脚本；安装与执行流程由 Rust 代码内建。

## 依赖与外部交互

### 1) crate 依赖关系

来自 `codex-rs/artifacts/Cargo.toml`：

1. 内部依赖：`codex-package-manager`。
2. 网络与序列化：`reqwest`、`serde`、`serde_json`、`url`。
3. 执行与异步：`tokio`、`tempfile`。
4. 本机运行时发现：`which`。
5. 错误建模：`thiserror`。

### 2) 外部交互面

1. 网络交互
- 访问 release manifest 与压缩包 URL（通常指向 GitHub Releases）。

2. 文件系统交互
- 读写 `codex_home/packages/artifacts/...`。
- 写 staging 临时目录和运行脚本临时文件。
- 目录重命名/回滚用于安装原子性。

3. 进程交互
- spawn Node/Electron 子进程执行 JS。
- 读取 stdout/stderr，超时 kill。

4. 环境交互
- runtime 探测读取 `PATH`、`HOME`、`LOCALAPPDATA`、`ProgramFiles` 等。
- Electron 执行时注入 `ELECTRON_RUN_AS_NODE=1`。

### 3) 安全与完整性约束

1. 包完整性：size + SHA256 双校验。
2. 解压安全：防路径逃逸、拒绝 symlink/hardlink 等危险 tar entry。
3. 包内容合法性：限制包名和导出入口。
4. 路径安全：导出入口必须是 runtime 根目录内相对路径。

## 风险、边界与改进建议

### 风险

1. 超时语义较粗
- 默认 30s 固定值，复杂生成任务可能频繁超时；当前仅支持调用级 `timeout_ms`，缺少按场景动态策略。

2. 输出聚合内存风险
- `run_command` 读到内存后一次性返回，面对超大 stdout/stderr 时可能增加内存压力。

3. 可观测性不足
- runtime 解析失败时，错误可读但缺少结构化 telemetry（例如“失败于下载/校验/解压/入口校验哪一步”统计维度）。

4. 运行时来源不透明
- Node/Electron/Codex App 候选命中路径当前不直接暴露给上层，排障时要靠日志或复现环境。

### 边界

1. 该 crate 只负责 runtime 管理与 JS 执行，不负责 artifact API 业务语义。
2. 工具是否对模型可见由 `core` feature 与平台能力共同决定，不由本 crate 单独决定。
3. 当前测试在 `artifacts` crate 层 `#[cfg(all(test, not(windows)))]`，Windows 侧行为覆盖相对弱。

### 改进建议

1. 增强执行可观测性
- 在 `ArtifactCommandOutput` 或事件层增加 runtime 解析来源（node/electron/app bundle）与入口路径摘要。

2. 增加流式输出能力
- 对长输出场景引入分段读取/上报，降低内存峰值并改善用户反馈时延。

3. 补齐 Windows 覆盖
- 增加针对 Windows 平台 runtime 候选路径与执行路径的专门测试矩阵。

4. 配置化 runtime pin（谨慎）
- 在保持默认 pin 的前提下，考虑允许受控 override（仅开发/实验环境），降低紧急修复发布时的耦合成本。
