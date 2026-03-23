# schema.rs 研究文档

## 场景与职责

`schema.rs` 是 codex-hooks crate 的 JSON Schema 定义与生成模块，负责：

1. **定义 Claude Hooks 的输入/输出数据结构**：为三种事件类型（SessionStart、UserPromptSubmit、Stop）定义 Rust 结构体
2. **生成 JSON Schema 文件**：使用 `schemars` crate 生成符合 Draft 07 规范的 schema 文件
3. **提供序列化/反序列化支持**：使用 `serde` 处理 JSON 数据交换

该模块是 Codex 与 Claude CLI 钩子系统**兼容性的关键**，确保 Codex 实现的钩子协议与 Claude 官方文档一致。

## 功能点目的

### 1. 输入数据结构定义

| 结构体 | 用途 | 对应事件 |
|--------|------|----------|
| `SessionStartCommandInput` | SessionStart 钩子输入 | SessionStart |
| `UserPromptSubmitCommandInput` | UserPromptSubmit 钩子输入 | UserPromptSubmit |
| `StopCommandInput` | Stop 钩子输入 | Stop |

**共同字段**：
- `session_id`: 会话 ID
- `turn_id`: 轮次 ID（Codex 扩展，Claude 文档中无此字段）
- `transcript_path`: 会话记录路径（可为 null）
- `cwd`: 当前工作目录
- `hook_event_name`: 事件名称常量
- `model`: 使用的模型名称
- `permission_mode`: 权限模式

**事件特有字段**：
- `SessionStartCommandInput`: `source`（启动来源：startup/resume/clear）
- `UserPromptSubmitCommandInput`: `prompt`（用户输入的提示词）
- `StopCommandInput`: `stop_hook_active`, `last_assistant_message`

### 2. 输出数据结构定义

| 结构体 | 用途 | 关键字段 |
|--------|------|----------|
| `HookUniversalOutputWire` | 通用输出字段 | `continue`, `stop_reason`, `suppress_output`, `system_message` |
| `SessionStartCommandOutputWire` | SessionStart 输出 | `universal` + `hook_specific_output.additional_context` |
| `UserPromptSubmitCommandOutputWire` | UserPromptSubmit 输出 | `universal` + `decision` + `reason` + `hook_specific_output` |
| `StopCommandOutputWire` | Stop 输出 | `universal` + `decision` + `reason` |

### 3. JSON Schema 生成

```rust
pub fn write_schema_fixtures(schema_root: &Path) -> anyhow::Result<()>
```

生成 6 个 schema 文件到 `schema_root/generated/`：
- `session-start.command.input.schema.json`
- `session-start.command.output.schema.json`
- `user-prompt-submit.command.input.schema.json`
- `user-prompt-submit.command.output.schema.json`
- `stop.command.input.schema.json`
- `stop.command.output.schema.json`

## 具体技术实现

### 数据结构设计

#### NullableString 包装器

```rust
#[derive(Debug, Clone, Serialize)]
#[serde(transparent)]
pub(crate) struct NullableString(Option<String>);

impl JsonSchema for NullableString {
    fn json_schema(_gen: &mut SchemaGenerator) -> Schema {
        Schema::Object(SchemaObject {
            instance_type: Some(vec![InstanceType::String, InstanceType::Null].into()),
            ..Default::default()
        })
    }
}
```

**设计意图**：
- Rust `Option<String>` 默认 schema 为 `"type": ["string", "null"]`
- 但 `schemars` 默认行为可能不符合预期
- 自定义实现确保精确的 JSON Schema 输出

#### 通用输出结构

```rust
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
#[serde(deny_unknown_fields)]
pub(crate) struct HookUniversalOutputWire {
    #[serde(default = "default_continue")]
    pub r#continue: bool,  // 默认 true，继续处理
    #[serde(default)]
    pub stop_reason: Option<String>,
    #[serde(default)]
    pub suppress_output: bool,
    #[serde(default)]
    pub system_message: Option<String>,
}
```

**关键设计**：
- `deny_unknown_fields`: 拒绝未知字段，严格验证
- `default_continue() -> true`: 默认继续处理，向后兼容
- `r#continue`: Rust 关键字转义

#### 决策枚举

