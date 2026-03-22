# export.rs 研究文档

## 场景与职责

`export.rs` 是 Codex App Server Protocol  crate 的核心代码生成模块，负责将 Rust 协议类型导出为 TypeScript 类型定义和 JSON Schema。这是连接 Rust 后端与 TypeScript 前端（如 VS Code 扩展）的关键桥梁。

### 主要使用场景
1. **构建时类型生成**：在编译/构建阶段生成 TypeScript 类型，供前端项目使用
2. **API 契约维护**：确保 Rust 后端与 TypeScript 前端的类型一致性
3. **实验性功能管理**：支持实验性 API 的过滤和条件导出
4. **多版本协议支持**：同时处理 v1（遗留）和 v2（当前）API 版本

## 功能点目的

### 1. TypeScript 类型生成 (`generate_ts`)
- 使用 `ts-rs` crate 将 Rust 类型导出为 TypeScript 接口
- 支持命名空间组织（v2 类型放在 `v2/` 子目录）
- 自动生成 `index.ts` 汇总文件
- 可选 Prettier 格式化

### 2. JSON Schema 生成 (`generate_json`)
- 使用 `schemars` crate 生成 JSON Schema 定义
- 支持两种 bundle 格式：
  - 完整 bundle：`codex_app_server_protocol.schemas.json`
  - 扁平 v2 bundle：`codex_app_server_protocol.v2.schemas.json`（用于 Python 代码生成）

### 3. 实验性 API 管理
- 通过 `experimental_api` 特性开关控制实验性内容的导出
- 支持方法级别和字段级别的实验性标记
- 运行时过滤生成的 TypeScript 和 JSON Schema

### 4. 命名空间与引用重写
- 自动处理 `v2::TypeName` 命名空间映射
- 重写 `$ref` 引用路径，确保跨命名空间引用正确

## 具体技术实现

### 关键数据结构

```rust
#[derive(Clone)]
pub struct GeneratedSchema {
    namespace: Option<String>,      // 命名空间（如 "v2"）
    logical_name: String,           // 类型逻辑名称
    value: Value,                   // JSON Schema 值
    in_v1_dir: bool,                // 是否在 v1 目录
}
```

### 核心流程

#### TypeScript 生成流程 (`generate_ts_with_options`)
1. 创建输出目录结构（根目录 + v2 子目录）
2. 导出各类枚举和响应类型：
   - `ClientRequest::export_all_to(out_dir)`
   - `export_client_responses(out_dir)`
   - `ClientNotification::export_all_to(out_dir)`
   - `ServerRequest::export_all_to(out_dir)`
   - `export_server_responses(out_dir)`
   - `ServerNotification::export_all_to(out_dir)`
3. 如非实验模式，过滤实验性内容
4. 生成索引文件
5. 添加文件头标记
6. 可选运行 Prettier 格式化

#### JSON Schema 生成流程 (`generate_json_with_experimental`)
1. 生成信封类型 schema（RequestId, JSONRPCMessage, JSONRPCRequest 等）
2. 导出各类参数和响应 schema：
   - `export_client_param_schemas`
   - `export_client_response_schemas`
   - `export_server_param_schemas`
   - `export_server_response_schemas`
   - `export_client_notification_schemas`
   - `export_server_notification_schemas`
3. 构建 schema bundle
4. 如非实验模式，过滤实验性内容
5. 写入 bundle 文件

### 实验性内容过滤机制

#### TypeScript 过滤 (`filter_experimental_ts`)
```rust
fn filter_experimental_ts(out_dir: &Path) -> Result<()> {
    let registered_fields = experimental_fields();
    let experimental_method_types = experimental_method_types();
    // 1. 从 ClientRequest.ts 中移除实验性方法
    filter_client_request_ts(out_dir, EXPERIMENTAL_CLIENT_METHODS)?;
    // 2. 从类型定义中移除实验性字段
    filter_experimental_type_fields_ts(out_dir, &registered_fields)?;
    // 3. 删除实验性类型文件
    remove_generated_type_files(out_dir, &experimental_method_types, "ts")?;
    Ok(())
}
```

