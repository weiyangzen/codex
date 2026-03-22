# LocalShellAction Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`LocalShellAction` 是 Codex Protocol 中表示本地 Shell 操作类型的枚举类型。它是 `LocalShellCall` 响应项的子类型，用于区分不同的 Shell 操作类型。

主要使用场景：
- **Shell 命令执行**：模型请求执行本地 Shell 命令
- **操作类型区分**：区分不同类型的 Shell 操作（目前仅支持 exec）
- **响应项构造**：作为 `ResponseItem::LocalShellCall` 的一部分

## 2. 功能点目的 (Purpose of This Type)

- **操作分类**：区分不同类型的 Shell 操作
- **扩展性**：为未来添加其他操作类型（如 shell 脚本、交互式命令）预留扩展点
- **类型安全**：确保操作类型的有效性
- **序列化一致性**：保证 JSON 序列化的稳定性

## 3. 具体技术实现 (Technical Implementation Details)

### 数据结构

```typescript
// TypeScript 定义（由 ts-rs 生成）
import type { LocalShellExecAction } from "./LocalShellExecAction";

export type LocalShellAction = { "type": "exec" } & LocalShellExecAction;
```

```rust
// Rust 定义
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, JsonSchema, TS)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum LocalShellAction {
    Exec(LocalShellExecAction),
}
```

### 关键特性

- **Tagged Union**：使用 `#[serde(tag = "type")]` 实现带标签的联合类型
- **Snake Case 序列化**：变体名使用 snake_case（`"exec"`）
- **内联数据**：`LocalShellExecAction` 的字段内联到序列化输出中

### TypeScript 表示解释

TypeScript 类型使用交叉类型表示：
```typescript
{ "type": "exec" } & LocalShellExecAction
```

这表示对象同时包含：
- `type: "exec"` 字段
- `LocalShellExecAction` 的所有字段（`command`, `timeout_ms`, `working_directory`, `env`, `user`）

### 使用位置

```rust
// 在 ResponseItem::LocalShellCall 中使用
pub enum ResponseItem {
    // ...
    LocalShellCall {
        #[serde(default, skip_serializing)]
        #[ts(skip)]
        id: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        #[ts(skip)]
        call_id: Option<String>,
        status: LocalShellStatus,
        action: LocalShellAction,
    },
    // ...
}
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

| 文件路径 | 说明 |
|---------|------|
| `/codex-rs/protocol/src/models.rs` (lines 1041-1045) | Rust 枚举定义 |
| `/codex-rs/app-server-protocol/schema/typescript/LocalShellAction.ts` | TypeScript 类型定义（生成） |
| `/codex-rs/app-server-protocol/schema/typescript/LocalShellExecAction.ts` | 嵌套类型定义 |

### 相关类型

- `LocalShellExecAction`：exec 操作的具体参数
- `LocalShellStatus`：Shell 操作的状态
- `ResponseItem::LocalShellCall`：使用 LocalShellAction 的响应项

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 依赖项

- `LocalShellExecAction`：exec 操作的参数结构
- `serde`：序列化/反序列化
- `ts_rs::TS`：TypeScript 类型生成
- `schemars::JsonSchema`：JSON Schema 生成

### 序列化示例

```json
// LocalShellAction::Exec
{
  "type": "exec",
  "command": ["ls", "-la"],
  "timeout_ms": 30000,
  "working_directory": "/home/user",
  "env": { "PATH": "/usr/bin" },
  "user": null
}
```

### 使用流程

```rust
// 构造 LocalShellAction
let action = LocalShellAction::Exec(LocalShellExecAction {
    command: vec!["git".to_string(), "status".to_string()],
    timeout_ms: Some(10000),
    working_directory: Some("/path/to/repo".to_string()),
    env: None,
    user: None,
});

// 构造 LocalShellCall 响应项
let item = ResponseItem::LocalShellCall {
    id: None,
    call_id: Some("call-123".to_string()),
    status: LocalShellStatus::InProgress,
    action,
};
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险与边界

1. **单一变体**：目前只有 `Exec` 一个变体，枚举的价值有限
2. **扩展复杂性**：添加新变体需要更新所有相关处理代码
3. **序列化兼容性**：修改标签或结构可能影响现有客户端

### 改进建议

1. **添加更多操作类型**：
   ```rust
   pub enum LocalShellAction {
       Exec(LocalShellExecAction),
       Script(LocalShellScriptAction),  // 执行多行脚本
       Interactive(LocalShellInteractiveAction),  // 交互式命令
   }
   ```

2. **添加操作元数据**：
   ```rust
   pub enum LocalShellAction {
       Exec {
           action: LocalShellExecAction,
           metadata: ActionMetadata,
       },
   }
   ```

3. **简化设计**：如果短期内不需要扩展，考虑直接使用 `LocalShellExecAction`

### 测试建议

- 测试序列化/反序列化的正确性
- 测试带标签的联合类型处理
- 验证与 `LocalShellExecAction` 的集成
- 测试未来添加新变体的兼容性

### 未来扩展

可能的扩展方向：
- **Script 操作**：执行多行 Shell 脚本
- **Interactive 操作**：支持交互式命令（如需要输入密码）
- **Batch 操作**：批量执行多个命令
- **Remote 操作**：在远程主机上执行命令
