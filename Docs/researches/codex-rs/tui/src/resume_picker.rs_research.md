# resume_picker.rs 研究文档

## 场景与职责

`resume_picker.rs` 是 Codex TUI 的会话恢复选择器模块，负责在用户启动时或执行 `/resume`、`/fork` 命令时，提供一个交互式界面让用户浏览、搜索并选择历史会话。该模块实现了完整的分页列表 UI，支持两种操作模式：

1. **Resume 模式**：恢复选中的历史会话，继续之前的对话
2. **Fork 模式**：基于选中的历史会话创建分支，开启新会话但保留历史上下文

该模块是 TUI 应用的核心入口组件之一，直接影响用户的工作流连续性体验。

## 功能点目的

### 1. 会话列表展示
- 以表格形式展示历史会话，包含以下列：
  - **Created at**: 会话创建时间（人类可读格式，如 "16 minutes ago"）
  - **Updated at**: 最后更新时间
  - **Branch**: Git 分支名（截断显示）
  - **CWD**: 工作目录（截断显示）
  - **Conversation**: 会话预览（首条用户消息或自定义会话名）

### 2. 智能搜索过滤
- 支持实时输入搜索关键词
- 本地过滤：在已加载数据中匹配预览文本和会话名
- 远程搜索：当本地无结果且存在更多分页时，自动触发后端扫描

### 3. 分页加载机制
- 基于 Cursor 的分页加载，每页默认 25 条（`PAGE_SIZE = 25`）
- 智能预加载：当用户滚动到距离底部 5 条（`LOAD_NEAR_THRESHOLD = 5`）时自动加载下一页
- 去重机制：使用 `seen_paths: HashSet<PathBuf>` 防止分页边界处的重复项

### 4. 排序切换
- 支持按创建时间（CreatedAt）或更新时间（UpdatedAt）排序
- 通过 Tab 键切换，切换后重新加载整个列表

### 5. 响应式布局
- 根据终端宽度动态决定显示哪些列
- 窄屏时优先显示当前排序对应的时间列
- 确保预览列至少有 10 字符宽度（`MIN_PREVIEW_WIDTH`）

## 具体技术实现

### 关键数据结构

```rust
// 会话选择结果枚举
pub enum SessionSelection {
    StartFresh,                    // 开始新会话
    Resume(SessionTarget),         // 恢复会话
    Fork(SessionTarget),           // 分叉会话
    Exit,                          // 退出应用
}

// 会话目标信息
pub struct SessionTarget {
    pub path: PathBuf,             // 会话文件路径
    pub thread_id: ThreadId,       // 线程 ID
}

// 选择器状态
struct PickerState {
    codex_home: PathBuf,
    requester: FrameRequester,
    pagination: PaginationState,   // 分页状态
    all_rows: Vec<Row>,            // 所有已加载行
    filtered_rows: Vec<Row>,       // 过滤后的行
    seen_paths: HashSet<PathBuf>,  // 去重集合
    selected: usize,               // 当前选中索引
    scroll_top: usize,             // 滚动位置
    query: String,                 // 搜索查询
    search_state: SearchState,     // 搜索状态
    sort_key: ThreadSortKey,       // 排序键
    thread_name_cache: HashMap<ThreadId, Option<String>>, // 会话名缓存
}

// 行数据
struct Row {
    path: PathBuf,
    preview: String,               // 首条用户消息预览
    thread_id: Option<ThreadId>,
    thread_name: Option<String>,   // 自定义会话名（优先显示）
    created_at: Option<DateTime<Utc>>,
    updated_at: Option<DateTime<Utc>>,
    cwd: Option<PathBuf>,
    git_branch: Option<String>,
}
```

### 核心流程

#### 1. 初始化流程 (`run_session_picker`)
```
1. 进入备用屏幕模式 (AltScreenGuard)
2. 创建后台事件通道 (mpsc::unbounded_channel)
3. 配置过滤条件（当前工作目录或全部）
4. 创建异步页面加载器 (PageLoader)
5. 初始化 PickerState 并触发初始加载
6. 进入事件循环处理 TUI 事件和后台事件
```

