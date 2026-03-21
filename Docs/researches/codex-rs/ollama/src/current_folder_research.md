# DIR codex-rs/ollama/src 深度研究文档

## 1. 场景与职责

`codex-rs/ollama/src` 是 Codex CLI 的 **Ollama 本地开源模型提供者集成模块**。该模块负责与本地运行的 Ollama 服务器进行交互，使用户能够在不依赖 OpenAI 云端 API 的情况下，使用本地部署的开源大语言模型（如 gpt-oss:20b）。

### 1.1 核心职责

| 职责 | 说明 |
|------|------|
| **服务器发现与连接** | 检测本地 Ollama 服务器是否运行（默认端口 11434） |
| **模型管理** | 查询本地可用模型列表，按需拉取新模型 |
| **版本兼容性检查** | 验证 Ollama 版本是否支持 Responses API（≥0.13.4） |
| **下载进度报告** | 提供 CLI 和 TUI 两种进度展示方式 |
| **OpenAI 兼容层检测** | 自动识别 OpenAI 兼容端点（/v1）与原生 Ollama API |

### 1.2 在架构中的位置

```
┌─────────────────────────────────────────────────────────────┐
│                      Codex CLI (tui/exec)                    │
├─────────────────────────────────────────────────────────────┤
│                  codex_utils_oss (OSS工具集)                  │
│         ┌─────────────────┬─────────────────┐               │
│         │   codex_lmstudio │  codex_ollama   │  ← 本模块     │
│         │   (LM Studio)    │   (Ollama)      │               │
│         └─────────────────┴─────────────────┘               │
├─────────────────────────────────────────────────────────────┤
│              codex_core::model_provider_info                 │
│                   (提供者配置与抽象层)                        │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 主要功能模块

| 功能模块 | 源文件 | 目的 |
|---------|--------|------|
| `OllamaClient` | `client.rs` | HTTP 客户端封装，处理与 Ollama 服务器的所有通信 |
| `PullEvent` / `PullProgressReporter` | `pull.rs` | 模型拉取事件定义与进度报告 trait 实现 |
| `pull_events_from_value` | `parser.rs` | 解析 Ollama 流式响应中的 JSON 事件 |
| URL 处理 | `url.rs` | 处理 OpenAI 兼容端点与原生 Ollama API 的 URL 转换 |
| 环境准备 | `lib.rs` | 高阶 API：`ensure_oss_ready()` 和 `ensure_responses_supported()` |

### 2.2 默认模型配置

```rust
pub const DEFAULT_OSS_MODEL: &str = "gpt-oss:20b";
```

当用户使用 `--oss` 参数但未指定模型时，默认使用 `gpt-oss:20b` 模型。

### 2.3 版本兼容性矩阵

| Ollama 版本 | 支持状态 | 说明 |
|------------|---------|------|
| 0.0.0 (开发版) | ✅ 支持 | 开发版本特殊处理 |
| < 0.13.4 | ❌ 不支持 | 报错提示升级 |
| ≥ 0.13.4 | ✅ 支持 | 正式支持 Responses API |

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 OllamaClient

```rust
pub struct OllamaClient {
    client: reqwest::Client,      // HTTP 客户端
    host_root: String,            // 服务器根地址（如 http://localhost:11434）
    uses_openai_compat: bool,     // 是否使用 OpenAI 兼容模式
}
```

#### 3.1.2 PullEvent（模型拉取事件）

```rust
pub enum PullEvent {
    Status(String),               // 状态消息（如 "verifying", "writing"）
    ChunkProgress {               // 分块进度
        digest: String,           // 层摘要（如 sha256:abc...）
        total: Option<u64>,       // 总字节数
        completed: Option<u64>,   // 已完成字节数
    },
    Success,                      // 拉取成功
    Error(String),                // 错误消息
}
```

#### 3.1.3 PullProgressReporter Trait

```rust
pub trait PullProgressReporter {
    fn on_event(&mut self, event: &PullEvent) -> io::Result<()>;
}
```

实现者：
- `CliProgressReporter`：命令行进度条（stderr 输出）
- `TuiProgressReporter`：TUI 模式进度报告（目前委托给 CLI 实现）

### 3.2 关键流程

#### 3.2.1 客户端创建流程

```
try_from_oss_provider(config)
    ↓
