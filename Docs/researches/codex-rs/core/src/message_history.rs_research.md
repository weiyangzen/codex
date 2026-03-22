# message_history.rs 深度研究文档

## 场景与职责

`message_history.rs` 是 Codex CLI 的全局消息历史持久化层，负责将用户与 AI 的对话记录以 **JSON Lines** 格式追加写入到 `~/.codex/history.jsonl` 文件。该模块解决了以下核心问题：

1. **持久化存储**：保存用户输入的历史消息，支持跨会话检索和复用
2. **并发安全**：多进程（多个 TUI 实例）同时写入时的数据完整性保证
3. **存储限制**：自动修剪历史文件以控制磁盘占用
4. **元数据追踪**：提供文件标识符（inode/creation_time）和条目计数功能

历史文件采用 **append-only** 设计哲学，符合审计日志的最佳实践，同时支持高效的尾部追加和流式读取。

## 功能点目的

### 1. 历史条目追加 (`append_entry`)
- **目的**：将新的对话记录原子性地追加到历史文件
- **配置感知**：根据 `config.history.persistence` 设置决定是否写入（`SaveAll` 或 `None`）
- **并发控制**：使用 POSIX 建议性文件锁（`try_lock`）配合重试机制，防止多进程写入冲突
- **异步执行**：通过 `spawn_blocking` 避免阻塞异步运行时

### 2. 存储限制管理 (`enforce_history_limit`)
- **目的**：防止历史文件无限增长
- **硬限制** (`max_bytes`)：文件大小的绝对上限
- **软限制** (`HISTORY_SOFT_CAP_RATIO = 0.8`)：修剪后保留的目标大小，避免频繁修剪
- **策略**：从文件开头删除最旧的记录，始终保留最新条目

### 3. 元数据查询 (`history_metadata`)
- **目的**：获取历史文件的标识符和当前条目数量
- **文件标识**：Unix 使用 inode，Windows 使用 creation_time
- **条目计数**：通过统计换行符数量实现

### 4. 历史条目查找 (`lookup`)
- **目的**：根据文件标识符和偏移量检索特定历史记录
- **一致性保证**：通过比较文件标识符确保读取的是同一文件版本
- **共享锁读取**：使用 `try_lock_shared` 实现并发安全的读取

## 具体技术实现

### 关键数据结构

```rust
/// 历史条目结构
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct HistoryEntry {
    pub session_id: String,  // 会话/线程 ID（向后兼容保留 conversation_id 语义）
    pub ts: u64,             // Unix 时间戳（秒）
    pub text: String,        // 消息内容
}
```

### 核心流程

#### 追加写入流程
```
1. 检查 HistoryPersistence 配置
2. 构造 HistoryEntry（序列化为 JSON + \n）
3. 创建/打开文件（Unix: O_APPEND + 0o600 权限）
4. spawn_blocking 执行阻塞写入
5. 尝试获取独占文件锁（最多 MAX_RETRIES=10 次）
6. seek 到文件末尾
7. 写入完整行
8. 调用 enforce_history_limit 修剪
9. 释放锁
```

#### 修剪算法流程
```
1. 检查当前文件大小是否超过 max_bytes
2. 计算软限制目标：max_bytes * 0.8，且 >= 最新条目长度
3. 逐行读取，记录每行长度
4. 从开头累计删除字节，直到满足软限制
5. 读取剩余尾部内容到内存
6. 截断文件并写入尾部
```

#### 条目查找流程
```
1. 打开历史文件
2. 获取文件元数据，计算 log_id
3. 验证 log_id 匹配（确保文件未被替换）
4. 获取共享锁（最多重试 MAX_RETRIES 次）
5. 逐行读取到指定 offset
6. 解析并返回 HistoryEntry
```

### 平台适配

| 平台 | 文件标识 | 权限控制 |
|------|----------|----------|
| Unix | inode (`metadata.ino()`) | 强制 0o600 (rw-------) |
| Windows | creation_time | 无特殊处理 |
| 其他 | 不支持 (返回 None) | 无特殊处理 |

### 常量定义

```rust
const HISTORY_FILENAME: &str = "history.jsonl";           // 历史文件名
const HISTORY_SOFT_CAP_RATIO: f64 = 0.8;                  // 软限制比例
const MAX_RETRIES: usize = 10;                            // 锁获取最大重试次数
const RETRY_SLEEP: Duration = Duration::from_millis(100); // 重试间隔
```

## 关键代码路径与文件引用

### 本文件关键函数

