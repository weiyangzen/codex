# codex-rs/ollama/src/client.rs 研究文档

## 场景与职责

`client.rs` 是 `codex-ollama` crate 的核心模块，负责与本地 Ollama 服务器进行 HTTP 通信。它是 Codex CLI 与 Ollama 开源模型提供者之间的桥梁，主要职责包括：

1. **服务器探测与连接管理**：验证本地 Ollama 服务器是否可达
2. **模型管理**：获取可用模型列表、查询服务器版本
3. **模型拉取**：支持从 Ollama 仓库拉取模型，并提供流式进度报告
4. **协议兼容性**：同时支持 Ollama 原生 API 和 OpenAI 兼容 API

该模块在 Codex 的 OSS（开源软件）模式下被调用，当用户通过 `--oss` 或 `--local-provider=ollama` 选择使用本地 Ollama 服务器时启用。

## 功能点目的

### 1. OllamaClient 结构体

```rust
pub struct OllamaClient {
    client: reqwest::Client,
    host_root: String,
    uses_openai_compat: bool,
}
```

- `client`: HTTP 客户端，配置了 5 秒连接超时
- `host_root`: Ollama 服务器根地址（如 `http://localhost:11434`）
- `uses_openai_compat`: 标记是否使用 OpenAI 兼容模式（URL 以 `/v1` 结尾）

### 2. 构造函数

| 方法 | 用途 |
|------|------|
| `try_from_oss_provider` | 从 Config 构建客户端，使用内置 OSS 提供者配置 |
| `try_from_provider` | 从 ModelProviderInfo 构建客户端，验证服务器可达性 |
| `from_host_root` | 测试用的低级构造函数，直接指定 host_root |

### 3. 核心 API 方法

| 方法 | HTTP 端点 | 功能 |
|------|-----------|------|
| `probe_server` | `GET /api/tags` 或 `GET /v1/models` | 探测服务器是否运行 |
| `fetch_models` | `GET /api/tags` | 获取本地模型列表 |
| `fetch_version` | `GET /api/version` | 获取服务器版本号 |
| `pull_model_stream` | `POST /api/pull` | 拉取模型，返回事件流 |
| `pull_with_reporter` | - | 高级封装，驱动进度报告器 |

## 具体技术实现

### 服务器探测逻辑

```rust
async fn probe_server(&self) -> io::Result<()> {
    let url = if self.uses_openai_compat {
        format!("{}/v1/models", self.host_root.trim_end_matches('/'))
    } else {
        format!("{}/api/tags", self.host_root.trim_end_matches('/'))
    };
    // ... 发送请求并检查响应
}
```

探测逻辑根据 `uses_openai_compat` 自动选择端点：
- OpenAI 兼容模式：`/v1/models`
- 原生 Ollama 模式：`/api/tags`

### 流式拉取实现

`pull_model_stream` 使用 `async-stream` crate 实现异步流：

1. **请求构造**：发送 `POST /api/pull`，body 为 `{"model": "...", "stream": true}`
2. **流处理**：使用 `bytes_stream()` 获取字节流，逐块读取
3. **行解析**：按 `\n` 分割，解析每行为 JSON
4. **事件生成**：通过 `parser::pull_events_from_value` 将 JSON 转换为 `PullEvent`
5. **终止条件**：遇到 `status: "success"` 或 `error` 字段时结束流

```rust
let s = async_stream::stream! {
    while let Some(chunk) = stream.next().await {
        // 处理字节块，解析 JSON 行
        // yield 生成 PullEvent
    }
};
```

### 错误处理策略

- **连接错误**：返回预定义的错误消息 `OLLAMA_CONNECTION_ERROR`，提示用户启动 `ollama serve`
- **HTTP 错误**：原生 API 返回空列表（`fetch_models`），版本查询返回 `None`
- **流错误**：`pull_model_stream` 中遇到错误事件会 yield `PullEvent::Error`，由 `pull_with_reporter` 转换为 `io::Error`

**重要边界情况**：Ollama 在拉取失败时仍返回 HTTP 200，错误信息在响应流中。代码通过检查流中的 `error` 字段来检测失败。

## 关键代码路径与文件引用

### 模块依赖图

```
client.rs
    ├── parser.rs (pull_events_from_value)
    ├── pull.rs (PullEvent, PullProgressReporter)
    ├── url.rs (base_url_to_host_root, is_openai_compatible_base_url)
    └── codex_core::model_provider_info (OLLAMA_OSS_PROVIDER_ID, ModelProviderInfo)
```

### 调用方

