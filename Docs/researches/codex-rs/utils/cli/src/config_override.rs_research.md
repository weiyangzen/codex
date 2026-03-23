# config_override.rs 研究文档

## 场景与职责

`config_override.rs` 是 `codex-utils-cli` crate 的核心配置模块，提供 `-c key=value` 命令行参数支持，允许用户在运行 Codex CLI 工具时动态覆盖配置文件（`~/.codex/config.toml`）中的设置。这是实现灵活配置管理的关键组件。

该模块主要服务于以下场景：
- **临时配置调整**：用户需要在单次运行中临时修改模型、沙箱权限等配置
- **脚本自动化**：在 CI/CD 或自动化脚本中通过命令行注入配置
- **配置调试**：快速测试不同配置组合而无需修改配置文件
- **嵌套配置覆盖**：支持使用点号路径（如 `foo.bar.baz`）覆盖嵌套配置项

## 功能点目的

### 1. 命令行参数捕获

提供 `CliConfigOverrides` 结构体，通过 `clap` 的 `ArgAction::Append` 支持多次 `-c` 参数：

```bash
codex -c model="o3" -c 'sandbox_permissions=["disk-full-read-access"]' "prompt"
```

### 2. TOML 值解析

- 尝试将值解析为 TOML 格式（支持字符串、数字、布尔、数组、内联表）
- 解析失败时回退为原始字符串（自动去除引号）
- 支持复杂嵌套结构：`{a = 1, b = 2}`

### 3. 配置应用机制

- 解析点号分隔的路径（如 `features.use_legacy_landlock`）
- 自动创建中间表结构
- 将覆盖值合并到目标配置树

### 4. 特殊键别名处理

提供 `use_legacy_landlock` → `features.use_legacy_landlock` 的自动映射，保持向后兼容性。

## 具体技术实现

### 核心数据结构

```rust
#[derive(Parser, Debug, Default, Clone)]
pub struct CliConfigOverrides {
    #[arg(
        short = 'c',
        long = "config",
        value_name = "key=value",
        action = ArgAction::Append,
        global = true,
    )]
    pub raw_overrides: Vec<String>,
}
```

### 关键方法

#### `parse_overrides()`

将原始字符串解析为 `(path, value)` 元组列表：

```rust
pub fn parse_overrides(&self) -> Result<Vec<(String, Value)>, String> {
    self.raw_overrides
        .iter()
        .map(|s| {
            // 1. 使用 splitn(2, '=') 分割键值（值部分可包含 '='）
            let mut parts = s.splitn(2, '=');
            let key = parts.next()?.trim();
            let value_str = parts.next()?.trim();
            
            // 2. 尝试 TOML 解析，失败则作为原始字符串
            let value = match parse_toml_value(value_str) {
                Ok(v) => v,
                Err(_) => {
                    let trimmed = value_str.trim().trim_matches(|c| c == '"' || c == '\'');
                    Value::String(trimmed.to_string())
                }
            };
            
            Ok((canonicalize_override_key(key), value))
        })
        .collect()
}
```

#### `apply_on_value()`

将解析后的覆盖应用到目标配置：

```rust
pub fn apply_on_value(&self, target: &mut Value) -> Result<(), String> {
    let overrides = self.parse_overrides()?;
    for (path, value) in overrides {
        apply_single_override(target, &path, value);
    }
    Ok(())
}
```

### TOML 解析技巧

```rust
fn parse_toml_value(raw: &str) -> Result<Value, toml::de::Error> {
    // 包装为临时表结构以利用 toml crate 的解析能力
    let wrapped = format!("_x_ = {raw}");
    let table: toml::Table = toml::from_str(&wrapped)?;
    table.get("_x_").cloned()
        .ok_or_else(|| SerdeError::custom("missing sentinel key"))
}
```

### 路径遍历与中间表创建

