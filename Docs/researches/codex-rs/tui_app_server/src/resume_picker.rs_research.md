# resume_picker.rs 研究文档

## 场景与职责

`resume_picker.rs` 是 Codex TUI 应用服务器中的**会话选择器模块**，负责提供一个交互式的全屏界面，让用户可以：

1. **恢复 (Resume)** 之前的会话 - 继续之前的对话线程
2. **分叉 (Fork)** 之前的会话 - 基于已有会话创建新的分支
3. **开始新会话 (StartFresh)** - 放弃恢复，创建全新会话
4. **退出 (Exit)** - 直接退出应用

该模块是用户进入主 TUI 界面前的**入口门户**，在启动流程中由 `lib.rs` 调用，根据用户选择决定后续的应用状态。

## 功能点目的

### 1. 会话列表展示
- 显示历史会话的元数据：创建时间、更新时间、Git 分支、工作目录、对话预览
- 支持按创建时间或更新时间排序（通过 Tab 键切换）
- 自适应列宽：根据终端宽度动态决定显示哪些列

### 2. 搜索与过滤
- **实时搜索**：用户输入时即时过滤会话列表
- **本地过滤**：基于当前工作目录过滤（除非使用 `--all` 标志）
- **Provider 过滤**：根据模型提供商过滤（本地模式）

### 3. 分页加载
- 游标分页 (Cursor-based Pagination)：避免一次性加载所有会话
- 按需加载：滚动接近底部时自动加载更多
- 搜索驱动加载：搜索无结果时自动加载更多数据继续搜索

### 4. 双数据源支持
- **Rollout 数据源**：本地文件系统存储的历史会话
- **AppServer 数据源**：通过 app-server 协议获取的远程/服务端会话

## 具体技术实现

### 核心数据结构

```rust
// 会话选择结果
pub enum SessionSelection {
    StartFresh,
    Resume(SessionTarget),
    Fork(SessionTarget),
    Exit,
}

// 会话目标
pub struct SessionTarget {
    pub path: Option<PathBuf>,
    pub thread_id: ThreadId,
}

// 行数据
struct Row {
    path: Option<PathBuf>,
    preview: String,
    thread_id: Option<ThreadId>,
    thread_name: Option<String>,
    created_at: Option<DateTime<Utc>>,
    updated_at: Option<DateTime<Utc>>,
    cwd: Option<PathBuf>,
    git_branch: Option<String>,
}

// 分页状态
struct PaginationState {
    next_cursor: Option<PageCursor>,
    num_scanned_files: usize,
    reached_scan_cap: bool,
    loading: LoadingState,
}
```

### 关键流程

#### 1. 初始化流程
```
run_resume_picker_with_app_server
  └── run_session_picker_with_loader
      ├── AltScreenGuard::enter(tui)     // 进入备用屏幕
      ├── PickerState::new()             // 初始化状态
      ├── start_initial_load()           // 开始初始加载
      └── 事件循环
```

#### 2. 事件循环
使用 `tokio::select!` 同时处理两类事件：
- **TUI 事件**：键盘输入、绘制请求
- **后台事件**：分页数据加载完成

```rust
loop {
    tokio::select! {
        Some(ev) = tui_events.next() => { /* 处理键盘/绘制 */ }
        Some(event) = background_events.next() => { /* 处理加载完成 */ }
    }
}
```

#### 3. 分页加载机制
```rust
fn load_more_if_needed(&mut self, trigger: LoadTrigger) {
    // 1. 检查是否已在加载中
    // 2. 检查是否还有下一页
    // 3. 分配请求令牌
    // 4. 调用 page_loader 闭包发送加载请求
}
```

#### 4. 搜索流程
```
用户输入搜索词
  └── set_query()
      ├── apply_filter()           // 本地过滤已有数据
      └── 如果过滤结果为空且还有数据
          └── continue_search_if_needed()
              └── load_more_if_needed(LoadTrigger::Search)
```

### 渲染系统

#### 布局结构（垂直布局）
```
┌─────────────────────────────────────┐
│ Header: "Resume a previous session" │  // 1行
├─────────────────────────────────────┤
│ Search: query                       │  // 1行
├─────────────────────────────────────┤
│ Created at  Updated at  Branch  CWD │  // 1行（列头）
├─────────────────────────────────────┤
│ > 16 minutes ago  Fix resume picker │  // 列表区域（动态高度）
│   1 hour ago      Investigate lazy  │
│   2 hours ago     Explain codebase  │
├─────────────────────────────────────┤
│ Enter to resume  Esc to start new   │  // 1行（提示）
└─────────────────────────────────────┘
```

#### 列可见性算法
```rust
fn column_visibility(area_width: u16, metrics: &ColumnMetrics, sort_key: ThreadSortKey) -> ColumnVisibility {
    const MIN_PREVIEW_WIDTH: usize = 10;
    // 1. 计算剩余宽度
    // 2. 如果预览区太窄，只显示与排序键对应的时间戳列
    // 3. Branch/CWD 列只在有数据时显示
}
```

