# codex-rs/package-manager/README.md 研究文档

## 场景与职责

`README.md` 是 `codex-package-manager` crate 的用户文档，面向开发者和使用者说明该 crate 的设计目标、核心概念、使用方式和扩展方法。

该文档的核心职责：
- 阐述 crate 的定位：共享安装器，用于版本化运行时包和其他缓存工件
- 说明核心功能：平台检测、manifest 获取、归档下载、校验验证、提取安装
- 定义 `ManagedPackage` trait 契约
- 提供消费者指导和扩展示例
- 说明安全性和提取规则

## 功能点目的

### 1. 定位说明

```markdown
`codex-package-manager` is the shared installer used for versioned runtime bundles 
and other cached artifacts in `codex-rs`.
```

明确该 crate 的角色：
- **共享安装器**：被多个上层 crate 复用，避免重复实现
- **版本化运行时包**：主要用例是管理 Artifact Runtime（如 JS 运行时）
- **缓存工件**：支持本地缓存，避免重复下载

### 2. 核心功能列表

| 功能 | 说明 | 对应源码 |
|------|------|----------|
| current-platform detection | 检测当前 OS/架构组合 | `platform.rs` - `PackagePlatform::detect_current()` |
| manifest and archive fetches | 从远程获取 manifest 和归档 | `manager.rs` - `fetch_release_manifest()`, `download_bytes()` |
| checksum and archive-size validation | SHA-256 和大小校验 | `archive.rs` - `verify_sha256()`, `verify_archive_size()` |
| archive extraction (.zip, .tar.gz) | 归档提取 | `archive.rs` - `extract_archive()` |
| staging and promotion | 暂存和提升到缓存目录 | `manager.rs` - `ensure_installed()` 中的 staging 逻辑 |
| cross-process install locking | 跨进程安装锁 | `manager.rs` - `fd-lock` + `try_write()` 循环 |

### 3. ManagedPackage Trait 契约

文档详细说明了实现 `ManagedPackage` trait 时需要遵守的约定：

| 方法 | 契约要求 | 违反后果 |
|------|----------|----------|
| `install_dir()` | 必须对版本和平台唯一 | 并发版本覆盖，清理不安全 |
| `load_installed()` | 必须完全验证已安装包 | 缓存解析信任成功加载为有效缓存 |
| `detect_extracted_root()` | 默认查找 `manifest.json` | 包布局不同时需覆盖 |
| `archive_url()` | 从 manifest 数据派生 | manifest 选择和下载不一致 |

### 4. 消费者指导

文档提供了三条关键指导：

1. **不要仅依赖预安装检查**：
   - `resolve_cached()` 只回答"是否已存在"
   - `ensure_installed()` 是引导路径
   - 功能注册不应仅基于缓存检查

2. **缓存根覆盖**：
   - 在 manager/config 层面处理
   - 避免单独的 helper 重建安装路径

3. **调试建议**：
   - 从 `load_installed()` 暴露包特定的验证失败
   - 通用 manager 将失败的缓存加载视为缓存未命中

### 5. 安全性和提取规则

| 归档类型 | 安全规则 |
|----------|----------|
| `.zip` | 拒绝逃逸提取根的路径；保留 Unix 可执行位 |
| `.tar.gz` | 拒绝符号链接、硬链接、稀疏文件、设备文件、FIFO；仅允许常规文件和目录 |
| 通用 | 始终验证 SHA-256；如果 manifest 提供 `size_bytes` 则强制执行 |

## 具体技术实现

### 架构模型

文档描述的简化模型（对应源码实现）：

