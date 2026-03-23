# write_hooks_schema_fixtures.rs 研究文档

## 场景与职责

`write_hooks_schema_fixtures.rs` 是 `codex-hooks` crate 中的一个二进制可执行文件，其核心职责是**生成并写入 Hooks 系统的 JSON Schema 契约文件**。这些 schema 文件定义了 Codex CLI 与外部 Hook 命令之间交互的输入/输出数据格式。

### 定位与上下文

该二进制文件位于 `codex-rs/hooks/src/bin/` 目录下，属于代码生成/契约维护工具链的一部分。它通过调用 `codex_hooks::write_schema_fixtures()` 函数，将 Rust 类型定义转换为标准化的 JSON Schema 文件，供以下场景使用：

1. **Hook 开发者参考**：外部开发者可以查阅这些 schema 来理解如何编写兼容的 hook 命令
2. **运行时验证**：`schema_loader.rs` 在编译时将生成的 schema 嵌入到二进制中，用于运行时的输入验证
3. **IDE/编辑器支持**：JSON Schema 可被编辑器用于提供代码补全和类型检查
4. **文档生成**：作为 API 契约的单一真相源

### 调用方式

```bash
# 使用默认输出目录（<crate_root>/schema）
cargo run -p codex-hooks --bin write_hooks_schema_fixtures

# 指定自定义输出目录
cargo run -p codex-hooks --bin write_hooks_schema_fixtures -- /path/to/output

# 通过 just 命令（项目推荐方式）
just write-hooks-schema
```

对应的 justfile 定义：
```just
[no-cd]
write-hooks-schema:
    cargo run --manifest-path ./codex-rs/Cargo.toml -p codex-hooks --bin write_hooks_schema_fixtures
```

---

## 功能点目的

### 1. 契约生成（Schema Generation）

将 Rust 内部类型转换为公开的 JSON Schema 契约，实现**单一真相源（Single Source of Truth）**。

涉及的事件类型（与 Claude Code 兼容）：
| 事件 | 输入 Schema | 输出 Schema |
|------|------------|------------|
| SessionStart | `session-start.command.input` | `session-start.command.output` |
| UserPromptSubmit | `user-prompt-submit.command.input` | `user-prompt-submit.command.output` |
| Stop | `stop.command.input` | `stop.command.output` |

### 2. 目录管理

- 自动创建 `generated` 子目录
- 清空已有内容（`ensure_empty_dir` 会先删除再重建）
- 支持通过命令行参数指定自定义根目录

### 3. 输出标准化

- 使用 JSON Schema Draft 07 标准
- 字段按字母顺序排序（`canonicalize_json`）
- 美化输出（`to_vec_pretty`）

---

## 具体技术实现

### 关键流程

```
main()
├── 解析命令行参数（可选的 schema_root 路径）
│   └── 默认为 env!("CARGO_MANIFEST_DIR")/schema
└── 调用 codex_hooks::write_schema_fixtures(&schema_root)
    ├── ensure_empty_dir(schema_root/generated)
    ├── 为每种输入/输出类型生成 schema
    │   ├── schema_json::<SessionStartCommandInput>()
    │   ├── schema_json::<SessionStartCommandOutputWire>()
    │   ├── schema_json::<UserPromptSubmitCommandInput>()
    │   ├── schema_json::<UserPromptSubmitCommandOutputWire>()
    │   ├── schema_json::<StopCommandInput>()
    │   └── schema_json::<StopCommandOutputWire>()
    │       └── schema_for_type<T>()
    │           └── SchemaSettings::draft07()
    │               └── option_add_null_type = false
    │       └── canonicalize_json()  // 字母排序
    └── write_schema()  // 写入文件系统
```

### 核心数据结构

#### 输入类型（Input Types）

```rust
// codex-rs/hooks/src/schema.rs
#[derive(Debug, Clone, Serialize, JsonSchema)]
#[serde(deny_unknown_fields)]
#[schemars(rename = "session-start.command.input")]
pub(crate) struct SessionStartCommandInput {
    pub session_id: String,
    pub transcript_path: NullableString,
    pub cwd: String,
    #[schemars(schema_with = "session_start_hook_event_name_schema")]
    pub hook_event_name: String,  // 固定为 "SessionStart"
    pub model: String,
    #[schemars(schema_with = "permission_mode_schema")]
    pub permission_mode: String,  // 枚举: default, acceptEdits, plan, dontAsk, bypassPermissions
    #[schemars(schema_with = "session_start_source_schema")]
    pub source: String,  // 枚举: startup, resume, clear
}

#[derive(Debug, Clone, Serialize, JsonSchema)]
#[serde(deny_unknown_fields)]
#[schemars(rename = "user-prompt-submit.command.input")]
pub(crate) struct UserPromptSubmitCommandInput {
    pub session_id: String,
    pub turn_id: String,  // Codex 扩展字段
    pub transcript_path: NullableString,
    pub cwd: String,
    pub hook_event_name: String,  // 固定为 "UserPromptSubmit"
    pub model: String,
    pub permission_mode: String,
    pub prompt: String,
}

#[derive(Debug, Clone, Serialize, JsonSchema)]
#[serde(deny_unknown_fields)]
#[schemars(rename = "stop.command.input")]
pub(crate) struct StopCommandInput {
    pub session_id: String,
    pub turn_id: String,
    pub transcript_path: NullableString,
    pub cwd: String,
    pub hook_event_name: String,  // 固定为 "Stop"
    pub model: String,
    pub permission_mode: String,
    pub stop_hook_active: bool,
    pub last_assistant_message: NullableString,
}
```

