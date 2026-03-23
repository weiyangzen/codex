# request_user_input.rs 研究文档

## 场景与职责

`request_user_input.rs` 实现了 Codex 的用户输入请求工具处理器，允许模型向用户提出 1-3 个简短问题并等待响应。该工具仅在特定协作模式下可用（主要是 Plan 模式），用于在任务执行过程中获取用户澄清或决策。

## 功能点目的

### 1. 用户输入请求工具 (request_user_input)
- **交互式澄清**: 允许模型在不确定时向用户提问
- **模式限制**: 仅在特定协作模式下可用（Plan 模式，或 Default 模式下启用特性）
- **结构化问题**: 支持多选题格式，每个问题必须有非空选项

### 2. 模式可用性控制
- **Plan 模式**: 默认可用
- **Default 模式**: 可通过配置启用
- **Execute/PairProgramming 模式**: 不可用

### 3. 问题格式处理
- **选项验证**: 确保每个问题都有非空选项列表
- **Other 支持**: 自动设置 `is_other = true`，允许用户自由输入
- **问题数量限制**: 1-3 个问题

## 具体技术实现

### 核心数据结构

```rust
pub struct RequestUserInputHandler {
    pub default_mode_request_user_input: bool,  // 特性开关
}

// 来自 codex_protocol 的参数类型
pub struct RequestUserInputArgs {
    pub questions: Vec<UserInputQuestion>,
}

pub struct UserInputQuestion {
    pub question: String,
    pub options: Option<Vec<String>>,  // 必须非空
    pub is_other: bool,  // 自动设置为 true
}
```

### 模式可用性检查

```rust
fn request_user_input_is_available(
    mode: ModeKind,
    default_mode_request_user_input: bool
) -> bool {
    mode.allows_request_user_input()
        || (default_mode_request_user_input && mode == ModeKind::Default)
}

pub(crate) fn request_user_input_unavailable_message(
    mode: ModeKind,
    default_mode_request_user_input: bool,
) -> Option<String> {
    if request_user_input_is_available(mode, default_mode_request_user_input) {
        None
    } else {
        let mode_name = mode.display_name();
        Some(format!(
            "request_user_input is unavailable in {mode_name} mode"
        ))
    }
}
```

### 工具描述生成

```rust
pub(crate) fn request_user_input_tool_description(default_mode_request_user_input: bool) -> String {
    let allowed_modes = format_allowed_modes(default_mode_request_user_input);
    format!(
        "Request user input for one to three short questions and wait for the response. This tool is only available in {allowed_modes}."
    )
}

fn format_allowed_modes(default_mode_request_user_input: bool) -> String {
    let mode_names: Vec<&str> = TUI_VISIBLE_COLLABORATION_MODES
        .into_iter()
        .filter(|mode| request_user_input_is_available(*mode, default_mode_request_user_input))
        .map(ModeKind::display_name)
        .collect();

    match mode_names.as_slice() {
        [] => "no modes".to_string(),
        [mode] => format!("{mode} mode"),
        [first, second] => format!("{first} or {second} mode"),
        [..] => format!("modes: {}", mode_names.join(",")),
    }
}
```

### Handler 实现

```rust
#[async_trait]
impl ToolHandler for RequestUserInputHandler {
    type Output = FunctionToolOutput;

    fn kind(&self) -> ToolKind {
        ToolKind::Function
    }

    async fn handle(&self, invocation: ToolInvocation) -> Result<Self::Output, FunctionCallError> {
        let ToolInvocation {
            session,
            turn,
            call_id,
            payload,
            ..
        } = invocation;

        // 1. 提取 Function payload
        let arguments = match payload {
            ToolPayload::Function { arguments } => arguments,
            _ => return Err(FunctionCallError::RespondToModel(
                "request_user_input handler received unsupported payload".to_string()
            )),
        };

        // 2. 检查模式可用性
        let mode = session.collaboration_mode().await.mode;
        if let Some(message) =
            request_user_input_unavailable_message(mode, self.default_mode_request_user_input)
        {
            return Err(FunctionCallError::RespondToModel(message));
        }

        // 3. 解析参数
        let mut args: RequestUserInputArgs = parse_arguments(&arguments)?;

        // 4. 验证选项非空
        let missing_options = args
            .questions
            .iter()
            .any(|question| question.options.as_ref().is_none_or(Vec::is_empty));
        if missing_options {
            return Err(FunctionCallError::RespondToModel(
                "request_user_input requires non-empty options for every question".to_string()
            ));
        }

        // 5. 设置 is_other = true
        for question in &mut args.questions {
            question.is_other = true;
        }

        // 6. 发送请求并等待响应
        let response = session
            .request_user_input(turn.as_ref(), call_id, args)
            .await
            .ok_or_else(|| {
                FunctionCallError::RespondToModel(
                    "request_user_input was cancelled before receiving a response".to_string()
                )
            })?;

        // 7. 序列化响应
        let content = serde_json::to_string(&response).map_err(|err| {
            FunctionCallError::Fatal(format!(
                "failed to serialize request_user_input response: {err}"
            ))
        })?;

        Ok(FunctionToolOutput::from_text(content, Some(true)))
    }
}
```

