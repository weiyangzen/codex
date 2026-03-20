# DIR `codex-rs/artifacts/src/runtime` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/artifacts/src/runtime`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-artifacts`（`codex-rs/artifacts/Cargo.toml:2`）

## 场景与职责

`codex-rs/artifacts/src/runtime` 是 `codex-artifacts` 中专门负责“artifact JS 运行时生命周期”的子模块：

1. 解析并生成 runtime 发布地址（release tag / manifest / archive URL）。
2. 通过 `codex-package-manager` 完成下载、校验、解压、缓存与安装复用。
3. 对已安装 runtime 做结构化校验（`package.json`、导出入口、路径安全）。
4. 选择本机可用的 JS 执行器（Node / Electron / Codex Desktop 内置 Electron）。
5. 对上层提供统一错误模型与稳定 API 导出。

目录内模块拼装点在 `runtime/mod.rs`，统一导出公共类型，且仅暴露必要 internal helper 给同 crate 其他模块（`codex-rs/artifacts/src/runtime/mod.rs:1-28`）。

它的上游/下游边界非常清晰：

- 上游调用方：
  - `ArtifactsClient` 在执行 JS 前调用 runtime 解析（`codex-rs/artifacts/src/client.rs:51-53,94-98`）。
  - `core` 的 artifacts tool handler 构建默认 runtime manager 并触发执行（`codex-rs/core/src/tools/handlers/artifacts.rs:82-99,214-219`）。
  - tool 是否暴露由 feature + runtime 平台能力决定（`codex-rs/core/src/tools/spec.rs:335-336,2922-2930`）。
- 下游依赖：
  - `codex-package-manager` 的泛型安装流程（`codex-rs/package-manager/src/manager.rs:43-320`）。
  - 平台检测与平台字符串编码（`codex-rs/package-manager/src/platform.rs:20-47`）。
  - 归档校验与安全解压（`codex-rs/package-manager/src/archive.rs:74-270`）。

## 功能点目的

### 1) Release 定位与版本绑定

对应代码：`manager.rs`。

- 通过 `ArtifactRuntimeReleaseLocator` 将 `(base_url, runtime_version, tag_prefix)` 组合成发布路径（`codex-rs/artifacts/src/runtime/manager.rs:27-88`）。
- 默认约定：
  - tag 前缀：`artifact-runtime-v`（`manager.rs:17`）。
  - 下载基址：`https://github.com/openai/codex/releases/download/`（`manager.rs:23`）。
  - manifest 文件名：`<release_tag>-manifest.json`（`manager.rs:64-67`）。
- 目的：把运行时升级问题收敛为“仅变更版本号 + 固定命名协议”。

### 2) 缓存目录与安装入口管理

对应代码：`manager.rs` + `installed.rs`。

- 默认缓存相对目录：`packages/artifacts`（`manager.rs:20`）。
- 最终安装路径：`<cache_root>/<runtime_version>/<platform>`（`manager.rs:236-238`，`installed.rs:114-120`）。
- `ArtifactRuntimeManager` 提供两类入口：
  - `resolve_cached`：只看本地（`manager.rs:166-171`）。
  - `ensure_installed`：必要时下载并安装（`manager.rs:173-176`）。
- 目的：支持“离线命中缓存”和“在线自动补齐”两种运行场景。

### 3) 已安装 runtime 校验

对应代码：`installed.rs`。

- `load_cached_runtime` 先按当前平台拼接安装目录并检查存在性，再进入严格加载（`installed.rs:16-33`）。
- `InstalledArtifactRuntime::load` 要求：
  - `package.json` 可解析；
  - 包名必须是 `@oai/artifact-tool`（`installed.rs:13,255-267`）；
  - `exports` 必须能解析主入口（`installed.rs:225-239,269-277`）；
  - 主入口路径必须是安全相对路径，禁止绝对路径和 `..` 跳转（`installed.rs:126-147`）；
  - 最终入口文件必须存在（`installed.rs:149-158`）。
- 目的：避免加载错误包、目录穿越路径或残缺安装。

### 4) JS 运行器发现与回退

对应代码：`js_runtime.rs` + `installed.rs`。

