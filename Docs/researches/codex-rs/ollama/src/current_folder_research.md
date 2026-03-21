# Research: codex-rs/ollama/src

## 概述

`codex-rs/ollama/src` 是 Codex CLI 的 Ollama 本地模型提供者集成模块，负责与本地运行的 Ollama 服务器进行通信，实现模型拉取、版本检查和进度报告等功能。该模块是 Codex 支持开源本地模型（OSS）的关键组件。

---

## 场景与职责

### 核心场景

1. **本地 OSS 模型支持**：当用户使用 `--oss` 标志时，Codex 需要与本地 Ollama 服务器通信，使用本地模型替代 OpenAI 云端 API
2. **模型自动拉取**：如果指定的模型不存在于本地，自动触发 `ollama pull` 操作
3. **版本兼容性检查**：确保 Ollama 服务器版本支持 Responses API（最低版本 0.13.4）
4. **进度可视化**：在 CLI 和 TUI 中显示模型下载进度

### 职责边界

| 职责 | 说明 |
|------|------|
| 服务器发现与连接 | 通过 `OllamaClient` 建立与本地 Ollama 实例的 HTTP 连接 |
| 模型管理 | 查询本地模型列表 (`fetch_models`)、拉取新模型 (`pull_model_stream`) |
| 版本检查 | 获取 Ollama 版本并验证是否支持 Responses API |
| 进度报告 | 提供 `PullProgressReporter` trait 及 CLI/TUI 实现 |
| URL 处理 | 支持 OpenAI 兼容端点 (`/v1`) 和原生 Ollama API (`/api`) |

---

## 功能点目的

### 1. 客户端连接 (`client.rs`)

**目的**：建立与 Ollama 服务器的可靠连接，提供模型查询和拉取功能。

**关键功能**：
- `OllamaClient::try_from_oss_provider()` - 从配置创建客户端并验证服务器可达性
- `probe_server()` - 健康检查，支持 OpenAI 兼容端点 (`/v1/models`) 和原生端点 (`/api/tags`)
- `fetch_models()` - 获取本地可用模型列表
- `fetch_version()` - 获取 Ollama 服务器版本
- `pull_model_stream()` - 流式拉取模型，返回 `PullEvent` 流
- `pull_with_reporter()` - 带进度报告的高级拉取接口

### 2. 进度报告 (`pull.rs`)

**目的**：将模型拉取的底层事件转换为用户可见的进度信息。

**关键组件**：
- `PullEvent` 枚举 - 表示拉取过程中的各种事件（状态更新、块进度、成功、错误）
- `PullProgressReporter` trait - 进度报告抽象接口
- `CliProgressReporter` - 命令行进度条实现（显示下载速度、百分比、总大小）
- `TuiProgressReporter` - TUI 进度报告（当前委托给 CLI 实现）

### 3. 事件解析 (`parser.rs`)

**目的**：将 Ollama API 返回的 JSON 响应解析为结构化的 `PullEvent`。

**关键功能**：
- `pull_events_from_value()` - 解析 JSON 对象，提取状态、摘要、总大小、已完成大小等信息

### 4. URL 处理 (`url.rs`)

**目的**：处理 OpenAI 兼容端点和原生 Ollama API 的 URL 转换。

**关键功能**：
- `is_openai_compatible_base_url()` - 检测 URL 是否指向 OpenAI 兼容端点（以 `/v1` 结尾）
- `base_url_to_host_root()` - 将 `/v1` 后缀的 URL 转换为 Ollama 原生 API 根路径

### 5. 库入口 (`lib.rs`)

**目的**：提供高层 API 供其他模块使用。

**关键功能**：
- `DEFAULT_OSS_MODEL` - 默认 OSS 模型 `"gpt-oss:20b"`
- `ensure_oss_ready()` - 完整的 OSS 环境准备流程（检查服务器、检查模型、按需拉取）
- `ensure_responses_supported()` - 验证 Ollama 版本是否支持 Responses API（>= 0.13.4）

---

## 具体技术实现

