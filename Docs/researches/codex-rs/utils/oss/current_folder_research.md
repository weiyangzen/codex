# codex-rs/utils/oss 深度研究文档

## 1. 场景与职责

### 1.1 定位
`codex-utils-oss` 是一个**共享工具库**，专门为 Codex CLI/TUI 提供**开源模型提供商（OSS Provider）的通用抽象层**。它位于 `codex-rs/utils/oss`，作为连接上层应用（TUI/exec）与底层具体 OSS 实现（lmstudio/ollama）的桥梁。

### 1.2 核心职责
- **默认模型映射**：为不同的 OSS 提供商（LM Studio、Ollama）提供默认模型名称
- **就绪状态保证**：在会话启动前确保选定的 OSS 提供商已就绪（服务可达、模型已下载）
- **统一错误处理**：将底层提供商的具体错误转换为标准的 `std::io::Error`

### 1.3 使用场景
| 场景 | 说明 |
|------|------|
| `--oss` 模式启动 | 用户通过 `--oss` 或 `--local-provider` 参数启用本地开源模型 |
| 交互式提供商选择 | TUI 显示 LM Studio 和 Ollama 的选择界面后，需要初始化选中的提供商 |
| 默认模型推断 | 当用户未指定 `-m` 模型时，根据选中的提供商自动选择默认模型 |

### 1.4 调用方
- **`codex-exec`**：CLI 执行模式，在 `run()` 函数中调用 `ensure_oss_provider_ready()` 和 `get_default_model_for_oss_provider()`
- **`codex-tui`**：TUI 交互模式，同样在启动流程中调用上述函数
- **`codex-tui-app-server`**：应用服务器模式，包含并行的 OSS 选择逻辑

---

## 2. 功能点目的

### 2.1 `get_default_model_for_oss_provider`

**目的**：根据提供商 ID 获取默认模型名称。

**设计 rationale**：
- 不同 OSS 提供商使用不同的模型命名约定
- LM Studio 使用 OpenAI 兼容格式（如 `openai/gpt-oss-20b`）
- Ollama 使用自己的命名格式（如 `gpt-oss:20b`）

**映射关系**：
| 提供商 ID | 默认模型 |
|-----------|----------|
| `lmstudio` | `openai/gpt-oss-20b` |
| `ollama` | `gpt-oss:20b` |
| 其他 | `None` |

### 2.2 `ensure_oss_provider_ready`

**目的**：异步确保指定的 OSS 提供商已准备好接受请求。

**执行流程**：
1. **LM Studio 路径**：
   - 调用 `codex_lmstudio::ensure_oss_ready()`
   - 检查本地服务器是否可达（默认端口 1234）
   - 如模型不存在，调用 `lms get --yes <model>` 下载
   - 后台异步加载模型到内存

2. **Ollama 路径**：
   - 首先调用 `codex_ollama::ensure_responses_supported()` 验证版本（要求 ≥ 0.13.4）
   - 调用 `codex_ollama::ensure_oss_ready()`
   - 检查本地服务器是否可达（默认端口 11434）
   - 如模型不存在，通过 `/api/pull` 流式下载并显示进度

**错误处理**：
- 所有内部错误统一转换为 `std::io::Error` with `ErrorKind::Other`
- 保留原始错误信息用于调试

---

## 3. 具体技术实现

### 3.1 关键流程

```
┌─────────────────────────────────────────────────────────────────┐
│                     ensure_oss_provider_ready                   │
│                    (codex-rs/utils/oss/src/lib.rs)              │
└───────────────────────────┬─────────────────────────────────────┘
                            │ match provider_id
            ┌───────────────┴───────────────┐
            ▼                               ▼
┌───────────────────────┐       ┌───────────────────────┐
│   LMSTUDIO_OSS_       │       │   OLLAMA_OSS_         │
│   PROVIDER_ID         │       │   PROVIDER_ID         │
└───────────┬───────────┘       └───────────┬───────────┘
            │                               │
            ▼                               ▼
┌───────────────────────┐       ┌───────────────────────┐
│ codex_lmstudio::      │       │ codex_ollama::        │
│ ensure_oss_ready()    │       │ ensure_responses_     │
│                       │       │ supported()           │
│ - Check server        │       │ - Verify version      │
│ - Download if needed  │       └───────────┬───────────┘
│ - Load model          │                   │
└───────────────────────┘                   ▼
                                ┌───────────────────────┐
                                │ codex_ollama::        │
                                │ ensure_oss_ready()    │
                                │ - Check server        │
                                │ - Pull if needed      │
                                └───────────────────────┘
```

