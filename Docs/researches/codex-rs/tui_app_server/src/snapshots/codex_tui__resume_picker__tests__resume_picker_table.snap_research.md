# 研究文档：resume_picker_table.snap

## 场景与职责

此快照测试验证会话恢复选择器的表格显示效果。当有可恢复的会话时，以表格形式展示会话信息。

## 功能点目的

1. **会话信息展示**：以表格形式展示会话元数据
2. **时间显示**：使用相对时间（如 "16 minutes ago"）
3. **选择指示**：用 `>` 符号指示当前选中的会话

## 具体技术实现

### 快照输出分析

```
  Created at      Updated at      Branch  CWD  Conversation
  16 minutes ago  42 seconds ago  -       -    Fix resume picker timestamps
> 1 hour ago      35 minutes ago  -       -    Investigate lazy pagination cap
  2 hours ago     2 hours ago     -       -    Explain the codebase
```

表格列：
- `Created at`：会话创建时间（相对时间）
- `Updated at`：最后更新时间（相对时间）
- `Branch`：Git 分支（`-` 表示无）
- `CWD`：工作目录（`-` 表示无）
- `Conversation`：对话主题/第一条消息

选择指示：
- `>` 表示当前选中的会话

### 时间格式化

```rust
fn format_relative_time(timestamp: DateTime<Utc>) -> String {
    let now = Utc::now();
    let duration = now.signed_duration_since(timestamp);
    
    if duration.num_minutes() < 60 {
        format!("{} minutes ago", duration.num_minutes())
    } else if duration.num_hours() < 24 {
        format!("{} hours ago", duration.num_hours())
    } else {
        format!("{} days ago", duration.num_days())
    }
}
```

## 关键代码路径与文件引用

1. **表格渲染**：
   - `codex-rs/tui/src/resume_picker.rs`
   - `ratatui::widgets::Table`

2. **时间处理**：
   - `chrono` crate - 时间处理

## 依赖与外部交互

### 时间库
- `chrono::DateTime` - 日期时间类型
- `chrono::Utc` - UTC 时间

## 风险、边界与改进建议

### 潜在风险
1. **时区问题**：相对时间可能因时区而显示不正确
2. **列宽问题**：长内容可能导致列宽不均

### 边界情况
1. 会话时间在未来（时钟不同步）
2. 会话时间非常久远（>1 年）
3. 会话主题非常长

### 改进建议
1. 添加悬停显示绝对时间
2. 支持按列排序
3. 添加会话标签/颜色标识
4. 支持多选批量操作
