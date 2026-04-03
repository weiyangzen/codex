# 研究文档: forked_thread_history_line_without_name.snap

## 场景与职责

该快照文件测试当源线程没有名称时，分叉线程历史记录行的渲染效果。

## 功能点目的

1. **无名线程处理**: 处理源线程没有自定义名称的情况
2. **ID显示**: 仅使用线程ID标识源线程
3. **信息完整性**: 即使缺少名称也提供可追溯的信息

## 具体技术实现

### 测试数据

```rust
let forked_from_id = ThreadId::from_string("019c2d47-4935-7423-a190-05691f566092").expect("forked id");
// 注意：没有写入 session_index_entry，模拟无名线程

chat.emit_forked_thread_event(forked_from_id);
```

### 渲染输出

```
Thread forked from 019c2d47-4935-7423-a190-05691f566092
```

### 差异对比

| 有名称 | 无名称 |
|--------|--------|
| `Thread forked from "named-thread" (e9f18a88)` | `Thread forked from 019c2d47...` |
| 显示名称和短ID | 显示完整ID |

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs` (行 599-624)

## 改进建议
1. 对无名线程提供重命名提示
2. 添加创建时间作为替代标识