#### 2. 页面加载流程
```rust
// 异步加载页面数据
let page = RolloutRecorder::list_threads(
    &config,
    PAGE_SIZE,
    request.cursor.as_ref(),
    request.sort_key,
    INTERACTIVE_SESSION_SOURCES,
    Some(provider_filter.as_slice()),
    request.default_provider.as_str(),
    /*search_term*/ None,
).await;
```

#### 3. 键盘事件处理 (`handle_key`)
| 按键 | 功能 |
|------|------|
| Enter | 选中当前项，返回 Resume/Fork 结果 |
| Esc | 取消，返回 StartFresh |
| Ctrl+C | 退出应用，返回 Exit |
| Up/Down | 上下移动选择 |
| PageUp/PageDown | 翻页 |
| Tab | 切换排序方式 |
| Backspace | 删除搜索字符 |
| 字符键 | 输入搜索内容 |

#### 4. 搜索实现
```rust
fn set_query(&mut self, new_query: String) {
    // 1. 更新查询并本地过滤
    self.query = new_query;
    self.apply_filter();
    
    // 2. 如果本地无结果且还有更多数据，触发远程搜索
    if self.filtered_rows.is_empty() && !self.pagination.reached_scan_cap {
        let token = self.allocate_search_token();
        self.search_state = SearchState::Active { token };
        self.load_more_if_needed(LoadTrigger::Search { token });
    }
}
```

#### 5. 渲染流程 (`draw_picker`)
```
Layout 垂直分割：
- Header (1行): 标题 + 排序方式
- Search (1行): 搜索框或错误提示
- Columns (1行): 列标题
- List (剩余): 会话列表
- Hint (1行): 操作提示
```

### 列宽度计算

```rust
struct ColumnMetrics {
    max_created_width: usize,
    max_updated_width: usize,
    max_branch_width: usize,
    max_cwd_width: usize,
    labels: Vec<(String, String, String, String)>, // 预计算的标签
}

// 分支和 CWD 使用右截断（显示尾部）
fn right_elide(s: &str, max: usize) -> String {
    if s.chars().count() <= max {
        return s.to_string();
    }
    let tail_len = max - 1;
    let tail: String = s.chars().rev().take(tail_len).collect::<String>()
        .chars().rev().collect();
    format!("…{tail}")
}
```

## 关键代码路径与文件引用

### 本文件关键函数

| 函数 | 行号 | 职责 |
|------|------|------|
| `run_resume_picker` | 122 | 公开 API：运行恢复选择器 |
| `run_fork_picker` | 130 | 公开 API：运行分叉选择器 |
| `run_session_picker` | 138 | 核心实现：初始化并运行事件循环 |
| `draw_picker` | 872 | 渲染整个选择器界面 |
| `render_list` | 941 | 渲染会话列表 |
| `render_column_headers` | 1152 | 渲染列标题 |
| `calculate_column_metrics` | 1230 | 计算列宽度 |
| `column_visibility` | 1296 | 决定列显示/隐藏 |
| `handle_key` | 403 | 处理键盘输入 |
| `ingest_page` | 560 | 处理加载的页面数据 |
| `update_thread_names` | 584 | 异步更新会话名缓存 |

### 依赖的外部模块

| 模块 | 路径 | 用途 |
|------|------|------|
| `RolloutRecorder` | `codex_core::RolloutRecorder` | 后端会话列表查询 |
| `ThreadItem` | `codex_core::ThreadItem` | 会话数据模型 |
| `ThreadSortKey` | `codex_core::ThreadSortKey` | 排序键枚举 |
| `find_thread_names_by_ids` | `codex_core` | 批量查询会话名 |
| `path_utils` | `codex_core::path_utils` | 路径比较 |
| `ThreadId` | `codex_protocol::ThreadId` | 线程 ID 类型 |
| `display_path_for` | `crate::diff_render` | 路径显示格式化 |
| `truncate_text` | `crate::text_formatting` | 文本截断 |
| `key_hint` | `crate::key_hint` | 按键提示渲染 |