- 决策顺序：Node -> Electron -> Codex Desktop 安装路径候选（`js_runtime.rs:83-93`）。
- `which("node")` 和 `which("electron")` 检查系统 PATH（`js_runtime.rs:95-105`）。
- 如命中 Electron，执行时必须注入 `ELECTRON_RUN_AS_NODE=1`（`js_runtime.rs:51-54`，`client.rs:80-82`）。
- 桌面候选路径按 OS 规则生成：
  - macOS：`/Applications` + `~/Applications` 下 `.app/Contents/MacOS/<name>`；
  - Windows：`LOCALAPPDATA/Programs`、`ProgramFiles`、`ProgramFiles(x86)`；
  - Linux：`/opt`、`/usr/lib`。
  见 `js_runtime.rs:116-170`。
- 目的：尽可能复用机器已有 JS 执行环境，降低运行前置依赖。

### 5) 能力判定 API

对应代码：`js_runtime.rs`。

- `can_manage_artifact_runtime()`：仅判断“平台是否受 package-manager 支持”（`js_runtime.rs:66-73`）。
- `is_js_runtime_available(codex_home, runtime_version)`：判断“是否能执行 artifact JS”，会尝试缓存 runtime + runtime 解析，失败再回退机器运行器（`js_runtime.rs:57-64`）。
- 目的：把“是否展示功能”和“是否真正可执行”拆开给上层做不同决策。

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 关键流程

1. `core` 层打开 artifacts tool：
- `Feature::Artifact` 打开且平台支持 managed runtime（`codex-rs/core/src/features.rs:175-176,809-813`，`codex-rs/core/src/tools/spec.rs:335-336`）。
- tool 注册 `create_artifacts_tool + ArtifactsHandler`（`codex-rs/core/src/tools/spec.rs:2069-2093,2922-2930`）。

2. handler 构建默认 manager：
- 使用 `versions::ARTIFACT_RUNTIME`（当前 `2.5.6`）+ 默认 release 基址（`codex-rs/core/src/tools/handlers/artifacts.rs:214-218`，`codex-rs/core/src/packages/versions.rs:2`）。

3. 执行路径（managed 模式）：
- `ArtifactsClient::resolve_runtime()` 调 `manager.ensure_installed()`（`codex-rs/artifacts/src/client.rs:94-98`）。
- `ArtifactRuntimeManager` 委托 `PackageManager::ensure_installed()`（`codex-rs/artifacts/src/runtime/manager.rs:173-176`）。

4. package-manager 核心安装步骤：
- 先查缓存，再加安装锁（`codex-rs/package-manager/src/manager.rs:55-118`）；
- 拉 manifest，校验 manifest 版本与请求版本一致（`manager.rs:120-127`）；
- 下载 archive，校验 size + sha256（`manager.rs:147-156`，`archive.rs:74-96`）；
- 解压到 staging，检测 package root，加载并做 package-specific 校验（`manager.rs:157-199`）；
- 两阶段提升安装目录，并处理回滚（`manager.rs:211-297`）。

5. runtime 验证与执行准备：
- `InstalledArtifactRuntime::load` 完成 package.json + 入口验证（`codex-rs/artifacts/src/runtime/installed.rs:60-76,217-283`）。
- `resolve_js_runtime` 决策可执行器（`installed.rs:98-111` + `js_runtime.rs:83-113`）。

6. JS 命令执行：
- `ArtifactsClient` 在临时目录写入 `artifact-build.mjs`，内容是：先动态 import runtime entrypoint，再把 named exports 注入 `globalThis`（`codex-rs/artifacts/src/client.rs:57-70,141-163`）。
- 命令形态：`<node_or_electron> <temp_script>`，工作目录是请求 `cwd`（`client.rs:77-79`）。
- `tokio::time::timeout` 控制超时，超时 kill 子进程（`client.rs:190-201`）。

### B. 关键数据结构

1. `ArtifactRuntimeReleaseLocator`（`manager.rs:27-31`）
- 字段：`base_url`、`runtime_version`、`release_tag_prefix`。
- 作用：构造 manifest/archive 绝对 URL（`manager.rs:69-78,207-216`）。

2. `ArtifactRuntimeManagerConfig`（`manager.rs:93-96`）
- 内含 package-manager config 与 release locator。
- 支持 `with_cache_root` 做缓存重定位（`manager.rs:118-127`）。

3. `ReleaseManifest`（`manifest.rs:8-15`）
- 字段：`schema_version`、`runtime_version`、`release_tag`、`node_version`、`platforms`。
- `platforms` 的值类型是 `PackageReleaseArchive`（`manifest.rs:1,14`）。

