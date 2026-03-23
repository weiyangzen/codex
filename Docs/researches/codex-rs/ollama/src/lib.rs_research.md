# codex-rs/ollama/src/lib.rs 研究文档

## 场景与职责

`lib.rs` 是 `codex-ollama` crate 的根模块，定义了库的公共接口和高级工作流。它作为 Ollama 集成的入口点，为 Codex CLI 的 OSS（开源软件）模式提供以下能力：

1. **环境准备**：`ensure_oss_ready` 函数确保 Ollama 服务器运行且所需模型可用
2. **版本兼容性检查**：`ensure_responses_supported` 验证 Ollama 版本是否支持 Responses API
3. **模块组织**：声明并重新导出子模块（client、parser、pull、url）的公共接口

该模块是 `codex-utils-oss` crate 的底层依赖，后者为 TUI 和 exec 模式提供统一的 OSS 提供者抽象。

## 功能点目的

### 1. 默认模型常量

```rust
pub const DEFAULT_OSS_MODEL: &str = "gpt-oss:20b";
```

当用户启用 `--oss` 模式但未指定 `-m` 模型时，使用此默认模型。这是 OpenAI 的 GPT-OSS 20B 参数模型，专为本地运行优化。

### 2. ensure_oss_ready 函数

这是 OSS 模式启动时的核心准备函数：

```rust
pub async fn ensure_oss_ready(config: &Config) -> std::io::Result<()>
```

执行流程：
1. **确定目标模型**：从 `config.model` 读取，或使用 `DEFAULT_OSS_MODEL`
2. **验证服务器可达**：通过 `OllamaClient::try_from_oss_provider` 创建客户端并探测服务器
3. **检查模型存在**：调用 `fetch_models` 获取本地模型列表
4. **按需拉取模型**：如果模型不存在，使用 `CliProgressReporter` 显示进度并拉取

### 3. ensure_responses_supported 函数

验证 Ollama 服务器版本是否支持 Responses API：

```rust
pub async fn ensure_responses_supported(provider: &ModelProviderInfo) -> std::io::Result<()>
```

版本要求：
- 最低版本：`0.13.4`
- 特殊处理：`0.0.0` 视为开发版本，始终通过

### 4. 模块重新导出

```rust
pub use client::OllamaClient;
pub use pull::CliProgressReporter;
pub use pull::PullEvent;
pub use pull::PullProgressReporter;
pub use pull::TuiProgressReporter;
```

这些类型被 `codex-utils-oss` 和其他上层模块直接使用。

## 具体技术实现

### 版本兼容性逻辑

```rust
fn min_responses_version() -> Version {
    Version::new(0, 13, 4)
}

fn supports_responses(version: &Version) -> bool {
    *version == Version::new(0, 0, 0) || *version >= min_responses_version()
}
```

- `0.0.0` 是开发版本的标记，允许通过检查
- 生产版本必须 >= 0.13.4

### ensure_oss_ready 详细流程

```rust
pub async fn ensure_oss_ready(config: &Config) -> std::io::Result<()> {
    // 1. 确定模型
    let model = match config.model.as_ref() {
        Some(model) => model,
        None => DEFAULT_OSS_MODEL,
    };

    // 2. 验证服务器
    let ollama_client = crate::OllamaClient::try_from_oss_provider(config).await?;

    // 3. 检查并拉取模型
    match ollama_client.fetch_models().await {
        Ok(models) => {
            if !models.iter().any(|m| m == model) {
                let mut reporter = crate::CliProgressReporter::new();
                ollama_client.pull_with_reporter(model, &mut reporter).await?;
            }
        }
        Err(err) => {
            // 非致命错误，仅记录警告
            tracing::warn!("Failed to query local models from Ollama: {}.", err);
        }
    }

    Ok(())
}
```

**关键设计决策**：
- `fetch_models` 失败不阻塞流程，允许在查询失败时继续尝试使用模型
- 模型拉取失败会返回错误，中断启动流程
- 使用 `CliProgressReporter` 向 stderr 输出进度

### 模块声明

```rust
mod client;
mod parser;
mod pull;
mod url;
```

这些模块都是私有的，只有通过 `pub use` 重新导出的类型才是公共 API。

## 关键代码路径与文件引用

### 模块结构

```
codex-ollama (lib.rs)
├── client.rs (OllamaClient)
├── parser.rs (pull_events_from_value)
├── pull.rs (PullEvent, CliProgressReporter, TuiProgressReporter)
└── url.rs (URL 处理工具)
```

### 调用方

| 调用方 | 调用函数 | 场景 |
|--------|----------|------|
| `codex-utils-oss/src/lib.rs` | `ensure_oss_ready`, `ensure_responses_supported` | 统一的 OSS 准备流程 |
| `codex-tui/src/oss_selection.rs` | 通过 `utils/oss` 间接调用 | TUI 模式下的 OSS 选择 |
| `codex-exec/src/lib.rs` | 通过 `utils/oss` 间接调用 | CLI 执行模式 |

