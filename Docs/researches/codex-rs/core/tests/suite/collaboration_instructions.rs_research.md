# 研究文档：collaboration_instructions.rs

## 文件位置
`codex-rs/core/tests/suite/collaboration_instructions.rs`

---

## 1. 场景与职责

### 1.1 核心职责

`collaboration_instructions.rs` 是 Codex 核心测试套件中的集成测试文件，专门负责验证**协作模式指令（Collaboration Mode Instructions）**在整个对话生命周期中的正确注入、传播和持久化行为。

### 1.2 业务场景

该测试文件覆盖以下关键业务场景：

| 场景 | 描述 |
|------|------|
| 默认行为 | 验证未配置协作模式时，不会意外注入协作指令 |
| 覆盖模式 | 通过 `OverrideTurnContext` 操作设置协作模式 |
| 单轮模式 | 通过 `UserTurn` 操作在单轮对话中指定协作模式 |
| 模式切换 | 验证不同协作模式之间的切换行为 |
| 重复设置 | 验证相同协作模式重复设置时的幂等性（noop 不追加） |
| 会话恢复 | 验证会话恢复（resume）后协作指令的正确重放 |
| 空指令处理 | 验证空字符串协作指令被正确忽略 |

### 1.3 协作模式类型

测试涉及两种主要协作模式（定义于 `codex_protocol::config_types::ModeKind`）：

- **`ModeKind::Default`** - 默认模式，执行模式
- **`ModeKind::Plan`** - 计划模式，用于规划阶段

---

## 2. 功能点目的

### 2.1 测试目标

1. **指令注入验证**：确保协作模式指令以正确的 XML 标签格式（`<collaboration_mode>...</collaboration_mode>`）注入到开发者消息中
2. **上下文传播验证**：验证 `OverrideTurnContext` 和 `UserTurn` 两种操作对协作模式的传播行为
3. **持久化验证**：验证协作模式在会话恢复后能够正确重放
4. **幂等性验证**：确保相同协作模式重复设置不会导致重复指令注入

### 2.2 关键断言模式

所有测试用例均采用以下验证模式：

```rust
// 1. 构建协作模式配置
let collaboration_mode = collab_mode_with_instructions(Some("instructions text"));

// 2. 提交操作（OverrideTurnContext 或 UserTurn）
test.codex.submit(Op::OverrideTurnContext { 
    collaboration_mode: Some(collaboration_mode),
    ... 
}).await?;

// 3. 提交用户输入
test.codex.submit(Op::UserInput { ... }).await?;

// 4. 等待回合完成
wait_for_event(&test.codex, |ev| matches!(ev, EventMsg::TurnComplete(_))).await;

// 5. 验证请求中的开发者消息包含预期指令
let input = req.single_request().input();
let dev_texts = developer_texts(&input);
assert_eq!(count_messages_containing(&dev_texts, &collab_xml(collab_text)), 1);
```

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 CollaborationMode（协议层）

```rust
// 位置: codex-rs/protocol/src/config_types.rs
#[derive(Clone, PartialEq, Eq, Hash, Debug, Serialize, Deserialize, JsonSchema, TS)]
#[serde(rename_all = "lowercase")]
pub struct CollaborationMode {
    pub mode: ModeKind,
    pub settings: Settings,
}

#[derive(Clone, PartialEq, Eq, Hash, Debug, Serialize, Deserialize, JsonSchema, TS)]
pub struct Settings {
    pub model: String,
    pub reasoning_effort: Option<ReasoningEffort>,
    pub developer_instructions: Option<String>,  // 协作指令内容
}
```

#### 3.1.2 ModeKind（枚举）

```rust
// 位置: codex-rs/protocol/src/config_types.rs
#[derive(...)]
#[serde(rename_all = "snake_case")]
pub enum ModeKind {
    Plan,
    #[default]
    #[serde(alias = "code", alias = "pair_programming", alias = "execute", alias = "custom")]
    Default,
    #[doc(hidden)]
    PairProgramming,  // 已隐藏，向后兼容
    #[doc(hidden)]
    Execute,          // 已隐藏，向后兼容
}
```

