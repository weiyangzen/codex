# session-start.command.input.schema.json 研究文档

## 场景与职责

`session-start.command.input.schema.json` 是 Codex Hooks 系统中 **SessionStart** 事件的命令输入 JSON Schema 定义文件。它定义了当会话启动时，Codex 向外部钩子命令传递的输入数据结构。

该 Schema 属于 Claude Hooks 协议的一部分，用于标准化钩子命令的输入接口，确保外部钩子能够正确解析 Codex 传递的会话上下文信息。

## 功能点目的

### 核心功能
1. **标准化输入协议**: 定义 SessionStart 事件触发时传递给钩子的 JSON 结构
2. **会话上下文传递**: 向钩子提供会话标识、工作目录、模型信息、权限模式等关键上下文
3. **事件来源标识**: 区分会话启动的不同来源（startup/resume/clear）
4. **类型安全验证**: 通过 JSON Schema 验证钩子接收的输入数据格式

### Schema 约束特性
- **additionalProperties: false**: 禁止未定义的属性，确保协议严格性
- **required 字段**: 强制要求所有核心字段必须存在
- **枚举类型**: 对 permission_mode 和 source 字段使用枚举约束

## 具体技术实现

### 数据结构定义

```json
{
  "properties": {
    "cwd": { "type": "string" },                    // 当前工作目录
    "hook_event_name": { "const": "SessionStart" }, // 固定事件名标识
    "model": { "type": "string" },                   // 使用的AI模型
    "permission_mode": {                              // 权限模式枚举
      "enum": ["default", "acceptEdits", "plan", "dontAsk", "bypassPermissions"]
    },
    "session_id": { "type": "string" },              // 会话唯一标识
    "source": {                                       // 启动来源枚举
      "enum": ["startup", "resume", "clear"]
    },
    "transcript_path": { "$ref": "#/definitions/NullableString" } // 可选的转录路径
  }
}
```

### 关键流程

1. **Schema 生成流程** (`codex-rs/hooks/src/schema.rs`):
   - Rust 结构体 `SessionStartCommandInput` 使用 `schemars` 派生宏生成 Schema
   - 通过 `schema_for_type::<T>()` 生成符合 JSON Schema Draft 07 的规范
   - `write_schema_fixtures()` 函数将 Schema 写入文件

2. **运行时输入序列化** (`codex-rs/hooks/src/events/session_start.rs`):
   ```rust
   let input_json = serde_json::to_string(&SessionStartCommandInput::new(
       request.session_id.to_string(),
       request.transcript_path.clone(),
       request.cwd.display().to_string(),
       request.model.clone(),
       request.permission_mode.clone(),
       request.source.as_str().to_string(),
   ));
   ```

3. **Schema 加载验证** (`codex-rs/hooks/src/engine/schema_loader.rs`):
   - 使用 `include_str!` 编译时嵌入 Schema 文件
   - 运行时通过 `generated_hook_schemas()` 提供静态访问

### 自定义 Schema 构造器

```rust
// session_start_hook_event_name_schema: 生成 const "SessionStart"
fn session_start_hook_event_name_schema(_gen: &mut SchemaGenerator) -> Schema {
    string_const_schema("SessionStart")
}

// permission_mode_schema: 生成权限模式枚举
fn permission_mode_schema(_gen: &mut SchemaGenerator) -> Schema {
    string_enum_schema(&[
        "default", "acceptEdits", "plan", "dontAsk", "bypassPermissions"
    ])
}

// session_start_source_schema: 生成来源枚举
fn session_start_source_schema(_gen: &mut SchemaGenerator) -> Schema {
    string_enum_schema(&["startup", "resume", "clear"])
}
```

## 关键代码路径与文件引用

### 生成侧代码
| 文件 | 职责 |
|------|------|
| `codex-rs/hooks/src/schema.rs` | Schema 生成逻辑、Rust 结构体定义、测试验证 |
| `codex-rs/hooks/src/bin/write_hooks_schema_fixtures.rs` | 二进制工具，用于重新生成 Schema 文件 |

