# app_backtrack.rs 深度研究文档

## 场景与职责

`app_backtrack.rs` 是 Codex TUI 中负责**回溯(backtrack)**功能的核心模块。该功能允许用户在对话历史中"回退"到之前的某个用户消息点，类似于撤销多轮对话。

### 核心场景
1. **对话回退**: 用户可以通过 Esc 键进入回溯模式，选择之前的某条用户消息，将对话状态回退到该点
2. **Transcript 覆盖层**: 提供 Ctrl+T 快捷键打开的全屏历史查看器，支持在覆盖层中浏览和选择历史消息
3. **状态同步**: 确保 UI 状态与后端(core)状态保持一致，避免 UI 超前或滞后于实际对话状态

### 职责边界
- 管理回溯相关的所有状态（`BacktrackState`）
- 处理 transcript 覆盖层的生命周期（打开/关闭/渲染）
- 协调与 `ChatWidget` 的交互（获取当前活动单元格、设置 composer 预填充文本）
- 向后端提交 `Op::ThreadRollback` 操作并处理响应

---

## 功能点目的

### 1. 回溯状态机 (Backtrack State Machine)

```rust
pub(crate) struct BacktrackState {
    pub(crate) primed: bool,                    // Esc 是否已激活回溯准备状态
    pub(crate) base_id: Option<ThreadId>,       // 基准线程ID，用于验证有效性
    pub(crate) nth_user_message: usize,         // 当前选中的用户消息索引
    pub(crate) overlay_preview_active: bool,    // 是否处于覆盖层预览模式
    pub(crate) pending_rollback: Option<PendingBacktrackRollback>, // 等待确认的 rollback
}
```

**状态流转**:
1. **初始状态**: `primed = false`, 无覆盖层
2. **准备状态**: 第一次按 Esc + composer 为空 → `primed = true`, 显示提示
3. **覆盖层模式**: 第二次按 Esc → 打开 transcript 覆盖层，进入预览模式
4. **选择状态**: 在覆盖层中使用 Esc/Left/Right 选择用户消息
5. **提交状态**: 按 Enter → 提交 `Op::ThreadRollback`，设置 `pending_rollback`
6. **完成状态**: 收到 `EventMsg::ThreadRolledBack` → 修剪本地 transcript，重置状态

### 2. Transcript 覆盖层 (Transcript Overlay)

覆盖层是一个全屏的 pager 视图，显示：
- **已提交的历史单元格** (`transcript_cells`): 已完成的对话历史
- **实时尾部** (live tail): 当前正在进行的活跃单元格（通过 `ChatWidget.active_cell_transcript_key()` 获取）

**关键设计**: 覆盖层使用缓存机制避免每帧重建渲染行。缓存键包含：
- 终端宽度（影响文本换行）
- 活跃单元格修订号（in-place 变更时递增）
- 动画 tick（时间相关的视觉效果）

### 3. 本地 Transcript 修剪

当后端确认 rollback 后，需要同步修剪本地 `transcript_cells`:

```rust
fn trim_transcript_cells_to_nth_user(
    transcript_cells: &mut Vec<Arc<dyn HistoryCell>>,
    nth_user_message: usize,
) -> bool
```

该函数找到第 n 个用户消息的位置，截断其后的所有单元格。这确保了本地 UI 状态与后端状态一致。

---

## 具体技术实现

### 关键数据结构

#### BacktrackSelection
```rust
pub(crate) struct BacktrackSelection {
    pub(crate) nth_user_message: usize,         // 用户消息序号
    pub(crate) prefill: String,                 // composer 预填充文本
    pub(crate) text_elements: Vec<TextElement>, // 文本元素（富文本）
    pub(crate) local_image_paths: Vec<PathBuf>, // 本地图片路径
    pub(crate) remote_image_urls: Vec<String>,  // 远程图片URL
}
```

当用户确认回溯时，选中的用户消息内容会被提取出来，用于：
1. 计算 rollback 深度（需要回退多少轮）
2. 预填充 composer，方便用户基于原消息编辑或重发

#### PendingBacktrackRollback
```rust
pub(crate) struct PendingBacktrackRollback {
    pub(crate) selection: BacktrackSelection,
    pub(crate) thread_id: Option<ThreadId>, // 发起 rollback 时的线程ID
}
```

用于防止并发 rollback 请求，并确保响应与请求匹配（避免线程切换后的过期响应）。

