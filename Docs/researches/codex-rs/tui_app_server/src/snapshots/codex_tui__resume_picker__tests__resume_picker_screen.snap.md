# Resume Picker 全屏界面快照测试文档

## 场景与职责

此快照文件对应 `tui/src/resume_picker.rs` 中的 `resume_picker_screen_snapshot` 测试（当前被注释为 `TODO(jif) fix`），用于验证 Resume Picker 的完整全屏界面渲染。Resume Picker 是 Codex CLI 的会话恢复选择器，允许用户浏览、搜索和选择之前保存的会话记录。

该组件的主要职责包括：
- 在备用屏幕（alternate screen）中显示可恢复的会话列表
- 支持按创建时间或更新时间排序
- 提供实时搜索过滤功能
- 显示会话的元数据（时间戳、分支、工作目录、对话预览）
- 支持恢复（Resume）或分叉（Fork）已有会话

## 功能点目的

### 全屏界面渲染验证
此测试验证 Resume Picker 的完整界面布局，包括：

1. **标题栏**：显示 "Resume a previous session" 和操作模式
2. **搜索栏**：显示 "Type to search" 提示
3. **表头**：显示列标题（Created at、Updated at、Branch、CWD、Conversation）
4. **内容区**：显示会话列表或空状态
5. **底部提示栏**：显示键盘快捷键（enter to resume、esc to start new 等）

### 快照内容解析
```
Resume a previous session  Sort: Created at     <- 标题栏，显示当前排序方式
Type to search                                      <- 搜索栏提示
  Created at  Updated at  Branch  CWD  Conversation  <- 表头
No sessions yet                                     <- 空状态提示



enter to resume     esc to start new     ctrl + c to quit     tab to toggle sort  <- 底部提示
```

### 界面布局结构
```
┌─────────────────────────────────────────────────────────────────┐
│ Resume a previous session  Sort: Created at                     │ 标题行 (1行)
├─────────────────────────────────────────────────────────────────┤
│ Type to search                                                  │ 搜索行 (1行)
├─────────────────────────────────────────────────────────────────┤
│   Created at  Updated at  Branch  CWD  Conversation             │ 表头行 (1行)
├─────────────────────────────────────────────────────────────────┤
│ No sessions yet                                                 │ 内容区 (动态)
│                                                                 │
│                                                                 │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│ enter to resume  esc to start new  ctrl+c to quit  tab to sort  │ 提示行 (1行)
└─────────────────────────────────────────────────────────────────┘
```

## 具体技术实现

### 核心数据结构

```rust
pub struct SessionTarget {
    pub path: PathBuf,
    pub thread_id: ThreadId,
}

pub enum SessionSelection {
    StartFresh,
    Resume(SessionTarget),
    Fork(SessionTarget),
    Exit,
}

enum SessionPickerAction {
    Resume,  // "Resume a previous session"
    Fork,    // "Fork a previous session"
}

struct PickerState {
    codex_home: PathBuf,
    requester: FrameRequester,
    pagination: PaginationState,
    all_rows: Vec<Row>,           // 所有会话行
    filtered_rows: Vec<Row>,      // 过滤后的行
    seen_paths: HashSet<PathBuf>, // 去重集合
    selected: usize,              // 当前选中索引
    scroll_top: usize,            // 滚动顶部索引
    query: String,                // 搜索查询
    search_state: SearchState,
    sort_key: ThreadSortKey,      // CreatedAt 或 UpdatedAt
    thread_name_cache: HashMap<ThreadId, Option<String>>,
    inline_error: Option<String>,
}

struct Row {
    path: PathBuf,
    preview: String,              // 对话预览（首条用户消息）
    thread_id: Option<ThreadId>,
    thread_name: Option<String>,  // 会话名称（优先于 preview 显示）
    created_at: Option<DateTime<Utc>>,
    updated_at: Option<DateTime<Utc>>,
    cwd: Option<PathBuf>,
    git_branch: Option<String>,
}
```

### 渲染流程

1. **主入口** (`run_resume_picker`):
   ```rust
   pub async fn run_resume_picker(
       tui: &mut Tui,
       config: &Config,
       show_all: bool,
   ) -> Result<SessionSelection>
   ```

2. **界面布局** (`draw_picker`):
   ```rust
   let [header, search, columns, list, hint] = Layout::vertical([
       Constraint::Length(1),                           // 标题
       Constraint::Length(1),                           // 搜索
       Constraint::Length(1),                           // 表头
       Constraint::Min(area.height.saturating_sub(4)),  // 内容
       Constraint::Length(1),                           // 提示
   ])
   .areas(area);
   ```

