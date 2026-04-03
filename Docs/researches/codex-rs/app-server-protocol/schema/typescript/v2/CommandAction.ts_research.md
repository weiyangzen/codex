# CommandAction.ts 研究文档

## 场景与职责

`CommandAction.ts` 定义了命令解析后的动作类型，用于 `CommandExecutionRequestApprovalParams` 中的 `commandActions` 字段。该类型将用户输入的命令字符串解析为结构化的动作表示，便于 UI 以友好的方式展示命令的意图。

该类型是 Codex 命令执行审批流程的一部分，帮助用户理解 AI 尝试执行的命令的具体行为。

## 功能点目的

### 核心功能

1. **命令解析**：将原始命令字符串解析为结构化的动作类型
2. **友好展示**：为 UI 提供人类可读的命令描述
3. **意图识别**：识别命令的真实意图（读取、列出文件、搜索等）
4. **安全审计**：帮助用户快速判断命令是否安全

### 类型定义

```typescript
export type CommandAction = 
  | { "type": "read", command: string, name: string, path: string } 
  | { "type": "listFiles", command: string, path: string | null } 
  | { "type": "search", command: string, query: string | null, path: string | null } 
  | { "type": "unknown", command: string };
```

### 变体说明

| 类型 | 用途 | 字段 |
|------|------|------|
| `read` | 读取文件内容 | `command`, `name`, `path` |
| `listFiles` | 列出目录内容 | `command`, `path` |
| `search` | 搜索文件内容 | `command`, `query`, `path` |
| `unknown` | 无法识别的命令 | `command` |

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `type` | 枚举字符串 | 动作类型标识 |
| `command` | `string` | 原始命令字符串 |
| `name` | `string` | 友好的动作名称（read 类型） |
| `path` | `string \| null` | 目标路径 |
| `query` | `string \| null` | 搜索查询（search 类型） |

## 具体技术实现

### 代码生成来源

**Rust 源码位置**：`codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1436-1458)

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(tag = "type", rename_all = "camelCase")]
#[ts(tag = "type")]
#[ts(export_to = "v2/")]
pub enum CommandAction {
    Read {
        command: String,
        name: String,
        path: PathBuf,
    },
    ListFiles {
        command: String,
        path: Option<String>,
    },
    Search {
        command: String,
        query: Option<String>,
        path: Option<String>,
    },
    Unknown {
        command: String,
    },
}
```

### 核心协议映射

该类型与 `codex_protocol::parse_command::ParsedCommand` 进行双向转换：

| API v2 | Core Protocol |
|--------|---------------|
| `CommandAction::Read` | `CoreParsedCommand::Read` |
| `CommandAction::ListFiles` | `CoreParsedCommand::ListFiles` |
| `CommandAction::Search` | `CoreParsedCommand::Search` |
| `CommandAction::Unknown` | `CoreParsedCommand::Unknown` |

### 转换实现

```rust
impl CommandAction {
    pub fn into_core(self) -> CoreParsedCommand {
        match self {
            CommandAction::Read { command: cmd, name, path } => {
                CoreParsedCommand::Read { cmd, name, path }
            }
            CommandAction::ListFiles { command: cmd, path } => {
                CoreParsedCommand::ListFiles { cmd, path }
            }
            CommandAction::Search { command: cmd, query, path } => {
                CoreParsedCommand::Search { cmd, query, path }
            }
            CommandAction::Unknown { command: cmd } => CoreParsedCommand::Unknown { cmd },
        }
    }
}
```

## 关键代码路径与文件引用

### 使用位置

| 文件 | 字段 | 说明 |
|------|------|------|
| `CommandExecutionRequestApprovalParams.ts` | `commandActions` | 审批请求中的命令动作列表 |

### 依赖关系

```
CommandExecutionRequestApprovalParams.ts
  └── CommandAction.ts
```

### 解析流程

```
用户输入命令
      |
      v
[命令解析器] 
      |
      v
ParsedCommand (Core)
      |
      v
CommandAction (API v2)
      |
      v
UI 展示友好的命令描述
```

### 相关文件

| 文件 | 说明 |
|------|------|
| `CommandExecutionRequestApprovalParams.ts` | 使用 CommandAction 的审批参数 |
| `codex_protocol::parse_command` | 核心命令解析模块 |

## 依赖与外部交互

### 命令解析系统

命令解析是 Codex 的安全特性之一：

1. **解析规则**：
   - `cat`, `head`, `tail`, `less` 等 → `read`
   - `ls`, `dir`, `find`（无查询） → `listFiles`
   - `grep`, `rg`, `find`（有查询） → `search`
   - 其他 → `unknown`

2. **安全价值**：
   - 帮助用户识别潜在的恶意命令
   - 将技术命令转换为用户友好的描述
   - 支持基于命令类型的细粒度审批策略

### UI 展示示例

| 原始命令 | 解析类型 | UI 展示 |
|----------|----------|---------|
| `cat src/main.rs` | `read` | "读取文件: src/main.rs" |
| `ls -la` | `listFiles` | "列出当前目录文件" |
| `grep -r "TODO" .` | `search` | "搜索: TODO" |
| `rm -rf /` | `unknown` | "执行命令: rm -rf /" ⚠️ |

## 风险、边界与改进建议

### 潜在风险

1. **解析不准确**：复杂命令可能无法正确解析
2. **安全误导**：解析为 `read` 的命令仍可能包含危险操作（如 `cat /dev/zero`）
3. **绕过检测**：攻击者可能构造看似无害但实际危险的命令

### 边界情况

1. **组合命令**：
   - `cat file.txt && rm file.txt` → 可能只解析第一部分
   - 管道命令 `cat file | grep pattern` → 解析复杂

2. **别名和函数**：
   - 用户定义的别名可能掩盖真实命令
   - shell 函数无法静态解析

3. **变量展开**：
   - `cat $FILE` → 运行时才能确定目标

### 改进建议

1. **增加更多类型**：
   ```typescript
   type CommandAction = 
     | { type: "read"; ... }
     | { type: "write"; ... }      // 新增：写入操作
     | { type: "delete"; ... }     // 新增：删除操作
     | { type: "execute"; ... }    // 新增：执行程序
     | { type: "network"; ... }    // 新增：网络操作
     | { type: "search"; ... }
     | { type: "listFiles"; ... }
     | { type: "unknown"; ... };
   ```

2. **添加风险评分**：
   ```typescript
   interface CommandAction {
     // ...
     riskLevel?: "low" | "medium" | "high";
     riskReason?: string;
   }
   ```

3. **支持命令链解析**：
   ```typescript
   interface CommandAction {
     // ...
     chainedActions?: CommandAction[];  // 解析组合命令
   }
   ```

4. **添加参数解析**：
   ```typescript
   interface CommandAction {
     // ...
     flags?: string[];      // 解析的命令行标志
     arguments?: string[];  // 解析的参数
   }
   ```

### 版本兼容性

- 当前版本：v2
- 稳定性：稳定
- 向后兼容：新增变体是安全的

### 安全建议

1. **不要完全依赖**：命令解析仅作为辅助，不应替代用户审查
2. **运行时验证**：对于关键操作，应在执行前再次验证
3. **沙箱执行**：所有命令应在沙箱环境中执行
4. **审计日志**：记录所有解析结果和实际执行的命令
