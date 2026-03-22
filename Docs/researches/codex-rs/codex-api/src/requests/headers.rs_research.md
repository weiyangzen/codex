# headers.rs 研究文档

## 场景与职责

`headers.rs` 是 Codex API 请求模块中的 HTTP 头构建工具模块，负责为 OpenAI Responses API 请求构建和管理各种 HTTP 头信息。该模块在客户端与 OpenAI/Azure API 通信时起到关键的协议适配作用，确保请求携带正确的会话标识、子代理标识等元数据。

## 功能点目的

模块提供三个核心功能：

1. **`build_conversation_headers`** - 构建会话相关的 HTTP 头
   - 注入 `session_id` 头（当提供 conversation_id 时）
   - 用于服务端追踪和关联同一会话的多个请求

2. **`subagent_header`** - 生成子代理标识头值
   - 将 `SessionSource::SubAgent` 枚举转换为字符串标识
   - 支持 Review、Compact、MemoryConsolidation、ThreadSpawn 等子代理类型
   - 允许自定义标签（Other 变体）

3. **`insert_header`** - 安全的 HTTP 头插入辅助函数
   - 处理头名称和值的解析错误
   - 仅在解析成功时才插入头

## 具体技术实现

### 关键数据结构

```rust
// 依赖类型（来自 codex_protocol）
pub enum SessionSource {
    Cli,
    VSCode,
    Exec,
    Mcp,
    SubAgent(SubAgentSource),
    Unknown,
}

pub enum SubAgentSource {
    Review,
    Compact,
    ThreadSpawn { parent_thread_id, depth, agent_nickname, agent_role },
    MemoryConsolidation,
    Other(String),
}
```

### 关键流程

**subagent_header 转换映射：**
| SubAgentSource 变体 | 输出字符串 |
|---------------------|-----------|
| Review | "review" |
| Compact | "compact" |
| MemoryConsolidation | "memory_consolidation" |
| ThreadSpawn | "collab_spawn" |
| Other(label) | label 原值 |

**build_conversation_headers 流程：**
1. 创建空的 HeaderMap
2. 如果 conversation_id 存在，插入 `session_id` 头
3. 返回构建好的 HeaderMap

**insert_header 安全机制：**
- 使用 `http::HeaderName::parse` 验证头名称
- 使用 `HeaderValue::from_str` 验证头值
- 仅当两者都解析成功时才执行插入

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/codex-api/src/requests/headers.rs` (37 行)

### 调用方
1. **`codex-rs/codex-api/src/endpoint/responses.rs`**
   - `stream_request` 方法调用 `build_conversation_headers` 和 `subagent_header`
   - 用于构建 Responses API 的 HTTP 请求头

2. **`codex-rs/core/src/client.rs`**
   - `build_conversation_headers` 被重导出并用于 WebSocket 和 HTTP 请求
   - `build_subagent_headers` 方法（内部实现类似逻辑）

3. **`codex-rs/codex-api/src/lib.rs`**
   - 重导出 `build_conversation_headers` 供外部使用

### 依赖类型定义
- `codex-rs/protocol/src/protocol.rs` - `SessionSource` 和 `SubAgentSource` 枚举定义

### 测试文件
- `codex-rs/core/tests/responses_headers.rs` - 端到端测试子代理头
- `codex-rs/core/src/client_tests.rs` - 单元测试 `build_subagent_headers`
- `codex-rs/codex-api/tests/clients.rs` - 测试 Azure 端点的头注入

## 依赖与外部交互

### 外部 crate 依赖
- `http` - 提供 `HeaderMap` 和 `HeaderValue` 类型
- `codex_protocol` - 提供 `SessionSource` 和 `SubAgentSource` 类型

### 生成的 HTTP 头
| 头名称 | 来源函数 | 用途 |
|--------|---------|------|
| `session_id` | `build_conversation_headers` | 服务端会话追踪 |
| `x-openai-subagent` | `subagent_header` | 子代理类型标识 |
| `x-client-request-id` | `endpoint/responses.rs` | 客户端请求追踪 |

## 风险、边界与改进建议

### 潜在风险

1. **静默失败风险**：`insert_header` 在解析失败时静默忽略错误，可能导致调试困难
   - 建议：添加 tracing 日志记录解析失败的情况

2. **头名称硬编码**：`session_id` 头名称直接硬编码，缺乏集中管理
   - 建议：定义为常量，与其他头名称统一管理

3. **非 SubAgent 源返回 None**：`subagent_header` 对非 SubAgent 源返回 None，调用方需处理
   - 当前实现使用 `let-else` 模式正确处理此情况

### 边界情况

1. **空 conversation_id**：`build_conversation_headers` 正确处理 None 情况，返回空 HeaderMap
2. **非法头值**：`insert_header` 通过 Result 处理非法字符，避免 panic
3. **ThreadSpawn 参数忽略**：`ThreadSpawn` 变体的详细参数在转换中被忽略，仅输出固定字符串

### 改进建议

1. **添加文档注释**：为 `insert_header` 添加更详细的文档，说明其静默失败的行为
2. **常量提取**：将头名称提取为模块级常量
   ```rust
   pub const SESSION_ID_HEADER: &str = "session_id";
   pub const SUBAGENT_HEADER: &str = "x-openai-subagent";
   ```
3. **错误处理增强**：考虑在 debug 模式下记录头解析失败的情况
4. **测试覆盖**：当前测试主要在 `core/tests/responses_headers.rs`，建议添加单元测试直接测试 `headers.rs`