## 关键代码路径与文件引用

### 本文件位置
`codex-rs/core/src/tools/handlers/request_user_input.rs`

### 配套测试文件
`codex-rs/core/src/tools/handlers/request_user_input_tests.rs`

### 依赖模块
```rust
use codex_protocol::config_types::ModeKind;
use codex_protocol::config_types::TUI_VISIBLE_COLLABORATION_MODES;
use codex_protocol::request_user_input::RequestUserInputArgs;
use crate::tools::handlers::parse_arguments;
```

### 调用路径
1. 模型调用 `request_user_input` 工具
2. `RequestUserInputHandler::handle` 接收调用
3. 检查当前协作模式是否允许使用该工具
4. 解析并验证参数（选项非空）
5. 调用 `session.request_user_input()` 发送请求
6. 用户通过客户端 UI 回答问题
7. 返回答案给模型

## 依赖与外部交互

### 外部模块依赖
| 模块 | 用途 |
|-----|------|
| `codex_protocol::config_types::ModeKind` | 协作模式枚举 |
| `codex_protocol::config_types::TUI_VISIBLE_COLLABORATION_MODES` | 可见模式列表 |
| `codex_protocol::request_user_input` | 请求/响应类型 |
| `crate::tools::handlers::parse_arguments` | 参数解析 |

### 会话交互
- 调用 `session.collaboration_mode()` 获取当前模式
- 调用 `session.request_user_input()` 发送输入请求
- 等待用户响应（可能长时间阻塞）

### 协作模式
| 模式 | 默认可用性 | 说明 |
|-----|----------|------|
| Plan | ✅ 可用 | 计划模式默认可用 |
| Default | ❌ 禁用（可配置）| 需启用 `default_mode_request_user_input` |
| Execute | ❌ 禁用 | 执行模式不可用 |
| PairProgramming | ❌ 禁用 | 结对编程模式不可用 |

## 风险、边界与改进建议

### 潜在风险
1. **模式检查绕过**: 如果 `default_mode_request_user_input` 配置不当，可能在不当模式下启用
2. **无限等待**: 用户可能长时间不响应，导致会话挂起
3. **问题滥用**: 模型可能频繁提问，打断用户工作流

### 边界情况
1. **空问题列表**: 协议层可能允许，但无实际意义
2. **超过3个问题**: 协议层可能允许，但工具描述限制为 1-3 个
3. **空选项列表**: 已处理，返回错误
4. **用户取消**: 返回取消错误
5. **序列化失败**: 使用 `FunctionCallError::Fatal` 处理

### 改进建议

1. **添加问题数量验证**:
   ```rust
   if args.questions.is_empty() || args.questions.len() > 3 {
       return Err(FunctionCallError::RespondToModel(
           "request_user_input requires 1-3 questions".to_string()
       ));
   }
   ```

2. **添加问题长度限制**:
   ```rust
   const MAX_QUESTION_LENGTH: usize = 500;
   for question in &args.questions {
       if question.question.len() > MAX_QUESTION_LENGTH {
           return Err(...);
       }
   }
   ```

3. **添加请求频率限制**:
   ```rust
   // 防止模型频繁提问
   if turn.user_input_request_count() >= MAX_REQUESTS_PER_TURN {
       return Err(FunctionCallError::RespondToModel(
           "Maximum user input requests reached for this turn".to_string()
       ));
   }
   ```

4. **改进取消处理**:
   ```rust
   // 区分用户取消和系统取消
   let response = session.request_user_input(...).await;
   match response {
       Some(resp) => ...,  // 正常响应
       None => {
           // 检查是否是用户主动取消
           if session.was_cancelled_by_user() {
               return Err(FunctionCallError::RespondToModel(
                   "User cancelled the input request".to_string()
               ));
           }
           ...
       }
   }
   ```

5. **添加超时处理**:
   ```rust
   use tokio::time::{timeout, Duration};
   
   let response = timeout(
       Duration::from_secs(300),  // 5分钟超时
       session.request_user_input(turn.as_ref(), call_id, args)
   ).await;
   ```

### 测试覆盖
测试文件 `request_user_input_tests.rs` 已覆盖：
- 模式默认可用性（Plan 可用，其他禁用）
- `default_mode_request_user_input` 特性开关
- 工具描述生成

建议补充：
- 参数解析错误
- 空选项验证
- 取消处理
- 序列化错误

### 设计观察
- 该工具主要用于 Plan 模式，与计划制定流程集成
- `is_other = true` 的设计允许用户自由输入，不限于预设选项
- 工具描述动态生成，反映当前配置状态
