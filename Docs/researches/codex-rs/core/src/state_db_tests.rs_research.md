# state_db_tests.rs 研究文档

## 场景与职责

`state_db_tests.rs` 是 `state_db.rs` 的单元测试模块，位于 `state_db.rs` 文件末尾通过 `#[cfg(test)]` 条件编译引入。

**测试范围：**
- 游标（Cursor）与锚点（Anchor）之间的转换逻辑
- 时间戳格式解析的兼容性验证

## 功能点目的

### 测试：游标到锚点的转换与时间戳规范化

验证 `cursor_to_anchor` 函数能够正确解析两种时间戳格式：
1. 文件名格式：`2026-01-27T12-34-56`（`%Y-%m-%dT%H-%M-%S`）
2. RFC3339 格式

## 具体技术实现

### 测试用例

```rust
#[test]
fn cursor_to_anchor_normalizes_timestamp_format()
```

**测试流程：**
1. 生成随机 UUID
2. 构造时间戳字符串 `2026-01-27T12-34-56`
3. 构建游标 token: `{ts_str}|{uuid}`
4. 调用 `parse_cursor` 解析游标
5. 调用 `cursor_to_anchor` 转换为锚点
6. 验证锚点的 ID 和时间戳与预期一致

**关键断言：**
```rust
assert_eq!(anchor.id, uuid);
assert_eq!(anchor.ts, expected_ts);
```

### 依赖

- `Uuid::new_v4()` - 生成测试用 UUID
- `NaiveDateTime::parse_from_str` - 解析预期时间戳
- `DateTime::<Utc>::from_naive_utc_and_offset` - 构建 UTC 时间

## 关键代码路径与文件引用

### 被测函数

| 函数 | 定义位置 | 用途 |
|------|---------|------|
| `cursor_to_anchor` | `state_db.rs:118-136` | 游标到锚点转换 |
| `parse_cursor` | `rollout/list.rs:659-675` | 游标字符串解析 |

### 测试依赖

```rust
use super::*;                    // 引入 state_db 模块
use crate::rollout::list::parse_cursor;
use pretty_assertions::assert_eq;
```

## 依赖与外部交互

### 测试框架

- 使用 Rust 内置测试框架 `#[test]`
- 使用 `pretty_assertions` 提供清晰的差异输出

### 时间处理

- `chrono::NaiveDateTime` - 解析时间戳字符串
- `chrono::DateTime::<Utc>` - UTC 时间处理
- `chrono::Timelike` - 纳秒精度处理

## 风险、边界与改进建议

### 当前覆盖局限

1. **测试范围狭窄**
   - 仅测试游标转换一个功能点
   - 未覆盖：数据库初始化、回填逻辑、read-repair、动态工具管理

2. **无异步测试**
   - 所有数据库操作均为异步，但当前无异步测试用例
   - 未使用 `tokio::test`

3. **无集成测试**
   - 未测试与 `codex_state` crate 的实际交互
   - 未测试文件系统回退场景

### 改进建议

1. **扩展测试覆盖**
   ```rust
   // 建议添加：
   - test_init_creates_runtime()
   - test_get_state_db_returns_none_when_missing()
   - test_list_thread_ids_db_filters_by_source()
   - test_reconcile_rollout_updates_metadata()
   - test_read_repair_fast_path()
   - test_read_repair_slow_path()
   ```

2. **添加异步测试**
   ```rust
   #[tokio::test]
   async fn test_list_threads_db_filters_stale_paths()
   ```

3. **添加错误场景测试**
   - 数据库损坏场景
   - 并发回填竞争场景
   - 无效游标格式处理

4. **使用临时数据库**
   ```rust
   use tempfile::TempDir;
   // 为每个测试创建隔离的临时数据库
   ```

### 测试数据建议

当前使用固定时间戳 `2026-01-27T12-34-56`，建议添加：
- 边界时间戳（Unix 纪元、未来日期）
- 无效时间戳格式
- 包含特殊字符的 UUID
