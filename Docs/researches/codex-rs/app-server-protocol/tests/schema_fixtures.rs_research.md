# schema_fixtures.rs 研究文档

## 1. 场景与职责

### 1.1 文件定位

`codex-rs/app-server-protocol/tests/schema_fixtures.rs` 是 **Codex App Server Protocol** 的集成测试文件，负责验证协议 schema 生成与 fixture 文件的一致性。

### 1.2 核心职责

该测试文件承担以下关键职责：

1. **Schema 一致性验证**：确保 vendored（已提交到仓库的）schema fixture 文件与代码生成的 schema 完全一致
2. **TypeScript Schema 验证**：验证 `schema/typescript/` 目录下的类型定义文件
3. **JSON Schema 验证**：验证 `schema/json/` 目录下的 JSON Schema 文件
4. **防止 schema 漂移**：当开发者修改协议类型时，强制要求更新 fixture 文件

### 1.3 工作流程

```
┌─────────────────────────────────────────────────────────────────┐
│                     Schema Fixtures Test                         │
├─────────────────────────────────────────────────────────────────┤
│  1. 读取 vendored fixture 文件 (schema/typescript/, schema/json/) │
│  2. 在内存中生成新的 schema (通过 ts-rs 和 schemars)              │
│  3. 对比文件集合是否一致                                          │
│  4. 对比每个文件内容是否一致                                      │
│  5. 不一致时 panic 并提示运行 just write-app-server-schema       │
└─────────────────────────────────────────────────────────────────┘
```

### 1.4 业务价值

- **类型安全**：确保 Rust 类型定义与 TypeScript/JSON Schema 保持同步
- **CI/CD 防护**：防止未同步的 schema 变更进入主分支
- **开发者体验**：通过清晰的错误提示引导开发者更新 fixture

---

## 2. 功能点目的

### 2.1 测试函数

| 函数名 | 目的 | 验证内容 |
|--------|------|----------|
| `typescript_schema_fixtures_match_generated` | 验证 TypeScript 类型定义 | `schema/typescript/` 下的 `.ts` 文件 |
| `json_schema_fixtures_match_generated` | 验证 JSON Schema 定义 | `schema/json/` 下的 `.json` 文件 |

### 2.2 辅助函数

| 函数名 | 目的 |
|--------|------|
| `assert_schema_fixtures_match_generated` | 通用 schema 验证逻辑，支持临时目录生成对比 |
| `assert_schema_trees_match` | 对比两个 schema 树（文件集合+内容） |
| `schema_root` | 定位 schema 根目录（支持 Bazel runfiles） |
| `read_tree` | 递归读取目录为 `BTreeMap<PathBuf, Vec<u8>>` |

### 2.3 关键特性

#### 2.3.1 Bazel 兼容性

```rust
// 使用 codex_utils_cargo_bin::find_resource! 支持 Bazel runfiles
let typescript_index = codex_utils_cargo_bin::find_resource!("schema/typescript/index.ts")
    .context("resolve TypeScript schema index.ts")?;
```

- 在 Bazel manifest-only 模式下可靠解析目录
- 通过已知文件路径推导 schema 根目录

#### 2.3.2 平台无关的对比

- 使用 `BTreeMap` 确保文件顺序一致
- 使用 `similar::TextDiff` 生成统一的 diff 输出
- 清晰的错误提示引导开发者运行修复命令

#### 2.3.3 双重验证机制

1. **文件集合验证**：确保 fixture 和生成的文件列表完全一致
2. **内容逐文件验证**：确保每个文件的内容完全一致

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 TypeScript Schema 测试流程

```rust
#[test]
fn typescript_schema_fixtures_match_generated() -> Result<()> {
    // 1. 获取 schema 根目录
    let schema_root = schema_root()?;
    
    // 2. 读取 vendored fixture 树
    let fixture_tree = read_tree(&schema_root, "typescript")?;
    
    // 3. 生成内存中的 TypeScript schema
    let generated_tree = generate_typescript_schema_fixture_subtree_for_tests()
        .context("generate in-memory typescript schema fixtures")?;
    
    // 4. 对比两者
    assert_schema_trees_match("typescript", &fixture_tree, &generated_tree)?;
    
    Ok(())
}
```

#### 3.1.2 JSON Schema 测试流程

```rust
#[test]
fn json_schema_fixtures_match_generated() -> Result<()> {
    assert_schema_fixtures_match_generated("json", |output_dir| {
        generate_json_with_experimental(output_dir, false)
    })
}
```

JSON 测试使用临时目录，因为 JSON schema 生成需要文件系统输出。

### 3.2 数据结构

