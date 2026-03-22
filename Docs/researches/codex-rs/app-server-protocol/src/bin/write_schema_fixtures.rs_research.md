# write_schema_fixtures.rs 研究文档

## 场景与职责

`write_schema_fixtures.rs` 是 `codex-app-server-protocol` crate 提供的另一个命令行工具二进制文件，专门用于**重新生成 vendored（内置）的 app-server schema fixtures**。与 `export.rs` 不同，该工具直接操作 crate 内部的 `schema/` 目录，确保版本控制中的 schema 文件与代码定义保持同步。

该工具的核心职责：
1. **Fixture 再生**：根据当前 Rust 类型定义重新生成 `schema/typescript/` 和 `schema/json/` 目录内容
2. **清理陈旧文件**：删除旧的生成文件，避免残留过时类型定义
3. **支持实验性 API**：通过 `--experimental` 标志生成包含实验性 API 的 fixtures

## 功能点目的

### 1. Vendored Schema 管理
- 将生成的 schema 文件作为源代码的一部分提交到版本控制
- 允许客户端在不安装 Rust 工具链的情况下获取类型定义
- 提供协议版本的快照，便于追踪变更历史

### 2. 开发工作流集成
- 通过 `just write-app-server-schema` 命令调用
- 在修改协议类型后快速更新 fixtures
- 与测试套件配合，确保 fixtures 始终与代码同步

### 3. 目录结构维护
- 自动清空目标目录，确保无残留文件
- 创建标准化的 `typescript/` 和 `json/` 子目录结构

## 具体技术实现

### 命令行参数结构

```rust
#[derive(Parser, Debug)]
#[command(about = "Regenerate vendored app-server schema fixtures")]
struct Args {
    /// 包含 `typescript/` 和 `json/` 的根目录
    #[arg(long = "schema-root", value_name = "DIR")]
    schema_root: Option<PathBuf>,

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
├── 确定 schema_root
│   └── 默认：CARGO_MANIFEST_DIR/schema
└── codex_app_server_protocol::write_schema_fixtures_with_options()
    ├── ensure_empty_dir(typescript_out_dir)   // 清空旧文件
    ├── ensure_empty_dir(json_out_dir)         // 清空旧文件
    ├── generate_ts_with_options()             // 生成 TypeScript
    └── generate_json_with_experimental()      // 生成 JSON Schema
```

### 关键数据结构

**SchemaFixtureOptions**（位于 `src/schema_fixtures.rs`）:
```rust
#[derive(Clone, Copy, Debug, Default)]
pub struct SchemaFixtureOptions {
    pub experimental_api: bool,
}
```

### 目录清空逻辑

```rust
fn ensure_empty_dir(dir: &Path) -> Result<()> {
    if dir.exists() {
        std::fs::remove_dir_all(dir)?;  // 删除整个目录
    }
    std::fs::create_dir_all(dir)?;      // 重新创建
    Ok(())
}
```

这种"清空后重建"的策略确保：
- 删除已弃用的类型定义文件
- 避免新旧文件混合导致的冲突
- 保持目录结构整洁

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs` (42 行)

### 依赖的核心模块
| 文件 | 职责 |
|------|------|
| `src/lib.rs` | 公共 API 导出，包括 `write_schema_fixtures_with_options` |
| `src/schema_fixtures.rs` | Fixture 读写核心逻辑 (~357 行) |
| `src/export.rs` | TypeScript/JSON Schema 实际生成逻辑 |
| `src/protocol/common.rs` | 协议类型定义 |

### 输入/输出路径

**默认 schema 根目录**：
```
${CARGO_MANIFEST_DIR}/schema/
├── typescript/          # TypeScript 类型定义输出
│   ├── index.ts
│   ├── v2/
│   └── ...
└── json/               # JSON Schema 文件输出
    ├── codex_app_server_protocol.schemas.json
    ├── codex_app_server_protocol.v2.schemas.json
    └── ...