3. **列宽计算** (`calculate_column_metrics`):
   - 根据内容动态计算每列的最大宽度
   - 使用 Unicode 显示宽度（非字节长度）处理多字节字符
   - 分支和 CWD 列使用右侧截断（`right_elide`）

4. **列可见性** (`column_visibility`):
   - 窄终端时隐藏非活动排序列
   - 确保预览列至少有 `MIN_PREVIEW_WIDTH`（10字符）

### 分页与加载机制

```rust
const PAGE_SIZE: usize = 25;
const LOAD_NEAR_THRESHOLD: usize = 5;

struct PaginationState {
    next_cursor: Option<Cursor>,
    num_scanned_files: usize,
    reached_scan_cap: bool,
    loading: LoadingState,
}
```

- **初始加载**: 启动时加载第一页
- **滚动加载**: 当剩余行数 ≤ 5 时自动加载下一页
- **搜索加载**: 搜索无结果且未达扫描上限时继续加载

## 关键代码路径与文件引用

### 主要源文件
- `codex-rs/tui/src/resume_picker.rs` - Resume Picker 完整实现

### 依赖模块
- `codex-rs/tui/src/key_hint.rs` - 键盘提示渲染
- `codex-rs/tui/src/text_formatting.rs` - 文本截断工具
- `codex-rs/tui/src/diff_render.rs` - 路径显示格式化
- `codex-core/src/lib.rs` - `RolloutRecorder::list_threads`
- `codex-core/src/config.rs` - Config 结构

### 测试代码位置
```rust
// 位于 codex-rs/tui/src/resume_picker.rs:1682-1850
// 注意：当前被注释为 TODO(jif) fix
#[tokio::test]
async fn resume_picker_screen_snapshot() {
    // ... 测试实现
}
```

### 相关快照文件
- `codex_tui__resume_picker__tests__resume_picker_screen.snap`（当前文件）
- `codex_tui__resume_picker__tests__resume_picker_table.snap` - 表格渲染
- `codex_tui__resume_picker__tests__resume_picker_search_error.snap` - 搜索错误
- `codex_tui__resume_picker__tests__resume_picker_thread_names.snap` - 会话名称

## 依赖与外部交互

### 外部依赖
- **ratatui**: 布局管理（`Layout`、`Constraint`、`Rect`）
- **crossterm**: 键盘事件处理
- **chrono**: 时间戳解析和格式化
- **unicode-width**: Unicode 字符宽度计算
- **tokio**: 异步运行时和通道

### 内部依赖
- **RolloutRecorder**: 后端会话数据提供者
  ```rust
  RolloutRecorder::list_threads(
      &config,
      PAGE_SIZE,
      request.cursor.as_ref(),
      request.sort_key,
      INTERACTIVE_SESSION_SOURCES,
      Some(provider_filter.as_slice()),
      request.default_provider.as_str(),
      /*search_term*/ None,
  )
  ```
- **find_thread_names_by_ids**: 异步获取会话名称

### 事件循环
```rust
loop {
    tokio::select! {
        Some(ev) = tui_events.next() => { /* 处理键盘/绘制事件 */ }
        Some(event) = background_events.next() => { /* 处理页面加载完成 */ }
    }
}
```

## 风险、边界与改进建议

### 潜在风险

1. **测试被禁用**: 
   - 当前测试被注释标记为 `TODO(jif) fix`
   - 风险：界面回归无法被自动检测
   - 建议：修复并重新启用测试

2. **异步加载竞争**:
   - 风险：快速滚动可能触发多次重叠的加载请求
   - 缓解：`request_token` 机制确保只处理最新请求

3. **搜索延迟**:
   - 风险：大数据集时前端过滤可能卡顿
   - 现状：使用 `tokio::spawn` 在后台执行

### 边界情况

1. **空状态**: 无会话时显示 "No sessions yet"
2. **搜索无结果**: 显示 "No results for your search"
3. **扫描上限**: 达到扫描上限时显示警告信息
4. **窄终端**: 列自动隐藏，优先保证预览列宽度
5. **缺失元数据**: 无法读取会话文件时显示内联错误

### 改进建议

1. **测试修复**: 修复并启用被注释的快照测试
2. **虚拟滚动**: 大数据集时使用虚拟滚动优化性能
3. **多选支持**: 支持批量恢复或删除会话
4. **预览面板**: 添加右侧预览面板显示会话详情
5. **排序指示器**: 在表头添加排序方向箭头
6. **搜索高亮**: 高亮匹配搜索词的文本
7. **会话分组**: 按日期或项目分组显示会话

### 代码质量建议

1. **错误处理**: 当前错误仅显示内联，可添加重试机制
2. **缓存策略**: `thread_name_cache` 可考虑持久化
3. **可访问性**: 添加更多键盘导航（如跳转到指定行）
