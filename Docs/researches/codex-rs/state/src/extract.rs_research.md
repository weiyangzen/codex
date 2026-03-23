# extract.rs 深度研究文档

## 场景与职责

`extract.rs` 是 `codex-state` crate 的核心模块之一，负责从 JSONL rollout 文件中提取和解析元数据，并将其应用到 `ThreadMetadata` 结构中。它是连接原始 rollout 数据与 SQLite 状态存储的桥梁，确保线程元数据能够正确地从文件系统中同步到数据库。

### 核心职责
1. **Rollout Item 解析与处理**：解析不同类型的 rollout items（SessionMeta、TurnContext、EventMsg、ResponseItem、Compacted）
2. **元数据提取与更新**：将 rollout 中的信息提取并应用到 ThreadMetadata 结构
3. **标题生成**：从用户消息中提取线程标题
4. **枚举序列化**：提供通用的枚举到字符串的转换工具

## 功能点目的

### 1. `apply_rollout_item` - 核心应用函数

这是模块的主要入口点，将单个 rollout item 应用到 metadata 结构：

```rust
pub fn apply_rollout_item(
    metadata: &mut ThreadMetadata,
    item: &RolloutItem,
    default_provider: &str,
)
```

**处理逻辑**：
- `SessionMeta`：应用会话元数据（ID、来源、昵称、角色、模型提供者、CLI 版本、工作目录、Git 信息）
- `TurnContext`：应用轮次上下文（工作目录、模型、推理努力度、沙盒策略、审批模式）
- `EventMsg`：处理事件消息（Token 计数、用户消息）
- `ResponseItem`：当前不处理（标题和首条用户消息仅从 EventMsg 派生）
- `Compacted`：忽略

**默认提供者回退**：如果 metadata 中没有设置 model_provider，则使用传入的 default_provider。

### 2. `rollout_item_affects_thread_metadata` - 变更检测

判断一个 rollout item 是否会改变线程元数据：

```rust
pub fn rollout_item_affects_thread_metadata(item: &RolloutItem) -> bool
```

**返回 true 的情况**：
- `SessionMeta` / `TurnContext`：总是影响
- `EventMsg::TokenCount` / `EventMsg::UserMessage`：影响
- 其他情况：不影响

这个函数用于优化，避免不必要的数据库写入。

### 3. `apply_session_meta_from_item` - 会话元数据处理

处理 SessionMetaLine，提取：
- 线程 ID（会验证匹配，不匹配则忽略，用于处理 forked rollouts）
- 来源、昵称、角色
- 模型提供者
- CLI 版本
- 工作目录
- Git 信息（SHA、分支、远程 URL）

**注意**：如果 meta_line 中的 cwd 为空，则不会覆盖现有的 cwd。

### 4. `apply_turn_context` - 轮次上下文处理

处理 TurnContextItem，提取：
- 工作目录（仅在现有 cwd 为空时设置）
- 模型名称
- 推理努力度（ReasoningEffort）
- 沙盒策略
- 审批模式

### 5. `apply_event_msg` - 事件消息处理

处理 EventMsg 变体：
- `TokenCount`：更新 tokens_used 字段
- `UserMessage`：提取首条用户消息和标题

### 6. 标题和首条消息提取

```rust
fn strip_user_message_prefix(text: &str) -> &str
fn user_message_preview(user: &UserMessageEvent) -> Option<String>
```

**逻辑**：
- 去除 `USER_MESSAGE_BEGIN` 前缀
- 如果消息为空但有图片，使用 `[Image]` 占位符
- 标题从首条非空用户消息派生

### 7. `enum_to_string` - 枚举序列化工具

通用的枚举到字符串转换函数，使用 serde_json 进行序列化：

```rust
pub(crate) fn enum_to_string<T: Serialize>(value: &T) -> String
```

## 具体技术实现

### 关键流程

```
RolloutItem
    ├── SessionMeta ────────► apply_session_meta_from_item
    │                           ├── 验证线程 ID
    │                           ├── 提取基础元数据
    │                           └── 提取 Git 信息
    │
    ├── TurnContext ────────► apply_turn_context
    │                           ├── 设置工作目录（条件）
    │                           ├── 设置模型
    │                           ├── 设置推理努力度
    │                           └── 设置策略/模式
    │
    ├── EventMsg ───────────► apply_event_msg
    │                           ├── TokenCount ──► 更新 tokens_used
    │                           └── UserMessage ─► 提取标题和预览
    │
    ├── ResponseItem ───────► apply_response_item (空实现)
    │
    └── Compacted ──────────► 忽略
```

### 数据结构