### 3.2 数据结构

#### 3.2.1 输入参数
```rust
// 提供商 ID 字符串（由 codex-core 定义）
pub const LMSTUDIO_OSS_PROVIDER_ID: &str = "lmstudio";
pub const OLLAMA_OSS_PROVIDER_ID: &str = "ollama";

// 配置对象（来自 codex-core）
pub struct Config {
    pub model: Option<String>,
    pub model_providers: HashMap<String, ModelProviderInfo>,
    // ... 其他字段
}
```

#### 3.2.2 返回值
```rust
// get_default_model_for_oss_provider
Option<&'static str>  // 静态字符串切片，避免内存分配

// ensure_oss_provider_ready
Result<(), std::io::Error>
```

### 3.3 协议与接口

#### 3.3.1 LM Studio 集成
- **基础 URL**：`http://localhost:1234/v1`（可通过 `CODEX_OSS_PORT`/`CODEX_OSS_BASE_URL` 覆盖）
- **API 端点**：
  - `GET /models` - 列出可用模型
  - `POST /responses` - OpenAI Responses API 兼容端点
- **CLI 工具**：`lms` 命令行工具（支持 `lms get --yes <model>` 下载）

#### 3.3.2 Ollama 集成
- **基础 URL**：`http://localhost:11434`（可覆盖）
- **API 端点**：
  - `GET /api/tags` - 列出本地模型
  - `GET /api/version` - 获取服务器版本
  - `POST /api/pull` - 流式下载模型
- **版本要求**：支持 Responses API 需要 ≥ 0.13.4

### 3.4 关键代码路径

#### 3.4.1 默认模型获取
```rust
// codex-rs/utils/oss/src/lib.rs:8-14
pub fn get_default_model_for_oss_provider(provider_id: &str) -> Option<&'static str> {
    match provider_id {
        LMSTUDIO_OSS_PROVIDER_ID => Some(codex_lmstudio::DEFAULT_OSS_MODEL),  // "openai/gpt-oss-20b"
        OLLAMA_OSS_PROVIDER_ID => Some(codex_ollama::DEFAULT_OSS_MODEL),      // "gpt-oss:20b"
        _ => None,
    }
}
```