### 关键流程

#### 1. OSS 环境准备流程 (`ensure_oss_ready`)

```rust
pub async fn ensure_oss_ready(config: &Config) -> std::io::Result<()> {
    // 1. 确定要使用的模型
    let model = config.model.as_ref().unwrap_or(DEFAULT_OSS_MODEL);
    
    // 2. 创建客户端并验证服务器可达
    let ollama_client = OllamaClient::try_from_oss_provider(config).await?;
    
    // 3. 查询本地模型列表
    match ollama_client.fetch_models().await {
        Ok(models) => {
            // 4. 如果模型不存在，触发拉取
            if !models.iter().any(|m| m == model) {
                let mut reporter = CliProgressReporter::new();
                ollama_client.pull_with_reporter(model, &mut reporter).await?;
            }
        }
        Err(err) => {
            // 非致命错误，上层可能稍后处理
            tracing::warn!("Failed to query local models: {}", err);
        }
    }
    Ok(())
}
```

#### 2. 模型拉取流处理 (`pull_model_stream`)

```rust
pub async fn pull_model_stream(&self, model: &str) -> io::Result<BoxStream<'static, PullEvent>> {
    // 1. 发送 POST /api/pull 请求
    let resp = self.client.post(url)
        .json(&json!({"model": model, "stream": true}))
        .send().await?;
    
    // 2. 处理 SSE 流式响应
    let s = async_stream::stream! {
        while let Some(chunk) = stream.next().await {
            // 3. 按行解析 JSON
            while let Some(pos) = buf.iter().position(|b| *b == b'\n') {
                let line = buf.split_to(pos + 1);
                if let Ok(value) = serde_json::from_str::<JsonValue>(text) {
                    // 4. 转换为 PullEvent
                    for ev in pull_events_from_value(&value) { yield ev; }
                    // 5. 检查错误或成功状态
                    if error_detected { yield PullEvent::Error(...); return; }
                    if status == "success" { yield PullEvent::Success; return; }
                }
            }
        }
    };
    Ok(Box::pin(s))
}
```

#### 3. 进度报告渲染 (`CliProgressReporter`)

```rust
impl PullProgressReporter for CliProgressReporter {
    fn on_event(&mut self, event: &PullEvent) -> io::Result<()> {
        match event {
            PullEvent::Status(status) => {
                // 显示状态文本（跳过 "pulling manifest" 减少噪音）
            }
            PullEvent::ChunkProgress { digest, total, completed } => {
                // 按 digest 聚合进度
                // 计算总进度百分比
                // 显示：done_gb/total_gb (pct%) speed_mb/s
            }
            PullEvent::Success => { /* 换行结束 */ }
            PullEvent::Error(_) => { /* 由调用者处理 */ }
        }
    }
}
```

### 数据结构

#### `OllamaClient`

```rust
pub struct OllamaClient {
    client: reqwest::Client,      // HTTP 客户端（5秒连接超时）
    host_root: String,            // 服务器根地址（如 http://localhost:11434）
    uses_openai_compat: bool,     // 是否使用 OpenAI 兼容端点
}
```

#### `PullEvent`

```rust
pub enum PullEvent {
    Status(String),                // 状态消息（如 "verifying", "writing"）
    ChunkProgress {
        digest: String,           // 层摘要（如 sha256:abc...）
        total: Option<u64>,       // 总字节数
        completed: Option<u64>,   // 已完成字节数
    },
    Success,                       // 拉取完成
    Error(String),                 // 错误消息
}
```

#### `CliProgressReporter`

```rust
pub struct CliProgressReporter {
    printed_header: bool,         // 是否已打印头部信息
    last_line_len: usize,         // 上一行长度（用于清屏）
    last_completed_sum: u64,      // 上次完成字节数（计算速度）
    last_instant: Instant,        // 上次更新时间
    totals_by_digest: HashMap<String, (u64, u64)>, // 按 digest 跟踪进度
}
```

### 协议与 API

#### Ollama 原生 API