从 config.model_providers 获取 "ollama" 提供者配置
    ↓
try_from_provider(provider)
    ↓
解析 base_url → 检测 OpenAI 兼容模式 → 提取 host_root
    ↓
构建 reqwest::Client（5秒连接超时）
    ↓
probe_server() 健康检查
    ↓
返回 OllamaClient 或返回连接错误
```

**关键代码路径**：`client.rs:31-75`

#### 3.2.2 服务器探测逻辑

```rust
async fn probe_server(&self) -> io::Result<()> {
    let url = if self.uses_openai_compat {
        format!("{}/v1/models", self.host_root)  // OpenAI 兼容端点
    } else {
        format!("{}/api/tags", self.host_root)   // Ollama 原生端点
    };
    // 发送 GET 请求，失败返回 OLLAMA_CONNECTION_ERROR
}
```

**连接错误提示**：
```
No running Ollama server detected. Start it with: `ollama serve` (after installing).
Install instructions: https://github.com/ollama/ollama?tab=readme-ov-file#ollama
```

#### 3.2.3 模型拉取流程

```
pull_with_reporter(model, reporter)
    ↓
pull_model_stream(model) → 返回 BoxStream<'static, PullEvent>
    ↓
POST /api/pull {"model": "...", "stream": true}
    ↓
异步流解析（async_stream）
    ↓
逐行读取 NDJSON → parser::pull_events_from_value()
    ↓
Yield PullEvent 到调用方
    ↓
reporter.on_event() 更新进度显示
```

**流式解析关键代码**（`client.rs:178-208`）：
- 使用 `async_stream::stream!` 宏创建异步流
- 使用 `BytesMut` 缓冲区处理分块数据
- 按 `\n` 分割行，解析每行的 JSON

#### 3.2.4 版本检查流程

```rust
pub async fn ensure_responses_supported(provider: &ModelProviderInfo) -> io::Result<()> {
    let client = OllamaClient::try_from_provider(provider).await?;
    let Some(version) = client.fetch_version().await? else {
        return Ok(());  // 无法获取版本时放行
    };
    
    if supports_responses(&version) {
        return Ok(());
    }
    
    Err(io::Error::other(format!(
        "Ollama {version} is too old. Codex requires Ollama {min} or newer."
    )))
}
```

### 3.3 协议与 API 端点

| 端点 | 方法 | 用途 |
|------|------|------|
| `/api/tags` | GET | 获取本地模型列表 |
| `/api/version` | GET | 获取服务器版本 |
| `/api/pull` | POST | 拉取模型（流式） |
| `/v1/models` | GET | OpenAI 兼容模式健康检查 |

### 3.4 URL 处理逻辑

```rust
// url.rs
pub(crate) fn is_openai_compatible_base_url(base_url: &str) -> bool {
    base_url.trim_end_matches('/').ends_with("/v1")
}

pub fn base_url_to_host_root(base_url: &str) -> String {
    let trimmed = base_url.trim_end_matches('/');
    if trimmed.ends_with("/v1") {
        trimmed.trim_end_matches("/v1").trim_end_matches('/').to_string()
    } else {
        trimmed.to_string()
    }
}
```

**示例**：
- `http://localhost:11434/v1` → `http://localhost:11434`（OpenAI 兼容模式）
- `http://localhost:11434` → `http://localhost:11434`（原生模式）

---

## 4. 关键代码路径与文件引用

### 4.1 源文件清单

