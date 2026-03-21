# codex-rs/lmstudio 研究文档

## 概述

`codex-lmstudio` 是 Codex CLI 的 LM Studio 本地开源模型（OSS）提供者集成 crate。它负责与本地运行的 LM Studio 服务器通信，管理模型下载、加载和状态检查，使用户能够在离线环境下使用开源大语言模型。

---

## 场景与职责

### 核心场景

1. **本地 OSS 模型支持**：当用户使用 `--oss` 标志启动 Codex 时，系统需要连接到本地运行的 AI 模型服务器，而不是 OpenAI 云端 API
2. **模型自动管理**：自动检测本地模型是否存在，如不存在则自动下载；自动加载模型到内存
3. **多提供者选择**：与 Ollama 并列作为两个主要的本地 OSS 提供者选项

### 主要职责

- **服务器连通性检查**：验证 LM Studio 服务器是否可达（默认端口 1234）
- **模型列表获取**：查询服务器上已安装的模型列表
- **模型下载**：通过 `lms` CLI 工具下载缺失的模型
- **模型加载**：通过发送空请求预热/加载模型到内存
- **错误处理与提示**：提供清晰的错误信息引导用户安装和启动 LM Studio

---

## 功能点目的

### 1. `ensure_oss_ready()` - OSS 环境准备入口

**位置**: `src/lib.rs:13`

**目的**: 在使用 OSS 模式前确保环境就绪的协调函数

**流程**:
```
1. 确定要使用的模型（用户指定 > 默认模型 openai/gpt-oss-20b）
2. 创建 LMStudioClient 并验证服务器可达
3. 获取本地模型列表，如目标模型不存在则下载
4. 后台异步加载模型到内存
```

**关键设计决策**:
- 模型加载在后台执行（`tokio::spawn`），不阻塞主流程
- 查询模型失败仅记录警告，不中断流程（让上层后续处理错误）

### 2. `LMStudioClient` - HTTP 客户端封装

**位置**: `src/client.rs:7`

**目的**: 封装与 LM Studio HTTP API 的所有交互

**核心方法**:

| 方法 | 用途 | 端点 |
|------|------|------|
| `try_from_provider()` | 从配置创建客户端并验证连通性 | 读取配置中的 base_url |
| `check_server()` | 健康检查 | `GET /models` |
| `fetch_models()` | 获取已安装模型列表 | `GET /models` |
| `load_model()` | 加载/预热模型 | `POST /responses` |
| `download_model()` | 下载模型 | 调用 `lms get --yes <model>` |

### 3. 默认模型常量

**位置**: `src/lib.rs:7`

```rust
pub const DEFAULT_OSS_MODEL: &str = "openai/gpt-oss-20b";
```

这是当用户使用 `--oss` 但未指定 `-m` 模型时使用的默认模型。

### 4. `lms` CLI 工具查找

**位置**: `src/client.rs:127-166`

**目的**: 跨平台查找 LM Studio 的 CLI 工具 `lms`

**查找顺序**:
1. 首先检查 `PATH` 中的 `lms`
2. 如未找到，使用平台特定的回退路径:
   - Unix: `~/.lmstudio/bin/lms`
   - Windows: `~/.lmstudio/bin/lms.exe`

---

## 具体技术实现

### 关键流程

#### 服务器连通性验证流程

```rust
// src/client.rs:46-62
async fn check_server(&self) -> io::Result<()> {
    let url = format!("{}/models", self.base_url.trim_end_matches('/'));
    let response = self.client.get(&url).send().await;
    
    if let Ok(resp) = response {
        if resp.status().is_success() {
            Ok(())
        } else {
            Err(io::Error::other(format!(
                "Server returned error: {} {LMSTUDIO_CONNECTION_ERROR}",
                resp.status()
            )))
        }
    } else {
        Err(io::Error::other(LMSTUDIO_CONNECTION_ERROR))
    }
}
```

