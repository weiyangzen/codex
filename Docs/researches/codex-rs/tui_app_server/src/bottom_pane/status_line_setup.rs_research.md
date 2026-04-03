# status_line_setup.rs 深度研究文档

## 1. 场景与职责

`status_line_setup.rs` 是 Codex TUI 应用中负责**状态栏配置界面**的核心组件。当用户通过 `/statusline` 命令触发状态栏设置时，该视图提供一个交互式多选界面，允许用户自定义状态栏显示的内容项及其顺序。

### 核心职责
- **状态栏项管理**: 提供 15+ 种可选状态栏项（模型、Git 分支、上下文使用率等）
- **多选与排序**: 支持选择/取消选择项目，以及调整项目显示顺序
- **实时预览**: 显示当前配置的状态栏预览
- **配置持久化**: 通过 `AppEvent` 将配置变更发送到应用层
- **键盘导航**: 支持方向键导航、空格选择、回车确认

## 2. 功能点目的

### 2.1 StatusLineItem 枚举

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
    ContextUsed,         // 上下文已使用百分比
    FiveHourLimit,       // 5小时限制剩余
    WeeklyLimit,         // 周限制剩余
    CodexVersion,        // Codex 版本
    ContextWindowSize,   // 上下文窗口大小
    UsedTokens,          // 已使用 token 数
    TotalInputTokens,    // 总输入 token
    TotalOutputTokens,   // 总输出 token
    SessionId,           // 会话 ID
    FastMode,            // Fast 模式状态
}
```

**设计意图**:
- 使用 `strum` 宏实现枚举与字符串的互相转换（kebab-case 格式）
- `EnumIter` 支持遍历所有变体
- `Ord`/`PartialOrd` 支持排序操作
- 序列化名称用于配置文件存储（如 `model-name`, `git-branch`）

### 2.2 StatusLinePreviewData 结构

```rust
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub(crate) struct StatusLinePreviewData {
    values: BTreeMap<StatusLineItem, String>,
}
```

**用途**: 存储运行时数据用于状态栏预览，如：
- 当前模型名称（"gpt-5-codex"）
- Git 分支（"feature-branch"）
- 上下文使用率（"45%"）

### 2.3 StatusLineSetupView 结构

```rust
pub(crate) struct StatusLineSetupView {
    picker: MultiSelectPicker,  // 底层多选组件
}
```

**设计模式**: 使用组合模式包装 `MultiSelectPicker`，专注于状态栏特定的业务逻辑。

## 3. 具体技术实现

### 3.1 初始化流程

```rust
pub(crate) fn new(
    status_line_items: Option<&[String]>,  // 当前配置
    preview_data: StatusLinePreviewData,    // 预览数据
    app_event_tx: AppEventSender,
) -> Self {
    // 1. 构建已启用的项目列表（保持原有顺序）
    if let Some(selected_items) = status_line_items.as_ref() {
        for id in *selected_items {
            if let Ok(item) = id.parse::<StatusLineItem>() {
                items.push(Self::status_line_select_item(item, true));
            }
        }
    }

    // 2. 添加未启用的项目（按枚举定义顺序）
    for item in StatusLineItem::iter() {
        if !used_ids.contains(&item.to_string()) {
            items.push(Self::status_line_select_item(item, false));
        }
    }

    // 3. 使用 Builder 模式构建 MultiSelectPicker
    Self {
        picker: MultiSelectPicker::builder("Configure Status Line".to_string(), ...)
            .items(items)
            .enable_ordering()  // 启用排序功能
            .on_preview(move |items| preview_data.line_for_items(items))
            .on_confirm(|ids, app_event| { /* 发送确认事件 */ })
            .on_cancel(|app_event| { /* 发送取消事件 */ })
            .build(),
    }
}
```

### 3.2 预览生成逻辑

```rust
fn line_for_items(&self, items: &[MultiSelectItem]) -> Option<Line<'static>> {
    let preview = items
        .iter()
        .filter(|item| item.enabled)                    // 只选启用的
        .filter_map(|item| item.id.parse::<StatusLineItem>().ok())  // 解析枚举
        .filter_map(|item| self.values.get(&item).cloned())          // 获取值
        .collect::<Vec<_>>()
        .join(" · ");                                   // 用 "·" 连接
    
    if preview.is_empty() { None } else { Some(Line::from(preview)) }
}
```

**预览示例**: `gpt-5-codex · ~/codex-rs · jif/statusline-preview`

### 3.3 项目描述

每个 `StatusLineItem` 都有用户可见的描述：

```rust
impl StatusLineItem {
    pub(crate) fn description(&self) -> &'static str {
        match self {
            StatusLineItem::ModelName => "Current model name",
            StatusLineItem::GitBranch => "Current Git branch (omitted when unavailable)",
            StatusLineItem::ContextRemaining => {
                "Percentage of context window remaining (omitted when unknown)"
            }
            // ... 更多描述
        }
    }
}
```

**设计意图**: 帮助用户理解每个项目的含义和显示条件。

### 3.4 与 MultiSelectPicker 的集成

`StatusLineSetupView` 将具体操作委托给 `MultiSelectPicker`：

```rust
impl BottomPaneView for StatusLineSetupView {
    fn handle_key_event(&mut self, key_event: KeyEvent) {
        self.picker.handle_key_event(key_event);  // 委托键盘事件
    }

