# Status Line Setup View - Runtime Preview Values Research Document

## 场景与职责

`StatusLineSetupView` 是一个状态栏配置视图，允许用户自定义底部状态栏显示的内容项。它提供了一个交互式选择器，用户可以选择哪些信息项显示在状态栏中，以及它们的显示顺序。

### 核心职责
- 提供状态栏项目的选择界面
- 支持项目启用/禁用状态的切换
- 支持项目排序（左右箭头移动）
- 实时预览配置后的状态栏效果
- 将用户配置持久化到应用设置

## 功能点目的

### 1. 状态栏项目选择
- **目的**：让用户决定哪些信息应该显示在状态栏
- **项目类型**：模型名称、当前目录、Git 分支、上下文使用情况、使用限制等
- **实现**：使用 `MultiSelectPicker` 组件，支持复选框式选择

### 2. 项目排序
- **目的**：允许用户自定义信息项的显示顺序
- **交互**：使用左右箭头键移动选中项目
- **实现**：通过 `enable_ordering()` 启用排序功能

### 3. 实时预览
- **目的**：让用户在确认前看到配置效果
- **实现**：使用 `StatusLinePreviewData` 提供运行时值进行预览渲染
- **优势**：避免反复试错，提升用户体验

### 4. 配置持久化
- **目的**：保存用户的个性化配置
- **事件**：确认时发送 `AppEvent::StatusLineSetup`，取消时发送 `AppEvent::StatusLineSetupCancelled`

## 具体技术实现

### 数据结构

#### StatusLineItem（状态栏项目枚举）
```rust
#[derive(EnumIter, EnumString, Display, Debug, Clone, Eq, PartialEq, Ord, PartialOrd)]
#[strum(serialize_all = "kebab_case")]
pub(crate) enum StatusLineItem {
    ModelName,           // 当前模型名称
    ModelWithReasoning,  // 带推理级别的模型名称
    CurrentDir,          // 当前工作目录
    ProjectRoot,         // 项目根目录
    GitBranch,           // Git 分支名称
    ContextRemaining,    // 上下文窗口剩余百分比
    ContextUsed,         // 上下文窗口已使用百分比
    FiveHourLimit,       // 5小时使用限制剩余
    WeeklyLimit,         // 每周使用限制剩余
    CodexVersion,        // Codex 应用版本
    ContextWindowSize,   // 上下文窗口总大小
    UsedTokens,          // 会话中使用的token数
    TotalInputTokens,    // 总输入token数
    TotalOutputTokens,   // 总输出token数
    SessionId,           // 当前会话ID
    FastMode,            // 快速模式是否激活
}
```

#### StatusLinePreviewData（预览数据）
```rust
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub(crate) struct StatusLinePreviewData {
    values: BTreeMap<StatusLineItem, String>,
}
```

#### StatusLineSetupView（配置视图）
```rust
pub(crate) struct StatusLineSetupView {
    picker: MultiSelectPicker,  // 底层多选选择器
}
```

### 关键方法

#### `new()` 构造函数
```rust
pub(crate) fn new(
    status_line_items: Option<&[String]>,    // 当前配置的项目ID列表
    preview_data: StatusLinePreviewData,      // 运行时预览数据
    app_event_tx: AppEventSender,            // 事件发送器
) -> Self
```

**初始化逻辑**：
1. 如果有现有配置，按顺序创建已启用的项目
2. 遍历所有 `StatusLineItem` 枚举值，添加未使用的项目（禁用状态）
3. 配置 `MultiSelectPicker` 的标题、说明、指令
4. 启用排序功能 (`enable_ordering()`)
5. 设置预览回调 (`on_preview`)
6. 设置确认和取消回调

#### `line_for_items()` - 预览行生成
```rust
fn line_for_items(&self, items: &[MultiSelectItem]) -> Option<Line<'static>> {
    let preview = items
        .iter()
        .filter(|item| item.enabled)
        .filter_map(|item| item.id.parse::<StatusLineItem>().ok())
        .filter_map(|item| self.values.get(&item).cloned())
        .collect::<Vec<_>>()
        .join(" · ");
    // ...
}
```

### 渲染布局
```
┌──────────────────────────────────────────────────────────────────────┐
│  Configure Status Line                                                │
│  Select which items to display in the status line.                    │
│                                                                       │
│  Type to search                                                       │
│  >                                                                    │
│ › [x] model-name            Current model name                        │
│   [x] current-dir           Current working directory                 │
│   [x] git-branch            Current Git branch (omitted when...       │
│   [ ] model-with-reasoning  Current model name with reasoning level   │
│   [ ] project-root          Project root directory (omitted...        │
│   [ ] context-remaining     Percentage of context window remaining... │
│   [ ] context-used          Percentage of context window used...      │
│   [ ] five-hour-limit       Remaining usage on 5-hour usage limit...  │
│                                                                       │
│  gpt-5-codex · ~/codex-rs · jif/statusline-preview                    │  <- 实时预览
│  Use ↑↓ to navigate, ←→ to move, space to select, enter to confirm... │
└──────────────────────────────────────────────────────────────────────┘
```

## 关键代码路径与文件引用

