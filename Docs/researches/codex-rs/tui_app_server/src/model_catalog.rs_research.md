# model_catalog.rs 深入研究

## 场景与职责

`model_catalog.rs` 是 Codex TUI 应用服务器中负责**模型目录和协作模式管理**的模块。它作为模型配置的中心化抽象层，连接底层模型管理器和上层UI组件。

### 核心职责

1. **模型目录封装**：提供统一的模型列表查询接口
2. **协作模式预设**：管理内置的协作模式（Plan、Default）及其配置
3. **模板化指令生成**：动态生成开发者指令，替换占位符为实际配置

### 架构位置

```
codex_core::models_manager
    ├── manager.rs          # 底层模型管理
    ├── model_presets.rs    # 模型预设定义
    └── collaboration_mode_presets.rs  # 协作模式预设（core层）
            ↑
codex_tui_app_server::model_catalog    # 本模块：TUI适配层
            ↑
codex_tui_app_server::collaboration_modes  # 协作模式UI逻辑
            ↑
codex_tui_app_server::chatwidget       # 主UI组件
```

## 功能点目的

### 1. ModelCatalog 结构

```rust
#[derive(Debug, Clone)]
pub(crate) struct ModelCatalog {
    models: Vec<ModelPreset>,
    collaboration_modes_config: CollaborationModesConfig,
}
```

**设计目的**：
- 封装模型列表，提供类型安全的访问接口
- 隔离协作模式配置的复杂性
- 支持配置驱动的行为变更（如 `default_mode_request_user_input`）

### 2. 模型列表接口

```rust
pub(crate) fn try_list_models(&self) -> Result<Vec<ModelPreset>, Infallible>
```

- 目前为简单代理，未来可扩展过滤/排序逻辑
- 使用 `Infallible` 表示当前不会失败，保留错误处理扩展点

### 3. 协作模式列表

```rust
pub(crate) fn list_collaboration_modes(&self) -> Vec<CollaborationModeMask>
```

返回内置的协作模式预设：
- **Plan模式**：规划专用模式，固定使用 Medium reasoning effort
- **Default模式**：默认编码模式，支持配置化的 `request_user_input` 可用性

### 4. 模板化指令系统

```rust
const COLLABORATION_MODE_PLAN: &str = include_str!("../../core/templates/collaboration_mode/plan.md");
const COLLABORATION_MODE_DEFAULT: &str = include_str!("../../core/templates/collaboration_mode/default.md");

const KNOWN_MODE_NAMES_PLACEHOLDER: &str = "{{KNOWN_MODE_NAMES}}";
const REQUEST_USER_INPUT_AVAILABILITY_PLACEHOLDER: &str = "{{REQUEST_USER_INPUT_AVAILABILITY}}";
const ASKING_QUESTIONS_GUIDANCE_PLACEHOLDER: &str = "{{ASKING_QUESTIONS_GUIDANCE}}";
```

**模板替换流程**：
1. 加载模板文件（编译时嵌入）
2. 替换 `{{KNOWN_MODE_NAMES}}` 为可见模式名称列表
3. 替换 `{{REQUEST_USER_INPUT_AVAILABILITY}}` 为工具可用性说明
4. 替换 `{{ASKING_QUESTIONS_GUIDANCE}}` 为提问指导

## 具体技术实现

### 1. Plan 模式预设

```rust
fn plan_preset() -> CollaborationModeMask {
    CollaborationModeMask {
        name: ModeKind::Plan.display_name().to_string(),
        mode: Some(ModeKind::Plan),
        model: None,
        reasoning_effort: Some(Some(ReasoningEffort::Medium)),
        developer_instructions: Some(Some(COLLABORATION_MODE_PLAN.to_string())),
    }
}
```

**特点**：
- 固定使用 Medium reasoning effort
- 使用静态模板指令（无动态替换）

### 2. Default 模式预设

```rust
fn default_preset(collaboration_modes_config: CollaborationModesConfig) -> CollaborationModeMask {
    CollaborationModeMask {
        name: ModeKind::Default.display_name().to_string(),
        mode: Some(ModeKind::Default),
        model: None,
        reasoning_effort: None,
        developer_instructions: Some(Some(default_mode_instructions(collaboration_modes_config))),
    }
}
```

**特点**：
- reasoning_effort 不固定，继承用户配置
- 开发者指令动态生成，基于配置替换占位符

### 3. 模式名称格式化

```rust
fn format_mode_names(modes: &[ModeKind]) -> String {
    let mode_names: Vec<&str> = modes.iter().map(|mode| mode.display_name()).collect();
    match mode_names.as_slice() {
        [] => "none".to_string(),
        [mode_name] => (*mode_name).to_string(),
        [first, second] => format!("{first} and {second}"),
        [..] => mode_names.join(", "),
    }
}
```

**英语语法处理**：
- 空列表 → "none"
- 单个 → 直接显示
- 两个 → "X and Y"
- 多个 → "X, Y, Z"（逗号分隔）

### 4. request_user_input 可用性消息

```rust
fn request_user_input_availability_message(
    mode: ModeKind,
    default_mode_request_user_input: bool,
) -> String {
    let mode_name = mode.display_name();
    if mode.allows_request_user_input()
        || (default_mode_request_user_input && mode == ModeKind::Default)
    {
        format!("The `request_user_input` tool is available in {mode_name} mode.")
    } else {
        format!(
            "The `request_user_input` tool is unavailable in {mode_name} mode. If you call it while in {mode_name} mode, it will return an error."
        )
    }
}
```

