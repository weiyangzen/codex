# status_line_setup.rs 研究文档

## 场景与职责

`status_line_setup.rs` 是 Codex TUI 中用于 **自定义状态栏（Status Line）** 的交互式配置界面。状态栏位于终端底部，显示当前会话的各种信息（如模型名称、当前目录、Git 分支、上下文使用情况等）。该组件允许用户：

- 选择要在状态栏显示哪些信息项
- 调整信息项的显示顺序
- 实时预览配置后的状态栏效果
- 将配置持久化保存

该组件是 `StatusLineSetupView` 结构体的实现，是对 `MultiSelectPicker` 的包装，专门用于状态栏配置场景。

## 功能点目的

### 1. StatusLineItem 枚举
```rust
#[derive(EnumIter, EnumString, Display, Debug, Clone, Eq, PartialEq, Ord, PartialOrd)]
#[strum(serialize_all = "kebab_case")]
pub(crate) enum StatusLineItem {
    ModelName,           // 当前模型名称
    ModelWithReasoning,  // 模型名称 + 推理级别
    CurrentDir,          // 当前工作目录
    ProjectRoot,         // 项目根目录
    GitBranch,           // Git 分支名
    ContextRemaining,    // 上下文剩余百分比
    ContextUsed,         // 上下文使用百分比
    FiveHourLimit,       // 5小时限制剩余
    WeeklyLimit,         // 周限制剩余
    CodexVersion,        // Codex 版本
    ContextWindowSize,   // 上下文窗口大小
    UsedTokens,          // 已使用 token 数
    TotalInputTokens,    // 总输入 token 数
    TotalOutputTokens,   // 总输出 token 数
    SessionId,           // 会话 ID
    FastMode,            // Fast 模式状态
}
```

**设计特点**：
- 使用 `strum` 宏实现枚举迭代、字符串解析和显示
- `kebab-case` 序列化用于配置存储（如 `model-name`）
- 每个变体都有用户可见的描述说明
- 部分项有条件显示（如 GitBranch 在非 Git 仓库时省略）

### 2. StatusLinePreviewData 预览数据
```rust
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub(crate) struct StatusLinePreviewData {
    values: BTreeMap<StatusLineItem, String>,
}
```

- 存储当前运行时各数据项的值
- 用于在配置界面实时预览状态栏效果
- 通过 `line_for_items()` 方法生成预览文本

### 3. 多选配置界面
`StatusLineSetupView` 包装 `MultiSelectPicker` 提供：
- **预填充**：根据当前配置初始化选项状态
- **排序功能**：通过左右箭头调整项目顺序
- **实时预览**：显示配置后的状态栏效果
- **事件通知**：确认时发送 `StatusLineSetup` 事件，取消时发送 `StatusLineSetupCancelled`

## 具体技术实现

### 关键流程

#### 1. 初始化流程
```rust
pub(crate) fn new(
    status_line_items: Option<&[String]>,  // 当前配置
    preview_data: StatusLinePreviewData,    // 预览数据
    app_event_tx: AppEventSender,
) -> Self {
    // 1. 解析已配置项，标记为启用
    // 2. 遍历所有 StatusLineItem，未配置的标记为禁用
    // 3. 使用 MultiSelectPicker::builder 构建选择器
    // 4. 启用排序功能
    // 5. 设置预览回调
    // 6. 设置确认/取消回调
}
```

#### 2. 预览生成流程
```rust
fn line_for_items(&self, items: &[MultiSelectItem]) -> Option<Line<'static>> {
    // 1. 过滤启用的项
    // 2. 解析 ID 为 StatusLineItem
    // 3. 从 preview_data 获取对应值
    // 4. 用 " · " 连接各值
    // 5. 返回 Line 或 None（如果没有值）
}
```

#### 3. 确认流程
```rust
.on_confirm(|ids, app_event| {
    // 1. 解析 ID 字符串为 StatusLineItem
    // 2. 发送 StatusLineSetup 事件
})
```

### 数据结构

| 结构/类型 | 用途 |
|-----------|------|
| `StatusLineItem` | 状态栏可选项枚举 |
| `StatusLinePreviewData` | 预览数据存储 |
| `StatusLineSetupView` | 配置视图包装器 |
| `MultiSelectPicker` | 底层多选组件（来自 multi_select_picker.rs） |
| `MultiSelectItem` | 选择项数据结构 |

### 依赖模块

```rust
use crate::app_event::AppEvent;
use crate::app_event_sender::AppEventSender;
use crate::bottom_pane::CancellationEvent;
use crate::bottom_pane::bottom_pane_view::BottomPaneView;
use crate::bottom_pane::multi_select_picker::MultiSelectItem;
use crate::bottom_pane::multi_select_picker::MultiSelectPicker;
use crate::render::renderable::Renderable;
use strum::IntoEnumIterator;
use strum_macros::{Display, EnumIter, EnumString};
```

## 关键代码路径与文件引用

### 核心实现
- `codex-rs/tui/src/bottom_pane/status_line_setup.rs` - 本文件，状态栏配置实现