| 端点 | 方法 | 用途 |
|------|------|------|
| `/api/tags` | GET | 获取本地模型列表 |
| `/api/version` | GET | 获取服务器版本 |
| `/api/pull` | POST | 拉取模型（流式响应） |

#### OpenAI 兼容 API

| 端点 | 方法 | 用途 |
|------|------|------|
| `/v1/models` | GET | 健康检查（OpenAI 兼容模式） |

#### 版本兼容性

- **最低支持版本**: 0.13.4（支持 Responses API）
- **开发版本**: 0.0.0（跳过版本检查）
- **版本解析**: 支持 `v` 前缀（如 `v0.14.1`）

---

## 关键代码路径与文件引用

### 文件结构

```
codex-rs/ollama/
├── Cargo.toml           # 包配置（依赖: reqwest, semver, async-stream, bytes, futures）
├── BUILD.bazel          # Bazel 构建配置
└── src/
    ├── lib.rs           # 库入口，导出公共 API
    ├── client.rs        # OllamaClient 实现（~411 行）
    ├── pull.rs          # 进度报告 trait 和实现（~147 行）
    ├── parser.rs        # JSON 事件解析（~75 行）
    └── url.rs           # URL 处理工具（~39 行）
```

### 关键代码路径

1. **服务器连接验证**
   - `client.rs:31-46` - `try_from_oss_provider()`
   - `client.rs:56-75` - `try_from_provider()`
   - `client.rs:78-98` - `probe_server()`

2. **模型查询**
   - `client.rs:101-124` - `fetch_models()`
   - `client.rs:127-150` - `fetch_version()`

3. **模型拉取**
   - `client.rs:154-209` - `pull_model_stream()`
   - `client.rs:212-243` - `pull_with_reporter()`
   - `parser.rs:6-29` - `pull_events_from_value()`

4. **进度报告**
   - `pull.rs:6-21` - `PullEvent` 定义
   - `pull.rs:25-27` - `PullProgressReporter` trait
   - `pull.rs:30-136` - `CliProgressReporter` 实现
   - `pull.rs:140-147` - `TuiProgressReporter` 实现

5. **URL 处理**
   - `url.rs:2-4` - `is_openai_compatible_base_url()`
   - `url.rs:7-18` - `base_url_to_host_root()`

6. **高层 API**
   - `lib.rs:22-49` - `ensure_oss_ready()`
   - `lib.rs:62-76` - `ensure_responses_supported()`
   - `lib.rs:51-57` - 版本检查辅助函数

---

## 依赖与外部交互

### 内部依赖

| 依赖 | 用途 |
|------|------|
| `codex-core` | `ModelProviderInfo`, `Config`, `OLLAMA_OSS_PROVIDER_ID` |
| `codex-utils-oss` | 调用 `ensure_oss_ready()` 和 `DEFAULT_OSS_MODEL` |

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `reqwest` | HTTP 客户端，支持 JSON 和流式响应 |
| `semver` | 语义版本解析和比较 |
| `async-stream` | 异步流生成器（`stream!` 宏）|
| `bytes` | 字节缓冲区管理（`BytesMut`）|
| `futures` | 流处理工具（`StreamExt`, `BoxStream`）|
| `serde_json` | JSON 解析 |
| `tokio` | 异步运行时 |
| `tracing` | 日志记录 |
| `wiremock` | 测试中的 HTTP mock |

### 调用方

| 调用方 | 调用方式 | 用途 |
|--------|----------|------|
| `codex-utils-oss` | `ensure_oss_ready()`, `DEFAULT_OSS_MODEL` | OSS 提供者统一接口 |
| `codex-tui` | `--oss` 标志处理 | TUI 模式下使用本地模型 |
| `codex-exec` | `--oss` 标志处理 | Exec 模式下使用本地模型 |

### 配置集成

通过 `Config::model_providers` 获取 Ollama 提供者配置：

```rust
let provider = config.model_providers.get(OLLAMA_OSS_PROVIDER_ID)?;
```