**错误提示信息**:
```rust
const LMSTUDIO_CONNECTION_ERROR: &str = 
    "LM Studio is not responding. Install from https://lmstudio.ai/download and run 'lms server start'.";
```

#### 模型加载流程

LM Studio 通过发送一个空的 completion 请求来触发模型加载:

```rust
// src/client.rs:65-92
pub async fn load_model(&self, model: &str) -> io::Result<()> {
    let url = format!("{}/responses", self.base_url.trim_end_matches('/'));
    
    let request_body = serde_json::json!({
        "model": model,
        "input": "",
        "max_output_tokens": 1
    });
    
    // POST 请求...
}
```

注意这里使用的是 OpenAI-compatible 的 `/responses` 端点。

#### 模型下载流程

```rust
// src/client.rs:168-190
pub async fn download_model(&self, model: &str) -> std::io::Result<()> {
    let lms = Self::find_lms()?;
    eprintln!("Downloading model: {model}");
    
    let status = std::process::Command::new(&lms)
        .args(["get", "--yes", model])
        .stdout(std::process::Stdio::inherit())
        .stderr(std::process::Stdio::null())
        .status()?;
    // 检查退出码...
}
```

使用 `--yes` 自动确认下载，stdout 继承以显示进度，stderr 丢弃避免噪音。

### 数据结构

#### `LMStudioClient`

```rust
#[derive(Clone)]
pub struct LMStudioClient {
    client: reqwest::Client,  // HTTP 客户端
    base_url: String,         // LM Studio 服务器地址
}
```

HTTP 客户端配置了 5 秒连接超时:
```rust
let client = reqwest::Client::builder()
    .connect_timeout(std::time::Duration::from_secs(5))
    .build()
    .unwrap_or_else(|_| reqwest::Client::new());
```

### 协议与 API

LM Studio 提供 OpenAI-compatible 的 REST API:

| 端点 | 方法 | 用途 |
|------|------|------|
| `/v1/models` | GET | 列出可用模型 |
| `/v1/responses` | POST | 创建 completion（也用于模型加载） |

默认基础 URL: `http://localhost:1234/v1`

端口可通过环境变量覆盖:
- `CODEX_OSS_PORT`: 指定自定义端口
- `CODEX_OSS_BASE_URL`: 指定完整基础 URL

---

## 关键代码路径与文件引用

### 文件结构

```
codex-rs/lmstudio/
├── Cargo.toml          # crate 配置
├── BUILD.bazel         # Bazel 构建配置
└── src/
    ├── lib.rs          # 公共 API: ensure_oss_ready(), DEFAULT_OSS_MODEL
    └── client.rs       # LMStudioClient 实现 + 单元测试
```

### 关键代码路径

1. **入口函数**: `src/lib.rs::ensure_oss_ready()`
   - 被 `codex-utils-oss::ensure_oss_provider_ready()` 调用

2. **客户端创建**: `src/client.rs::LMStudioClient::try_from_provider()`
   - 从 `Config` 中读取 `model_providers["lmstudio"]` 配置
   - 需要 `base_url` 配置项

3. **配置定义**: `codex-rs/core/src/model_provider_info.rs`
   - `LMSTUDIO_OSS_PROVIDER_ID = "lmstudio"`
   - `DEFAULT_LMSTUDIO_PORT = 1234`
   - `create_oss_provider()` 函数创建默认配置

4. **CLI 集成**: 
   - `codex-rs/tui/src/cli.rs`: `--oss`, `--local-provider` 参数
   - `codex-rs/exec/src/cli.rs`: 同上

5. **提供者选择 UI**: 
   - `codex-rs/tui/src/oss_selection.rs`: TUI 选择界面
   - `codex-rs/tui_app_server/src/oss_selection.rs`: app-server 版本

6. **配置持久化**: `codex-rs/core/src/config/mod.rs::set_default_oss_provider()`
   - 保存用户选择的默认 OSS 提供者到 `config.toml`

---

## 依赖与外部交互

### 内部依赖

