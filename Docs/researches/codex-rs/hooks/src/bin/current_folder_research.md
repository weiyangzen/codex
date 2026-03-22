# 研究报告：codex-rs/hooks/src/bin

## 目录
1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 目录定位
`codex-rs/hooks/src/bin/` 是 `codex-hooks` crate 的二进制可执行文件目录，目前包含单个可执行文件：`write_hooks_schema_fixtures.rs`。

### 核心职责
该二进制文件的主要职责是**生成并写入 Hooks 系统的 JSON Schema 文件**，用于：

1. **契约定义**：定义 Claude Hooks 协议的输入/输出数据结构（与 Claude Code CLI 的 hooks 协议兼容）
2. **代码生成基础**：为 TypeScript 客户端和其他消费者提供类型定义来源
3. **测试验证**：作为测试固件(fixture)验证序列化/反序列化的正确性
4. **文档生成**：为开发者提供 hooks 数据格式的参考文档

### 运行场景
- **开发阶段**：当 hooks 的数据结构发生变化时，运行此工具更新 schema 文件
- **CI/CD**：在构建流程中验证 schema 文件与代码定义的一致性
- **发布前**：确保所有 schema 文件都是最新的

---

## 功能点目的

### 1. Schema 文件生成

| Schema 文件 | 用途 | 对应事件 |
|------------|------|---------|
| `session-start.command.input.schema.json` | SessionStart 事件输入参数定义 | SessionStart |
| `session-start.command.output.schema.json` | SessionStart 事件输出结构定义 | SessionStart |
| `user-prompt-submit.command.input.schema.json` | UserPromptSubmit 事件输入参数定义 | UserPromptSubmit |
| `user-prompt-submit.command.output.schema.json` | UserPromptSubmit 事件输出结构定义 | UserPromptSubmit |
| `stop.command.input.schema.json` | Stop 事件输入参数定义 | Stop |
| `stop.command.output.schema.json` | Stop 事件输出结构定义 | Stop |

### 2. 命令行接口

```bash
# 默认行为：写入到 <CARGO_MANIFEST_DIR>/schema 目录
cargo run -p codex-hooks --bin write_hooks_schema_fixtures

# 自定义输出目录
cargo run -p codex-hooks --bin write_hooks_schema_fixtures /path/to/schema
```

### 3. 与 just 命令集成

在 `justfile` 中定义了快捷命令：

```just
write-hooks-schema:
    cargo run --manifest-path ./codex-rs/Cargo.toml -p codex-hooks --bin write_hooks_schema_fixtures
```

---

## 具体技术实现

### 3.1 入口点实现

**文件**: `codex-rs/hooks/src/bin/write_hooks_schema_fixtures.rs`

```rust
use std::path::PathBuf;

fn main() -> anyhow::Result<()> {
    let schema_root = std::env::args_os()
        .nth(1)
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("schema"));
    codex_hooks::write_schema_fixtures(&schema_root)
}
```

**关键逻辑**：
- 接受可选的命令行参数作为 schema 输出根目录
- 默认使用 `CARGO_MANIFEST_DIR/schema`（即 `codex-rs/hooks/schema`）
- 委托给库函数 `codex_hooks::write_schema_fixtures` 执行实际写入

### 3.2 Schema 生成核心逻辑

**文件**: `codex-rs/hooks/src/schema.rs`

#### 3.2.1 输入数据结构定义

```rust
// SessionStart 命令输入
#[derive(Debug, Clone, Serialize, JsonSchema)]
#[serde(deny_unknown_fields)]
#[schemars(rename = "session-start.command.input")]
pub(crate) struct SessionStartCommandInput {
    pub session_id: String,
    pub transcript_path: NullableString,
    pub cwd: String,
    #[schemars(schema_with = "session_start_hook_event_name_schema")]
    pub hook_event_name: String,  // 固定值 "SessionStart"
    pub model: String,
    #[schemars(schema_with = "permission_mode_schema")]
    pub permission_mode: String,  // 枚举: default, acceptEdits, plan, dontAsk, bypassPermissions
    #[schemars(schema_with = "session_start_source_schema")]
    pub source: String,  // 枚举: startup, resume, clear
}

// UserPromptSubmit 命令输入（Codex 扩展：包含 turn_id）
#[derive(Debug, Clone, Serialize, JsonSchema)]
#[serde(deny_unknown_fields)]
#[schemars(rename = "user-prompt-submit.command.input")]
pub(crate) struct UserPromptSubmitCommandInput {
    pub session_id: String,
    pub turn_id: String,  // Codex 扩展字段
    pub transcript_path: NullableString,
    pub cwd: String,
    pub hook_event_name: String,  // 固定值 "UserPromptSubmit"
    pub model: String,
    pub permission_mode: String,
    pub prompt: String,
}

// Stop 命令输入
#[derive(Debug, Clone, Serialize, JsonSchema)]
#[serde(deny_unknown_fields)]
#[schemars(rename = "stop.command.input")]
pub(crate) struct StopCommandInput {
    pub session_id: String,
    pub turn_id: String,  // Codex 扩展字段
    pub transcript_path: NullableString,
    pub cwd: String,
    pub hook_event_name: String,  // 固定值 "Stop"
    pub model: String,
    pub permission_mode: String,
    pub stop_hook_active: bool,
    pub last_assistant_message: NullableString,
}
```