**逻辑**：
- Plan 模式始终允许（`allows_request_user_input()` 返回 true）
- Default 模式取决于配置标志 `default_mode_request_user_input`

## 关键代码路径与文件引用

### 直接依赖

| 文件/模块 | 依赖类型 | 用途 |
|-----------|----------|------|
| `codex_core::models_manager::collaboration_mode_presets::CollaborationModesConfig` | 外部crate | 协作模式配置标志 |
| `codex_protocol::config_types::CollaborationModeMask` | 外部crate | 协作模式掩码类型 |
| `codex_protocol::config_types::ModeKind` | 外部crate | 模式种类枚举 |
| `codex_protocol::config_types::TUI_VISIBLE_COLLABORATION_MODES` | 外部crate | TUI可见模式列表 |
| `codex_protocol::openai_models::ModelPreset` | 外部crate | 模型预设类型 |
| `codex_protocol::openai_models::ReasoningEffort` | 外部crate | 推理努力级别 |
| `codex-rs/core/templates/collaboration_mode/plan.md` | 资源文件 | Plan模式模板 |
| `codex-rs/core/templates/collaboration_mode/default.md` | 资源文件 | Default模式模板 |

### 调用方

| 文件 | 使用方式 |
|------|----------|
| `collaboration_modes.rs` | 导入 `ModelCatalog`，用于过滤和选择协作模式 |
| `chatwidget.rs` | 导入 `ModelCatalog`，用于模型列表查询 |
| `app.rs` | 通过 `chatwidget` 间接使用 |

### 协作模式过滤

```rust
// collaboration_modes.rs
fn filtered_presets(model_catalog: &ModelCatalog) -> Vec<CollaborationModeMask> {
    model_catalog
        .list_collaboration_modes()
        .into_iter()
        .filter(|mask| mask.mode.is_some_and(ModeKind::is_tui_visible))
        .collect()
}
```

只返回 `is_tui_visible()` 为 true 的模式（目前为 Plan 和 Default）。

## 依赖与外部交互

### 外部crate依赖

```rust
use codex_core::models_manager::collaboration_mode_presets::CollaborationModesConfig;
use codex_protocol::config_types::CollaborationModeMask;
use codex_protocol::config_types::ModeKind;
use codex_protocol::config_types::TUI_VISIBLE_COLLABORATION_MODES;
use codex_protocol::openai_models::ModelPreset;
use codex_protocol::openai_models::ReasoningEffort;
```

### 配置常量

```rust
// protocol/src/config_types.rs
pub const TUI_VISIBLE_COLLABORATION_MODES: [ModeKind; 2] = [ModeKind::Default, ModeKind::Plan];

impl ModeKind {
    pub const fn is_tui_visible(self) -> bool {
        matches!(self, Self::Plan | Self::Default)
    }
    
    pub const fn allows_request_user_input(self) -> bool {
        matches!(self, Self::Plan)
    }
}
```

### 与core层协作

```rust
// core/src/models_manager/collaboration_mode_presets.rs
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct CollaborationModesConfig {
    pub default_mode_request_user_input: bool,
}
```

配置标志控制 Default 模式的行为。

## 风险、边界与改进建议

### 已知风险

1. **模板硬编码**：模板路径和占位符名称硬编码，修改需要同步更新多处
   ```rust
   const COLLABORATION_MODE_DEFAULT: &str =
       include_str!("../../core/templates/collaboration_mode/default.md");
   // 路径硬编码，重构时容易遗漏
   ```

2. **英语特定格式**：`format_mode_names` 使用英语语法（"and" 连接），国际化支持有限

3. **模板替换简单**：使用 `String::replace`，如果占位符在模板中出现多次会被全部替换

### 边界情况

| 场景 | 处理方式 |
|------|----------|
| 空模型列表 | `try_list_models` 返回空Vec，调用方处理 |
| 配置标志变化 | 需要重新创建 `ModelCatalog` 实例 |
| 模板文件缺失 | 编译时 `include_str!` 会panic |
| 未知模式种类 | `ModeKind::is_tui_visible()` 过滤掉 |

### 改进建议

1. **国际化支持**：
   - 将模式名称格式化和消息模板化，支持多语言
   - 使用 `fluent` 或类似框架管理本地化字符串

2. **模板系统增强**：
   - 使用专用模板引擎（如 `handlebars` 或 `tera`）替代简单字符串替换
   - 添加模板验证，确保所有占位符都被替换

3. **动态配置**：
   - 支持运行时重新加载配置，无需重启TUI
   - 添加配置变更通知机制

4. **扩展性**：
   - 支持用户自定义协作模式
   - 支持从配置文件加载额外模式

5. **测试覆盖**：
   - 当前文件无测试，建议添加：
     - 模板替换正确性测试
     - 配置标志影响测试
     - 边界情况测试（空列表、单元素等）

6. **文档完善**：
   - 添加模板文件格式文档
   - 说明占位符含义和替换规则

### 相关文件

| 文件 | 关系 |
|------|------|
| `core/templates/collaboration_mode/plan.md` | Plan模式模板 |
| `core/templates/collaboration_mode/default.md` | Default模式模板 |
| `core/src/models_manager/collaboration_mode_presets.rs` | Core层协作模式配置 |
| `protocol/src/config_types.rs` | 协作模式类型定义 |
| `protocol/src/openai_models.rs` | 模型相关类型 |
| `collaboration_modes.rs` | 本模块的主要调用方 |
