# Resume Picker 表格快照研究文档

## 场景与职责

该快照测试验证 **Resume Picker** 的表格渲染功能，展示当有多个会话可用时的列表界面。这是用户最常见的使用场景，表格需要清晰展示会话的关键信息，支持排序和选择。

### 核心职责
- 以表格形式展示会话列表
- 显示时间戳（相对时间格式）
- 支持选中项高亮（`> ` 标记）
- 响应式列宽（根据内容自适应）

## 功能点目的

### 1. 会话信息展示
表格包含以下列：
- **Created at**: 会话创建时间（相对时间）
- **Updated at**: 最后更新时间（相对时间）
- **Branch**: Git 分支（本例中无数据，显示 `-`）
- **CWD**: 当前工作目录（本例中无数据，显示 `-`）
- **Conversation**: 对话预览（第一条用户消息）

### 2. 时间格式化
- 使用相对时间格式（如 "16 minutes ago", "1 hour ago"）
- 自动选择合适的时间单位（秒、分钟、小时、天）
- 单复数自动处理（"1 minute ago" vs "2 minutes ago"）

### 3. 选中高亮
- 当前选中行使用 `> ` 前缀标记
- 其他行使用 `  `（两个空格）前缀
- 选中行以粗体显示

### 4. 列宽自适应
- 根据内容计算每列最大宽度
- 使用 Unicode 宽度计算（支持中文等）
- 预留适当的列间距（两个空格）

## 具体技术实现

### 数据结构

```rust
struct Row {
    path: PathBuf,
    preview: String,                    // 对话预览
    thread_id: Option<ThreadId>,
    thread_name: Option<String>,
    created_at: Option<DateTime<Utc>>,
    updated_at: Option<DateTime<Utc>>,
    cwd: Option<PathBuf>,
    git_branch: Option<String>,
}

struct ColumnMetrics {
    max_created_width: usize,
    max_updated_width: usize,
    max_branch_width: usize,
    max_cwd_width: usize,
    labels: Vec<(String, String, String, String)>,  // 每行的格式化标签
}
```

### 时间格式化

```rust
fn human_time_ago(ts: DateTime<Utc>) -> String {
    let now = Utc::now();
    let delta = now - ts;
    let secs = delta.num_seconds();
    
    if secs < 60 {
        // "N seconds ago" / "1 second ago"
    } else if secs < 60 * 60 {
        // "N minutes ago" / "1 minute ago"
    } else if secs < 60 * 60 * 24 {
        // "N hours ago" / "1 hour ago"
    } else {
        // "N days ago" / "1 day ago"
    }
}

fn format_created_label(row: &Row) -> String {
    match row.created_at {
        Some(created) => human_time_ago(created),
        None => "-".to_string(),
    }
}

fn format_updated_label(row: &Row) -> String {
    match (row.updated_at, row.created_at) {
        (Some(updated), _) => human_time_ago(updated),
        (None, Some(created)) => human_time_ago(created),
        (None, None) => "-".to_string(),
    }
}
```

### 列宽计算

```rust
fn calculate_column_metrics(rows: &[Row], include_cwd: bool) -> ColumnMetrics {
    fn right_elide(s: &str, max: usize) -> String {
        // 右截断："...tail"
        if s.chars().count() <= max {
            return s.to_string();
        }
        if max <= 1 {
            return "…".to_string();
        }
        let tail_len = max - 1;
        let tail: String = s.chars().rev().take(tail_len).collect::<String>()
            .chars().rev().collect();
        format!("…{tail}")
    }

    let mut labels = Vec::with_capacity(rows.len());
    // 初始化最大宽度为列标题宽度
    let mut max_created_width = UnicodeWidthStr::width("Created at");
    let mut max_updated_width = UnicodeWidthStr::width("Updated at");
    let mut max_branch_width = UnicodeWidthStr::width("Branch");
    let mut max_cwd_width = if include_cwd { UnicodeWidthStr::width("CWD") } else { 0 };

    for row in rows {
        let created = format_created_label(row);
        let updated = format_updated_label(row);
        let branch = right_elide(&row.git_branch.clone().unwrap_or_default(), 24);
        let cwd = if include_cwd { 
            right_elide(&cwd_raw, 24) 
        } else { 
            String::new() 
        };
        
        // 更新最大宽度
        max_created_width = max_created_width.max(UnicodeWidthStr::width(created.as_str()));
        // ... 其他列
        
        labels.push((created, updated, branch, cwd));
    }

    ColumnMetrics { ... }
}
```

### 列表渲染

```rust
fn render_list(frame: &mut Frame, area: Rect, state: &PickerState, metrics: &ColumnMetrics) {
    let rows = &state.filtered_rows;
    let capacity = area.height as usize;
    let start = state.scroll_top.min(rows.len().saturating_sub(1));
    let end = rows.len().min(start + capacity);
    
    for (idx, (row, (created_label, updated_label, branch_label, cwd_label))) in 
        rows[start..end].iter().zip(labels[start..end].iter()).enumerate() 
    {
        let is_sel = start + idx == state.selected;
        let marker = if is_sel { "> ".bold() } else { "  ".into() };
        
        // 构建行内容
        let mut spans: Vec<Span> = vec![marker];
        
        // 添加各列
        if visibility.show_created {
            spans.push(Span::from(format!("{created_label:<max_created_width$}")).dim());
            spans.push("  ".into());
        }
        // ... Updated at, Branch, CWD
        
        // 对话预览（剩余宽度）
        let preview = truncate_text(row.display_preview(), preview_width);
        spans.push(preview.into());
        
        let line: Line = spans.into();
        frame.render_widget_ref(line, rect);
    }
}
```