### 3.2 XML 标签常量

```rust
// 位置: codex-rs/protocol/src/protocol.rs
pub const COLLABORATION_MODE_OPEN_TAG: &str = "<collaboration_mode>";
pub const COLLABORATION_MODE_CLOSE_TAG: &str = "</collaboration_mode>";
```

### 3.3 指令生成流程

#### 3.3.1 从协作模式到开发者指令

```rust
// 位置: codex-rs/protocol/src/models.rs
impl DeveloperInstructions {
    pub fn from_collaboration_mode(collaboration_mode: &CollaborationMode) -> Option<Self> {
        collaboration_mode
            .settings
            .developer_instructions
            .as_ref()
            .filter(|instructions| !instructions.is_empty())  // 过滤空指令
            .map(|instructions| {
                DeveloperInstructions::new(format!(
                    "{COLLABORATION_MODE_OPEN_TAG}{instructions}{COLLABORATION_MODE_CLOSE_TAG}"
                ))
            })
    }
}
```

#### 3.3.2 指令注入点（核心代码）

```rust
// 位置: codex-rs/core/src/codex.rs
// 在 prepare_turn_context 函数中

// Add developer instructions from collaboration_mode if they exist and are non-empty
if let Some(collab_instructions) =
    DeveloperInstructions::from_collaboration_mode(&collaboration_mode)
{
    developer_sections.push(collab_instructions.into_text());
}
```

### 3.4 测试辅助函数

```rust
// 位置: collaboration_instructions.rs

/// 构建带指令的协作模式
fn collab_mode_with_mode_and_instructions(
    mode: ModeKind,
    instructions: Option<&str>,
) -> CollaborationMode {
    CollaborationMode {
        mode,
        settings: Settings {
            model: "gpt-5.1".to_string(),
            reasoning_effort: None,
            developer_instructions: instructions.map(str::to_string),
        },
    }
}

/// 从输入中提取开发者角色的文本内容
fn developer_texts(input: &[Value]) -> Vec<String> {
    input
        .iter()
        .filter(|item| item.get("role").and_then(Value::as_str) == Some("developer"))
        .filter_map(|item| item.get("content")?.as_array().cloned())
        .flatten()
        .filter_map(|content| {
            let text = content.get("text")?.as_str()?;
            Some(text.to_string())
        })
        .collect()
}

/// 构建 XML 格式的协作指令
fn collab_xml(text: &str) -> String {
    format!("{COLLABORATION_MODE_OPEN_TAG}{text}{COLLABORATION_MODE_CLOSE_TAG}")
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 测试文件依赖图

```
collaboration_instructions.rs
├── 测试框架依赖
│   ├── core_test_support::responses::*     (codex-rs/core/tests/common/responses.rs)
│   ├── core_test_support::test_codex::*    (codex-rs/core/tests/common/test_codex.rs)
│   └── core_test_support::wait_for_event   (codex-rs/core/tests/common/lib.rs)
│
├── 协议类型依赖
│   ├── codex_protocol::config_types::*     (codex-rs/protocol/src/config_types.rs)
│   ├── codex_protocol::protocol::*         (codex-rs/protocol/src/protocol.rs)
│   └── codex_protocol::user_input::*       (codex-rs/protocol/src/user_input.rs)
│
└── 核心实现依赖（间接）
    ├── codex_core::CodexThread             (codex-rs/core/src/codex_thread.rs)
    └── codex_core::models_manager::*       (codex-rs/core/src/models_manager/)
```

### 4.2 核心实现文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/protocol/src/config_types.rs` | `CollaborationMode`、`ModeKind`、`Settings` 定义 |
| `codex-rs/protocol/src/protocol.rs` | `Op::UserTurn`、`Op::OverrideTurnContext`、XML 标签常量 |
| `codex-rs/protocol/src/models.rs` | `DeveloperInstructions::from_collaboration_mode` |
| `codex-rs/core/src/codex.rs` | 会话管理、指令注入逻辑 |
| `codex-rs/core/src/models_manager/collaboration_mode_presets.rs` | 预设协作模式配置 |
| `codex-rs/core/templates/collaboration_mode/default.md` | Default 模式模板 |
| `codex-rs/core/templates/collaboration_mode/plan.md` | Plan 模式模板 |

