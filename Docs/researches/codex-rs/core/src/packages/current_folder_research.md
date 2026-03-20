# Research: codex-rs/core/src/packages

## 概述

`codex-rs/core/src/packages` 是 Codex 核心库中的一个极简模块，仅包含版本管理功能。该模块定义了 Artifact 工具运行时的固定版本号，用于支持 artifacts 功能的 JavaScript 运行时下载和管理。

---

## 场景与职责

### 核心职责

1. **版本固定（Version Pinning）**：定义 Artifact 工具运行时的固定版本号 `ARTIFACT_RUNTIME`，确保所有用户使用一致的运行时版本。

2. **Artifacts 功能支持**：为 `artifacts` 工具提供 JavaScript 运行时版本信息，使其能够下载、缓存和执行 artifact 构建脚本。

### 使用场景

- 当 Codex 需要执行 artifact 构建任务时，通过 `artifacts` 工具调用 JavaScript 代码
- 系统需要下载或验证 `@oai/artifact-tool` 包时，使用固定的版本号 `2.5.6`
- 在测试环境中模拟 artifact 运行时安装和加载过程

---

## 功能点目的

### 1. 版本常量定义

```rust
pub(crate) const ARTIFACT_RUNTIME: &str = "2.5.6";
```

**目的**：
- 确保所有 Codex 实例使用相同的 artifact 工具版本
- 避免版本漂移导致的兼容性问题
- 便于统一升级和管理

### 2. 模块组织

```rust
// mod.rs
pub(crate) mod versions;
```

**设计意图**：
- 虽然目前只有一个版本模块，但保留了扩展性
- 未来可能添加更多包管理相关的版本常量或配置

---

## 具体技术实现

### 关键数据结构

#### ARTIFACT_RUNTIME 常量

```rust
/// Pinned versions for package-manager-backed installs.
pub(crate) const ARTIFACT_RUNTIME: &str = "2.5.6";
```

- **类型**：`&str` 字符串常量
- **值**：`"2.5.6"` - artifact 工具运行时版本
- **可见性**：`pub(crate)`，仅 crate 内部可访问

### 关键流程

#### Artifact 工具执行流程

1. **版本引用**：`artifacts.rs` 处理器通过 `versions::ARTIFACT_RUNTIME` 获取固定版本
2. **运行时管理器创建**：使用版本号创建 `ArtifactRuntimeManager`
3. **运行时解析**：
   - 检查本地缓存是否存在对应版本的运行时
   - 如不存在，从 GitHub releases 下载
4. **JavaScript 执行**：使用解析到的运行时执行 artifact 构建脚本

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  ArtifactsHandler│────▶│ versions::       │────▶│ ArtifactRuntime │
│  (tools/handlers)│     │ ARTIFACT_RUNTIME │     │ Manager         │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                                                          │
                           ┌──────────────────────────────┘
                           ▼
                    ┌─────────────────┐
                    │ GitHub Releases │
                    │ (下载/缓存)      │
                    └─────────────────┘
