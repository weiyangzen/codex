# Cargo.toml 研究文档

## 场景与职责

该文件定义了 `codex-hooks` crate 的包元数据、编译配置和依赖关系。它是 Rust 构建系统的核心配置文件，同时被 Cargo 和 Bazel（通过 rules_rust）使用。

## 功能点目的

### 1. 包元数据
```toml
[package]
edition.workspace = true
license.workspace = true
name = "codex-hooks"
version.workspace = true
```
- **name**: `"codex-hooks"` - crate 名称，遵循项目 `codex-` 前缀规范
- **edition**: 使用 workspace 定义的 Rust edition（2021）
- **license**: 继承 workspace 许可证配置
- **version**: 继承 workspace 版本号

### 2. 库配置
```toml
[lib]
doctest = false
name = "codex_hooks"
path = "src/lib.rs"
```
- **doctest = false**: 禁用文档测试，减少构建时间
- **name**: Rust 标识符使用下划线（`codex_hooks`）
- **path**: 库入口文件

### 3. Lints 配置
```toml
[lints]
workspace = true
```
继承 workspace 级别的 lint 规则，确保代码风格一致性。

### 4. 依赖项

#### 运行时依赖
| 依赖 | 用途 |
|------|------|
| `anyhow` | 错误处理 |
| `chrono` | 时间戳处理（支持 serde） |
| `codex-config` | 配置层栈访问 |
| `codex-protocol` | 协议类型（ThreadId, SandboxPermissions 等） |
| `futures` | 异步编程（BoxFuture） |
| `regex` | 正则匹配（SessionStart matcher） |
| `schemars` | JSON Schema 生成 |
| `serde` | 序列化/反序列化 |
| `serde_json` | JSON 处理 |
| `tokio` | 异步运行时（io-util, process, time） |

#### 开发依赖
| 依赖 | 用途 |
|------|------|
| `pretty_assertions` | 测试断言美化 |
| `tempfile` | 临时文件创建（测试） |
| `tokio` | 测试运行时（macros, rt-multi-thread, time） |

## 具体技术实现

### 关键依赖详解

#### codex-protocol
提供核心类型：
- `ThreadId`: 会话/线程标识
- `SandboxPermissions`: 沙箱权限配置
- `protocol::*`: Hook 相关协议类型（HookRunSummary, HookCompletedEvent 等）

#### tokio 特性选择
```toml
tokio = { workspace = true, features = ["io-util", "process", "time"] }
```
- `io-util`: 异步 IO 工具（stdin/stdout 操作）
- `process`: 子进程管理（执行 hook 命令）
- `time`: 超时控制

#### chrono 特性
```toml
chrono = { workspace = true, features = ["serde"] }
```
启用 serde 支持，使 `DateTime<Utc>` 可直接序列化。

### 版本管理策略
所有依赖版本通过 workspace 统一管理，确保：
1. 跨 crate 依赖版本一致性
2. 简化版本升级流程
3. 避免依赖冲突

## 关键代码路径与文件引用

| 路径 | 说明 |
|------|------|
| `src/lib.rs` | 库入口，模块声明和公共导出 |
| `src/types.rs` | Hook 核心类型定义 |
| `src/registry.rs` | Hooks 注册表和配置 |
| `src/engine/` | Hook 执行引擎 |
| `src/events/` | 事件处理（SessionStart, UserPromptSubmit, Stop） |
| `src/schema.rs` | JSON Schema 生成 |

## 依赖与外部交互

### 内部 Workspace 依赖
- `codex-config`: 配置系统
- `codex-protocol`: 协议定义

### 外部 Crate 依赖
- **异步生态**: `tokio`, `futures`
- **序列化**: `serde`, `serde_json`, `schemars`
- **工具**: `chrono`, `regex`, `anyhow`

### 调用方
- `codex-tui`: TUI 应用使用 hooks 进行事件处理
- `codex-cli`: CLI 工具集成

## 风险、边界与改进建议

### 风险
1. **依赖版本冲突**: workspace 统一管理降低了风险，但需注意外部 crate 的兼容性
2. **tokio 特性不足**: 当前特性集刚好满足需求，新增功能时可能需要扩展

### 边界
1. **doctest = false**: 意味着文档中的代码示例不会被测试，需要额外注意文档正确性
2. **仅支持异步**: 依赖 tokio，无法在同步环境中使用

### 改进建议
1. **特性门控**: 考虑为不同功能添加 feature flags（如 `schema` 特性控制 schema 生成）
2. **依赖精简**: 评估 `futures` 是否必要，tokio 的 `sync` 特性可能足够
3. **文档测试**: 考虑对关键公共 API 启用 doctest
4. **版本约束**: 对关键依赖（如 `schemars`）考虑添加更严格的版本约束

### 架构关联
该 crate 在架构中的位置：
```
codex-tui / codex-cli
       ↓
   codex-hooks
       ↓
   codex-protocol
   codex-config
```
作为中间层，负责将高层应用事件转换为可配置的 hook 调用。
