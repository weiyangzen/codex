# codex-rs/utils/oss 研究文档

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 定位

`codex-utils-oss` 是 Codex CLI 项目中专门用于 **开源本地模型提供商 (OSS Provider)** 的共享工具库。它位于 `codex-rs/utils/oss`，作为 TUI (`codex-tui`) 和 Exec (`codex-exec`) 两个主要入口点的共享依赖。

### 核心职责

1. **统一抽象层**：为不同的本地 OSS 提供商（LM Studio 和 Ollama）提供统一的 Rust API 接口
2. **默认模型管理**：定义并暴露各 OSS 提供商的默认模型标识
3. **就绪状态检查**：确保本地 OSS 服务已启动且模型可用，必要时触发模型下载/拉取
4. **跨组件复用**：避免 TUI 和 Exec 重复实现相同的 OSS 初始化逻辑

### 使用场景

当用户通过 `--oss` 或 `--local-provider` 参数启用本地开源模型时：

```bash
# 自动选择 OSS 提供商
codex --oss

# 显式指定提供商
codex --oss --local-provider=ollama
codex --oss --local-provider=lmstudio
```

此时 TUI 或 Exec 会调用 `codex_utils_oss` 来：
1. 解析应使用哪个 OSS 提供商
2. 获取该提供商的默认模型
3. 确保提供商服务就绪（服务器运行中 + 模型已下载）

---

## 功能点目的

### 1. 默认模型获取 (`get_default_model_for_oss_provider`)

| 提供商 ID | 默认模型 |
|-----------|----------|
| `lmstudio` | `openai/gpt-oss-20b` |
| `ollama` | `gpt-oss:20b` |

**设计差异说明**：
- LM Studio 使用 OpenAI 兼容格式路径 `openai/gpt-oss-20b`
- Ollama 使用其原生格式 `gpt-oss:20b`

### 2. 提供商就绪检查 (`ensure_oss_provider_ready`)

该函数是异步的核心初始化流程：

**LM Studio 路径**：
1. 检查服务器是否可达（HTTP GET `/models`）
2. 查询已安装模型列表
3. 如模型缺失，调用 `lms get --yes <model>` 下载
4. 后台加载模型到内存（非阻塞）

**Ollama 路径**：
1. 额外检查 Responses API 版本兼容性（要求 >= 0.13.4）
2. 检查服务器是否可达
3. 如模型缺失，通过 `/api/pull` 流式拉取
4. 显示下载进度（CLI/TUI 进度报告器）

### 3. 错误处理策略

所有错误均被转换为 `std::io::Error`，并附加用户友好的错误消息：
- LM Studio 连接失败 → "LM Studio is not responding. Install from https://lmstudio.ai/download..."
- Ollama 版本过旧 → "Ollama {version} is too old. Codex requires Ollama {min} or newer."

---

## 具体技术实现

### 关键流程

```
┌─────────────────────────────────────────────────────────────────┐
│                     ensure_oss_provider_ready                    │
│                     (codex-rs/utils/oss/src/lib.rs)              │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              │                               │
              ▼                               ▼
┌─────────────────────────┐       ┌─────────────────────────┐
│   LMSTUDIO_OSS_PROVIDER │       │   OLLAMA_OSS_PROVIDER   │
│         (_ID)           │       │         (_ID)           │
└─────────────────────────┘       └─────────────────────────┘
              │                               │
              ▼                               ▼
┌─────────────────────────┐       ┌─────────────────────────┐
│  codex_lmstudio::       │       │  codex_ollama::         │
│  ensure_oss_ready()     │       │  ensure_responses_      │
│                         │       │  supported()            │
└─────────────────────────┘       └─────────────────────────┘
              │                               │
              ▼                               ▼
┌─────────────────────────┐       ┌─────────────────────────┐
│  LMStudioClient::       │       │  OllamaClient::         │
│  try_from_provider()    │       │  try_from_oss_provider()│
│  - 检查服务器状态        │       │  - 检查版本兼容性        │
│  - fetch_models()       │       │  - 检查服务器状态        │
│  - download_model()     │       │  - fetch_models()       │
│  - load_model() (后台)   │       │  - pull_model_stream()  │
└─────────────────────────┘       └─────────────────────────┘
```