**ThreadMetadata**（来自 model/thread_metadata.rs）：
- 基础信息：id, rollout_path, created_at, updated_at
- 来源信息：source, agent_nickname, agent_role
- 模型信息：model_provider, model, reasoning_effort
- 环境信息：cwd, cli_version
- 内容信息：title, first_user_message, tokens_used
- 策略信息：sandbox_policy, approval_mode
- 归档信息：archived_at
- Git 信息：git_sha, git_branch, git_origin_url

**RolloutItem**（来自 codex_protocol）：
```rust
pub enum RolloutItem {
    SessionMeta(SessionMetaLine),
    TurnContext(TurnContextItem),
    EventMsg(EventMsg),
    ResponseItem(ResponseItem),
    Compacted(CompactedItem),
}
```

### 关键常量

```rust
const IMAGE_ONLY_USER_MESSAGE_PLACEHOLDER: &str = "[Image]";
```

## 关键代码路径与文件引用

### 内部依赖

| 文件 | 用途 |
|------|------|
| `model/thread_metadata.rs` | ThreadMetadata 结构定义 |
| `model/mod.rs` | 模型模块导出 |
| `lib.rs` | 模块导出（apply_rollout_item, rollout_item_affects_thread_metadata） |

### 外部依赖

| Crate | 模块/类型 | 用途 |
|-------|----------|------|
| `codex_protocol` | `ThreadMetadata` | 协议层元数据类型 |
| `codex_protocol` | `ResponseItem` | 响应项类型 |
| `codex_protocol::protocol` | `EventMsg`, `RolloutItem`, `SessionMetaLine` | 协议事件类型 |
| `codex_protocol::protocol` | `TurnContextItem`, `UserMessageEvent` | 上下文类型 |
| `codex_protocol::protocol` | `USER_MESSAGE_BEGIN` | 消息前缀常量 |
| `serde` | `Serialize` | 枚举序列化 |
| `serde_json` | `Value` | JSON 处理 |

### 测试覆盖

测试文件位于 `extract.rs` 底部（约 300 行测试代码）：

1. `response_item_user_messages_do_not_set_title_or_first_user_message`：验证 ResponseItem 不影响标题
2. `event_msg_user_messages_set_title_and_first_user_message`：验证 EventMsg 正确设置标题
3. `event_msg_image_only_user_message_sets_image_placeholder_preview`：图片消息占位符
4. `event_msg_blank_user_message_without_images_keeps_first_user_message_empty`：空消息处理
5. `turn_context_does_not_override_session_cwd`：TurnContext 不覆盖 Session cwd
6. `turn_context_sets_cwd_when_session_cwd_missing`：TurnContext 作为 cwd 回退
7. `turn_context_sets_model_and_reasoning_effort`：模型和推理努力度设置
8. `session_meta_does_not_set_model_or_reasoning_effort`：SessionMeta 不设置模型信息
9. `diff_fields_detects_changes`：元数据差异检测

## 依赖与外部交互

### 上游调用方

1. **runtime/threads.rs**：`apply_rollout_items` 方法调用 `apply_rollout_item`
2. **lib.rs**：导出给外部 crate 使用

### 下游被调用方

1. **codex-core**：可能通过 `StateRuntime` 间接使用

### 数据流

```
JSONL Rollout File
    │
    ▼
RolloutItem (parsed by codex-protocol)
    │
    ▼
apply_rollout_item()
    │
    ▼
ThreadMetadata (updated)
    │
    ▼
SQLite (via StateRuntime)
```

## 风险、边界与改进建议

### 潜在风险

1. **ID 不匹配静默忽略**：`apply_session_meta_from_item` 中如果 ID 不匹配直接返回，可能导致 forked rollouts 的元数据丢失
2. **枚举序列化失败**：`enum_to_string` 在序列化失败时返回空字符串，可能导致数据丢失
3. **cwd 条件更新逻辑**：TurnContext 仅在 cwd 为空时设置，可能不符合预期

### 边界情况

1. **空用户消息**：处理空消息 + 无图片的情况（返回 None）
2. **图片消息**：纯图片消息使用 `[Image]` 占位符
3. **默认提供者回退**：当 model_provider 为空时使用 default_provider
4. **Git 信息优先级**：现有 Git 信息优先于 rollout 中的信息

### 改进建议

1. **增加日志记录**：在 ID 不匹配时添加警告日志
2. **错误处理优化**：`enum_to_string` 失败时考虑返回 Result 而非空字符串
3. **文档完善**：`apply_response_item` 的空实现应添加更详细的注释说明原因
4. **性能优化**：考虑缓存 `USER_MESSAGE_BEGIN` 的查找结果
5. **测试覆盖**：增加对 `enum_to_string` 错误路径的测试

### 代码质量

- 遵循了 Rust 的 Result/Option 处理惯例
- 使用了模式匹配处理不同 RolloutItem 变体
- 测试覆盖较全面，包括边界情况
- 代码结构清晰，职责单一
