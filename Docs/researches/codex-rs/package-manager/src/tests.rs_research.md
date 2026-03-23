# tests.rs 研究文档

## 场景与职责

`tests.rs` 是 `codex-package-manager` crate 的测试模块，包含单元测试和集成测试。该模块使用 `wiremock` 模拟 HTTP 服务器，`tempfile` 创建临时目录，全面测试包管理器的各项功能。

### 核心职责
1. **功能测试**：验证核心功能的正确性
2. **集成测试**：测试组件间的协作
3. **并发测试**：验证并发安装的正确性
4. **安全测试**：验证安全限制（路径遍历、符号链接等）
5. **错误处理测试**：验证错误场景的处理

## 功能点目的

### 1. 测试基础设施

#### TestPackage - 测试包类型
```rust
#[derive(Clone, Debug)]
struct TestPackage {
    base_url: Url,
    version: String,
    fail_on_final_install_dir: bool,  // 用于测试验证失败场景
}
```

**设计目的**：
- 实现 `ManagedPackage` trait，作为测试替身
- 可配置的 `fail_on_final_install_dir` 用于模拟验证失败
- 简单的清单结构，易于构造测试数据

#### TestReleaseManifest - 测试清单类型
```rust
#[derive(Clone, Debug, Deserialize)]
struct TestReleaseManifest {
    package_version: String,
    platforms: BTreeMap<String, PackageReleaseArchive>,
}
```

**设计目的**：
- 简单的 JSON 可反序列化结构
- 使用 `BTreeMap` 保证平台条目的确定性顺序

#### TestInstalledPackage - 测试安装包类型
```rust
#[derive(Clone, Debug, PartialEq, Eq)]
struct TestInstalledPackage {
    version: String,
    platform: PackagePlatform,
    root_dir: PathBuf,
}
```

**设计目的**：
- 包含完整的安装信息，便于验证
- 实现 `PartialEq + Eq`，支持断言比较

### 2. ManagedPackage 实现

```rust
impl ManagedPackage for TestPackage {
    type Error = PackageManagerError;
    type Installed = TestInstalledPackage;
    type ReleaseManifest = TestReleaseManifest;

    fn default_cache_root_relative(&self) -> &str { "packages/test-package" }
    fn version(&self) -> &str { &self.version }
    fn manifest_url(&self) -> Result<Url, PackageManagerError> { ... }
    fn archive_url(&self, archive: &PackageReleaseArchive) -> Result<Url, PackageManagerError> { ... }
    fn release_version<'a>(&self, manifest: &'a Self::ReleaseManifest) -> &'a str { ... }
    fn platform_archive(&self, manifest: &Self::ReleaseManifest, platform: PackagePlatform) -> Result<PackageReleaseArchive, Self::Error> { ... }
    fn install_dir(&self, cache_root: &Path, platform: PackagePlatform) -> PathBuf { ... }
    fn installed_version<'a>(&self, package: &'a Self::Installed) -> &'a str { ... }
    fn load_installed(&self, root_dir: PathBuf, platform: PackagePlatform) -> Result<Self::Installed, Self::Error> { ... }
}
```

**关键实现细节**：
- `load_installed` 读取 `manifest.json` 文件内容作为版本
- `fail_on_final_install_dir` 为 true 时，在最终安装目录验证时失败

### 3. 测试用例详解

#### ensure_installed_downloads_and_extracts_zip_package
**目的**：验证完整的 ZIP 包下载和安装流程

**流程**：
1. 启动 `wiremock` 服务器
2. 构造 ZIP 归档（包含 `manifest.json` 和 `bin/tool`）
3. 配置清单和归档的 mock 响应
4. 调用 `ensure_installed()`
5. 验证返回的安装包信息
6. 验证可执行文件权限（Unix）

**验证点**：
- 正确下载清单和归档
- 正确解压 ZIP 文件
- 正确检测包根目录
- 正确保留 Unix 可执行权限

#### resolve_cached_uses_custom_cache_root
**目的**：验证自定义缓存根目录功能

**流程**：
1. 创建自定义缓存目录
2. 手动创建有效的安装目录结构
3. 使用 `with_cache_root` 配置管理器
4. 调用 `resolve_cached()`

**验证点**：
- 从自定义缓存目录解析成功
- 返回正确的安装包信息

#### ensure_installed_replaces_invalid_cached_install
**目的**：验证损坏缓存的自动替换

**流程**：
1. 创建包含错误文件（`broken.txt`）的缓存目录
2. 配置 mock 服务器
3. 调用 `ensure_installed()`

**验证点**：
- 检测到缓存无效（无 `manifest.json`）
- 自动下载并安装新版本
- 旧文件被清理

#### ensure_installed_rejects_manifest_version_mismatch
**目的**：验证清单版本不匹配的错误处理

