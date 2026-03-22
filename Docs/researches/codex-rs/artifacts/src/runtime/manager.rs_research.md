# manager.rs 研究文档

## 场景与职责

`manager.rs` 是 artifact runtime 子系统的核心管理模块，负责协调运行时的下载、安装和缓存管理。它基于 `codex_package_manager` 提供的通用包管理能力，实现了 artifact runtime 特定的下载、验证和安装逻辑。

该文件的核心职责：
1. **发布定位**：构建 artifact runtime 发布的下载 URL
2. **配置管理**：管理运行时管理器的配置参数
3. **安装协调**：委托 package manager 执行实际的下载和安装
4. **平台适配**：处理不同平台（macOS、Linux、Windows）的特定需求

## 功能点目的

### 1. ArtifactRuntimeReleaseLocator

负责构建 artifact runtime 发布的 URL：
- 基础 URL（默认是 GitHub releases）
- 运行时版本
- 发布标签前缀（默认 `"artifact-runtime-v"`）

生成的 URL 格式：
```
{base_url}/{release_tag}/{release_tag}-manifest.json
{base_url}/{release_tag}/{archive_name}
```

### 2. ArtifactRuntimeManagerConfig

配置运行时管理器的行为：
- `codex_home`: Codex 主目录
- `release`: 发布定位器
- `cache_root`: 缓存根目录（可选，默认 `~/.codex/packages/artifacts`）

### 3. ArtifactRuntimeManager

运行时管理器的主入口，提供：
- `resolve_cached()`: 检查本地缓存
- `ensure_installed()`: 确保运行时已安装（下载如果需要）

### 4. ArtifactRuntimePackage（内部 trait 实现）

实现 `ManagedPackage` trait，提供 artifact runtime 特定的逻辑：
- 版本解析
- 平台特定的归档选择
- 安装目录计算
- 运行时根目录检测

## 具体技术实现

### 常量定义

```rust
/// Release tag prefix used for artifact runtime assets.
pub const DEFAULT_RELEASE_TAG_PREFIX: &str = "artifact-runtime-v";

/// Relative cache root for installed artifact runtimes under `codex_home`.
pub const DEFAULT_CACHE_ROOT_RELATIVE: &str = "packages/artifacts";

/// Base URL used by default when downloading runtime assets from GitHub releases.
pub const DEFAULT_RELEASE_BASE_URL: &str = "https://github.com/openai/codex/releases/download/";
```

### URL 构建

```rust
impl ArtifactRuntimeReleaseLocator {
    pub fn release_tag(&self) -> String {
        format!("{}{}", self.release_tag_prefix, self.runtime_version)
    }

    pub fn manifest_url(&self) -> Result<Url, PackageManagerError> {
        self.base_url
            .join(&format!(
                "{}/{}",
                self.release_tag(),
                self.manifest_file_name()
            ))
            .map_err(PackageManagerError::InvalidBaseUrl)
    }
}
```

示例 URL：
```
https://github.com/openai/codex/releases/download/artifact-runtime-v0.1.0/artifact-runtime-v0.1.0-manifest.json
```

### ManagedPackage trait 实现

```rust
impl ManagedPackage for ArtifactRuntimePackage {
    type Error = ArtifactRuntimeError;
    type Installed = InstalledArtifactRuntime;
    type ReleaseManifest = ReleaseManifest;

    fn version(&self) -> &str {
        self.release.runtime_version()
    }

    fn platform_archive(
        &self,
        manifest: &Self::ReleaseManifest,
        platform: ArtifactRuntimePlatform,
    ) -> Result<PackageReleaseArchive, Self::Error> {
        manifest
            .platforms
            .get(platform.as_str())
            .cloned()
            .ok_or_else(|| {
                PackageManagerError::MissingPlatform(platform.as_str().to_string()).into()
            })
    }

    fn install_dir(&self, cache_root: &Path, platform: ArtifactRuntimePlatform) -> PathBuf {
        cache_root.join(self.version()).join(platform.as_str())
    }

    fn load_installed(
        &self,
        root_dir: PathBuf,
        platform: ArtifactRuntimePlatform,
    ) -> Result<Self::Installed, Self::Error> {
        InstalledArtifactRuntime::load(root_dir, platform)
    }

    fn detect_extracted_root(&self, extraction_root: &Path) -> Result<PathBuf, Self::Error> {
        detect_runtime_root(extraction_root)
    }
}
```