### 调用方

| 文件 | 函数/代码 | 用途 |
|------|----------|------|
| `lib.rs` | `resolve_session_thread_id` | 解析会话线程 ID |
| `lib.rs` | CLI 参数处理（`--resume`, `--fork` 等） | 启动时恢复/分叉 |
| `app.rs` | `/resume`, `/fork` 命令处理 | 运行时恢复/分叉 |

## 依赖与外部交互

### 后端数据流

```
resume_picker.rs
    ↓ PageLoadRequest
RolloutRecorder::list_threads (codex_core)
    ↓
文件系统扫描: ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
    ↓
ThreadsPage { items: Vec<ThreadItem>, next_cursor, ... }
```

### 会话索引交互

```rust
// 异步更新会话名缓存
async fn update_thread_names(&mut self) {
    // 1. 收集缺失的 thread_id
    // 2. 调用 find_thread_names_by_ids 批量查询
    let names = find_thread_names_by_ids(&self.codex_home, &missing_ids)
        .await
        .unwrap_or_default();
    // 3. 更新缓存并重新过滤
}
```

### TUI 框架集成

- **ratatui**: 用于 UI 渲染（Layout、Rect、Span、Line、Paragraph 等）
- **crossterm**: 用于键盘事件处理（KeyCode、KeyEvent、KeyModifiers）
- **tokio**: 用于异步运行时和通道通信

## 风险、边界与改进建议

### 已知风险

1. **会话名加载延迟**
   - 会话名从 `session_index.jsonl` 异步加载，初始显示可能为预览文本而非自定义名
   - 已在 `update_thread_names` 中实现，但依赖文件系统 IO

2. **分页边界重复**
   - 新会话可能在分页过程中创建，导致跨页重复
   - 使用 `seen_paths: HashSet` 去重，但会增加内存占用

3. **搜索扫描上限**
   - 后端扫描有硬上限，搜索可能无法找到旧会话
   - UI 会显示 "Search scanned first N sessions; more may exist" 提示

4. **路径比较性能**
   - `paths_match` 使用规范化路径比较，在大量会话时可能成为瓶颈

### 边界情况处理

| 场景 | 处理方式 |
|------|----------|
| 无历史会话 | 显示 "No sessions yet" |
| 搜索无结果 | 显示 "No results for your search" |
| 扫描达到上限 | 显示扫描数量提示 |
| 选中项元数据读取失败 | 显示内联错误信息 |
| 终端极窄 | 动态隐藏非必要列，确保预览列最小宽度 |

### 改进建议

1. **性能优化**
   - 考虑使用虚拟列表（virtual list）处理大量会话，减少渲染开销
   - 会话名缓存可持久化到内存，减少重复文件读取

2. **功能增强**
   - 支持多选批量操作
   - 添加会话删除功能
   - 支持按更多维度过滤（如 Git 分支、模型提供者）

3. **可访问性**
   - 添加更多键盘快捷键（如跳转到首/尾项）
   - 支持搜索语法（如 `branch:main`）

4. **代码结构**
   - 文件较长（约 2000 行），可考虑将渲染逻辑拆分到独立模块
   - 测试覆盖率良好，但部分集成测试被注释（TODO 标记）

### 测试

模块包含全面的单元测试和快照测试：
- `head_to_row_uses_first_user_message`: 验证预览文本提取
- `rows_from_items_preserves_backend_order`: 验证顺序保持
- `resume_table_snapshot`: UI 快照测试
- `resume_picker_thread_names_snapshot`: 会话名显示测试
- `pageless_scrolling_deduplicates_and_keeps_order`: 分页去重测试