### 消费侧代码
| 文件 | 职责 |
|------|------|
| `codex-rs/hooks/src/engine/schema_loader.rs` | 编译时加载 Schema，运行时提供访问 |
| `codex-rs/hooks/src/events/session_start.rs` | 序列化输入数据，触发钩子执行 |
| `codex-rs/hooks/src/engine/dispatcher.rs` | 调度钩子执行，传递输入 JSON |

### 配置与发现
| 文件 | 职责 |
|------|------|
| `codex-rs/hooks/src/engine/discovery.rs` | 从 `hooks.json` 配置文件发现 SessionStart 钩子 |
| `codex-rs/hooks/src/engine/config.rs` | 钩子配置结构体定义 |

## 依赖与外部交互

### 上游依赖
1. **schemars crate**: JSON Schema 生成
2. **serde crate**: 序列化/反序列化
3. **codex_protocol**: `HookEventName::SessionStart` 枚举定义

### 下游消费者
1. **外部钩子命令**: 任何符合此 Schema 的可执行程序
2. **ClaudeHooksEngine**: 内部引擎，负责调用钩子并传递输入

### 协议层级关系
```
Codex Protocol (HookEventName::SessionStart)
    ↓
Claude Hooks Engine (SessionStartCommandInput)
    ↓
JSON Schema (session-start.command.input.schema.json)
    ↓
External Hook Commands (stdin input)
```

### 相关 Schema 文件
- `session-start.command.output.schema.json`: 对应的输出 Schema
- `user-prompt-submit.command.input.schema.json`: 类似结构的提示提交输入
- `stop.command.input.schema.json`: 类似结构的停止事件输入

## 风险、边界与改进建议

### 当前风险

1. **硬编码枚举值**: permission_mode 和 source 的枚举值在 Schema 和 Rust 代码中重复定义，需要保持同步
   - 位置: `schema.rs` 的 `permission_mode_schema()` 和 `session_start_source_schema()`
   - 风险: 修改枚举值时可能遗漏同步

2. **source 枚举不一致**: Rust 代码中的 `SessionStartSource` 枚举只有 `Startup` 和 `Resume`，但 Schema 包含 `clear`
   - 位置: `events/session_start.rs` 第 20-32 行
   - 风险: 运行时可能遇到未处理的 "clear" 值

3. **NullableString 处理**: transcript_path 使用自定义 NullableString 类型，但外部钩子可能期望标准 null 语义

### 边界情况

1. **空 cwd**: Schema 允许空字符串，但某些钩子可能依赖有效路径
2. **长 session_id**: 无长度限制，极端情况可能导致缓冲区问题
3. **特殊字符**: model 字段无格式验证，可能包含任意字符串

### 改进建议

1. **统一枚举定义**: 使用宏或代码生成确保 Rust 枚举和 Schema 枚举保持一致
   ```rust
   // 建议: 使用 strum 宏统一处理
   #[derive(strum::EnumString, strum::Display)]
   pub enum PermissionMode { ... }
   ```

2. **添加字段验证**: 为关键字段（如 cwd）添加格式验证
   ```json
   "cwd": {
     "type": "string",
     "minLength": 1,
     "description": "Absolute path to current working directory"
   }
   ```

3. **Schema 版本控制**: 考虑添加 `$id` 字段标识 Schema 版本，便于未来演进
   ```json
   "$id": "https://codex.openai.com/schemas/hooks/session-start.input.v1.json"
   ```

4. **文档增强**: 为每个字段添加 `description`，帮助钩子开发者理解用途

5. **测试覆盖**: 当前测试仅验证 Schema 结构，建议添加边界值测试
   - 空字符串处理
   - 特殊字符转义
   - Unicode 路径支持

### 相关测试
- `schema.rs` 第 391-411 行: `generated_hook_schemas_match_fixtures` 测试验证 Schema 文件与生成结果一致
- `session_start.rs` 第 246-376 行: 输出解析测试，间接验证输入/输出协议