#### 3.2.1 Schema 树表示

```rust
// BTreeMap 确保排序一致性
BTreeMap<PathBuf, Vec<u8>>
```

- Key: 相对路径（如 `v2/ThreadStartParams.ts`）
- Value: 文件内容的字节数组

#### 3.2.2 差异报告

```rust
let diff = TextDiff::from_lines(&expected, &actual)
    .unified_diff()
    .header("fixture", "generated")
    .to_string();

panic!(
    "Vendored {label} app-server schema fixture file set doesn't match freshly generated output. \
    Run `just write-app-server-schema` to overwrite with your changes.\n\n{diff}"
);
```

### 3.3 协议与命令

#### 3.3.1 依赖的库函数

| 函数/类型 | 来源 | 用途 |
|-----------|------|------|
| `generate_typescript_schema_fixture_subtree_for_tests` | `schema_fixtures.rs` | 内存生成 TypeScript schema |
| `generate_json_with_experimental` | `export.rs` | 生成 JSON schema（支持实验性 API） |
| `read_schema_fixture_subtree` | `schema_fixtures.rs` | 递归读取 schema 子目录 |
| `SchemaFixtureOptions` | `schema_fixtures.rs` | schema 生成选项（实验性 API 开关） |

#### 3.3.2 相关 just 命令

```bash
# 重新生成 schema fixture 文件
just write-app-server-schema

# 包含实验性 API
just write-app-server-schema --experimental
```

---

## 4. 关键代码路径与文件引用

### 4.1 测试文件内部结构

```
codex-rs/app-server-protocol/tests/schema_fixtures.rs
├── typescript_schema_fixtures_match_generated()  [Line 11-21]
├── json_schema_fixtures_match_generated()        [Line 23-28]
├── assert_schema_fixtures_match_generated()      [Line 30-51]
├── assert_schema_trees_match()                   [Line 53-105]
├── schema_root()                                 [Line 107-134]
└── read_tree()                                   [Line 136-143]
```

### 4.2 被调用方（库代码）

```
codex-rs/app-server-protocol/src/
├── lib.rs
│   └── pub use schema_fixtures::*               [Line 41-47]
├── schema_fixtures.rs                           [核心实现]
│   ├── generate_typescript_schema_fixture_subtree_for_tests() [Line 53-76]
│   ├── read_schema_fixture_subtree()            [Line 43-50]
│   ├── write_schema_fixtures()                  [Line 82-84]
│   ├── write_schema_fixtures_with_options()     [Line 87-109]
│   ├── canonicalize_json()                      [Line 148-204]
│   └── read_file_bytes()                        [Line 120-146]
└── export.rs                                    [生成逻辑]
    ├── generate_ts_with_options()               [Line 105-183]
    ├── generate_json_with_experimental()        [Line 195-244]
    └── filter_experimental_ts_tree()            [Line 259-292]
```

### 4.3 调用方

| 调用方 | 用途 |
|--------|------|
| `cargo test -p codex-app-server-protocol` | 运行测试 |
| CI/CD 流程 | 防止 schema 漂移 |

### 4.4 Schema 文件位置

```
codex-rs/app-server-protocol/schema/
├── typescript/                    # TypeScript 类型定义
│   ├── index.ts                   # 入口文件
│   ├── ClientRequest.ts           # 客户端请求类型
│   ├── ServerNotification.ts      # 服务端通知类型
│   └── v2/                        # v2 API 命名空间
│       ├── ThreadStartParams.ts
│       ├── TurnStartParams.ts
│       └── ...
└── json/                          # JSON Schema 定义
    ├── codex_app_server_protocol.schemas.json      # 完整 bundle
    ├── codex_app_server_protocol.v2.schemas.json   # v2 扁平 bundle
    ├── ClientRequest.json
    ├── ServerNotification.json
    └── v2/                        # v2 API 命名空间
        └── ...
```

---

## 5. 依赖与外部交互

### 5.1 直接依赖（dev-dependencies）

| Crate | 用途 |
|-------|------|
| `anyhow` | 错误处理 |
| `codex-utils-cargo-bin` | Bazel/Cargo 二进制路径解析 |
| `pretty_assertions` | 测试断言（虽未直接使用，但项目规范要求） |
| `similar` | 文本差异对比（TextDiff） |
| `tempfile` | 临时目录（JSON 测试用） |

### 5.2 协议类型依赖

测试通过 `codex_app_server_protocol` crate 的公共 API 生成 schema：

```rust
use codex_app_server_protocol::generate_json_with_experimental;
use codex_app_server_protocol::generate_typescript_schema_fixture_subtree_for_tests;
use codex_app_server_protocol::read_schema_fixture_subtree;
```