| 函数 | 行号 | 可见性 | 说明 |
|------|------|--------|------|
| `append_entry` | 84-165 | pub | 异步追加历史条目 |
| `enforce_history_limit` | 171-244 | private | 强制执行存储限制 |
| `history_metadata` | 261-264 | pub | 获取历史文件元数据 |
| `lookup` | 276-279 | pub | 同步查找历史条目 |
| `lookup_history_entry` | 332-399 | private | 实际查找实现 |
| `history_metadata_for_file` | 303-330 | private | 元数据获取实现 |
| `ensure_owner_only_permissions` | 284-301 | private | 权限设置（平台相关） |
| `history_log_id` | 402-416 | private | 计算文件标识符（平台相关） |

### 依赖类型

```rust
// 配置相关
crate::config::Config
crate::config::types::HistoryPersistence

// 协议类型
codex_protocol::ThreadId

// 序列化
serde::Serialize, serde::Deserialize

// 异步运行时
tokio::fs, tokio::io::AsyncReadExt
tokio::task::spawn_blocking

// 文件锁（std）
std::fs::File::try_lock, try_lock_shared
```

### 调用方引用

- `codex_protocol::protocol.rs` - 协议层调用历史记录功能

## 依赖与外部交互

### 上游依赖（被调用）

1. **Config 模块** (`crate::config`)
   - `Config::codex_home` - 确定历史文件存储位置
   - `Config::history.persistence` - 控制是否启用历史记录
   - `Config::history.max_bytes` - 存储限制配置

2. **协议模块** (`codex_protocol`)
   - `ThreadId` - 会话标识符类型

3. **Tokio 运行时**
   - 异步文件操作
   - `spawn_blocking` 用于执行阻塞 I/O

4. **标准库**
   - `std::fs::File` - 文件锁机制（`try_lock`, `try_lock_shared`）
   - `std::os::unix::fs::OpenOptionsExt` - Unix 特定选项（append, mode）
   - `std::os::unix::fs::PermissionsExt` - Unix 权限设置

### 下游消费（调用本模块）

- 协议层通过历史记录功能实现消息检索和复用
- TUI 层可能通过历史记录实现消息搜索功能

## 风险、边界与改进建议

### 已知风险

1. **文件锁限制**
   - POSIX 建议性锁不是强制性的，其他不遵守锁协议的进程仍可写入
   - 锁在进程退出时自动释放，但写入操作可能不完整

2. **修剪操作的原子性**
   - `enforce_history_limit` 在持有锁的情况下执行读-改-写操作
   - 如果进程在修剪过程中崩溃，可能留下不完整的数据

3. **WSL/跨平台兼容性**
   - Windows 使用 creation_time 作为文件标识，在文件系统不支持时可能不可靠
   - Unix 权限设置在其他平台上是空操作

4. **内存使用**
   - 修剪大文件时需要将整个尾部加载到内存
   - 极端情况下（数百万条记录）可能影响性能

### 边界条件

| 场景 | 处理行为 |
|------|----------|
| `max_bytes = 0` | 跳过限制检查，不修剪 |
| `max_bytes` 溢出 u64 | 跳过限制检查 |
| 文件不存在 | `history_metadata` 返回 (0, 0)；`lookup` 返回 None |
| 锁获取失败（超时） | 返回 `WouldBlock` 错误 |
| 单条记录超过 `max_bytes` | 保留该记录，文件大小可能超过限制 |
| 无效 JSON | `lookup` 返回 None 并记录警告 |
| 循环符号链接 | `lookup` 返回 None（通过 visited set 检测） |

### 改进建议

1. **增强修剪策略**
   - 考虑按时间而非单纯按大小修剪（如保留最近 N 天的记录）
   - 添加压缩选项（gzip）减少磁盘占用

2. **改进并发模型**
   - 考虑使用 SQLite 替代 JSON Lines，获得更好的并发支持和查询能力
   - 实现基于 WAL（Write-Ahead Logging）的写入模式

3. **增强可观测性**
   - 添加指标：历史文件大小、条目数量、修剪频率
   - 记录更详细的操作日志（debug/trace 级别）

4. **安全加固**
   - 对 `text` 内容进行敏感信息扫描（TODO 注释中已提及）
   - 考虑对历史文件进行加密存储选项

5. **性能优化**
   - 实现基于索引的查找，避免每次从头扫描
   - 考虑内存映射（mmap）大文件读取

6. **测试覆盖**
   - 添加并发写入压力测试
   - 测试文件系统满、权限不足等错误场景
