# DIR codex-rs/core/src/packages 研究文档

## 概述

`codex-rs/core/src/packages` 是 Codex CLI 项目中一个精简但关键的模块，负责管理 **Artifact Runtime** 的版本 pinning（固定版本）。该模块通过定义常量来锁定 artifact 工具的运行时版本，确保 Codex 在执行 JavaScript artifact 构建时使用确定性的、经过测试的运行时环境。

---

## 场景与职责

### 核心职责

1. **版本锁定（Version Pinning）**：定义并暴露 Artifact Runtime 的固定版本号，确保所有用户使用一致的运行时环境
2. **与 Artifact 系统集成**：为 `codex_artifacts` crate 提供版本常量，支持 artifact 工具的下载、缓存和执行
3. **确定性构建**：避免因运行时版本漂移导致的构建不一致问题

### 使用场景

- 当 Codex 需要执行 JavaScript artifact 构建时，通过 `ArtifactsHandler` 调用 `default_runtime_manager()`
- `default_runtime_manager()` 使用 `versions::ARTIFACT_RUNTIME` 作为参数创建 `ArtifactRuntimeManager`
- `ArtifactRuntimeManager` 根据该版本号从 GitHub Releases 下载对应版本的 `@oai/artifact-tool` 包

---

## 功能点目的

### 1. 版本常量定义 (`versions.rs`)

```rust
/// Pinned versions for package-manager-backed installs.
pub(crate) const ARTIFACT_RUNTIME: &str = "2.5.6";
```

**设计意图**：
- 将版本号集中管理，便于统一升级
- 使用 `pub(crate)` 限制可见性，仅 crate 内部使用
- 语义化版本号遵循 SemVer 规范

### 2. 模块导出 (`mod.rs`)

```rust
pub(crate) mod versions;
```

**设计意图**：
- 极简的模块结构，仅暴露必要的版本信息
- 为将来可能的扩展预留空间（如添加更多包管理相关的版本常量）

---

## 具体技术实现

### 关键数据结构与常量

| 项目 | 类型 | 值 | 说明 |
|------|------|-----|------|
| `ARTIFACT_RUNTIME` | `&str` | `"2.5.6"` | Artifact 工具运行时版本 |

### 调用链流程

```
┌─────────────────────────────────────────────────────────────────┐
│  调用方 (Callers)                                                │
├─────────────────────────────────────────────────────────────────┤
│  1. ArtifactsHandler::handle()                                   │
│     └─> default_runtime_manager(turn.config.codex_home)         │
│         └─> versions::ARTIFACT_RUNTIME                          │
│                                                                  │
│  2. ArtifactsHandler 测试                                         │
│     └─> 验证 runtime_version() 返回值                           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  ArtifactRuntimeManager (codex_artifacts crate)                 │
├─────────────────────────────────────────────────────────────────┤
│  - 使用传入的版本号构建 ReleaseLocator                          │
│  - 从 GitHub Releases 下载对应版本的 artifact-runtime            │
│  - 缓存路径: ~/.codex/packages/artifacts/{version}/{platform}/  │
└─────────────────────────────────────────────────────────────────┘
```

### 缓存目录结构

```
~/.codex/
└── packages/
    └── artifacts/
        └── 2.5.6/                    # ARTIFACT_RUNTIME 版本号
            ├── darwin-arm64/         # 平台特定目录
            │   ├── package.json
            │   └── dist/
            │       └── artifact_tool.mjs
            ├── darwin-x64/
            ├── linux-arm64/
            ├── linux-x64/
            ├── windows-arm64/
            └── windows-x64/
```

### 版本验证流程

1. **下载阶段**：`ArtifactRuntimeManager` 从 GitHub Releases 下载 `artifact-runtime-v{VERSION}-manifest.json`
2. **校验阶段**：验证 manifest 中的 `runtime_version` 与 `ARTIFACT_RUNTIME` 常量一致
3. **安装阶段**：解压归档到缓存目录，验证 `package.json` 中的版本号
4. **运行时阶段**：`InstalledArtifactRuntime::load()` 再次验证版本一致性

---

## 关键代码路径与文件引用

### 本模块文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `mod.rs` | 1 | 模块导出，暴露 `versions` 子模块 |
| `versions.rs` | 2 | 定义 `ARTIFACT_RUNTIME` 版本常量 |

### 调用方文件

| 文件 | 引用方式 | 用途 |
|------|----------|------|
| `core/src/tools/handlers/artifacts.rs:18` | `use crate::packages::versions;` | 导入版本模块 |
| `core/src/tools/handlers/artifacts.rs:217` | `versions::ARTIFACT_RUNTIME` | 创建默认 runtime manager |
| `core/src/tools/handlers/artifacts_tests.rs:2` | `use crate::packages::versions;` | 测试导入 |
| `core/src/tools/handlers/artifacts_tests.rs:40` | `versions::ARTIFACT_RUNTIME` | 验证版本号 |

