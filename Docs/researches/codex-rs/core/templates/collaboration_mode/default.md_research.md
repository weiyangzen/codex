# 研究文档：default.md 协作模式模板

## 场景与职责

`default.md` 是 Codex 协作模式系统的**默认回退模板**，用于定义当系统处于 Default 模式（非 Plan/Execute/Pair Programming 模式）时的行为准则。它是四个协作模式模板中最基础、最核心的一个，承担着以下关键职责：

1. **模式切换声明**：明确告知 AI 当前已进入 Default 模式，之前的 Plan 模式指令不再生效
2. **已知模式枚举**：通过占位符动态注入系统支持的所有协作模式名称
3. **工具可用性说明**：动态说明 `request_user_input` 工具在当前模式下的可用性
4. **提问策略指导**：根据配置决定 AI 在 Default 模式下应该如何向用户提问

该模板是**动态模板**，包含三个占位符需要在运行时替换：
- `{{KNOWN_MODE_NAMES}}` - 系统支持的协作模式名称列表
- `{{REQUEST_USER_INPUT_AVAILABILITY}}` - request_user_input 工具可用性说明
- `{{ASKING_QUESTIONS_GUIDANCE}}` - 提问策略指导

## 功能点目的

### 1. 模式状态管理
- **目的**：确保 AI 清楚当前所处的协作模式，避免模式混淆
- **机制**：通过 `<collaboration_mode>` XML 标签包装指令，在每次模式切换时注入到对话上下文
- **重要性**：防止 Plan 模式的"非变异探索"规则在 Default 模式下继续生效

### 2. 工具可用性动态配置
- **目的**：根据功能标志配置控制 `request_user_input` 工具的可用性
- **配置项**：`CollaborationModesConfig.default_mode_request_user_input`
- **影响**：决定 AI 在 Default 模式下是否可以使用结构化提问工具，还是只能使用纯文本提问

### 3. 用户交互策略指导
- **目的**：规范 AI 在 Default 模式下的提问行为
- **策略差异**：
  - 当 `request_user_input` 启用时：优先使用工具进行结构化提问
  - 当禁用时：使用纯文本直接提问，避免多选题形式

## 具体技术实现

### 关键流程

```
1. 模板加载 (编译时)
   ↓
   include_str!("../../templates/collaboration_mode/default.md")
   ↓
2. 占位符替换 (运行时)
   ↓
   default_mode_instructions() 函数
   - 替换 KNOWN_MODE_NAMES_PLACEHOLDER
   - 替换 REQUEST_USER_INPUT_AVAILABILITY_PLACEHOLDER  
   - 替换 ASKING_QUESTIONS_GUIDANCE_PLACEHOLDER
   ↓
3. DeveloperInstructions 生成
   ↓
   DeveloperInstructions::from_collaboration_mode()
   包装为: <collaboration_mode>{instructions}</collaboration_mode>
   ↓
4. 注入到对话上下文
```

### 数据结构

```rust
// 协作模式配置标志
pub struct CollaborationModesConfig {
    /// 在 Default 模式下启用 request_user_input
    pub default_mode_request_user_input: bool,
}

// 协作模式掩码（包含模板内容）
pub struct CollaborationModeMask {
    pub name: String,
    pub mode: Option<ModeKind>,
    pub model: Option<String>,
    pub reasoning_effort: Option<Option<ReasoningEffort>>,
    pub developer_instructions: Option<Option<String>>,  // 模板内容存储于此
}
```

### 占位符替换逻辑

```rust
fn default_mode_instructions(collaboration_modes_config: CollaborationModesConfig) -> String {
    let known_mode_names = format_mode_names(&TUI_VISIBLE_COLLABORATION_MODES);
    let request_user_input_availability = request_user_input_availability_message(
        ModeKind::Default,
        collaboration_modes_config.default_mode_request_user_input,
    );
    let asking_questions_guidance = asking_questions_guidance_message(
        collaboration_modes_config.default_mode_request_user_input,
    );
    
    COLLABORATION_MODE_DEFAULT
        .replace(KNOWN_MODE_NAMES_PLACEHOLDER, &known_mode_names)
        .replace(REQUEST_USER_INPUT_AVAILABILITY_PLACEHOLDER, &request_user_input_availability)
        .replace(ASKING_QUESTIONS_GUIDANCE_PLACEHOLDER, &asking_questions_guidance)
}
```

### 模式名称格式化规则

```rust
fn format_mode_names(modes: &[ModeKind]) -> String {
    match mode_names.as_slice() {
        [] => "none".to_string(),
        [mode_name] => (*mode_name).to_string(),
        [first, second] => format!("{first} and {second}"),
        [..] => mode_names.join(", "),
    }
}
```

