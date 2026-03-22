# Config Schema 研究文档

## 场景与职责

`schema.rs` 负责生成 `config.toml` 的 JSON Schema，用于编辑器集成和配置验证。它使用 `schemars` crate 从 Rust 类型自动生成 Schema。

主要使用场景：
- **编辑器自动补全**：VS Code 等编辑器使用 Schema 提供配置提示
- **配置验证**：在保存时验证配置格式
- **文档生成**：Schema 可作为配置文档的基础

## 功能点目的

### 1. Features Schema 生成 (`features_schema`)
生成 `[features]` 部分的 Schema：
- 只允许预定义的功能键（`FEATURES` 数组）
- 允许遗留功能键（`legacy_feature_keys()`）
- 禁止未知键（`additional_properties: false`）

### 2. MCP Servers Schema 生成 (`mcp_servers_schema`)
生成 `[mcp_servers]` 部分的 Schema：
- 允许任意服务器名称作为键
- 值必须符合 `RawMcpServerConfig` 结构

### 3. 主 Schema 生成 (`config_schema`)
从 `ConfigToml` 类型生成完整的 JSON Schema：
- 使用 JSON Schema Draft 07
- `Option<T>` 字段不作为 `null` 类型（`option_add_null_type = false`）

### 4. Schema 规范化与输出
- `canonicalize`：递归排序 JSON 键，确保输出稳定
- `config_schema_json`：生成格式化的 JSON
- `write_config_schema`：写入文件

## 具体技术实现

### Features Schema

```rust
pub(crate) fn features_schema(schema_gen: &mut SchemaGenerator) -> Schema {
    let mut object = SchemaObject {
        instance_type: Some(InstanceType::Object.into()),
        ..Default::default()
    };

    let mut validation = ObjectValidation::default();
    
    // 添加所有已知功能键
    for feature in FEATURES {
        validation
            .properties
            .insert(feature.key.to_string(), schema_gen.subschema_for::<bool>());
    }
    
    // 添加遗留功能键（向后兼容）
    for legacy_key in crate::features::legacy_feature_keys() {
        validation
            .properties
            .insert(legacy_key.to_string(), schema_gen.subschema_for::<bool>());
    }
    
    // 禁止未知键
    validation.additional_properties = Some(Box::new(Schema::Bool(false)));
    object.object = Some(Box::new(validation));

    Schema::Object(object)
}
```

### MCP Servers Schema

```rust
pub(crate) fn mcp_servers_schema(schema_gen: &mut SchemaGenerator) -> Schema {
    let mut object = SchemaObject {
        instance_type: Some(InstanceType::Object.into()),
        ..Default::default()
    };

    let validation = ObjectValidation {
        // 允许任意键，值类型为 RawMcpServerConfig
        additional_properties: Some(Box::new(schema_gen.subschema_for::<RawMcpServerConfig>())),
        ..Default::default()
    };
    object.object = Some(Box::new(validation));

    Schema::Object(object)
}
```

### 主 Schema 生成

```rust
pub fn config_schema() -> RootSchema {
    SchemaSettings::draft07()
        .with(|settings| {
            // Option<T> 不作为 null 类型，而是作为非必需字段
            settings.option_add_null_type = false;
        })
        .into_generator()
        .into_root_schema_for::<ConfigToml>()
}
```

### JSON 规范化

```rust
fn canonicalize(value: &Value) -> Value {
    match value {
        Value::Array(items) => {
            Value::Array(items.iter().map(canonicalize).collect())
        }
        Value::Object(map) => {
            // 按键排序
            let mut entries: Vec<_> = map.iter().collect();
            entries.sort_by(|(left, _), (right, _)| left.cmp(right));
            
            let mut sorted = Map::with_capacity(map.len());
            for (key, child) in entries {
                sorted.insert(key.clone(), canonicalize(child));
            }
            Value::Object(sorted)
        }
        _ => value.clone(),
    }
}
```

## 关键代码路径与文件引用

### 本文件核心函数

| 函数 | 行号 | 职责 |
|------|------|------|
| `features_schema` | 16-37 | 生成 features 部分的 Schema |
| `mcp_servers_schema` | 40-53 | 生成 mcp_servers 部分的 Schema |
| `config_schema` | 56-63 | 生成完整 Schema |
| `canonicalize` | 66-80 | 规范化 JSON（排序键） |
| `config_schema_json` | 83-89 | 生成 JSON 字符串 |
| `write_config_schema` | 92-96 | 写入文件 |

### 调用方

| 文件 | 调用点 | 用途 |
|------|--------|------|
| `codex-rs/core/src/bin/write_config_schema.rs` | `write_config_schema()` | CLI 工具 |
| `codex-rs/core/src/config/schema_tests.rs` | `config_schema_json()` | 测试验证 |

