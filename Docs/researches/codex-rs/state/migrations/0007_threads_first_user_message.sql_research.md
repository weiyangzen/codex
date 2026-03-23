# 0007_threads_first_user_message.sql 研究文档

## 场景与职责

本迁移为 `threads` 表添加 `first_user_message` 字段，用于存储会话中第一条用户消息的内容预览。这改善了会话列表的用户体验，使用户能够快速识别会话内容。

## 功能点目的

### 1. 添加 first_user_message 字段
- **字段**: `first_user_message TEXT`
- **约束**: `NOT NULL DEFAULT ''`
- **用途**: 存储第一条用户消息的预览文本

### 2. 数据回填
迁移包含 UPDATE 语句回填现有数据：
```sql
UPDATE threads
SET first_user_message = title
WHERE first_user_message = '' AND has_user_event = 1 AND title <> '';
```

**逻辑说明**:
- 仅更新有用户事件（`has_user_event = 1`）的会话
- 使用现有 `title` 作为预览（如果可用）
- 避免覆盖已有值的记录

## 具体技术实现

### 关键流程
1. **消息提取**: 从 `EventMsg::UserMessage` 事件提取消息内容
2. **预览生成**: 去除前缀，限制长度，生成预览
3. **标题回退**: 如果消息为空，使用会话标题

### 代码映射
在 `codex-rs/state/src/extract.rs` 中：
```rust
fn apply_event_msg(metadata: &mut ThreadMetadata, event: &EventMsg) {
    match event {
        EventMsg::UserMessage(user) => {
            if metadata.first_user_message.is_none() {
                metadata.first_user_message = user_message_preview(user);
            }
            if metadata.title.is_empty() {
                let title = strip_user_message_prefix(user.message.as_str());
                if !title.is_empty() {
                    metadata.title = title.to_string();
                }
            }
        }
        // ...
    }
}

fn user_message_preview(user: &UserMessageEvent) -> Option<String> {
    let message = strip_user_message_prefix(user.message.as_str());
    if !message.is_empty() {
        return Some(message.to_string());
    }
    // 图片占位符处理
    if user.images.as_ref().is_some_and(|images| !images.is_empty())
        || !user.local_images.is_empty()
    {
        return Some(IMAGE_ONLY_USER_MESSAGE_PLACEHOLDER.to_string());
    }
    None
}
```

在 `codex-rs/state/src/model/thread_metadata.rs` 中：
```rust
pub struct ThreadMetadata {
    pub first_user_message: Option<String>,  // None 表示空字符串
    // ...
}
```

## 关键代码路径与文件引用

### 消息提取
- `codex-rs/state/src/extract.rs`:
  - `apply_event_msg()`: 处理用户消息事件
  - `user_message_preview()`: 生成预览文本
  - `strip_user_message_prefix()`: 去除消息前缀

### 数据查询
- `codex-rs/state/src/runtime/threads.rs`:
  - `list_threads()`: 查询包含 `first_user_message` 的线程列表
  - `push_thread_filters()`: 过滤空消息的会话

### UI 展示
- `codex-rs/tui/src/components/thread_list.rs`: 会话列表展示

## 依赖与外部交互

### 上游依赖
- `0001_threads.sql`: 基础 threads 表结构
- `0005_threads_cli_version.sql`: 可能依赖的迁移顺序

### 下游依赖
- 无直接下游依赖

### 协议层
- `codex-protocol/src/protocol.rs`: `UserMessageEvent` 定义

## 风险、边界与改进建议

### 风险
1. **隐私泄露**: 用户消息可能包含敏感信息
2. **长度限制**: 未限制字段长度，可能存储大量文本

### 边界情况
1. **图片消息**: 纯图片消息显示占位符 `[Image]`
2. **空消息**: 空白消息不设置预览
3. **多条消息**: 仅记录第一条用户消息

### 改进建议
1. 考虑添加长度限制（如 200 字符）
2. 考虑敏感信息脱敏处理
3. 可为空预览的会话添加默认提示
4. 考虑支持更新预览（如果第一条消息被编辑）