#### 3.2.2 输出数据结构定义

```rust
// 通用输出结构（所有事件共享）
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

// SessionStart 专用输出
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[schemars(rename = "session-start.command.output")]
pub(crate) struct SessionStartCommandOutputWire {
    #[serde(flatten)]
    pub universal: HookUniversalOutputWire,
    #[serde(default)]
    pub hook_specific_output: Option<SessionStartHookSpecificOutputWire>,
}

// UserPromptSubmit 专用输出（支持 block 决策）
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[schemars(rename = "user-prompt-submit.command.output")]
pub(crate) struct UserPromptSubmitCommandOutputWire {
    #[serde(flatten)]
    pub universal: HookUniversalOutputWire,
    #[serde(default)]
    pub decision: Option<BlockDecisionWire>,  // "block" 或 null
    #[serde(default)]
    pub reason: Option<String>,  // block 时必须提供
    #[serde(default)]
    pub hook_specific_output: Option<UserPromptSubmitHookSpecificOutputWire>,
}

// Stop 专用输出
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[schemars(rename = "stop.command.output")]
pub(crate) struct StopCommandOutputWire {
    #[serde(flatten)]
    pub universal: HookUniversalOutputWire,
    #[serde(default)]
    pub decision: Option<BlockDecisionWire>,
    #[serde(default)]
    pub reason: Option<String>,
}

// Block 决策枚举
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, PartialEq, Eq)]
pub(crate) enum BlockDecisionWire {
    #[serde(rename = "block")]
    Block,
}
```

#### 3.2.3 Schema 生成流程

```rust
pub fn write_schema_fixtures(schema_root: &Path) -> anyhow::Result<()> {
    let generated_dir = schema_root.join(GENERATED_DIR);
    ensure_empty_dir(&generated_dir)?;

    // 生成 6 个 schema 文件
    write_schema(
        &generated_dir.join(SESSION_START_INPUT_FIXTURE),
        schema_json::<SessionStartCommandInput>()?,
    )?;
    // ... 其他 5 个文件
    
    Ok(())
}

fn schema_json<T>() -> anyhow::Result<Vec<u8>>
where
    T: JsonSchema,
{
    let schema = schema_for_type::<T>();
    let value = serde_json::to_value(schema)?;
    let value = canonicalize_json(&value);  // 按键名排序，确保输出稳定
    Ok(serde_json::to_vec_pretty(&value)?)
}

fn schema_for_type<T>() -> RootSchema
where
    T: JsonSchema,
{
    SchemaSettings::draft07()
        .with(|settings| {
            settings.option_add_null_type = false;  // Option<T> 不添加 null 类型
        })
        .into_generator()
        .into_root_schema_for::<T>()
}
```

### 3.3 自定义 Schema 生成

对于需要特殊约束的字段，使用 `schema_with` 属性指定自定义生成函数：

```rust
// 固定值字符串（const schema）
fn session_start_hook_event_name_schema(_gen: &mut SchemaGenerator) -> Schema {
    string_const_schema("SessionStart")
}

// 枚举字符串
fn permission_mode_schema(_gen: &mut SchemaGenerator) -> Schema {
    string_enum_schema(&[
        "default",
        "acceptEdits",
        "plan",
        "dontAsk",
        "bypassPermissions",
    ])
}

fn session_start_source_schema(_gen: &mut SchemaGenerator) -> Schema {
    string_enum_schema(&["startup", "resume", "clear"])
}
```

### 3.4 NullableString 类型

用于处理可能为 null 的字符串字段（如 `transcript_path`）：

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

---

## 关键代码路径与文件引用

### 4.1 文件结构

