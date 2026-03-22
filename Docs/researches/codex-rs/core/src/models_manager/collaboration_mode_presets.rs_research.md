# collaboration_mode_presets.rs 研究文档

## 场景与职责

`collaboration_mode_presets.rs` 定义了 Codex CLI 的协作模式（Collaboration Mode）预设系统。协作模式是一种运行时行为配置机制，用于控制 AI 助手在不同工作场景下的行为方式：

1. **Plan 模式**：专注于规划和设计，禁止执行修改性操作，支持多轮对话澄清需求
2. **Default 模式**：标准的代码执行模式，支持工具调用和文件修改

该模块的核心职责是将这些模式配置转换为结构化的 `CollaborationModeMask`，供后续系统注入到模型的开发者消息（developer instructions）中。

## 功能点目的

### 1. 内置协作模式预设生成 (`builtin_collaboration_mode_presets`)
- **目的**：根据配置生成 Plan 和 Default 两种内置模式的预设
- **输入**：`CollaborationModesConfig`（功能开关配置）
- **输出**：`Vec<CollaborationModeMask>` - 模式掩码列表

### 2. Plan 模式预设 (`plan_preset`)
- **固定配置**：
  - 名称："Plan"
  - 模式：`ModeKind::Plan`
  - 推理力度：`ReasoningEffort::Medium`
  - 开发者指令：加载自 `templates/collaboration_mode/plan.md`

### 3. Default 模式预设 (`default_preset`)
- **动态配置**：
  - 名称："Default"
  - 模式：`ModeKind::Default`
  - 开发者指令：基于模板动态生成，支持功能开关
- **模板变量替换**：
  - `{{KNOWN_MODE_NAMES}}` → 可见模式名称列表
  - `{{REQUEST_USER_INPUT_AVAILABILITY}}` → 用户输入工具可用性说明
  - `{{ASKING_QUESTIONS_GUIDANCE}}` → 提问指导文本

### 4. 模式名称格式化 (`format_mode_names`)
- **目的**：将模式列表格式化为人类可读的字符串
- **示例**：`[Plan, Default]` → "Plan and Default"

## 具体技术实现

### 关键数据结构

```rust
/// 协作模式功能开关配置
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct CollaborationModesConfig {
    /// 在 Default 模式下启用 request_user_input 工具
    pub default_mode_request_user_input: bool,
}

/// 模式掩码（来自 codex_protocol）
pub struct CollaborationModeMask {
    pub name: String,
    pub mode: Option<ModeKind>,
    pub model: Option<String>,
    pub reasoning_effort: Option<Option<ReasoningEffort>>,
    pub developer_instructions: Option<Option<String>>,
}
```

### 模板系统

#### 模板文件
| 文件路径 | 用途 |
|----------|------|
| `templates/collaboration_mode/plan.md` | Plan 模式完整指令 |
| `templates/collaboration_mode/default.md` | Default 模式模板（含占位符） |

#### 占位符常量
```rust
const KNOWN_MODE_NAMES_PLACEHOLDER: &str = "{{KNOWN_MODE_NAMES}}";
const REQUEST_USER_INPUT_AVAILABILITY_PLACEHOLDER: &str = "{{REQUEST_USER_INPUT_AVAILABILITY}}";
const ASKING_QUESTIONS_GUIDANCE_PLACEHOLDER: &str = "{{ASKING_QUESTIONS_GUIDANCE}}";
```

### 核心流程

#### Default 模式指令生成流程
```
1. 加载模板文件（compile-time include_str）
2. 获取可见模式名称列表（TUI_VISIBLE_COLLABORATION_MODES）
3. 根据配置生成 request_user_input 可用性文本
4. 根据配置生成提问指导文本
5. 字符串替换填充模板
6. 返回填充后的指令
```

#### 可用性消息生成逻辑
```rust
fn request_user_input_availability_message(mode: ModeKind, enabled: bool) -> String {
    if mode.allows_request_user_input() || (enabled && mode == ModeKind::Default) {
        format!("The `request_user_input` tool is available in {mode_name} mode.")
    } else {
        format!("The `request_user_input` tool is unavailable in {mode_name} mode...")
    }
}
```