```rust
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, PartialEq, Eq)]
pub(crate) enum BlockDecisionWire {
    #[serde(rename = "block")]
    Block,
}
```

**注意**：当前仅支持 `block` 决策，无 `allow` 变体（通过省略 `decision` 字段表示允许）。

### Schema 生成流程

```
write_schema_fixtures(schema_root)
  │
  ├─> ensure_empty_dir(generated_dir)
  │
  ├─> 对每个类型 T:
  │     ├─> schema_for_type::<T>()  // 使用 schemars
  │     ├─> canonicalize_json()     // 排序字段，确保输出稳定
  │     └─> write_schema()          // 写入文件
  │
  └─> 返回 Ok(())
```

### 自定义 Schema 生成

```rust
fn schema_for_type<T>() -> RootSchema
where
    T: JsonSchema,
{
    SchemaSettings::draft07()
        .with(|settings| {
            settings.option_add_null_type = false;  // Option<T> 不自动添加 null
        })
        .into_generator()
        .into_root_schema_for::<T>()
}
```

**配置说明**：
- `draft07()`: 使用 JSON Schema Draft 07
- `option_add_null_type = false`: 手动控制 null 类型（通过 `NullableString`）

### 常量字段 Schema

```rust
fn session_start_hook_event_name_schema(_gen: &mut SchemaGenerator) -> Schema {
    string_const_schema("SessionStart")
}

fn string_const_schema(value: &str) -> Schema {
    let mut schema = SchemaObject {
        instance_type: Some(InstanceType::String.into()),
        ..Default::default()
    };
    schema.const_value = Some(Value::String(value.to_string()))
    Schema::Object(schema)
}
```

**用途**：`hook_event_name` 字段在每种输入类型中为常量（如 `"SessionStart"`），使用 `const` schema 约束。

## 关键代码路径与文件引用

### 当前文件关键代码

| 行号 | 代码 | 说明 |
|------|------|------|
| 15-21 | 常量定义 | 6 个 schema 文件名 |
| 23-48 | `NullableString` | 可空字符串包装器 |
| 50-62 | `HookUniversalOutputWire` | 通用输出结构 |
| 64-72 | `HookEventNameWire` | 事件名称枚举 |
| 74-132 | 输出结构体 | SessionStart/Stop/UserPromptSubmit 输出 |
| 139-209 | 输入结构体 | 三种事件输入 |
| 211-241 | `write_schema_fixtures` | schema 生成主函数 |
| 266-276 | `schema_for_type` | 自定义 schema 生成器 |
| 278-292 | `canonicalize_json` | JSON 规范化（排序） |
| 294-341 | schema 辅助函数 | 常量、枚举 schema 生成 |

### 生成的 Schema 文件

| 文件 | 路径 | 用途 |
|------|------|------|
| session-start.command.input.schema.json | `schema/generated/` | SessionStart 输入验证 |
| session-start.command.output.schema.json | `schema/generated/` | SessionStart 输出验证 |
| user-prompt-submit.command.input.schema.json | `schema/generated/` | UserPromptSubmit 输入验证 |
| user-prompt-submit.command.output.schema.json | `schema/generated/` | UserPromptSubmit 输出验证 |
| stop.command.input.schema.json | `schema/generated/` | Stop 输入验证 |
| stop.command.output.schema.json | `schema/generated/` | Stop 输出验证 |

### 跨文件引用

| 引用目标 | 路径 | 用途 |
|----------|------|------|
| `output_parser.rs` | `engine/output_parser.rs` | 使用输出结构解析钩子 stdout |
| `session_start.rs` | `events/session_start.rs` | 使用 `SessionStartCommandInput` |
| `user_prompt_submit.rs` | `events/user_prompt_submit.rs` | 使用 `UserPromptSubmitCommandInput` |
| `stop.rs` | `events/stop.rs` | 使用 `StopCommandInput` |
| `schema_loader.rs` | `engine/schema_loader.rs` | 嵌入 schema 文件内容 |

### 调用方

| 调用方 | 路径 | 调用内容 |
|--------|------|----------|
| 构建脚本/justfile | `just write-hook-schema` | `write_schema_fixtures()` |
| 测试代码 | `schema.rs` 内部测试 | 验证生成结果 |

## 依赖与外部交互

### 内部依赖

