# package.rs 研究文档

## 场景与职责

`package.rs` 定义了 `ManagedPackage` trait，这是 `codex-package-manager` crate 的核心抽象接口。该 trait 定义了包管理器与具体包类型之间的契约，允许包管理器以统一的方式处理不同类型的包（如 artifact runtime、工具链等）。

### 核心职责
1. **抽象接口定义**：定义包类型必须实现的方法
2. **契约规范**：文档化实现者必须遵守的不变式
3. **默认实现**：提供通用的默认行为（如 `detect_extracted_root`）

## 功能点目的

### 1. ManagedPackage Trait - 托管包契约

```rust
pub trait ManagedPackage: Clone {
    type Error: From<PackageManagerError>;
    type Installed: Clone;
    type ReleaseManifest: DeserializeOwned;

    fn default_cache_root_relative(&self) -> &str;
    fn version(&self) -> &str;
    fn manifest_url(&self) -> Result<Url, PackageManagerError>;
    fn archive_url(&self, archive: &PackageReleaseArchive) -> Result<Url, PackageManagerError>;
    fn release_version<'a>(&self, manifest: &'a Self::ReleaseManifest) -> &'a str;
    fn platform_archive(
        &self,
        manifest: &Self::ReleaseManifest,
        platform: PackagePlatform,
    ) -> Result<PackageReleaseArchive, Self::Error>;
    fn install_dir(&self, cache_root: &Path, platform: PackagePlatform) -> PathBuf;
    fn installed_version<'a>(&self, package: &'a Self::Installed) -> &'a str;
    fn load_installed(
        &self,
        root_dir: PathBuf,
        platform: PackagePlatform,
    ) -> Result<Self::Installed, Self::Error>;
    fn detect_extracted_root(&self, extraction_root: &Path) -> Result<PathBuf, Self::Error> {
        detect_single_package_root(extraction_root).map_err(Self::Error::from)
    }
}
```

### 2. 关联类型详解

| 关联类型 | 约束 | 用途 |
|----------|------|------|
| `Error` | `From<PackageManagerError>` | 包特定的错误类型，必须能从通用错误转换 |
| `Installed` | `Clone` | 表示已安装包的类型，包管理器会克隆它 |
| `ReleaseManifest` | `DeserializeOwned` | 发布清单类型，需支持 JSON 反序列化 |

### 3. 必需方法详解

#### default_cache_root_relative
```rust
fn default_cache_root_relative(&self) -> &str;
```
- 返回相对于 Codex home 的缓存根目录
- 应使用正斜杠 `/`，由配置模块转换为平台分隔符
- **不变式**：必须返回相对路径，不含 `..`

#### version
```rust
fn version(&self) -> &str;
```
- 返回请求的包版本
- 用于与清单中的版本和已安装包的版本比较

#### manifest_url
```rust
fn manifest_url(&self) -> Result<Url, PackageManagerError>;
```
- 返回发布清单的完整 URL
- 通常基于基础 URL 和版本构造

#### archive_url
```rust
fn archive_url(&self, archive: &PackageReleaseArchive) -> Result<Url, PackageManagerError>;
```
- 返回归档文件的下载 URL
- **契约**：应从清单数据派生，而非重新计算

#### release_version
```rust
fn release_version<'a>(&self, manifest: &'a Self::ReleaseManifest) -> &'a str;
```
- 从清单中提取版本字符串
- 用于验证清单与请求版本匹配

#### platform_archive
```rust
fn platform_archive(
    &self,
    manifest: &Self::ReleaseManifest,
    platform: PackagePlatform,
) -> Result<PackageReleaseArchive, Self::Error>;
```
- 从清单中选择指定平台的归档
- 失败时返回 `MissingPlatform` 错误

#### install_dir
```rust
fn install_dir(&self, cache_root: &Path, platform: PackagePlatform) -> PathBuf;
```
- 返回最终安装目录路径
- **不变式**：必须对版本和平台唯一，避免冲突