### 安装流程

```rust
impl ArtifactRuntimeManager {
    pub async fn ensure_installed(&self) -> Result<InstalledArtifactRuntime, ArtifactRuntimeError> {
        self.package_manager.ensure_installed().await
    }
}
```

实际的安装逻辑委托给 `PackageManager::ensure_installed()`，包括：
1. 检查本地缓存
2. 获取文件锁（避免并发安装冲突）
3. 下载 manifest
4. 下载平台特定的归档
5. 验证校验和
6. 解压归档
7. 验证安装
8. 提升到最终位置

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/artifacts/src/runtime/manager.rs` (255 行)

### 依赖文件
- `/home/sansha/Github/codex/codex-rs/package-manager/src/manager.rs` - `PackageManager` 实现
- `/home/sansha/Github/codex/codex-rs/package-manager/src/package.rs` - `ManagedPackage` trait
- `/home/sansha/Github/codex/codex-rs/package-manager/src/config.rs` - `PackageManagerConfig`
- `/home/sansha/Github/codex/codex-rs/artifacts/src/runtime/error.rs` - 错误类型
- `/home/sansha/Github/codex/codex-rs/artifacts/src/runtime/installed.rs` - `InstalledArtifactRuntime`
- `/home/sansha/Github/codex/codex-rs/artifacts/src/runtime/manifest.rs` - `ReleaseManifest`

### 调用方文件
- `/home/sansha/Github/codex/codex-rs/artifacts/src/lib.rs` - 导出公共 API
- `/home/sansha/Github/codex/codex-rs/artifacts/src/client.rs` - `ArtifactsClient` 使用管理器
- `/home/sansha/Github/codex/codex-rs/artifacts/src/tests.rs` - 单元测试
- `/home/sansha/Github/codex/codex-rs/core/src/tools/handlers/artifacts.rs` - 核心工具处理器

### 关键调用链

```
ArtifactsHandler::handle (in core)
    -> ArtifactsClient::from_runtime_manager
        -> ArtifactRuntimeManager::new
            -> ArtifactRuntimeManagerConfig::with_default_release
    -> client.execute_build
        -> runtime.resolve_runtime
            -> ArtifactRuntimeManager::ensure_installed
                -> PackageManager::ensure_installed
                    -> fetch_release_manifest
                    -> download_bytes
                    -> extract_archive
                    -> ArtifactRuntimePackage::load_installed
                        -> InstalledArtifactRuntime::load
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `reqwest::Client` | HTTP 客户端（通过 PackageManager） |
| `url::Url` | URL 解析和构建 |
| `codex_package_manager` | 通用包管理功能 |
| `tokio` | 异步运行时 |

### 模块关系

```
manager.rs
    |
    +-- uses package-manager/manager.rs (PackageManager)
    |
    +-- uses package-manager/package.rs (ManagedPackage trait)
    |
    +-- uses package-manager/config.rs (PackageManagerConfig)
    |
    +-- uses error.rs (ArtifactRuntimeError)
    |
    +-- uses installed.rs (InstalledArtifactRuntime, detect_runtime_root)
    |
    +-- uses manifest.rs (ReleaseManifest)
    |
    +-- exported by lib.rs (ArtifactRuntimeManager, ArtifactRuntimeManagerConfig, etc.)
    |
    +-- used by client.rs (ArtifactsClient)
    |
    +-- used by core/tools/handlers/artifacts.rs (ArtifactsHandler)
```