### 依赖文件
- `codex-rs/tui/src/bottom_pane/multi_select_picker.rs` - 多选选择器组件
- `codex-rs/tui/src/bottom_pane/bottom_pane_view.rs` - BottomPaneView trait
- `codex-rs/tui/src/app_event.rs` - AppEvent 定义（StatusLineSetup, StatusLineSetupCancelled）
- `codex-rs/tui/src/app_event_sender.rs` - 事件发送器
- `codex-rs/tui/src/render/renderable.rs` - Renderable trait

### 调用方
- `codex-rs/tui/src/bottom_pane/mod.rs` - 导出 `StatusLineItem`, `StatusLinePreviewData`, `StatusLineSetupView`
- `codex-rs/tui/src/chatwidget.rs` - 处理状态栏配置相关事件

### 配置存储
- 配置通过 `AppEvent::StatusLineSetup` 事件传递到应用层
- 由应用层持久化到配置文件（config.toml）
- 配置键使用 kebab-case（如 `status-line-items = ["model-name", "current-dir"]`）

## 依赖与外部交互

### 输入依赖
1. **当前配置**：`Option<&[String]>`，已配置的状态栏项 ID 列表
2. **预览数据**：`StatusLinePreviewData`，各数据项的当前值
3. **事件发送器**：`AppEventSender`，用于发送配置变更事件

### 输出交互
1. **配置确认事件**：`AppEvent::StatusLineSetup { items: Vec<StatusLineItem> }`
   - 包含用户选择的项（按顺序）
   - 由应用主循环接收并持久化
2. **取消事件**：`AppEvent::StatusLineSetupCancelled`
   - 通知应用配置被取消，不做更改

### 与 MultiSelectPicker 的协作
```
StatusLineSetupView (包装层)
    ↓ 配置和回调
MultiSelectPicker (通用组件)
    ↓ 渲染和交互
用户界面
    ↓ 确认/取消
StatusLineSetupView 回调
    ↓ 发送事件
App 主循环
    ↓ 持久化
配置文件
```

### 与状态栏渲染的协作
- `StatusLineItem` 定义了所有可能的状态栏项
- 实际状态栏渲染逻辑在 `footer.rs` 或 `chat_composer.rs` 中
- 配置变更后，应用层更新配置，状态栏渲染自动使用新配置

## 风险、边界与改进建议

### 潜在风险

1. **配置与实现不同步**：
   - `StatusLineItem` 枚举定义了可用项
   - 但实际状态栏渲染逻辑可能在其他文件中
   - 如果添加新项但忘记更新渲染逻辑，会导致配置无效
   - 建议：在 `StatusLineItem` 文档中明确说明需要同步更新的文件

2. **预览数据不完整**：
   - `StatusLinePreviewData` 可能缺少某些项的值
   - 这会导致预览显示不完整，用户可能困惑
   - 建议：为缺失项显示占位符（如 `"N/A"` 或 `"--"`）

3. **排序持久化问题**：
   - 用户调整顺序后，如果配置保存失败，下次打开顺序会恢复
   - 但用户不会收到错误通知
   - 建议：添加保存状态反馈

### 边界情况

1. **空配置处理**：
   - 当 `status_line_items` 为 `None` 时，所有项初始为禁用
   - 这是合理的默认行为（用户从零开始配置）

2. **无效配置项**：
   - 如果配置文件中包含无效的项 ID，`parse::<StatusLineItem>()` 会失败
   - 当前实现使用 `continue` 跳过无效项
   - 建议：记录警告日志，帮助用户发现配置问题

3. **重复项处理**：
   - `used_ids` HashSet 用于检测和跳过重复项
   - 这是防御性编程，正常不应出现重复

4. **极窄终端**：
   - 预览文本可能超出终端宽度
   - `MultiSelectPicker` 会截断显示，但可能影响用户体验

### 改进建议

1. **配置验证**：
   - 添加配置项有效性验证
   - 在发现无效项时向用户显示警告

2. **默认值优化**：
   - 当前空配置时所有项禁用
   - 建议提供 "恢复默认" 功能，使用推荐配置

3. **分组功能**：
   - 将相关项分组（如模型信息、路径信息、使用统计）
   - 支持分组级别的启用/禁用

4. **搜索功能**：
   - 当状态栏项很多时，添加搜索过滤功能
   - 复用 `MultiSelectPicker` 的搜索能力

5. **预览增强**：
   - 添加颜色预览（状态栏实际使用颜色）
   - 显示预览说明，解释各缩写含义

6. **测试覆盖**：
   当前已有一个快照测试 `setup_view_snapshot_uses_runtime_preview_values`，建议补充：
   - 配置解析测试（有效/无效项）
   - 排序功能测试
   - 边界情况测试（空配置、重复项）
   - 事件发送测试

7. **文档完善**：
   - 在 `StatusLineItem::description()` 中添加更多上下文信息
   - 例如解释 "5-hour limit" 是什么，帮助用户做出选择

8. **国际化准备**：
   - 当前描述是硬编码的英文
   - 如果未来需要多语言支持，需要将描述提取到资源文件中
