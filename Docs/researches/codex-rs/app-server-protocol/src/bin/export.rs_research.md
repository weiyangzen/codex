# export.rs 研究文档

## 场景与职责

`export.rs` 是 `codex-app-server-protocol` crate 提供的一个命令行工具二进制文件，用于**生成 TypeScript 类型定义和 JSON Schema 文件**。它是协议类型系统与前端/客户端代码之间的桥梁，确保 Rust 中定义的 API 类型能够自动同步到 TypeScript 客户端。

该工具主要服务于以下场景：
1. **CI/CD 流程**：在构建过程中自动生成最新的类型定义
2. **开发者工作流**：通过 `just` 命令快速更新 schema 文件
3. **外部集成**：为第三方客户端提供准确的类型信息

## 功能点目的

### 1. 类型导出功能
- **TypeScript 绑定生成**：使用 `ts-rs` crate 将 Rust 类型导出为 TypeScript 接口
- **JSON Schema 生成**：使用 `schemars` crate 生成符合 JSON Schema 标准的 schema 文件
- **实验性 API 控制**：通过 `--experimental` 标志控制是否包含实验性 API

### 2. 代码格式化
- 支持可选的 Prettier 格式化，确保生成的 TypeScript 代码风格一致

### 3. 目录结构生成
- 在输出目录下创建 `v2/` 子目录存放 v2 API 相关的类型定义
- 生成索引文件 (`index.ts`) 方便客户端统一导入

## 具体技术实现

### 命令行参数结构

```rust
#[derive(Parser, Debug)]
#[command(
    about = "Generate TypeScript bindings and JSON Schemas for the Codex app-server protocol"
)]
struct Args {
    /// 输出目录
    #[arg(short = 'o', long = "out", value_name = "DIR")]
    out_dir: PathBuf,

    /// 可选的 Prettier 可执行文件路径
    #[arg(short = 'p', long = "prettier", value_name = "PRETTIER_BIN")]
    prettier: Option<PathBuf>,

    /// 包含实验性 API 方法和字段
    #[arg(long = "experimental")]
    experimental: bool,
}
```

### 核心调用流程

```
main()
├── Args::parse()  // 解析命令行参数
├── codex_app_server_protocol::generate_ts_with_options()
│   ├── ClientRequest::export_all_to()
│   ├── export_client_responses()
│   ├── ClientNotification::export_all_to()
│   ├── ServerRequest::export_all_to()
│   ├── export_server_responses()
│   ├── ServerNotification::export_all_to()
│   ├── filter_experimental_ts()  // 如未启用实验性 API
│   ├── generate_index_ts()
│   └── 可选：Prettier 格式化
└── codex_app_server_protocol::generate_json_with_experimental()
    ├── 生成信封类型 schema (RequestId, JSONRPCMessage 等)
    ├── 生成客户端请求/响应 schema
    ├── 生成服务端请求/响应 schema
    ├── 生成通知类型 schema
    └── 构建 schema bundle 并写入文件
```

### 关键数据结构

**GenerateTsOptions**（位于 `src/export.rs`）:
```rust
pub struct GenerateTsOptions {
    pub generate_indices: bool,    // 是否生成 index.ts
    pub ensure_headers: bool,      // 是否添加生成文件头
    pub run_prettier: bool,        // 是否运行 Prettier
    pub experimental_api: bool,    // 是否包含实验性 API
}
```

### 实验性 API 过滤机制

当 `--experimental` 未指定时，系统会：
1. 从 `ClientRequest.ts` 中移除实验性方法的联合类型分支
2. 从各类型定义中移除标记为 `#[experimental(...)]` 的字段
3. 删除实验性方法相关的类型定义文件
4. 从 JSON schema 中过滤实验性字段和方法

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/bin/export.rs` (34 行)

### 依赖的核心模块
| 文件 | 职责 |
|------|------|
| `src/lib.rs` | 模块聚合与公共 API 导出 |
| `src/export.rs` | TypeScript/JSON Schema 生成核心逻辑 (~1000+ 行) |
| `src/schema_fixtures.rs` | Schema fixture 读写工具 |
| `src/protocol/common.rs` | 协议类型定义与宏 |
| `src/protocol/v2.rs` | v2 API 类型定义 |
| `src/experimental_api.rs` | 实验性 API 标记 trait 与注册机制 |

### 生成的输出文件
```
<out_dir>/
├── *.ts                    # 根级别类型定义
├── v2/
│   ├── *.ts               # v2 API 类型定义
│   └── index.ts           # v2 模块索引
├── index.ts               # 根模块索引
├── codex_app_server_protocol.schemas.json      # 完整 schema bundle
└── codex_app_server_protocol.v2.schemas.json   # v2 扁平化 schema
```

## 依赖与外部交互

### 外部依赖
- **`clap`**：命令行参数解析
- **`anyhow`**：错误处理

### 内部 crate 依赖
- **`codex_app_server_protocol`**：核心协议库
  - `generate_ts_with_options()`：TypeScript 生成
  - `generate_json_with_experimental()`：JSON Schema 生成
  - `GenerateTsOptions`：生成选项

### 相关 Just 命令
根据项目 `justfile`，相关命令包括：
- `just write-app-server-schema`：调用此工具生成 schema fixtures
- 可能通过 `just export-ts` 或类似命令调用 TypeScript 导出

## 风险、边界与改进建议

### 潜在风险

1. **实验性 API 过滤的脆弱性**
   - TypeScript 过滤依赖字符串解析，可能因 `ts-rs` 输出格式变化而失效
   - 建议：增加更健壮的 AST 解析或添加格式变更检测测试

2. **并发写入问题**
   - `generate_ts_with_options` 使用多线程处理文件头添加
   - 如果输出目录被多个进程同时写入，可能产生竞态条件

3. **Prettier 依赖**
   - Prettier 是可选依赖，但未安装时生成的代码格式可能不一致
   - 建议：考虑使用 `dprint` 或内置格式化作为备选

### 边界情况

1. **空输出目录**
   - 工具会递归创建目录，但权限问题可能导致失败
   - 错误处理已通过 `anyhow::Context` 增强

2. **大量类型定义**
   - 当前实现会加载所有类型到内存，极端情况下可能占用大量 RAM
   - 但鉴于实际类型数量，这不是紧迫问题

3. **Windows 路径处理**
   - 代码使用 `PathBuf` 和 `Path`，应能正确处理 Windows 路径
   - 但 Prettier 调用在 Windows 上可能需要 `.cmd` 后缀处理

### 改进建议

1. **增量生成**
   - 当前每次都会重新生成所有文件
   - 可考虑添加文件哈希检查，仅更新变更的文件

2. **配置化输出**
   - 支持配置文件指定要生成的类型子集
   - 对大型项目可减少生成时间

3. **验证模式**
   - 添加 `--check` 模式，验证现有文件是否与生成结果一致
   - 适用于 CI 中检测未提交的 schema 变更

4. **文档生成**
   - 集成生成 Markdown 文档的功能
   - 便于维护 API 文档

5. **性能优化**
   - 当前 TypeScript 生成是单线程的，可考虑并行化
   - JSON Schema 生成已使用并行迭代器
