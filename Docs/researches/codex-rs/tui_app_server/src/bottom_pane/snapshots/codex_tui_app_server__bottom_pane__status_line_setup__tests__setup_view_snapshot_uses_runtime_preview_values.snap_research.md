# Status Line Setup View with Runtime Preview Values 研究文档

## 场景与职责

该 Snapshot 展示了 **Status Line Setup View** 组件的 UI 表现，用于让用户自定义状态栏（Status Line）中显示的信息项。状态栏位于 TUI 底部，显示当前会话的各种运行时信息。

**核心职责：**
- 提供交互式界面选择要在状态栏显示的项目
- 支持项目排序（通过左右箭头）
- 实时预览配置后的状态栏效果
- 使用运行时真实数据（如当前模型名、目录、Git 分支）进行预览

**典型应用场景：**
- 用户首次配置 Codex TUI 时自定义状态栏
- 根据工作流需求调整显示信息（如开发时显示 Git 分支，调试时显示上下文使用）
- 简化状态栏以减少视觉干扰

---

## 功能点目的

### 1. 状态栏项目选择
- 复选框 `[x]` 表示已启用，`[ ]` 表示未启用
- 当前已启用：model-name、current-dir、git-branch
- 当前未启用：model-with-reasoning、project-root、context-remaining 等

### 2. 项目排序
- 使用 `←/→` 键调整项目顺序
- 顺序决定状态栏中的显示顺序

### 3. 实时预览
- 底部显示预览：`gpt-5-codex · ~/codex-rs · jif/statusline-preview`
- 使用运行时真实数据，而非占位符

### 4. 项目描述
每个项目都有描述说明：
- `model-name`: "Current model name"
- `current-dir`: "Current working directory"
- `git-branch`: "Current Git branch (omitted when unavailable)"

---

## 具体技术实现

### 状态栏项目枚举

```rust
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

impl StatusLineItem {
    pub(crate) fn description(&self) -> &'static str {
        match self {
            StatusLineItem::ModelName => "Current model name",
            StatusLineItem::ModelWithReasoning => "Current model name with reasoning level",
            StatusLineItem::CurrentDir => "Current working directory",
            StatusLineItem::ProjectRoot => "Project root directory (omitted when unavailable)",
            StatusLineItem::GitBranch => "Current Git branch (omitted when unavailable)",
            // ... 其他项目描述
        }
    }
}
```

### 预览数据结构

```rust
/// 运行时值用于预览当前状态栏选择
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub(crate) struct StatusLinePreviewData {
    values: BTreeMap<StatusLineItem, String>,
}

impl StatusLinePreviewData {
    pub(crate) fn from_iter<I>(values: I) -> Self
    where
        I: IntoIterator<Item = (StatusLineItem, String)>,
    {
        Self {
            values: values.into_iter().collect(),
        }
    }

    /// 根据选中的项目生成预览行
    fn line_for_items(&self, items: &[MultiSelectItem]) -> Option<Line<'static>> {
        let preview = items
            .iter()
            .filter(|item| item.enabled)
            .filter_map(|item| item.id.parse::<StatusLineItem>().ok())
            .filter_map(|item| self.values.get(&item).cloned())
            .collect::<Vec<_>>()
            .join(" · ");  // 使用中间点分隔
        
        if preview.is_empty() {
            None
        } else {
            Some(Line::from(preview))
        }
    }
}
```

### 视图构建

```rust
pub(crate) struct StatusLineSetupView {
    picker: MultiSelectPicker,
}

impl StatusLineSetupView {
    pub(crate) fn new(
        status_line_items: Option<&[String]>,
        preview_data: StatusLinePreviewData,
        app_event_tx: AppEventSender,
    ) -> Self {
        let mut used_ids = HashSet::new();
        let mut items = Vec::new();

        // 首先添加已配置的项目（保持顺序）
        if let Some(selected_items) = status_line_items.as_ref() {
            for id in *selected_items {
                let Ok(item) = id.parse::<StatusLineItem>() else {
                    continue;
                };
                let item_id = item.to_string();
                if !used_ids.insert(item_id.clone()) {
                    continue;
                }
                items.push(Self::status_line_select_item(item, /*enabled*/ true));
            }
        }

        // 添加剩余未配置的项目
        for item in StatusLineItem::iter() {
            let item_id = item.to_string();
            if used_ids.contains(&item_id) {
                continue;
            }
            items.push(Self::status_line_select_item(item, /*enabled*/ false));
        }

        Self {
            picker: MultiSelectPicker::builder(
                "Configure Status Line".to_string(),
                Some("Select which items to display in the status line.".to_string()),
                app_event_tx,
            )
            .instructions(vec![
                "Use ↑↓ to navigate, ←→ to move, space to select, enter to confirm, esc to cancel."
                    .into(),
            ])
            .items(items)
            .enable_ordering()  // 启用排序功能
            .on_preview(move |items| preview_data.line_for_items(items))
            .on_confirm(|ids, app_event| {
                let items = ids
                    .iter()
                    .filter_map(|id| id.parse::<StatusLineItem>().ok())
                    .collect();
                app_event.send(AppEvent::StatusLineSetup { items });
            })
            .on_cancel(|app_event| {
                app_event.send(AppEvent::StatusLineSetupCancelled);
            })
            .build(),
        }
    }

    fn status_line_select_item(item: StatusLineItem, enabled: bool) -> MultiSelectItem {
        MultiSelectItem {
            id: item.to_string(),
            name: item.to_string(),
            description: Some(item.description().to_string()),
            enabled,
        }
    }
}
```

### MultiSelectPicker 构建器模式

