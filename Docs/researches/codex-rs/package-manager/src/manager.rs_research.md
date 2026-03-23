# manager.rs 研究文档

## 场景与职责

`manager.rs` 是 `codex-package-manager` crate 的核心模块，实现了 `PackageManager` 结构体及其方法。该模块负责协调包的下载、验证、解压和安装全过程，是包管理器的主要对外接口。

### 核心职责
1. **缓存解析**：检查并验证已缓存的包安装
2. **并发控制**：通过文件锁实现跨进程安装串行化
3. **下载管理**：从远程获取清单和归档文件
4. **安全安装**：使用 staging-promotion 模式确保原子性安装
5. **错误恢复**：安装失败时回滚到之前的有效状态

## 功能点目的

### 1. PackageManager - 包管理器结构体

```rust
#[derive(Clone, Debug)]
pub struct PackageManager<P> {
    client: Client,                    // HTTP 客户端
    config: PackageManagerConfig<P>,   // 配置（包含包类型实例）
}
```

**设计考量**：
- 泛型参数 `P: ManagedPackage` 允许管理不同类型的包
- 使用 `reqwest::Client` 进行 HTTP 通信，支持连接复用
- 实现 `Clone`，允许在多个异步任务间共享

### 2. 构造函数

```rust
pub fn new(config: PackageManagerConfig<P>) -> Self
pub fn with_client(config: PackageManagerConfig<P>, client: Client) -> Self
```

**使用场景**：
- `new`：常规使用，创建默认 HTTP 客户端
- `with_client`：需要自定义 HTTP 客户端配置（如超时、代理）

### 3. resolve_cached - 缓存解析

```rust
pub async fn resolve_cached(&self) -> Result<Option<P::Installed>, P::Error>
```

**执行流程**：
1. 检测当前平台
2. 计算安装目录路径
3. 调用 `resolve_cached_at` 执行实际检查

**设计目的**：
- 快速路径：无需网络即可确定包是否可用
- 支持预热检查，避免在关键路径上阻塞

### 4. resolve_cached_at - 实际缓存检查

```rust
async fn resolve_cached_at(
    &self,
    platform: PackagePlatform,
    install_dir: PathBuf,
) -> Result<Option<P::Installed>, P::Error>
```

**验证逻辑**：
1. 检查安装目录是否存在
2. 调用 `ManagedPackage::load_installed` 加载并验证
3. 验证版本是否匹配
4. 任一失败返回 `None`（视为缓存未命中）

**容错设计**：
- 加载失败不返回错误，而是视为缓存未命中
- 允许后续 `ensure_installed` 重新下载

### 5. ensure_installed - 确保安装（核心方法）

```rust
pub async fn ensure_installed(&self) -> Result<P::Installed, P::Error>
```

**完整流程**：

```
ensure_installed
├── 快速路径：resolve_cached (行58-60)
├── 平台检测和路径计算 (行62-64)
├── 再次检查缓存 (行65-70)
├── 创建父目录 (行72-80)
├── 获取安装锁 (行82-109)
│   ├── 打开/创建锁文件
│   ├── 尝试获取写锁
│   └── 忙等待重试
├── 锁内再次检查缓存 (行113-118)
├── 获取发布清单 (行120)
├── 验证清单版本 (行121-127)
├── 创建缓存和 staging 目录 (行129-143)
├── 下载并验证归档 (行147-155)
│   ├── 计算归档 URL
│   ├── 下载字节
│   ├── 验证大小
│   └── 验证 SHA-256
├── 创建临时 staging 目录 (行157-165)
├── 写入归档文件 (行166-173)
├── 创建解压目录 (行174-181)
├── 解压归档 (行183-184)
├── 检测包根目录 (行185-188)
├── 加载并验证 staging 包 (行189-199)
├── 隔离现有安装 (行214-216)
├── 提升 staging 到安装目录 (行217)
├── 处理竞争条件 (行218-243)
├── 最终验证 (行248-291)
│   ├── 从最终路径加载
│   ├── 失败时回滚
│   └── 恢复隔离的安装
├── 清理隔离目录 (行293-295)
└── 返回安装包
```

### 6. 安装锁机制

