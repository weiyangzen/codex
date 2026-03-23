# Research: codex-rs/utils/cache/src/lib.rs

## 场景与职责

`codex-utils-cache` 是一个为 Codex 项目提供通用缓存能力的 Rust 工具库。它主要解决以下场景：

1. **图像处理缓存**：在 `codex-utils-image` 中缓存已处理的图像，避免重复编码/解码和尺寸调整操作
2. **Token 估算缓存**：在 `codex-core` 的上下文管理中缓存原始图像的 token 估算结果，优化性能

该库的设计哲学是**运行时自适应**：当代码运行在 Tokio 异步运行时中时，缓存功能完全启用；当没有运行时（如某些测试或同步上下文），缓存自动降级为透传模式，保证代码可用性而不阻塞。

---

## 功能点目的

### 1. BlockingLruCache - 阻塞式 LRU 缓存

核心结构，提供线程安全的 LRU (Least Recently Used) 缓存：

| 方法 | 用途 |
|------|------|
| `new(capacity)` | 创建指定容量的缓存 |
| `try_with_capacity(capacity)` | 条件创建，capacity 为 0 时返回 None |
| `get_or_insert_with(key, factory)` | 获取或插入（懒加载） |
| `get_or_try_insert_with(key, factory)` | 获取或插入，支持可能失败的工厂函数 |
| `get(key)` | 获取缓存值 |
| `insert(key, value)` | 插入值，返回旧值 |
| `remove(key)` | 删除并返回值 |
| `clear()` | 清空缓存 |
| `with_mut(callback)` | 提供可变访问回调 |
| `blocking_lock()` | 直接获取锁（高级用法） |

### 2. sha1_digest - 内容哈希

为缓存键提供基于内容的 SHA-1 哈希：
- 生成 20 字节（160 位）固定长度哈希
- 用于图像内容寻址，避免文件名/路径变化导致的缓存失效

---

## 具体技术实现

### 关键数据结构

```rust
/// 内部使用 Tokio Mutex 保护 LRU 缓存
pub struct BlockingLruCache<K, V> {
    inner: Mutex<LruCache<K, V>>,
}
```

- **K**: 键类型，需实现 `Eq + Hash`
- **V**: 值类型，克隆时需提供 `Clone`
- **Mutex**: `tokio::sync::Mutex`，支持异步上下文

### 运行时检测机制

```rust
fn lock_if_runtime<K, V>(m: &Mutex<LruCache<K, V>>) -> Option<MutexGuard<'_, LruCache<K, V>>> {
    // 尝试获取当前 Tokio 运行时句柄
    tokio::runtime::Handle::try_current().ok()?;
    // 在阻塞线程中执行锁获取
    Some(tokio::task::block_in_place(|| m.blocking_lock()))
}
```

**关键设计决策**：
1. 使用 `try_current()` 检测运行时存在性
2. 使用 `block_in_place` 避免在异步运行时中阻塞执行器
3. 无运行时返回 `None`，调用方回退到直接计算

### 缓存键设计（调用方）

**图像缓存** (`codex-utils-image/src/lib.rs`):
```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
struct ImageCacheKey {
    digest: [u8; 20],      // 文件内容 SHA-1
    mode: PromptImageMode, // 处理模式（ResizeToFit/Original）
}
```

**Token 估算缓存** (`codex-core/src/context_manager/history.rs`):
```rust
// 直接使用 SHA-1 哈希作为键
static ORIGINAL_IMAGE_ESTIMATE_CACHE: LazyLock<BlockingLruCache<[u8; 20], Option<i64>>> = ...
```

### LRU 淘汰策略

- 基于 `lru` crate (v0.16.3) 实现
- 当缓存满时，淘汰最久未使用的条目
- 容量通过 `NonZeroUsize` 保证非零

---

## 关键代码路径与文件引用

### 库本身

| 文件 | 说明 |
|------|------|
| `codex-rs/utils/cache/src/lib.rs` | 主实现，193 行 |
| `codex-rs/utils/cache/Cargo.toml` | 包配置，依赖 lru/sha1/tokio |
| `codex-rs/utils/cache/BUILD.bazel` | Bazel 构建配置 |

### 调用方

| 文件 | 使用方式 | 用途 |
|------|----------|------|
| `codex-rs/utils/image/src/lib.rs:8-9` | `use codex_utils_cache::{BlockingLruCache, sha1_digest}` | 图像处理结果缓存 |
| `codex-rs/core/src/context_manager/history.rs:23-24` | 同上 | 原始图像 token 估算缓存 |

### 图像缓存具体路径

