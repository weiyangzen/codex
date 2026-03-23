# schema_loader.rs 深入研究

## 场景与职责

`schema_loader.rs` 是 Codex Hooks 系统的 JSON Schema 加载与管理模块，负责在编译时将生成的 JSON Schema 文件嵌入到二进制中，并在运行时提供静态访问。该模块确保 Hook 输入/输出格式的契约在编译期就确定，避免运行时文件读取的开销和失败风险。

**核心职责：**
1. 编译时嵌入 6 个 JSON Schema 文件（3 个事件 × 输入/输出）
2. 运行时通过 `OnceLock` 提供线程安全的懒加载访问
3. 提供统一的 Schema 访问接口
4. 验证嵌入的 Schema 文件的有效性

## 功能点目的

### 1. 编译时 Schema 嵌入

使用 `include_str!` 宏将 JSON Schema 文件内容嵌入到可执行文件中，确保：
- 无运行时文件 I/O 依赖
- Schema 与代码版本强一致
- 部署时无需携带额外的 Schema 文件

### 2. 懒加载与缓存

使用 `std::sync::OnceLock` 实现：
- 首次访问时初始化
- 后续访问零开销（直接返回静态引用）
- 线程安全，无需显式同步

### 3. Schema 验证

在编译时（通过 `parse_json_schema` 的 `panic`）和测试时验证 Schema 文件：
- 必须是有效的 JSON
- 必须是有效的 JSON Schema（对象类型）

## 具体技术实现

### 关键数据结构

```rust
pub(crate) struct GeneratedHookSchemas {
    pub session_start_command_input: Value,      // SessionStart 输入 Schema
    pub session_start_command_output: Value,     // SessionStart 输出 Schema
    pub user_prompt_submit_command_input: Value, // UserPromptSubmit 输入 Schema
    pub user_prompt_submit_command_output: Value,// UserPromptSubmit 输出 Schema
    pub stop_command_input: Value,               // Stop 输入 Schema
    pub stop_command_output: Value,              // Stop 输出 Schema
}
```

使用 `serde_json::Value` 存储 Schema，提供灵活的运行时访问能力。

### 关键流程

**初始化流程：**

```
generated_hook_schemas() 首次调用
    ↓
OnceLock::get_or_init()
    ↓
创建 GeneratedHookSchemas 实例
    ↓
对每个 Schema 文件：
    include_str!("../../schema/generated/xxx.schema.json")
        ↓
    parse_json_schema(name, content)
        ↓
    serde_json::from_str() 解析
        ↓
    成功 → 存储 Value
    失败 → panic!("invalid generated hooks schema {name}: {err}")
```

### 核心函数实现

**`generated_hook_schemas()` - 公共访问接口：**

```rust
pub(crate) fn generated_hook_schemas() -> &'static GeneratedHookSchemas {
    static SCHEMAS: OnceLock<GeneratedHookSchemas> = OnceLock::new();
    SCHEMAS.get_or_init(|| GeneratedHookSchemas {
        session_start_command_input: parse_json_schema(
            "session-start.command.input",
            include_str!("../../schema/generated/session-start.command.input.schema.json"),
        ),
        // ... 其他 5 个 Schema
    })
}
```

**设计要点：**
- 返回 `'static` 引用，确保生命周期安全
- 使用 `OnceLock` 而非 `lazy_static`，符合现代 Rust 实践
- 初始化闭包内联，避免额外的函数调用开销

**`parse_json_schema()` - Schema 解析器：**

```rust
fn parse_json_schema(name: &str, schema: &str) -> Value {
    serde_json::from_str(schema)
        .unwrap_or_else(|err| panic!("invalid generated hooks schema {name}: {err}"))
}
```

**设计决策：**
- 使用 `panic` 而非 `Result`：Schema 无效是编译期/部署期问题，不应在运行时处理
- 包含 Schema 名称：便于定位问题

### 嵌入的 Schema 文件