### 版本常量

在 `core/src/packages/versions.rs` 中定义了 artifact runtime 的版本：
```rust
pub const ARTIFACT_RUNTIME: &str = env!("ARTIFACT_RUNTIME_VERSION");
```

这个版本号在构建时通过环境变量注入，用于确定要下载的 runtime 版本。

## 风险、边界与改进建议

### 当前风险

1. **网络依赖**：首次安装需要网络连接，且依赖 GitHub releases 的可用性
2. **版本锁定**：版本号在编译时确定，无法动态更新
3. **单点故障**：默认使用单一的 GitHub releases 源
4. **并发安装**：虽然有文件锁，但锁超时处理可能不够健壮

### 边界情况

1. **磁盘空间不足**：下载和解压过程中可能耗尽磁盘空间
2. **网络中断**：大文件下载过程中网络中断需要重新下载
3. **权限问题**：缓存目录可能没有写入权限
4. **代理环境**：企业环境可能需要 HTTP 代理配置
5. **版本回滚**：安装新版本后，旧版本被替换，没有版本回滚机制

### 改进建议

1. **支持镜像源**：
   ```rust
   pub struct ArtifactRuntimeReleaseLocator {
       primary_url: Url,
       mirror_urls: Vec<Url>,
       // ...
   }
   
   impl ArtifactRuntimeReleaseLocator {
       pub async fn try_mirrors(&self) -> Result<Url, ArtifactRuntimeError> {
           // 尝试多个镜像源
       }
   }
   ```

2. **断点续传**：
   ```rust
   pub async fn download_with_resume(
       &self,
       url: &Url,
       partial_file: &Path,
   ) -> Result<Vec<u8>, ArtifactRuntimeError> {
       // 支持 HTTP Range 请求
   }
   ```

3. **版本管理**：
   ```rust
   impl ArtifactRuntimeManager {
       pub async fn list_installed_versions(&self) -> Vec<String> { ... }
       
       pub async fn switch_version(&self, version: &str) -> Result<(), ArtifactRuntimeError> { ... }
       
       pub async fn uninstall_version(&self, version: &str) -> Result<(), ArtifactRuntimeError> { ... }
   }
   ```

4. **离线模式支持**：
   ```rust
   pub struct ArtifactRuntimeManagerConfig {
       offline_mode: bool,
       local_archive_path: Option<PathBuf>,
       // ...
   }
   ```

5. **下载进度回调**：
   ```rust
   pub trait DownloadProgress {
       fn on_progress(&self, downloaded: u64, total: u64);
       fn on_complete(&self);
       fn on_error(&self, error: &ArtifactRuntimeError);
   }
   
   impl ArtifactRuntimeManager {
       pub async fn ensure_installed_with_progress(
           &self,
           progress: &dyn DownloadProgress,
       ) -> Result<InstalledArtifactRuntime, ArtifactRuntimeError> { ... }
   }
   ```

6. **健康检查和自修复**：
   ```rust
   impl ArtifactRuntimeManager {
       pub async fn verify_installation(&self) -> Result<VerificationReport, ArtifactRuntimeError> {
           // 验证文件完整性
           // 检查校验和
           // 测试运行时可用性
       }
       
       pub async fn repair_installation(&self) -> Result<(), ArtifactRuntimeError> {
           // 删除损坏的文件
           // 重新下载
       }
   }
   ```

7. **配置热重载**：
   ```rust
   impl ArtifactRuntimeManagerConfig {
       pub fn reload(&mut self) -> Result<(), ArtifactRuntimeError> {
           // 从配置文件重新加载
       }
   }
   ```

8. **审计日志**：
   ```rust
   pub struct InstallationEvent {
       pub timestamp: SystemTime,
       pub version: String,
       pub source: Url,
       pub duration: Duration,
       pub success: bool,
   }
   ```
