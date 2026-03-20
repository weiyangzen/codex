# DIR `codex-rs/artifacts/src` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/artifacts/src`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- crate：`codex-artifacts`（lib: `codex_artifacts`）

## 场景与职责

`codex-rs/artifacts/src` 是 Codex 在 Rust 侧对“本地 artifact JavaScript 运行能力”的核心实现层，处在“core 工具编排”与“package manager 安装机制”之间：

1. 向上承接 `core` 的 `artifacts` tool 调用，将 freeform JS 代码真正落地执行。
2. 向下依赖 `codex-package-manager` 完成 runtime 下载、校验、解压、缓存与并发安装互斥。
3. 封装运行时资产合法性检查（`package.json` 包名/导出入口/文件存在）与执行环境发现（Node/Electron/Codex Desktop）。

在系统中的职责边界是“runtime 管理 + 子进程执行”，不是实现 PPT/Spreadsheet API 本身。业务 API 来自被预加载的 `@oai/artifact-tool` JS 包。

与上下文关系：

- 调用方：`codex-rs/core/src/tools/handlers/artifacts.rs:82-101`（构造 `ArtifactsClient` 并调用 `execute_build`）。
- Tool 暴露门控：`codex-rs/core/src/tools/spec.rs:335-336`（`Feature::Artifact` + `can_manage_artifact_runtime()`）。
- 版本钉住：`codex-rs/core/src/packages/versions.rs:2`（当前 `2.5.6`）。
- 下游安装器：`codex-rs/package-manager/src/manager.rs:55-323`。

## 功能点目的

### 1) Runtime 发布定位与缓存安装

- 入口对象：`ArtifactRuntimeReleaseLocator`、`ArtifactRuntimeManagerConfig`、`ArtifactRuntimeManager`（`runtime/manager.rs`）。
- 目的：给定 runtime 版本，生成 manifest/archive URL，并在本地缓存目录中确保该版本 runtime 可用。
- 默认约定：
  - tag 前缀：`artifact-runtime-v`（`runtime/manager.rs:17`）
  - 缓存根相对路径：`packages/artifacts`（`runtime/manager.rs:20`）
  - 发布基址：`https://github.com/openai/codex/releases/download/`（`runtime/manager.rs:23`）

### 2) 本地已安装 runtime 的严格加载与校验

- 入口函数：`load_cached_runtime`（`runtime/installed.rs:16`）。
- 目的：无网络情况下读取并验证已安装 runtime，校验失败即视为不可用。
- 关键约束：
  - `package.json.name` 必须是 `@oai/artifact-tool`（`runtime/installed.rs:13,255-268`）。
  - `exports["."]` 必须存在并指向 JS 入口（`runtime/installed.rs:271-279`）。
  - 入口路径必须是相对路径且不能越界（`runtime/installed.rs:126-148`）。

### 3) JS 可执行环境探测

- 入口：`is_js_runtime_available` / `can_manage_artifact_runtime`（`runtime/js_runtime.rs:58,71`）。
- 目的：分别回答两个问题：
  - 机器上当前是否能“执行 JS”（含缓存命中+Node/Electron 回退）
  - 当前平台是否支持“托管 runtime 安装流程”（仅平台能力检查）
- 候选顺序：Node -> Electron -> Codex Desktop App 内置 Electron（`runtime/js_runtime.rs:75-114`）。

### 4) JS 执行与输出捕获

- 入口：`ArtifactsClient::execute_build`（`client.rs:47-91`）。
- 目的：将 runtime entrypoint 与用户 JS 拼接为临时脚本，按请求 cwd/timeout/env 执行，返回结构化 `exit_code/stdout/stderr`。
- 关键机制：
  - 生成 staging 脚本 `artifact-build.mjs`（`client.rs:57`）。
  - 预加载 runtime 并把命名导出复制到 `globalThis`（`client.rs:141-163`）。
  - 采用 tokio 异步管道读取 stdout/stderr，超时后 kill 子进程（`client.rs:165-226`）。

### 5) 对 core tool 的可集成 API

- `lib.rs` 统一 re-export（`lib.rs:6-24`），让 `core` 只依赖稳定公共类型（`ArtifactBuildRequest`、`ArtifactsClient`、`ArtifactRuntimeManager` 等）。
- 支持两种 client 模式：
  - `from_runtime_manager`：懒安装/懒解析。
  - `from_installed_runtime`：对测试或预置 runtime 场景做固定绑定（`client.rs:31-45`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 关键流程（端到端）

1. `core` 注册 `artifacts` freeform tool（`core/src/tools/spec.rs:2069-2092,2925-2929`）。
2. `ArtifactsHandler` 验证 feature 与输入格式（支持首行 pragma `// codex-artifact-tool: timeout_ms=...`），并拒绝 JSON/字符串/fence（`core/src/tools/handlers/artifacts.rs:67-203`）。
3. handler 使用 `versions::ARTIFACT_RUNTIME` 构建默认 manager（`core/src/tools/handlers/artifacts.rs:214-218` + `core/src/packages/versions.rs:2`）。
4. `ArtifactsClient::execute_build` 中，先 `resolve_runtime()`：
   - managed 模式调用 `manager.ensure_installed()`。
   - pinned 模式直接用传入 `InstalledArtifactRuntime`（`client.rs:94-100`）。