### 测试用例分析

```rust
#[test]
fn resume_table_snapshot() {
    // 1. 创建测试状态
    let mut state = PickerState::new(...);
    
    // 2. 创建测试数据（三个会话）
    let now = Utc::now();
    let rows = vec![
        Row {
            preview: "Fix resume picker timestamps".to_string(),
            created_at: Some(now - Duration::minutes(16)),
            updated_at: Some(now - Duration::seconds(42)),
            // ... 其他字段
        },
        Row {
            preview: "Investigate lazy pagination cap".to_string(),
            created_at: Some(now - Duration::hours(1)),
            updated_at: Some(now - Duration::minutes(35)),
            // ...
        },
        Row {
            preview: "Explain the codebase".to_string(),
            created_at: Some(now - Duration::hours(2)),
            updated_at: Some(now - Duration::hours(2)),
            // ...
        },
    ];
    state.all_rows = rows.clone();
    state.filtered_rows = rows;
    state.selected = 1;  // 选中第二行
    
    // 3. 渲染并验证
    let metrics = calculate_column_metrics(&state.filtered_rows, state.show_all);
    render_column_headers(&mut frame, segments[0], &metrics, state.sort_key);
    render_list(&mut frame, segments[1], &state, &metrics);
    
    assert_snapshot!("resume_picker_table", snapshot);
}
```

### 快照输出解析

```
  Created at      Updated at      Branch  CWD  Conversation
// 列标题（粗体）
  16 minutes ago  42 seconds ago  -       -    Fix resume picker timestamps
// 第一行（未选中）
> 1 hour ago      35 minutes ago  -       -    Investigate lazy pagination cap
// 第二行（选中，> 标记）
  2 hours ago     2 hours ago     -       -    Explain the codebase
// 第三行（未选中）
```

## 关键代码路径与文件引用

### 核心文件
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui/src/resume_picker.rs` | Resume Picker 实现 |

### 关键函数

1. **时间格式化**
   - `human_time_ago()` (line 1102-1135)
   - `format_created_label()` (line 1145-1150)
   - `format_updated_label()` (line 1137-1143)

2. **列宽计算**
   - `calculate_column_metrics()` (line 1230-1289)
   - `right_elide()` (line 1231-1248) - 右截断

3. **渲染**
   - `render_list()` (line 941-1072)
   - `render_column_headers()` (line 1152-1202)

4. **测试**
   - `resume_table_snapshot()` (line 1565-1642)

### 列可见性

```rust
#[derive(Debug, PartialEq, Eq)]
struct ColumnVisibility {
    show_created: bool,
    show_updated: bool,
    show_branch: bool,
    show_cwd: bool,
}

fn column_visibility(area_width: u16, metrics: &ColumnMetrics, sort_key: ThreadSortKey) 
    -> ColumnVisibility {
    const MIN_PREVIEW_WIDTH: usize = 10;
    
    // 计算剩余宽度
    // 如果预览宽度不足，隐藏非活动排序的时间列
    let show_both = preview_width >= MIN_PREVIEW_WIDTH;
    let show_created = if show_both { ... } else { sort_key == ThreadSortKey::CreatedAt };
    let show_updated = if show_both { ... } else { sort_key == ThreadSortKey::UpdatedAt };
    
    ColumnVisibility { ... }
}
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `chrono` | 时间处理，DateTime, Duration |
| `unicode_width` | Unicode 字符串宽度计算 |
| `ratatui` | 终端 UI 渲染 |

### 内部模块交互

```
resume_picker.rs
├── text_formatting::truncate_text() (文本截断)
├── diff_render::display_path_for() (路径显示)
└── custom_terminal.rs (VT100Backend 测试后端)
```

## 风险、边界与改进建议

### 潜在风险

1. **时间精度**
   - 使用 `Utc::now()` 计算相对时间
   - 测试可能因时间流逝而失败（flaky test）
   - 当前测试使用固定时间偏移，相对安全

2. **列宽溢出**
   - 极端长的分支名或路径可能导致布局混乱
   - `right_elide` 使用固定最大长度（24）

3. **时区问题**
   - 时间戳存储为 UTC，显示为相对时间
   - 用户可能困惑于时间差异

### 边界情况

1. **空数据**
   - Branch/CWD 为空时显示 `-`
   - 时间戳缺失时显示 `-`

2. **终端宽度不足**
   - 优先隐藏非活动排序的时间列
   - 预览列保留最小宽度（10字符）

3. **超长预览**
   - 使用 `truncate_text` 截断
   - 保留可见部分

### 改进建议

1. **时间显示**
   - 支持悬停显示绝对时间
   - 支持切换相对/绝对时间显示

2. **排序指示**
   - 当前排序列添加箭头指示（▲/▼）
   - 更直观的视觉反馈

3. **列自定义**
   - 允许用户自定义显示列
   - 保存用户偏好

4. **搜索高亮**
   - 搜索结果中高亮匹配文本
   - 支持预览列搜索

5. **测试稳定性**
   - 使用固定时间戳而非相对时间
   - 避免时间流逝导致的测试失败