| 字段名 | 文件路径 | 用途 |
|--------|----------|------|
| `session_start_command_input` | `schema/generated/session-start.command.input.schema.json` | SessionStart 输入验证 |
| `session_start_command_output` | `schema/generated/session-start.command.output.schema.json` | SessionStart 输出验证 |
| `user_prompt_submit_command_input` | `schema/generated/user-prompt-submit.command.input.schema.json` | UserPromptSubmit 输入验证 |
| `user_prompt_submit_command_output` | `schema/generated/user-prompt-submit.command.output.schema.json` | UserPromptSubmit 输出验证 |
| `stop_command_input` | `schema/generated/stop.command.input.schema.json` | Stop 输入验证 |
| `stop_command_output` | `schema/generated/stop.command.output.schema.json` | Stop 输出验证 |

### Schema 文件生成

Schema 文件由 `schema.rs` 中的 `write_schema_fixtures()` 函数生成：

```rust
// schema.rs
pub fn write_schema_fixtures(schema_root: &Path) -> anyhow::Result<()> {
    let generated_dir = schema_root.join(GENERATED_DIR);
    ensure_empty_dir(&generated_dir)?;
    
    write_schema(
        &generated_dir.join(SESSION_START_INPUT_FIXTURE),
        schema_json::<SessionStartCommandInput>()?,
    )?;
    // ... 其他 Schema
}
```

使用 `schemars` crate 从 Rust 类型自动生成 JSON Schema：

```rust
fn schema_json<T>() -> anyhow::Result<Vec<u8>>
where
    T: JsonSchema,
{
    let schema = schema_for_type::<T>();
    let value = serde_json::to_value(schema)?;
    let value = canonicalize_json(&value); // 排序字段，确保确定性输出
    Ok(serde_json::to_vec_pretty(&value)?)
}
```

## 关键代码路径与文件引用

### 调用关系

```
engine/mod.rs:ClaudeHooksEngine::new()
    ↓ 调用
    schema_loader::generated_hook_schemas()
        ↓ 首次初始化时
            include_str!("...") 嵌入 6 个 JSON 文件
            parse_json_schema() 验证并解析
```

**注意：** 当前代码中 `ClaudeHooksEngine::new()` 调用 `generated_hook_schemas()` 但忽略返回值，仅用于触发初始化。这是一种"副作用触发"模式，确保 Schema 在引擎创建时即被验证。

### 文件引用

| 文件 | 引用方式 | 用途 |
|------|----------|------|
| `schema/generated/*.schema.json` | `include_str!` 编译时嵌入 | Schema 数据源 |
| `schema.rs` | 独立模块 | Schema 生成逻辑 |

### 代码路径

**编译时路径：**
```
schema.rs 中的类型定义
    ↓ schemars 宏展开
生成 JsonSchema trait 实现
    ↓ build.rs 或测试调用 write_schema_fixtures()
生成 .schema.json 文件
    ↓ 编译时 include_str!
嵌入到二进制中
```

**运行时路径：**
```
ClaudeHooksEngine::new() 调用
    ↓
generated_hook_schemas() 首次调用
    ↓
OnceLock 初始化（仅一次）
    ↓
返回 &'static GeneratedHookSchemas
```

## 依赖与外部交互

### 内部依赖

| 模块 | 依赖内容 | 交互方式 |
|------|----------|----------|
| `serde_json::Value` | Schema 存储类型 | 直接 use |
| `std::sync::OnceLock` | 懒加载机制 | 直接 use |

### 外部文件依赖

**编译时依赖（相对路径）：**
- `../../schema/generated/session-start.command.input.schema.json`
- `../../schema/generated/session-start.command.output.schema.json`
- `../../schema/generated/user-prompt-submit.command.input.schema.json`
- `../../schema/generated/user-prompt-submit.command.output.schema.json`
- `../../schema/generated/stop.command.input.schema.json`
- `../../schema/generated/stop.command.output.schema.json`

