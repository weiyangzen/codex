# test_codex.rs 研究文档

## 文件基本信息

- **路径**: `codex-rs/core/tests/common/test_codex.rs`
- **大小**: 约 640 行 (20398 bytes)
- **所属 crate**: `core_test_support`
- **用途**: Codex 核心测试 DSL 和基础设施

---

## 场景与职责

`test_codex.rs` 提供了**高级测试 DSL (领域特定语言)**，用于编写 Codex 核心功能的集成测试。它封装了复杂的初始化逻辑，提供声明式 API 构建测试场景。

### 核心职责

1. **测试环境搭建**: 自动创建隔离的临时目录（home、cwd）
2. **配置管理**: 提供流畅的 API 修改配置
3. **服务器集成**: 支持 wiremock、流式 SSE、WebSocket 三种服务器类型
4. **会话生命周期**: 处理线程创建、恢复、shell 覆盖
5. **请求验证**: 提供便捷的请求体查询方法

### 适用场景

- **单元测试**: 快速验证单个功能点
- **集成测试**: 多组件协作验证
- **回归测试**: 确保修复不引入新问题
- **复杂场景**: 多轮对话、工具调用、会话恢复

---

## 功能点目的

### 1. 构建器模式 (`TestCodexBuilder`)

```rust
pub struct TestCodexBuilder {
    config_mutators: Vec<Box<ConfigMutator>>,    // 配置修改器队列
    auth: CodexAuth,                             // 认证信息
    pre_build_hooks: Vec<Box<PreBuildHook>>,    // 构建前钩子
    home: Option<Arc<TempDir>>,                  // 自定义 home 目录
    user_shell_override: Option<Shell>,          // Shell 覆盖
}
```

**方法链 API**:
- `with_config()`: 添加配置修改器
- `with_model()`: 设置模型名称
- `with_auth()`: 设置认证方式
- `with_home()`: 使用自定义 home 目录
- `with_user_shell()`: 覆盖默认 shell
- `with_windows_cmd_shell()`: Windows CMD 专用

**构建方法**:
- `build()`: 使用 wiremock 服务器
- `build_with_streaming_server()`: 使用流式 SSE 服务器
- `build_with_websocket_server()`: 使用 WebSocket 服务器
- `resume()`: 从 rollout 文件恢复会话

### 2. 测试运行时 (`TestCodex`)

```rust
pub struct TestCodex {
    pub home: Arc<TempDir>,                    // 隔离的 home 目录
    pub cwd: Arc<TempDir>,                     // 隔离的工作目录
    pub codex: Arc<CodexThread>,               // 核心线程实例
    pub session_configured: SessionConfiguredEvent,  // 会话配置事件
    pub config: Config,                        // 最终配置
    pub thread_manager: Arc<ThreadManager>,    // 线程管理器
}
```

**便捷方法**:
- `cwd_path()`: 获取工作目录路径
- `workspace_path()`: 构建工作目录下的路径
- `submit_turn()`: 提交用户输入并等待完成
- `submit_turn_with_policy()`: 指定沙箱策略
- `submit_turn_with_service_tier()`: 指定服务层级

### 3. 测试 harness (`TestCodexHarness`)

```rust
pub struct TestCodexHarness {
    server: MockServer,
    test: TestCodex,
}
```

**一站式测试工具**:
- `new()`: 快速创建默认测试环境
- `with_config()`: 自定义配置
- `submit()`: 提交 prompt
- `request_bodies()`: 获取所有请求体
- `function_call_output_value()`: 获取函数调用输出
- `custom_tool_call_output()`: 获取自定义工具输出

### 4. 模型输出格式枚举

```rust
pub enum ApplyPatchModelOutput {
    Freeform,           // 自由格式（custom_tool_call）
    Function,           // 函数调用格式
    Shell,              // shell 工具格式
    ShellViaHeredoc,    // heredoc 方式
    ShellCommandViaHeredoc,  // shell_command 工具 + heredoc
}

pub enum ShellModelOutput {
    Shell,
    ShellCommand,
    LocalShell,
}
```

**目的**: 测试不同模型输出格式的兼容性。

---

## 具体技术实现

### 配置准备流程

```rust
async fn prepare_config(
    &mut self,
    base_url: String,
    home: &TempDir,
) -> anyhow::Result<(Config, Arc<TempDir>)> {
    // 1. 创建模型提供者（指向 mock 服务器）
    let model_provider = ModelProviderInfo {
        base_url: Some(base_url),
        supports_websockets: false,
        ..built_in_model_providers(None)["openai"].clone()
    };
    
    // 2. 创建临时工作目录
    let cwd = Arc::new(TempDir::new()?);
    
    // 3. 加载默认配置
    let mut config = load_default_config_for_test(home).await;
    config.cwd = cwd.path().to_path_buf();
    config.model_provider = model_provider;
    
    // 4. 执行预构建钩子
    for hook in self.pre_build_hooks.drain(..) {
        hook(home.path());
    }
    
    // 5. 应用配置修改器
    for mutator in mutators {
        mutator(&mut config);
    }
    
    // 6. 设置实验性工具
    ensure_test_model_catalog(&mut config)?;
    
    Ok((config, cwd))
}
```

### 线程创建/恢复逻辑