**流程**：
1. 配置返回不同版本（`0.2.0`）的清单 mock
2. 请求版本 `0.1.0`
3. 调用 `ensure_installed()`

**验证点**：
- 返回 `UnexpectedPackageVersion` 错误
- 错误包含期望和实际版本

#### ensure_installed_serializes_concurrent_installs
**目的**：验证并发安装的正确串行化

**流程**：
1. 配置 mock，期望仅一次清单和归档请求
2. 创建两个共享配置的 `PackageManager` 实例
3. 使用 `Barrier` 确保同时启动
4. 并发调用 `ensure_installed()`

**验证点**：
- 仅执行一次下载（mock 的 `expect(1)`）
- 两个调用都成功返回
- 返回的安装包相同

**技术细节**：
- 使用 `Arc<Barrier>` 同步两个任务
- 验证文件锁的并发控制效果

#### ensure_installed_rejects_unexpected_archive_size
**目的**：验证归档大小验证

**流程**：
1. 构造正确大小的归档
2. 在清单中声明更大的大小
3. 调用 `ensure_installed()`

**验证点**：
- 返回 `UnexpectedArchiveSize` 错误
- 错误包含期望和实际大小

#### staged_install_restore_keeps_previous_install_on_failed_promotion
**目的**：验证提升失败时的回滚机制

**流程**：
1. 创建现有安装目录
2. 调用 `quarantine_existing_install` 隔离
3. 尝试从不存在目录提升（模拟失败）
4. 调用 `restore_quarantined_install` 恢复

**验证点**：
- 隔离成功
- 提升失败
- 恢复成功
- 原安装内容保持完整

#### ensure_installed_restores_previous_install_when_final_validation_fails
**目的**：验证最终验证失败时的完整回滚

**流程**：
1. 创建旧版本（`0.0.9`）的现有安装
2. 配置 mock 返回新版本（`0.1.0`）
3. 使用 `fail_on_final_install_dir: true` 触发验证失败
4. 调用 `ensure_installed()`

**验证点**：
- 返回 `ArchiveExtraction` 错误（由 `fail_on_final_install_dir` 触发）
- 旧版本保持完整
- 隔离目录被清理

#### tar_gz_extraction_supports_default_package_root_detection
**目的**：验证 Tar.gz 解压和包根检测

**流程**：
1. 创建 Tar.gz 归档
2. 调用 `extract_archive`
3. 调用 `detect_single_package_root`

**验证点**：
- Tar.gz 正确解压
- 正确检测包根目录

#### tar_gz_extraction_rejects_symlinks
**目的**：验证 Tar.gz 符号链接拒绝

**流程**：
1. 创建包含符号链接的 Tar.gz 归档
2. 调用 `extract_archive`

**验证点**：
- 返回 `ArchiveExtraction` 错误
- 错误信息包含 "unsupported type"

#### zip_extraction_rejects_parent_paths
**目的**：验证 ZIP 路径遍历防护

**流程**：
1. 创建包含 `../escape.txt` 条目的 ZIP 归档
2. 调用 `extract_archive`

**验证点**：
- 返回 `ArchiveExtraction` 错误
- 错误信息包含 "escapes extraction root"

### 4. 辅助函数

#### build_zip_archive
构造测试用 ZIP 归档：
- 包含 `test-package/manifest.json`
- 包含 `test-package/bin/tool`（Unix 可执行权限 0o755）

#### write_zip_archive_with_parent_path
构造包含路径遍历的 ZIP：
- 包含 `../escape.txt` 条目

#### write_tar_gz_archive
构造测试用 Tar.gz 归档：
- 包含 `test-package/manifest.json`

#### write_tar_gz_archive_with_symlink
构造包含符号链接的 Tar.gz：
- 包含指向 `/tmp/escape` 的符号链接

#### append_tar_file
辅助函数：向 Tar 归档添加文件

## 具体技术实现

### 测试框架

| 工具 | 用途 |
|------|------|
| `tokio::test` | 异步测试运行时 |
| `wiremock` | HTTP mock 服务器 |
| `tempfile::TempDir` | 临时目录 |
| `pretty_assertions::assert_eq` | 美观的断言输出 |

### Mock 配置模式

```rust
Mock::given(method("GET"))
    .and(path(format!("/test-package-v{version}-manifest.json")))
    .respond_with(ResponseTemplate::new(200).set_body_json(&manifest))
    .expect(1)  // 验证仅调用一次
    .mount(&server)
    .await;
```

### 并发测试模式

```rust
let barrier = Arc::new(Barrier::new(2));
let barrier_one = Arc::clone(&barrier);
let barrier_two = Arc::clone(&barrier);

let (first, second) = tokio::join!(
    async {
        barrier_one.wait().await;
        manager_one.ensure_installed().await
    },
    async {
        barrier_two.wait().await;
        manager_two.ensure_installed().await
    },
);
```