```rust
const INSTALL_LOCK_POLL_INTERVAL: Duration = Duration::from_millis(50);

let lock_path = install_dir.with_extension("lock");
let lock_file = OpenOptions::new()
    .create(true)
    .read(true)
    .write(true)
    .truncate(false)
    .open(&lock_path)?;
let mut install_lock = FileRwLock::new(lock_file);
let _install_guard = loop {
    match install_lock.try_write() {
        Ok(guard) => break guard,
        Err(source) if source.kind() == WouldBlock => {
            sleep(INSTALL_LOCK_POLL_INTERVAL).await;
        }
        Err(source) => return Err(...),
    }
};
```

**设计考量**：
- 使用 `fd-lock` crate 实现跨进程文件锁
- 忙等待策略（50ms 间隔）避免阻塞异步运行时
- 锁文件与安装目录同名，仅扩展名不同（`.lock`）

### 7. Staging-Promotion 模式

**两阶段安装**：
1. **隔离阶段** (`quarantine_existing_install`)：
   - 将现有安装重命名为 `.replaced-{pid}-{suffix}`
   - 处理命名冲突（递增 suffix）

2. **提升阶段** (`promote_staged_install`)：
   - 使用 `fs::rename` 原子移动 staging 目录到安装位置

3. **回滚阶段** (`restore_quarantined_install`)：
   - 提升失败时将隔离的目录恢复

**原子性保证**：
- `fs::rename` 在大多数文件系统上是原子操作
- 失败时可恢复到之前的状态

### 8. 竞争条件处理

```rust
if let Err(error) = promotion {
    // 检查是否是竞争失败（目录已存在）
    if matches!(&error, PackageManagerError::Io { source, .. }
        if matches!(source.kind(), AlreadyExists | DirectoryNotEmpty))
        && let Some(package) = self.resolve_cached_at(...).await?
    {
        // 其他进程已完成安装，使用其结果
        if let Some(replaced) = replaced_install_dir {
            let _ = fs::remove_dir_all(replaced).await;
        }
        return Ok(package);
    }
    // 真正的失败，执行回滚
    restore_quarantined_install(&install_dir, ...).await?;
    return Err(error.into());
}
```

**场景**：
- 进程 A 和 B 同时尝试安装同一版本
- 进程 A 先获得锁并完成安装
- 进程 B 获得锁后尝试提升，发现目录已存在
- 进程 B 检测到竞争，使用已安装的版本

### 9. 最终验证和回滚

```rust
let package = match self.config.package.load_installed(install_dir.clone(), platform) {
    Ok(package) => package,
    Err(error) => {
        if let Some(replaced) = replaced_install_dir.as_deref() {
            // 删除损坏的新安装
            if fs::try_exists(&install_dir).await? {
                fs::remove_dir_all(&install_dir).await?;
            }
            // 恢复之前的安装
            fs::rename(replaced, &install_dir).await?;
        }
        return Err(error);
    }
};
```

**设计目的**：
- 某些包只能在最终安装路径上完全验证
- 确保原子性：要么成功安装新版本，要么保持旧版本

## 具体技术实现

### 关键常量

```rust
const INSTALL_LOCK_POLL_INTERVAL: Duration = Duration::from_millis(50);
```

### 辅助函数

| 函数 | 用途 | 可见性 |
|------|------|--------|
| `quarantine_existing_install` | 隔离现有安装 | `pub(crate)` |
| `promote_staged_install` | 提升 staging 目录 | `pub(crate)` |
| `restore_quarantined_install` | 恢复隔离的安装 | `pub(crate)` |
| `fetch_release_manifest` | 获取发布清单 | `async fn` |
| `download_bytes` | 下载字节数据 | `async fn` |

### 错误处理模式

```rust
.map_err(|source| PackageManagerError::Io {
    context: format!("failed to create {}", parent.display()),
    source,
})
.map_err(P::Error::from)?;
```

- 将底层错误包装为 `PackageManagerError`
- 添加上下文描述
- 转换为包特定的错误类型

## 关键代码路径与文件引用

### 内部依赖

| 模块 | 使用内容 |
|------|----------|
| `archive` | `extract_archive`, `verify_archive_size`, `verify_sha256` |
| `config` | `PackageManagerConfig` |
| `error` | `PackageManagerError` |
| `package` | `ManagedPackage` trait |
| `platform` | `PackagePlatform` |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `fd-lock` | 跨进程文件锁 |
| `reqwest` | HTTP 客户端 |
| `tempfile` | 临时目录创建 |
| `tokio` | 异步文件操作、睡眠 |
| `url` | URL 处理 |

### 调用关系