#### JSON Schema 过滤 (`filter_experimental_schema`)
- 从根 schema 和 definitions 中移除实验性字段
- 剪枝实验性方法变体
- 删除实验性方法类型定义

### TypeScript 解析与操作

由于需要精确修改生成的 TypeScript 文件，模块实现了一套 TypeScript 代码解析器：

#### 扫描状态机 (`ScanState`)
```rust
#[derive(Default)]
struct ScanState {
    depth: Depth,                   // 括号深度跟踪
    string_delim: Option<char>,     // 当前字符串定界符
    escape: bool,                   // 转义状态
}
```

#### 关键解析函数
- `split_type_alias`: 分割类型别名定义
- `type_body_brace_span`: 定位类型体大括号范围
- `find_top_level_brace_span`: 查找顶层大括号对
- `split_top_level`: 按分隔符分割顶层元素
- `extract_method_from_arm`: 从联合类型臂提取方法名
- `parse_property_name`: 解析属性名

### Schema Bundle 构建

#### 命名空间处理
```rust
fn split_namespace(name: &str) -> (Option<&str>, &str) {
    name.split_once("::")
        .map_or((None, name), |(ns, rest)| (Some(ns), rest))
}
```

#### 引用重写
- `rewrite_refs_to_namespace`: 将 `#/definitions/Type` 重写为 `#/definitions/v2/Type`
- `rewrite_refs_to_known_namespaces`: 根据已知类型映射重写引用

#### 扁平 v2 Bundle 构建 (`build_flat_v2_schema`)
将嵌套的 v2 定义扁平化到根 definitions，同时保留共享根定义和依赖：
1. 提取 v2 命名空间定义
2. 收集共享根定义（ClientRequest, ServerNotification）
3. 收集非 v2 依赖
4. 合并所有定义到扁平结构
5. 重写引用路径

## 关键代码路径与文件引用

### 主要入口函数
| 函数 | 位置 | 用途 |
|------|------|------|
| `generate_types` | L76-80 | 同时生成 TS 和 JSON |
| `generate_ts` | L101-103 | 生成 TypeScript |
| `generate_ts_with_options` | L105-183 | 带选项生成 TS |
| `generate_json` | L185-193 | 生成 JSON Schema |
| `generate_json_with_experimental` | L195-244 | 带实验性选项生成 JSON |

### 实验性过滤相关
| 函数 | 位置 | 用途 |
|------|------|------|
| `filter_experimental_ts` | L246-257 | TS 实验性过滤入口 |
| `filter_client_request_ts` | L295-306 | 过滤 ClientRequest 中的实验性方法 |
| `filter_experimental_type_fields_ts` | L334-360 | 过滤类型中的实验性字段 |
| `filter_experimental_schema` | L400-407 | JSON Schema 实验性过滤入口 |

### TypeScript 解析工具
| 函数 | 位置 | 用途 |
|------|------|------|
| `ScanState` | L883-930 | 扫描状态机 |
| `split_top_level` | L757-760 | 顶层分割 |
| `extract_method_from_arm` | L782-797 | 提取方法名 |
| `parse_property_name` | L818-852 | 解析属性名 |

### Schema 构建工具
| 函数 | 位置 | 用途 |
|------|------|------|
| `build_schema_bundle` | L946-1027 | 构建 schema bundle |
| `build_flat_v2_schema` | L1041-1089 | 构建扁平 v2 bundle |
| `rewrite_refs_to_namespace` | L1506-1530 | 重写命名空间引用 |
| `collect_namespaced_types` | L1569-1589 | 收集命名空间类型 |