5. `ArtifactRuntimeManager` 内部委托 `PackageManager::ensure_installed()`（`runtime/manager.rs:174-175`）。
6. 包管理流程包括：manifest 下载、平台归档选择、size/sha256 校验、安全解压、staging 提升与回滚（`package-manager/src/manager.rs:55-323`）。
7. runtime 验证通过后，client 生成包装脚本并启动 Node/Electron 执行（`client.rs:69-91,141-163`）。
8. 输出统一为 `ArtifactCommandOutput`，`core` 再格式化为用户可见文本（`core/src/tools/handlers/artifacts.rs:263-283`）。

### B. 关键数据结构

1. `ArtifactBuildRequest`（`client.rs:104-109`）
- `source`: JS 源码
- `cwd`: 执行目录
- `timeout`: 可选超时
- `env`: 额外环境变量

2. `ArtifactCommandOutput`（`client.rs:113-123`）
- `exit_code/stdout/stderr`
- `success()` 用 `exit_code == Some(0)` 判定

3. `ArtifactRuntimeReleaseLocator`（`runtime/manager.rs:27-88`）
- 描述版本发布位置，负责生成 `manifest_url`/`release_tag`/`manifest_file_name`

4. `ArtifactRuntimeManagerConfig`（`runtime/manager.rs:93-132`）
- 组合 package-manager config 与 release 定位器
- `with_cache_root` 支持缓存重定向

5. `InstalledArtifactRuntime`（`runtime/installed.rs:37-124`）
- 校验通过后的运行时对象，包含 `root_dir/runtime_version/platform/build_js_path`
- 提供 `resolve_js_runtime()` 决策实际可执行文件

6. `ReleaseManifest`（`runtime/manifest.rs:8-15`）
- `schema_version/runtime_version/release_tag/node_version/platforms`
- `platforms` 值类型是 `PackageReleaseArchive`

### C. 协议与约定

1. 发布资产 URL 约定（`runtime/manager.rs:70-76,207-216`）
- manifest：`<base>/<release_tag>/<release_tag>-manifest.json`
- archive：`<base>/<release_tag>/<archive_name>`

2. runtime 包结构约定（`runtime/installed.rs:217-279`）
- package 名固定 `@oai/artifact-tool`
- `exports["."]` 指向入口
- 入口路径必须是 runtime 根目录下安全相对路径

3. freeform JS 输入约定（调用方语义）
- grammar：`core/src/tools/spec.rs:2070-2083`
- pragma 支持键：仅 `timeout_ms`
- reject 规则：禁止 JSON 外壳、字符串外壳、markdown code fence（`core/src/tools/handlers/artifacts.rs:190-203`）

### D. 关键命令与进程行为

1. 下载：`reqwest` GET manifest + archive（`package-manager/src/manager.rs:326-381`）。
2. 校验：`verify_archive_size`、`verify_sha256`（`package-manager/src/manager.rs:154-155`，实现见 `archive.rs:74-96`）。
3. 解压：支持 `zip`/`tar.gz`，并阻止路径逃逸与危险 tar entry（`archive.rs:99-267`）。
4. 执行：`<node_or_electron> <temp>/artifact-build.mjs`；Electron 场景注入 `ELECTRON_RUN_AS_NODE=1`（`client.rs:73-81`）。

## 关键代码路径与文件引用

### 目录内（`codex-rs/artifacts/src`）

- `codex-rs/artifacts/src/lib.rs:1-24`
  - 对外 API 汇总导出。
- `codex-rs/artifacts/src/client.rs:16-226`
  - `ArtifactsClient`、脚本包装、进程执行、超时终止、输出收集。
- `codex-rs/artifacts/src/runtime/manager.rs:17-254`
  - release 定位器、manager 配置、`ManagedPackage` 适配。
- `codex-rs/artifacts/src/runtime/installed.rs:13-284`
  - runtime 加载与 package metadata 校验、路径安全检查。
- `codex-rs/artifacts/src/runtime/js_runtime.rs:10-168`
  - JS runtime 候选发现与平台能力判定。
- `codex-rs/artifacts/src/runtime/error.rs:1-27`
  - runtime 层错误类型。
- `codex-rs/artifacts/src/runtime/manifest.rs:1-15`
  - release manifest 数据模型。
- `codex-rs/artifacts/src/tests.rs:35-470`
  - URL 组装、缓存加载、zip/tar.gz 安装、client 执行等回归测试。

### 调用方（上游）

- `codex-rs/core/src/tools/handlers/artifacts.rs:30-295`
  - artifacts tool 执行入口。
- `codex-rs/core/src/tools/spec.rs:335-336,2069-2092,2925-2929`
  - artifacts tool 是否暴露、grammar、handler 注册。
