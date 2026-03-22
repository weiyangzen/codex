# GitSha Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`GitSha` 是 Codex 中用于表示 Git 提交 SHA 的类型安全包装器。它在整个协议中作为 Git 提交标识符的标准类型使用。

主要使用场景：
- **提交标识**：唯一标识 Git 仓库中的一个提交
- **版本引用**：在 API 中引用特定的代码版本
- **状态追踪**：追踪对话开始时的代码状态
- **幽灵提交**：标识临时创建的幽灵提交

## 2. 功能点目的 (Purpose of This Type)

- **类型安全**：防止将任意字符串误用为 Git SHA
- **统一表示**：在整个协议中提供一致的 SHA 表示
- **序列化友好**：在 JSON 中表现为字符串，便于传输
- **TypeScript 兼容**：在 TypeScript 端表现为简单字符串类型

## 3. 具体技术实现 (Technical Implementation Details)

### 数据结构

```typescript
// TypeScript 定义（由 ts-rs 生成）
export type GitSha = string;
```

```rust
// Rust 定义
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, JsonSchema, TS)]
#[ts(type = "string")]
pub struct GitSha(pub String);

impl GitSha {
    pub fn new(sha: &str) -> Self {
        Self(sha.to_string())
    }
}
```

### 关键特性

- **Newtype 模式**：使用元组结构体包装 `String`，提供类型安全
- **透明序列化**：使用 `#[ts(type = "string")]` 在 TypeScript 中表现为原生字符串
- **简单构造**：提供 `new()` 方法便于创建实例

### 与其他类型的关系

```rust
// 在 GhostCommit 中使用
pub struct GhostCommit {
    id: CommitID,  // CommitID 是 String 的别名
    parent: Option<CommitID>,
    // ...
}

// 在 GitDiffToRemoteResponse 中使用
pub struct GitDiffToRemoteResponse {
    pub sha: GitSha,
    pub diff: String,
}
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

| 文件路径 | 说明 |
|---------|------|
| `/codex-rs/app-server-protocol/src/protocol/common.rs` (lines 17-25) | Rust 类型定义 |
| `/codex-rs/app-server-protocol/schema/typescript/GitSha.ts` | TypeScript 类型定义（生成） |
| `/codex-rs/app-server-protocol/src/protocol/v1.rs` (line 24) | 导入使用 |

### 使用位置

| 使用位置 | 用途 |
|---------|------|
| `GitDiffToRemoteResponse.sha` | 标识 diff 的基准提交 |
| `ConversationGitInfo.sha` | 对话时的 Git 状态 |
| `GhostCommit` | 幽灵提交的 ID 和父提交 |

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 依赖项

- `serde`：序列化/反序列化
- `ts_rs::TS`：TypeScript 类型生成
- `schemars::JsonSchema`：JSON Schema 生成

### 序列化行为

```rust
// Rust 端
let sha = GitSha::new("abc123");
let json = serde_json::to_string(&sha)?;  // "\"abc123\""

// TypeScript 端
const sha: GitSha = "abc123";  // 直接使用字符串
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险与边界

1. **无格式验证**：当前实现不验证字符串是否为有效的 Git SHA 格式
2. **长度不固定**：Git SHA 可以是完整（40字符）或缩写形式
3. **大小写敏感**：Git SHA 是十六进制，通常小写但可能大写

### 改进建议

1. **添加验证**：实现 SHA 格式验证（长度、十六进制字符）
   ```rust
   impl GitSha {
       pub fn is_valid(&self) -> bool {
           self.0.len() >= 4 && self.0.chars().all(|c| c.is_ascii_hexdigit())
       }
   }
   ```

2. **标准化**：自动转换为小写
   ```rust
   pub fn new(sha: &str) -> Self {
       Self(sha.to_lowercase())
   }
   ```

3. **长度常量**：定义标准长度常量
   ```rust
   pub const FULL_SHA_LENGTH: usize = 40;
   pub const SHORT_SHA_LENGTH: usize = 7;
   ```

4. **Display trait**：实现 `Display` 便于打印
   ```rust
   impl fmt::Display for GitSha {
       fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
           write!(f, "{}", self.0)
       }
   }
   ```

### 测试建议

- 验证有效 SHA 格式（完整和缩写）
- 验证无效 SHA 的处理
- 测试序列化/反序列化
- 测试大小写处理