```rust
async fn build_from_config(...) -> anyhow::Result<TestCodex> {
    // 创建线程管理器
    let thread_manager = Arc::new(ThreadManager::new(...));
    
    // 根据参数选择创建或恢复
    let new_conversation = match (resume_from, user_shell_override) {
        (Some(path), Some(shell)) => {
            // 恢复 + Shell 覆盖
            resume_thread_from_rollout_with_user_shell_override(...)
        }
        (Some(path), None) => {
            // 普通恢复
            thread_manager.resume_thread_from_rollout(...)
        }
        (None, Some(shell)) => {
            // 新建 + Shell 覆盖
            start_thread_with_user_shell_override(...)
        }
        (None, None) => {
            // 普通新建
            thread_manager.start_thread(config).await?
        }
    };
    
    Ok(TestCodex { ... })
}
```

### 测试模型目录生成

```rust
fn ensure_test_model_catalog(config: &mut Config) -> Result<()> {
    // 仅对特定测试模型启用
    if config.model.as_deref() != Some(TEST_MODEL_WITH_EXPERIMENTAL_TOOLS) {
        return Ok(());
    }
    
    // 加载 bundled models.json
    let bundled_models_path = codex_utils_cargo_bin::find_resource!("../../models.json")?;
    let bundled_models: ModelsResponse = serde_json::from_str(...)?;
    
    // 找到 gpt-5.1-codex 并克隆
    let mut model = bundled_models.models.iter()
        .find(|m| m.slug == "gpt-5.1-codex")
        .cloned()
        .unwrap();
    
    // 修改为测试专用名称和工具列表
    model.slug = TEST_MODEL_WITH_EXPERIMENTAL_TOOLS.to_string();
    model.experimental_supported_tools = vec![
        "test_sync_tool".to_string(),
        "read_file".to_string(),
        "grep_files".to_string(),
        "list_dir".to_string(),
    ];
    
    config.model_catalog = Some(ModelsResponse { models: vec![model] });
    Ok(())
}
```

### 请求体验证辅助函数

```rust
fn custom_tool_call_output<'a>(bodies: &'a [Value], call_id: &str) -> &'a Value {
    for body in bodies {
        if let Some(items) = body.get("input").and_then(Value::as_array) {
            for item in items {
                if item.get("type").and_then(Value::as_str) == Some("custom_tool_call_output")
                    && item.get("call_id").and_then(Value::as_str) == Some(call_id)
                {
                    return item;
                }
            }
        }
    }
    panic!("custom_tool_call_output {call_id} not found");
}
```

---

## 关键代码路径与文件引用

### 内部依赖

| 文件 | 用途 |
|------|------|
| `lib.rs` | 模块导出，配置加载辅助函数 |
| `responses.rs` | `start_mock_server()`, `WebSocketTestServer` |
| `streaming_sse.rs` | `StreamingSseServer` |

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_core` | `CodexThread`, `ThreadManager`, `Config` |
| `codex_protocol` | `Op`, `EventMsg`, `SessionConfiguredEvent` |
| `tempfile` | `TempDir` 临时目录 |
| `wiremock` | `MockServer` |

### 调用方示例

```rust
// codex-rs/core/tests/suite/tools.rs
#[tokio::test]
async fn test_shell_command() {
    let harness = TestCodexHarness::new().await.unwrap();
    
    // 挂载 mock 响应
    let mock = mount_function_call_agent_response(
        harness.server(), "call-1", r#"{"command":["ls"]}"#, "shell"
    ).await;
    
    // 提交任务
    harness.submit("list files").await.unwrap();
    
    // 验证输出
    let output = harness.function_call_stdout("call-1").await;
    assert!(output.contains("file.txt"));
}
```

---

## 依赖与外部交互

### 1. Codex 核心架构

```
TestCodexBuilder
    ↓ build()
TestCodex
    ├── ThreadManager (管理线程生命周期)
    ├── CodexThread (核心对话线程)
    ├── Config (配置快照)
    └── TempDir (隔离环境)
```

### 2. 配置系统

- 基于 `ConfigBuilder` 构建默认配置
- 通过 `config_mutators` 链式修改
- 支持 `model_provider` 指向 mock 服务器

### 3. 认证系统

- 默认使用 `CodexAuth::from_api_key("dummy")`
- 支持通过 `with_auth()` 覆盖

### 4. Shell 系统

- 默认使用系统 shell
- 支持 `with_user_shell()` 覆盖
- 特殊处理 Windows CMD

---

## 风险、边界与改进建议

### 已知风险

| 风险 | 影响 | 缓解 |
|------|------|------|
| `Box::pin()` 递归 | 栈溢出风险 | 已使用，但需监控深度 |
| 临时目录泄漏 | 磁盘空间耗尽 | `TempDir` 在 `Drop` 时清理 |
| 配置修改器顺序依赖 | 难以调试 | 文档明确顺序语义 |
| 硬编码模型名称 | 模型变更时失效 | 使用常量定义 |

### 边界条件

1. **多次构建**: `TestCodexBuilder` 在 `build()` 后应丢弃，不可重用
2. **Shell 覆盖限制**: 仅在新建会话时有效，恢复时可能被覆盖
3. **模型目录**: 仅在特定模型名称时生成实验性工具列表
4. **并发限制**: `TempDir` 非线程安全，需 `Arc` 包装

### 改进建议

1. **资源池**: 复用 `TempDir` 减少 IO 开销
2. **并行测试**: 支持同时运行多个独立测试
3. **快照集成**: 内置 `insta` 快照测试支持
4. **性能分析**: 添加耗时统计，识别慢测试
5. **文档生成**: 从测试代码生成 API 文档示例

### 测试覆盖

模块包含 2 个单元测试：
- `custom_tool_call_output_text_returns_output_text`: 正常路径
- `custom_tool_call_output_text_panics_when_output_is_missing`: 错误路径

建议补充：
- 构建器链式调用测试
- 配置修改器顺序测试
- 恢复会话测试
- 并发构建测试
