# ThreadSetNameParams.json 研究文档

## 场景与职责

`ThreadSetNameParams` 是 Codex App Server Protocol v2 中 `thread/name/set` 方法的请求参数结构，用于为线程设置用户可见的显示名称（标题）。这是线程元数据管理的基础 API。

该功能允许用户：
- 为线程设置有意义的标题，便于识别和管理
- 在会话列表中区分不同的对话线程
- 通过名称快速定位历史会话

## 功能点目的

### 核心功能
- **线程命名**: 为线程设置用户友好的显示名称
- **持久化存储**: 名称会被持久化到磁盘，跨会话保持
- **实时同步**: 名称变更会广播给所有连接的客户端

### 使用场景
1. 用户手动为重要对话设置描述性标题
2. 客户端根据对话内容自动生成建议标题
3. 多客户端场景下同步线程名称变更

## 具体技术实现

### 数据结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadSetNameParams {
    /// 目标线程 ID
    pub thread_id: String,
    /// 线程显示名称
    pub name: String,
}
```

### JSON Schema 定义

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "properties": {
    "name": {
      "type": "string"
    },
    "threadId": {
      "type": "string"
    }
  },
  "required": ["name", "threadId"],
  "title": "ThreadSetNameParams",
  "type": "object"
}
```

### 关键流程

1. **请求处理入口**: `CodexMessageProcessor::thread_set_name()` (codex_message_processor.rs:2290)
2. **参数解析**: 提取 thread_id 和 name
3. **线程 ID 验证**: 解析并验证 thread_id 格式
4. **名称规范化**: 使用 `codex_core::util::normalize_thread_name()` 清理名称
5. **空名称检查**: 拒绝空字符串名称
6. **已加载线程处理**:
   - 如果线程已加载，通过 `Op::SetThreadName` 提交核心操作
7. **未加载线程处理**:
   - 检查线程是否存在
   - 调用 `codex_core::append_thread_name()` 直接写入名称文件
8. **响应返回**: 返回空的 `ThreadSetNameResponse`
9. **通知广播**: 发送 `ThreadNameUpdatedNotification` 给所有客户端

### 名称规范化

```rust
let Some(name) = codex_core::util::normalize_thread_name(&name) else {
    self.send_invalid_request_error(
        request_id,
        "thread name must not be empty".to_string(),
    )
    .await;
    return;
};
```

### 通知机制

```rust
let notification = ThreadNameUpdatedNotification {
    thread_id: thread_id.to_string(),
    thread_name: Some(name),
};
self.outgoing
    .send_server_notification(ServerNotification::ThreadNameUpdated(notification))
    .await;
```

## 关键代码路径与文件引用

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/v2.rs`: ThreadSetNameParams 结构体定义
- `codex-rs/app-server-protocol/src/protocol/common.rs`: ClientRequest 枚举 ThreadSetName 变体

### 服务端实现
- `codex-rs/app-server/src/codex_message_processor.rs`:
  - `thread_set_name()` 方法 (line 2290-2364)

### 测试用例
- `codex-rs/app-server/tests/suite/v2/thread_name_websocket.rs`:
  - `thread_name_updated_broadcasts_for_loaded_threads`: 已加载线程的名称广播
  - `thread_name_updated_broadcasts_for_not_loaded_threads`: 未加载线程的名称广播

### TypeScript 类型定义
- `codex-rs/app-server-protocol/schema/typescript/v2/ThreadSetNameParams.ts`

## 依赖与外部交互

### 内部依赖
- **codex_core**: 
  - `util::normalize_thread_name()` 名称规范化
  - `append_thread_name()` 持久化名称到文件
- **codex_protocol**: `ThreadId` 类型解析

### 外部交互
- **文件系统**: 名称存储在 `$CODEX_HOME/thread_names/{thread_id}.txt`
- **SQLite**: 可选的 state_db 元数据更新

### 响应结构
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadSetNameResponse {}
```

响应体为空对象，仅表示操作成功。

## 风险、边界与改进建议

### 已知风险

1. **名称冲突**: 无全局唯一性约束，多个线程可以有相同名称
2. **长度限制**: 当前实现未明确限制名称长度，可能导致 UI 截断问题
3. **特殊字符**: 名称规范化可能过度清理某些合法字符

### 边界情况

1. **空名称**: 服务端拒绝空字符串，返回无效请求错误
2. **仅空白字符**: `normalize_thread_name()` 会返回 None，视为空名称
3. **线程不存在**: 返回 "thread not found" 错误
4. **无效线程 ID**: 返回 "invalid thread id" 错误

### 改进建议

1. **长度限制**: 添加明确的名称长度限制（如 100 字符）
2. **重复检测**: 可选的同名线程警告机制
3. **表情符号支持**: 验证名称规范化是否正确处理 Unicode 表情
4. **历史名称**: 考虑保留名称变更历史
5. **自动生成**: 集成 AI 自动生成描述性标题

### 安全考虑
- 名称内容应进行适当的清理，防止 XSS 攻击
- 考虑对名称进行长度限制，防止拒绝服务攻击