#### 3.4.2 提供商就绪检查
```rust
// codex-rs/utils/oss/src/lib.rs:17-38
pub async fn ensure_oss_provider_ready(
    provider_id: &str,
    config: &Config,
) -> Result<(), std::io::Error> {
    match provider_id {
        LMSTUDIO_OSS_PROVIDER_ID => {
            codex_lmstudio::ensure_oss_ready(config)
                .await
                .map_err(|e| std::io::Error::other(format!("OSS setup failed: {e}")))?;
        }
        OLLAMA_OSS_PROVIDER_ID => {
            // Ollama 需要额外检查版本
            codex_ollama::ensure_responses_supported(&config.model_provider).await?;
            codex_ollama::ensure_oss_ready(config)
                .await
                .map_err(|e| std::io::Error::other(format!("OSS setup failed: {e}")))?;
        }
        _ => { /* Unknown provider, skip setup */ }
    }
    Ok(())
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 本 crate 文件
| 文件 | 行数 | 说明 |
|------|------|------|
| `codex-rs/utils/oss/src/lib.rs` | 61 | 主库代码，包含两个公共函数和单元测试 |
| `codex-rs/utils/oss/Cargo.toml` | 13 | 包配置，依赖 codex-core、codex-lmstudio、codex-ollama |
| `codex-rs/utils/oss/BUILD.bazel` | 6 | Bazel 构建配置 |

### 4.2 依赖 crate 关键文件
| 文件 | 说明 |
|------|------|
| `codex-rs/lmstudio/src/lib.rs` | LM Studio 集成，定义 `DEFAULT_OSS_MODEL` 和 `ensure_oss_ready()` |
| `codex-rs/lmstudio/src/client.rs` | `LMStudioClient` 实现，包含模型下载和加载逻辑 |
| `codex-rs/ollama/src/lib.rs` | Ollama 集成，定义 `DEFAULT_OSS_MODEL`、`ensure_oss_ready()` 和 `ensure_responses_supported()` |
| `codex-rs/ollama/src/client.rs` | `OllamaClient` 实现，包含版本检查和模型拉取 |
| `codex-rs/ollama/src/pull.rs` | 模型拉取进度报告 trait 和实现 |
| `codex-rs/core/src/model_provider_info.rs` | 定义 `LMSTUDIO_OSS_PROVIDER_ID`、`OLLAMA_OSS_PROVIDER_ID` 和 `ModelProviderInfo` |
| `codex-rs/core/src/config/mod.rs` | 定义 `Config` 结构和 `resolve_oss_provider()`、`set_default_oss_provider()` |

### 4.3 调用方文件
| 文件 | 说明 |
|------|------|
| `codex-rs/exec/src/lib.rs:75-76` | 导入 `ensure_oss_provider_ready` 和 `get_default_model_for_oss_provider` |
| `codex-rs/exec/src/lib.rs:329` | 调用 `get_default_model_for_oss_provider()` 获取默认模型 |
| `codex-rs/exec/src/lib.rs:517` | 调用 `ensure_oss_provider_ready()` 确保提供商就绪 |
| `codex-rs/tui/src/lib.rs:47-48` | 导入 OSS 工具函数 |
| `codex-rs/tui/src/lib.rs:401` | 调用 `get_default_model_for_oss_provider()` |
| `codex-rs/tui/src/lib.rs:517` | 调用 `ensure_oss_provider_ready()` |
| `codex-rs/tui/src/oss_selection.rs` | TUI OSS 提供商选择界面 |
| `codex-rs/tui_app_server/src/oss_selection.rs` | 应用服务器模式的 OSS 选择界面 |

---

## 5. 依赖与外部交互

### 5.1 crate 依赖图

```
codex-utils-oss
├── codex-core (workspace)
│   ├── ModelProviderInfo
│   ├── Config
│   ├── LMSTUDIO_OSS_PROVIDER_ID
│   └── OLLAMA_OSS_PROVIDER_ID
├── codex-lmstudio (workspace)
│   ├── DEFAULT_OSS_MODEL
│   └── ensure_oss_ready()
└── codex-ollama (workspace)
    ├── DEFAULT_OSS_MODEL
    ├── ensure_oss_ready()
    └── ensure_responses_supported()
```

### 5.2 外部系统交互

#### 5.2.1 LM Studio 交互
```
codex-utils-oss → codex-lmstudio → HTTP GET/POST → LM Studio Server (localhost:1234)
                                          ↓
                                   lms CLI (下载模型)
```

#### 5.2.2 Ollama 交互
```
codex-utils-oss → codex-ollama → HTTP GET/POST → Ollama Server (localhost:11434)
                                        ↓
                                 /api/pull (流式下载)
```

### 5.3 环境变量
| 变量 | 说明 | 默认值 |
|------|------|--------|
| `CODEX_OSS_PORT` | 覆盖 OSS 提供商端口 | 1234 (LM Studio) / 11434 (Ollama) |
| `CODEX_OSS_BASE_URL` | 完全覆盖基础 URL | `http://localhost:{port}/v1` |

---

## 6. 风险、边界与改进建议

### 6.1 当前风险

#### 6.1.1 错误处理粒度不足
- **问题**：所有错误统一转换为 `std::io::Error::other()`，调用方无法区分错误类型（网络错误、模型不存在、版本不兼容等）
- **影响**：上层无法提供针对性的用户指导
- **代码位置**：`codex-rs/utils/oss/src/lib.rs:25, 31`

#### 6.1.2 未知提供商静默处理
- **问题**：`ensure_oss_provider_ready` 对未知提供商直接跳过，不返回错误
- **影响**：可能导致用户在拼写错误时得不到反馈，后续请求失败时才暴露问题
- **代码位置**：`codex-rs/utils/oss/src/lib.rs:33-35`

