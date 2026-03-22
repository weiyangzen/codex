# codex-rs/utils/cache 深度研究文档

## 1. 场景与职责

### 1.1 模块定位
`codex-utils-cache` 是 Codex 项目的底层工具缓存库，位于 `codex-rs/utils/cache`，为整个 Rust 代码库提供统一的内存缓存抽象。该模块封装了基于 LRU (Least Recently Used) 策略的线程安全缓存实现，专门设计用于异步 Tokio 运行时环境。

### 1.2 核心职责
- **提供进程内内存缓存**：为频繁计算或 I/O 操作的结果提供高速内存缓存
- **LRU 淘汰策略**：自动管理缓存容量，淘汰最少使用的条目
- **Tokio 运行时感知**：在非 Tokio 环境下自动降级为无操作（no-op），确保测试和同步代码路径的兼容性
- **内容寻址缓存键**：提供 SHA-1 摘要工具函数，支持基于内容的缓存键生成

### 1.3 使用场景
该缓存模块主要服务于以下两类场景：

1. **图像处理缓存** (`codex-utils-image`)
   - 缓存已编码/调整大小的图像数据
   - 避免重复处理相同的图像文件
   - 使用 SHA-1 摘要作为缓存键，确保内容变化时自动失效

2. **Token 估算缓存** (`codex-core`)
   - 缓存原始图像的 token 估算结果
   - 优化上下文管理器中的图像字节估算性能
   - 减少重复的 base64 解码和图像解析操作

---

## 2. 功能点目的

### 2.1 BlockingLruCache 结构体

```rust
pub struct BlockingLruCache<K, V> {
    inner: Mutex<LruCache<K, V>>,
}
```

**设计目的**：
- **线程安全**：使用 `tokio::sync::Mutex` 保护内部 `LruCache`，允许多线程并发访问
- **阻塞式 API**：提供同步风格的 API（`get_or_insert_with`），但内部正确处理异步运行时
- **运行时自适应**：通过 `lock_if_runtime` 检测 Tokio 运行时是否存在，不存在时优雅降级

### 2.2 核心方法

| 方法 | 目的 |
|------|------|
| `new(capacity)` | 创建指定容量的缓存 |
| `try_with_capacity(capacity)` | 条件创建，容量为 0 时返回 None |
| `get_or_insert_with(key, factory)` | 获取或计算插入（工厂模式） |
| `get_or_try_insert_with(key, factory)` | 支持可能失败的工厂函数 |
| `get(key)` | 读取缓存值 |
| `insert(key, value)` | 插入/更新缓存 |
| `remove(key)` | 删除指定条目 |
| `clear()` | 清空缓存 |
| `with_mut(callback)` | 提供底层缓存的可变访问 |
| `blocking_lock()` | 获取原始 MutexGuard |

### 2.3 sha1_digest 工具函数

```rust
pub fn sha1_digest(bytes: &[u8]) -> [u8; 20]
```

**设计目的**：
- 为内容寻址缓存提供标准哈希函数
- 避免基于文件路径的缓存键导致的陈旧数据问题
- 20 字节固定长度输出，适合作为缓存键使用

---

## 3. 具体技术实现

### 3.1 关键数据结构

```rust
// 主缓存结构
pub struct BlockingLruCache<K, V> {
    inner: Mutex<LruCache<K, V>>,
}

// 键约束
K: Eq + Hash

// 容量类型
std::num::NonZeroUsize  // 确保容量不为零
```

### 3.2 核心流程

#### 3.2.1 运行时检测机制

```rust
fn lock_if_runtime<K, V>(m: &Mutex<LruCache<K, V>>) -> Option<MutexGuard<'_, LruCache<K, V>>>
where
    K: Eq + Hash,
{
    tokio::runtime::Handle::try_current().ok()?;
    Some(tokio::task::block_in_place(|| m.blocking_lock()))
}
```

**流程说明**：
1. 尝试获取当前 Tokio 运行时句柄
2. 若无运行时（如同步测试环境），返回 `None`
3. 若有运行时，使用 `block_in_place` 执行阻塞式锁获取
4. 这种设计确保在异步上下文中不会阻塞事件循环

#### 3.2.2 Get-or-Insert 模式

```rust
pub fn get_or_insert_with(&self, key: K, value: impl FnOnce() -> V) -> V
where
    V: Clone,
{
    if let Some(mut guard) = lock_if_runtime(&self.inner) {
        if let Some(v) = guard.get(&key) {
            return v.clone();  // 缓存命中
        }
        let v = value();       // 执行工厂函数
        guard.put(key, v.clone());
        return v;
    }
    value()  // 无运行时，直接计算
}
```

**关键特性**：
- 工厂函数仅在缓存未命中时执行
- 返回值克隆，原始值保留在缓存中
- 无运行时环境下直接透传工厂调用

#### 3.2.3 降级处理模式

所有方法在无 Tokio 运行时时都遵循相同的降级模式：
- `get_or_insert_with` → 直接调用工厂
- `get_or_try_insert_with` → 直接调用工厂
- `get` → 返回 None
- `insert`/`remove`/`clear` → 无操作
- `with_mut` → 使用临时无界缓存执行回调，但更改不保留