### 主要文件
- `codex-rs/tui/src/bottom_pane/status_line_setup.rs` - 主要实现文件

### 依赖模块
- `crate::bottom_pane::multi_select_picker::MultiSelectPicker` - 多选选择器组件
- `crate::bottom_pane::multi_select_picker::MultiSelectItem` - 选择项数据结构
- `strum::EnumIter` - 枚举迭代支持
- `strum::EnumString` - 字符串解析枚举支持
- `strum::Display` - 枚举显示支持

### 关键代码段

#### 项目描述映射（lines 100-134）
```rust
impl StatusLineItem {
    pub(crate) fn description(&self) -> &'static str {
        match self {
            StatusLineItem::ModelName => "Current model name",
            StatusLineItem::GitBranch => "Current Git branch (omitted when unavailable)",
            // ... 其他项目描述
        }
    }
}
```

#### 视图构建（lines 191-246）
```rust
pub(crate) fn new(status_line_items: Option<&[String]>, preview_data: StatusLinePreviewData, ...) -> Self {
    // 按现有配置顺序创建项目
    if let Some(selected_items) = status_line_items.as_ref() {
        for id in *selected_items {
            let Ok(item) = id.parse::<StatusLineItem>() else { continue };
            items.push(Self::status_line_select_item(item, /*enabled*/ true));
        }
    }
    
    // 添加剩余未配置的项目
    for item in StatusLineItem::iter() {
        // ... 添加禁用状态的项目
    }
    
    Self {
        picker: MultiSelectPicker::builder(...)
            .enable_ordering()  // 启用排序
            .on_preview(move |items| preview_data.line_for_items(items))
            .on_confirm(|ids, app_event| { ... })
            .on_cancel(|app_event| { ... })
            .build(),
    }
}
```

#### 预览测试（lines 296-370）
```rust
#[test]
fn setup_view_snapshot_uses_runtime_preview_values() {
    let preview_data = StatusLinePreviewData::from_iter([
        (StatusLineItem::ModelName, "gpt-5-codex".to_string()),
        (StatusLineItem::CurrentDir, "~/codex-rs".to_string()),
        (StatusLineItem::GitBranch, "jif/statusline-preview".to_string()),
        (StatusLineItem::WeeklyLimit, "weekly 82%".to_string()),
    ]);
    // ... 测试验证预览行正确显示运行时值
}
```

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|------|------|
| `ratatui` | TUI 渲染框架 |
| `strum` | 枚举工具宏（EnumIter, EnumString, Display） |
| `std::collections::BTreeMap` | 有序存储预览数据 |
| `std::collections::HashSet` | 去重检查已使用项目 |

### 应用事件交互
| 事件 | 方向 | 说明 |
|------|------|------|
| `AppEvent::StatusLineSetup` | 发送 | 用户确认配置变更 |
| `AppEvent::StatusLineSetupCancelled` | 发送 | 用户取消配置 |

### 序列化格式
- 使用 `kebab-case` 序列化（如 `model-with-reasoning`）
- 与配置文件格式保持一致

## 风险边界与改进建议

### 潜在风险

1. **预览数据不完整**
   - **风险**：如果 `StatusLinePreviewData` 不包含某些项目的运行时值，预览中这些项目会被省略
   - **边界**：`line_for_items()` 使用 `filter_map` 过滤掉无值项目
   - **影响**：用户可能误以为项目未启用
   - **建议**：在预览区域添加提示，说明某些项目因无可用数据而被隐藏

2. **配置解析失败**
   - **风险**：`id.parse::<StatusLineItem>()` 可能失败（如配置文件中存在无效项目）
   - **边界**：当前使用 `continue` 跳过无效项目
   - **影响**：无效项目静默丢失，用户可能困惑
   - **建议**：添加无效项目警告或迁移提示

3. **排序持久化**
   - **风险**：用户可能期望排序后配置自动保存，但实际需要按 Enter 确认
   - **边界**：仅在 `on_confirm` 回调中发送事件
   - **建议**：添加自动保存选项或更明显的确认提示

4. **预览与实际显示差异**
   - **风险**：预览使用运行时数据，但某些项目（如 Git 分支）可能因环境不同而不显示
   - **边界**：描述中注明了 "(omitted when unavailable)"
   - **建议**：在预览中也模拟这种条件显示逻辑

### 改进建议

1. **搜索增强**
   - 当前搜索仅匹配项目 ID，建议同时搜索描述文本
   - 添加搜索高亮

2. **分组功能**
   - 将相关项目分组（如 "模型信息"、"使用统计"、"路径信息"）
   - 支持组级别的启用/禁用

3. **预设配置**
   - 提供常用预设（如 "最小模式"、"开发模式"、"完整模式"）
   - 允许用户保存自定义预设

4. **实时更新**
   - 当运行时值变化时，预览应自动更新
   - 需要 `StatusLinePreviewData` 支持响应式更新

5. **测试覆盖**
   - 当前测试仅验证预览值使用
   - 建议添加：
     - 项目排序测试
     - 确认/取消事件测试
     - 无效配置处理测试
     - 边界条件测试（空配置、全部启用等）