### 关键流程

#### 1. 处理覆盖层事件
```rust
pub(crate) async fn handle_backtrack_overlay_event(
    &mut self,
    tui: &mut tui::Tui,
    event: TuiEvent,
) -> Result<bool>
```

- 如果在预览模式 (`overlay_preview_active = true`):
  - `Esc/Left`: 选择更早的用户消息
  - `Right`: 选择更晚的用户消息
  - `Enter`: 确认选择并提交 rollback
- 如果不在预览模式:
  - `Esc`: 进入预览模式（选中最新用户消息）
  - 其他事件: 转发给覆盖层处理

#### 2. 应用 Rollback
```rust
pub(crate) fn apply_backtrack_rollback(&mut self, selection: BacktrackSelection)
```

流程:
1. 检查是否有正在进行的 rollback（`pending_rollback` 是否存在）
2. 计算需要回退的轮数: `user_total - selection.nth_user_message`
3. 设置 `pending_rollback` 守卫
4. 提交 `Op::ThreadRollback { num_turns }` 到后端
5. 预填充 composer（即使 rollback 失败，用户也可以继续编辑）

#### 3. 处理 ThreadRolledBack 事件
```rust
pub(crate) fn handle_backtrack_event(&mut self, event: &EventMsg)
```

区分两种情况:
- **有 pending_rollback**: 这是当前 UI 发起的 rollback，调用 `finish_pending_backtrack()` 立即处理
- **无 pending_rollback**: 这是从其他来源（如 replay）发起的 rollback，通过 `AppEvent::ApplyThreadRollback` 排队处理，确保与 `InsertHistoryCell` 事件按 FIFO 顺序处理

### 用户消息定位算法

```rust
fn user_positions_iter(
    cells: &[Arc<dyn HistoryCell>],
) -> impl Iterator<Item = usize> + '_
```

该迭代器:
1. 找到最后一个 `SessionInfoCell` 的位置（会话起点）
2. 从会话起点开始，返回所有 `UserHistoryCell` 的索引

这确保了只考虑当前会话内的用户消息，忽略历史会话的内容。

---

## 关键代码路径与文件引用

### 内部依赖

| 文件 | 用途 |
|------|------|
| `app.rs` | `App` 结构体的主实现，包含 `BacktrackState` 字段 |
| `app_event.rs` | `AppEvent::ApplyThreadRollback` 事件定义 |
| `history_cell.rs` | `HistoryCell`, `UserHistoryCell`, `SessionInfoCell` trait/struct |
| `pager_overlay.rs` | `Overlay::Transcript`, `TranscriptOverlay` 覆盖层实现 |
| `chatwidget.rs` | `ChatWidget` - 提供活跃单元格信息、提交 Op、设置 composer |
| `tui.rs` | `TuiEvent`, `FrameRequester` 用于帧调度 |

### 外部协议依赖

| 类型 | 来源 | 用途 |
|------|------|------|
| `EventMsg::ThreadRolledBack` | `codex_protocol::protocol` | 后端确认 rollback 完成 |
| `CodexErrorInfo::ThreadRollbackFailed` | `codex_protocol::protocol` | rollback 失败错误 |
| `Op::ThreadRollback` | `codex_protocol::protocol` | 提交 rollback 请求 |
| `ThreadId` | `codex_protocol` | 线程标识 |

### 关键代码路径

```
用户按 Esc (主界面)
  → handle_backtrack_esc_key()
    → prime_backtrack() [第一次] / open_backtrack_preview() [第二次]
      → open_transcript_overlay()
        → tui.enter_alt_screen()
        → Overlay::new_transcript()

用户按 Esc/Left/Right (覆盖层)
  → handle_backtrack_overlay_event()
    → step_backtrack_and_highlight() / step_forward_backtrack_and_highlight()
      → apply_backtrack_selection_internal()
        → nth_user_position() [定位用户消息]
        → TranscriptOverlay::set_highlight_cell()

用户按 Enter (覆盖层)
  → overlay_confirm_backtrack()
    → backtrack_selection() [构建 BacktrackSelection]
    → close_transcript_overlay()
    → apply_backtrack_rollback()
      → submit Op::ThreadRollback
      → set pending_rollback

收到 ThreadRolledBack 事件
  → handle_backtrack_event()
    → finish_pending_backtrack() [有 pending] 
      → trim_transcript_cells_to_nth_user()
      → sync_overlay_after_transcript_trim()
    → AppEvent::ApplyThreadRollback [无 pending]
      → apply_non_pending_thread_rollback()
```