| 文件 | 行数 | 职责 |
|------|------|------|
| `lib.rs` | 97 | 模块导出、高阶 API、版本检查 |
| `client.rs` | 411 | OllamaClient 实现、HTTP 通信、流式解析 |
| `pull.rs` | 147 | 拉取事件定义、进度报告器实现 |
| `parser.rs` | 75 | JSON 事件解析器 |
| `url.rs` | 39 | URL 处理工具函数 |

### 4.2 关键函数引用

| 函数 | 位置 | 用途 |
|------|------|------|
| `ensure_oss_ready` | `lib.rs:22` | 主入口：准备 OSS 环境 |
| `ensure_responses_supported` | `lib.rs:62` | 版本兼容性检查 |
| `OllamaClient::try_from_oss_provider` | `client.rs:31` | 从配置创建客户端 |
| `OllamaClient::fetch_models` | `client.rs:101` | 获取模型列表 |
| `OllamaClient::fetch_version` | `client.rs:127` | 获取版本信息 |
| `OllamaClient::pull_model_stream` | `client.rs:154` | 流式拉取模型 |
| `OllamaClient::pull_with_reporter` | `client.rs:212` | 带进度报告的拉取 |
| `pull_events_from_value` | `parser.rs:6` | 解析 JSON 事件 |

### 4.3 测试覆盖

| 测试 | 位置 | 说明 |
|------|------|------|
| `supports_responses_for_dev_zero` | `lib.rs:83` | 开发版本支持检查 |
| `does_not_support_responses_before_cutoff` | `lib.rs:88` | 旧版本拒绝检查 |
| `supports_responses_at_or_after_cutoff` | `lib.rs:93` | 新版本支持检查 |
| `test_fetch_models_happy_path` | `client.rs:267` | 模型获取测试 |
| `test_fetch_version` | `client.rs:297` | 版本获取测试 |
| `test_probe_server_happy_path_openai_compat_and_native` | `client.rs:334` | 服务器探测测试 |
| `test_try_from_oss_provider_ok_when_server_running` | `client.rs:371` | 客户端创建成功测试 |
| `test_try_from_oss_provider_err_when_server_missing` | `client.rs:394` | 客户端创建失败测试 |
| `test_pull_events_decoder_status_and_success` | `parser.rs:38` | 事件解析测试 |
| `test_pull_events_decoder_progress` | `parser.rs:50` | 进度解析测试 |
| `test_base_url_to_host_root` | `url.rs:25` | URL 转换测试 |

---

## 5. 依赖与外部交互

### 5.1 Cargo 依赖

```toml
[dependencies]
async-stream = { workspace = true }      # 异步流生成
bytes = { workspace = true }             # 字节缓冲区
codex-core = { workspace = true }        # 核心类型（Config, ModelProviderInfo）
futures = { workspace = true }           # 异步 trait
reqwest = { workspace = true, features = ["json", "stream"] }  # HTTP 客户端
semver = { workspace = true }            # 语义版本解析
serde_json = { workspace = true }        # JSON 解析
tokio = { workspace = true, ... }        # 异步运行时
tracing = { workspace = true }           # 日志追踪
wiremock = { workspace = true }          # HTTP 测试模拟
```

### 5.2 上游调用方

| 调用方 | 调用点 | 用途 |
|--------|--------|------|
| `codex_utils_oss` | `utils/oss/src/lib.rs:28-31` | `ensure_oss_provider_ready()` 委托 |
| `codex_exec` | `exec/src/lib.rs:517` | 启动时检查 OSS 准备状态 |
| `codex_tui` | `tui/src/oss_selection.rs` | OSS 提供者选择 UI |

### 5.3 下游依赖

| 依赖 | 用途 |
|------|------|
| `codex_core::OLLAMA_OSS_PROVIDER_ID` | 提供者标识符常量（"ollama"） |
| `codex_core::ModelProviderInfo` | 提供者配置结构体 |
| `codex_core::Config` | 应用配置 |
| `codex_core::create_oss_provider_with_base_url` | 测试用提供者构造 |