**路径解析：**
- 源文件路径：`codex-rs/hooks/src/engine/schema_loader.rs`
- Schema 路径：`codex-rs/hooks/schema/generated/`
- 相对路径 `../../schema/generated/` 正确指向目标

### 编译时依赖

```toml
[dependencies]
serde_json = { workspace = true }
```

### 测试依赖

```toml
[dev-dependencies]
pretty_assertions = { workspace = true }
```

## 风险、边界与改进建议

### 已知风险

1. **编译时路径硬编码**
   - 使用相对路径 `../../schema/generated/`
   - 如果文件结构变更，编译失败且错误信息不清晰
   - **缓解：** 文件结构稳定，且有测试覆盖

2. **Panic 在初始化时**
   - 如果 Schema 文件损坏，整个程序 panic
   - 但这是预期行为（Schema 损坏是严重问题）

3. **未使用的 Schema 字段**
   - 当前代码仅验证 Schema 可解析，未实际使用 Schema 进行验证
   - 潜在的"僵尸代码"风险

4. **`#[allow(dead_code)]` 属性**
   - 结构体标记为 `dead_code`，说明当前无活跃使用
   - 可能是为未来功能预留，或已废弃

### 边界情况

| 场景 | 行为 | 测试覆盖 |
|------|------|----------|
| Schema 文件缺失 | 编译错误（include_str! 失败） | 编译期保证 |
| Schema 文件无效 JSON | panic! | 编译期保证 |
| Schema 文件非对象 | 正常解析（Value 可接受任何 JSON） | 否 |
| 多次调用 generated_hook_schemas() | 仅首次初始化，后续直接返回 | 是（OnceLock 保证） |
| 并发首次调用 | OnceLock 保证线程安全 | 是（标准库保证） |

### 改进建议

1. **移除 `#[allow(dead_code)]` 或启用功能**
   - 如果 Schema 验证功能不再需要，考虑移除整个模块
   - 如果需要，实现实际的 JSON Schema 验证逻辑

2. **添加实际验证功能**
   ```rust
   // 建议：添加基于 Schema 的验证函数
   pub fn validate_session_start_output(output: &Value) -> Result<(), ValidationError> {
       let schema = &generated_hook_schemas().session_start_command_output;
       // 使用 jsonschema crate 进行验证
       ...
   }
   ```

3. **使用编译时路径常量**
   ```rust
   const SCHEMA_DIR: &str = "../../schema/generated/";
   const SESSION_START_INPUT: &str = concat!(SCHEMA_DIR, "session-start.command.input.schema.json");
   ```

4. **添加 Schema 版本信息**
   ```rust
   pub struct GeneratedHookSchemas {
       pub version: &'static str, // Schema 版本号
       // ...
   }
   ```

5. **延迟初始化优化**
   - 当前在 `ClaudeHooksEngine::new()` 中强制初始化
   - 如果 Schema 验证功能未启用，可延迟到实际需要时

6. **错误处理改进**
   ```rust
   // 建议：提供更详细的错误信息
   fn parse_json_schema(name: &str, schema: &str) -> Value {
       serde_json::from_str(schema)
           .unwrap_or_else(|err| {
               eprintln!("Schema content preview: {}", &schema[..100.min(schema.len())]);
               panic!("invalid generated hooks schema {name}: {err}")
           })
   }
   ```

### 测试分析

当前测试仅验证：
- 所有 6 个 Schema 可成功加载
- 每个 Schema 的 `type` 字段为 `"object"`

**测试覆盖缺口：**
- 未验证 Schema 的具体结构
- 未验证 Schema 与实际类型的对应关系
- 未测试并发初始化

**建议添加：**
```rust
#[test]
fn schema_matches_expected_structure() {
    let schemas = generated_hook_schemas();
    
    // 验证 SessionStart 输入 Schema 包含预期字段
    let input = &schemas.session_start_command_input;
    assert!(input["properties"]["sessionId"]["type"] == "string");
    assert!(input["required"].as_array().unwrap().contains(&json!("sessionId")));
}
```