## 关键代码路径与文件引用

### 核心实现文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/templates/collaboration_mode/default.md` | 模板源文件（本文件） |
| `codex-rs/core/src/models_manager/collaboration_mode_presets.rs` | 模板加载、占位符替换、预设生成 |
| `codex-rs/core/src/models_manager/collaboration_mode_presets_tests.rs` | 单元测试 |
| `codex-rs/core/src/models_manager/manager.rs` | ModelsManager 暴露 list_collaboration_modes() |
| `codex-rs/protocol/src/models.rs` | DeveloperInstructions::from_collaboration_mode() |

### 协议定义

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/protocol/src/protocol.rs` | COLLABORATION_MODE_OPEN_TAG/CLOSE_TAG 常量定义 |
| `codex-rs/protocol/src/config_types.rs` | ModeKind, CollaborationModeMask, CollaborationMode 类型定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | CollaborationModeListParams, CollaborationModeListResponse API 类型 |

### 消费端

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/collaboration_modes.rs` | TUI 协作模式过滤与选择逻辑 |
| `codex-rs/tui_app_server/src/collaboration_modes.rs` | TUI App Server 协作模式处理 |
| `codex-rs/tui/src/bottom_pane/footer.rs` | 底部状态栏模式指示器渲染 |
| `codex-rs/app-server/src/codex_message_processor.rs` | collaborationMode/list RPC 处理 |

### 测试文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/tests/suite/collaboration_instructions.rs` | 协作模式指令注入集成测试 |
| `codex-rs/app-server/tests/suite/v2/collaboration_mode_list.rs` | collaborationMode/list API 测试 |

## 依赖与外部交互

### 编译时依赖

1. **模板嵌入**：通过 `include_str!` 宏在编译时将模板文件内容嵌入到二进制中
   ```rust
   const COLLABORATION_MODE_DEFAULT: &str = 
       include_str!("../../templates/collaboration_mode/default.md");
   ```

2. **Bazel 构建**：BUILD.bazel 中显式导出模板文件作为编译数据
   ```starlark
   exports_files([
       "templates/collaboration_mode/default.md",
       "templates/collaboration_mode/plan.md",
   ])
   ```

### 运行时依赖

1. **配置系统**：依赖 `CollaborationModesConfig` 中的 `default_mode_request_user_input` 标志
2. **模式类型**：依赖 `ModeKind` 枚举和 `TUI_VISIBLE_COLLABORATION_MODES` 常量
3. **指令注入**：依赖 `DeveloperInstructions` 类型将模板包装为 XML 格式

### API 交互

1. **v2 API**：通过 `collaborationMode/list` 方法暴露协作模式预设
2. **类型转换**：`CoreCollaborationModeMask` ↔ `CollaborationModeMask` 协议转换

## 风险、边界与改进建议

### 已知风险

1. **占位符未替换风险**：如果代码逻辑遗漏某个占位符的替换，AI 会看到原始模板标记（如 `{{KNOWN_MODE_NAMES}}`），造成困惑
   - 缓解：单元测试 `default_mode_instructions_replace_mode_names_placeholder` 验证所有占位符都被替换

2. **模式名称不一致**：`TUI_VISIBLE_COLLABORATION_MODES` 只包含 `[Default, Plan]`，但模板中可能提到其他模式
   - 注意：Execute 和 PairProgramming 模式在 TUI 中被隐藏（`is_tui_visible()` 返回 false）

3. **空指令处理**：如果替换后的指令为空字符串，会被过滤掉不注入（`filter(|instructions| !instructions.is_empty())`）

### 边界情况

| 场景 | 行为 |
|-----|------|
| 空模式列表 | `format_mode_names` 返回 `"none"` |
| 单模式 | 直接返回模式名称 |
| 双模式 | 使用 `"X and Y"` 格式 |
| 三模式及以上 | 使用逗号分隔列表 |
| request_user_input 禁用 | 指导 AI 使用纯文本提问，不使用工具 |

### 改进建议

1. **模板验证**：在编译时验证模板中是否包含未定义的占位符
2. **国际化支持**：当前模板为英文硬编码，可考虑多语言支持
3. **动态模板加载**：当前为编译时嵌入，未来可考虑运行时热更新模板
4. **模式文档链接**：在模板中添加指向模式详细文档的链接，帮助 AI 更好理解模式差异
5. **版本控制**：在模板中嵌入版本信息，便于调试和追踪模板变更

### 相关 TODO

- `codex-rs/core/src/models_manager/manager.rs:277`：`get_default_model` 应该仅对 core 可见并随 session_configured 事件发送
- 考虑将 Execute 和 PairProgramming 模式重新加入 TUI 可见模式列表