### 5.4 环境变量

| 变量 | 用途 | 定义位置 |
|------|------|---------|
| `CODEX_OSS_PORT` | 覆盖默认端口（11434） | `core/src/model_provider_info.rs:320` |
| `CODEX_OSS_BASE_URL` | 覆盖完整 base URL | `core/src/model_provider_info.rs:327` |
| `CODEX_SANDBOX_NETWORK_DISABLED` | 测试时禁用网络 | 测试跳过检查 |

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 严重程度 | 说明 |
|------|---------|------|
| **错误处理盲区** | 中 | `fetch_models` 失败时返回空列表而非错误（`client.rs:110`），可能掩盖连接问题 |
| **版本检查宽松** | 低 | `ensure_responses_supported` 在无法获取版本时放行（`lib.rs:65`），可能导致运行时错误 |
| **硬编码超时** | 低 | 连接超时固定为 5 秒（`client.rs:65`），在慢网络环境可能不足 |
| **TUI 进度报告简化** | 低 | `TuiProgressReporter` 直接委托给 `CliProgressReporter`，未实现真正的 TUI 集成 |

### 6.2 边界条件

| 场景 | 行为 |
|------|------|
| Ollama 服务器未运行 | 返回友好错误消息，提示启动命令 |
| 模型已存在 | `ensure_oss_ready` 跳过拉取，直接返回 |
| 拉取过程中断 | 流结束但无 Success 事件，返回错误 |
| Ollama 返回 200 但包含错误 | 检查流中的 `error` 字段（`client.rs:190-193`） |
| 空 base_url | 通过 `expect` 触发 panic（仅配置错误时发生） |

### 6.3 改进建议

#### 6.3.1 短期改进

1. **增强错误上下文**
   ```rust
   // 当前：直接返回空列表
   if !resp.status().is_success() {
       return Ok(Vec::new());
   }
   // 建议：记录警告或返回具体错误
   ```

2. **可配置超时**
   ```rust
   // 从 Config 读取超时设置
   .connect_timeout(config.ollama_connect_timeout)
   ```

3. **TUI 原生进度报告**
   - 实现真正的 TUI 进度条，而非委托给 CLI 实现
   - 支持 ratatui 的 `Gauge` 组件

#### 6.3.2 中期改进

1. **模型缓存管理**
   - 添加 `list_local_models()` 缓存机制
   - 支持模型版本检查和更新提示

2. **并发拉取优化**
   - 当前单线程流式处理，可考虑并发下载多个层

3. **健康检查增强**
   - 支持重试机制
   - 检测服务器启动中状态（优雅等待）

#### 6.3.3 长期改进

1. **统一 OSS 提供者抽象**
   - 当前 `codex_lmstudio` 和 `codex_ollama` 有重复代码
   - 考虑提取 `codex_oss_provider` trait

2. **异步模型预热**
   - 启动时后台预拉取常用模型
   - 配置化预热策略

---

## 7. 附录

### 7.1 代码统计

```
Language: Rust
Files: 5
Total Lines: 769
- lib.rs: 97
- client.rs: 411
- pull.rs: 147
- parser.rs: 75
- url.rs: 39
```

### 7.2 相关文档

- [Ollama API 文档](https://github.com/ollama/ollama/blob/main/docs/api.md)
- [OpenAI API 兼容说明](https://github.com/ollama/ollama/blob/main/docs/openai.md)
- Codex 配置文档：`docs/` 目录下的 provider 配置说明

### 7.3 调试技巧

```bash
# 测试 Ollama 连接
curl http://localhost:11434/api/tags

# 测试模型拉取（流式）
curl -X POST http://localhost:11434/api/pull \
  -d '{"model": "gpt-oss:20b", "stream": true}'

# 检查版本
curl http://localhost:11434/api/version
```

---

*文档生成时间：2026-03-21*
*研究范围：codex-rs/ollama/src/*