#### 输出类型（Output Types）

```rust
// 通用输出基座
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
#[serde(deny_unknown_fields)]
pub(crate) struct HookUniversalOutputWire {
    #[serde(default = "default_continue")]
    pub r#continue: bool,  // 默认 true
    #[serde(default)]
    pub stop_reason: Option<String>,
    #[serde(default)]
    pub suppress_output: bool,
    #[serde(default)]
    pub system_message: Option<String>,
}

// SessionStart 特有输出
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[schemars(rename = "session-start.command.output")]
pub(crate) struct SessionStartCommandOutputWire {
    #[serde(flatten)]
    pub universal: HookUniversalOutputWire,
    pub hook_specific_output: Option<SessionStartHookSpecificOutputWire>,
}

// UserPromptSubmit 特有输出（支持 block 决策）
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[schemars(rename = "user-prompt-submit.command.output")]
pub(crate) struct UserPromptSubmitCommandOutputWire {
    #[serde(flatten)]
    pub universal: HookUniversalOutputWire,
    pub decision: Option<BlockDecisionWire>,  // "block" 或 null
    pub reason: Option<String>,  // block 时必须提供
    pub hook_specific_output: Option<UserPromptSubmitHookSpecificOutputWire>,
}

// Stop 特有输出
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[schemars(rename = "stop.command.output")]
pub(crate) struct StopCommandOutputWire {
    #[serde(flatten)]
    pub universal: HookUniversalOutputWire,
    pub decision: Option<BlockDecisionWire>,
    pub reason: Option<String>,  // block 时必须提供
}
```

#### 自定义 Schema 生成辅助类型

```rust
// 用于处理 Option<PathBuf> 的可空字符串
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

### Schema 生成配置

```rust
fn schema_for_type<T>() -> RootSchema
where
    T: JsonSchema,
{
    SchemaSettings::draft07()
        .with(|settings| {
            settings.option_add_null_type = false;  // Option<T> 不自动添加 null 类型
        })
        .into_generator()
        .into_root_schema_for::<T>()
}
```

### 自定义字段 Schema

```rust
// 固定值字段（如 hook_event_name）
fn string_const_schema(value: &str) -> Schema {
    let mut schema = SchemaObject {
        instance_type: Some(InstanceType::String.into()),
        ..Default::default()
    };
    schema.const_value = Some(Value::String(value.to_string()));
    Schema::Object(schema)
}

// 枚举字段（如 permission_mode）
fn string_enum_schema(values: &[&str]) -> Schema {
    let mut schema = SchemaObject {
        instance_type: Some(InstanceType::String.into()),
        ..Default::default()
    };
    schema.enum_values = Some(values.iter().map(|v| Value::String((*v).to_string())).collect());
    Schema::Object(schema)
}
```

---

## 关键代码路径与文件引用

### 核心文件关系图

```
write_hooks_schema_fixtures.rs (bin)
│
└──► lib.rs
     │
     └──► schema.rs
          │
          ├── write_schema_fixtures()          # 主入口
          ├── schema_json<T>()                 # 生成单个 schema
          ├── schema_for_type<T>()             # schemars 配置
          │
          ├── SessionStartCommandInput         # 输入类型定义
          ├── UserPromptSubmitCommandInput
          ├── StopCommandInput
          │
          ├── SessionStartCommandOutputWire    # 输出类型定义
          ├── UserPromptSubmitCommandOutputWire
          ├── StopCommandOutputWire
          │
          ├── HookUniversalOutputWire          # 通用输出基座
          ├── NullableString                   # 自定义可空字符串
          └── BlockDecisionWire                # block 决策枚举