#### installed_version
```rust
fn installed_version<'a>(&self, package: &'a Self::Installed) -> &'a str;
```
- 从已安装包中提取版本
- 用于验证缓存中的包版本正确

#### load_installed
```rust
fn load_installed(
    &self,
    root_dir: PathBuf,
    platform: PackagePlatform,
) -> Result<Self::Installed, Self::Error>;
```
- 从磁盘加载并验证已安装的包
- **契约**：必须完全验证包的有效性
- 失败时返回错误（会被视为缓存未命中）

### 4. 默认方法

#### detect_extracted_root
```rust
fn detect_extracted_root(&self, extraction_root: &Path) -> Result<PathBuf, Self::Error> {
    detect_single_package_root(extraction_root).map_err(Self::Error::from)
}
```
- 默认实现使用 `archive::detect_single_package_root`
- 支持两种布局：
  - 直接包含 `manifest.json`
  - 单层子目录包含 `manifest.json`
- 可覆盖以支持自定义布局

## 具体技术实现

### Trait 约束

```rust
pub trait ManagedPackage: Clone { ... }
```

`Clone` 约束确保：
- 配置可以在多处克隆
- 包管理器可以克隆包实例

### 生命周期设计

```rust
fn release_version<'a>(&self, manifest: &'a Self::ReleaseManifest) -> &'a str;
fn installed_version<'a>(&self, package: &'a Self::Installed) -> &'a str;
```

使用显式生命周期：
- 允许返回对传入参数的引用
- 避免不必要的克隆

## 关键代码路径与文件引用

### 内部依赖

| 模块 | 使用内容 |
|------|----------|
| `archive` | `detect_single_package_root` |
| `error` | `PackageManagerError` |
| `platform` | `PackagePlatform` |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `serde` | `DeserializeOwned` trait |
| `url` | `Url` 类型 |

### 实现示例

**TestPackage**（来自 tests.rs）：
```rust
impl ManagedPackage for TestPackage {
    type Error = PackageManagerError;
    type Installed = TestInstalledPackage;
    type ReleaseManifest = TestReleaseManifest;

    fn default_cache_root_relative(&self) -> &str { "packages/test-package" }
    fn version(&self) -> &str { &self.version }
    fn manifest_url(&self) -> Result<Url, PackageManagerError> { ... }
    fn archive_url(&self, archive: &PackageReleaseArchive) -> Result<Url, PackageManagerError> { ... }
    fn release_version<'a>(&self, manifest: &'a Self::ReleaseManifest) -> &'a str { &manifest.package_version }
    fn platform_archive(&self, manifest: &Self::ReleaseManifest, platform: PackagePlatform) -> Result<PackageReleaseArchive, Self::Error> { ... }
    fn install_dir(&self, cache_root: &Path, platform: PackagePlatform) -> PathBuf { ... }
    fn installed_version<'a>(&self, package: &'a Self::Installed) -> &'a str { &package.version }
    fn load_installed(&self, root_dir: PathBuf, platform: PackagePlatform) -> Result<Self::Installed, Self::Error> { ... }
}
```

