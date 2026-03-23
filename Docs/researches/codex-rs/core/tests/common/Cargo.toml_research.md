# Cargo.toml 研究文档

## 文件信息
- **路径**: `codex-rs/core/tests/common/Cargo.toml`
- **大小**: 1106 bytes
- **所属模块**: core_test_support (测试支持库)

---

## 场景与职责

此 Cargo.toml 文件定义了 `core_test_support` crate，这是一个专门为 Codex Core 模块提供集成测试基础设施的测试支持库。它不属于生产代码，而是为测试套件提供共享的辅助函数、Mock 服务器和测试工具。

### 核心职责
1. **测试基础设施提供**: 为 codex-rs/core 的集成测试提供共享代码
2. **Mock 服务器支持**: 集成 wiremock 用于模拟 OpenAI API 响应
3. **异步测试支持**: 提供 tokio 运行时和测试辅助函数
4. **跨平台测试**: 支持 Windows、Linux 和 macOS 的测试场景

---

## 功能点目的

### 1. Package 配置
```toml
[package]
name = "core_test_support"
version.workspace = true
edition.workspace = true
license.workspace = true
```
- **name**: `core_test_support` - 在测试代码中通过此名称引用
- **version/edition/license**: 继承工作区级别配置，确保一致性

### 2. Library 配置
```toml
[lib]
path = "lib.rs"
```
- 显式指定库入口文件为 `lib.rs`
- 该文件使用条件编译和模块声明来组织测试支持代码

### 3. 依赖分析

#### 核心项目依赖
| 依赖 | 用途 |
|-----|------|
| `codex-core` | 被测试的核心库，提供 CodexThread、Config 等类型 |
| `codex-protocol` | 协议定义，提供 EventMsg、Op、ResponseItem 等 |
| `codex-utils-absolute-path` | 绝对路径处理工具 |
| `codex-utils-cargo-bin` | 在测试中定位编译后的二进制文件 |

#### 测试框架依赖
| 依赖 | 用途 |
|-----|------|
| `wiremock` | HTTP Mock 服务器，模拟 OpenAI API |
| `assert_cmd` | CLI 测试断言 |
| `tempfile` | 临时目录/文件管理 |
| `pretty_assertions` | 更好的测试失败输出 (dev-dependency) |

#### 异步运行时
| 依赖 | 用途 |
|-----|------|
| `tokio` | 异步运行时，启用 `net` 和 `time` 特性 |
| `futures` | 异步编程工具 |
| `tokio-tungstenite` | WebSocket 支持 |

#### 序列化与编码
| 依赖 | 用途 |
|-----|------|
| `serde_json` | JSON 序列化/反序列化 |
| `base64` | Base64 编码 |
| `zstd` | Zstd 压缩支持 (用于压缩请求体) |

#### 其他工具
| 依赖 | 用途 |
|-----|------|
| `regex-lite` | 轻量级正则表达式 |
| `walkdir` | 目录遍历 |
| `notify` | 文件系统事件监听 |
| `shlex` | Shell 命令解析 |
| `ctor` | 构造函数/初始化器宏 |

#### OpenTelemetry 支持
| 依赖 | 用途 |
|-----|------|
| `opentelemetry` | 分布式追踪 API |
| `opentelemetry_sdk` | SDK 实现 |
| `tracing` | 日志追踪 |
| `tracing-opentelemetry` | tracing 与 OpenTelemetry 集成 |
| `tracing-subscriber` | 日志订阅者 |

---

## 具体技术实现

### 依赖版本管理
所有依赖都使用 `workspace = true`，表示版本在工作区根目录的 `Cargo.toml` 中统一管理。这种设计确保：
1. 所有 crate 使用相同版本的依赖
2. 版本升级只需修改一处
3. 避免依赖冲突

### Feature 配置
```toml
tokio = { workspace = true, features = ["net", "time"] }
```
- `net`: 启用网络功能 (TcpListener 等)
- `time`: 启用时间相关功能 (sleep, timeout 等)

### Dev Dependencies
```toml
[dev-dependencies]
pretty_assertions = { workspace = true }
reqwest = { workspace = true }
```
- `pretty_assertions`: 提供彩色差异输出，改善测试体验
- `reqwest`: HTTP 客户端，用于测试 streaming_sse 服务器

---

## 关键代码路径与文件引用

### 模块结构
```
core_test_support (由本 Cargo.toml 定义)
├── lib.rs              # 库入口，定义公共 API
├── responses.rs        # OpenAI API Mock 响应
├── streaming_sse.rs    # 流式 SSE 测试服务器
├── test_codex.rs       # TestCodex 构建器
├── test_codex_exec.rs  # codex-exec 测试支持
├── context_snapshot.rs # 上下文快照格式化
├── apps_test_server.rs # Apps (MCP) 测试服务器
├── process.rs          # 进程管理工具
├── tracing.rs          # 测试追踪支持
└── zsh_fork.rs         # Zsh fork 测试运行时
```

### 使用场景
在 `codex-rs/core/tests/suite/*.rs` 中通过以下方式引用：
```rust
// 在测试文件中
use core_test_support::test_codex::test_codex;
use core_test_support::responses::{mount_sse_once, ev_completed};
use core_test_support::wait_for_event;
```

---

## 依赖与外部交互

### 与工作区的关系
```
codex-rs/Cargo.toml (workspace root)
    ├── core_test_support (本 crate)
    ├── codex-core (被测试)
    ├── codex-protocol (协议)
    └── ... 其他工具 crate
```

### 测试依赖链
```
集成测试 (如 client.rs)
    └── 依赖: core_test_support
        ├── 依赖: codex-core
        ├── 依赖: codex-protocol
        └── 依赖: 外部 crates (wiremock, tokio, etc.)
```

---

## 风险、边界与改进建议

### 潜在风险

1. **循环依赖风险**
   - `core_test_support` 依赖 `codex-core`
   - 如果 `codex-core` 的测试又依赖 `core_test_support`，可能形成循环
   - 当前设计通过将测试支持独立为 crate 避免了此问题

2. **版本漂移**
   - 使用 `workspace = true` 虽然统一管理，但如果工作区版本升级不兼容，可能影响测试

3. **平台特定依赖**
   - `zstd` 和某些系统级依赖可能在不同平台表现不一致

### 边界条件

1. **仅用于测试**
   - 此 crate 不应被生产代码使用
   - 包含大量测试专用代码（如 Mock 服务器）

2. **异步运行时假设**
   - 假设测试运行在 tokio 运行时上
   - 同步测试可能需要特殊处理

### 改进建议

1. **添加文档注释**
   ```toml
   [package]
   description = "Test support utilities for codex-core integration tests"
   ```

2. **分离可选依赖**
   - 考虑将 WebSocket 相关依赖设为可选特性：
   ```toml
   [features]
   websocket = ["tokio-tungstenite"]
   ```

3. **依赖精简**
   - 审查 `opentelemetry` 相关依赖，如果仅在少数测试中使用，可考虑设为可选

4. **版本约束**
   - 对于关键依赖如 `wiremock`，可考虑显式版本约束而非完全依赖 workspace

---

## 相关文件
- `codex-rs/Cargo.toml` - 工作区根配置
- `codex-rs/core/Cargo.toml` - 被测试的核心库
- `codex-rs/core/tests/common/lib.rs` - 库实现
- `codex-rs/core/tests/common/BUILD.bazel` - Bazel 构建配置
