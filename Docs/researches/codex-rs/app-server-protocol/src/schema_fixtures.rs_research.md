# schema_fixtures.rs 研究文档

## 场景与职责

`schema_fixtures.rs` 是 `codex-app-server-protocol` crate 的核心工具模块，负责管理协议 Schema 的生成、读取、比较和写入。它是连接 Rust 类型系统与外部客户端（TypeScript/JavaScript）的桥梁。

### 核心职责

1. **Schema 固件读写**：管理 `schema/typescript/` 和 `schema/json/` 目录下的文件
2. **跨平台规范化**：处理 Windows/Unix 换行符差异、JSON 数组排序等跨平台问题
3. **实验性 API 过滤**：支持生成包含/排除实验性 API 的 Schema
4. **测试支持**：为测试提供内存中的 Schema 树生成

### 使用场景

- **开发工作流**：`just write-app-server-schema` 命令调用此模块生成 Schema
- **CI 验证**：测试确保生成的 Schema 与代码同步
- **客户端集成**：TypeScript 客户端使用生成的类型定义

## 功能点目的

### 1. Schema 读取功能

```rust
pub fn read_schema_fixture_tree(schema_root: &Path) -> Result<BTreeMap<PathBuf, Vec<u8>>>
pub fn read_schema_fixture_subtree(schema_root: &Path, label: &str) -> Result<BTreeMap<PathBuf, Vec<u8>>>
```

- 递归读取 Schema 目录，返回按路径排序的文件映射
- 支持 TypeScript 和 JSON 两种格式
- 自动规范化文件内容（换行符、JSON 格式）

### 2. Schema 写入功能

```rust
pub fn write_schema_fixtures(schema_root: &Path, prettier: Option<&Path>) -> Result<()>
pub fn write_schema_fixtures_with_options(
    schema_root: &Path,
    prettier: Option<&Path>,
    options: SchemaFixtureOptions,
) -> Result<()>
```

- 清空并重新生成 Schema 目录
- 支持 Prettier 代码格式化
- 支持实验性 API 开关

### 3. 测试专用生成

```rust
#[doc(hidden)]
pub fn generate_typescript_schema_fixture_subtree_for_tests() -> Result<BTreeMap<PathBuf, Vec<u8>>>
```

- 在内存中生成 TypeScript Schema，不写入磁盘
- 用于测试验证生成结果
- 自动过滤实验性 API 并生成索引文件

### 4. JSON 规范化

```rust
fn canonicalize_json(value: &Value) -> Value
fn schema_array_item_sort_key(item: &Value) -> Option<String>
```

- 对 JSON Schema 中的数组进行稳定排序
- 解决跨平台生成顺序不一致问题
- 基于 `$ref` 和 `title` 字段生成排序键

## 具体技术实现

### 核心数据结构

```rust
#[derive(Clone, Copy, Debug, Default)]
pub struct SchemaFixtureOptions {
    pub experimental_api: bool,
}
```

### 文件读取与规范化

```rust
fn read_file_bytes(path: &Path) -> Result<Vec<u8>> {
    // JSON 文件：解析后重新序列化，确保格式一致
    // TypeScript 文件：统一换行符为 LF，移除生成头
}
```

### JSON 数组排序策略

```rust
fn schema_array_item_sort_key(item: &Value) -> Option<String> {
    match item {
        Value::Object(map) => {
            if let Some(Value::String(reference)) = map.get("$ref") {
                Some(format!("ref:{reference}"))
            } else if let Some(Value::String(title)) = map.get("title") {
                Some(format!("title:{title}"))
            } else {
                None  // 无法排序的数组保持原样
            }
        }
        // ... 其他类型处理
    }
}
```

### TypeScript 依赖收集

```rust
fn collect_typescript_fixture_file<T: TS + 'static + ?Sized>(
    files: &mut BTreeMap<PathBuf, String>,
    seen: &mut HashSet<TypeId>,
) -> Result<()>
```

- 使用 `ts-rs` 的 `TS` trait 生成 TypeScript 代码
- 通过 `TypeVisitor` 递归收集依赖类型
- 使用 `TypeId` 去重避免循环依赖

### 实验性 API 过滤流程

```rust
fn filter_experimental_ts_tree(tree: &mut BTreeMap<PathBuf, String>) -> Result<()>
```

1. 获取所有标记为实验性的字段
2. 过滤 `ClientRequest.ts` 中的实验性方法
3. 从各类型文件中移除实验性字段
4. 移除未使用的类型导入