```rust
MultiSelectPicker::builder(
    "Configure Status Line".to_string(),
    Some("Select which items to display in the status line.".to_string()),
    app_event_tx,
)
.instructions(vec![...])      // 操作说明
.items(items)                 // 项目列表
.enable_ordering()            // 启用排序
.on_preview(callback)         // 预览回调
.on_confirm(callback)         // 确认回调
.on_cancel(callback)          // 取消回调
.build()
```

---

## 关键代码路径与文件引用

### 主要实现文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/bottom_pane/status_line_setup.rs` | Status Line Setup View 实现 |
| `codex-rs/tui_app_server/src/bottom_pane/multi_select_picker.rs` | 通用多选选择器组件 |

### 关键类型定义

```rust
// StatusLineItem: ~48-98 行
pub(crate) enum StatusLineItem { ... }

// StatusLinePreviewData: ~137-166 行
pub(crate) struct StatusLinePreviewData { ... }

// StatusLineSetupView: ~175-257 行
pub(crate) struct StatusLineSetupView { ... }
```

### 测试代码

```rust
#[test]
fn setup_view_snapshot_uses_runtime_preview_values() {
    let view = StatusLineSetupView::new(
        Some(&[
            StatusLineItem::ModelName.to_string(),
            StatusLineItem::CurrentDir.to_string(),
            StatusLineItem::GitBranch.to_string(),
        ]),
        StatusLinePreviewData::from_iter([
            (StatusLineItem::ModelName, "gpt-5-codex".to_string()),
            (StatusLineItem::CurrentDir, "~/codex-rs".to_string()),
            (StatusLineItem::GitBranch, "jif/statusline-preview".to_string()),
            (StatusLineItem::WeeklyLimit, "weekly 82%".to_string()),
        ]),
        AppEventSender::new(tx_raw),
    );

    assert_snapshot!(render_lines(&view, 72));
}
```

### 事件定义

```rust
pub enum AppEvent {
    StatusLineSetup {
        items: Vec<StatusLineItem>,
    },
    StatusLineSetupCancelled,
    // ...
}
```

---

## 依赖与外部交互

### 外部库依赖

| 依赖 | 用途 |
|-----|------|
| `strum_macros::EnumIter` | 枚举迭代器派生 |
| `strum_macros::EnumString` | 字符串解析枚举 |
| `strum_macros::Display` | 枚举显示派生 |
| `strum::IntoEnumIterator` | 枚举遍历 |

### 内部模块依赖

| 模块 | 用途 |
|-----|------|
| `crate::bottom_pane::multi_select_picker` | 多选选择器组件 |
| `crate::app_event::AppEvent` | 状态栏配置事件 |
| `crate::app_event_sender::AppEventSender` | 事件发送器 |

### 配置持久化

```rust
// 确认时发送配置事件
.on_confirm(|ids, app_event| {
    let items = ids
        .iter()
        .filter_map(|id| id.parse::<StatusLineItem>().ok())
        .collect();
    app_event.send(AppEvent::StatusLineSetup { items });
})
```

配置通过事件系统传递到后端，最终保存到用户配置文件中。

---

## 风险、边界与改进建议

### 当前限制

1. **预览数据不完整**
   - 如果 `StatusLinePreviewData` 缺少某些项目的值，预览中会省略这些项目
   - 用户可能误以为这些项目不会显示，实际上运行时可能有值

2. **无默认值提示**
   - 用户不清楚初始默认配置是什么

3. **项目顺序调整不直观**
   - 使用 `←/→` 键移动项目，但无视觉反馈表明可以排序

4. **预览与实际可能不一致**
   - 预览使用传入的静态数据，实际运行时值可能不同
   - 例如：Git 分支在预览中是固定的，实际会随仓库状态变化

### 边界情况

| 场景 | 当前行为 |
|-----|---------|
| 所有项目都禁用 | 预览为空，状态栏可能显示默认内容或为空 |
| 预览数据缺少某些启用项目的值 | 该项目在预览中不显示 |
| 传入的 `status_line_items` 包含无效 ID | 跳过无效项目 |
| 用户取消配置 | 发送 `StatusLineSetupCancelled` 事件 |
| 重复的项目 ID | 使用 `HashSet` 去重 |

### 改进建议

1. **预览增强**
   ```rust
   // 建议：对缺失预览值的项目显示占位符
   fn line_for_items(&self, items: &[MultiSelectItem]) -> Option<Line<'static>> {
       let preview: Vec<String> = items
           .iter()
           .filter(|item| item.enabled)
           .filter_map(|item| {
               let item_enum = item.id.parse::<StatusLineItem>().ok()?;
               match self.values.get(&item_enum) {
                   Some(value) => Some(value.clone()),
                   None => Some(format!("<{}>", item.id)),  // 占位符
               }
           })
           .collect();
       // ...
   }
   ```

2. **默认配置提示**
   ```rust
   // 建议：添加 "Reset to default" 选项
   .on_reset(|app_event| {
       app_event.send(AppEvent::StatusLineSetup { 
           items: vec![StatusLineItem::ModelName, StatusLineItem::CurrentDir] 
       });
   })
   ```

3. **视觉排序指示**
   - 在选中项目旁显示 `← →` 提示
   - 或使用不同背景色表示可排序区域

4. **实时数据预览**
   ```rust
   // 建议：传递实时数据引用而非静态值
   pub(crate) struct StatusLinePreviewData {
       values: Arc<RwLock<BTreeMap<StatusLineItem, String>>>,
   }
   ```

5. **项目分组**
   - 将相关项目分组（如模型信息、Git 信息、上下文信息）
   - 使用分隔线或标题区分

6. **搜索功能**
   - 当项目较多时，添加搜索过滤功能
   - 类似 Skills Toggle View 的实现

7. **条件显示说明**
   - 对于 "omitted when unavailable" 的项目
   - 在预览中显示条件状态（如 Git 分支显示 "(not in git repo)"）
