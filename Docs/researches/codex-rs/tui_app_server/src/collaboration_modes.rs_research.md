# collaboration_modes.rs 研究文档

## 场景与职责

`collaboration_modes.rs` 是 Codex TUI 应用服务器的协作模式管理模块，负责处理 AI 助手的工作模式（如 Plan 模式、Default 模式等）的筛选、查询和切换逻辑。该模块作为 ModelCatalog 的包装层，为 TUI 提供特定于 UI 的协作模式操作接口。

协作模式定义了 AI 助手的行为特征，包括：
- **Plan 模式**：专注于规划和设计，使用中等推理强度
- **Default 模式**：标准执行模式，使用默认配置
- 其他模式（如 Pair Programming、Execute）当前被过滤隐藏，保留供将来使用

## 功能点目的

### 1. 模式筛选与过滤
- **`filtered_presets`**：从 ModelCatalog 中筛选出 TUI 可见的协作模式
- 使用 `ModeKind::is_tui_visible()` 进行过滤
- 确保只有适合 TUI 展示的模式才会显示给用户

### 2. TUI 模式查询接口
- **`presets_for_tui`**：获取所有 TUI 可见的协作模式预设列表
- **`default_mask`**：获取默认协作模式掩码
  - 优先查找标记为 `ModeKind::Default` 的模式
  - 如果没有默认模式，返回列表中的第一个
- **`mask_for_kind`**：根据特定模式类型查找对应的掩码

### 3. 模式切换
- **`next_mask`**：循环切换到下一个协作模式
  - 支持在模式列表中循环遍历
  - 处理当前模式为 `None` 的情况（默认从第一个开始）

### 4. 便捷查询函数
- **`default_mode_mask`**：获取 Default 模式的掩码
- **`plan_mask`**：获取 Plan 模式的掩码

## 具体技术实现

### 数据结构

```rust
// 来自 codex_protocol::config_types
pub struct CollaborationModeMask {
    pub name: String,
    pub mode: Option<ModeKind>,
    pub model: Option<String>,
    pub reasoning_effort: Option<Option<ReasoningEffort>>,
    pub developer_instructions: Option<Option<String>>,
}

pub enum ModeKind {
    Default,
    Plan,
    PairProgramming,
    Execute,
    // ...
}
```

### 核心函数实现

#### 筛选函数
```rust
fn filtered_presets(model_catalog: &ModelCatalog) -> Vec<CollaborationModeMask> {
    model_catalog
        .list_collaboration_modes()
        .into_iter()
        .filter(|mask| mask.mode.is_some_and(ModeKind::is_tui_visible))
        .collect()
}
```

#### 默认模式查找
```rust
pub(crate) fn default_mask(model_catalog: &ModelCatalog) -> Option<CollaborationModeMask> {
    let presets = filtered_presets(model_catalog);
    presets
        .iter()
        .find(|mask| mask.mode == Some(ModeKind::Default))
        .cloned()
        .or_else(|| presets.into_iter().next())
}
```

#### 模式切换
```rust
pub(crate) fn next_mask(
    model_catalog: &ModelCatalog,
    current: Option<&CollaborationModeMask>,
) -> Option<CollaborationModeMask> {
    let presets = filtered_presets(model_catalog);
    if presets.is_empty() {
        return None;
    }
    let current_kind = current.and_then(|mask| mask.mode);
    let next_index = presets
        .iter()
        .position(|mask| mask.mode == current_kind)
        .map_or(0, |idx| (idx + 1) % presets.len());
    presets.get(next_index).cloned()
}
```

## 关键代码路径与文件引用

### 定义位置
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/collaboration_modes.rs`

### 调用方
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/chatwidget.rs`：
  - 使用 `next_mask` 处理模式切换（Shift+Tab）
  - 使用 `default_mask` 获取默认模式
  - 使用 `plan_mask` 获取 Plan 模式
  
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/chatwidget/tests.rs`：测试中使用

- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/footer.rs`：
  - 使用 `CollaborationModeIndicator` 枚举显示当前模式
  
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/slash_commands.rs`：
  - 使用模式相关功能处理 `/plan` 等命令
  
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`：
  - 处理模式切换快捷键
  
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/command_popup.rs`：
  - 模式相关的命令弹出框
  
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/mod.rs`：
  - 底部面板集成
  
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/model_catalog.rs`：
  - 提供 `list_collaboration_modes` 方法

### 模块声明
- 在 `lib.rs` 中声明为 `mod collaboration_modes;`

## 依赖与外部交互

### 外部依赖
- `codex_protocol::config_types::CollaborationModeMask`：协作模式掩码定义
- `codex_protocol::config_types::ModeKind`：模式类型枚举

### 内部模块交互
- `model_catalog::ModelCatalog`：提供底层模式列表

### 模式可见性常量
- `TUI_VISIBLE_COLLABORATION_MODES`：定义在 `codex_protocol` 中，控制哪些模式对 TUI 可见

## 风险、边界与改进建议

### 风险点

1. **模式列表为空**
   - 如果 `filtered_presets` 返回空列表，`default_mask` 和 `next_mask` 都会返回 `None`
   - 调用方需要正确处理 `None` 情况
   - **当前状态**：调用方（如 `chatwidget.rs`）已处理 `None` 情况

2. **模式标识依赖**
   - 使用 `ModeKind` 的相等性比较来识别模式
   - 如果协议层添加新模式，需要确保 `is_tui_visible` 正确配置

### 边界情况

1. **当前模式不在列表中**
   - `next_mask` 处理这种情况：如果当前模式不在过滤后的列表中，切换到第一个
   - 实现：`map_or(0, |idx| (idx + 1) % presets.len())`

2. **重复模式**
   - 假设 `ModelCatalog` 返回的模式列表中每种 `ModeKind` 只出现一次
   - 如果出现重复，`default_mask` 返回第一个匹配项

3. **模式可见性变化**
   - `is_tui_visible` 是运行时属性
   - 如果配置动态变化，模式列表可能不一致

### 改进建议

1. **缓存优化**
   - 当前每次调用都重新筛选列表
   - 建议：如果 `ModelCatalog` 不频繁变化，考虑缓存筛选结果

2. **错误处理增强**
   - 添加日志记录，当模式列表为空时发出警告
   - 帮助诊断配置问题

3. **模式切换方向**
   - 当前只有 `next_mask`（向前切换）
   - 建议：添加 `prev_mask` 支持双向切换

4. **模式描述信息**
   - 当前只返回 `CollaborationModeMask`
   - 建议：添加获取模式描述/帮助文本的函数，用于 UI 提示

5. **测试覆盖**
   - 当前无单元测试
   - 建议添加：
     - 空列表处理测试
     - 循环切换测试
     - 当前模式不在列表中的测试

6. **文档完善**
   - 添加模块级文档说明协作模式的概念
   - 说明与 `ModelCatalog` 的关系