```
┌─────────────────────────────────────────────────────────────┐
│                    PackageManager<P>                         │
│  ┌─────────────────┐        ┌─────────────────────────────┐ │
│  │ resolve_cached()│        │      ensure_installed()     │ │
│  │  - 检查缓存存在  │        │  1. 调用 resolve_cached()   │ │
│  │  - 加载验证包   │        │  2. 获取文件锁               │ │
│  │  - 版本匹配检查 │        │  3. 再次检查缓存             │ │
│  └─────────────────┘        │  4. 获取 manifest           │ │
│                             │  5. 下载归档                 │ │
│                             │  6. 校验验证                 │ │
│                             │  7. 提取到 staging           │ │
│                             │  8. 加载验证                 │ │
│                             │  9. 隔离旧安装               │ │
│                             │ 10. 提升到缓存               │ │
│                             │ 11. 最终验证                 │ │
│                             │ 12. 清理隔离目录             │ │
│                             └─────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    ManagedPackage (Trait)                    │
│  - manifest_url()    - platform_archive()   - install_dir() │
│  - archive_url()     - load_installed()     - version()     │
│  - release_version() - installed_version()  - ...           │
└─────────────────────────────────────────────────────────────┘
```

### 默认缓存根路径

```
<codex_home>/<default_cache_root_relative>
```

示例（Artifact Runtime）：
```
~/.codex/packages/artifacts/0.1.0/linux-x64/
```

对应源码：
- `config.rs` - `cache_root()` 方法
- `manager.rs` - `ArtifactRuntimePackage::default_cache_root_relative()` 返回 `"packages/artifacts"`

### 典型使用模式

文档提供的示例代码：

```rust
let config = PackageManagerConfig::new(codex_home, MyPackage::new(...));
let manager = PackageManager::new(config);
let package = manager.ensure_installed().await?;
```

实际使用（来自 `artifacts` crate）：

```rust
// artifacts/src/runtime/manager.rs
let config = ArtifactRuntimeManagerConfig::new(
    codex_home,
    ArtifactRuntimeReleaseLocator::default(runtime_version),
);
let manager = ArtifactRuntimeManager::new(config);
let runtime = manager.ensure_installed().await?;
```

## 关键代码路径与文件引用

### 核心实现文件

```
codex-rs/package-manager/src/
├── lib.rs              # 公共 API 导出
├── manager.rs          # PackageManager 实现（464 行）
│   ├── resolve_cached()
│   ├── ensure_installed()  # 主要安装逻辑
│   ├── resolve_cached_at()
│   ├── fetch_release_manifest()
│   ├── download_bytes()
│   ├── quarantine_existing_install()
│   ├── promote_staged_install()
│   └── restore_quarantined_install()
├── package.rs          # ManagedPackage trait 定义（69 行）
├── archive.rs          # 归档处理（270 行）
│   ├── PackageReleaseArchive
│   ├── ArchiveFormat
│   ├── extract_archive()
│   ├── extract_zip_archive()
│   ├── extract_tar_gz_archive()
│   ├── verify_sha256()
│   ├── verify_archive_size()
│   └── detect_single_package_root()
├── config.rs           # PackageManagerConfig（40 行）
├── platform.rs         # PackagePlatform 枚举（48 行）
├── error.rs            # PackageManagerError（54 行）
└── tests.rs            # 单元测试和集成测试（700 行）
```

### 消费者实现示例

```
codex-rs/artifacts/src/runtime/
├── manager.rs          # ArtifactRuntimeManager 实现
│   ├── ArtifactRuntimeReleaseLocator
│   ├── ArtifactRuntimeManagerConfig
│   ├── ArtifactRuntimeManager
│   └── ArtifactRuntimePackage (impl ManagedPackage)
├── installed.rs        # InstalledArtifactRuntime
├── manifest.rs         # ReleaseManifest
├── js_runtime.rs       # JS 运行时检测和选择
└── error.rs            # ArtifactRuntimeError
```

## 依赖与外部交互

### 内部模块依赖图

```
lib.rs
├── archive.rs ◄────── manager.rs
├── config.rs ◄─────── manager.rs
├── error.rs ◄──────── manager.rs, archive.rs, platform.rs
├── manager.rs ◄────── lib.rs (pub use)
├── package.rs ◄────── manager.rs, config.rs
├── platform.rs ◄───── manager.rs, package.rs
└── tests.rs ◄──────── (测试所有模块)
```

