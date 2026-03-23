# Cargo.toml 研究文档

## 场景与职责

该文件是 `codex-utils-cache` crate 的 Cargo 包清单，定义了 Rust 缓存工具库的元数据、依赖关系和构建配置。它是 Cargo 构建系统和 Bazel 构建系统（通过 `cargo-bazel`）解析依赖的主要来源。

## 功能点目的

1. **包元数据定义**: 指定 crate 名称、版本、Rust 版本和许可证
2. **工作区继承**: 从 workspace 继承通用配置（版本、edition、license、lints）
3. **依赖管理**: 声明运行时依赖（`lru`, `sha1`, `tokio`）和开发依赖
4. **代码质量**: 继承 workspace 级别的 lint 规则

## 具体技术实现

### 包配置

```toml
[package]
name = "codex-utils-cache"
version.workspace = true
edition.workspace = true
license.workspace = true
```

- **命名约定**: 遵循 AGENTS.md 规定的 `codex-` 前缀（Cargo 使用连字符 `codex-utils-cache`，Bazel 使用下划线 `codex_utils_cache`）
- **工作区继承**: 所有关键属性从 workspace 根目录的 `Cargo.toml` 继承，确保一致性

### 依赖配置

#### 运行时依赖

| Crate | 版本 | 特性 | 用途 |
|-------|------|------|------|
| `lru` | workspace | - | LRU（最近最少使用）缓存实现 |
| `sha1` | workspace | - | SHA-1 哈希算法 |
| `tokio` | workspace | `sync`, `rt`, `rt-multi-thread` | 异步运行时和同步原语 |

#### 开发依赖

| Crate | 版本 | 特性 | 用途 |
|-------|------|------|------|
| `tokio` | workspace | `macros`, `rt`, `rt-multi-thread` | 测试宏和多线程运行时 |

### Tokio 特性分析

**运行时依赖特性**:
- `sync`: 提供 `Mutex` 等同步原语（`BlockingLruCache` 使用 `tokio::sync::Mutex`）
- `rt`: 运行时支持
- `rt-multi-thread`: 多线程运行时支持

**开发依赖特性**:
- `macros`: 提供 `#[tokio::test]` 等测试宏
- `rt`, `rt-multi-thread`: 测试运行时

## 关键代码路径与文件引用

### 直接关联文件
- `codex-rs/utils/cache/src/lib.rs` - 库实现源代码
- `codex-rs/utils/cache/BUILD.bazel` - Bazel 构建配置
- `codex-rs/Cargo.toml` - Workspace 根配置（继承来源）

### 依赖使用代码路径

#### LRU 缓存使用
```rust
// src/lib.rs
use lru::LruCache;

pub struct BlockingLruCache<K, V> {
    inner: Mutex<LruCache<K, V>>,
}
```

#### SHA-1 使用
```rust
// src/lib.rs
use sha1::Digest;
use sha1::Sha1;

pub fn sha1_digest(bytes: &[u8]) -> [u8; 20] {
    let mut hasher = Sha1::new();
    hasher.update(bytes);
    // ...
}
```

#### Tokio 同步使用
```rust
// src/lib.rs
use tokio::sync::Mutex;
use tokio::sync::MutexGuard;

fn lock_if_runtime<K, V>(m: &Mutex<LruCache<K, V>>) -> Option<MutexGuard<'_, LruCache<K, V>>> {
    tokio::runtime::Handle::try_current().ok()?;
    Some(tokio::task::block_in_place(|| m.blocking_lock()))
}
```

### 调用方（依赖本 crate）

#### 1. codex-utils-image
**文件**: `codex-rs/utils/image/Cargo.toml`
```toml
[dependencies]
codex-utils-cache = { path = "../cache" }
```

**使用场景**: 图像处理缓存
```rust
// codex-rs/utils/image/src/lib.rs
use codex_utils_cache::BlockingLruCache;
use codex_utils_cache::sha1_digest;

static IMAGE_CACHE: LazyLock<BlockingLruCache<ImageCacheKey, EncodedImage>> =
    LazyLock::new(|| BlockingLruCache::new(NonZeroUsize::new(32).unwrap()));
```

