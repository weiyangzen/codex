# Cargo.toml 研究文档

## 场景与职责

该 Cargo.toml 文件定义了 `codex-app-server-protocol` crate 的元数据、依赖项和构建配置。这个 crate 是 Codex 应用服务器协议的核心定义库，负责：

1. 定义客户端-服务器通信的协议类型
2. 提供 JSON-RPC 消息格式的序列化/反序列化
3. 生成 TypeScript 类型定义和 JSON Schema
4. 支持实验性 API 的标记和过滤

## 功能点目的

### 1. 库配置 (`[lib]`)
- 指定库名称为 `codex_app_server_protocol`（Rust 标识符风格）
- 入口文件为 `src/lib.rs`

### 2. 工作空间继承 (`[package]` 和 `[lints]`)
- 版本、edition、license 从工作空间继承，确保整个项目的一致性
- Lint 规则也从工作空间继承

### 3. 依赖管理 (`[dependencies]`)
核心依赖分为几类：

**协议/序列化依赖**:
- `serde` + `serde_json`: JSON 序列化
- `schemars`: JSON Schema 生成
- `ts-rs`: TypeScript 类型生成
- `serde_with`: 高级序列化工具

**Codex 内部依赖**:
- `codex-protocol`: 核心协议类型（来自 codex-rs/protocol）
- `codex-experimental-api-macros`: 实验性 API 宏
- `codex-utils-absolute-path`: 绝对路径类型

**MCP 支持**:
- `rmcp`: Model Context Protocol 实现，支持 server、macros、schemars 特性

**其他工具**:
- `clap`: 命令行参数解析（用于 bin 工具）
- `uuid`: UUID v7 生成
- `inventory`: 运行时类型注册（用于实验性 API 标记）
- `shlex`: Shell 词法分析
- `strum_macros`: 枚举工具宏
- `thiserror`: 错误定义宏
- `tracing`: 日志追踪

### 4. 开发依赖 (`[dev-dependencies]`)
- `pretty_assertions`: 更好的测试断言输出
- `similar`: 文本差异比较（用于 schema fixture 测试）
- `tempfile`: 临时文件创建
- `codex-utils-cargo-bin`: Cargo 二进制工具

## 具体技术实现

### 关键依赖详解

```toml
[dependencies]
# 协议序列化
serde = { workspace = true, features = ["derive"] }
serde_json = { workspace = true }
schemars = { workspace = true }
ts-rs = { workspace = true }

# 核心协议类型
codex-protocol = { workspace = true }

# 实验性 API 支持
codex-experimental-api-macros = { workspace = true }
inventory = { workspace = true }

# MCP 协议
rmcp = { workspace = true, default-features = false, features = [
    "base64",
    "macros",
    "schemars",
    "server",
] }
```

### 二进制工具

crate 包含两个二进制工具：

1. **`export`** (`src/bin/export.rs`):
   - 生成 TypeScript 类型定义和 JSON Schema
   - 支持 `--experimental` 标志包含实验性 API
   - 支持 `--prettier` 格式化生成的 TypeScript

2. **`write_schema_fixtures`** (`src/bin/write_schema_fixtures.rs`):
   - 重新生成 `schema/` 目录下的 fixture 文件
   - 用于 `just write-app-server-schema` 命令

## 关键代码路径与文件引用

### 源代码结构
```
src/
├── lib.rs                    # 库入口，导出所有公共类型
├── experimental_api.rs       # 实验性 API 标记 trait 和宏
├── export.rs                 # TypeScript/JSON Schema 生成逻辑
├── jsonrpc_lite.rs          # JSON-RPC 消息格式定义
├── schema_fixtures.rs       # Schema fixture 读写工具
├── protocol/
│   ├── mod.rs               # 协议模块入口
│   ├── common.rs            # 通用协议定义（ClientRequest, ServerRequest, ServerNotification）
│   ├── v1.rs                # v1 API 定义（已废弃）
│   ├── v2.rs                # v2 API 定义（主要 API）
│   ├── mappers.rs           # v1 到 v2 的映射
│   ├── serde_helpers.rs     # 序列化辅助函数
│   └── thread_history.rs    # 线程历史构建器
└── bin/
    ├── export.rs            # 导出工具
    └── write_schema_fixtures.rs  # Schema fixture 更新工具
```

### 生成的 Schema 文件
```
schema/
├── typescript/              # 生成的 TypeScript 类型
│   ├── index.ts
│   ├── v2/
│   └── ...
└── json/                    # 生成的 JSON Schema
    ├── codex_app_server_protocol.schemas.json
    ├── codex_app_server_protocol.v2.schemas.json
    └── ...
```

## 依赖与外部交互

### 上游依赖（工作空间级别）
- `serde` 1.0+
- `schemars` 0.8+
- `ts-rs` 10.0+
- `rmcp` 0.1+

### 下游使用者
- `codex-rs/app-server`: 应用服务器实现，使用协议类型处理请求
- `codex-rs/tui`: TUI 客户端，使用协议类型与服务器通信
- `codex-rs/tui_app_server`: TUI 应用服务器
- 外部客户端（如 VS Code 扩展）：使用生成的 TypeScript 类型

### 协议版本演进
- **v1**: 早期 API，已标记为废弃，保留用于向后兼容
- **v2**: 当前主要 API，包含 thread、turn、item 等核心概念

## 风险、边界与改进建议

### 风险

1. **Schema 漂移风险**:
   - Rust 类型修改后，如果不重新生成 schema，会导致 TypeScript 客户端类型不匹配
   - 测试 `schema_fixtures.rs` 会检测这种漂移，但需要手动运行 `just write-app-server-schema` 修复

2. **实验性 API 泄露**:
   - 实验性 API 通过 `#[experimental(...)]` 标记
   - 如果忘记标记，可能导致不稳定 API 被客户端依赖

3. **MCP 协议版本**:
   - `rmcp` crate 的 API 可能变化，需要关注版本更新

### 边界

1. **纯协议 crate**:
   - 不应包含任何业务逻辑
   - 只定义数据结构、序列化规则和类型转换

2. **版本兼容性**:
   - v1 API 已废弃，不应新增功能
   - v2 API 需要保持向后兼容

3. **平台兼容性**:
   - 生成的 TypeScript 类型需要兼容目标客户端（Node.js、浏览器）
   - JSON Schema 需要兼容标准验证工具

### 改进建议

1. **自动化 Schema 更新**:
   - 在 CI 中检测 schema 变更，自动提交 PR
   - 或者使用 pre-commit hook 自动更新

2. **API 版本管理**:
   - 考虑引入更正式的 API 版本控制流程
   - 添加 API 变更日志自动生成

3. **文档生成**:
   - 可以从 Rust doc 自动生成 API 文档
   - 与生成的 TypeScript 类型关联

4. **测试覆盖**:
   - 增加更多序列化/反序列化的边界测试
   - 添加与真实客户端的集成测试

5. **依赖优化**:
   - `rmcp` 特性可以按需启用，减少编译时间
   - 考虑将二进制工具拆分为独立 crate，减少库依赖