```
schema.rs
  ├─> (被 engine/schema_loader.rs 使用)
  ├─> (被 engine/output_parser.rs 使用)
  └─> (被 events/*.rs 使用)
```

### 外部依赖

| Crate | 用途 |
|-------|------|
| `schemars` | JSON Schema 生成 |
| `serde` | 序列化/反序列化 |
| `serde_json` | JSON 处理 |
| `std::path` | 路径操作 |

### 与 Claude 文档的对应

| Codex 结构体 | Claude 文档 | 兼容性 |
|--------------|-------------|--------|
| `SessionStartCommandInput` | SessionStart Input | ✓ 完整兼容 |
| `UserPromptSubmitCommandInput` | UserPromptSubmit Input | ✓ + Codex 扩展 `turn_id` |
| `StopCommandInput` | Stop Input | ✓ + Codex 扩展 `turn_id` |
| `HookUniversalOutputWire` | Universal Output Fields | ✓ 完整兼容 |
| `BlockDecisionWire` | Decision Enum | ✓ 完整兼容 |

## 风险、边界与改进建议

### 已知风险

1. **Codex 扩展字段 `turn_id`**
   - Claude 官方文档中无此字段
   - 可能导致与 Claude CLI 的钩子不互操作
   - 建议：文档明确标注 Codex 扩展，或提供兼容模式

2. **`deny_unknown_fields` 的严格性**
   - 拒绝任何未知字段
   - Claude 未来添加新字段时会导致解析失败
   - 建议：评估是否需要放宽到 `serde(default)`

3. **Schema 版本管理**
   - 当前无版本号机制
   - 协议演进时难以区分 schema 版本
   - 建议：添加 `$id` 或版本字段

### 边界情况

| 场景 | 行为 |
|------|------|
| `transcript_path = None` | 序列化为 `null`（通过 `NullableString`） |
| `continue` 字段缺失 | 默认 `true`（`default_continue`） |
| `decision = "block"` 但 `reason` 为空 | 在输出解析层拒绝，非 schema 层 |
| 未知字段 | 反序列化失败（`deny_unknown_fields`） |

### 测试覆盖

当前测试：
- `generated_hook_schemas_match_fixtures`: 验证生成文件与预期一致
- `turn_scoped_hook_inputs_include_codex_turn_id_extension`: 验证 `turn_id` 存在

建议增加：
- 反序列化边界测试（缺失字段、null 值、类型错误）
- 与 Claude CLI 实际钩子输出互操作测试
- Schema 验证性能测试（大输入）

### 改进建议

1. **文档改进**
   ```rust
   /// SessionStart 事件输入。
   /// 
   /// # Codex 扩展
   /// - `turn_id`: 当前轮次 ID，Claude 文档中无此字段
   /// 
   /// # 示例
   /// ```json
   /// { "session_id": "...", "turn_id": "...", ... }
   /// ```
   ```

2. **版本管理**
   ```rust
   pub const SCHEMA_VERSION: &str = "1.0.0";
   
   #[derive(JsonSchema)]
   #[schemars(rename = "session-start.command.input", version = "1.0.0")]
   struct SessionStartCommandInput { ... }
   ```

3. **兼容性模式**
   ```rust
   #[derive(Deserialize)]
   struct SessionStartCommandInput {
       // ... 标准字段
       
       #[serde(flatten)]
       extensions: HashMap<String, Value>, // 捕获扩展字段
   }
   ```

4. **Schema 验证工具**
   - 提供 CLI 工具验证用户 hooks.json 输出
   - 集成到 `codex doctor` 或类似命令

### 代码统计

| 指标 | 数值 |
|------|------|
| 总行数 | ~437 行 |
| 结构体定义 | 8 个 |
| 枚举定义 | 2 个 |
| 测试函数 | 2 个 |
| 生成 schema 文件 | 6 个 |

### 与 Claude 协议的差异汇总

| 差异点 | Codex 行为 | Claude 行为 | 影响 |
|--------|-----------|-------------|------|
| `turn_id` | 包含在输入中 | 无此字段 | Codex 钩子可获取更多信息 |
| `source` 枚举 | `startup/resume/clear` | 可能不同 | 需验证 |
| `permission_mode` | 5 种模式 | 可能不同 | 需验证 |

建议定期与 Claude CLI 最新版本进行兼容性测试。
