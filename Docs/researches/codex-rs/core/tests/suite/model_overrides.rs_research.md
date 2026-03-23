# model_overrides.rs 研究文档

## 场景与职责

`model_overrides.rs` 是 Codex Core 集成测试套件的一部分，专门测试 `OverrideTurnContext` 操作中的模型覆盖行为。该测试文件验证以下核心场景：

1. **临时模型切换的持久化边界**：确保通过 `OverrideTurnContext` 设置的模型覆盖不会意外持久化到配置文件
2. **配置文件的不可变性**：验证当用户已存在 `config.toml` 时，模型覆盖操作不会修改该文件
3. **无配置场景的行为**：验证当用户没有配置文件时，模型覆盖不会自动创建配置

这些测试确保了 Codex 的"临时覆盖"语义——即 `OverrideTurnContext` 仅影响当前会话的后续回合，而不应改变用户的持久化配置。

## 功能点目的

### 测试用例 1: `override_turn_context_does_not_persist_when_config_exists`
- **目的**：验证当用户已存在 `config.toml` 且其中指定了模型时，执行 `OverrideTurnContext` 切换模型后，配置文件内容保持不变
- **业务价值**：防止临时模型切换意外覆盖用户的默认模型偏好

### 测试用例 2: `override_turn_context_does_not_create_config_file`
- **目的**：验证当用户没有 `config.toml` 时，执行 `OverrideTurnContext` 不会自动创建配置文件
- **业务价值**：确保"临时覆盖"不会引入意外的持久化副作用

## 具体技术实现

### 关键数据结构

```rust
// Op::OverrideTurnContext 定义 (protocol/src/protocol.rs)
OverrideTurnContext {
    cwd: Option<PathBuf>,
    approval_policy: Option<AskForApproval>,
    approvals_reviewer: Option<ApprovalsReviewer>,
    sandbox_policy: Option<SandboxPolicy>,
    windows_sandbox_level: Option<WindowsSandboxLevel>,
    model: Option<String>,              // 模型覆盖字段
    effort: Option<Option<ReasoningEffortConfig>>,
    summary: Option<ReasoningSummaryConfig>,
    service_tier: Option<Option<ServiceTier>>,
    collaboration_mode: Option<CollaborationMode>,
    personality: Option<Personality>,
}
```

### 测试流程

1. **初始化阶段**：
   - 启动 Mock Server (`start_mock_server().await`)
   - 使用 `test_codex()` 构建器创建测试环境
   - 可选：通过 `with_pre_build_hook` 预置 `config.toml`

2. **执行覆盖操作**：
   ```rust
   codex.submit(Op::OverrideTurnContext {
       model: Some("o3".to_string()),  // 临时切换到 o3 模型
       effort: Some(Some(ReasoningEffort::High)),
       // ... 其他字段为 None 表示不覆盖
   }).await
   ```

3. **验证阶段**：
   - 提交 `Op::Shutdown` 关闭会话
   - 等待 `ShutdownComplete` 事件
   - 读取 `config.toml` 内容，验证其未被修改

### 测试辅助工具

- **`test_codex()`**: 创建 `TestCodexBuilder`，提供流畅的测试配置 API
- **`with_pre_build_hook`**: 在构建测试环境前执行自定义初始化（如写入配置文件）
- **`wait_for_event`**: 异步等待特定事件，用于测试同步点

## 关键代码路径与文件引用

### 被测试代码路径

| 文件 | 相关功能 |
|------|----------|
| `codex-rs/core/src/codex.rs` | 处理 `OverrideTurnContext` 操作，更新会话状态但不持久化配置 |
| `codex-rs/core/src/config/` | 配置加载与保存逻辑，确保覆盖不触发配置写入 |
| `codex-rs/protocol/src/protocol.rs` | `Op::OverrideTurnContext` 定义 (行 301-353) |

### 测试依赖

| 文件 | 用途 |
|------|------|
| `codex-rs/core/tests/common/test_codex.rs` | `TestCodexBuilder` 和测试环境构建 |
| `codex-rs/core/tests/common/responses.rs` | Mock Server 和 SSE 响应辅助 |
| `codex-rs/core/tests/common/lib.rs` | 共享测试工具（`wait_for_event` 等） |

## 依赖与外部交互

### 外部依赖

1. **wiremock**: 用于启动 Mock HTTP Server，模拟 OpenAI API 响应
2. **tokio**: 异步运行时，测试使用 `#[tokio::test]` 属性
3. **tempfile**: 创建临时目录作为测试隔离的 `CODEX_HOME`

### 协议依赖

- `codex_protocol::protocol::Op`: 定义了 `OverrideTurnContext` 操作
- `codex_protocol::openai_models::ReasoningEffort`: 推理努力级别枚举

### 测试框架依赖

- `core_test_support`: 内部测试支持库，提供：
  - `test_codex::test_codex()` - 测试构建器工厂
  - `responses::start_mock_server()` - Mock 服务器启动
  - `wait_for_event()` - 事件等待辅助

## 风险、边界与改进建议

### 当前风险

1. **测试覆盖有限**：仅测试了模型字段的覆盖行为，未覆盖 `effort`、`service_tier` 等其他字段的持久化边界
2. **缺少并发测试**：未验证多线程/多回合并发执行覆盖操作的正确性
3. **配置格式耦合**：测试硬编码了 TOML 格式的配置内容，若配置序列化格式变更，测试可能失效

### 边界情况

1. **空模型字符串**：测试未覆盖传入空字符串 `""` 作为模型的情况
2. **无效模型标识**：测试未覆盖覆盖为不存在模型时的错误处理
3. **配置权限问题**：测试未模拟配置文件只读或磁盘满等 IO 错误场景

### 改进建议

1. **扩展字段覆盖测试**：为 `effort`、`summary`、`service_tier` 等字段添加类似的持久化边界测试
2. **添加负面测试**：验证无效模型标识时的错误传播行为
3. **文档化契约**：在 `OverrideTurnContext` 的文档中明确说明哪些字段是"临时"的，哪些是"持久化"的
4. **集成配置重载测试**：验证 `OverrideTurnContext` 后执行 `ReloadUserConfig` 的交互行为

### 相关测试文件

- `model_switching.rs`: 测试模型切换的功能性行为（与覆盖行为互补）
- `model_visible_layout.rs`: 测试模型变更对请求布局的影响
- `override_updates.rs`: 测试覆盖操作的更新传播机制