### 数据结构

**核心常量定义**（`codex-rs/core/src/model_provider_info.rs`）：

```rust
pub const DEFAULT_LMSTUDIO_PORT: u16 = 1234;
pub const DEFAULT_OLLAMA_PORT: u16 = 11434;
pub const LMSTUDIO_OSS_PROVIDER_ID: &str = "lmstudio";
pub const OLLAMA_OSS_PROVIDER_ID: &str = "ollama";
```

**ModelProviderInfo 结构**（简化）：

```rust
pub struct ModelProviderInfo {
    pub name: String,
    pub base_url: Option<String>,  // 如 "http://localhost:1234/v1"
    pub env_key: Option<String>,   // API Key 环境变量（OSS 通常为 None）
    pub wire_api: WireApi,         // 固定为 Responses
    pub requires_openai_auth: bool, // OSS 为 false
    pub supports_websockets: bool,  // OSS 为 false
    // ... 其他配置
}
```

### 协议与 API

**LM Studio 通信协议**：
- 基础 URL: `http://localhost:1234/v1`（可通过 `CODEX_OSS_PORT` 或 `CODEX_OSS_BASE_URL` 覆盖）
- 端点：
  - `GET /models` - 列出可用模型
  - `POST /responses` - 加载模型（空请求，max_tokens=1）
- 下载工具：调用本地 `lms` CLI（`lms get --yes <model>`）

**Ollama 通信协议**：
- 基础 URL: `http://localhost:11434`（可覆盖）
- 端点：
  - `GET /api/tags` - 列出模型
  - `GET /api/version` - 获取版本
  - `POST /api/pull` - 流式拉取模型
- 版本检查：要求 >= 0.13.4 以支持 Responses API

### 命令执行

**LM Studio 模型下载**（`codex-rs/lmstudio/src/client.rs`）：

```rust
let status = std::process::Command::new(&lms)
    .args(["get", "--yes", model])
    .stdout(std::process::Stdio::inherit())
    .stderr(std::process::Stdio::null())
    .status()
```

查找优先级：
1. `PATH` 中的 `lms`
2. 回退路径：`~/.lmstudio/bin/lms` (Unix) 或 `~/.lmstudio/bin/lms.exe` (Windows)

---

## 关键代码路径与文件引用

### 本 crate 文件

| 文件 | 说明 |
|------|------|
| `codex-rs/utils/oss/src/lib.rs` | 唯一源文件，包含两个公共函数和单元测试 |
| `codex-rs/utils/oss/Cargo.toml` | 依赖声明：codex-core, codex-lmstudio, codex-ollama |
| `codex-rs/utils/oss/BUILD.bazel` | Bazel 构建配置 |

### 上游依赖（被调用方）

| 文件 | 功能 |
|------|------|
| `codex-rs/lmstudio/src/lib.rs` | LM Studio 公共 API (`ensure_oss_ready`, `DEFAULT_OSS_MODEL`) |
| `codex-rs/lmstudio/src/client.rs` | LMStudioClient 实现（HTTP 通信、模型下载） |
| `codex-rs/ollama/src/lib.rs` | Ollama 公共 API (`ensure_oss_ready`, `ensure_responses_supported`, `DEFAULT_OSS_MODEL`) |
| `codex-rs/ollama/src/client.rs` | OllamaClient 实现（HTTP 通信、版本检查） |
| `codex-rs/ollama/src/pull.rs` | 模型拉取进度报告 |
| `codex-rs/core/src/model_provider_info.rs` | 提供商常量定义和 ModelProviderInfo 结构 |
| `codex-rs/core/src/config/mod.rs` | `resolve_oss_provider()` 函数（配置解析） |

### 下游调用方

| 文件 | 使用场景 |
|------|----------|
| `codex-rs/exec/src/lib.rs` | `run_main()` → `ensure_oss_provider_ready()` 在 OSS 模式下初始化 |
| `codex-rs/tui/src/lib.rs` | `run_main()` → `ensure_oss_provider_ready()` 在 OSS 模式下初始化 |
| `codex-rs/tui_app_server/src/lib.rs` | 同上（TUI 的 App Server 版本） |
| `codex-rs/tui/src/oss_selection.rs` | OSS 提供商选择 UI（调用 `set_default_oss_provider`） |