```rust
fn apply_single_override(root: &mut Value, path: &str, value: Value) {
    let parts: Vec<&str> = path.split('.').collect();
    let mut current = root;
    
    for (i, part) in parts.iter().enumerate() {
        let is_last = i == parts.len() - 1;
        
        if is_last {
            // 最终路径段：插入值
            match current {
                Value::Table(tbl) => { tbl.insert(part.to_string(), value); }
                _ => { /* 替换为表 */ }
            }
            return;
        }
        
        // 中间路径段：遍历或创建表
        match current {
            Value::Table(tbl) => {
                current = tbl.entry(part.to_string())
                    .or_insert_with(|| Value::Table(Table::new()));
            }
            _ => { /* 替换为表并继续 */ }
        }
    }
}
```

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/utils/cli/src/config_override.rs` (200 行，含测试)

### 调用方

#### CLI 定义
- `codex-rs/cli/src/main.rs` (第 71-72 行): 作为 `MultitoolCli` 的扁平化字段
- `codex-rs/tui/src/cli.rs` (第 113-114 行): `config_overrides: CliConfigOverrides`
- `codex-rs/exec/src/cli.rs` (第 82-83 行): 同上
- `codex-rs/tui_app_server/src/cli.rs` (第 113-114 行): 同上

#### MCP 命令
- `codex-rs/cli/src/mcp_cmd.rs` (第 27-28 行): 用于 MCP 服务器配置

### 配置系统集成

- `codex-core` 的 `Config` 和 `ConfigOverrides` 类型
- 配置文件路径：`~/.codex/config.toml`

### 使用示例

```bash
# 覆盖模型
codex -c model="o3" "prompt"

# 覆盖沙箱权限（数组语法）
codex -c 'sandbox_permissions=["disk-full-read-access"]' "prompt"

# 覆盖嵌套配置
codex -c shell_environment_policy.inherit=all "prompt"

# 多个覆盖
codex -c model="o3" -c features.use_legacy_landlock=true "prompt"
```

## 依赖与外部交互

### 直接依赖
- `clap::ArgAction` / `clap::Parser`: CLI 参数解析
- `serde::de::Error`: 反序列化错误处理
- `toml::Value`: TOML 值类型

### Crate 依赖关系
```
codex-utils-cli
├── clap (workspace)
├── serde (workspace)
├── toml (workspace)
└── codex-protocol (workspace)
```

### 模块导出
在 `codex-rs/utils/cli/src/lib.rs` 中公开导出：
```rust
pub use config_override::CliConfigOverrides;
```

## 风险、边界与改进建议

### 已知风险

1. **TOML 解析歧义**
   - 未引用的字符串（如 `hello`）会被 TOML 解析器拒绝
   - 回退逻辑会去除引号，但可能导致意外行为
   - 示例：`-c key=value` 中的 `value` 会被视为字符串 `"value"`

2. **路径冲突**
   - 如果配置项本身包含点号（虽然罕见），无法正确覆盖
   - 当前实现没有转义机制

3. **类型覆盖风险**
   - 可以将字符串覆盖到原本期望数字的字段
   - 运行时可能产生类型错误

4. **特殊键硬编码**
   - `use_legacy_landlock` 的别名映射是硬编码的
   - 新增别名需要修改源码

### 边界情况

| 场景 | 行为 |
|------|------|
| 空键 (`=value`) | 返回错误 "Empty key in override" |
| 无等号 (`key`) | 返回错误 "Invalid override (missing '=')" |
| 多个等号 (`key=a=b`) | 值部分保留 `a=b`（splitn(2, '=')） |
| 空值 (`key=`) | 值为空字符串 `""` |
| 目标路径非表 | 替换为表结构，可能丢失原有值 |

### 测试覆盖

模块包含 6 个单元测试：
- `parses_basic_scalar`: 整数解析
- `parses_bool`: 布尔值解析
- `fails_on_unquoted_string`: 未引用字符串失败
- `parses_array`: 数组解析
- `canonicalizes_use_legacy_landlock_alias`: 别名映射
- `parses_inline_table`: 内联表解析

### 改进建议

1. **增强错误信息**
   ```rust
   // 当前
   return Err("Override missing key".to_string());
   
   // 建议
   return Err(format!("Override '{}' missing key", s));
   ```

2. **支持引号转义**
   - 允许值中包含引号字符
   - 支持 `"key=val\"ue"` 语法

3. **类型验证**
   - 与 JSON Schema 集成，在应用前验证类型
   - 提前发现配置错误

4. **配置预览模式**
   ```bash
   codex --show-config -c model="o3"  # 显示最终配置而不执行
   ```

5. **文档生成**
   - 从配置 schema 自动生成可覆盖的键列表
   - 集成到 `--help` 输出

6. **数组追加语法**
   ```bash
   # 建议新增语法
   codex -c 'sandbox_permissions+=["new-perm"]'  # 追加而非替换
   ```
