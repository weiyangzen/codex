# user_notification.rs 研究文档

## 场景与职责

`user_notification.rs` 是 codex-hooks crate 中的用户通知模块，与 `legacy_notify.rs` 功能高度相似，都是实现**遗留通知机制**。该模块负责在 Agent 完成一轮对话后，通过外部命令触发用户通知（如桌面通知、声音提示等）。

**注意**：经代码对比分析，`user_notification.rs` 和 `legacy_notify.rs` 内容几乎完全相同，可能是：
1. 历史遗留的重复文件
2. 重构过程中的过渡文件
3. 不同用途的变体（但当前代码未体现差异）

## 功能点目的

### 1. 遗留通知钩子创建 (`notify_hook`)
- **目的**：创建一个可在 `AfterAgent` 事件后执行的钩子
- **输入**：命令行参数向量 `argv`
- **输出**：`Hook` 结构体

### 2. JSON 通知负载生成 (`legacy_notify_json`)
- **目的**：将钩子事件负载序列化为特定格式的 JSON
- **支持的事件类型**：仅支持 `AfterAgent` 事件

### 3. 通知数据结构 (`UserNotification`)
- **类型**：内部枚举，仅包含 `AgentTurnComplete` 变体
- **字段**：
  - `thread_id`: 会话线程 ID
  - `turn_id`: 当前轮次 ID
  - `cwd`: 当前工作目录
  - `client`: 客户端标识（可选）
  - `input_messages`: 用户输入消息列表
  - `last_assistant_message`: 助手最后回复（可选）

## 具体技术实现

### 关键流程

```
notify_hook(argv)
  │
  ├─> 创建 Hook 结构体
  │     ├─ name: "legacy_notify"
  │     └─ func: 异步闭包
  │
  └─> 执行时流程
        ├─> command_from_argv(&argv) 解析命令
        ├─> legacy_notify_json(payload) 生成 JSON 负载
        ├─> command.arg(notify_payload) 将 JSON 作为最后一个参数附加
        └─> command.spawn() 异步执行（fire-and-forget）
```

### 与 legacy_notify.rs 的代码对比

| 方面 | user_notification.rs | legacy_notify.rs | 差异 |
|------|---------------------|------------------|------|
| 文件大小 | ~148 行 | ~145 行 | +3 行（注释差异） |
| `UserNotification` 注释 | 有详细字段注释 | 无字段注释 | 文档差异 |
| `legacy_notify_json` 错误处理 | `_ => Err(...)` | `HookEvent::AfterToolUse { .. } => Err(...)` | 匹配模式差异 |
| 导出方式 | 通过 lib.rs | 通过 lib.rs | 相同 |

**关键差异**：

1. **字段文档注释**
   ```rust
   // user_notification.rs 有详细注释
   /// Messages that the user sent to the agent to initiate the turn.
   input_messages: Vec<String>,
   
   /// The last message sent by the assistant in the turn.
   last_assistant_message: Option<String>,
   
   // legacy_notify.rs 无注释
   input_messages: Vec<String>,
   last_assistant_message: Option<String>,
   ```

2. **错误处理匹配**
   ```rust
   // user_notification.rs: 使用通配符
   _ => Err(serde_json::Error::io(...))
   
   // legacy_notify.rs: 显式匹配
   HookEvent::AfterToolUse { .. } => Err(serde_json::Error::io(...))
   ```

### 数据结构

```rust
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(tag = "type", rename_all = "kebab-case")]
enum UserNotification {
    #[serde(rename_all = "kebab-case")]
    AgentTurnComplete {
        thread_id: String,
        turn_id: String,
        cwd: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        client: Option<String>,
        /// Messages that the user sent to the agent to initiate the turn.
        input_messages: Vec<String>,
        /// The last message sent by the assistant in the turn.
        last_assistant_message: Option<String>,
    },
}
```

### 序列化示例

```json
{
  "type": "agent-turn-complete",
  "thread-id": "b5f6c1c2-1111-2222-3333-444455556666",
  "turn-id": "12345",
  "cwd": "/Users/example/project",
  "client": "codex-tui",
  "input-messages": ["Rename `foo` to `bar` and update the callsites."],
  "last-assistant-message": "Rename complete and verified `cargo build` succeeds."
}
```

## 关键代码路径与文件引用

### 当前文件关键代码

| 行号 | 代码 | 说明 |
|------|------|------|
| 12-30 | `UserNotification` 枚举定义 | 带详细字段注释 |
| 32-48 | `legacy_notify_json` 函数 | JSON 负载生成 |
| 50-78 | `notify_hook` 函数 | 钩子创建 |
| 65-69 | 命令配置 | 注释说明 "Backwards-compat" |

