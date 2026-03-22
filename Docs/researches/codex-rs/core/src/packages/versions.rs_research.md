# codex-rs/core/src/packages/versions.rs 研究文档

## 场景与职责

`versions.rs` 是 Codex 核心库中负责定义 **Artifact 工具运行时固定版本** 的关键文件。在 Codex 架构中，Artifact 是一种允许 AI 通过 JavaScript 代码动态生成内容（如图表、可视化、交互式组件）的机制。

该文件的核心职责：
1. **版本锁定**：定义 Artifact 工具运行时的精确版本号（当前为 `"2.5.6"`）
2. **可复现性保证**：确保所有 Codex 实例使用相同的 Artifact 运行时版本，避免因版本差异导致的行为不一致
3. **缓存定位**：版本号用于构建本地缓存路径（`~/.codex/packages/artifacts/{version}/{platform}/`）

## 功能点目的

### 版本常量定义

```rust
/// Pinned versions for package-manager-backed installs.
pub(crate) const ARTIFACT_RUNTIME: &str = "2.5.6";
```

该常量的设计目的：

| 目的 | 说明 |
|------|------|
| **确定性执行** | 固定版本确保 Artifact 工具行为可预测，不受上游更新影响 |
| **缓存一致性** | 版本号作为缓存键的一部分，避免不同版本间的缓存冲突 |
| **发布追踪** | 对应 GitHub Release 标签 `artifact-runtime-v2.5.6` |
| **回滚能力** | 若新版本出现问题，可通过修改此常量快速回滚 |

### 命名规范

- `ARTIFACT_RUNTIME`：明确指示这是 Artifact 功能的运行时版本，区别于其他可能的运行时（如 REPL 运行时、MCP 运行时）
- 注释 `Pinned versions`：表明这是有意为之的版本锁定，而非疏忽

## 具体技术实现

### 数据结构

该文件仅包含一个字符串常量，无复杂数据结构：

```rust
pub(crate) const ARTIFACT_RUNTIME: &str = "2.5.6";
```

### 版本号格式