### 键盘处理

| 按键 | 动作 |
|------|------|
| `Enter` | 确认选择（Resume/Fork） |
| `Esc` | 开始新会话 |
| `Ctrl+C` | 退出应用 |
| `Tab` | 切换排序键（CreatedAt/UpdatedAt） |
| `↑/↓` | 上下移动选择 |
| `PageUp/PageDown` | 翻页 |
| 字符输入 | 搜索过滤 |
| `Backspace` | 删除搜索字符 |

## 关键代码路径与文件引用

### 入口点
- `run_resume_picker_with_app_server()` - 带 app-server 的恢复选择器
- `run_fork_picker_with_app_server()` - 带 app-server 的分叉选择器

### 状态管理
- `PickerState` - 主状态结构（404-426行）
- `PickerState::handle_key()` - 键盘事件处理（588-686行）
- `PickerState::ingest_page()` - 数据页摄入（752-777行）

### 渲染函数
- `draw_picker()` - 主渲染函数（1133-1190行）
- `render_list()` - 列表渲染（1202-1333行）
- `render_column_headers()` - 列头渲染（1413-1463行）
- `calculate_column_metrics()` - 列宽计算（1491-1550行）

### 数据转换
- `picker_page_from_rollout_page()` - Rollout 数据转换（1023-1030行）
- `row_from_app_server_thread()` - AppServer 数据转换（1066-1091行）
- `head_to_row()` - ThreadItem 转 Row（1038-1064行）

### 后台加载
- `spawn_app_server_page_loader()` - AppServer 分页加载器（341-376行）
- `spawn_rollout_page_loader()` - Rollout 分页加载器（301-339行）
- `load_app_server_page()` - 实际加载逻辑（464-486行）

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `crate::tui::Tui` | TUI 框架封装 |
| `crate::key_hint` | 键盘提示渲染 |
| `crate::text_formatting::truncate_text` | 文本截断 |
| `crate::diff_render::display_path_for` | 路径显示格式化 |

### 外部 crate 依赖
| Crate | 用途 |
|-------|------|
| `ratatui` | 终端 UI 渲染框架 |
| `crossterm` | 跨平台终端控制（键盘事件） |
| `tokio` | 异步运行时 |
| `chrono` | 时间处理 |
| `color-eyre` | 错误处理 |
| `unicode_width` | Unicode 字符宽度计算 |

### Core/Protocol 依赖
| 模块 | 用途 |
|------|------|
| `codex_core::RolloutRecorder` | 本地会话记录读取 |
| `codex_core::ThreadSortKey` | 排序键类型 |
| `codex_app_server_protocol::*` | AppServer 通信协议 |
| `codex_protocol::ThreadId` | 线程 ID 类型 |

## 风险、边界与改进建议

### 已知风险

1. **线程名称缓存竞争**
   - `update_thread_names()` 异步加载线程名称，可能在用户快速滚动时产生竞态
   - 已使用 `thread_name_cache` 缓解，但仍可能在极端情况下显示过时数据

2. **搜索令牌过期**
   - 使用简单的 `usize` 令牌，极端情况下可能回绕（虽然实际几乎不可能发生）

3. **路径比较精度**
   - `paths_match()` 使用规范化路径比较，但在某些文件系统上可能存在边缘情况

### 边界情况

1. **空列表处理**
   - `render_empty_state_line()` 处理多种空状态：无会话、搜索无结果、加载中

2. **极窄终端**
   - `column_visibility()` 确保至少保留 `MIN_PREVIEW_WIDTH` 给预览列

3. **远程会话 CWD 过滤**
   - 远程会话禁用本地 CWD 过滤（244-248行注释说明）

### 改进建议

1. **性能优化**
   - 考虑使用虚拟列表 (virtual list) 处理超大会话列表
   - 搜索过滤可移至后台线程避免阻塞 UI

2. **功能增强**
   - 支持正则表达式搜索
   - 添加会话标签/分类支持
   - 支持多选批量操作

3. **代码质量**
   - `resume_picker_orders_by_updated_at` 测试被注释（1664-1748行），建议修复或移除
   - `spawn_rollout_page_loader` 标记为 `#[allow(dead_code)]`，需确认是否仍需要

4. **可访问性**
   - 添加更多键盘快捷键（如直接跳转到指定序号）
   - 支持屏幕阅读器友好的输出模式

### 测试覆盖

模块包含全面的单元测试（1604行起）：
- `head_to_row_uses_first_user_message` - 数据转换测试
- `rows_from_items_preserves_backend_order` - 顺序保持测试
- `row_uses_tail_timestamp_for_updated_at` - 时间戳处理测试
- `resume_table_snapshot` - 快照测试（UI 渲染）
- `resume_search_error_snapshot` - 错误状态快照测试
