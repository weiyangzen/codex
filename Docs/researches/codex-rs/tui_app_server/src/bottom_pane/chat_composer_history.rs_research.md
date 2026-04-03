# chat_composer_history.rs 研究文档

## 场景与职责

`chat_composer_history.rs` 是 Codex TUI 应用中负责管理聊天输入框历史记录功能的核心模块。它实现了类 Shell 的历史导航机制（Up/Down 键浏览历史），同时支持两种历史来源的合并管理：

1. **持久化跨会话历史**（Persistent cross-session history）：文本-only，存储在持久化日志中
2. **本地会话历史**（Local in-session history）：包含完整的草稿状态（文本、文本元素、图片附件、Mention 绑定等）

该模块被设计为与渲染 Widget 解耦的状态机，使得逻辑层可以独立测试，符合项目架构中"逻辑与渲染分离"的设计原则。

## 功能点目的

### 1. 历史条目管理（HistoryEntry）
- **目的**：保存可重hydrate的草稿状态
- **关键数据**：
  - `text`: 原始文本（可能包含占位符字符串）
  - `text_elements`: 占位符的文本元素范围（如图片附件的占位符）
  - `local_image_paths`: 本地图片路径
  - `remote_image_urls`: 远程图片 URL
  - `mention_bindings`: Mention 绑定（工具/应用/技能引用）
  - `pending_pastes`: 用于恢复大段粘贴内容的占位符-载荷对

### 2. 历史导航状态机（ChatComposerHistory）
- **目的**：管理 Up/Down 键历史导航的状态
- **核心状态**：
  - `history_log_id`: 历史日志标识符
  - `history_entry_count`: 持久化历史条目数量
  - `local_history`: 本会话新提交的消息（最新在末尾）
  - `fetched_history`: 按需获取的持久化历史缓存
  - `history_cursor`: 当前历史游标（None 表示未浏览历史）
  - `last_history_text`: 上次插入输入框的历史文本

### 3. 智能导航判定
- **目的**：区分历史导航键与多行文本的光标移动
- **逻辑**：
  - 空文本时始终启用历史遍历
  - 非空文本时，只有当光标在行边界（开始或结束）且文本匹配上次历史条目时，才进行历史导航
  - 防止用户在多行草稿中移动光标时意外触发历史切换

### 4. 异步历史获取
- **目的**：支持从持久化存储按需获取历史条目
- **机制**：当导航到未缓存的持久化历史索引时，发送 `GetHistoryEntryRequest` 操作，异步获取后通过 `on_entry_response` 更新

## 具体技术实现

### 关键数据结构

```rust
/// 历史条目，可重hydrate草稿状态
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct HistoryEntry {
    pub(crate) text: String,
    pub(crate) text_elements: Vec<TextElement>,
    pub(crate) local_image_paths: Vec<PathBuf>,
    pub(crate) remote_image_urls: Vec<String>,
    pub(crate) mention_bindings: Vec<MentionBinding>,
    pub(crate) pending_pastes: Vec<(String, String)>,
}

/// 历史导航状态机
pub(crate) struct ChatComposerHistory {
    history_log_id: Option<u64>,
    history_entry_count: usize,
    local_history: Vec<HistoryEntry>,
    fetched_history: HashMap<usize, HistoryEntry>,
    history_cursor: Option<isize>,
    last_history_text: Option<String>,
}
```

### 关键流程

#### 历史导航流程（Up 键）
1. 计算总条目数：`history_entry_count + local_history.len()`
2. 确定下一个索引：
   - 如果 `history_cursor` 为 None，从最新条目开始（`total_entries - 1`）
   - 如果已在最旧条目（0），返回 None
   - 否则索引减 1
3. 调用 `populate_history_at_index` 获取条目：
   - 如果是本地条目（索引 >= `history_entry_count`），从 `local_history` 直接获取
   - 如果已缓存，从 `fetched_history` 获取
   - 如果未缓存，发送 `GetHistoryEntryRequest` 异步请求