4. `InstalledArtifactRuntime`（`installed.rs:37-42`）
- 字段：`root_dir`、`runtime_version`、`platform`、`build_js_path`。
- 运行时消费最关键的是 `build_js_path` 与 `resolve_js_runtime()`。

5. `ArtifactRuntimeError`（`error.rs:7-28`）
- 聚合包管理错误、IO 错误、JSON 元数据错误、路径错误与“找不到 JS runtime”错误。

### C. 协议与约定

1. 发布 URL 协议
- manifest：`<base>/<tag>/<tag>-manifest.json`（`manager.rs:69-78`）。
- archive：`<base>/<tag>/<archive>`（`manager.rs:207-216`）。

2. 包内容协议
- runtime 目录必须含合法 `package.json`；
- `package.json.name` 必须是 `@oai/artifact-tool`；
- `exports["."]`（或 main string）必须指向 JS 入口文件。
见 `installed.rs:217-283`。

3. 平台协议
- 平台字符串固定枚举：`darwin-arm64`、`darwin-x64`、`linux-arm64`、`linux-x64`、`windows-arm64`、`windows-x64`（`codex-rs/package-manager/src/platform.rs:5-47`）。

4. artifacts tool 输入协议（runtime 的上游依赖）
- Lark grammar 支持可选 pragma 第一行（`codex-rs/core/src/tools/spec.rs:2070-2083`）。
- pragma 仅允许 `timeout_ms`，并拒绝 JSON/字符串/markdown fence 包装（`codex-rs/core/src/tools/handlers/artifacts.rs:123-207`）。

### D. 关键命令与系统调用

- 网络命令：`reqwest` 发起 GET manifest/archive（`codex-rs/package-manager/src/manager.rs:326-381`）。
- 文件命令：创建 cache/staging、写 archive、解压、rename promote/rollback（`manager.rs:129-297`）。
- 进程命令：`tokio::process::Command::new(js_runtime.executable_path())`（`codex-rs/artifacts/src/client.rs:77-85`）。

## 关键代码路径与文件引用

### 目录内核心文件

1. `codex-rs/artifacts/src/runtime/mod.rs`
- 导出面与 internal helper 可见性组织（`1-28`）。

2. `codex-rs/artifacts/src/runtime/manager.rs`
- 默认协议常量（`16-23`）。
- `ArtifactRuntimeReleaseLocator` URL 生成（`33-88`）。
- `ArtifactRuntimeManagerConfig`（`98-132`）。
- `ArtifactRuntimeManager` 托管安装入口（`142-176`）。
- `ManagedPackage` 实现（`190-255`）。

3. `codex-rs/artifacts/src/runtime/installed.rs`
- 缓存加载入口（`16-33`）。
- `InstalledArtifactRuntime` 模型与加载（`35-112`）。
- 相对路径安全校验（`126-147`）。
- runtime root 探测（`160-197`）。
- `package.json` 解析与约束（`217-283`）。

4. `codex-rs/artifacts/src/runtime/js_runtime.rs`
- `JsRuntime`/`JsRuntimeKind` 模型（`17-55`）。
- runtime 可用性与平台能力 API（`57-73`）。
- Node/Electron/桌面候选路径决策（`75-170`）。

5. `codex-rs/artifacts/src/runtime/error.rs`
- runtime 层错误模型（`7-28`）。

6. `codex-rs/artifacts/src/runtime/manifest.rs`
- release manifest 结构（`8-15`）。

### 上下文关键调用路径

- `codex-rs/artifacts/src/client.rs:46-99,141-229`
- `codex-rs/core/src/tools/handlers/artifacts.rs:58-120,214-219`
- `codex-rs/core/src/tools/spec.rs:335-336,2069-2093,2922-2930`
- `codex-rs/core/src/packages/versions.rs:1-2`
- `codex-rs/package-manager/src/package.rs:10-69`
- `codex-rs/package-manager/src/manager.rs:43-320`
- `codex-rs/package-manager/src/archive.rs:14-270`
- `codex-rs/package-manager/src/config.rs:4-40`
- `codex-rs/package-manager/src/platform.rs:3-47`

### 测试路径

- `codex-rs/artifacts/src/tests.rs`
  - URL 构建：`34-60`
  - 缓存加载与入口检查：`62-118,186-222,290-313`
  - zip/tar.gz 安装链路：`120-184,224-288`
  - 真实执行包装脚本行为：`315-352`
