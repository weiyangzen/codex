# test_support.rs 研究文档

## 场景与职责

`test_support.rs` 是 `codex-state` crate 的测试辅助模块，专门用于为 `StateRuntime` 相关的单元测试和集成测试提供**测试数据构造**和**测试环境准备**功能。该模块仅在 `#[cfg(test)]` 条件下编译，不会包含在生产构建中。

### 核心职责
1. **临时目录管理**：为每个测试用例生成唯一的临时目录，避免测试间文件系统冲突
2. **测试数据工厂**：提供标准化的 `ThreadMetadata` 构造器，确保测试数据的一致性
3. **测试隔离保障**：通过 UUID + 时间戳的复合命名策略，确保并发测试的安全性

---

## 功能点目的

### 1. `unique_temp_dir()` - 唯一临时目录生成

**目的**：为每个测试用例创建隔离的文件系统环境

**实现机制**：
- 使用 `SystemTime::now()` 获取纳秒级时间戳
- 结合 `Uuid::new_v4()` 生成随机 UUID
- 路径格式：`{temp_dir}/codex-state-runtime-test-{nanos}-{uuid}`

**关键设计决策**：
```rust
let nanos = SystemTime::now()
    .duration_since(UNIX_EPOCH)
    .map_or(0, |duration| duration.as_nanos());
```
- 时间戳提供时序唯一性（同一毫秒内多次调用不会冲突）
- UUID 提供全局唯一性（跨进程/跨机器）

### 2. `test_thread_metadata()` - 测试线程元数据工厂

**目的**：快速构造符合测试需求的 `ThreadMetadata` 实例

**参数设计**：
| 参数 | 类型 | 说明 |
|------|------|------|
| `codex_home` | `&Path` | 用于构建 `rollout_path` 的基础路径 |
| `thread_id` | `ThreadId` | 线程唯一标识 |
| `cwd` | `PathBuf` | 工作目录 |

**硬编码默认值**：
- `created_at` / `updated_at`: 固定时间戳 `1_700_000_000` (2023-11-14)
- `source`: `"cli"`
- `model_provider`: `"test-provider"`
- `model`: `"gpt-5"`
- `reasoning_effort`: `Medium`
- `cli_version`: `"0.0.0"`
- `sandbox_policy`: `SandboxPolicy::new_read_only_policy()`
- `approval_mode`: `AskForApproval::OnRequest`
- `first_user_message`: `"hello"`

**设计意图**：
- 固定时间戳确保测试的可重复性
- 合理的默认值减少测试代码的噪音
- 关键字段（`id`, `rollout_path`, `cwd`）由调用方指定，保持灵活性

---

## 具体技术实现

### 模块结构
```rust
#[cfg(test)]  // 条件编译：仅在测试模式下包含
mod test_support {
    // 测试辅助函数
}
```

### 依赖项（条件导入）
```rust
#[cfg(test)]
use chrono::DateTime;
#[cfg(test)]
use chrono::Utc;
// ... 其他测试专用依赖
```

所有导入都标记了 `#[cfg(test)]`，确保不会意外引入到生产代码。

### 路径构造逻辑
```rust
pub(super) fn unique_temp_dir() -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |duration| duration.as_nanos());
    std::env::temp_dir().join(format!(
        "codex-state-runtime-test-{nanos}-{}",
        Uuid::new_v4()
    ))
}
```

### ThreadMetadata 构造逻辑
```rust
pub(super) fn test_thread_metadata(
    codex_home: &Path,
    thread_id: ThreadId,
    cwd: PathBuf,
) -> ThreadMetadata {
    let now = DateTime::<Utc>::from_timestamp(1_700_000_000, 0).expect("timestamp");
    ThreadMetadata {
        id: thread_id,
        rollout_path: codex_home.join(format!("rollout-{thread_id}.jsonl")),
        // ... 其他字段
    }
}
```

---

## 关键代码路径与文件引用

### 被引用位置
该模块的函数被以下测试文件广泛使用：

| 文件 | 使用场景 |
|------|----------|
| `runtime/threads.rs` (行 683-684) | `test_thread_metadata`, `unique_temp_dir` |
| `runtime/backfill.rs` (行 126, 134) | `unique_temp_dir` |
| `runtime/memories.rs` (行 1285-1286) | `test_thread_metadata`, `unique_temp_dir` |
| `runtime/agent_jobs.rs` | 测试辅助 |