#### 6.1.3 版本检查不一致
- **问题**：仅 Ollama 有版本检查（`ensure_responses_supported`），LM Studio 没有
- **影响**：LM Studio 的旧版本可能导致不兼容的 API 行为

### 6.2 边界情况

| 场景 | 当前行为 | 潜在问题 |
|------|----------|----------|
| 用户指定了非默认模型 | 仅检查模型是否存在，不验证兼容性 | 可能下载了不支持的模型格式 |
| 网络中断在下载过程中 | 返回错误，但可能留下不完整文件 | 需要手动清理 |
| 两个 OSS 提供商都运行 | TUI 显示选择界面，exec 需要显式指定 | 自动选择逻辑可能不符合用户预期 |
| OSS 服务器在检查后可访问但在使用时停止 | 就绪检查通过，但后续请求失败 | 没有保活机制 |

### 6.3 改进建议

#### 6.3.1 引入结构化错误类型
```rust
pub enum OssProviderError {
    ServerNotReachable { provider: String, url: String },
    ModelNotFound { provider: String, model: String },
    VersionIncompatible { provider: String, current: String, required: String },
    DownloadFailed { provider: String, model: String, source: Box<dyn std::error::Error> },
    UnknownProvider(String),
}
```

#### 6.3.2 添加提供商健康检查缓存
- 问题：每次启动都进行完整的就绪检查，即使刚刚检查过
- 建议：添加短时间缓存（如 30 秒），避免重复检查

#### 6.3.3 统一版本检查
- 为 LM Studio 添加类似的版本检查机制
- 定义最小支持版本常量

#### 6.3.4 支持更多 OSS 提供商
当前仅支持 LM Studio 和 Ollama，可考虑添加：
- **llama.cpp**（独立模式）
- **vLLM**
- **LocalAI**

#### 6.3.5 改进测试覆盖
当前测试仅覆盖 `get_default_model_for_oss_provider`，建议添加：
- 集成测试（使用 mock 服务器）
- 错误路径测试
- 并发安全测试

### 6.4 架构演进建议

当前架构：
```
tui/exec → codex-utils-oss → {codex-lmstudio, codex-ollama}
```

建议演进为插件化架构：
```
tui/exec → codex-utils-oss → ProviderRegistry
                                      ├── LmStudioProvider
                                      ├── OllamaProvider
                                      └── (extensible)
```

这样可以：
1. 支持动态注册新的 OSS 提供商
2. 统一 trait 接口，强制实现版本检查、健康检查等方法
3. 简化测试（可以 mock Provider trait）

---

## 7. 测试分析

### 7.1 当前测试
位于 `codex-rs/utils/oss/src/lib.rs:40-61`：

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_get_default_model_for_provider_lmstudio() {
        let result = get_default_model_for_oss_provider(LMSTUDIO_OSS_PROVIDER_ID);
        assert_eq!(result, Some(codex_lmstudio::DEFAULT_OSS_MODEL));
    }

    #[test]
    fn test_get_default_model_for_provider_ollama() {
        let result = get_default_model_for_oss_provider(OLLAMA_OSS_PROVIDER_ID);
        assert_eq!(result, Some(codex_ollama::DEFAULT_OSS_MODEL));
    }

    #[test]
    fn test_get_default_model_for_provider_unknown() {
        let result = get_default_model_for_oss_provider("unknown-provider");
        assert_eq!(result, None);
    }
}
```

### 7.2 测试缺口
- 没有 `ensure_oss_provider_ready` 的测试
- 没有错误路径测试
- 没有与下游 crate 的集成测试契约

---

## 8. 总结

`codex-utils-oss` 是一个**轻量级但关键的抽象层**，它：

1. **简化了上层代码**：TUI/exec 不需要直接依赖 lmstudio/ollama 的具体实现
2. **统一了接口**：提供一致的函数签名和错误处理方式
3. **支持扩展**：通过 match 语句可以轻松添加新的提供商

但其当前实现相对简单，在错误处理、测试覆盖和架构扩展性方面存在改进空间。随着支持的 OSS 提供商增多，建议考虑引入 trait-based 的插件化架构。
