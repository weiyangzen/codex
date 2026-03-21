# codex-rs/ollama 研究文档

## 场景与职责

`codex-ollama` crate 是 Codex CLI 的 Ollama 本地开源模型（OSS）集成模块。它负责：

1. **本地 Ollama 服务器发现与连接**：检测并连接运行在本地（默认端口 11434）的 Ollama 服务
2. **模型管理**：查询本地可用模型列表，按需拉取（pull）缺失的模型
3. **版本兼容性检查**：验证 Ollama 服务器版本是否支持 Responses API（最低版本 0.13.4）
4. **进度报告**：在 CLI 和 TUI 模式下提供模型下载进度反馈

该模块是 Codex "--oss" 模式的核心组件，允许用户在不使用 OpenAI 云服务的情况下，通过本地 Ollama 实例运行开源模型（默认使用 `gpt-oss:20b`）。

## 功能点目的

### 1. 环境准备 (`ensure_oss_ready`)
- **目的**：在用户选择 `--oss` 模式时，确保本地环境就绪
- **流程**：
  1. 确定目标模型（用户指定或默认 `gpt-oss:20b`）
  2. 创建 `OllamaClient` 并验证服务器可达性
  3. 查询本地模型列表，如缺失则自动拉取

### 2. 版本兼容性检查 (`ensure_responses_supported`)
- **目的**：确保 Ollama 版本支持 Responses API
- **最小版本**：0.13.4
- **特殊处理**：开发版本（0.0.0）被视为支持

### 3. 模型拉取与进度报告
- **目的**：从 Ollama 仓库下载模型，提供实时进度反馈
- **支持模式**：
  - CLI 模式：内联进度条，显示下载速度、已完成/总量（GB）、百分比
  - TUI 模式：当前委托给 CLI 实现（未来可能实现专用 TUI 渲染）

### 4. OpenAI 兼容模式支持
- **目的**：支持 Ollama 的 OpenAI 兼容端点（`/v1/*`）
- **检测逻辑**：通过 `base_url` 是否以 `/v1` 结尾判断
- **健康检查端点**：
  - 原生模式：`/api/tags`
  - 兼容模式：`/v1/models`

## 具体技术实现

### 关键数据结构

#### `OllamaClient` (`src/client.rs`)
```rust
pub struct OllamaClient {
    client: reqwest::Client,      // HTTP 客户端，5秒连接超时
    host_root: String,            // Ollama 服务器根地址（去除 /v1 后缀）
    uses_openai_compat: bool,     // 是否使用 OpenAI 兼容模式
}
```

#### `PullEvent` (`src/pull.rs`)
拉取过程中的事件枚举：
- `Status(String)`：状态消息（如 "verifying", "writing"）
- `ChunkProgress { digest, total, completed }`：分片级进度更新
- `Success`：拉取完成
- `Error(String)`：错误信息

#### `PullProgressReporter` trait (`src/pull.rs`)
```rust
pub trait PullProgressReporter {
    fn on_event(&mut self, event: &PullEvent) -> io::Result<()>;
}
```
实现者：
- `CliProgressReporter`：向 stderr 输出内联进度
- `TuiProgressReporter`：当前委托给 CLI 实现

### 关键流程

#### 1. 客户端创建流程 (`try_from_oss_provider`)
```
Config -> 查找 OLLAMA_OSS_PROVIDER_ID -> ModelProviderInfo 
  -> 提取 base_url -> 检测 OpenAI 兼容模式 
  -> 构建 host_root -> 创建 reqwest Client 
  -> probe_server() 验证可达性
```

#### 2. 服务器探测 (`probe_server`)
- 根据 `uses_openai_compat` 选择端点：
  - `true`：`{host_root}/v1/models`
  - `false`：`{host_root}/api/tags`
- 失败时返回友好错误消息，提示用户运行 `ollama serve`

#### 3. 模型拉取流 (`pull_model_stream`)
- 发送 POST 请求到 `/api/pull`，请求体 `{"model": "...", "stream": true}`
- 使用 `async_stream` 创建异步流
- 字节流解析：按换行符分割 JSON 行，转换为 `PullEvent`
- 终止条件：收到 `status: "success"` 或 `error` 字段

#### 4. JSON 事件解析 (`pull_events_from_value`)
解析 Ollama 拉取 API 返回的 JSON：
- `status` 字段 → `PullEvent::Status`
- `digest` + `total`/`completed` → `PullEvent::ChunkProgress`
- `status == "success"` → 额外生成 `PullEvent::Success`

### URL 处理 (`src/url.rs`)

#### `is_openai_compatible_base_url`
检测 base_url 是否以 `/v1` 结尾。

#### `base_url_to_host_root`
将 OpenAI 兼容 URL 转换为原生 Ollama host root：
- `http://localhost:11434/v1` → `http://localhost:11434`
- `http://localhost:11434/` → `http://localhost:11434`

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 | 关键导出 |
|------|------|----------|
| `src/lib.rs` | 模块入口，环境准备，版本检查 | `ensure_oss_ready`, `ensure_responses_supported`, `DEFAULT_OSS_MODEL` |
| `src/client.rs` | HTTP 客户端，API 调用 | `OllamaClient`, `fetch_models`, `fetch_version`, `pull_model_stream` |
| `src/pull.rs` | 进度事件定义与报告 | `PullEvent`, `PullProgressReporter`, `CliProgressReporter`, `TuiProgressReporter` |
| `src/parser.rs` | JSON 事件解析 | `pull_events_from_value` |
| `src/url.rs` | URL 处理工具 | `base_url_to_host_root` |