生成的 Schema 文件输出到：
codex-rs/hooks/schema/generated/
├── session-start.command.input.schema.json
├── session-start.command.output.schema.json
├── user-prompt-submit.command.input.schema.json
├── user-prompt-submit.command.output.schema.json
├── stop.command.input.schema.json
└── stop.command.output.schema.json
```

### 被调用方（Consumers）

| 文件 | 用途 |
|------|------|
| `src/engine/schema_loader.rs` | 编译时通过 `include_str!` 嵌入生成的 schema 文件，用于运行时加载和验证 |
| `src/engine/output_parser.rs` | 解析 hook 命令的 stdout，使用与 schema 对应的 Wire 类型进行反序列化 |
| `src/events/session_start.rs` | 构造 `SessionStartCommandInput` 作为 hook 命令的 stdin 输入 |
| `src/events/user_prompt_submit.rs` | 构造 `UserPromptSubmitCommandInput` 作为 hook 命令的 stdin 输入 |
| `src/events/stop.rs` | 构造 `StopCommandInput` 作为 hook 命令的 stdin 输入 |

### 测试覆盖

`schema.rs` 包含内置测试：

```rust
#[cfg(test)]
mod tests {
    // 验证生成的 schema 与 fixtures 文件一致
    #[test]
    fn generated_hook_schemas_match_fixtures() { ... }
    
    // 验证 turn_id 扩展字段存在于 UserPromptSubmit 和 Stop 输入中
    #[test]
    fn turn_scoped_hook_inputs_include_codex_turn_id_extension() { ... }
}
```

---

## 依赖与外部交互

### 直接依赖

| Crate | 用途 |
|-------|------|
| `schemars` | JSON Schema 生成核心库 |
| `serde` / `serde_json` | 序列化和 JSON 处理 |
| `anyhow` | 错误处理 |

### 类型依赖

```rust
// 来自 codex-protocol（协议层）
use codex_protocol::protocol::HookEventName;
use codex_protocol::protocol::HookCompletedEvent;
use codex_protocol::protocol::HookRunSummary;
// ...

// 来自 codex-config（配置层）
use codex_config::ConfigLayerStack;
```

### 外部 Hook 命令契约

生成的 schema 定义了 Codex 与外部命令的 stdin/stdout 契约：

**输入流向（Codex → Hook）：**
```
Codex 构造 Input 类型 → serde_json::to_string → 写入 hook 命令 stdin
```

**输出流向（Hook → Codex）：**
```
Hook 命令 stdout → serde_json::from_str → 解析为 Output Wire 类型
```

---

## 风险、边界与改进建议

### 当前风险

1. **Schema 与代码不同步风险**
   - 如果修改了 `schema.rs` 中的类型定义但忘记运行 `write_hooks_schema_fixtures`，生成的 fixture 文件将与实际代码行为不一致
   - **缓解措施**：CI 应检查 `generated_hook_schemas_match_fixtures` 测试是否通过

2. **`ensure_empty_dir` 的破坏性**
   - 该函数会先递归删除整个 `generated` 目录再重建，如果路径配置错误可能导致数据丢失
   - **缓解措施**：目前路径被限制在 crate 目录下的 `schema/generated`，且接受的是 OsString 而非原始字符串

3. **Codex 扩展字段的兼容性**
   - `turn_id` 是 Codex 对 Claude Code 原始协议的扩展，外部 hook 可能不期望此字段
   - **缓解措施**：schema 中明确标注为 "Codex extension"，且该字段是附加而非替换

4. **硬编码的 Schema 设置**
   - `option_add_null_type = false` 影响所有 Option 类型的 schema 生成
   - 如果未来需要为某些字段添加 null 类型支持，需要重构配置逻辑

### 边界情况

| 场景 | 行为 |
|------|------|
| 未提供命令行参数 | 使用 `CARGO_MANIFEST_DIR` 拼接默认路径 |
| 目标目录已存在 | 完全删除后重建（非合并） |
| 序列化失败 | 返回 `anyhow::Error`，程序以非零码退出 |
| 文件写入失败 | 返回 `anyhow::Error`，程序以非零码退出 |

### 改进建议

1. **添加 dry-run 模式**
   ```rust
   // 建议添加
   if args.dry_run {
       println!("Would write schemas to: {}", schema_root.display());
       for (name, json) in schemas {
           println!("  - {} ({} bytes)", name, json.len());
       }
       return Ok(());
   }
   ```

2. **增量更新支持**
   - 当前总是清空重建，可以考虑只更新变更的文件，保留未变更文件的修改时间

3. **Schema 版本管理**
   - 在生成的 schema 中添加版本字段，便于未来进行契约演进

4. **增强验证**
   - 添加验证模式，检查生成的 schema 是否符合预期结构（如所有必需字段都存在）

5. **文档生成集成**
   - 将 schema 转换为 Markdown 文档，便于开发者查阅

6. **Watch 模式**
   - 开发时自动监听 `schema.rs` 变更并重新生成

### 相关命令速查

```bash
# 生成 schema
just write-hooks-schema

# 测试 schema 一致性
cargo test -p codex-hooks generated_hook_schemas_match_fixtures

# 运行所有 hooks 测试
cargo test -p codex-hooks
```