#### 2. codex-core
**文件**: `codex-rs/core/Cargo.toml`

**使用场景**: 上下文管理器中的图像 token 估算缓存
```rust
// codex-rs/core/src/context_manager/history.rs
use codex_utils_cache::BlockingLruCache;
use codex_utils_cache::sha1_digest;

static ORIGINAL_IMAGE_ESTIMATE_CACHE: LazyLock<BlockingLruCache<[u8; 20], Option<i64>>> =
    LazyLock::new(|| BlockingLruCache::new(
        NonZeroUsize::new(ORIGINAL_IMAGE_ESTIMATE_CACHE_SIZE).unwrap()
    ));
```

## 依赖与外部交互

### Workspace 依赖解析

依赖版本通过 `codex-rs/Cargo.toml` workspace 定义：

```toml
[workspace.dependencies]
lru = "0.12"
sha1 = "0.10"
tokio = { version = "1.40", features = ["full"] }
```

### Bazel 集成

Bazel 通过 `cargo-bazel` 从 `Cargo.toml` 生成依赖：
- `MODULE.bazel.lock` 锁定依赖版本
- `defs.bzl` 中的 `all_crate_deps()` 解析依赖

### 特性传播

`tokio` 的特性选择经过精心设计：
- 运行时仅需 `sync`, `rt`, `rt-multi-thread`
- 测试需要额外的 `macros` 特性
- 避免启用不必要的特性以减少编译时间和二进制大小

## 风险、边界与改进建议

### 风险

1. **依赖版本锁定**: 
   - 修改依赖后需运行 `just bazel-lock-update` 更新 `MODULE.bazel.lock`
   - 需运行 `just bazel-lock-check` 验证锁定文件一致性

2. **Tokio 运行时依赖**:
   - `BlockingLruCache` 在无 Tokio 运行时时会降级为无操作（见 `lock_if_runtime` 实现）
   - 这种设计是刻意的，但可能导致非异步环境下的性能问题

3. **SHA-1 安全性**:
   - SHA-1 用于内容寻址缓存键，不用于安全敏感场景
   - 用于图像内容哈希以检测文件变化

### 边界

1. **缓存容量限制**:
   - `LruCache` 需要 `NonZeroUsize` 容量
   - `try_with_capacity` 方法处理零容量情况（返回 `None`）

2. **线程安全**:
   - 使用 `tokio::sync::Mutex` 而非 `std::sync::Mutex`
   - 专为异步环境设计，同步环境会降级

3. **平台支持**:
   - 继承 workspace 的平台支持矩阵
   - 无平台特定代码

### 改进建议

1. **依赖优化**:
   ```toml
   # 考虑减少 tokio 特性以加快编译
   tokio = { workspace = true, features = ["sync", "rt"] }
   ```
   如果不需要多线程运行时，可移除 `rt-multi-thread`

2. **可选依赖**:
   ```toml
   [features]
   default = ["sha"]
   sha = ["dep:sha1"]
   ```
   如果某些用户不需要 SHA-1 功能，可设为可选

3. **版本规范**:
   - 考虑在 `Cargo.toml` 中显式指定最小版本要求
   - 添加 `rust-version` 字段指定最低支持的 Rust 版本

4. **文档依赖**:
   ```toml
   [package]
   documentation = "https://docs.rs/codex-utils-cache"
   repository = "https://github.com/openai/codex"
   ```
   添加更多元数据以提高可发现性

5. **测试配置**:
   ```toml
   [profile.test]
   opt-level = 2
   ```
   考虑为测试配置优化级别以提高测试性能

### 维护注意事项

1. **依赖更新**: 更新 `lru` 或 `sha1` 时需检查 API 兼容性
2. **Tokio 升级**: 跨主版本升级时需验证 `block_in_place` 行为
3. **Bazel 同步**: 任何依赖修改后必须更新 Bazel 锁定文件