```
codex-rs/hooks/
├── src/
│   ├── bin/
│   │   └── write_hooks_schema_fixtures.rs    # 二进制入口
│   ├── schema.rs                              # Schema 生成核心逻辑
│   └── lib.rs                                 # 库导出
├── schema/
│   └── generated/                             # 生成的 schema 文件目录
│       ├── session-start.command.input.schema.json
│       ├── session-start.command.output.schema.json
│       ├── user-prompt-submit.command.input.schema.json
│       ├── user-prompt-submit.command.output.schema.json
│       ├── stop.command.input.schema.json
│       └── stop.command.output.schema.json
└── BUILD.bazel                                # Bazel 构建配置
```

### 4.2 关键代码引用

| 功能 | 文件路径 | 行号范围 |
|-----|---------|---------|
| 二进制入口 | `src/bin/write_hooks_schema_fixtures.rs` | 1-9 |
| Schema 生成主函数 | `src/schema.rs` | 211-241 |
| 输入结构定义 | `src/schema.rs` | 139-209 |
| 输出结构定义 | `src/schema.rs` | 50-137 |
| JSON 序列化 | `src/schema.rs` | 256-292 |
| 自定义 schema 函数 | `src/schema.rs` | 294-345 |
| 测试固件验证 | `src/schema.rs` | 347-437 |

### 4.3 调用链

```
write_hooks_schema_fixtures.rs:main()
    └── codex_hooks::write_schema_fixtures()
        └── schema.rs:write_schema_fixtures()
            ├── ensure_empty_dir()           # 清空生成目录
            ├── schema_json::<T>()            # 为每个类型生成 schema
            │   ├── schema_for_type::<T>()    # 使用 schemars 生成
            │   └── canonicalize_json()       # 排序键名
            └── write_schema()                # 写入文件
```

### 4.4 运行时加载

生成的 schema 文件在运行时被嵌入到二进制中：

**文件**: `src/engine/schema_loader.rs`

```rust
pub(crate) fn generated_hook_schemas() -> &'static GeneratedHookSchemas {
    static SCHEMAS: OnceLock<GeneratedHookSchemas> = OnceLock::new();
    SCHEMAS.get_or_init(|| GeneratedHookSchemas {
        session_start_command_input: parse_json_schema(
            "session-start.command.input",
            include_str!("../../schema/generated/session-start.command.input.schema.json"),
        ),
        // ... 其他 5 个
    })
}
```

---

## 依赖与外部交互

### 5.1 外部依赖

| 依赖 | 用途 | 版本来源 |
|-----|------|---------|
| `schemars` | JSON Schema 生成 | workspace |
| `serde` | 序列化/反序列化 | workspace |
| `serde_json` | JSON 处理 | workspace |
| `anyhow` | 错误处理 | workspace |

### 5.2 内部依赖

| 模块 | 用途 |
|-----|------|
| `codex_config` | 配置层栈访问 |
| `codex_protocol` | 协议类型定义（HookEventName 等） |

### 5.3 与其他组件的交互

```
┌─────────────────────────────────────────────────────────────┐
│                    write_hooks_schema_fixtures               │
│                         (二进制工具)                         │
└──────────────────────┬──────────────────────────────────────┘
                       │ 生成
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              schema/generated/*.schema.json                  │
│                    (JSON Schema 文件)                        │
└──────────────────────┬──────────────────────────────────────┘
                       │ include_str!
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              schema_loader::generated_hook_schemas()         │
│                    (运行时加载)                              │
└──────────────────────┬──────────────────────────────────────┘
                       │ 使用
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              output_parser::parse_*() 函数                   │
│         (解析 hooks 命令输出，验证是否符合 schema)            │
└─────────────────────────────────────────────────────────────┘
```

### 5.4 构建系统集成

**Bazel**: 
- `BUILD.bazel` 使用 `glob(["schema/generated/*.json"])` 收集 schema 文件
- 作为 `compile_data` 嵌入到二进制中

**Cargo**:
- 通过 `include_str!` 在编译时嵌入 schema 文件
- 测试中使用 `include_str!` 验证生成的 schema 与预期一致

---

## 风险、边界与改进建议

### 6.1 风险点

#### 6.1.1 Schema 漂移风险

**问题**: 当 `schema.rs` 中的结构定义发生变化时，如果忘记运行 `write-hooks-schema`，生成的 schema 文件将与代码不同步。

**缓解措施**:
- 测试 `generated_hook_schemas_match_fixtures` 会验证一致性
- CI 应该运行测试捕获此类问题

#### 6.1.2 JSON 排序稳定性

**问题**: `canonicalize_json` 函数对 JSON 键进行字母排序，确保输出稳定。但如果 `schemars` 的生成逻辑变化，可能导致不必要的 diff。

**代码位置**: `src/schema.rs:278-292`

#### 6.1.3 路径处理

**问题**: 二进制使用 `env!("CARGO_MANIFEST_DIR")` 作为默认路径，这在 Bazel 构建环境中可能需要特殊处理。