    fn is_complete(&self) -> bool {
        self.picker.complete  // 委托完成状态
    }

    fn on_ctrl_c(&mut self) -> CancellationEvent {
        self.picker.close();
        CancellationEvent::Handled
    }
}

impl Renderable for StatusLineSetupView {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        self.picker.render(area, buf)  // 委托渲染
    }

    fn desired_height(&self, width: u16) -> u16 {
        self.picker.desired_height(width)  // 委托高度计算
    }
}
```

## 4. 关键代码路径与文件引用

### 4.1 文件位置
- **主文件**: `codex-rs/tui_app_server/src/bottom_pane/status_line_setup.rs`

### 4.2 依赖文件
```
codex-rs/tui_app_server/src/bottom_pane/
├── multi_select_picker.rs       # MultiSelectPicker, MultiSelectItem
├── bottom_pane_view.rs          # BottomPaneView trait
└── mod.rs                       # 模块导出

codex-rs/tui_app_server/src/
├── app_event.rs                 # AppEvent::StatusLineSetup, StatusLineSetupCancelled
├── app_event_sender.rs          # AppEventSender
└── render/renderable.rs         # Renderable trait
```

### 4.3 关键代码片段

#### 状态栏项定义
```rust
// status_line_setup.rs:48-98
#[derive(EnumIter, EnumString, Display, Debug, Clone, Eq, PartialEq, Ord, PartialOrd)]
#[strum(serialize_all = "kebab_case")]
pub(crate) enum StatusLineItem {
    ModelName,
    ModelWithReasoning,
    CurrentDir,
    ProjectRoot,
    GitBranch,
    ContextRemaining,
    ContextUsed,
    FiveHourLimit,
    WeeklyLimit,
    CodexVersion,
    ContextWindowSize,
    UsedTokens,
    TotalInputTokens,
    TotalOutputTokens,
    SessionId,
    FastMode,
}
```

#### 描述实现
```rust
// status_line_setup.rs:100-134
impl StatusLineItem {
    pub(crate) fn description(&self) -> &'static str {
        match self {
            StatusLineItem::ModelName => "Current model name",
            StatusLineItem::ModelWithReasoning => "Current model name with reasoning level",
            StatusLineItem::CurrentDir => "Current working directory",
            StatusLineItem::ProjectRoot => "Project root directory (omitted when unavailable)",
            StatusLineItem::GitBranch => "Current Git branch (omitted when unavailable)",
            // ... 更多
        }
    }
}
```

#### 视图构建
```rust
// status_line_setup.rs:191-257
impl StatusLineSetupView {
    pub(crate) fn new(
        status_line_items: Option<&[String]>,
        preview_data: StatusLinePreviewData,
        app_event_tx: AppEventSender,
    ) -> Self {
        let mut used_ids = HashSet::new();
        let mut items = Vec::new();

        // 添加已配置的项目
        if let Some(selected_items) = status_line_items.as_ref() {
            for id in *selected_items {
                let Ok(item) = id.parse::<StatusLineItem>() else { continue; };
                let item_id = item.to_string();
                if !used_ids.insert(item_id.clone()) { continue; }
                items.push(Self::status_line_select_item(item, true));
            }
        }

        // 添加剩余项目
        for item in StatusLineItem::iter() {
            let item_id = item.to_string();
            if used_ids.contains(&item_id) { continue; }
            items.push(Self::status_line_select_item(item, false));
        }

        Self {
            picker: MultiSelectPicker::builder(...)
                .items(items)
                .enable_ordering()
                .on_preview(move |items| preview_data.line_for_items(items))
                .on_confirm(|ids, app_event| {
                    let items = ids.iter()
                        .map(|id| id.parse::<StatusLineItem>())
                        .collect::<Result<Vec<_>, _>>()
                        .unwrap_or_default();
                    app_event.send(AppEvent::StatusLineSetup { items });
                })
                .on_cancel(|app_event| {
                    app_event.send(AppEvent::StatusLineSetupCancelled);
                })
                .build(),
        }
    }
}
```

### 4.4 测试代码

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use insta::assert_snapshot;

    #[test]
    fn preview_uses_runtime_values() {
        let preview_data = StatusLinePreviewData::from_iter([
            (StatusLineItem::ModelName, "gpt-5".to_string()),
            (StatusLineItem::CurrentDir, "/repo".to_string()),
        ]);
        let items = vec![/* ... */];

        assert_eq!(
            preview_data.line_for_items(&items),
            Some(Line::from("gpt-5 · /repo"))
        );
    }

    #[test]
    fn setup_view_snapshot_uses_runtime_preview_values() {
        let (tx_raw, _rx) = unbounded_channel::<AppEvent>();
        let view = StatusLineSetupView::new(
            Some(&[
                StatusLineItem::ModelName.to_string(),
                StatusLineItem::CurrentDir.to_string(),
                StatusLineItem::GitBranch.to_string(),
            ]),
            StatusLinePreviewData::from_iter([/* ... */]),
            AppEventSender::new(tx_raw),
        );
        assert_snapshot!(render_lines(&view, 72));
    }
}
```