### 引用示例（来自 threads.rs 测试）
```rust
use crate::runtime::test_support::test_thread_metadata;
use crate::runtime::test_support::unique_temp_dir;

#[tokio::test]
async fn upsert_thread_keeps_creation_memory_mode_for_existing_rows() {
    let codex_home = unique_temp_dir();
    let runtime = StateRuntime::init(codex_home.clone(), "test-provider".to_string())
        .await
        .expect("state db should initialize");
    let thread_id = ThreadId::from_string("00000000-0000-0000-0000-000000000123").expect("valid thread id");
    let mut metadata = test_thread_metadata(&codex_home, thread_id, codex_home.clone());
    // ... 测试逻辑
}
```

### 模块注册位置
```rust
// runtime.rs 行 52-58
mod agent_jobs;
mod backfill;
mod logs;
mod memories;
#[cfg(test)]
mod test_support;  // <-- 在此处注册
mod threads;
```

---

## 依赖与外部交互

### 内部依赖
| 依赖 | 用途 |
|------|------|
| `crate::ThreadMetadata` | 构造目标类型 |
| `crate::extract::enum_to_string` | 序列化枚举字段 |

### 外部 Crate 依赖
| Crate | 用途 |
|-------|------|
| `chrono` | 时间戳处理 |
| `codex_protocol` | `ThreadId`, `ReasoningEffort`, `AskForApproval`, `SandboxPolicy` |
| `uuid` | UUID 生成 |
| `std::path` | 路径操作 |

### 无外部交互
该模块是纯工具模块，不涉及：
- 数据库操作
- 网络请求
- 文件系统写入（仅返回路径，不创建文件）
- 环境变量读取

---

## 风险、边界与改进建议

### 当前风险

1. **时间戳硬编码风险**
   ```rust
   let now = DateTime::<Utc>::from_timestamp(1_700_000_000, 0).expect("timestamp");
   ```
   - 风险：所有测试使用相同时间戳，可能掩盖时序相关的 bug
   - 缓解：测试覆盖本身不依赖时间戳顺序

2. **临时目录清理依赖**
   - `unique_temp_dir()` 只创建路径，不创建目录，也不负责清理
   - 依赖测试代码手动清理：`tokio::fs::remove_dir_all(codex_home).await`
   - 风险：测试失败时可能留下孤儿目录

3. **UUID 生成依赖标准库**
   - `Uuid::new_v4()` 使用随机数生成器
   - 极端情况下（/dev/urandom 耗尽）可能阻塞或失败

### 边界条件

1. **路径长度限制**
   - Windows 有 260 字符路径限制
   - 当前格式：`codex-state-runtime-test-{nanos}-{uuid}` 约 60-70 字符
   - 加上系统临时目录路径，通常安全

2. **并发安全性**
   - 纳秒 + UUID 的组合在理论上存在冲突可能（UUID v4 冲突概率约 10^-18）
   - 实际可视为唯一

### 改进建议

1. **自动清理支持**
   ```rust
   // 建议：返回 RAII 守卫
   pub struct TempDirGuard(PathBuf);
   impl Drop for TempDirGuard {
       fn drop(&mut self) {
           let _ = std::fs::remove_dir_all(&self.0);
       }
   }
   ```

2. **可配置时间戳**
   ```rust
   pub fn test_thread_metadata_with_time(
       codex_home: &Path,
       thread_id: ThreadId,
       cwd: PathBuf,
       created_at: DateTime<Utc>,
   ) -> ThreadMetadata
   ```

3. **添加目录创建辅助**
   ```rust
   pub async fn setup_test_env() -> anyhow::Result<PathBuf> {
       let dir = unique_temp_dir();
       tokio::fs::create_dir_all(&dir).await?;
       Ok(dir)
   }
   ```

4. **文档化清理责任**
   在函数文档中明确说明调用方负责清理临时目录

### 测试覆盖率
该模块本身没有单元测试（作为测试辅助代码），但其正确性通过以下测试间接验证：
- `runtime/threads.rs` 中的 10+ 个测试用例
- `runtime/backfill.rs` 中的 3 个测试用例
- `runtime/memories.rs` 中的 15+ 个测试用例

所有测试均通过 `cargo test -p codex-state` 验证。