### 依赖类型

| 类型 | 来源 | 用途 |
|------|------|------|
| `ConfigToml` | `crate::config` | 主配置类型 |
| `RawMcpServerConfig` | `crate::config::types` | MCP 服务器配置 |
| `FEATURES` | `crate::features` | 功能键列表 |

## 依赖与外部交互

### Schema 生成流程

```
┌─────────────────────────────────────────────────────────────────┐
│                     Rust 类型定义                                │
│  ┌─────────────┐ ┌─────────────┐ ┌────────────────────────────┐ │
│  │ ConfigToml  │ │ FEATURES    │ │ RawMcpServerConfig         │ │
│  │ (schemars)  │ │ (功能列表)   │ │ (schemars)                 │ │
│  └─────────────┘ └─────────────┘ └────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                    schemars::SchemaGenerator
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│              schema.rs: features_schema()                        │
│              schema.rs: mcp_servers_schema()                     │
│              schema.rs: config_schema()                          │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                    RootSchema (JSON Schema)
                              ↓
                    canonicalize() - 排序键
                              ↓
                    serde_json::to_vec_pretty()
                              ↓
              codex-rs/core/config.schema.json
```

### 特殊 Schema 处理

某些字段使用自定义 Schema 生成函数：

```rust
// 在 ConfigToml 或嵌套类型中
#[schemars(schema_with = "crate::config::schema::features_schema")]
pub features: Option<crate::features::FeaturesToml>,

#[schemars(schema_with = "crate::config::schema::mcp_servers_schema")]
pub mcp_servers: Option<BTreeMap<String, McpServerConfig>>,
```

## 风险、边界与改进建议

### 已知限制

1. **Option<T> 处理**
   - `option_add_null_type = false` 使 `Option<T>` 表现为非必需字段
   - 这与 Rust 的 `None` 语义不完全对应
   - 代码位置：第 58-60 行

2. **动态键支持有限**
   - `mcp_servers` 使用 `additional_properties` 支持任意键
   - 但无法提供每个服务器的具体验证

3. **Schema 大小**
   - 完整的 Schema 可能很大（>100KB）
   - 某些编辑器可能性能受影响

### 边界情况

1. **空配置**
   - 空对象 `{}` 是合法的（所有字段都是 Optional）
   - Schema 正确反映这一点

2. **未知功能键**
   - `features_schema` 明确禁止未知键
   - 提供清晰的验证错误

3. **遗留键处理**
   - `legacy_feature_keys()` 允许已移除的功能键
   - 避免旧配置完全失效

### 改进建议

1. **Schema 分割**
   ```rust
   // 为大型配置生成多个 Schema
   pub fn config_schema_profile() -> RootSchema {
       SchemaSettings::draft07()
           .into_generator()
           .into_root_schema_for::<ConfigProfile>()
   }
   
   pub fn config_schema_permissions() -> RootSchema {
       SchemaSettings::draft07()
           .into_generator()
           .into_root_schema_for::<PermissionsToml>()
   }
   ```

2. **增强文档生成**
   ```rust
   // 使用 schemars 的文档功能
   #[derive(JsonSchema)]
   #[schemars(
       description = "Codex configuration",
       example = "{ \"model\": \"gpt-5\", \"approval_policy\": \"on-request\" }"
   )]
   pub struct ConfigToml {
       /// The model identifier to use
       pub model: Option<String>,
   }
   ```

3. **条件 Schema**
   ```rust
   // 根据平台生成不同 Schema
   #[cfg(target_os = "windows")]
   pub fn config_schema() -> RootSchema {
       // 包含 Windows 特定字段
   }
   
   #[cfg(not(target_os = "windows"))]
   pub fn config_schema() -> RootSchema {
       // 不包含 Windows 特定字段
   }
   ```

4. **测试增强**
   ```rust
   // 验证 Schema 有效性
   #[test]
   fn schema_is_valid_json_schema() {
       let schema = config_schema_json().unwrap();
       // 使用 jsonschema crate 验证
   }
   
   // 验证示例配置通过验证
   #[test]
   fn example_configs_validate() {
       // 测试示例配置
   }
   ```

5. **版本控制**
   ```rust
   pub fn config_schema_with_version() -> Value {
       let mut schema = serde_json::to_value(config_schema()).unwrap();
       schema["$id"] = "https://openai.com/codex/config.schema.json".into();
       schema["$version"] = env!("CARGO_PKG_VERSION").into();
       schema
   }
   ```

### 测试文件

- `schema_tests.rs`：验证生成的 Schema 与 fixture 匹配
- 测试确保 Schema 变更被显式审查