| 调用方 | 调用方法 | 场景 |
|--------|----------|------|
| `lib.rs::ensure_oss_ready` | `try_from_oss_provider`, `fetch_models`, `pull_with_reporter` | 准备 OSS 环境 |
| `lib.rs::ensure_responses_supported` | `try_from_provider`, `fetch_version` | 检查版本兼容性 |
| `tui/src/oss_selection.rs` | 通过 `utils/oss` 间接使用 | TUI 模式选择 OSS 提供者 |
| `exec/src/lib.rs` | 通过 `utils/oss` 间接使用 | CLI 执行模式 |

### 测试覆盖

测试模块位于文件底部（行 260-411），使用 `wiremock` 模拟 HTTP 服务器：

1. `test_fetch_models_happy_path`：验证模型列表获取
2. `test_fetch_version`：验证版本解析（支持 `v` 前缀，如 `v0.14.1`）
3. `test_probe_server_happy_path_openai_compat_and_native`：验证两种探测模式
4. `test_try_from_oss_provider_ok_when_server_running`：验证成功连接场景
5. `test_try_from_oss_provider_err_when_server_missing`：验证失败连接场景

所有测试都检查 `CODEX_SANDBOX_NETWORK_DISABLED_ENV_VAR` 环境变量，在沙箱网络禁用时跳过。

## 依赖与外部交互

### 外部 crate 依赖

| crate | 用途 |
|-------|------|
| `reqwest` | HTTP 客户端，支持 JSON 和流 |
| `serde_json` | JSON 解析 |
| `bytes::BytesMut` | 字节缓冲区管理 |
| `futures` | 异步流处理 |
| `async-stream` | 生成异步流 |
| `semver::Version` | 语义化版本解析 |
| `wiremock` | 测试中的 HTTP mock |

### Ollama API 端点

| 端点 | 方法 | 用途 |
|------|------|------|
| `/api/tags` | GET | 列出本地模型 |
| `/api/version` | GET | 获取服务器版本 |
| `/api/pull` | POST | 拉取模型（流式）|
| `/v1/models` | GET | OpenAI 兼容模式下的模型列表 |

### 配置集成

通过 `codex_core::config::Config` 获取提供者配置：

```rust
let provider = config.model_providers.get(OLLAMA_OSS_PROVIDER_ID)
```

支持通过 `CODEX_OSS_PORT` 和 `CODEX_OSS_BASE_URL` 环境变量自定义服务器地址（在 `model_provider_info.rs` 中处理）。

## 风险、边界与改进建议

### 已知风险

1. **版本兼容性**：`ensure_responses_supported` 要求 Ollama >= 0.13.4 以支持 Responses API。旧版本会导致错误提示。

2. **网络超时**：连接超时固定为 5 秒，在慢速网络或高负载环境下可能不够。

3. **错误检测延迟**：Ollama 的 pull 错误在 HTTP 200 响应流中返回，必须读取流才能发现错误。

4. **内存缓冲**：`BytesMut` 缓冲区在极端情况下可能无限增长（如果服务器发送无换行符的数据）。

### 边界情况

| 场景 | 行为 |
|------|------|
| 服务器未运行 | 返回 `OLLAMA_CONNECTION_ERROR` 错误 |
| 版本端点不可用 | `fetch_version` 返回 `Ok(None)`，不报错 |
| 模型列表获取失败 | `fetch_models` 返回空向量 |
| 拉取流意外结束 | `pull_with_reporter` 返回 `io::Error` |
| OpenAI 兼容 URL | 自动检测 `/v1` 后缀，调整探测端点 |

### 改进建议

1. **可配置超时**：将连接超时和流超时暴露为配置选项，而非硬编码 5 秒。

2. **重试机制**：为 `probe_server` 和 `fetch_models` 添加指数退避重试，提高鲁棒性。

3. **缓冲区上限**：为 `BytesMut` 设置最大大小，防止恶意服务器导致内存耗尽。

4. **更详细的错误分类**：当前所有连接错误都映射到同一错误消息，可区分连接拒绝、超时、DNS 失败等情况。

5. **取消支持**：`pull_model_stream` 目前无法从外部取消，可考虑接受 `CancellationToken`。

6. **指标收集**：添加拉取速度、成功率等指标，用于诊断和优化。

### 与 LM Studio 对比

| 特性 | Ollama | LM Studio |
|------|--------|-----------|
| 模型拉取 | 通过 `api/pull` 流式拉取 | 通过专用 API 下载 |
| 版本检查 | 显式版本检查（>= 0.13.4）| 无显式版本检查 |
| 进度报告 | `CliProgressReporter` 和 `TuiProgressReporter` | 类似机制 |
| 默认模型 | `gpt-oss:20b` | `openai/gpt-oss-20b` |

Ollama 的实现更复杂，需要处理版本兼容性和 OpenAI 兼容模式，而 LM Studio 的集成相对简单。