---

## 依赖与外部交互

### 与 ChatWidget 的交互

```rust
// 获取活跃单元格的 transcript key（用于缓存）
self.chat_widget.active_cell_transcript_key()

// 获取活跃单元格的 transcript 行
self.chat_widget.active_cell_transcript_lines(width)

// 提交操作到后端
self.chat_widget.submit_op(Op::ThreadRollback { num_turns })

// 设置 composer 内容
self.chat_widget.set_composer_text(prefill, text_elements, local_image_paths)
self.chat_widget.set_remote_image_urls(remote_image_urls)
```

### 与 TranscriptOverlay 的交互

```rust
// 同步实时尾部（在 Draw 事件中调用）
t.sync_live_tail(width, active_key, |w| chat_widget.active_cell_transcript_lines(w))

// 替换单元格（rollback 后）
t.replace_cells(self.transcript_cells.clone())

// 设置高亮
t.set_highlight_cell(Some(cell_idx))
```

### 与 Core/Protocol 的交互

```rust
// 提交 rollback 请求
self.chat_widget.submit_op(Op::ThreadRollback { num_turns });

// 处理响应事件
EventMsg::ThreadRolledBack(rollback) => { ... }
EventMsg::Error(ErrorEvent { codex_error_info: Some(CodexErrorInfo::ThreadRollbackFailed), .. }) => { ... }
```

---

## 风险、边界与改进建议

### 潜在风险

1. **线程切换竞争**: 
   - 如果在 pending rollback 期间切换了线程，`finish_pending_backtrack()` 会检查 `pending.thread_id != self.chat_widget.thread_id()` 并忽略响应
   - 但用户可能困惑为什么 rollback 没有生效

2. **Transcript 不一致**:
   - 如果 `ThreadRolledBack` 事件在 `InsertHistoryCell` 事件之前处理，可能导致修剪错误的单元格
   - 解决方案: 无 pending 时使用 `AppEvent` 排队，确保 FIFO 顺序

3. **大历史记录性能**:
   - `user_positions_iter()` 每次遍历整个 transcript，O(n) 复杂度
   - 对于极长的对话（数千轮）可能产生性能问题

4. **缓存失效**:
   - `sync_live_tail` 依赖 `active_cell_transcript_key()` 返回正确的缓存键
   - 如果 `ChatWidget` 没有正确更新修订号，覆盖层可能显示过时的"实时"内容

### 边界条件

| 场景 | 处理 |
|------|------|
| 无用户消息 | `user_count() == 0` 时直接返回，不执行 rollback |
| 选择第一个用户消息 | 修剪后 transcript 为空（保留 session start 之前的单元格）|
| rollback 0 轮 | 提前返回，不提交 Op |
| usize 溢出 | 使用 `saturating_sub` 和 `checked_sub` 防止溢出 |
| u32 转换溢出 | `unwrap_or(u32::MAX)` 处理超大数值 |

### 改进建议

1. **性能优化**:
   - 为 `user_positions_iter()` 添加缓存，避免每次重新计算
   - 使用增量更新替代全量 `replace_cells()`

2. **用户体验**:
   - 添加 rollback 进度指示（当前只是静默等待）
   - 在 rollback 失败时显示更详细的错误信息
   - 支持预览 rollback 后的状态（不实际执行）

3. **代码结构**:
   - 将 `trim_transcript_cells_*` 函数提取到单独的 `transcript_ops` 模块
   - 为 `BacktrackState` 实现更正式的状态机（使用 `enum` 替代多个 bool 字段）

4. **测试覆盖**:
   - 添加并发 rollback 的集成测试
   - 测试线程切换场景
   - 测试极端情况（空 transcript、单条消息、超大历史）

### 相关测试

文件末尾包含单元测试:
- `trim_transcript_for_first_user_drops_user_and_newer_cells`
- `trim_transcript_preserves_cells_before_selected_user`
- `trim_transcript_for_later_user_keeps_prior_history`
- `trim_drop_last_n_user_turns_applies_rollback_semantics`
- `trim_drop_last_n_user_turns_allows_overflow`

这些测试覆盖了主要的修剪逻辑，但缺少集成测试验证完整的回溯流程。