**ArtifactRuntimePackage**（来自 artifacts/src/runtime/manager.rs）：
```rust
impl ManagedPackage for ArtifactRuntimePackage {
    type Error = ArtifactRuntimeError;
    type Installed = InstalledArtifactRuntime;
    type ReleaseManifest = ReleaseManifest;

    fn default_cache_root_relative(&self) -> &str { DEFAULT_CACHE_ROOT_RELATIVE }
    fn version(&self) -> &str { self.release.runtime_version() }
    fn manifest_url(&self) -> Result<Url, PackageManagerError> { self.release.manifest_url() }
    fn archive_url(&self, archive: &PackageReleaseArchive) -> Result<Url, PackageManagerError> { ... }
    fn release_version<'a>(&self, manifest: &'a Self::ReleaseManifest) -> &'a str { &manifest.runtime_version }
    fn platform_archive(&self, manifest: &Self::ReleaseManifest, platform: ArtifactRuntimePlatform) -> Result<PackageReleaseArchive, Self::Error> { ... }
    fn install_dir(&self, cache_root: &Path, platform: ArtifactRuntimePlatform) -> PathBuf { ... }
    fn installed_version<'a>(&self, package: &'a Self::Installed) -> &'a str { package.runtime_version() }
    fn load_installed(&self, root_dir: PathBuf, platform: ArtifactRuntimePlatform) -> Result<Self::Installed, Self::Error> { InstalledArtifactRuntime::load(root_dir, platform) }
    fn detect_extracted_root(&self, extraction_root: &Path) -> Result<PathBuf, Self::Error> { detect_runtime_root(extraction_root) }
}
```

## 依赖与外部交互

### 调用方

| Crate | 使用方式 |
|-------|----------|
| `codex-artifacts` | 实现 `ManagedPackage` for `ArtifactRuntimePackage` |
| `codex-package-manager` (tests) | 实现 `ManagedPackage` for `TestPackage` |

### Trait 使用

**在 manager.rs 中**：
```rust
impl<P: ManagedPackage> PackageManager<P> {
    pub async fn ensure_installed(&self) -> Result<P::Installed, P::Error> { ... }
}
```

包管理器的所有操作都通过 `ManagedPackage` trait 进行。

## 风险、边界与改进建议

### 已知风险

1. **契约违反**
   - **风险**：实现者可能违反文档化的不变式
   - **缓解**：文档清晰，但无运行时检查
   - **示例**：`install_dir` 返回非唯一路径可能导致冲突

2. **错误转换丢失信息**
   - **风险**：`From<PackageManagerError>` 转换可能丢失上下文
   - **现状**：简单包装通常足够

3. **生命周期复杂性**
   - **风险**：`'a` 生命周期可能使实现复杂
   - **现状**：通常直接返回字段引用，实现简单

### 边界条件

| 场景 | 行为 |
|------|------|
| `load_installed` 返回 Ok | 视为有效缓存，直接使用 |
| `load_installed` 返回 Err | 视为缓存未命中，触发重新安装 |
| `platform_archive` 返回 Err | 安装失败，返回错误 |
| 版本不匹配 | `ensure_installed` 返回 `UnexpectedPackageVersion` |

### 改进建议

1. **验证宏**
   - 提供 `#[derive(ManagedPackage)]` 宏
   - 自动生成样板代码

2. **不变式检查**
   - 在调试构建中添加运行时检查
   - 例如：验证 `install_dir` 返回的路径包含版本和平台

3. **文档测试**
   - 添加 doc tests 展示正确用法
   - 确保文档中的代码示例可编译运行

4. **关联类型默认值**
   - 考虑为 `Error` 提供默认类型
   - 简化简单场景的实现

5. **异步支持**
   - 当前 `load_installed` 是同步的
   - 考虑添加异步变体 `load_installed_async`

6. **版本比较**
   - 当前使用字符串相等比较
   - 可考虑使用 `semver::Version` 进行语义化版本比较

7. **能力标记**
   - 添加可选的能力 trait
   - 例如：`Upgradeable`、`Rollbackable`

### 设计模式

**模板方法模式**：
- `detect_extracted_root` 提供默认实现
- 实现者可覆盖以自定义行为

**类型状态模式**（潜在）：
- 可考虑使用类型状态确保正确的调用顺序
- 例如：`Uninstalled` -> `Downloaded` -> `Installed`

### 与 README 的关系

README 中的 "ManagedPackage Contract" 节详细描述了实现契约：
- `install_dir` 唯一性要求
- `load_installed` 验证要求
- `detect_extracted_root` 默认行为
- `archive_url` 派生要求

这些文档与代码注释保持一致。