### SHA-256 计算

```rust
use sha2::Digest;
use sha2::Sha256;

let archive_sha = format!("{:x}", Sha256::digest(&archive_bytes));
```

## 关键代码路径与文件引用

### 被测试模块

| 模块 | 测试覆盖 |
|------|----------|
| `manager.rs` | `ensure_installed`, `resolve_cached`, 并发控制，回滚 |
| `archive.rs` | `extract_archive`, `detect_single_package_root`, 安全限制 |
| `config.rs` | `with_cache_root` |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `wiremock` | HTTP mock 服务器 |
| `tempfile` | 临时目录管理 |
| `tokio` | 异步运行时 |
| `serde_json` | JSON 构造 |
| `sha2` | SHA-256 计算 |
| `tar` | Tar 归档构造 |
| `zip` | ZIP 归档构造 |
| `flate2` | Gzip 压缩 |
| `pretty_assertions` | 美观的断言输出 |

## 依赖与外部交互

### 测试配置

`Cargo.toml` 中的 dev-dependencies：
```toml
[dev-dependencies]
pretty_assertions = { workspace = true }
serde_json = { workspace = true }
tokio = { workspace = true, features = ["fs", "macros", "rt", "rt-multi-thread"] }
wiremock = { workspace = true }
```

### 条件编译

```rust
#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;
```

Unix 权限测试仅在 Unix 平台编译。

## 风险、边界与改进建议

### 已知风险

1. **平台依赖测试**
   - **风险**：`detect_current()` 依赖当前平台
   - **影响**：某些测试仅在特定平台运行特定代码路径
   - **缓解**：测试覆盖所有平台的核心逻辑

2. **网络依赖**
   - **风险**：`wiremock` 使用本地端口
   - **影响**：端口冲突可能导致测试失败
   - **缓解**：`wiremock` 自动选择可用端口

3. **临时目录清理**
   - **风险**：`TempDir` 在 drop 时清理
   - **影响**：panic 时可能残留临时文件
   - **缓解**：使用 `tempfile` 的自动清理机制

### 边界条件

| 场景 | 测试覆盖 |
|------|----------|
| 空缓存 | `ensure_installed_downloads_and_extracts_zip_package` |
| 损坏缓存 | `ensure_installed_replaces_invalid_cached_install` |
| 版本不匹配 | `ensure_installed_rejects_manifest_version_mismatch` |
| 大小不匹配 | `ensure_installed_rejects_unexpected_archive_size` |
| 并发安装 | `ensure_installed_serializes_concurrent_installs` |
| 提升失败 | `staged_install_restore_keeps_previous_install_on_failed_promotion` |
| 验证失败 | `ensure_installed_restores_previous_install_when_final_validation_fails` |
| 符号链接 | `tar_gz_extraction_rejects_symlinks` |
| 路径遍历 | `zip_extraction_rejects_parent_paths` |

### 改进建议

1. **更多归档格式测试**
   - 添加 Tar.gz 的完整安装流程测试
   - 测试混合格式场景

2. **网络错误测试**
   - 测试超时场景
   - 测试断网重连
   - 测试 HTTP 错误码处理

3. **磁盘满测试**
   - 模拟磁盘空间不足
   - 验证错误处理和清理

4. **权限测试扩展**
   - 测试只读文件系统
   - 测试无权限目录

5. **性能基准测试**
   - 大文件下载和解压性能
   - 并发性能基准

6. **模糊测试**
   - 使用 `cargo-fuzz` 测试归档解析
   - 发现潜在的安全漏洞

7. **属性测试**
   - 使用 `proptest` 生成随机输入
   - 验证属性（如：解压后文件完整性）

8. **平台特定测试**
   - Windows 权限测试
   - macOS 扩展属性测试

### 测试组织

当前所有测试在一个文件中，可考虑按功能拆分：
- `tests/manager_tests.rs` - 管理器功能测试
- `tests/archive_tests.rs` - 归档处理测试
- `tests/concurrent_tests.rs` - 并发测试

### 测试覆盖率

当前测试覆盖：
- ✅ 正常安装流程
- ✅ 缓存解析
- ✅ 自定义缓存根
- ✅ 损坏缓存替换
- ✅ 版本验证
- ✅ 并发控制
- ✅ 归档大小验证
- ✅ 回滚机制
- ✅ Tar.gz 解压
- ✅ 符号链接拒绝
- ✅ 路径遍历防护

潜在未覆盖：
- ❌ 网络超时
- ❌ 磁盘满
- ❌ 权限不足
- ❌ 损坏的归档文件
- ❌ 清单 JSON 解析错误
