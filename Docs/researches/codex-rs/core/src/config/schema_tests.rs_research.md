# Config Schema Tests 研究文档

## 场景与职责

`schema_tests.rs` 是 `schema.rs` 的配套单元测试文件，负责验证生成的 JSON Schema 与预期的 fixture 文件一致。这确保了：

1. **Schema 变更被显式审查**：任何 Schema 变更都会导致测试失败，需要开发者显式更新 fixture
2. **生成逻辑正确性**：验证 `config_schema()` 函数生成预期的 Schema 结构
3. **输出稳定性**：验证 `write_config_schema` 生成的文件与内存生成一致

## 功能点目的

### 1. Schema 一致性验证 (`config_schema_matches_fixture`)
验证当前代码生成的 Schema 与 `config.schema.json` fixture 文件匹配。

### 2. 文件写入验证
验证 `write_config_schema` 函数写入的文件内容与内存生成一致。

## 具体技术实现

### 测试结构

```rust
#[test]
fn config_schema_matches_fixture() {
    // 1. 读取 fixture 文件
    let fixture_path = codex_utils_cargo_bin::find_resource!("config.schema.json")
        .expect("resolve config schema fixture path");
    let fixture = std::fs::read_to_string(fixture_path).expect("read config schema fixture");
    
    // 2. 解析 fixture
    let fixture_value: serde_json::Value =
        serde_json::from_str(&fixture).expect("parse config schema fixture");
    
    // 3. 生成当前 Schema
    let schema_json = config_schema_json().expect("serialize config schema");
    let schema_value: serde_json::Value =
        serde_json::from_slice(&schema_json).expect("decode schema json");
    
    // 4. 规范化（排序键）后比较
    let fixture_value = canonicalize(&fixture_value);
    let schema_value = canonicalize(&schema_value);
    
    // 5. 如果不匹配，生成详细的 diff 并 panic
    if fixture_value != schema_value {
        let expected = serde_json::to_string_pretty(&fixture_value).unwrap();
        let actual = serde_json::to_string_pretty(&schema_value).unwrap();
        let diff = TextDiff::from_lines(&expected, &actual)
            .unified_diff()
            .header("fixture", "generated")
            .to_string();
        panic!(
            "Current schema for `config.toml` doesn't match the fixture. \
            Run `just write-config-schema` to overwrite with your changes.\n\n{diff}"
        );
    }
    
    // 6. 验证文件写入一致性
    let tmp = TempDir::new().expect("create temp dir");
    let tmp_path = tmp.path().join("config.schema.json");
    write_config_schema(&tmp_path).expect("write config schema to temp path");
    let tmp_contents = std::fs::read_to_string(&tmp_path).unwrap();
    
    // Windows 换行符处理
    #[cfg(windows)]
    let fixture = fixture.replace("\r\n", "\n");
    #[cfg(windows)]
    let tmp_contents = tmp_contents.replace("\r\n", "\n");
    
    assert_eq!(
        trim_single_trailing_newline(&fixture),
        trim_single_trailing_newline(&tmp_contents),
        "fixture should match exactly with generated schema"
    );
}
```

### 辅助函数

```rust
fn trim_single_trailing_newline(contents: &str) -> &str {
    contents.strip_suffix('\n').unwrap_or(contents)
}
```

## 关键代码路径与文件引用

### 本文件内容

| 函数 | 行号 | 描述 |
|------|------|------|
| `trim_single_trailing_newline` | 9-11 | 辅助函数：去除末尾单个换行 |
| `config_schema_matches_fixture` | 13-55 | 主测试：验证 Schema 一致性 |

### 被测代码

- `codex-rs/core/src/config/schema.rs`：Schema 生成逻辑

### 依赖资源

| 资源 | 路径 | 用途 |
|------|------|------|
| `config.schema.json` | `codex-rs/core/config.schema.json` | 预期 Schema fixture |

### 外部 crate

| crate | 用途 |
|-------|------|
| `pretty_assertions` | 更好的断言输出 |
| `similar` | 文本 diff 生成 |
| `tempfile` | 临时目录创建 |
| `codex_utils_cargo_bin` | 资源文件定位 |