### 3.3 依赖库

| 依赖 | 版本 | 用途 |
|------|------|------|
| `lru` | 0.16.3 | 提供基础 LRU 缓存实现 |
| `sha1` | 0.10.6 | SHA-1 哈希计算 |
| `tokio` | 1.x | 异步运行时支持（sync, rt, rt-multi-thread） |

---

## 4. 关键代码路径与文件引用

### 4.1 本模块文件

| 文件 | 说明 |
|------|------|
| `codex-rs/utils/cache/src/lib.rs` | 主实现文件，193 行 |
| `codex-rs/utils/cache/Cargo.toml` | 包配置，依赖声明 |
| `codex-rs/utils/cache/BUILD.bazel` | Bazel 构建配置 |

### 4.2 调用方代码路径

#### 4.2.1 图像处理缓存 (`codex-utils-image`)

**文件**: `codex-rs/utils/image/src/lib.rs`

```rust
// 行 8-9: 导入
use codex_utils_cache::BlockingLruCache;
use codex_utils_cache::sha1_digest;

// 行 53-54: 全局缓存实例
static IMAGE_CACHE: LazyLock<BlockingLruCache<ImageCacheKey, EncodedImage>> =
    LazyLock::new(|| BlockingLruCache::new(NonZeroUsize::new(32).unwrap_or(NonZeroUsize::MIN)));

// 行 62-65: 缓存键构建
let key = ImageCacheKey {
    digest: sha1_digest(&file_bytes),
    mode,
};

// 行 68: 使用 get_or_try_insert_with
IMAGE_CACHE.get_or_try_insert_with(key, move || { ... })
```

**缓存键结构** (行 47-51):
```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
struct ImageCacheKey {
    digest: [u8; 20],      // SHA-1 文件内容摘要
    mode: PromptImageMode, // 处理模式（ResizeToFit/Original）
}
```

**容量**: 32 条目

#### 4.2.2 Token 估算缓存 (`codex-core`)

**文件**: `codex-rs/core/src/context_manager/history.rs`

```rust
// 行 23-24: 导入
use codex_utils_cache::BlockingLruCache;
use codex_utils_cache::sha1_digest;

// 行 455-460: 全局缓存实例
static ORIGINAL_IMAGE_ESTIMATE_CACHE: LazyLock<BlockingLruCache<[u8; 20], Option<i64>>> =
    LazyLock::new(|| {
        BlockingLruCache::new(
            NonZeroUsize::new(ORIGINAL_IMAGE_ESTIMATE_CACHE_SIZE).unwrap_or(NonZeroUsize::MIN),
        )
    });

// 行 524-526: 使用
let key = sha1_digest(image_url.as_bytes());
ORIGINAL_IMAGE_ESTIMATE_CACHE.get_or_insert_with(key, || { ... })
```

**容量**: 32 条目 (ORIGINAL_IMAGE_ESTIMATE_CACHE_SIZE = 32)

**用途**: 缓存原始图像的 token 估算结果，避免重复的 base64 解码和图像尺寸计算

### 4.3 测试覆盖

**文件**: `codex-rs/utils/cache/src/lib.rs` (行 144-193)

测试用例：
1. `stores_and_retrieves_values` - 基本存储和检索
2. `evicts_least_recently_used` - LRU 淘汰策略验证
3. `disabled_without_runtime` - 无运行时降级行为验证

---

## 5. 依赖与外部交互

### 5.1 内部依赖关系

```
codex-utils-cache (本模块)
    ├── lru crate (外部)
    ├── sha1 crate (外部)
    └── tokio crate (外部)

依赖本模块的 crate:
    ├── codex-utils-image
    │   └── 用于图像编码结果缓存
    └── codex-core
        └── 用于原始图像 token 估算缓存
```

### 5.2 外部 crate 依赖

| Crate | 功能使用 |
|-------|----------|
| `lru::LruCache` | 基础 LRU 缓存实现 |
| `sha1::Sha1` | SHA-1 哈希计算 |
| `tokio::sync::Mutex` | 异步互斥锁 |
| `tokio::runtime::Handle` | 运行时检测 |
| `tokio::task::block_in_place` | 阻塞式锁获取 |

### 5.3 与 Tokio 运行时的交互

