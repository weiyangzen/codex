# cache.rs 研究文档

## 场景与职责

`cache.rs` 是 Codex CLI 模型管理系统的磁盘缓存层，负责将远程获取的模型元数据持久化到本地文件系统，以支持离线使用和减少网络请求。该模块解决了以下核心问题：

1. **网络优化**：避免每次启动都请求 `/models` 接口
2. **离线可用**：在无网络连接时仍能提供模型列表
3. **版本一致性**：通过客户端版本校验确保缓存数据与当前软件版本兼容
4. **TTL 管理**：通过可配置的缓存过期时间平衡数据新鲜度和性能

## 功能点目的

### 1. 缓存加载与验证 (`load_fresh`)
- **目的**：从磁盘加载缓存并验证其有效性
- **验证维度**：
  - 文件是否存在
  - 客户端版本是否匹配（防止新旧版本数据格式不兼容）
  - 缓存是否在 TTL 有效期内
- **返回值**：`Option<ModelsCache>` - 仅在缓存有效时返回

### 2. 缓存持久化 (`persist_cache`)
- **目的**：将远程获取的模型列表保存到磁盘
- **存储内容**：模型列表、ETag（用于条件请求）、客户端版本、获取时间戳
- **错误处理**：失败时仅记录错误，不中断主流程

### 3. 缓存 TTL 刷新 (`renew_cache_ttl`)
- **目的**：在不重新获取数据的情况下延长缓存有效期
- **使用场景**：当服务端 ETag 未变化时，刷新本地缓存时间戳

### 4. 测试辅助方法
- `set_ttl`：动态调整 TTL 用于测试
- `manipulate_cache_for_test`：修改缓存时间戳
- `mutate_cache_for_test`：修改完整缓存内容

## 具体技术实现

### 关键数据结构

```rust
/// 磁盘缓存管理器
pub(crate) struct ModelsCacheManager {
    cache_path: PathBuf,  // 缓存文件路径（通常位于 ~/.codex/models_cache.json）
    cache_ttl: Duration,  // 缓存有效期（默认 300 秒）
}

/// 序列化的缓存快照
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct ModelsCache {
    pub(crate) fetched_at: DateTime<Utc>,      // 获取时间戳
    pub(crate) etag: Option<String>,           // HTTP ETag 用于条件请求
    pub(crate) client_version: Option<String>, // 客户端版本号
    pub(crate) models: Vec<ModelInfo>,         // 模型元数据列表
}
```

### 核心流程

#### 缓存加载流程 (`load_fresh`)
```
1. 读取缓存文件内容
2. JSON 反序列化为 ModelsCache
3. 验证 client_version 是否匹配当前版本
4. 验证 fetched_at + ttl > now（是否过期）
5. 全部通过则返回 Some(cache)，否则返回 None
```

#### 新鲜度检查算法 (`is_fresh`)
```rust
fn is_fresh(&self, ttl: Duration) -> bool {
    if ttl.is_zero() { return false; }
    let Ok(ttl_duration) = chrono::Duration::from_std(ttl) else {
        return false;
    };
    let age = Utc::now().signed_duration_since(self.fetched_at);
    age <= ttl_duration
}
```

#### 缓存写入流程 (`save_internal`)
```
1. 确保父目录存在（create_dir_all）
2. 将 ModelsCache 序列化为格式化的 JSON
3. 原子写入文件（fs::write）
```

### 文件位置

- 缓存文件默认路径：`~/.codex/models_cache.json`
- 文件名常量：`MODEL_CACHE_FILE = "models_cache.json"`

## 关键代码路径与文件引用

### 内部依赖
| 路径 | 用途 |
|------|------|
| `codex_protocol::openai_models::ModelInfo` | 模型元数据结构定义 |

### 外部调用方
| 路径 | 调用方法 | 用途 |
|------|----------|------|
| `manager.rs:501` | `load_fresh` | 尝试从缓存加载模型列表 |
| `manager.rs:463` | `persist_cache` | 保存远程获取的模型数据 |
| `manager.rs:382` | `renew_cache_ttl` | ETag 未变化时刷新缓存时间 |

### 常量定义
| 常量 | 值 | 说明 |
|------|-----|------|
| `DEFAULT_MODEL_CACHE_TTL` | 300 秒 | 默认缓存有效期 |

## 依赖与外部交互

### 外部 Crate 依赖
- `chrono`：UTC 时间戳处理
- `serde` / `serde_json`：JSON 序列化/反序列化
- `tokio::fs`：异步文件操作
- `tracing`：结构化日志记录

### 协议类型依赖
- `codex_protocol::openai_models::ModelInfo`：模型元数据结构

### 文件系统交互
- 读取：`~/.codex/models_cache.json`
- 写入：`~/.codex/models_cache.json`（自动创建父目录）

## 风险、边界与改进建议

### 已知风险

1. **版本兼容性问题**
   - 风险：当软件升级后，旧版缓存格式可能与新代码不兼容
   - 缓解：通过 `client_version` 字段校验，不匹配时自动丢弃缓存
   - 边界：仅比较主版本号（通过 `client_version_to_whole` 提取）

2. **并发写入风险**
   - 风险：多个进程同时写入缓存文件可能导致数据损坏
   - 现状：当前实现无文件锁机制，依赖操作系统原子写入
   - 建议：考虑添加文件锁或使用临时文件+原子重命名

3. **TTL 边界情况**
   - `ttl.is_zero()` 被视为永远过期（用于测试强制刷新）
   - 超大 TTL 值可能导致 `chrono::Duration::from_std` 失败

### 边界条件

| 场景 | 行为 |
|------|------|
| 缓存文件不存在 | 返回 `None`，触发网络请求 |
| 缓存文件损坏（无效 JSON） | 记录错误，返回 `None` |
| 版本不匹配 | 记录日志，返回 `None` |
| 缓存过期 | 记录日志，返回 `None` |
| 写入时磁盘满 | 记录错误，不中断主流程 |

### 改进建议

1. **原子写入优化**
   ```rust
   // 建议：使用临时文件+重命名确保原子性
   let temp_path = cache_path.with_extension("tmp");
   fs::write(&temp_path, json).await?;
   fs::rename(temp_path, cache_path).await?;
   ```

2. **缓存压缩**
   - 对于大型模型列表，考虑使用 gzip 压缩减少磁盘占用

3. **缓存加密**
   - 如果缓存包含敏感信息，考虑加密存储

4. **多版本缓存支持**
   - 当前版本不匹配即丢弃，可考虑保留多版本缓存用于回滚场景

5. **缓存统计**
   - 添加缓存命中率、加载时间等指标，用于性能监控

### 测试覆盖

测试文件：`manager_tests.rs` 中涉及缓存的测试：
- `refresh_available_models_uses_cache_when_fresh`：缓存命中场景
- `refresh_available_models_refetches_when_cache_stale`：缓存过期场景
- `refresh_available_models_refetches_when_version_mismatch`：版本不匹配场景