## 依赖与外部交互

### 测试流程

```
开发者修改配置类型
        ↓
运行测试: cargo test -p codex-core config_schema_matches_fixture
        ↓
┌─────────────────────────────────────────────────────────────────┐
│  Schema 变更？                                                   │
├─────────────────────────────────────────────────────────────────┤
│  否                    │  是                                     │
│  测试通过              │  测试失败，显示 diff                     │
│                        │  运行 just write-config-schema          │
│                        │  提交更新的 fixture                      │
└─────────────────────────────────────────────────────────────────┘
```

### Fixture 更新工作流

```bash
# 1. 修改 ConfigToml 或相关类型
# 2. 运行测试（预期失败）
cargo test -p codex-core config_schema_matches_fixture

# 3. 更新 fixture
just write-config-schema

# 4. 审查变更
git diff codex-rs/core/config.schema.json

# 5. 提交
```

## 风险、边界与改进建议

### 当前限制

1. **单一测试覆盖**
   - 仅有一个集成测试，覆盖所有 Schema 生成
   - 难以定位具体哪个类型变更导致失败

2. **Diff 可读性**
   - 大型 Schema 的 diff 可能很长
   - 难以快速识别关键变更

3. **平台差异**
   - 需要特殊处理 Windows 换行符
   - 代码位置：第 45-48 行

### 边界情况

1. **Fixture 文件缺失**
   - `find_resource!` 宏会 panic
   - 错误信息清晰

2. **无效 JSON**
   - fixture 或生成的 Schema 解析失败
   - 错误信息包含具体解析错误

3. **换行符差异**
   - Windows 平台自动处理
   - 其他平台行为一致

### 改进建议

1. **模块化测试**
   ```rust
   #[test]
   fn features_schema_matches_fixture() {
       // 单独测试 features 部分
   }
   
   #[test]
   fn mcp_servers_schema_matches_fixture() {
       // 单独测试 mcp_servers 部分
   }
   
   #[test]
   fn config_profile_schema_matches_fixture() {
       // 单独测试 ConfigProfile
   }
   ```

2. **结构化 Diff**
   ```rust
   // 不仅比较 JSON，还分析结构变更
   fn analyze_schema_changes(old: &Value, new: &Value) -> SchemaChanges {
       SchemaChanges {
           added_fields: vec![],
           removed_fields: vec![],
           modified_types: vec![],
       }
   }
   ```

3. **快照测试**
   ```rust
   // 使用 insta 进行快照测试
   #[test]
   fn config_schema_snapshot() {
       let schema = config_schema_json().unwrap();
       insta::assert_json_snapshot!(schema);
   }
   ```

4. **验证示例配置**
   ```rust
   #[test]
   fn example_configs_validate_against_schema() {
       let schema = config_schema();
       let validator = jsonschema::JSONSchema::compile(&schema).unwrap();
       
       let examples = vec![
           include_str!("../../examples/minimal.toml"),
           include_str!("../../examples/full.toml"),
       ];
       
       for example in examples {
           let config: Value = toml::from_str(example).unwrap();
           validator.validate(&config).expect("valid config");
       }
   }
   ```

5. **性能测试**
   ```rust
   #[test]
   fn schema_generation_performance() {
       let start = Instant::now();
       for _ in 0..100 {
           let _ = config_schema_json().unwrap();
       }
       let elapsed = start.elapsed();
       assert!(elapsed < Duration::from_secs(1), "schema generation too slow");
   }
   ```

6. **文档生成验证**
   ```rust
   #[test]
   fn schema_contains_descriptions() {
       let schema = config_schema();
       // 验证关键字段有描述
       assert!(schema.definitions["ConfigToml"].description.is_some());
   }
   ```

### 与 CI 集成

```yaml
# .github/workflows/schema.yml
name: Config Schema

on:
  pull_request:
    paths:
      - 'codex-rs/core/src/config/**'
      - 'codex-rs/core/config.schema.json'

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Check schema is up to date
        run: |
          cargo test -p codex-core config_schema_matches_fixture
```