#### 本地提交记录
```rust
pub fn record_local_submission(&mut self, entry: HistoryEntry) {
    // 忽略完全空的提交
    // 重置导航状态
    // 避免连续重复条目
    // 添加到 local_history
}
```

#### 异步响应处理
```rust
pub fn on_entry_response(&mut self, log_id: u64, offset: usize, entry: Option<String>) 
    -> Option<HistoryEntry> {
    // 验证 log_id 匹配
    // 创建 HistoryEntry 并缓存
    // 如果响应当前游标位置，更新 last_history_text 并返回条目
}
```

### Mention 解码

`HistoryEntry::new` 使用 `decode_history_mentions` 解码文本中的 mention 引用，将文本中的 mention 标记转换为 `MentionBinding` 列表。

## 关键代码路径与文件引用

### 当前文件关键路径
- `HistoryEntry::new()` (行 29-46): 从历史文本创建条目，解码 mentions
- `ChatComposerHistory::navigate_up()` (行 195-209): 处理 Up 键导航
- `ChatComposerHistory::navigate_down()` (行 212-236): 处理 Down 键导航
- `should_handle_navigation()` (行 173-191): 判定是否应处理导航键
- `populate_history_at_index()` (行 262-287): 按需获取历史条目
- `on_entry_response()` (行 239-256): 处理异步历史响应

### 调用方
- `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`: 
  - 创建 `ChatComposerHistory` 实例
  - 调用 `navigate_up/down` 处理键盘事件
  - 调用 `record_local_submission` 记录用户提交
  - 调用 `on_entry_response` 处理协议事件

### 被调用方
- `codex-rs/tui_app_server/src/bottom_pane/mention_codec.rs`:
  - `decode_history_mentions`: 解码历史文本中的 mentions
- `codex_protocol::protocol::Op::GetHistoryEntryRequest`: 异步获取历史条目

## 依赖与外部交互

### 依赖模块
| 模块 | 用途 |
|------|------|
| `mention_codec` | 解码/编码 mention 绑定 |
| `codex_protocol::protocol::Op` | 发送历史获取请求 |
| `codex_protocol::user_input::TextElement` | 文本元素范围定义 |
| `AppEventSender` | 发送应用事件 |

### 协议交互
- **发送**: `Op::GetHistoryEntryRequest { offset, log_id }` - 请求特定偏移的历史条目
- **接收**: 通过 `on_entry_response` 处理异步响应

## 风险、边界与改进建议

### 风险点

1. **异步响应时序问题**
   - 风险：用户快速连续按 Up 键可能产生多个未完成的异步请求，响应到达时可能已导航到其他位置
   - 缓解：`on_entry_response` 检查 `history_cursor` 是否仍匹配响应的偏移

2. **历史条目一致性**
   - 风险：`fetched_history` 缓存可能在会话配置变更后过期
   - 缓解：`set_metadata` 清除缓存并重置状态

3. **内存增长**
   - 风险：长时间会话中 `local_history` 和 `fetched_history` 持续增长
   - 现状：当前实现无显式限制，依赖会话生命周期

### 边界情况

1. **空历史导航**：当 `total_entries == 0` 时，导航方法返回 None
2. **边界导航**：已在最旧条目时按 Up、最新条目时按 Down 的特殊处理
3. **并发修改**：`record_local_submission` 重置导航状态，防止不一致

### 改进建议

1. **缓存大小限制**
   - 建议为 `fetched_history` 添加 LRU 限制，避免内存无限增长

2. **预取优化**
   - 当前按需获取可能导致导航延迟，可考虑预取相邻条目

3. **搜索/过滤**
   - 当前仅支持顺序导航，可考虑添加历史搜索功能

4. **持久化本地历史**
   - 当前本地历史仅在会话内有效，崩溃或重启会丢失，可考虑持久化到本地存储

5. **测试覆盖**
   - 当前测试覆盖基本功能，建议添加：
     - 并发导航和提交的竞态条件测试
     - 大历史列表性能测试
     - 会话配置变更后的状态一致性测试