当前使用 [SemVer](https://semver.org/) 格式的简化形式 `MAJOR.MINOR.PATCH`：
- `2`：主版本号，重大变更时递增
- `5`：次版本号，功能添加时递增
- `6`：补丁版本号，Bug 修复时递增

### 使用模式

#### 1. 运行时管理器配置

在 `tools/handlers/artifacts.rs` 中：

```rust
fn default_runtime_manager(codex_home: PathBuf) -> ArtifactRuntimeManager {
    ArtifactRuntimeManager::new(ArtifactRuntimeManagerConfig::with_default_release(
        codex_home,
        versions::ARTIFACT_RUNTIME,  // 传递 "2.5.6"
    ))
}
```

#### 2. 本地缓存路径构建

在测试代码中展示的路径构建逻辑：

```rust
let install_dir = codex_home
    .path()
    .join("packages")
    .join("artifacts")
    .join(versions::ARTIFACT_RUNTIME)  // "2.5.6"
    .join(platform.as_str());          // 如 "darwin-arm64"

// 结果路径示例：
// ~/.codex/packages/artifacts/2.5.6/darwin-arm64/
```

#### 3. GitHub Release 定位

版本号用于构建下载 URL：

```
https://github.com/openai/codex/releases/download/artifact-runtime-v2.5.6/artifact-runtime-v2.5.6-manifest.json
```

由 `ArtifactRuntimeReleaseLocator` 在 `codex-rs/artifacts/src/runtime/manager.rs` 中构建：

```rust
pub fn release_tag(&self) -> String {
    format!("{}{}", self.release_tag_prefix, self.runtime_version)
    // 结果："artifact-runtime-v2.5.6"
}
```

## 关键代码路径与文件引用

### 直接调用方

| 文件 | 使用方式 | 上下文 |
|------|----------|--------|
| `codex-rs/core/src/tools/handlers/artifacts.rs:18` | `use crate::packages::versions;` | Artifact 工具处理器导入版本模块 |
| `codex-rs/core/src/tools/handlers/artifacts.rs:217` | `versions::ARTIFACT_RUNTIME` | 创建默认运行时管理器 |
| `codex-rs/core/src/tools/handlers/artifacts_tests.rs:2` | `use crate::packages::versions;` | 测试代码导入版本模块 |
| `codex-rs/core/src/tools/handlers/artifacts_tests.rs:40` | `versions::ARTIFACT_RUNTIME` | 验证运行时版本配置 |
| `codex-rs/core/src/tools/handlers/artifacts_tests.rs:53` | `versions::ARTIFACT_RUNTIME` | 构建测试缓存路径 |
| `codex-rs/core/src/tools/handlers/artifacts_tests.rs:61` | `versions::ARTIFACT_RUNTIME` | 写入测试 package.json |
| `codex-rs/core/src/tools/handlers/artifacts_tests.rs:80` | `versions::ARTIFACT_RUNTIME` | 验证加载的运行时版本 |

### 间接依赖链

```
versions.rs (ARTIFACT_RUNTIME = "2.5.6")
    │
    ▼
artifacts.rs::default_runtime_manager()
    │
    ▼
codex_artifacts::ArtifactRuntimeManager::new(config)
    │
    ▼
codex_artifacts::ArtifactRuntimeReleaseLocator
    │
    ├──► release_tag() → "artifact-runtime-v2.5.6"
    ├──► manifest_url() → ".../artifact-runtime-v2.5.6-manifest.json"
    └──► archive_url() → ".../artifact-runtime-v2.5.6-{platform}.tar.gz"
```

### 相关文件完整列表

| 文件路径 | 相关性 | 说明 |
|----------|--------|------|
| `codex-rs/core/src/packages/mod.rs` | 父模块 | 声明 `versions` 子模块 |
| `codex-rs/core/src/tools/handlers/artifacts.rs` | 直接调用 | 使用版本号创建运行时管理器 |
| `codex-rs/core/src/tools/handlers/artifacts_tests.rs` | 测试验证 | 验证版本号配置和缓存路径 |
| `codex-rs/artifacts/src/runtime/manager.rs` | 间接使用 | 通过参数接收版本号 |
| `codex-rs/artifacts/src/runtime/installed.rs` | 间接使用 | 使用版本号构建缓存路径 |
| `codex-rs/artifacts/src/lib.rs` | 公共 API | 暴露运行时管理类型 |

## 依赖与外部交互

### 内部依赖

该文件无内部依赖，是一个纯常量定义文件。

### 外部系统交互

| 外部系统 | 交互方式 | 说明 |
|----------|----------|------|
| GitHub Releases | HTTP 下载 | 版本号用于构建下载 URL，获取运行时压缩包 |
| 本地文件系统 | 缓存存储 | 版本号作为缓存目录结构的一部分 |
| npm 包 `@oai/artifact-tool` | 版本对应 | 运行时版本与 npm 包版本保持一致 |

### 与 Artifact 子系统的集成

```
┌─────────────────────────────────────────────────────────────────┐
│                      Artifact 子系统架构                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌──────────────┐      versions.rs       ┌──────────────────┐ │
│   │ 工具注册表    │◄──── ARTIFACT_RUNTIME ──┤ 版本定义（本文件） │ │
│   └──────┬───────┘      = "2.5.6"         └──────────────────┘ │
│          │                                                      │
│          ▼                                                      │
│   ┌─────────────────┐    ┌──────────────────┐    ┌───────────┐ │
│   │ ArtifactsHandler │───►│ ArtifactRuntime  │───►│ GitHub    │ │
│   │   (artifacts.rs) │    │    Manager       │    │ Releases  │ │
│   └─────────────────┘    └──────────────────┘    └───────────┘ │
│                                   │                             │
│                                   ▼                             │
│                          ┌──────────────────┐                  │
│                          │ 本地缓存目录      │                  │
│                          │ ~/.codex/packages│                  │
│                          │   /artifacts/2.5.6 │                  │
│                          └──────────────────┘                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 风险、边界与改进建议

### 潜在风险

#### 1. 版本过时风险

**风险描述**：Artifact 运行时版本固定在 "2.5.6"，如果上游 `@oai/artifact-tool` 发布新版本（如 2.6.0），Codex 用户无法自动获得新功能和修复。

**影响评估**：
- 低风险：当前版本稳定，Artifact 功能相对成熟
- 中风险：长期不更新可能积累安全漏洞或兼容性问题

**缓解措施**：
- 定期审查 Artifact 运行时更新日志
- 在发布说明中记录版本锁定决策

#### 2. 版本号硬编码风险

**风险描述**：版本号作为字符串字面量硬编码，缺乏格式验证。

**潜在问题**：
```rust
// 如果误写为：
pub(crate) const ARTIFACT_RUNTIME: &str = "2.5.6-beta";  // 可能导致 URL 构建失败
// 或
pub(crate) const ARTIFACT_RUNTIME: &str = "v2.5.6";      // 重复前缀
```

#### 3. 缓存失效风险

**风险描述**：更新版本号后，旧版本缓存（`~/.codex/packages/artifacts/2.5.6/`）不会自动清理，可能占用磁盘空间。

### 边界情况

| 场景 | 行为 | 处理建议 |
|------|------|----------|
| 版本号对应的 Release 不存在 | `ArtifactRuntimeManager` 返回下载错误 | 提供清晰的错误信息，引导用户检查网络或版本号 |
| 本地缓存损坏 | 运行时加载失败 | 实现缓存校验和自动清理机制 |
| 平台不支持 | `ArtifactRuntimePlatform::detect_current()` 失败 | 优雅降级，禁用 Artifact 功能 |
| 并发下载 | 多个进程同时尝试下载同一版本 | 使用文件锁或原子操作避免冲突 |

### 改进建议

#### 1. 增加版本号验证

```rust
// 建议：增加编译期或运行期版本格式验证
pub(crate) const ARTIFACT_RUNTIME: &str = validate_version("2.5.6");

const fn validate_version(v: &str) -> &str {
    // 验证 SemVer 格式
    assert!(!v.is_empty(), "version must not be empty");
    assert!(!v.starts_with('v'), "version should not start with 'v'");
    v
}
```

#### 2. 支持配置覆盖

```rust
// 建议：允许用户通过配置覆盖默认版本
pub(crate) fn get_artifact_runtime_version(config: &CodexConfig) -> &str {
    config.tools.artifact_runtime_version.as_deref()
        .unwrap_or(ARTIFACT_RUNTIME)
}
```

#### 3. 增加版本更新检查

```rust
// 建议：在启动时异步检查最新版本
pub(crate) async fn check_latest_artifact_runtime() -> Option<String> {
    // 查询 GitHub API 获取最新 release 标签
    // 如果新版本可用，记录日志提示用户
}
```

#### 4. 完善文档注释

```rust
/// Pinned version of the @oai/artifact-tool runtime for artifact generation.
/// 
/// This version is used to:
/// 1. Locate the runtime in the local cache at `~/.codex/packages/artifacts/{version}/`
/// 2. Download the runtime from GitHub releases if not cached
/// 3. Ensure consistent artifact behavior across all Codex installations
/// 
/// The corresponding GitHub release is: 
/// https://github.com/openai/codex/releases/tag/artifact-runtime-v2.5.6
/// 
/// To update this version:
/// 1. Verify the new release exists on GitHub
/// 2. Update this constant
/// 3. Test artifact functionality
/// 4. Document the change in release notes
pub(crate) const ARTIFACT_RUNTIME: &str = "2.5.6";
```

#### 5. 考虑版本矩阵支持

如果未来需要支持多版本运行时：

```rust
// 建议：预留多版本支持接口
pub(crate) struct ArtifactRuntimeVersions {
    pub default: &'static str,
    pub supported: &'static [&'static str],
}

pub(crate) const ARTIFACT_RUNTIMES: ArtifactRuntimeVersions = ArtifactRuntimeVersions {
    default: "2.5.6",
    supported: &["2.5.6", "2.5.5"],  // 向后兼容版本
};
```

### 测试建议

当前测试已覆盖：
- ✅ 版本号在配置中的正确传递
- ✅ 版本号在缓存路径中的正确使用

建议增加：
- ⬜ 版本号格式验证测试
- ⬜ 无效版本号的错误处理测试
- ⬜ 版本升级/降级场景测试