- `codex-rs/core/src/packages/versions.rs:2`
  - runtime 版本 pin。
- `codex-rs/core/src/tools/spec_tests.rs:615-635`
  - tool 暴露测试。
- `codex-rs/core/src/tools/handlers/artifacts_tests.rs:13-99`
  - 参数解析、manager 默认配置、缓存路径契约测试。

### 被调用方（下游）

- `codex-rs/package-manager/src/manager.rs:55-323`
  - 安装主流程、并发锁、失败回滚。
- `codex-rs/package-manager/src/archive.rs:74-267`
  - 大小/哈希校验与安全解压。
- `codex-rs/package-manager/src/platform.rs:16-47`
  - 支持平台与 platform tag。
- `codex-rs/package-manager/src/error.rs:5-53`
  - 统一包管理错误语义。

### 配置、文档、脚本

- 配置入口：
  - `codex-rs/core/src/features.rs:809-813`（`Feature::Artifact`，默认关闭）
  - `codex-rs/core/config.schema.json:341,1935`（`features.artifact` schema）
- 文档：
  - `codex-rs/artifacts/README.md:1-36`（crate 定位与 API）
  - `codex-rs/package-manager/README.md:1-56`（安装与安全模型）
- 脚本（研究流程侧）：
  - `.ops/generate_daily_research_todo.sh:1-39`
  - `.ops/generate_research_blueprint_checklist.sh:1-73`

## 依赖与外部交互

### 1) 依赖

`codex-artifacts` 关键依赖见 `codex-rs/artifacts/Cargo.toml`：

- 内部：`codex-package-manager`
- 网络：`reqwest`
- 序列化：`serde` / `serde_json` / `url`
- 异步与进程：`tokio`
- 临时目录：`tempfile`
- 可执行查找：`which`
- 错误建模：`thiserror`

### 2) 外部交互面

1. 网络交互
- 与 release base URL 通信，下载 manifest 与 archive。

2. 文件系统交互
- 读写缓存目录：`<codex_home>/packages/artifacts/<version>/<platform>`。
- 写入 staging 目录和临时执行脚本。
- 通过 rename 实现安装提升与回滚。

3. 进程交互
- 启动 Node/Electron 子进程执行 JS。
- 异步读取 stdout/stderr，超时 kill 子进程。

4. 环境交互
- 发现可执行文件时读取 `PATH`。
- 发现 Codex Desktop 候选时读取 `HOME`（macOS）或 `LOCALAPPDATA/ProgramFiles`（Windows）。
- Electron 模式写入 `ELECTRON_RUN_AS_NODE=1`。

### 3) 测试与验证

`artifacts/src/tests.rs` 覆盖了核心路径：

- release URL 生成正确性（`tests.rs:35,50`）
- 本地缓存加载与入口缺失失败（`tests.rs:63,91`）
- zip/tar.gz 下载、校验、安装（`tests.rs:121,225`）
- client 包装脚本与 stdout/stderr 行为（`tests.rs:317`）

此外，`core` 层验证了 tool 暴露与 handler 行为：

- `core/src/tools/spec_tests.rs:615`
- `core/src/tools/handlers/artifacts_tests.rs:13`

## 风险、边界与改进建议

### 风险

1. 输出内存压力
- `run_command` 采用 `read_to_end` 聚合输出（`client.rs:179-221`），超大输出可能带来内存风险。

2. 超时策略固定
- 默认 30s（`client.rs:16`），仅靠调用方 pragma 覆盖；在重任务场景可能不稳定。

3. tool 可见性与可执行性存在“能力分离”
- spec 使用 `can_manage_artifact_runtime()` 仅检查平台（`core/src/tools/spec.rs:336` + `runtime/js_runtime.rs:71-72`），实际运行时仍可能因缺少 Node/Electron 在执行时报错（`runtime/error.rs:24-26`）。

4. Windows 直接测试覆盖偏弱
- crate 级测试模块启用条件为 `#[cfg(all(test, not(windows)))]`（`lib.rs:3`），Windows 行为更多依赖间接覆盖。

### 边界

1. 本目录不定义 artifact 业务 DSL，只负责 runtime 安装/校验/执行承载。
2. tool 输入协议（grammar + pragma）定义在 `core`，`artifacts` 只接收纯 `source/cwd/timeout/env`。
3. runtime 版本由 `core` pin；本目录不做自动升级策略。

### 改进建议

1. 输出限制与流式回传
- 在 `ArtifactsClient` 增加可选 stdout/stderr 截断阈值，或支持流式汇报给上层事件系统，降低内存峰值。

2. 能力探测前移
- 在 tool 注册条件中增加“本机 JS runtime 可用性”判定（或预检查告警），减少运行时错误才暴露问题的体验。

3. 可观测性增强
- 在错误输出中附带 runtime 选择来源（node/electron/desktop-candidate）与命中路径摘要，便于诊断现场环境差异。

4. 测试覆盖补强
- 补充 Windows 平台特定路径候选逻辑与执行分支测试（可通过模拟路径探测函数输入做平台无关单元测试）。
