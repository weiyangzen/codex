# Resume Picker 屏幕快照研究文档

## 场景与职责

该快照测试验证 **Resume Picker（会话恢复选择器）** 的完整界面渲染，展示当没有可用会话时的空状态界面。这是用户启动 Codex TUI 时可能看到的初始界面之一，用于选择恢复之前的会话或开始新会话。

### 核心职责
- 展示会话列表，支持分页加载
- 提供搜索功能，按会话内容过滤
- 支持排序切换（创建时间/更新时间）
- 处理会话选择（恢复、Fork、新建）

### 使用场景
1. 用户启动 Codex CLI，系统检测到历史会话
2. 显示 Resume Picker 界面，列出可恢复的会话
3. 用户可以选择：
   - 恢复（Resume）之前的会话
   - Fork 一个会话（基于历史创建新分支）
   - 开始新会话（Start Fresh）
   - 退出程序

## 功能点目的

### 1. 会话列表展示
- 表格形式展示会话信息：
  - Created at: 创建时间（相对时间，如 "16 minutes ago"）
  - Updated at: 更新时间
  - Branch: Git 分支
  - CWD: 工作目录
  - Conversation: 对话预览（第一条用户消息）

### 2. 搜索与过滤
- 实时搜索：输入时即时过滤
- 后端搜索：当本地无结果时，继续搜索后端
- 工作目录过滤：默认只显示当前目录的会话（`--all` 可显示全部）

### 3. 排序功能
- 支持按创建时间（Created at）或更新时间（Updated at）排序
- Tab 键切换排序方式
- 切换后重新加载列表

### 4. 键盘导航
- ↑/↓: 浏览会话
- Enter: 恢复/选中会话
- Esc: 开始新会话
- Ctrl+C: 退出
- Tab: 切换排序

## 具体技术实现

### 关键数据结构

```rust
// 会话选择结果
#[derive(Debug, Clone)]
pub enum SessionSelection {
    StartFresh,                              // 开始新会话
    Resume(SessionTarget),                   // 恢复会话
    Fork(SessionTarget),                     // Fork 会话
    Exit,                                    // 退出
}

pub struct SessionTarget {
    pub path: PathBuf,                       // 会话文件路径
    pub thread_id: ThreadId,                 // 线程 ID
}

// 选择器操作类型
#[derive(Clone, Copy, Debug)]
pub enum SessionPickerAction {
    Resume,                                  // 恢复模式
    Fork,                                    // Fork 模式
}

// 状态结构
struct PickerState {
    codex_home: PathBuf,
    requester: FrameRequester,
    pagination: PaginationState,             // 分页状态
    all_rows: Vec<Row>,                      // 所有行
    filtered_rows: Vec<Row>,                 // 过滤后的行
    seen_paths: HashSet<PathBuf>,            // 已见路径（去重）
    selected: usize,                         // 当前选中索引
    scroll_top: usize,                       // 滚动顶部
    query: String,                           // 搜索查询
    search_state: SearchState,               // 搜索状态
    sort_key: ThreadSortKey,                 // 排序键
    thread_name_cache: HashMap<ThreadId, Option<String>>, // 线程名称缓存
    inline_error: Option<String>,            // 行内错误
    ...
}

struct Row {
    path: PathBuf,
    preview: String,                         // 对话预览
    thread_id: Option<ThreadId>,
    thread_name: Option<String>,             // 线程名称（优先于 preview 显示）
    created_at: Option<DateTime<Utc>>,
    updated_at: Option<DateTime<Utc>>,
    cwd: Option<PathBuf>,
    git_branch: Option<String>,
}
```

### 主循环流程

```rust
async fn run_session_picker(...) -> Result<SessionSelection> {
    // 1. 进入备用屏幕
    let alt = AltScreenGuard::enter(tui);
    
    // 2. 创建后台加载器
    let page_loader: PageLoader = Arc::new(move |request: PageLoadRequest| {
        // 异步加载会话页面
        tokio::spawn(async move {
            let page = RolloutRecorder::list_threads(...).await;
            tx.send(BackgroundEvent::PageLoaded { ... });
        });
    });
    
    // 3. 初始化状态
    let mut state = PickerState::new(...);
    state.start_initial_load();
    
    // 4. 事件循环
    loop {
        tokio::select! {
            Some(ev) = tui_events.next() => {
                // 处理键盘、绘制事件
                if let Some(sel) = state.handle_key(key).await? {
                    return Ok(sel);
                }
            }
            Some(event) = background_events.next() => {
                // 处理后台加载完成事件
                state.handle_background_event(event).await?;
            }
        }
    }
}
```

### 渲染布局

```rust
fn draw_picker(tui: &mut Tui, state: &PickerState) {
    // 垂直布局：[header, search, columns, list, hint]
    let [header, search, columns, list, hint] = Layout::vertical([
        Constraint::Length(1),   // 标题行
        Constraint::Length(1),   // 搜索行
        Constraint::Length(1),   // 列标题
        Constraint::Min(...),    // 列表区域
        Constraint::Length(1),   // 提示行
    ]).areas(area);
    
    // Header: "Resume a previous session  Sort: Created at"
    // Search: "Type to search" 或错误信息
    // Columns: "Created at  Updated at  Branch  CWD  Conversation"
    // List: 会话列表或 "No sessions yet"
    // Hint: 快捷键提示
}
```