| Crate | 用途 |
|-------|------|
| `codex-core` | 配置类型 (`Config`, `LMSTUDIO_OSS_PROVIDER_ID`) |
| `codex-utils-oss` | 统一 OSS 提供者抽象层 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `reqwest` | HTTP 客户端 |
| `serde_json` | JSON 序列化/反序列化 |
| `tokio` | 异步运行时 |
| `tracing` | 日志记录 |
| `which` | 查找 `lms` 可执行文件 |

### 外部系统交互

1. **LM Studio HTTP Server** (localhost:1234)
   - 获取模型列表
   - 加载模型
   - 健康检查

2. **LM Studio CLI (`lms`)**
   - 下载模型: `lms get --yes <model>`
   - 需要用户预先安装 LM Studio 并运行 `lms server start`

3. **环境变量**
   - `CODEX_OSS_PORT`: 覆盖默认端口
   - `CODEX_OSS_BASE_URL`: 覆盖完整 URL
   - `HOME` / `USERPROFILE`: 查找 `lms` 回退路径

---

## 风险、边界与改进建议

### 已知风险

1. **网络依赖**: 虽然号称"本地"模型，但 `ensure_oss_ready` 需要网络连接来下载缺失模型
   - 缓解: 错误被记录为警告，不阻断流程

2. **后台加载失败静默**: 模型加载在后台执行，失败仅记录警告
   - 影响: 用户可能在首次请求时遇到延迟

3. **硬编码默认模型**: `openai/gpt-oss-20b` 是硬编码的
   - 风险: 模型名称变更或停用时需要代码更新

4. **平台差异**: `lms` 回退路径使用条件编译 (`#[cfg(unix)]` / `#[cfg(windows)]`)
   - 风险: 其他平台（如 BSD）可能无法正常工作

### 边界情况

1. **服务器可达但模型端点失败**: `fetch_models()` 失败不会阻止程序继续
2. **模型下载中断**: 依赖 `lms` 命令的退出码检测，无断点续传逻辑
3. **并发模型加载**: 多次调用 `ensure_oss_ready` 可能触发多次后台加载

### 测试覆盖

单元测试位于 `src/client.rs` 的 `#[cfg(test)]` 模块:

| 测试 | 描述 |
|------|------|
| `test_fetch_models_happy_path` | 正常获取模型列表 |
| `test_fetch_models_no_data_array` | 响应缺少 `data` 字段的错误处理 |
| `test_fetch_models_server_error` | 服务器 500 错误处理 |
| `test_check_server_happy_path` | 健康检查成功 |
| `test_check_server_error` | 健康检查失败 (404) |
| `test_find_lms` | 查找 `lms` 可执行文件 |
| `test_find_lms_with_mock_home` | 回退路径构造 |
| `test_from_host_root` | 客户端构造 |

**测试限制**: 所有测试都检查 `CODEX_SANDBOX_NETWORK_DISABLED_ENV_VAR` 环境变量，在沙箱环境中自动跳过。

### 改进建议

1. **配置化默认模型**: 将默认模型移到配置中，允许用户自定义
2. **模型加载状态反馈**: 提供同步加载选项或状态查询机制
3. **下载进度集成**: 当前 `lms` 输出直接继承 stdout，可考虑解析进度信息
4. **重试机制**: 为网络请求添加指数退避重试
5. **健康检查细化**: 区分"服务器未运行"和"服务器错误"的不同提示
6. **文档完善**: 添加更多关于 LM Studio 安装和配置的文档链接

### 与 Ollama 的对比

| 特性 | LM Studio | Ollama |
|------|-----------|--------|
| 默认端口 | 1234 | 11434 |
| 模型下载 | `lms get` | 内置 API |
| 版本检查 | 无 | 有 (`ensure_responses_supported`) |
| 默认模型 | openai/gpt-oss-20b | gpt-oss:20b |
| 进度报告 | 无 | 有 (`PullProgressReporter`) |

LM Studio 集成相对简单，缺少 Ollama 的一些高级特性如版本兼容性检查和下载进度报告。