### 调用链示例

```
exec/src/lib.rs::run_exec_session
    └── utils/oss/src/lib.rs::ensure_oss_provider_ready
            └── ollama/src/lib.rs::ensure_oss_ready
                    └── ollama/src/client.rs::OllamaClient::try_from_oss_provider
                    └── ollama/src/client.rs::OllamaClient::fetch_models
                    └── ollama/src/client.rs::OllamaClient::pull_with_reporter
```

### 测试覆盖

测试模块包含三个单元测试：

1. `supports_responses_for_dev_zero`：验证 `0.0.0` 版本通过检查
2. `does_not_support_responses_before_cutoff`：验证 `0.13.3` 被拒绝
3. `supports_responses_at_or_after_cutoff`：验证 `0.13.4` 和 `0.14.0` 通过

## 依赖与外部交互

### 外部 crate 依赖

| crate | 用途 |
|-------|------|
| `codex_core` | `Config`, `ModelProviderInfo`, `OLLAMA_OSS_PROVIDER_ID` |
| `semver::Version` | 语义化版本比较 |

### 与 codex_core 的集成

```rust
use codex_core::ModelProviderInfo;
use codex_core::config::Config;
use codex_core::OLLAMA_OSS_PROVIDER_ID;
```

- `Config`：获取用户配置（模型选择、提供者覆盖）
- `ModelProviderInfo`：提供者配置结构
- `OLLAMA_OSS_PROVIDER_ID`：常量 `"ollama"`

### 与 codex-utils-oss 的关系

`codex-utils-oss` 是更上层的抽象，支持多个 OSS 提供者：

```rust
// utils/oss/src/lib.rs
pub async fn ensure_oss_provider_ready(
    provider_id: &str,
    config: &Config,
) -> Result<(), std::io::Error> {
    match provider_id {
        LMSTUDIO_OSS_PROVIDER_ID => { /* ... */ }
        OLLAMA_OSS_PROVIDER_ID => {
            codex_ollama::ensure_responses_supported(&config.model_provider).await?;
            codex_ollama::ensure_oss_ready(config).await?;
        }
        _ => { /* 未知提供者 */ }
    }
}
```

注意：Ollama 需要额外的版本检查，而 LM Studio 不需要。

## 风险、边界与改进建议

### 已知风险

1. **模型拉取阻塞**：`pull_with_reporter` 是同步等待的，大模型拉取可能需要很长时间，阻塞启动流程。

2. **版本检查顺序**：`ensure_responses_supported` 和 `ensure_oss_ready` 是两个独立调用，可能重复创建客户端和探测服务器。

3. **模型名称匹配**：使用简单字符串相等比较，可能因标签格式（如 `gpt-oss:20b` vs `gpt-oss:latest`）导致误判。

### 边界情况

| 场景 | 行为 |
|------|------|
| 服务器不可达 | `try_from_oss_provider` 返回错误，启动失败 |
| 模型列表查询失败 | 记录警告，继续尝试使用模型 |
| 模型拉取失败 | 返回错误，启动失败 |
| 版本端点不可用 | `ensure_responses_supported` 返回 `Ok(())`，允许继续 |
| 版本低于 0.13.4 | 返回版本不兼容错误 |

### 改进建议

1. **合并版本检查和准备流程**：当前 `ensure_responses_supported` 和 `ensure_oss_ready` 各自创建客户端，可以合并以减少一次服务器探测。

2. **模型名称模糊匹配**：支持更灵活的模型名称匹配，例如忽略标签或支持别名。

3. **后台拉取**：考虑在后台异步拉取模型，不阻塞启动流程，首次使用时等待完成。

4. **配置化默认模型**：`DEFAULT_OSS_MODEL` 是硬编码的，可考虑从配置读取。

5. **拉取超时控制**：当前拉取没有超时，可能无限期阻塞，建议添加可配置超时。

### 与 LM Studio 对比

| 特性 | Ollama (lib.rs) | LM Studio (lib.rs) |
|------|-----------------|-------------------|
| 默认模型 | `gpt-oss:20b` | `openai/gpt-oss-20b` |
| 版本检查 | 显式检查 >= 0.13.4 | 无 |
| 模型加载 | 拉取后自动加载 | 需要显式 `load_model` 调用 |
| 后台任务 | 无 | 有（`tokio::spawn` 加载模型）|

LM Studio 的实现包含后台模型加载逻辑，而 Ollama 依赖其自身的懒加载机制。Ollama 需要额外的版本检查是因为 Responses API 支持是较新的功能。