```

### 依赖关系

#### 调用方（上游依赖）

| 文件路径 | 使用方式 | 用途 |
|---------|---------|------|
| `core/src/tools/handlers/artifacts.rs:18` | `use crate::packages::versions;` | 导入版本模块 |
| `core/src/tools/handlers/artifacts.rs:217` | `versions::ARTIFACT_RUNTIME` | 创建默认运行时管理器 |
| `core/src/tools/handlers/artifacts_tests.rs:2` | `use crate::packages::versions;` | 测试导入 |
| `core/src/tools/handlers/artifacts_tests.rs:40,53,61,80,83` | `versions::ARTIFACT_RUNTIME` | 测试断言 |

#### 被调用方（下游依赖）

该模块为纯常量定义，不依赖其他模块。

---

## 关键代码路径与文件引用

### 本模块文件

| 文件 | 行数 | 说明 |
|-----|------|------|
| `codex-rs/core/src/packages/mod.rs` | 1 | 模块入口，导出 versions 子模块 |
| `codex-rs/core/src/packages/versions.rs` | 2 | 版本常量定义 |

### 相关文件（Artifacts 系统）

| 文件 | 说明 |
|-----|------|
| `codex-rs/artifacts/src/lib.rs` | Artifacts crate 入口，导出运行时相关类型 |
| `codex-rs/artifacts/src/runtime/manager.rs` | ArtifactRuntimeManager 实现，包含 `DEFAULT_CACHE_ROOT_RELATIVE = "packages/artifacts"` |
| `codex-rs/artifacts/src/runtime/installed.rs` | 已安装运行时加载和验证 |
| `codex-rs/artifacts/src/runtime/js_runtime.rs` | JavaScript 运行时（Node/Electron）检测 |
| `codex-rs/artifacts/src/runtime/manifest.rs` | ReleaseManifest 定义 |
| `codex-rs/artifacts/src/client.rs` | ArtifactsClient 实现，执行 artifact 构建 |
| `codex-rs/core/src/tools/handlers/artifacts.rs` | Artifacts 工具处理器 |
| `codex-rs/core/src/tools/handlers/artifacts_tests.rs` | Artifacts 工具测试 |

### Package Manager 相关

| 文件 | 说明 |
|-----|------|
| `codex-rs/package-manager/src/lib.rs` | Package manager crate 入口 |
| `codex-rs/package-manager/src/manager.rs` | PackageManager 实现，通用包管理逻辑 |
| `codex-rs/package-manager/src/package.rs` | `ManagedPackage` trait 定义 |
| `codex-rs/package-manager/src/config.rs` | `PackageManagerConfig` 配置 |
| `codex-rs/package-manager/src/platform.rs` | `PackagePlatform` 平台检测 |
| `codex-rs/package-manager/src/error.rs` | `PackageManagerError` 错误类型 |

---

## 依赖与外部交互

### 内部依赖

```
codex-rs/core/src/packages/
├── mod.rs (无外部依赖)
└── versions.rs (无外部依赖)
```

### 外部交互

该模块本身不涉及外部交互，但使用该模块的代码会触发以下交互：

1. **GitHub Releases API**：下载 artifact 运行时包
   - 基础 URL：`https://github.com/openai/codex/releases/download/`
   - 发布标签格式：`artifact-runtime-v{VERSION}`

2. **文件系统**：缓存运行时到本地目录
   - 缓存路径：`{CODEX_HOME}/packages/artifacts/{VERSION}/{PLATFORM}/`

3. **进程执行**：启动 Node/Electron 执行 JavaScript

---

## 风险、边界与改进建议

### 潜在风险

1. **版本硬编码风险**
   - 当前版本 `2.5.6` 硬编码在源代码中
   - 升级需要重新编译发布
   - 无法通过配置动态调整

2. **版本过时风险**
   - 如果 artifact-tool 发布新版本，Codex 用户无法立即使用
   - 需要等待 Codex 更新并重新发布

3. **网络依赖风险**
   - 首次使用 artifacts 功能时需要下载运行时
   - 网络不可用或 GitHub 访问受限时功能不可用

### 边界情况

1. **缓存失效**：当 `ARTIFACT_RUNTIME` 版本更新时，旧版本缓存不会被自动清理
2. **平台不支持**：某些平台可能无法使用 artifacts 功能（`can_manage_artifact_runtime()` 返回 false）
3. **JS 运行时缺失**：如果系统没有 Node 或 Electron，artifacts 功能无法使用

### 改进建议

1. **配置化版本**
   ```rust
   // 建议：允许通过配置文件或环境变量覆盖版本
   pub(crate) fn artifact_runtime_version() -> &'static str {
       std::env::var("CODEX_ARTIFACT_RUNTIME_VERSION")
           .ok()
           .map(|s| s.leak())
           .unwrap_or("2.5.6")
   }
   ```

2. **版本自动检测**
   - 添加机制检测最新可用版本
   - 在兼容的前提下自动使用最新版本

3. **离线模式支持**
   - 支持预下载运行时包
   - 提供离线安装脚本

4. **缓存清理机制**
   - 添加命令清理旧版本缓存
   - 自动清理长期未使用的版本

5. **扩展模块功能**
   - 当前模块过于简单，可考虑合并到更上层的配置模块
   - 或扩展为管理多个包版本的通用模块

---

## 总结

`codex-rs/core/src/packages` 是一个极简的版本管理模块，仅定义了 `ARTIFACT_RUNTIME = "2.5.6"` 这一个常量。虽然代码量极少，但它是 artifacts 功能的核心依赖，确保所有 Codex 实例使用一致的 JavaScript 运行时版本来执行 artifact 构建任务。

该模块的设计体现了"单一职责"原则，将版本固定逻辑与具体的包管理实现（在 `codex-rs/artifacts` 和 `codex-rs/package-manager` 中）分离，使得版本更新只需修改这一处代码。