### 4.3 测试用例清单

| 测试函数 | 行号 | 测试目的 |
|---------|------|---------|
| `no_collaboration_instructions_by_default` | 67-106 | 验证默认无协作指令 |
| `user_input_includes_collaboration_instructions_after_override` | 108-156 | OverrideTurnContext 后 UserInput 包含指令 |
| `collaboration_instructions_added_on_user_turn` | 158-203 | UserTurn 直接包含协作指令 |
| `override_then_next_turn_uses_updated_collaboration_instructions` | 205-253 | Override 后下一轮使用更新后的指令 |
| `user_turn_overrides_collaboration_instructions_after_override` | 255-320 | UserTurn 覆盖 Override 设置的指令 |
| `collaboration_mode_update_emits_new_instruction_message` | 322-404 | 协作模式更新时发出新指令消息 |
| `collaboration_mode_update_noop_does_not_append` | 406-485 | 相同指令重复设置不追加 |
| `collaboration_mode_update_emits_new_instruction_message_when_mode_changes` | 487-575 | 模式切换时发出新指令 |
| `collaboration_mode_update_noop_does_not_append_when_mode_is_unchanged` | 577-662 | 相同模式重复设置不追加 |
| `resume_replays_collaboration_instructions` | 664-738 | 会话恢复后重放协作指令 |
| `empty_collaboration_instructions_are_ignored` | 740-795 | 空指令被忽略 |

---

## 5. 依赖与外部交互

### 5.1 测试基础设施

#### 5.1.1 Mock Server（wiremock）

```rust
// 使用 wiremock 启动模拟服务器
let server = start_mock_server().await;

// 挂载 SSE 响应
let req = mount_sse_once(
    &server,
    sse(vec![ev_response_created("resp-1"), ev_completed("resp-1")]),
).await;
```

#### 5.1.2 TestCodex 构建器

```rust
// 位置: codex-rs/core/tests/common/test_codex.rs
pub struct TestCodexBuilder {
    config_mutators: Vec<Box<ConfigMutator>>,
    auth: CodexAuth,
    pre_build_hooks: Vec<Box<PreBuildHook>>,
    home: Option<Arc<TempDir>>,
    user_shell_override: Option<Shell>,
}

pub struct TestCodex {
    pub home: Arc<TempDir>,
    pub cwd: Arc<TempDir>,
    pub codex: Arc<CodexThread>,
    pub session_configured: SessionConfiguredEvent,
    pub config: Config,
    pub thread_manager: Arc<ThreadManager>,
}
```

### 5.2 网络跳过机制

```rust
// 位置: codex-rs/core/tests/common/lib.rs
#[macro_export]
macro_rules! skip_if_no_network {
    ($return_value:expr $(,)?) => {{
        if ::std::env::var($crate::sandbox_network_env_var()).is_ok() {
            println!(
                "Skipping test because it cannot execute when network is disabled in a Codex sandbox."
            );
            return $return_value;
        }
    }};
}
```

所有测试用例均使用 `skip_if_no_network!(Ok(()))` 开头，确保在无网络环境的沙箱中跳过测试。

### 5.3 相关测试文件

| 文件 | 关联性 |
|------|--------|
| `override_updates.rs` | 同样测试 `OverrideTurnContext` 操作，包含协作模式更新测试 |
| `resume.rs` | 测试会话恢复功能，`collaboration_instructions.rs` 中的 `resume_replays_collaboration_instructions` 是其扩展 |
| `model_switching.rs` | 测试模型切换，与协作模式切换有相似模式 |

---

## 6. 风险、边界与改进建议

### 6.1 当前风险点

#### 6.1.1 测试依赖网络

**风险**：所有测试都依赖 `skip_if_no_network!` 宏，在无网络环境中会被完全跳过。

**缓解**：这是预期行为，因为测试需要与模拟的 OpenAI API 服务器交互。

#### 6.1.2 硬编码模型名称