支持的环境变量：
- `CODEX_OSS_PORT` - 覆盖默认端口（11434）
- `CODEX_OSS_BASE_URL` - 覆盖完整基础 URL

---

## 风险、边界与改进建议

### 已知风险

1. **版本兼容性**
   - Ollama < 0.13.4 不支持 Responses API，会返回明确的错误消息
   - 开发版本（0.0.0）跳过版本检查，可能导致运行时错误

2. **网络超时**
   - 连接超时硬编码为 5 秒，在慢速网络环境下可能不足
   - 拉取大模型时无整体超时控制，可能无限期挂起

3. **错误处理**
   - `fetch_models()` 失败时仅记录警告，不阻止后续操作
   - Ollama 可能在 HTTP 200 响应中返回错误，需要通过流解析检测

4. **并发安全**
   - `CliProgressReporter` 使用 `std::io::stderr()`，在多线程环境下输出可能交错

### 边界情况

1. **模型名称匹配**
   - 使用简单字符串比较，不支持通配符或版本标签匹配
   - 模型标签（如 `:latest`）必须完全匹配

2. **进度计算**
   - 依赖 Ollama 返回的 `total` 和 `completed` 字段，某些层可能缺少这些信息
   - 多 digest 进度聚合使用 `HashMap`，内存占用随层数线性增长

3. **URL 处理**
   - 仅支持 `/v1` 后缀检测，其他 OpenAI 兼容路径可能无法识别
   - 尾部斜杠处理依赖 `trim_end_matches('/')`，可能不适用于所有 URL 格式

### 改进建议

1. **可配置超时**
   ```rust
   // 建议：从配置读取超时值
   pub async fn try_from_provider_with_timeout(
       provider: &ModelProviderInfo,
       timeout: Duration,
   ) -> io::Result<Self>
   ```

2. **更健壮的版本检查**
   - 添加 Responses API 功能探测（尝试调用测试端点）
   - 提供自动升级提示

3. **进度报告增强**
   - 添加 ETA 估计
   - 支持暂停/恢复拉取
   - TUI 专用进度组件（当前委托给 CLI 实现）

4. **错误分类**
   - 区分网络错误、磁盘空间不足、模型不存在等具体错误类型
   - 提供针对性的用户指导

5. **并发拉取优化**
   - 支持多 digest 并行下载（如果 Ollama 支持）
   - 添加下载速度限制选项

6. **测试覆盖**
   - 当前测试依赖 `wiremock`，建议添加：
     - 集成测试（使用真实 Ollama 实例，可选）
     - 错误场景测试（网络中断、磁盘满等）
     - 大模型拉取的压力测试

---

## 测试

### 单元测试

位于各文件的 `#[cfg(test)]` 模块：

- `lib.rs:78-97` - 版本检查逻辑测试
- `client.rs:260-411` - HTTP 客户端测试（使用 wiremock）
- `parser.rs:31-75` - JSON 解析测试
- `url.rs:20-39` - URL 转换测试

### 测试注意事项

- 所有网络测试检查 `CODEX_SANDBOX_NETWORK_DISABLED` 环境变量
- 使用 `wiremock::MockServer` 模拟 Ollama API 响应
- 测试覆盖正常路径和错误路径（服务器不可达）

---

## 总结

`codex-rs/ollama/src` 是一个设计简洁、职责明确的模块，成功将 Ollama 本地模型提供者集成到 Codex CLI 中。其核心设计亮点包括：

1. **清晰的抽象分层** - 底层 HTTP 客户端、中层流处理、高层便利 API
2. **灵活的进度报告** - trait 抽象支持 CLI 和 TUI 不同渲染需求
3. **协议兼容性** - 同时支持 Ollama 原生 API 和 OpenAI 兼容端点
4. **健壮的错误处理** - 区分致命错误和非致命警告，提供有用的错误消息

该模块是 Codex 支持本地 AI 模型的关键基础设施，代码质量高，测试覆盖良好，但仍有提升空间（特别是可配置性和 TUI 体验方面）。