### 测试用例分析

```rust
#[test]
fn resume_picker_screen() {
    // 注意：此测试被注释掉了，当前快照来自简化版本
    // 测试验证空状态界面渲染
    
    // 创建状态（无会话）
    let mut state = PickerState::new(...);
    // all_rows 为空，filtered_rows 为空
    
    // 渲染界面
    draw_picker(&mut tui, &state)?;
    
    // 验证快照
}
```

### 快照输出解析

```
Resume a previous session  Sort: Created at    // 标题 + 排序方式
Type to search                                   // 搜索提示
  Created at  Updated at  Branch  CWD  Conversation  // 列标题
No sessions yet                                  // 空状态提示



enter to resume     esc to start new     ctrl + c to quit     tab to toggle sort
// 底部快捷键提示
```

## 关键代码路径与文件引用

### 核心文件
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui/src/resume_picker.rs` | Resume Picker 完整实现 |

### 关键函数

1. **入口函数**
   - `run_resume_picker()` (line 122-128)
   - `run_fork_picker()` (line 130-136)
   - `run_session_picker()` (line 138-228)

2. **状态管理**
   - `PickerState::new()` (line 360-397)
   - `PickerState::handle_key()` (line 403-494)
   - `PickerState::start_initial_load()` (line 496-526)
   - `PickerState::handle_background_event()` (line 528-551)

3. **渲染**
   - `draw_picker()` (line 872-929)
   - `search_line()` (line 931-939)
   - `render_list()` (line 941-1072)
   - `render_column_headers()` (line 1152-1202)
   - `render_empty_state_line()` (line 1074-1100)

4. **数据转换**
   - `rows_from_items()` (line 824-826)
   - `head_to_row()` (line 828-854)
   - `human_time_ago()` (line 1102-1135)

### 列宽计算

```rust
struct ColumnMetrics {
    max_created_width: usize,
    max_updated_width: usize,
    max_branch_width: usize,
    max_cwd_width: usize,
    labels: Vec<(String, String, String, String)>,  // 每行的标签
}

fn calculate_column_metrics(rows: &[Row], include_cwd: bool) -> ColumnMetrics {
    // 计算每列最大宽度，支持 Unicode 宽度
    // Branch 和 CWD 使用右截断（right_elide）
}
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `ratatui` | 终端 UI 框架 |
| `crossterm` | 键盘事件 |
| `tokio` | 异步运行时 |
| `chrono` | 时间处理 |
| `unicode_width` | Unicode 宽度计算 |
| `codex_core` | `RolloutRecorder`, `ThreadItem`, `Cursor` |
| `codex_protocol` | `ThreadId` |

### 内部模块交互

```
resume_picker.rs
├── codex_core::RolloutRecorder (后端会话列表)
├── codex_core::find_thread_names_by_ids (线程名称查询)
├── diff_render.rs (路径显示)
├── key_hint.rs (快捷键提示)
├── text_formatting.rs (文本截断)
└── tui.rs (TUI 基础)
```

### 后端交互

```rust
// 加载会话页面
RolloutRecorder::list_threads(
    &config,
    PAGE_SIZE,                    // 25
    request.cursor.as_ref(),      // 分页游标
    request.sort_key,             // 排序键
    INTERACTIVE_SESSION_SOURCES,  // 仅交互式会话
    Some(provider_filter.as_slice()), // 提供商过滤
    request.default_provider.as_str(),
    /*search_term*/ None,         // 搜索词（当前未使用）
).await
```

## 风险、边界与改进建议

### 潜在风险

1. **分页去重**
   - 使用 `seen_paths` HashSet 去重
   - 新会话在分页过程中创建可能导致重复或遗漏

2. **搜索性能**
   - 当前搜索在前端过滤已加载数据
   - 大数据集时可能需要后端搜索支持

3. **时间显示**
   - `human_time_ago` 使用相对时间，可能因时区产生歧义

### 边界情况

1. **空状态**
   - 无会话时显示 "No sessions yet"
   - 搜索无结果时显示 "No results for your search"

2. **列宽不足**
   - 终端过窄时，根据排序键优先显示对应时间列
   - `column_visibility()` 函数处理 (line 1296-1341)

3. **线程名称加载**
   - 异步加载线程名称，可能延迟显示
   - 使用 `thread_name_cache` 避免重复查询

### 改进建议

1. **搜索增强**
   - 支持正则表达式搜索
   - 支持按时间范围过滤
   - 后端搜索支持（大数据集）

2. **预览功能**
   - 选中会话时显示更多详情
   - 支持预览会话内容

3. **批量操作**
   - 支持删除多个会话
   - 支持导出会话

4. **性能优化**
   - 虚拟滚动（大量会话时）
   - 预加载下一页

5. **测试覆盖**
   - 当前 `resume_picker_screen` 测试被注释
   - 建议恢复并完善测试
