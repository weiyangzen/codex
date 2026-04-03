# 研究文档：resume_picker_screen.snap

## 场景与职责

此快照测试验证会话恢复选择器的初始屏幕显示。当用户启动 Codex 时，可以选择恢复之前的会话。

## 功能点目的

1. **会话列表展示**：显示可恢复的会话列表
2. **空状态处理**：当没有会话时显示友好提示
3. **操作引导**：提示用户可用的操作

## 具体技术实现

### 快照输出分析

```
Resume a previous session  Sort: Created at
Type to search
  Created at  Updated at  Branch  CWD  Conversation
No sessions yet




enter to resume     esc to start new     ctrl + c to quit     tab to toggle sort
```

界面元素：
- 标题：`Resume a previous session`
- 排序方式：`Sort: Created at`
- 搜索提示：`Type to search`
- 表头：创建时间、更新时间、分支、工作目录、对话主题
- 空状态：`No sessions yet`
- 底部操作提示

### 恢复选择器实现

```rust
// codex-rs/tui/src/resume_picker.rs
pub struct ResumePicker {
    sessions: Vec<SessionMetadata>,
    selected_index: usize,
    sort_by: SortBy,
    search_query: String,
}

impl ResumePicker {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        // 渲染标题和排序
        // 渲染搜索框
        // 渲染表头
        // 渲染会话列表或空状态
        // 渲染底部操作提示
    }
}
```

## 关键代码路径与文件引用

1. **恢复选择器**：
   - `codex-rs/tui/src/resume_picker.rs`
   - `codex-rs/tui_app_server/src/resume_picker.rs`

2. **会话管理**：
   - `codex_core::session`

## 依赖与外部交互

### 会话元数据
- `SessionMetadata` - 会话元数据结构
- 创建时间、更新时间、分支、CWD、对话主题

## 风险、边界与改进建议

### 潜在风险
1. **会话过多**：大量会话可能导致列表过长
2. **信息泄露**：会话主题可能包含敏感信息

### 边界情况
1. 会话文件损坏
2. 会话目录不可访问
3. 会话元数据不完整

### 改进建议
1. 添加会话预览功能
2. 支持会话删除
3. 添加会话搜索和过滤
4. 支持会话分组（按项目、日期等）
