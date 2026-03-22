# Config Schema Markdown 研究文档

## 场景与职责

`schema.md` 是一个简短的文档文件，说明如何为 `config.toml` 生成 JSON Schema。该 Schema 用于编辑器集成（如 VS Code），提供配置文件的自动补全和验证。

## 功能点目的

### 1. 文档目的
- 说明 JSON Schema 的生成方式
- 指导开发者何时需要重新生成 Schema
- 提供生成命令

## 具体技术实现

### 文件内容

```markdown
# Config JSON Schema

We generate a JSON Schema for `~/.codex/config.toml` from the `ConfigToml` type
and commit it at `codex-rs/core/config.schema.json` for editor integration.

When you change any fields included in `ConfigToml` (or nested config types),
regenerate the schema:

```
just write-config-schema
```
```

### 实现机制

1. **Schema 来源**：`ConfigToml` 结构体（使用 `schemars` 派生）
2. **输出位置**：`codex-rs/core/config.schema.json`
3. **生成命令**：`just write-config-schema`

### 生成流程

```
┌─────────────────────────────────────────────────────────────┐
│              ConfigToml (with schemars::JsonSchema)          │
│              └── 嵌套类型（ConfigProfile, NetworkToml 等）    │
└─────────────────────────────────────────────────────────────┘
                              ↓
                    schema::config_schema()
                              ↓
                    serde_json::to_vec_pretty()
                              ↓
              codex-rs/core/config.schema.json
                              ↓
              VS Code / 其他编辑器集成
```

## 关键代码路径与文件引用

### 相关文件

| 文件 | 职责 |
|------|------|
| `codex-rs/core/src/config/schema.rs` | Schema 生成逻辑 |
| `codex-rs/core/config.schema.json` | 生成的 Schema 文件 |
| `codex-rs/core/src/config/mod.rs` | `ConfigToml` 定义 |
| `justfile` | `write-config-schema` 命令定义 |

### 生成命令定义

在 `codex-rs/justfile` 中：
```just
write-config-schema:
    cargo run -p codex-core --bin write-config-schema
```

## 依赖与外部交互

### 编辑器集成

生成的 JSON Schema 可用于：
- **VS Code**：通过 `settings.json` 关联
- **IntelliJ**：自动识别
- **Vim/Neovim**：配合 LSP 使用
- **其他**：任何支持 JSON Schema 的编辑器

### VS Code 配置示例

```json
{
  "json.schemas": [
    {
      "fileMatch": [".codex/config.toml"],
      "url": "./codex-rs/core/config.schema.json"
    }
  ]
}
```

## 风险、边界与改进建议

### 当前限制

1. **TOML 支持**
   - JSON Schema 主要针对 JSON 设计
   - TOML 的某些特性（如日期、多行字符串）可能支持不完善

2. **动态验证**
   - Schema 只能验证结构，不能验证逻辑
   - 例如：不能验证 `model_provider` 引用存在的 provider

3. **版本同步**
   - Schema 需要手动重新生成
   - 可能忘记更新，导致编辑器提示与实际行为不符

### 改进建议

1. **CI 检查**
   ```yaml
   # 在 CI 中添加检查
   - name: Check config schema is up to date
     run: |
       just write-config-schema
       git diff --exit-code codex-rs/core/config.schema.json
   ```

2. **预提交钩子**
   ```bash
   # .git/hooks/pre-commit
   if git diff --cached --name-only | grep -q "codex-rs/core/src/config"; then
       echo "Config files changed, regenerating schema..."
       just write-config-schema
       git add codex-rs/core/config.schema.json
   fi
   ```

3. **扩展文档**
   ```markdown
   ## Schema 字段说明
   
   - 所有 `Option<T>` 字段在 Schema 中标记为非必需
   - 路径字段使用 `AbsolutePathBuf` 类型，接受绝对路径或 `~/` 开头
   - `features` 字段只允许预定义的功能键
   
   ## 自定义验证
   
   某些验证无法在 JSON Schema 中表达，运行时检查包括：
   - `model_provider` 必须引用 `model_providers` 中定义的 provider
   - `approval_policy` 与 `sandbox_mode` 的组合有效性
   ```

4. **在线 Schema 发布**
   - 考虑发布到 SchemaStore.org
   - 使所有用户自动获得编辑器支持，无需本地配置

### 相关代码

`schema.rs` 中的核心函数：

```rust
/// Build the config schema for `config.toml`.
pub fn config_schema() -> RootSchema {
    SchemaSettings::draft07()
        .with(|settings| {
            settings.option_add_null_type = false;
        })
        .into_generator()
        .into_root_schema_for::<ConfigToml>()
}
```

注意 `option_add_null_type = false` 的设置，这使得 `Option<T>` 字段在 Schema 中表现为非必需字段，而不是可 null 的字段。