```

### 相关测试
- `tests/schema_fixtures.rs`：验证 fixtures 与生成代码一致
  - `typescript_schema_fixtures_match_generated()`
  - `json_schema_fixtures_match_generated()`

## 依赖与外部交互

### 外部依赖
- **`clap`**：命令行参数解析
- **`anyhow`**：错误处理与上下文增强

### 内部 crate 依赖
- **`codex_app_server_protocol`**：核心协议库
  - `write_schema_fixtures_with_options()`：fixture 写入主入口
  - `SchemaFixtureOptions`：fixture 生成选项

### 与 Just 构建系统的集成

根据项目 `AGENTS.md`，相关命令：
```bash
# 重新生成 schema fixtures
just write-app-server-schema

# 包含实验性 API
just write-app-server-schema --experimental
```

### 与测试套件的交互

测试文件 `tests/schema_fixtures.rs` 会：
1. 读取 `schema/` 目录下的现有 fixtures
2. 在临时目录中重新生成 schema
3. 对比两者是否一致
4. 如不一致，提示运行 `just write-app-server-schema`

这种设计确保：
- 开发者不会忘记提交 schema 变更
- CI 可以检测未同步的协议修改

## 风险、边界与改进建议

### 潜在风险

1. **数据丢失风险**
   - `ensure_empty_dir` 会无条件删除整个目录
   - 如果 `--schema-root` 指向错误位置，可能导致数据丢失
   - **缓解**：添加确认提示或 `--force` 标志要求显式确认

2. **并发执行问题**
   - 如果同时运行多个实例，可能产生竞态条件
   - 目录删除和重建之间的时间窗口可能导致不一致状态
   - **建议**：添加文件锁机制

3. **权限问题**
   - 删除和创建目录需要适当的文件系统权限
   - 在只读环境（如某些 CI 配置）中会失败
   - **建议**：改进错误消息，明确指示权限问题

### 边界情况

1. **自定义 schema-root**
   - 用户可以通过 `--schema-root` 指定非标准位置
   - 需要确保该位置包含预期的子目录结构
   - 当前实现不会验证子目录是否存在

2. **Prettier 不可用**
   - Prettier 是可选的，但未指定时生成的代码可能格式不一致
   - 建议：如果未指定 Prettier，使用默认配置或跳过格式化

3. **空类型定义**
   - 如果协议定义为空，会生成空的 fixtures
   - 这是有效但可能令人困惑的情况

### 改进建议

1. **备份机制**
   ```rust
   // 建议添加
   if dir.exists() {
       let backup = format!("{}.backup.{}", dir.display(), timestamp());
       std::fs::rename(dir, backup)?;
   }
   ```

2. **增量更新模式**
   - 添加 `--incremental` 标志，仅更新变更的文件
   - 保留未变更的文件，减少 I/O 和版本控制噪音

3. **验证模式**
   - 添加 `--check` 标志，验证 fixtures 是否需要更新
   - 适用于 CI 环境，避免意外修改

4. **详细日志**
   - 添加 `--verbose` 标志，输出每个生成文件的信息
   - 便于调试生成问题

5. **选择性生成**
   - 支持 `--only-typescript` 或 `--only-json` 选项
   - 在只需要更新一种格式时节省时间

6. **与 git 集成**
   - 检测是否有未提交的协议变更
   - 提醒开发者运行更新命令

### 与 export.rs 的对比

| 特性 | export.rs | write_schema_fixtures.rs |
|------|-----------|-------------------------|
| 目标目录 | 任意指定 | 默认 crate 内 schema/ |
| 清理旧文件 | 否 | 是（清空目录） |
| 主要用途 | 外部集成/CI | 开发工作流 |
| 调用方式 | 直接运行 | 通过 just 命令 |
| 输出结构 | 灵活 | 固定 (typescript/, json/) |

两个工具共享核心的生成逻辑（`generate_ts_with_options` 和 `generate_json_with_experimental`），但在使用场景和目录管理上有所区分。