## 关键代码路径与文件引用

### 内部调用关系

```
write_schema_fixtures
├── ensure_empty_dir          # 清空目标目录
├── generate_ts_with_options  # 生成 TypeScript (export.rs)
│   ├── ClientRequest::export_all_to
│   ├── export_client_responses
│   ├── filter_experimental_ts
│   └── generate_index_ts
└── generate_json_with_experimental  # 生成 JSON Schema (export.rs)
    ├── write_json_schema
    ├── build_schema_bundle
    └── filter_experimental_schema

read_schema_fixture_tree
└── collect_files_recursive
    └── read_file_bytes
        ├── canonicalize_json    # JSON 规范化
        └── 换行符规范化        # TypeScript 处理

generate_typescript_schema_fixture_subtree_for_tests
├── collect_typescript_fixture_file
│   └── T::export_to_string()   # ts-rs 生成
├── visit_typescript_fixture_dependencies
│   └── TypeScriptFixtureCollector (TypeVisitor)
├── filter_experimental_ts_tree
└── generate_index_ts_tree
```

### 依赖模块

| 模块 | 用途 |
|------|------|
| `export.rs` | `generate_ts_with_options`, `filter_experimental_ts_tree` |
| `protocol/common.rs` | `visit_client_response_types`, `visit_server_response_types` |
| `protocol/v2.rs` | `ClientRequest`, `ClientNotification`, `ServerRequest`, `ServerNotification` |

### 外部依赖使用

| 依赖 | 使用场景 |
|------|----------|
| `ts-rs` | TypeScript 代码生成 (`TS::export_to_string`, `TS::visit_dependencies`) |
| `serde_json` | JSON 解析和序列化 |
| `anyhow` | 错误处理 |

## 依赖与外部交互

### 文件系统交互

```rust
// 目录结构
schema/
├── typescript/
│   ├── v1/
│   ├── v2/
│   └── index.ts
└── json/
    ├── v1/
    ├── v2/
    └── codex_app_server_protocol.schemas.json
```

### 与 export.rs 的协作

`schema_fixtures.rs` 负责高层流程（目录管理、文件读写），`export.rs` 负责具体生成逻辑：

- `generate_ts_with_options`：生成 TypeScript 文件
- `generate_json_with_experimental`：生成 JSON Schema
- `filter_experimental_ts_tree`：过滤实验性 API

### 与协议类型的交互

通过 `ts-rs` 的 `TS` trait 与协议类型交互：
- `ClientRequest::export_all_to()`
- `ClientRequest::export_to_string()`
- `T::visit_dependencies()`

## 风险、边界与改进建议

### 当前风险

1. **平台差异**：虽然已处理换行符和 JSON 排序，但文件系统遍历顺序仍可能影响结果
2. **内存使用**：`generate_typescript_schema_fixture_subtree_for_tests` 在内存中构建整个 Schema 树，大型项目可能内存压力
3. **错误处理**：部分错误使用 `unwrap_or` 回退，可能掩盖问题

### 边界情况处理

| 场景 | 处理方式 |
|------|----------|
| Windows CRLF | 统一替换为 LF |
| JSON 数组顺序 | 基于 `$ref`/`title` 排序 |
| 循环依赖 | 使用 `HashSet<TypeId>` 去重 |
| 符号链接 | 使用 `metadata()` 跟随链接 |
| 空目录 | `ensure_empty_dir` 先删除后创建 |

### 改进建议

1. **增量生成**：当前每次全量生成，可考虑增量更新
2. **并行处理**：文件生成可并行化（TypeScript 和 JSON 独立）
3. **缓存机制**：类型哈希未变化时跳过生成
4. **验证增强**：添加 Schema 语义验证，不仅比较文本
5. **文档生成**：自动生成 API 变更日志

### 测试覆盖

当前测试仅覆盖 JSON 规范化：
```rust
#[test]
fn canonicalize_json_sorts_string_arrays() { ... }

#[test]
fn canonicalize_json_sorts_schema_ref_arrays() { ... }
```

建议增加：
- 文件系统操作测试（使用临时目录）
- 实验性 API 过滤测试
- 跨平台一致性测试

### 维护注意事项

1. 修改后运行 `cargo test -p codex-app-server-protocol`
2. Schema 变更需同步更新固件：`just write-app-server-schema`
3. 新增协议类型需确保实现 `TS` trait
4. 实验性字段需正确标记以通过过滤