### 跨文件引用

| 引用目标 | 路径 | 用途 |
|----------|------|------|
| `Hook` | `types.rs` | 钩子结构体定义 |
| `HookEvent` | `types.rs` | 钩子事件枚举 |
| `HookPayload` | `types.rs` | 钩子负载结构 |
| `HookResult` | `types.rs` | 钩子执行结果枚举 |
| `command_from_argv` | `registry.rs` | 命令行解析工具函数 |

### 与 legacy_notify.rs 的关系

```
lib.rs
  ├─> mod legacy_notify;  // 声明 legacy_notify 模块
  ├─> mod user_notification;  // 声明 user_notification 模块（不存在于 lib.rs）
  │
  └─> pub use legacy_notify::legacy_notify_json;  // 导出
      pub use legacy_notify::notify_hook;         // 导出
```

**重要发现**：`lib.rs` 中**没有**声明 `user_notification` 模块，也没有导出其内容。该文件当前是**死代码**。

## 依赖与外部交互

### 内部依赖

```
user_notification.rs
  ├─> types.rs: Hook, HookEvent, HookPayload, HookResult
  ├─> registry.rs: command_from_argv
  └─> (未被 lib.rs 引用)
```

### 外部依赖

| Crate | 用途 |
|-------|------|
| `serde` | JSON 序列化 |
| `serde_json` | JSON 字符串生成 |
| `std::process::Stdio` | 进程 stdio 控制 |
| `std::sync::Arc` | 共享所有权 |

## 风险、边界与改进建议

### 关键发现：死代码

`user_notification.rs` **未被项目引用**，属于死代码。证据：

1. `lib.rs` 中没有 `mod user_notification;`
2. `lib.rs` 中导出的 `legacy_notify_json` 和 `notify_hook` 来自 `legacy_notify` 模块
3. `cargo build` 不会编译该文件（未被引用）

### 可能的历史原因

| 假设 | 解释 |
|------|------|
| 重构遗留 | 从 `user_notification` 重命名为 `legacy_notify`，但旧文件未删除 |
| 功能分支 | 计划中的功能变体，但未完成 |
| 文档改进 | 添加了字段注释的版本，但未替换原文件 |

### 建议行动

1. **立即行动：确认文件状态**
   ```bash
   # 验证文件是否被引用
   grep -r "user_notification" codex-rs/hooks/src/
   grep -r "mod user_notification" codex-rs/hooks/src/
   ```

2. **若确认为死代码**
   - 删除 `user_notification.rs`
   - 或将 `legacy_notify.rs` 的改进（字段注释）合并过来

3. **若计划使用**
   - 在 `lib.rs` 中添加 `mod user_notification;`
   - 明确与 `legacy_notify` 的差异和用途

### 代码质量对比

| 指标 | user_notification.rs | legacy_notify.rs | 评价 |
|------|---------------------|------------------|------|
| 文档注释 | ✓ 详细 | ✗ 缺失 | user_notification 更好 |
| 错误处理 | 通配符 `_` | 显式匹配 | legacy_notify 更清晰 |
| 代码行数 | 148 | 145 | 相当 |
| 测试覆盖 | 相同 | 相同 | 共享测试 |

### 合并建议

若决定保留一个文件，建议采用以下合并策略：

```rust
// 保留 legacy_notify.rs，但添加以下改进：

// 1. 添加字段文档注释（来自 user_notification.rs）
/// Messages that the user sent to the agent to initiate the turn.
input_messages: Vec<String>,

/// The last message sent by the assistant in the turn.
last_assistant_message: Option<String>,

// 2. 保持显式匹配（legacy_notify.rs 的方式）
HookEvent::AfterToolUse { .. } => Err(...)

// 3. 保留 "Backwards-compat" 注释（user_notification.rs 的方式）
// Backwards-compat: match legacy notify behavior (argv + JSON arg, fire-and-forget).
```

### 风险总结

| 风险 | 等级 | 说明 |
|------|------|------|
| 代码重复维护 | 中 | 两个文件内容相似，可能同步不一致 |
| 死代码混淆 | 高 | 新开发者可能困惑于该文件用途 |
| 构建冗余 | 低 | 未被引用，不影响构建 |
| 测试误导 | 中 | 测试文件中的导入可能指向错误模块 |

### 最终建议

1. **短期**：在代码注释中添加说明，标记该文件为 "未使用"
2. **中期**：决定合并或删除策略，执行清理
3. **长期**：建立代码审查检查，防止类似死代码积累