```
load_for_prompt_bytes()
  └── IMAGE_CACHE.get_or_try_insert_with(key, || {
        // 1. 检测格式
        // 2. 解码图像
        // 3. 按需调整尺寸
        // 4. 编码输出
      })
```

缓存键：`ImageCacheKey { digest: sha1_digest(&file_bytes), mode }`

### Token 估算缓存具体路径

```
estimate_original_image_bytes(image_url)
  └── ORIGINAL_IMAGE_ESTIMATE_CACHE.get_or_insert_with(key, || {
        // 1. 解析 base64 data URL
        // 2. 解码图像
        // 3. 计算 32px patch 数量
        // 4. 返回估算 token 数
      })
```

---

## 依赖与外部交互

### 外部依赖

| Crate | 版本 | 用途 |
|-------|------|------|
| `lru` | 0.16.3 | LRU 缓存核心实现 |
| `sha1` | 0.10.6 | SHA-1 哈希计算 |
| `tokio` | 1.x | 异步运行时支持（sync, rt, rt-multi-thread） |

### 被依赖情况

```
codex-utils-cache
├── codex-utils-image  (图像处理缓存)
└── codex-core         (token 估算缓存)
```

### 工作空间配置

在 `codex-rs/Cargo.toml` 中定义：
```toml
[workspace.dependencies]
lru = "0.16.3"
sha1 = "0.10.6"
codex-utils-cache = { path = "utils/cache" }
```

---

## 风险、边界与改进建议

### 当前风险

1. **SHA-1 碰撞风险**
   - 虽然用于缓存而非安全场景，但 SHA-1 已被证明存在碰撞攻击
   - 图像内容哈希冲突可能导致返回错误的缓存结果
   - **建议**: 考虑迁移到 SHA-256 或 Blake3（需权衡性能与安全性需求）

2. **运行时依赖隐式性**
   - 缓存是否启用取决于运行时检测，可能导致调试困难
   - 测试环境可能意外禁用缓存，掩盖性能问题
   - **建议**: 添加日志或指标暴露缓存命中率/启用状态

3. **容量硬编码**
   - 图像缓存固定 32 条目 (`NonZeroUsize::new(32)`)
   - token 估算缓存固定 32 条目
   - **建议**: 考虑从配置读取，适应不同内存环境

4. **锁竞争**
   - 使用 `tokio::sync::Mutex` 的 `blocking_lock`，在高并发下可能成为瓶颈
   - `block_in_place` 会阻塞线程，线程池耗尽时影响其他任务

### 边界情况

1. **零容量处理**
   - `try_with_capacity(0)` 返回 `None`，调用方需处理
   - 当前调用方（image/history）都使用固定非零容量

2. **克隆开销**
   - 所有返回值都通过 `clone()` 获取，大对象（如图像字节）可能产生显著内存分配
   - `EncodedImage` 包含 `Vec<u8>`，每次获取都克隆整个图像数据

3. **错误处理**
   - `get_or_try_insert_with` 在工厂函数失败时不缓存，符合预期
   - 但失败原因丢失，调用方无法区分"缓存未命中+工厂失败" vs "无运行时"

### 改进建议

1. **性能优化**
   ```rust
   // 考虑使用 Arc<V> 避免克隆大对象
   pub struct BlockingLruCache<K, V> {
       inner: Mutex<LruCache<K, Arc<V>>>,
   }
   ```

2. **可观测性**
   - 添加 `hit_count()`, `miss_count()`, `len()` 等统计方法
   - 集成 tracing 记录缓存操作

3. **配置化**
   ```rust
   pub struct CacheConfig {
       pub capacity: NonZeroUsize,
       pub ttl: Option<Duration>,  // 可选：添加过期时间
   }
   ```

4. **替代哈希**
   - 对安全性敏感场景提供 `sha256_digest` 选项
   - 或引入 feature flag 选择哈希算法

5. **并发优化**
   - 考虑 `dashmap` 或分片锁减少竞争
   - 或使用 `moka` crate 替代自建缓存（提供异步支持、TTL、LRU 等）

### 测试覆盖

当前测试 (`lib.rs` 144-192 行) 覆盖：
- ✅ 基本存取
- ✅ LRU 淘汰
- ✅ 无运行时降级

缺失测试：
- ❌ 并发安全（多线程同时读写）
- ❌ 大容量性能
- ❌ 边界条件（容量为 1，极端哈希碰撞）

---

## 总结

`codex-utils-cache` 是一个简洁实用的缓存原语，通过运行时检测实现"零成本抽象"——异步环境启用缓存，同步环境透明回退。当前主要用于图像处理和 token 估算两个性能敏感路径。主要风险在于 SHA-1 的碰撞可能性和硬编码容量，建议在后续迭代中引入可配置性和更好的可观测性。
