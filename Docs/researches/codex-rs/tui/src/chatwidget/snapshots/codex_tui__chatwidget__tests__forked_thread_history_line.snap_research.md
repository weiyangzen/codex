# 研究文档: forked_thread_history_line.snap

## 场景与职责

该快照文件测试分叉线程（forked thread）历史记录行的渲染效果。当用户从现有线程创建分支时显示此信息。

## 功能点目的

1. **分支标识**: 标识当前线程是从哪个线程分叉的
2. **历史追溯**: 帮助用户理解线程的演变关系
3. **命名显示**: 显示源线程的名称和ID

## 具体技术实现

### 测试数据

```rust
let forked_from_id = ThreadId::from_string("e9f18a88-8081-4e51-9d4e-8af5cde2d8dd").expect("forked id");
let session_index_entry = format!(
    "{{\"id\":\"{forked_from_id}\",\"thread_name\":\"named-thread\",\"updated_at\":\"2024-01-02T00:00:00Z\"}}\n"
);

chat.emit_forked_thread_event(forked_from_id);
```

### 渲染输出

```
Thread forked from "named-thread" (e9f18a88)
```

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs` (行 562-597)
- **会话索引**: `session_index.jsonl` 解析
- **事件发射**: `emit_forked_thread_event` 方法

## 依赖与外部交互

1. **会话管理**: `codex-core` 的线程管理

## 改进建议
1. 添加分叉时间戳显示
2. 提供跳转到源线程的链接
3. 显示分叉时的消息上下文
