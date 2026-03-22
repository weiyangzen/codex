# LocalShellExecAction Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`LocalShellExecAction` 是 Codex Protocol 中表示本地 Shell 执行操作参数的结构体类型。它封装了执行 Shell 命令所需的所有配置信息，是 `LocalShellAction::Exec` 变体的数据载体。

主要使用场景：
- **命令执行**：模型请求在本地执行 Shell 命令
- **环境配置**：指定工作目录、环境变量、执行用户等
- **超时控制**：设置命令执行的超时时间
- **安全限制**：通过用户切换实现权限控制

## 2. 功能点目的 (Purpose of This Type)

- **参数封装**：封装执行 Shell 命令的所有必要参数
- **环境隔离**：支持指定工作目录和环境变量
- **安全控制**：支持指定执行用户和超时时间
- **类型安全**：使用强类型确保参数有效性

## 3. 具体技术实现 (Technical Implementation Details)

### 数据结构

```typescript
// TypeScript 定义（由 ts-rs 生成）
export type LocalShellExecAction = {
  command: Array<string>,
  timeout_ms: bigint | null,
  working_directory: string | null,
  env: { [key in string]?: string } | null,
  user: string | null,
};
```

```rust
// Rust 定义
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, JsonSchema, TS)]
pub struct LocalShellExecAction {
    pub command: Vec<String>,
    pub timeout_ms: Option<u64>,
    pub working_directory: Option<String>,
    pub env: Option<HashMap<String, String>>,
    pub user: Option<String>,
}
```

### 字段说明

| 字段 | TypeScript 类型 | Rust 类型 | 说明 |
|-----|----------------|-----------|------|
| `command` | `string[]` | `Vec<String>` | 命令及其参数的数组（argv 格式） |
| `timeout_ms` | `bigint \| null` | `Option<u64>` | 超时时间（毫秒） |
| `working_directory` | `string \| null` | `Option<String>` | 工作目录路径 |
| `env` | `Record<string, string> \| null` | `Option<HashMap<String, String>>` | 环境变量字典 |
| `user` | `string \| null` | `Option<String>` | 执行命令的用户名 |

### 关键特性

- **Argv 格式**：`command` 使用数组格式而非字符串，避免 Shell 注入
- **TypeScript bigint**：`timeout_ms` 在 TypeScript 中使用 `bigint` 类型
- **可选字段**：所有字段（除 `command` 外）都是可选的

### 与 ShellToolCallParams 的关系

```rust
// ShellToolCallParams - 工具调用参数
pub struct ShellToolCallParams {
    pub command: Vec<String>,
    pub workdir: Option<String>,
    pub timeout_ms: Option<u64>,
    pub sandbox_permissions: Option<SandboxPermissions>,
    pub prefix_rule: Option<Vec<String>>,
    pub additional_permissions: Option<PermissionProfile>,
    pub justification: Option<String>,
}
```

`LocalShellExecAction` 是 `LocalShellCall` 响应项的一部分，而 `ShellToolCallParams` 是函数调用的参数。两者都描述命令执行，但使用场景不同。

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

| 文件路径 | 说明 |
|---------|------|
| `/codex-rs/protocol/src/models.rs` (lines 1047-1054) | Rust 结构体定义 |
| `/codex-rs/app-server-protocol/schema/typescript/LocalShellExecAction.ts` | TypeScript 类型定义（生成） |
| `/codex-rs/protocol/src/models.rs` (lines 1148-1168) | `ShellToolCallParams` 定义 |

### 相关类型

- `LocalShellAction`：包含 `LocalShellExecAction` 的枚举
- `LocalShellStatus`：命令执行状态
- `ResponseItem::LocalShellCall`：使用此类型的响应项
- `ShellToolCallParams`：类似的工具调用参数

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 依赖项

- `std::collections::HashMap`：环境变量存储
- `serde`：序列化/反序列化
- `ts_rs::TS`：TypeScript 类型生成
- `schemars::JsonSchema`：JSON Schema 生成

### 序列化示例

```json
// 完整示例
{
  "command": ["git", "clone", "https://github.com/example/repo.git"],
  "timeout_ms": 60000,
  "working_directory": "/home/user/projects",
  "env": {
    "GIT_SSH_COMMAND": "ssh -i /path/to/key",
    "HTTP_PROXY": "http://proxy.example.com:8080"
  },
  "user": null
}

// 最小示例
{
  "command": ["ls", "-la"],
  "timeout_ms": null,
  "working_directory": null,
  "env": null,
  "user": null
}
```

### 使用流程

```rust
// 构造执行动作
let action = LocalShellExecAction {
    command: vec!["cargo".to_string(), "build".to_string(), "--release".to_string()],
    timeout_ms: Some(300000),  // 5 分钟
    working_directory: Some("/path/to/project".to_string()),
    env: Some(HashMap::from([
        ("RUST_LOG".to_string(), "info".to_string()),
    ])),
    user: None,
};

// 包装为 LocalShellAction
let shell_action = LocalShellAction::Exec(action);
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险与边界

1. **命令注入**：虽然使用 argv 格式，但仍需验证命令内容
2. **路径遍历**：`working_directory` 需要验证防止目录遍历
3. **环境变量安全**：`env` 可能包含敏感信息
4. **用户切换**：`user` 字段需要系统权限支持
5. **超时处理**：`timeout_ms` 为 `None` 时可能导致命令无限期运行

### 改进建议

1. **添加命令验证**：
   ```rust
   pub fn validate(&self) -> Result<(), ValidationError> {
       // 验证命令不为空
       // 验证路径合法性
       // 验证环境变量键值
   }
   ```

2. **添加默认超时**：
   ```rust
   impl Default for LocalShellExecAction {
       fn default() -> Self {
           Self {
               timeout_ms: Some(30000),  // 默认 30 秒
               // ...
           }
       }
   }
   ```

3. **添加沙盒配置**：
   ```rust
   pub sandbox_policy: Option<SandboxPolicy>,
   ```

4. **使用 PathBuf**：
   ```rust
   pub working_directory: Option<PathBuf>,
   ```

### 安全考虑

- **命令白名单**：考虑实现允许执行的命令白名单
- **路径限制**：限制工作目录必须在允许的根目录下
- **敏感信息过滤**：过滤环境变量中的敏感信息
- **资源限制**：添加 CPU、内存等资源限制

### 测试建议

- 测试各种命令格式的序列化/反序列化
- 测试空命令、超长命令等边界情况
- 测试特殊字符在环境变量中的处理
- 验证路径遍历防护