### 5.3 类型系统依赖

Schema 生成依赖于以下核心类型（定义在 `protocol/common.rs` 和 `protocol/v2.rs`）：

| 类型 | 用途 |
|------|------|
| `ClientRequest` | 客户端请求枚举 |
| `ClientNotification` | 客户端通知枚举 |
| `ServerRequest` | 服务端请求枚举 |
| `ServerNotification` | 服务端通知枚举 |

这些类型通过 `ts-rs::TS` trait 和 `schemars::JsonSchema` trait 实现 schema 生成。

### 5.4 实验性 API 支持

```rust
// 通过 SchemaFixtureOptions 控制实验性 API
pub struct SchemaFixtureOptions {
    pub experimental_api: bool,
}
```

- 测试默认验证非实验性 schema
- 实验性 API 通过 `#[experimental("...")]` 属性标记

---

## 6. 风险、边界与改进建议

### 6.1 当前风险

#### 6.1.1 Bazel Runfiles 解析风险

```rust
// schema_root() 函数依赖特定文件存在
let typescript_index = codex_utils_cargo_bin::find_resource!("schema/typescript/index.ts")?;
let json_bundle = codex_utils_cargo_bin::find_resource!("schema/json/codex_app_server_protocol.schemas.json")?;
```

**风险**：如果这两个文件被意外删除或重命名，测试将无法定位 schema 根目录。

**缓解**：函数包含 sanity check 验证两个路径推导出的根目录一致。

#### 6.1.2 平台差异风险

虽然测试处理了 CRLF 换行符（`
` → `
`），但仍可能存在其他平台差异：

```rust
// schema_fixtures.rs 中的规范化
let text = text.replace("\r\n", "\n").replace('\r', "\n");
```

#### 6.1.3 JSON 数组排序稳定性

`canonicalize_json` 函数对部分 JSON 数组进行排序以确保对比稳定，但这可能掩盖实际的语义差异：

```rust
// 仅对可以推导稳定排序键的数组进行排序
let mut sortable = Vec::with_capacity(items.len());
for item in &items {
    let Some(key) = schema_array_item_sort_key(item) else {
        return Value::Array(items);  // 无法排序，保留原样
    };
    // ...
}
```

### 6.2 边界情况

| 边界情况 | 处理方式 |
|----------|----------|
| 空 schema 目录 | `read_tree` 返回空 `BTreeMap`，对比会失败 |
| 新增/删除文件 | 文件集合对比会失败，提示文件列表差异 |
| 文件内容变化 | 逐文件对比会失败，显示 unified diff |
| 实验性 API 变更 | 需要显式使用 `--experimental` 标志重新生成 |

### 6.3 改进建议

#### 6.3.1 增强错误信息

当前错误信息已较清晰，但可以进一步改进：

```rust
// 建议：添加更多上下文信息
panic!(
    "Schema fixture mismatch detected!\n\
    Type: {label}\n\
    Fixture root: {schema_root}\n\
    Mismatched files: {file_list}\n\n\
    Run `just write-app-server-schema` to regenerate.\n\n{diff}"
);
```

#### 6.3.2 支持选择性测试

```rust
// 建议：添加环境变量控制是否包含实验性 API
let experimental = std::env::var("TEST_EXPERIMENTAL_API").is_ok();
```

#### 6.3.3 性能优化

对于大型 schema 树，可以考虑：
- 并行文件读取
- 增量对比（仅对比修改时间戳不同的文件）

#### 6.3.4 增加快照测试覆盖

当前测试仅验证一致性，建议增加：
- 关键类型的结构快照测试
- 实验性 API 标记验证测试

### 6.4 相关代码规范

根据 `AGENTS.md` 的要求：

> **Regenerate schema fixtures when API shapes change:**
> `just write-app-server-schema`
> (and `just write-app-server-schema --experimental` when experimental API fixtures are affected)

开发者修改协议类型后，必须运行上述命令更新 fixture 文件。

---

## 7. 总结

`schema_fixtures.rs` 是 Codex App Server Protocol 的关键防护网，通过自动化测试确保：

1. **协议一致性**：Rust 类型定义与 TypeScript/JSON Schema 保持同步
2. **版本控制**：所有 schema 变更都必须显式提交到仓库
3. **开发者引导**：清晰的错误提示引导正确的修复流程

该测试文件虽然代码量不大（143 行），但承担了协议类型系统与外部消费者（TypeScript 客户端、JSON Schema 消费者）之间的桥梁验证职责，是项目类型安全体系的重要组成部分。