## 关键代码路径与文件引用

### 内部依赖
| 路径 | 用途 |
|------|------|
| `codex_protocol::config_types::CollaborationModeMask` | 模式掩码结构 |
| `codex_protocol::config_types::ModeKind` | 模式类型枚举 |
| `codex_protocol::config_types::TUI_VISIBLE_COLLABORATION_MODES` | 可见模式常量 |
| `codex_protocol::openai_models::ReasoningEffort` | 推理力度枚举 |

### 模板文件
| 路径 | 内容 |
|------|------|
| `codex-rs/core/templates/collaboration_mode/plan.md` | Plan 模式完整指令（128行） |
| `codex-rs/core/templates/collaboration_mode/default.md` | Default 模式模板（11行） |

### 外部调用方
| 路径 | 调用方法 | 用途 |
|------|----------|------|
| `manager.rs:266` | `builtin_collaboration_mode_presets` | 获取协作模式列表 |

### 可见模式定义
```rust
// 来自 codex_protocol::config_types
pub const TUI_VISIBLE_COLLABORATION_MODES: [ModeKind; 2] = [ModeKind::Default, ModeKind::Plan];
```

## 依赖与外部交互

### 外部 Crate 依赖
- 无直接外部 crate 依赖（仅使用标准库和协议类型）

### 协议类型依赖
- `codex_protocol::config_types`：协作模式相关类型
- `codex_protocol::openai_models`：推理力度类型

### 编译时资源嵌入
```rust
const COLLABORATION_MODE_PLAN: &str = include_str!("../../templates/collaboration_mode/plan.md");
const COLLABORATION_MODE_DEFAULT: &str = include_str!("../../templates/collaboration_mode/default.md");
```

## 风险、边界与改进建议

### 已知风险

1. **模板与代码耦合**
   - 风险：模板文件修改后需重新编译才能生效
   - 现状：使用 `include_str!` 编译时嵌入
   - 建议：考虑支持运行时模板覆盖，便于用户自定义

2. **占位符替换脆弱性**
   - 风险：模板中占位符拼写错误会导致替换失败
   - 现状：测试覆盖占位符替换（`default_mode_instructions_replace_mode_names_placeholder`）
   - 建议：添加编译时占位符校验或模板语法检查

3. **模式硬编码**
   - 风险：新增模式需要修改此文件
   - 现状：仅支持 Plan 和 Default 两种内置模式
   - 建议：考虑插件化架构支持自定义模式

### 边界条件

| 场景 | 行为 |
|------|------|
| 空模式列表 | `format_mode_names` 返回 "none" |
| 单模式列表 | 直接返回模式名称 |
| 双模式列表 | 使用 "X and Y" 格式 |
| 三模式及以上 | 使用逗号分隔列表 |

### 改进建议

1. **模板验证**
   ```rust
   // 建议：编译时验证所有占位符都被替换
   const_assert!(!DEFAULT_MODE_INSTRUCTIONS.contains("{{"));
   ```

2. **国际化支持**
   - 当前模板为英文，考虑支持多语言模板
   - 可根据系统语言自动选择模板文件

3. **用户自定义模式**
   - 支持从配置文件加载自定义模式模板
   - 允许用户覆盖内置模式指令

4. **模式版本控制**
   - 为模式指令添加版本号
   - 支持模式指令的平滑升级

5. **动态模式发现**
   - 扫描模板目录自动发现可用模式
   - 减少新增模式的代码修改

### 测试覆盖

测试文件：`collaboration_mode_presets_tests.rs`

| 测试用例 | 覆盖场景 |
|----------|----------|
| `preset_names_use_mode_display_names` | 预设名称与模式显示名称一致 |
| `default_mode_instructions_replace_mode_names_placeholder` | 所有占位符被正确替换 |
| `default_mode_instructions_use_plain_text_questions_when_feature_disabled` | 功能关闭时的回退行为 |

### 相关文档

- Plan 模式模板：`templates/collaboration_mode/plan.md`（详细的行为规范）
- Default 模式模板：`templates/collaboration_mode/default.md`（简洁的模板框架）