### 测试覆盖
测试模块位于 L2029-2820，包含：
- `generated_ts_optional_nullable_fields_only_in_params`: 验证可选可空字段仅在 Params 类型中
- `generate_ts_with_experimental_api_retains_experimental_entries`: 验证实验性内容保留
- `stable_schema_filter_removes_mock_thread_start_field`: 验证稳定模式过滤
- `build_schema_bundle_rewrites_root_helper_refs_to_namespaced_defs`: 验证引用重写
- `build_flat_v2_schema_keeps_shared_root_schemas_and_dependencies`: 验证扁平 bundle 构建

## 依赖与外部交互

### 外部 Crate 依赖
| Crate | 用途 |
|-------|------|
| `ts-rs` | Rust 到 TypeScript 的类型导出 |
| `schemars` | JSON Schema 生成 |
| `serde_json` | JSON 序列化/反序列化 |
| `anyhow` | 错误处理 |
| `inventory` | 实验性字段注册（通过 `experimental_api`） |

### 内部模块交互
```
export.rs
├── experimental_api.rs    # 实验性 API 标记定义
├── protocol/common.rs     # 协议枚举定义（ClientRequest, ServerRequest 等）
├── protocol/v2.rs         # v2 API 类型定义
└── schema_fixtures.rs     # 测试固件
```

### CLI 入口
`bin/export.rs` 提供命令行接口：
```bash
codex-app-server-protocol-export \
  --out-dir ./generated \
  --prettier ./node_modules/.bin/prettier \
  --experimental  # 包含实验性 API
```

### 构建系统集成
通过 `just write-app-server-schema` 命令调用（见 AGENTS.md）。

## 风险、边界与改进建议

### 已知风险

1. **TypeScript 解析器脆弱性**
   - 使用自定义字符串解析而非 AST 解析
   - 复杂类型定义可能导致解析失败
   - 风险区域：`filter_client_request_ts_contents`, `filter_experimental_type_fields_ts_contents`

2. **命名空间冲突**
   - 自动编号定义命名可能冲突（`detect_numbered_definition_collisions` 会 panic）
   - 需要手动使用 `#[schemars(rename = "...")]` 解决

3. **实验性过滤不完全**
   - 依赖 `inventory` 注册的实验性字段
   - 如果宏使用不当，可能导致过滤遗漏

4. **v1 API 遗留债务**
   - `JSON_V1_ALLOWLIST` 硬编码允许列表
   - `V1_CLIENT_REQUEST_METHODS` 硬编码方法列表
   - 新增 v1 方法需要手动更新这些列表

### 边界条件

1. **并发处理**
   - TypeScript 文件头添加使用线程池并行处理（L140-163）
   - 基于 `thread::available_parallelism()` 确定工作线程数

2. **内存使用**
   - 大型 schema bundle 可能占用大量内存
   - `BTreeMap<PathBuf, String>` 用于内存中的树操作

3. **文件系统操作**
   - 递归遍历目录查找 `.ts` 和 `.json` 文件
   - 临时目录用于测试（使用 `Uuid::now_v7()` 命名）

### 改进建议

1. **使用标准 TypeScript AST 解析器**
   - 当前自定义解析器维护成本高
   - 建议评估 `swc` 或 `oxc` 的 Rust 绑定

2. **增量生成支持**
   - 当前每次生成都是全量
   - 可添加文件哈希检查，只修改变更的文件

3. **更好的错误上下文**
   - 某些 `anyhow` 错误缺少具体文件路径上下文
   - 建议在错误链中保留更多上下文信息

4. **Schema 验证**
   - 生成后可添加 JSON Schema 自验证
   - 确保所有 `$ref` 指向有效的定义

5. **文档生成**
   - 可扩展生成 OpenAPI/Swagger 规范
   - 为 API 端点生成文档注释

6. **性能优化**
   - `build_schema_bundle` 中的多次克隆可优化
   - 考虑使用 `Arc<Value>` 共享不可变数据

### 测试建议

1. 添加模糊测试验证 TypeScript 解析器鲁棒性
2. 添加性能基准测试监控生成时间
3. 添加集成测试验证生成文件可编译性
4. 添加差异测试检测意外变更