### 调用链

```
# CLI/TUI 入口
codex-rs/exec/src/lib.rs:517
  -> codex_utils_oss::ensure_oss_provider_ready()
     
codex-rs/utils/oss/src/lib.rs:27-31
  -> codex_ollama::ensure_responses_supported()  // 版本检查
  -> codex_ollama::ensure_oss_ready()            // 环境准备
     
codex-rs/ollama/src/lib.rs:22-49
  -> OllamaClient::try_from_oss_provider()
     -> fetch_models() -> 如缺失则 pull_with_reporter()
```

### 配置集成

Ollama 提供商配置来自 `codex_core::model_provider_info`：

```rust
pub const OLLAMA_OSS_PROVIDER_ID: &str = "ollama";
pub const DEFAULT_OLLAMA_PORT: u16 = 11434;

// 内置默认配置
create_oss_provider(DEFAULT_OLLAMA_PORT, WireApi::Responses)
  -> base_url: "http://localhost:11434/v1"
  -> name: "gpt-oss"
  -> requires_openai_auth: false
```

环境变量覆盖（实验性）：
- `CODEX_OSS_PORT`：覆盖默认端口
- `CODEX_OSS_BASE_URL`：覆盖整个 base URL

## 依赖与外部交互

### 内部依赖

| Crate | 用途 |
|-------|------|
| `codex-core` | `ModelProviderInfo`, `Config`, `OLLAMA_OSS_PROVIDER_ID` |
| `codex-utils-oss` | 统一 OSS 提供商抽象（`ensure_oss_provider_ready`） |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `reqwest` | HTTP 客户端，支持 JSON 和流式响应 |
| `async-stream` | 异步流生成（`pull_model_stream`） |
| `futures` | 流处理工具 |
| `bytes` | 字节缓冲区管理 |
| `semver` | 版本解析与比较 |
| `serde_json` | JSON 解析 |
| `tokio` | 异步运行时 |
| `tracing` | 日志记录 |
| `wiremock` | 测试模拟（dev dependency） |

### 外部服务交互

#### Ollama API 端点

| 端点 | 方法 | 用途 |
|------|------|------|
| `/api/tags` | GET | 获取本地模型列表 |
| `/api/version` | GET | 获取服务器版本 |
| `/api/pull` | POST | 拉取模型（流式） |
| `/v1/models` | GET | OpenAI 兼容模式健康检查 |

### 与 LM Studio 的对比

| 特性 | Ollama | LM Studio |
|------|--------|-----------|
| 默认端口 | 11434 | 1234 |
| 默认模型 | `gpt-oss:20b` | `openai/gpt-oss-20b` |
| 模型拉取 | 自动（通过 Ollama API） | 自动（通过 LM Studio API） |
| 版本检查 | 是（最低 0.13.4） | 否 |
| OpenAI 兼容 | 是（自动检测） | 是 |

## 风险、边界与改进建议

### 已知风险

1. **版本兼容性**
   - Ollama < 0.13.4 不支持 Responses API，但错误信息只在版本检查时显示
   - 开发版本（0.0.0）被特殊处理为支持，可能存在误判

2. **网络超时**
   - 连接超时硬编码为 5 秒，在慢网络环境下可能不足
   - 拉取大模型时无整体超时控制，仅依赖流式连接

3. **错误处理**
   - Ollama 在拉取失败时仍返回 HTTP 200，需要通过解析流中的 `error` 字段检测
   - 部分错误仅记录 warning，不阻止后续执行（如 `fetch_models` 失败）

4. **测试限制**
   - 测试依赖 `wiremock`，在沙箱网络禁用时跳过
   - 无真实 Ollama 集成测试

### 边界情况

1. **base_url 处理**
   - 支持多种形式：`http://host:port`、`http://host:port/`、`http://host:port/v1`
   - 但 `/v1` 后缀的检测是简单的字符串匹配，可能误判

2. **进度报告**
   - 多分片下载时，进度基于各分片累计
   - 速度计算使用瞬时采样（1ms 最小间隔），可能波动较大

3. **并发**
   - `OllamaClient` 未实现 `Clone`，但内部 `reqwest::Client` 是 Arc 包装
   - 模型拉取是顺序执行，无并发控制

### 改进建议

1. **配置增强**
   - 支持 `config.toml` 中自定义 Ollama 超时设置
   - 支持自定义默认模型（当前硬编码 `gpt-oss:20b`）

2. **错误处理**
   - 添加重试机制（当前仅依赖 reqwest 内置重试）
   - 改进错误分类，区分网络错误、版本错误、模型不存在错误

3. **TUI 集成**
   - 实现专用的 `TuiProgressReporter`，集成到 ratatui 渲染循环
   - 支持取消正在进行的拉取操作

4. **测试覆盖**
   - 添加单元测试覆盖 `pull_events_from_value` 的更多边界情况
   - 添加集成测试验证与真实 Ollama 的交互（如可行）

5. **性能优化**
   - 考虑使用连接池（reqwest 默认已支持）
   - 大模型拉取时考虑分片并发下载（如 Ollama 支持）

6. **文档**
   - 添加更多内联文档说明 Ollama API 的响应格式
   - 记录版本兼容性检查的具体逻辑

---

*文档生成时间：2026-03-21*
*研究范围：codex-rs/ollama 目录及其上下游依赖*