## 5. 依赖与外部交互

### 5.1 上游依赖（输入）

| 来源 | 数据 | 说明 |
|------|------|------|
| `App` | `Option<&[String]>` | 当前状态栏配置（项目 ID 列表） |
| `App` | `StatusLinePreviewData` | 运行时预览数据 |
| `MultiSelectPicker` | 渲染和交互 | 底层多选组件 |

### 5.2 下游消费（输出）

| 消费者 | 事件 | 数据 |
|--------|------|------|
| `App` | `StatusLineSetup` | `Vec<StatusLineItem>`（确认配置） |
| `App` | `StatusLineSetupCancelled` | 无（取消操作） |

### 5.3 配置持久化流程

```
用户配置状态栏
    ↓
StatusLineSetupView::on_confirm
    ↓
发送 AppEvent::StatusLineSetup { items }
    ↓
App 层接收事件
    ↓
转换为字符串列表（kebab-case）
    ↓
保存到配置文件
```

### 5.4 与 MultiSelectPicker 的关系

| 特性 | StatusLineSetupView | MultiSelectPicker |
|------|---------------------|-------------------|
| 职责 | 状态栏特定逻辑 | 通用多选/排序 |
| 项目类型 | `StatusLineItem` | 任意字符串 ID |
| 预览 | 状态栏格式 | 通用回调 |
| 事件 | 特定 AppEvent | 通用回调 |

## 6. 风险、边界与改进建议

### 6.1 已知边界条件

1. **配置解析**: 无效的项目 ID 会被静默跳过（`continue`）
2. **预览数据缺失**: 如果 `StatusLinePreviewData` 不包含某项的值，该项在预览中省略
3. **空配置处理**: `status_line_items` 为 `None` 时，所有项目默认未启用
4. **最大项目数**: 受 `MultiSelectPicker` 和 `MAX_POPUP_ROWS` 限制

### 6.2 潜在风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 配置不兼容 | 新增/删除 `StatusLineItem` 变体可能导致旧配置失效 | 使用 `strum` 的 `serialize_all` 保持序列化稳定 |
| 预览数据过时 | 运行时数据可能与实际状态不同步 | 定期更新 `StatusLinePreviewData` |
| 顺序丢失 | 如果配置包含无效 ID，顺序可能改变 | 保持有效 ID 的相对顺序 |

### 6.3 改进建议

1. **配置迁移**:
   - 添加配置版本号
   - 支持自动迁移旧配置

2. **增强预览**:
   - 添加颜色/样式预览
   - 模拟不同宽度下的显示效果

3. **智能排序**:
   - 根据使用频率自动排序
   - 推荐常用组合

4. **搜索功能**:
   - 添加项目搜索过滤
   - 支持描述文本搜索

5. **分组显示**:
   - 按类别分组（如 "模型信息"、"Git 信息"、"使用情况"）
   - 支持折叠/展开

6. **测试增强**:
   - 添加所有 `StatusLineItem` 的序列化/反序列化测试
   - 测试配置顺序保持
   - 添加交互测试（选择、排序、确认）

### 6.4 相关测试

当前测试覆盖：
- ✅ 预览数据使用测试
- ✅ 缺失值处理测试
- ✅ 快照测试（完整 UI）

建议添加：
- 所有枚举变体的序列化测试
- 配置解析边界测试
- 事件发送验证测试
