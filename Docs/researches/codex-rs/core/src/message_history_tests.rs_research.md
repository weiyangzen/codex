# message_history_tests.rs 深度研究文档

## 场景与职责

`message_history_tests.rs` 是 `message_history.rs` 的配套测试模块，提供对历史记录持久化功能的全面单元测试覆盖。测试使用 `tempfile` 库创建隔离的临时目录，确保测试之间不会相互干扰。

## 功能点目的

### 1. 基本查找功能测试 (`lookup_reads_history_entries`)
- **目的**：验证 `lookup_history_entry` 能够正确读取历史条目
- **测试场景**：创建包含两条记录的历史文件，验证元数据计数和按偏移量查找

### 2. 文件标识稳定性测试 (`lookup_uses_stable_log_id_after_appends`)
- **目的**：验证追加操作后文件标识符（inode）保持不变
- **测试场景**：先写入初始记录获取 log_id，再追加新记录，验证仍可用原 log_id 查找

### 3. 存储限制修剪测试 (`append_entry_trims_history_when_beyond_max_bytes`)
- **目的**：验证当文件大小超过 `max_bytes` 时自动修剪旧记录
- **测试场景**：设置较小的限制，写入两条大记录，验证只保留最新的一条

### 4. 软限制行为测试 (`append_entry_trims_history_to_soft_cap`)
- **目的**：验证软限制（80%）修剪策略的正确性
- **测试场景**：精心构造记录大小，验证修剪后大小符合软限制而非硬限制

## 具体技术实现

### 测试结构

```rust
use super::*;  // 导入被测模块的所有公开项
use crate::config::ConfigBuilder;
use codex_protocol::ThreadId;
use pretty_assertions::assert_eq;
use std::fs::File;
use std::io::Write;
use tempfile::TempDir;
```

### 关键测试工具

| 工具 | 用途 |
|------|------|
| `TempDir` | 创建临时目录，测试结束时自动清理 |
| `ConfigBuilder` | 构建测试用的配置对象 |
| `ThreadId::new()` | 生成唯一的会话标识符 |
| `pretty_assertions::assert_eq` | 提供更易读的断言失败输出 |

### 测试数据构造模式

```rust
// 构造历史条目
HistoryEntry {
    session_id: "first-session".to_string(),
    ts: 1,
    text: "first".to_string(),
}

// 序列化并写入文件
writeln!(file, "{}", serde_json::to_string(&entry).expect("serialize"))
    .expect("write history entry");
```

## 关键代码路径与文件引用

### 测试函数清单

| 测试函数 | 行号 | 测试目标 |
|----------|------|----------|
| `lookup_reads_history_entries` | 9-43 | 基本读取功能 |
| `lookup_uses_stable_log_id_after_appends` | 45-86 | 文件标识稳定性 |
| `append_entry_trims_history_when_beyond_max_bytes` | 88-133 | 硬限制修剪 |
| `append_entry_trims_history_to_soft_cap` | 135-211 | 软限制修剪 |

### 被测函数覆盖

| 被测函数 | 测试覆盖 |
|----------|----------|
| `append_entry` | `append_entry_trims_*` 两个测试 |
| `history_metadata_for_file` | `lookup_reads_*`, `lookup_uses_stable_*` |
| `lookup_history_entry` | `lookup_reads_*`, `lookup_uses_stable_*` |
| `enforce_history_limit` | 间接通过 `append_entry` 测试 |

## 依赖与外部交互

### 测试依赖

```rust
// 被测模块
use super::*;

// 配置构建
use crate::config::ConfigBuilder;

// 协议类型
use codex_protocol::ThreadId;

// 断言增强
use pretty_assertions::assert_eq;

// 文件操作
use std::fs::File;
use std::io::Write;

// 临时目录
use tempfile::TempDir;
```

### 测试环境要求

- 文件系统写入权限
- 支持 `O_APPEND` 标志（Unix）
- 足够的临时磁盘空间

## 风险、边界与改进建议

### 当前测试覆盖 gaps

1. **并发测试缺失**
   - 没有多进程/多线程并发写入测试
   - 没有文件锁竞争场景测试

2. **错误场景覆盖不足**
   - 没有权限不足场景测试
   - 没有磁盘满场景测试
   - 没有损坏 JSON 处理测试

3. **平台特定测试**
   - 没有 Windows 特定的 `creation_time` 测试
   - 没有权限设置测试（Unix 0o600）

4. **大文件测试**
   - 没有百万级记录的性能测试
   - 没有大文件修剪性能测试

### 改进建议

1. **添加并发测试**
```rust
#[tokio::test]
async fn concurrent_appends_do_not_corrupt_file() {
    // 使用多个任务并发写入，验证最终文件完整性
}
```

2. **添加错误处理测试**
```rust
#[tokio::test]
async fn handles_permission_denied_gracefully() {
    // 创建只读目录，验证错误返回
}
```

3. **添加性能基准测试**
```rust
#[tokio::test]
async fn trim_performance_with_large_file() {
    // 测试大文件修剪的性能
}
```

4. **使用 insta snapshot 测试**
   - 对复杂的历史文件内容进行快照测试
   - 便于检测意外的格式变化

### 测试代码质量建议

1. **提取公共辅助函数**
   - `create_history_file(entries: Vec<HistoryEntry>) -> TempDir`
   - `read_all_entries(path: &Path) -> Vec<HistoryEntry>`

2. **参数化测试**
   - 使用 `rstest` 或类似工具参数化不同大小限制场景

3. **改进断言消息**
   - 当前测试使用基本断言，可添加更多上下文信息