### 配置相关

**配置解析链**（`resolve_oss_provider` 函数）：

```rust
// 优先级顺序：
1. CLI 显式指定 (--local-provider)
2. Profile 配置 (config.toml [profiles.<name>].oss_provider)
3. 全局配置 (config.toml oss_provider)
4. 返回 None（触发交互式选择）
```

---

## 依赖与外部交互

### 内部 crate 依赖

```
codex-utils-oss
├── codex-core (workspace)
│   ├── 常量: LMSTUDIO_OSS_PROVIDER_ID, OLLAMA_OSS_PROVIDER_ID
│   ├── 配置: Config, resolve_oss_provider
│   └── 模型提供商: ModelProviderInfo
├── codex-lmstudio (workspace)
│   ├── DEFAULT_OSS_MODEL
│   └── ensure_oss_ready()
└── codex-ollama (workspace)
    ├── DEFAULT_OSS_MODEL
    ├── ensure_oss_ready()
    └── ensure_responses_supported()
```

### 外部系统交互

| 系统 | 交互方式 | 用途 |
|------|----------|------|
| LM Studio Server | HTTP (端口 1234) | 模型列表查询、模型加载 |
| Ollama Server | HTTP (端口 11434) | 模型列表查询、版本检查、模型拉取 |
| `lms` CLI | 子进程调用 | 模型下载 (`lms get`) |
| 配置文件 | 文件读写 | 保存默认提供商偏好 (`set_default_oss_provider`) |

### 环境变量

| 变量 | 影响 |
|------|------|
| `CODEX_OSS_PORT` | 覆盖默认 OSS 端口（1234/11434） |
| `CODEX_OSS_BASE_URL` | 完全覆盖 OSS 基础 URL |

---

## 风险、边界与改进建议

### 已知风险

1. **硬编码模型名称**
   - 当前 `DEFAULT_OSS_MODEL` 是编译时常量
   - 如果上游模型发布新版本，需要重新编译
   - **建议**：考虑从远程配置或配置文件读取

2. **端口冲突检测不足**
   - 仅检查端口是否可连接，不验证服务类型
   - 如果 1234/11434 被其他服务占用，可能产生误导性错误

3. **版本检查差异**
   - Ollama 有显式版本检查（>= 0.13.4）
   - LM Studio 无版本检查，依赖其 OpenAI 兼容性

4. **错误消息耦合**
   - `ensure_oss_provider_ready` 将错误统一包装为 "OSS setup failed"
   - 原始错误细节在转换中可能丢失

### 边界情况

| 场景 | 当前行为 |
|------|----------|
| 未知提供商 ID | 静默跳过（返回 Ok(())） |
| 网络不可达 | 返回 `io::Error::other` 并附带帮助链接 |
| 模型下载失败 | 向上传播错误，终止启动 |
| 并发初始化 | 无锁保护，依赖底层 HTTP 客户端的并发安全 |

### 改进建议

1. **增加提供商健康检查接口**
   ```rust
   // 建议添加
   pub async fn check_oss_provider_health(provider_id: &str) -> ProviderHealthStatus
   ```

2. **统一模型下载进度报告**
   - LM Studio 当前使用 `Stdio::inherit()` 直接输出到 stderr
   - 建议与 Ollama 统一，使用 `PullProgressReporter` trait

3. **支持更多 OSS 提供商**
   - 当前仅支持 LM Studio 和 Ollama
   - 可考虑增加对 llama.cpp server、vLLM 等的支持

4. **配置热重载**
   - 当前 OSS 提供商配置在启动时解析后固定
   - 可考虑支持运行时切换（需配合 Session 重建）

5. **测试覆盖**
   - 当前单元测试仅测试 `get_default_model_for_oss_provider`
   - 建议增加集成测试（使用 mock server 测试 `ensure_oss_provider_ready`）

---

## 附录：代码统计

| 指标 | 数值 |
|------|------|
| 源文件数 | 1 (`lib.rs`) |
| 代码行数 | ~61 行 |
| 公共 API | 2 个函数 |
| 单元测试 | 3 个 |

---

*文档生成时间: 2026-03-22*
*研究范围: codex-rs/utils/oss/src 及其直接依赖*