- `codex-rs/core/src/tools/handlers/artifacts_tests.rs:5-98`
- `codex-rs/core/src/tools/spec_tests.rs:614-634`
- `codex-rs/package-manager/src/tests.rs:137,208,246,307,352,416,501,579,595,610`

## 依赖与外部交互

### 1) 依赖关系

`codex-artifacts` 的 runtime 相关依赖（`codex-rs/artifacts/Cargo.toml:7-17`）：

- `codex-package-manager`：安装与缓存生命周期。
- `reqwest`：网络拉取。
- `serde/serde_json/url`：manifest 与元数据处理。
- `tokio`：异步文件与进程。
- `which`：系统可执行探测。
- `tempfile`：临时脚本目录。
- `thiserror`：错误建模。

workspace 连接关系：`codex-rs/Cargo.toml:73,91-92`（`artifacts` 与 `codex-package-manager` 同属 workspace）。

### 2) 外部交互

1. 网络
- 访问 GitHub Releases（默认）或自定义 base URL（`manager.rs:23,35-41,80-88`）。

2. 文件系统
- 读写 `<codex_home>/packages/artifacts/...`（`manager.rs:20,236-238`，`installed.rs:122-124`）。
- staging 目录 `.staging` + lock 文件机制（`codex-rs/package-manager/src/manager.rs:82-99,136-143,157-175`）。

3. 进程
- 调 Node/Electron 运行临时脚本，并处理超时终止（`client.rs:77-92,190-201`）。

4. 环境变量
- 读取：`HOME`、`LOCALAPPDATA`、`ProgramFiles`、`ProgramFiles(x86)`（`js_runtime.rs:120-148`）。
- 写入：`ELECTRON_RUN_AS_NODE=1`（`client.rs:80-82`）。

### 3) 配置与脚本/文档上下文

- 配置项：
  - `Feature::Artifact`（默认关闭）`codex-rs/core/src/features.rs:175-176,809-813`。
  - runtime version pin：`codex-rs/core/src/packages/versions.rs:2`。
- 文档：
  - `codex-rs/artifacts/README.md:1-36` 描述 runtime 子模块职责。
- 脚本：
  - 仓库中未发现专门“构建 artifact runtime 包”的本地脚本（`scripts/` 与 `codex-rs/scripts/` 对 `artifact-runtime/@oai/artifact-tool` 无命中）。
  - 当前目录 runtime 主要依赖 release 产物消费，而非本地打包流水线。

## 风险、边界与改进建议

### 风险

1. tool 暴露与实际可执行性存在时差
- tool 注册仅看 `Feature::Artifact + can_manage_artifact_runtime()`（平台能力）（`core/src/tools/spec.rs:335-336`）。
- 若本机没有 Node/Electron，仍可能在执行阶段报 `MissingJsRuntime`（`runtime/error.rs:24-27`）。

2. 输出内存占用风险
- 当前 stdout/stderr 采用 `read_to_end` 全量聚合（`client.rs:181-188,203-228`），长输出可能抬高内存峰值。

3. runtime 根目录探测较保守
- `detect_runtime_root` 只接受“根目录直接合法”或“唯一子目录合法”（`installed.rs:160-197`）。
- 若上游发布包有多层目录变化，会直接失败。

4. 可执行路径候选可能受安装布局变化影响
- Codex Desktop 候选路径是硬编码约定（`js_runtime.rs:8-15,116-170`），产品命名或安装路径改变会导致回退失效。

### 边界

1. 本目录不负责 artifacts freeform 协议定义，协议在 `core/tools/spec.rs` 与 `core/tools/handlers/artifacts.rs`。
2. 本目录不管理 runtime 版本演进策略；版本由 `core/src/packages/versions.rs` 固定。
3. 本目录不包含 artifact runtime 包构建逻辑，只负责发布产物消费与本地验证。

### 改进建议

1. 增加“预检查接口”给上层
- 在 tool 暴露前或会话初始化时提供 `runtime + js executable` 联合可用性检查，避免运行时才报错。

2. 输出采集支持上限或流式
- 给 `ArtifactsClient::run_command` 增加可配置字节上限或流式上报，降低大输出风险。

3. runtime root 探测策略可配置化
- 在保持安全前提下支持多层前缀目录探测，降低发布包结构轻微变动带来的兼容性问题。

4. 桌面候选路径可观测性增强
- 记录“最终选中的 runtime 类型和路径”到调试日志，便于用户诊断环境问题。