```
┌─────────────────────────────────────────┐
│           调用方代码 (任意线程)           │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│      BlockingLruCache::get_or_insert_with │
│  ┌─────────────────────────────────────┐ │
│  │   lock_if_runtime()                 │ │
│  │   ├─ try_current() -> Ok(_)         │ │
│  │   │   └─ block_in_place(|| lock()) │ │
│  │   │       └─ 返回 MutexGuard        │ │
│  │   └─ try_current() -> Err(_)        │ │
│  │       └─ 返回 None (降级)           │ │
│  └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 运行时检测的潜在竞争
- **风险**: `try_current()` 检测运行时存在，但在 `block_in_place` 执行前运行时可能已关闭
- **影响**: 极低，通常发生在进程关闭阶段
- **缓解**: 当前实现返回 `Option`，调用方需正确处理 `None`

#### 6.1.2 缓存容量固定
- **风险**: 缓存容量在创建后不可调整，无法动态适应内存压力
- **影响**: 长期运行的进程可能占用过多内存
- **当前状态**: 图像缓存固定 32 条目，估算缓存固定 32 条目

#### 6.1.3 无持久化
- **风险**: 进程重启后缓存完全失效
- **影响**: 启动初期性能较低
- **设计意图**: 这是内存缓存的预期行为

### 6.2 边界情况

| 场景 | 行为 |
|------|------|
| 容量为 0 | `try_with_capacity` 返回 `None`，`new` 要求 `NonZeroUsize` |
| 无 Tokio 运行时 | 所有操作降级，缓存不生效 |
| 工厂函数 panic | 未捕获，会传播到调用方 |
| 工厂函数递归调用 | 可能导致死锁（Mutex 未重入） |
| 大值类型 | 克隆开销可能抵消缓存收益 |

### 6.3 改进建议

#### 6.3.1 可观测性增强
```rust
// 建议添加指标收集
pub fn hit_rate(&self) -> f64 { ... }
pub fn len(&self) -> usize { ... }
pub fn is_empty(&self) -> bool { ... }
```

#### 6.3.2 动态容量调整
```rust
// 建议支持运行时调整容量
pub fn resize(&self, new_capacity: NonZeroUsize) { ... }
```

#### 6.3.3 TTL 支持
当前实现为纯 LRU，可考虑添加时间过期支持：
```rust
pub struct BlockingLruCache<K, V> {
    inner: Mutex<LruCache<K, (V, Instant)>>,
    ttl: Option<Duration>,
}
```

#### 6.3.4 权重缓存
对于图像缓存等场景，条目大小差异大，可考虑按权重而非数量限制：
```rust
// 按字节数限制而非条目数
BlockingLruCache::with_weight_limit(max_bytes: usize)
```

#### 6.3.5 并发优化
当前使用 `block_in_place` 可能阻塞工作线程，可考虑：
- 使用 `tokio::sync::RwLock` 替代 `Mutex` 支持并发读
- 或使用 `moka` 等专门的异步缓存库

### 6.4 代码质量建议

1. **文档完善**: 为 `BlockingLruCache` 添加更多使用示例
2. **错误处理**: 考虑为 `get_or_try_insert_with` 的工厂错误添加专门类型
3. **测试覆盖**: 添加并发压力测试和内存使用测试
4. **性能基准**: 添加基准测试验证缓存命中率对性能的影响

---

## 附录：关键代码片段

### A.1 完整模块源码

```rust
// codex-rs/utils/cache/src/lib.rs
use std::borrow::Borrow;
use std::hash::Hash;
use std::num::NonZeroUsize;

use lru::LruCache;
use sha1::Digest;
use sha1::Sha1;
use tokio::sync::Mutex;
use tokio::sync::MutexGuard;

/// A minimal LRU cache protected by a Tokio mutex.
/// Calls outside a Tokio runtime are no-ops.
pub struct BlockingLruCache<K, V> {
    inner: Mutex<LruCache<K, V>>,
}

impl<K, V> BlockingLruCache<K, V>
where
    K: Eq + Hash,
{
    pub fn new(capacity: NonZeroUsize) -> Self { ... }
    pub fn get_or_insert_with(&self, key: K, value: impl FnOnce() -> V) -> V { ... }
    pub fn get_or_try_insert_with<E>(&self, key: K, value: impl FnOnce() -> Result<V, E>) -> Result<V, E> { ... }
    pub fn try_with_capacity(capacity: usize) -> Option<Self> { ... }
    pub fn get<Q>(&self, key: &Q) -> Option<V> { ... }
    pub fn insert(&self, key: K, value: V) -> Option<V> { ... }
    pub fn remove<Q>(&self, key: &Q) -> Option<V> { ... }
    pub fn clear(&self) { ... }
    pub fn with_mut<R>(&self, callback: impl FnOnce(&mut LruCache<K, V>) -> R) -> R { ... }
    pub fn blocking_lock(&self) -> Option<MutexGuard<'_, LruCache<K, V>>> { ... }
}

fn lock_if_runtime<K, V>(m: &Mutex<LruCache<K, V>>) -> Option<MutexGuard<'_, LruCache<K, V>>> { ... }

pub fn sha1_digest(bytes: &[u8]) -> [u8; 20] { ... }
```

### A.2 使用模式示例

```rust
// 典型使用模式（来自 codex-utils-image）
static CACHE: LazyLock<BlockingLruCache<Key, Value>> = 
    LazyLock::new(|| BlockingLruCache::new(NonZeroUsize::new(32).unwrap()));

// 内容寻址键
let key = ImageCacheKey {
    digest: sha1_digest(&file_bytes),
    mode: processing_mode,
};

// 获取或计算
CACHE.get_or_try_insert_with(key, || {
    // 昂贵的计算/IO 操作
    process_image(&file_bytes)
})?
```

---

*文档生成时间: 2026-03-22*
*基于代码版本: codex-rs/utils/cache/src/lib.rs (193 lines)*
