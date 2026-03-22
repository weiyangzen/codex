# codex-rs/artifacts/Cargo.toml 研究文档

## 场景与职责

`Cargo.toml` 是 Rust 包管理器 Cargo 的配置文件，定义了 `codex-artifacts` crate 的元数据、依赖关系和构建配置。该 crate 是 Codex 项目中负责 **Artifact 运行时管理** 的核心组件。

Artifact 是 Codex 生成的一种结构化输出格式（如 React 组件、图表、文档等），`codex-artifacts` 提供了：
1. Artifact 运行时的定位、验证和下载
2. 基于该运行时的构建和渲染命令执行

## 功能点目的

### 1. 包元数据配置

```toml
[package]
name = "codex-artifacts"
version.workspace = true
edition.workspace = true
license.workspace = true
```

- **name**: crate 名称，使用连字符命名规范（在代码中映射为 `codex_artifacts`）
- **version/edition/license**: 从工作区继承，确保整个 workspace 版本一致性

### 2. 运行时依赖

| 依赖 | 用途 |
|------|------|
| `codex-package-manager` | 包管理抽象，提供 `PackageManager` 和 `ManagedPackage` trait |
| `reqwest` | HTTP 客户端，用于下载运行时 release |
| `serde`/`serde_json` | 序列化/反序列化 manifest 和 package.json |
| `tempfile` | 创建临时目录用于构建 staging |
| `thiserror` | 错误类型派生宏 |
| `tokio` | 异步运行时（fs, process, time 特性） |
| `url` | URL 解析和处理 |
| `which` | 系统命令查找（node/electron） |

### 3. 开发依赖

| 依赖 | 用途 |
|------|------|
| `flate2` | gzip 压缩/解压（测试用） |
| `pretty_assertions` | 测试断言美化 |
| `sha2` | SHA256 校验（测试用） |
| `tar` | tar 归档处理（测试用） |
| `wiremock` | HTTP mock 服务器（测试用） |
| `zip` | zip 归档处理（测试用） |

开发依赖主要用于构建测试用的模拟运行时归档文件。

## 具体技术实现

### 依赖特性详解

#### tokio 特性选择

```toml
tokio = { workspace = true, features = ["fs", "io-util", "process", "time"] }
```

- `fs`: 异步文件系统操作（`tokio::fs`）
- `io-util`: 异步 IO 工具（`AsyncReadExt` 等）
- `process`: 异步进程管理（执行 artifact 构建命令）
- `time`: 超时控制（`tokio::time::timeout`）

#### serde derive 特性

```toml
serde = { workspace = true, features = ["derive"] }
```

启用 `#[derive(Deserialize, Serialize)]`，用于：
- `ReleaseManifest` 的 JSON 解析
- `package.json` 的解析

### 工作区依赖管理

所有依赖都使用 `workspace = true`，表示版本在根目录 `Cargo.toml` 的 `[workspace.dependencies]` 中统一管理。这种设计确保：

1. 整个 workspace 使用相同版本的依赖
2. 避免版本冲突
3. 简化依赖升级流程

## 关键代码路径与文件引用

### 依赖使用位置

| 依赖 | 使用位置 | 用途 |
|------|---------|------|
| `codex-package-manager` | `src/runtime/manager.rs` | `PackageManager<ArtifactRuntimePackage>` |
| `reqwest` | `src/runtime/manager.rs` | HTTP 客户端注入 |
| `serde` | `src/runtime/manifest.rs`, `src/runtime/installed.rs` | JSON 反序列化 |
| `tempfile` | `src/client.rs` | `TempDir::new()` 创建 staging |
| `thiserror` | `src/runtime/error.rs` | `#[derive(Error)]` |
| `tokio` | 全 crate | 异步 IO、进程、超时 |
| `url` | `src/runtime/manager.rs` | `Url` 类型 |
| `which` | `src/runtime/js_runtime.rs` | 查找 node/electron |

### 模块结构

```
src/
├── lib.rs           # 公共 API 导出
├── client.rs        # ArtifactsClient 实现
├── runtime/
│   ├── mod.rs       # runtime 模块聚合
│   ├── manager.rs   # ArtifactRuntimeManager
│   ├── installed.rs # InstalledArtifactRuntime
│   ├── js_runtime.rs # JsRuntime 解析
│   ├── manifest.rs  # ReleaseManifest
│   └── error.rs     # ArtifactRuntimeError
└── tests.rs         # 集成测试
```

## 依赖与外部交互

### 内部依赖

```
codex-artifacts
└── codex-package-manager (workspace)
    └── 提供: PackageManager, ManagedPackage, PackagePlatform
```

### 外部 crate 交互

| crate | 交互方式 |
|-------|---------|
| `reqwest` | 通过 `ArtifactRuntimeManager::with_client()` 注入 |
| `tokio::process` | `src/client.rs` 中执行 artifact 构建命令 |
| `serde_json` | 解析 manifest 和 package.json |

### 系统依赖

运行时依赖系统安装的 JavaScript 执行环境（按优先级）：
1. 系统 Node.js (`node` 命令)
2. 系统 Electron (`electron` 命令)
3. Codex Desktop App 内置的 Electron

## 风险、边界与改进建议

### 风险点

1. **版本漂移风险**:
   ```toml
   [dependencies]
   codex-package-manager = { workspace = true }
   ```
   如果 `codex-package-manager` 的 API 发生破坏性变更，需要同步更新本 crate。

2. **tokio 特性不足**:
   当前 tokio 特性在 dev-dependencies 中比 dependencies 多 `macros`, `rt`, `rt-multi-thread`。
   如果测试需要更多特性，需要保持同步。

3. **HTTP 客户端依赖**:
   `reqwest` 是较重的依赖，如果未来需要支持 WASM 或其他受限环境，可能需要抽象 HTTP 层。

### 边界条件

1. **平台支持**: 仅支持 `PackagePlatform` 定义的 6 种平台组合
2. **网络依赖**: 首次使用需要下载运行时（约数十 MB）
3. **磁盘空间**: 缓存目录位于 `~/.codex/packages/artifacts/`

### 改进建议

1. **特性门控**:
   考虑添加可选特性，如：
   ```toml
   [features]
   default = ["download"]
   download = ["reqwest"]
   offline = []  # 仅使用预安装运行时
   ```

2. **依赖精简**:
   - `url` crate 可能可以通过 `reqwest::Url` 替代，减少一个依赖
   - 评估 `which` 是否可以用标准库实现

3. **版本约束**:
   考虑为关键依赖添加最小版本约束：
   ```toml
   tokio = { workspace = true, features = [...], version = ">=1.28" }
   ```

4. **文档依赖**:
   在 `Cargo.toml` 中添加注释说明每个依赖的具体用途，便于新开发者理解

### 维护检查清单

- [ ] 修改依赖后运行 `just bazel-lock-update`
- [ ] 修改依赖后运行 `just bazel-lock-check`
- [ ] 新增依赖时检查是否需要添加 `compile_data` 或 `build_script_data`
- [ ] 确保 dev-dependencies 中的 tokio 特性覆盖测试需求