### 被调用方（依赖）文件

| 文件 | 说明 |
|------|------|
| `codex-rs/artifacts/src/runtime/manager.rs` | `ArtifactRuntimeManager` 实现，消费版本号 |
| `codex-rs/artifacts/src/runtime/installed.rs` | `InstalledArtifactRuntime` 验证已安装版本 |
| `codex-rs/package-manager/src/manager.rs` | 通用包管理器，处理下载和缓存 |

---

## 依赖与外部交互

### 内部依赖

```
codex-rs/core/src/packages/
    └── versions.rs
        └── ARTIFACT_RUNTIME
            └── 被以下模块使用:
                ├── tools/handlers/artifacts.rs
                └── tools/handlers/artifacts_tests.rs
```

### 外部 crate 依赖

| Crate | 关系 | 用途 |
|-------|------|------|
| `codex_artifacts` | 被调用 | 使用版本号管理 artifact runtime 生命周期 |
| `codex_package_manager` | 间接依赖 | 处理实际的包下载、解压、缓存逻辑 |

### 与 Artifact 工具的关系

```
┌─────────────────┐     ┌─────────────────────┐     ┌──────────────────┐
│   packages/     │────▶│  codex_artifacts    │────▶│ GitHub Releases  │
│  versions.rs    │     │  (runtime/manager)  │     │  artifact-runtime│
│  (版本常量)      │     │  (下载管理)          │     │  (v2.5.6)        │
└─────────────────┘     └─────────────────────┘     └──────────────────┘
         │                       │
         │                       ▼
         │              ┌─────────────────────┐
         │              │  ~/.codex/packages/ │
         └─────────────▶│  artifacts/2.5.6/   │
                        │  (本地缓存)          │
                        └─────────────────────┘
```

---

## 风险、边界与改进建议

### 当前风险

1. **硬编码版本号**：版本号 `2.5.6` 是硬编码的常量，需要手动更新
   - 升级时需要修改源代码并重新编译
   - 无法通过配置动态切换版本

2. **版本漂移风险**：如果 GitHub Releases 上的 artifact-runtime 被重新发布（相同版本号不同内容），SHA256 校验会失败
   - 当前设计依赖不可变发布物

3. **平台支持限制**：`ArtifactRuntimePlatform::detect_current()` 可能返回不支持的平台错误
   - 某些平台可能无法使用 artifact 功能

### 边界情况

1. **缓存失效**：当 `ARTIFACT_RUNTIME` 升级时，旧版本缓存不会自动清理
   - 缓存目录会累积多个版本
   - 需要手动清理或实现缓存淘汰策略

2. **离线环境**：首次使用需要网络下载，离线环境无法使用 artifact 功能
   - 没有预打包或离线安装机制

3. **并发安装**：多进程同时触发 `ensure_installed()` 时，文件锁机制确保只有一个进程执行下载
   - 其他进程会轮询等待（50ms 间隔）

### 改进建议

1. **配置化版本号**
   ```rust
   // 建议：允许通过配置文件覆盖版本号
   pub fn artifact_runtime_version() -> &'static str {
       option_env!("CODEX_ARTIFACT_RUNTIME_VERSION")
           .unwrap_or("2.5.6")
   }
   ```

2. **版本兼容性检查**
   - 添加最小/最大支持版本范围检查
   - 在版本不兼容时提供清晰的错误信息

3. **缓存清理机制**
   - 实现 LRU 缓存淘汰策略
   - 提供 `codex cleanup` 命令清理旧版本缓存

4. **离线模式支持**
   - 支持从本地路径加载预下载的 artifact-runtime
   - 允许通过环境变量指定离线包路径

5. **版本升级自动化**
   - 添加 CI 检查，当有新版本发布时自动创建 PR
   - 集成版本检查到健康检查命令

### 测试覆盖

| 测试文件 | 测试内容 |
|----------|----------|
| `artifacts_tests.rs:30-42` | `default_runtime_manager_uses_openai_codex_release_base` - 验证默认配置使用正确的 base URL 和版本号 |
| `artifacts_tests.rs:45-65` | `load_cached_runtime_reads_pinned_cache_path` - 验证缓存路径包含版本号 |
| `artifacts_tests.rs:75-85` | `load_cached_runtime_prefers_cached_install` - 验证优先使用已缓存的安装 |

---

## 总结

`codex-rs/core/src/packages` 是一个设计简洁、职责单一的模块。虽然代码量极少（仅 3 行有效代码），但它在整个 artifact 工具链中扮演着关键的"版本锚点"角色。通过与 `codex_artifacts` 和 `codex_package_manager` 的协作，实现了 artifact runtime 的自动下载、缓存和版本管理。

该模块的极简设计体现了良好的软件工程实践：**单一职责原则**和**显式依赖**。版本号的集中定义使得升级维护变得简单明确，同时也便于审计和追踪。