```rust
fn collab_mode_with_mode_and_instructions(...) -> CollaborationMode {
    CollaborationMode {
        mode,
        settings: Settings {
            model: "gpt-5.1".to_string(),  // 硬编码
            ...
        },
    }
}
```

**风险**：模型名称变更可能导致测试配置不匹配。

**建议**：使用测试配置中的默认模型或常量定义。

#### 6.1.3 并发测试风险

所有测试使用 `#[tokio::test(flavor = "multi_thread", worker_threads = 2)]`，虽然提高了测试速度，但可能引入并发相关问题。

### 6.2 边界情况

#### 6.2.1 已处理的边界

| 边界情况 | 处理测试 |
|---------|---------|
| 空指令字符串 | `empty_collaboration_instructions_are_ignored` |
| 相同指令重复设置 | `collaboration_mode_update_noop_does_not_append` |
| 相同模式重复设置 | `collaboration_mode_update_noop_does_not_append_when_mode_is_unchanged` |
| 模式切换 | `collaboration_mode_update_emits_new_instruction_message_when_mode_changes` |

#### 6.2.2 潜在未覆盖边界

1. **超长指令**：未测试超长协作指令的处理
2. **特殊字符**：未测试包含 XML 特殊字符的指令
3. **Unicode**：未测试非 ASCII 字符的指令
4. **并发更新**：未测试多线程并发设置协作模式

### 6.3 改进建议

#### 6.3.1 测试覆盖增强

```rust
// 建议添加：特殊字符处理测试
#[tokio::test]
async fn collaboration_instructions_with_special_xml_chars() -> Result<()> {
    let collab_text = "<script>alert('xss')</script>&\"'";
    // 验证正确转义或保留原样
}

// 建议添加：超长指令测试
#[tokio::test]
async fn collaboration_instructions_with_very_long_text() -> Result<()> {
    let collab_text = "x".repeat(10000);
    // 验证系统能处理长指令
}
```

#### 6.3.2 代码结构改进

当前测试文件有 795 行，建议按功能分组：

```
collaboration_instructions/
├── mod.rs              # 公共辅助函数
├── basic.rs            # 基础功能测试
├── override.rs         # OverrideTurnContext 相关
├── user_turn.rs        # UserTurn 相关
├── resume.rs           # 会话恢复相关
└── edge_cases.rs       # 边界情况
```

#### 6.3.3 文档改进

建议在每个测试函数头部添加更详细的注释：

```rust
/// Test: collaboration_mode_update_noop_does_not_append
/// 
/// Scenario: User sets the same collaboration mode twice via OverrideTurnContext
/// Expected: The collaboration instructions should only appear once in the request
/// Rationale: Prevents duplicate instructions that could confuse the model
#[tokio::test]
async fn collaboration_mode_update_noop_does_not_append() -> Result<()> { ... }
```

#### 6.3.4 性能优化

当前测试每个用例都启动新的 mock server 和 TestCodex，考虑：

1. 使用 `serial_test` crate 串行执行，共享单个实例
2. 或使用 `rstest` crate 的参数化测试减少重复代码

### 6.4 架构演进建议

当前协作模式指令通过字符串拼接 XML 标签实现，未来可考虑：

1. **结构化指令**：使用结构化类型替代字符串拼接
2. **版本控制**：为协作模式指令添加版本号
3. **增量更新**：支持指令的增量更新而非全量替换
4. **缓存机制**：缓存编译后的指令模板

---

## 7. 总结

`collaboration_instructions.rs` 是 Codex 核心测试套件中验证协作模式功能的关键文件。它通过 11 个全面的集成测试，覆盖了协作模式指令的注入、传播、持久化和边界情况。

该测试文件的设计体现了以下最佳实践：

1. **单一职责**：每个测试验证一个具体行为
2. **可重复性**：使用 mock server 确保测试可重复
3. **环境感知**：使用 `skip_if_no_network!` 适配不同环境
4. **断言清晰**：使用 `pretty_assertions` 提供清晰的失败信息

通过维护这组测试，可以确保协作模式功能在代码演进过程中保持稳定可靠。
