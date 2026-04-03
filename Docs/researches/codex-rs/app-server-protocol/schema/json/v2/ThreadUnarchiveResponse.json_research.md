# ThreadUnarchiveResponse.json 研究文档

## 场景与职责

`ThreadUnarchiveResponse` 是 Codex App-Server Protocol v2 中定义的 `thread/unarchive` 请求的响应类型。当客户端成功请求解归档一个 Thread 后，服务器返回此响应，包含恢复后的完整 Thread 对象。这是 Thread 生命周期管理中归档/解归档流程的关键组成部分。

典型使用场景：
- 客户端请求解归档后接收恢复的 Thread 数据
- 更新客户端本地缓存的 Thread 信息
- 导航到恢复的 Thread 继续对话
- 验证解归档操作的成功和完整性

## 功能点目的

该响应类型的主要目的是：
1. **确认操作成功**：向客户端确认 Thread 已成功解归档
2. **提供完整数据**：返回解归档后的完整 Thread 对象，包含所有元数据
3. **状态同步**：确保客户端获得 Thread 的最新状态
4. **支持后续操作**：客户端可以基于返回的 Thread 数据继续操作

### Thread 对象包含的关键信息

| 字段 | 描述 |
|------|------|
| `id` | Thread 唯一标识符 |
| `preview` | Thread 预览文本（通常是第一条用户消息） |
| `ephemeral` | 是否为临时 Thread（不持久化到磁盘） |
| `modelProvider` | 使用的模型提供商 |
| `createdAt` | 创建时间戳（Unix 秒） |
| `updatedAt` | 最后更新时间戳（Unix 秒） |
| `status` | 当前运行状态 |
| `path` | Thread 在磁盘上的路径（可选） |
| `cwd` | 工作目录 |
| `cliVersion` | 创建时使用的 CLI 版本 |
| `source` | Thread 来源（CLI、VSCode、Exec 等） |
| `name` | 用户定义的 Thread 名称（可选） |
| `turns` | Thread 中的 Turn 列表（通常为空） |

## 具体技术实现

### JSON Schema 结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "properties": {
    "thread": { "$ref": "#/definitions/Thread" }
  },
  "required": ["thread"]
}
```

注意：此 Schema 文件非常大（约 44KB），因为它内联了完整的 `Thread` 类型定义，包括所有相关的子类型如 `ThreadItem`、`Turn`、`UserInput` 等。

### Rust 实现

位于 `codex-rs/app-server-protocol/src/protocol/v2.rs`（行 2857-2862）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadUnarchiveResponse {
    pub thread: Thread,
}
```

### Thread 结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct Thread {
    pub id: String,
    pub preview: String,
    pub ephemeral: bool,
    pub model_provider: String,
    #[ts(type = "number")]
    pub created_at: i64,
    #[ts(type = "number")]
    pub updated_at: i64,
    pub status: ThreadStatus,
    pub path: Option<PathBuf>,
    pub cwd: PathBuf,
    pub cli_version: String,
    pub source: SessionSource,
    pub agent_nickname: Option<String>,
    pub agent_role: Option<String>,
    pub git_info: Option<GitInfo>,
    pub name: Option<String>,
    pub turns: Vec<Turn>,
}
```

### 客户端请求定义

在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中：

```rust
client_request_definitions! {
    ThreadUnarchive => "thread/unarchive" {
        params: v2::ThreadUnarchiveParams,
        response: v2::ThreadUnarchiveResponse,
    },
    // ...
}
```

## 关键代码路径与文件引用

### 核心定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/schema/json/v2/ThreadUnarchiveResponse.json` | JSON Schema 定义（约 44KB） |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构体定义（行 2857-2862） |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Thread 结构定义（行 3472-3512） |

### Schema 文件结构

`ThreadUnarchiveResponse.json` 包含以下内联定义：
- `Thread` - 完整的 Thread 类型
- `ThreadItem` - Thread 中的项目类型（多种变体）
- `Turn` - 对话轮次
- `TurnError` - Turn 错误信息
- `UserInput` - 用户输入类型
- `CommandAction` - 命令动作解析
- `PatchChangeKind` - 补丁变更类型
- `GitInfo` - Git 元数据
- `SessionSource` - 会话来源
- `ThreadStatus` - Thread 状态
- 以及许多其他辅助类型

### 服务端处理代码

位于 `codex-rs/app-server/src/codex_message_processor.rs`：
- 处理 `thread/unarchive` 请求
- 构建 `ThreadUnarchiveResponse` 响应
- 序列化并发送给客户端

### 测试文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/tests/suite/v2/thread_unarchive.rs` | 解归档功能测试 |

## 依赖与外部交互

### 上游依赖

1. **Thread 存储系统**：从磁盘加载归档的 Thread 数据
2. **Thread 序列化**：反序列化 Thread 的持久化数据
3. **codex_protocol**：核心 Thread 类型定义

### 下游消费者

1. **客户端应用**：接收并处理解归档响应
2. **UI 组件**：使用返回的 Thread 数据更新界面
3. **本地缓存**：客户端可能缓存返回的 Thread 数据

### 相关类型

| 类型 | 说明 |
|------|------|
| `ThreadUnarchiveParams` | 解归档请求参数 |
| `Thread` | 响应中包含的核心 Thread 类型 |
| `ThreadUnarchivedNotification` | 解归档完成后的广播通知 |

## 风险、边界与改进建议

### 潜在风险

1. **响应体积过大**：完整的 Thread 定义导致 Schema 文件约 44KB，可能影响解析性能
2. **数据一致性**：返回的 Thread 状态可能与实际磁盘状态不一致（并发修改）
3. **敏感信息泄露**：Thread 可能包含敏感信息，需要适当的访问控制

### 边界情况

1. **Turns 为空**：根据注释，解归档响应中的 `turns` 字段通常为空列表
2. **路径不可用**：`path` 字段标记为 `[UNSTABLE]`，可能为 null
3. **Git 信息缺失**：`git_info` 可能为 null，如果创建时未捕获 Git 状态
4. **子代理 Thread**：`agent_nickname` 和 `agent_role` 仅在子代理 Thread 中设置

### 改进建议

1. **延迟加载 Turns**：考虑不在解归档响应中包含 turns，让客户端按需通过 `thread/read` 获取
2. **响应压缩**：对于大型 Thread，考虑压缩响应数据
3. **选择性字段**：支持客户端指定需要返回的字段子集
4. **版本控制**：添加 Thread 数据格式版本信息，便于未来迁移
5. **增量更新**：如果 Thread 已被客户端缓存，支持增量更新响应

### 性能考虑

- Schema 文件较大（44KB），但主要是文档和类型定义
- 实际响应大小取决于 Thread 的 turns 数量（通常为空）
- 建议在客户端实现响应缓存，避免重复获取相同 Thread 数据

### 版本兼容性

- 当前为 v2 API，遵循 camelCase 命名规范
- Thread 结构中的 `path` 字段标记为 `[UNSTABLE]`，未来可能变更
- `turns` 字段的行为在不同 API 调用中有所不同（详见注释）