**被调用方**（来自 artifacts）：
- `PackageManager::new` / `with_client`
- `PackageManager::resolve_cached`
- `PackageManager::ensure_installed`

## 依赖与外部交互

### HTTP 交互

**清单获取** (`fetch_release_manifest`)：
```rust
let response = self.client.get(manifest_url).send().await?;
let manifest = response.json::<P::ReleaseManifest>().await?;
```

**归档下载** (`download_bytes`)：
```rust
let response = self.client.get(url).send().await?;
let bytes = response.bytes().await?;
```

### 文件系统交互

| 操作 | 用途 |
|------|------|
| `fs::create_dir_all` | 创建目录结构 |
| `fs::try_exists` | 检查路径存在 |
| `fs::rename` | 原子移动目录 |
| `fs::remove_dir_all` | 清理临时目录 |
| `fs::write` | 写入归档文件 |
| `OpenOptions::open` | 打开锁文件 |

## 风险、边界与改进建议

### 已知风险

1. **锁文件残留**
   - **风险**：进程崩溃可能导致 `.lock` 文件残留
   - **缓解**：使用 `fd-lock` 的咨询锁，锁随进程退出自动释放
   - **残留影响**：无，锁文件本身不阻止后续操作

2. **隔离目录残留**
   - **风险**：崩溃可能导致 `.replaced-*` 目录残留
   - **缓解**：成功安装后清理，但崩溃时可能遗留
   - **建议**：添加定期清理机制

3. **磁盘空间耗尽**
   - **风险**：staging 过程需要额外磁盘空间
   - **缓解**：使用 `tempfile` 的临时目录，进程退出自动清理
   - **边界**：原子性保证需要同时存在新旧版本

4. **网络超时**
   - **风险**：大文件下载可能超时
   - **现状**：使用默认 `reqwest` 配置，无显式超时设置
   - **建议**：允许通过 `with_client` 传入自定义超时配置

### 边界条件

| 场景 | 行为 |
|------|------|
| 并发安装 | 通过文件锁串行化，后完成者使用已安装版本 |
| 磁盘满 | 写入失败，回滚到之前状态（如果存在） |
| 网络中断 | 下载失败，返回错误，无状态变更 |
| 权限不足 | IO 错误，返回错误，无状态变更 |
| 版本回滚 | 隔离新版本，恢复旧版本 |
| 损坏的缓存 | 视为未命中，重新下载 |

### 改进建议

1. **进度回调**
   - 添加可选的进度回调参数
   - 支持下载和解压进度报告

2. **断点续传**
   - 大文件下载支持 Range 请求
   - 避免重复下载已获取的数据

3. **缓存清理策略**
   - 添加旧版本自动清理
   - 配置最大缓存大小

4. **校验和流式计算**
   - 当前下载完成后校验
   - 可改为流式计算，减少内存占用

5. **重试机制**
   - 网络错误自动重试
   - 指数退避策略

6. **安装钩子**
   - 添加 pre/post install 钩子
   - 允许包特定自定义逻辑

7. **并发下载**
   - 多部分并行下载大文件
   - 提高下载速度

8. **签名验证**
   - 除 SHA-256 外支持 GPG 签名验证
   - 增强安全性

### 测试覆盖

测试文件 `tests.rs` 中相关测试：
- `ensure_installed_downloads_and_extracts_zip_package` - 完整安装流程
- `resolve_cached_uses_custom_cache_root` - 自定义缓存根
- `ensure_installed_replaces_invalid_cached_install` - 替换损坏缓存
- `ensure_installed_rejects_manifest_version_mismatch` - 版本验证
- `ensure_installed_serializes_concurrent_installs` - 并发控制
- `ensure_installed_rejects_unexpected_archive_size` - 大小验证
- `staged_install_restore_keeps_previous_install_on_failed_promotion` - 回滚机制
- `ensure_installed_restores_previous_install_when_final_validation_fails` - 最终验证失败回滚

### 性能考量

| 操作 | 复杂度 | 优化方向 |
|------|--------|----------|
| 缓存检查 | O(1) | 文件系统 stat 操作 |
| 锁获取 | O(1) | 忙等待，可优化为通知机制 |
| 下载 | O(n) | n=文件大小，支持并发/断点续传 |
| 解压 | O(n) | n=归档大小，依赖 CPU/IO |
| 提升 | O(1) | 原子 rename，通常很快 |