### 外部 crate 依赖

| 依赖 | 用途 | 使用位置 |
|------|------|----------|
| `fd-lock` | 跨进程文件锁 | `manager.rs:94` |
| `reqwest` | HTTP 客户端 | `manager.rs:9, 326-381` |
| `tokio` | 异步运行时 | 全文件 |
| `serde` | 序列化 | `archive.rs:15-25`, `package.rs:28` |
| `sha2` | SHA-256 哈希 | `archive.rs:88-97` |
| `zip` | zip 提取 | `archive.rs:110-152` |
| `tar` + `flate2` | tar.gz 提取 | `archive.rs:178-247` |
| `tempfile` | 临时目录 | `manager.rs:157` |
| `url` | URL 处理 | `manager.rs:17`, `package.rs:8` |
| `thiserror` | 错误定义 | `error.rs:5` |

### 消费者

| 消费者 | 使用方式 | 文件 |
|--------|----------|------|
| `codex-rs/artifacts` | 实现 `ManagedPackage` trait | `artifacts/src/runtime/manager.rs:190-255` |

## 风险、边界与改进建议

### 风险

1. **文档与实现不同步**：
   - README 提到 "The default `detect_extracted_root()` looks for `manifest.json`..."
   - 实际实现 `detect_single_package_root()` 在 `archive.rs:39-72`
   - 风险：如果实现变更而文档未更新，会导致消费者困惑

2. **安全规则依赖外部 crate**：
   - zip 路径逃逸检查依赖 `zip::read::ZipFile::enclosed_name()`
   - 如果 `zip` crate 有漏洞，安全边界可能被突破
   - 建议：定期审计 `zip` 和 `tar` crate 的安全公告

3. **缓存污染风险**：
   - 文档说明 `load_installed()` 失败会被视为缓存未命中
   - 但如果 `load_installed()` 部分成功（如文件句柄泄漏），可能导致未定义行为

### 边界

1. **单平台限制**：
   - `PackagePlatform` 仅支持 6 种平台组合（Darwin/Linux/Windows × ARM64/X64）
   - 不支持 32 位系统、BSD、或其他架构

2. **HTTP -only**：
   - 仅支持 HTTP/HTTPS 下载
   - 不支持本地文件、FTP、或其他协议

3. **无并发下载优化**：
   - 文档未提及分块下载、断点续传、或并发下载
   - 大文件下载可能效率低下

4. **无缓存清理策略**：
   - 文档提到 "cleanup become unsafe" 但未提供清理机制
   - 长期运行可能导致磁盘空间无限增长

### 改进建议

1. **文档改进**：
   - 添加架构图说明组件关系
   - 提供 `ManagedPackage` 实现的完整示例
   - 添加故障排除指南（如缓存损坏如何处理）

2. **功能增强**：
   - 添加下载进度回调支持：
     ```rust
     pub trait ManagedPackage: Clone {
         fn on_download_progress(&self, bytes_downloaded: u64, total_bytes: u64) {}
     }
     ```
   - 支持并发下载（Range 请求）
   - 添加缓存清理 API（如 `manager.cleanup_old_versions(keep_last_n: usize)`）

3. **安全加固**：
   - 添加归档深度限制（防止 zip bomb）
   - 添加文件大小上限检查
   - 考虑使用 `async-compression` 替代同步压缩库

4. **可观测性**：
   - 添加结构化日志（`tracing` 集成）
   - 暴露安装指标（下载时间、校验时间、提取时间）
   - 添加缓存命中率统计

5. **API 改进**：
   - 考虑添加 `update_available()` 检查新版本
   - 支持强制重新下载（绕过缓存）
   - 添加取消支持（`CancellationToken`）

6. **测试覆盖**：
   - 当前测试主要覆盖正常路径
   - 建议添加更多边界情况测试：
     - 网络中断恢复
     - 磁盘满错误处理
     - 并发安装竞争条件
     - 损坏的归档文件