### 6.2 边界情况

#### 6.2.1 空目录处理

```rust
fn ensure_empty_dir(dir: &Path) -> anyhow::Result<()> {
    if dir.exists() {
        std::fs::remove_dir_all(dir)?;  // 递归删除整个目录
    }
    std::fs::create_dir_all(dir)?;      // 重新创建
    Ok(())
}
```

**注意**: 该函数会**递归删除**整个 `generated` 目录，如果传入错误路径可能导致数据丢失。

#### 6.2.2 命令行参数

- 接受单个可选参数作为输出目录
- 不验证参数是否为有效目录路径
- 不处理多个参数的情况（ silently 忽略）

### 6.3 改进建议

#### 6.3.1 增强命令行接口

```rust
// 建议：使用 clap 提供更友好的 CLI
#[derive(Parser)]
struct Args {
    /// 输出目录
    #[arg(default_value = concat!(env!("CARGO_MANIFEST_DIR"), "/schema"))]
    output: PathBuf,
    
    /// 仅验证，不写入
    #[arg(long)]
    check: bool,
    
    /// 详细输出
    #[arg(short, long)]
    verbose: bool,
}
```

#### 6.3.2 添加验证模式

添加 `--check` 模式用于 CI，验证 schema 文件是否最新而不实际写入：

```rust
fn check_schema_fixtures(schema_root: &Path) -> anyhow::Result<bool> {
    // 生成新的 schema 并与现有文件比较
    // 返回是否一致
}
```

#### 6.3.3 路径安全检查

在 `ensure_empty_dir` 中添加安全检查，防止误删除重要目录：

```rust
fn ensure_empty_dir(dir: &Path) -> anyhow::Result<()> {
    // 验证目录名是否为 "generated" 或位于预期位置
    if dir.file_name() != Some(std::ffi::OsStr::new("generated")) {
        anyhow::bail!("refusing to delete non-generated directory: {}", dir.display());
    }
    // ...
}
```

#### 6.3.4 增量更新

当前实现总是删除并重新创建整个目录。可以改为仅更新变化的文件：

```rust
fn write_schema_if_changed(path: &Path, new_content: &[u8]) -> anyhow::Result<bool> {
    if path.exists() {
        let existing = std::fs::read(path)?;
        if existing == new_content {
            return Ok(false);  // 未变化
        }
    }
    std::fs::write(path, new_content)?;
    Ok(true)
}
```

#### 6.3.5 文档生成

可以扩展工具生成 Markdown 文档，便于开发者查阅：

```rust
fn generate_markdown_docs(schema_root: &Path) -> anyhow::Result<()> {
    // 从 schema 生成人类可读的文档
}
```

### 6.4 测试覆盖

当前测试覆盖良好，包括：

1. **Schema 匹配测试**: `generated_hook_schemas_match_fixtures`
2. **Codex 扩展验证**: `turn_scoped_hook_inputs_include_codex_turn_id_extension`
3. **Schema 加载测试**: `loads_generated_hook_schemas`

建议添加：
- 命令行参数解析测试
- 错误处理测试（无效路径、权限问题等）
- 并发安全测试（如果未来支持并行生成）

---

## 附录：Schema 文件示例

### SessionStart 输入 Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "additionalProperties": false,
  "properties": {
    "cwd": { "type": "string" },
    "hook_event_name": { "const": "SessionStart", "type": "string" },
    "model": { "type": "string" },
    "permission_mode": {
      "enum": ["default", "acceptEdits", "plan", "dontAsk", "bypassPermissions"],
      "type": "string"
    },
    "session_id": { "type": "string" },
    "source": { "enum": ["startup", "resume", "clear"], "type": "string" },
    "transcript_path": { "type": ["string", "null"] }
  },
  "required": ["cwd", "hook_event_name", "model", "permission_mode", "session_id", "source", "transcript_path"],
  "title": "session-start.command.input",
  "type": "object"
}
```

### UserPromptSubmit 输出 Schema（节选）

```json
{
  "properties": {
    "continue": { "default": true, "type": "boolean" },
    "decision": { "enum": ["block"], "type": "string" },
    "reason": { "default": null, "type": "string" },
    "stopReason": { "default": null, "type": "string" },
    "suppressOutput": { "default": false, "type": "boolean" },
    "systemMessage": { "default": null, "type": "string" }
  },
  "title": "user-prompt-submit.command.output",
  "type": "object"
}
```

---

*文档生成时间: 2026-03-22*
*基于代码版本: codex-rs/hooks/src/bin/write_hooks_schema_fixtures.rs*
