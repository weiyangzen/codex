# agent_navigation.rs 深度研究文档

## 1. 场景与职责

### 1.1 模块定位
`agent_navigation.rs` 是 TUI App Server 中负责**多智能体导航状态管理**的专用模块。它从主 `App` 结构体中抽离出来，专门处理与多智能体（Multi-Agent）协作相关的导航逻辑，包括：

- `/agent` 选择器的条目排序与展示
- 键盘快捷键导航（上一个/下一个智能体）
- 当前查看线程的页脚标签显示

### 1.2 设计哲学
模块采用**纯函数式状态管理**设计：
- **独立可测试**：所有导航逻辑不依赖 UI 副作用，可独立单元测试
- **稳定遍历顺序**：基于首次发现（first-seen）的 spawn 顺序，而非 thread-id 排序，确保用户导航体验的一致性
- **职责分离**：线程生命周期管理留在 `App`，纯导航逻辑放在本模块

### 1.3 核心不变式（Invariant）
> 遍历遵循首次发现的 spawn 顺序。一旦观察到线程 ID，即使后续条目被更新或标记为关闭，它在循环中的位置也保持不变。

---

## 2. 功能点目的

### 2.1 AgentNavigationState - 导航状态容器

```rust
#[derive(Debug, Default)]
pub(crate) struct AgentNavigationState {
    /// 每个被跟踪线程 ID 的最新选择器元数据
    threads: HashMap<ThreadId, AgentPickerThreadEntry>,
    /// 用于选择器行和键盘循环的稳定首次发现遍历顺序
    order: Vec<ThreadId>,
}
```

**设计意图**：
- `threads`：存储最新的线程元数据（昵称、角色、关闭状态）
- `order`：维护稳定的遍历顺序，确保导航一致性

### 2.2 AgentNavigationDirection - 导航方向

```rust
pub(crate) enum AgentNavigationDirection {
    Previous,  // 向 spawn 顺序中更早的条目移动，在前端环绕
    Next,      // 向 spawn 顺序中更晚的条目移动，在末端环绕
}
```

### 2.3 核心功能方法

| 方法 | 用途 |
|------|------|
| `upsert()` | 插入或更新选择器条目，保持首次发现顺序 |
| `mark_closed()` | 标记线程为关闭，但保留在选择器中 |
| `adjacent_thread_id()` | 计算键盘导航的相邻线程 ID（支持环绕） |
| `active_agent_label()` | 生成当前显示线程的页脚标签 |
| `picker_subtitle()` | 构建 `/agent` 选择器的副标题 |
| `ordered_threads()` | 返回按顺序排列的选择器行 |

---

## 3. 具体技术实现

### 3.1 首次发现顺序维护

```rust
pub(crate) fn upsert(
    &mut self,
    thread_id: ThreadId,
    agent_nickname: Option<String>,
    agent_role: Option<String>,
    is_closed: bool,
) {
    // 关键：仅在首次看到时追加到 order
    if !self.threads.contains_key(&thread_id) {
        self.order.push(thread_id);
    }
    self.threads.insert(
        thread_id,
        AgentPickerThreadEntry {
            agent_nickname,
            agent_role,
            is_closed,
        },
    );
}
```

**技术细节**：
- 使用 `contains_key` 检查避免重复添加
- 更新操作不影响 `order` 向量，保持遍历稳定性

### 3.2 环绕式键盘导航

```rust
pub(crate) fn adjacent_thread_id(
    &self,
    current_displayed_thread_id: Option<ThreadId>,
    direction: AgentNavigationDirection,
) -> Option<ThreadId> {
    let ordered_threads = self.ordered_threads();
    if ordered_threads.len() < 2 {
        return None;
    }

    let current_thread_id = current_displayed_thread_id?;
    let current_idx = ordered_threads
        .iter()
        .position(|(thread_id, _)| *thread_id == current_thread_id)?;
    
    let next_idx = match direction {
        AgentNavigationDirection::Next => (current_idx + 1) % ordered_threads.len(),
        AgentNavigationDirection::Previous => {
            if current_idx == 0 {
                ordered_threads.len() - 1  // 在前端环绕到末尾
            } else {
                current_idx - 1
            }
        }
    };
    Some(ordered_threads[next_idx].0)
}
```

### 3.3 页脚标签生成

```rust
pub(crate) fn active_agent_label(
    &self,
    current_displayed_thread_id: Option<ThreadId>,
    primary_thread_id: Option<ThreadId>,
) -> Option<String> {
    // 单线程会话不显示标签，避免浪费空间
    if self.threads.len() <= 1 {
        return None;
    }
    // ... 格式化逻辑
}
```

**格式化规则**：
- 主线程显示 `"Main [default]"`
- 有昵称和角色：`"Nickname [role]"`
- 仅昵称：`"Nickname"`
- 仅角色：`"[role]"`
- 都没有：`"Agent"`

### 3.4 与 multi_agents.rs 的协作

本模块依赖 `multi_agents.rs` 提供的：
- `AgentPickerThreadEntry`：选择器条目数据结构
- `format_agent_picker_item_name()`：统一的格式化函数
- `next_agent_shortcut()` / `previous_agent_shortcut()`：键盘快捷键定义

---

## 4. 关键代码路径与文件引用

### 4.1 模块内关键路径

```
agent_navigation.rs
├── AgentNavigationState::upsert()           [行 79-97]
├── AgentNavigationState::mark_closed()      [行 105-114]
├── AgentNavigationState::adjacent_thread_id() [行 154-179]
├── AgentNavigationState::active_agent_label() [行 187-214]
├── AgentNavigationState::picker_subtitle()  [行 220-227]
└── tests::                                  [行 242-331]
    ├── upsert_preserves_first_seen_order()
    ├── adjacent_thread_id_wraps_in_spawn_order()
    └── active_agent_label_tracks_current_thread()
```

### 4.2 跨文件引用

| 引用目标 | 路径 | 用途 |
|---------|------|------|
| `AgentPickerThreadEntry` | `multi_agents.rs` | 选择器条目数据结构 |
| `format_agent_picker_item_name` | `multi_agents.rs` | 格式化显示名称 |
| `next_agent_shortcut` | `multi_agents.rs` | 下一个智能体快捷键 |
| `previous_agent_shortcut` | `multi_agents.rs` | 上一个智能体快捷键 |
| `ThreadId` | `codex_protocol` | 线程标识符 |

### 4.3 在 App 中的使用

```rust
// app.rs [行 129-136]
mod agent_navigation;
use self::agent_navigation::AgentNavigationDirection;
use self::agent_navigation::AgentNavigationState;

// App 结构体中的使用
self.agent_navigation.upsert(thread_id, nickname, role, is_closed);
let next = self.agent_navigation.adjacent_thread_id(current, direction);
let label = self.agent_navigation.active_agent_label(current, primary);
```

---

## 5. 依赖与外部交互

### 5.1 直接依赖

```rust
use crate::multi_agents::AgentPickerThreadEntry;
use crate::multi_agents::format_agent_picker_item_name;
use crate::multi_agents::next_agent_shortcut;
use crate::multi_agents::previous_agent_shortcut;
use codex_protocol::ThreadId;
use ratatui::text::Span;
use std::collections::HashMap;
```

### 5.2 依赖模块职责

| 模块 | 职责 |
|------|------|
| `multi_agents.rs` | 提供多智能体展示和交互的共享契约 |
| `codex_protocol` | 提供 `ThreadId` 类型 |
| `ratatui` | 提供终端 UI 的文本样式 |

### 5.3 事件流向

```
App (接收线程事件)
    ↓
agent_navigation.upsert() / mark_closed()
    ↓
AgentNavigationState (更新内部状态)
    ↓
App (查询导航状态)
    ↓
adjacent_thread_id() / active_agent_label() / ordered_threads()
    ↓
UI 渲染
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 风险 1：关闭线程的幽灵条目
- **描述**：`mark_closed()` 不会从选择器中移除线程，可能导致选择器积累大量已关闭线程
- **缓解**：这是设计意图，允许用户回顾已关闭的线程，但长期运行可能累积大量条目

#### 风险 2：线程 ID 解析失败
- **描述**：`ordered_threads()` 使用 `filter_map` 跳过无法解析的线程 ID
- **影响**：在极端竞态条件下（如线程被删除但 order 未更新），可能出现空槽位

#### 风险 3：单线程会话的标签隐藏
- **描述**：`active_agent_label()` 在 `threads.len() <= 1` 时返回 `None`
- **边界**：如果线程被快速创建和关闭，可能导致标签闪烁

### 6.2 测试覆盖

模块包含全面的单元测试：
- `upsert_preserves_first_seen_order`：验证首次发现顺序不变式
- `adjacent_thread_id_wraps_in_spawn_order`：验证环绕导航
- `picker_subtitle_mentions_shortcuts`：验证副标题包含快捷键
- `active_agent_label_tracks_current_thread`：验证标签跟踪当前线程

### 6.3 改进建议

#### 建议 1：添加最大条目限制
```rust
const MAX_TRACKED_THREADS: usize = 100;

pub(crate) fn upsert(...) {
    if !self.threads.contains_key(&thread_id) && self.order.len() >= MAX_TRACKED_THREADS {
        // 移除最旧的非主线程
        self.evict_oldest_non_primary();
    }
    // ...
}
```

#### 建议 2：添加线程活跃度时间戳
- 记录每个线程的最后活动时间
- 允许按活跃度排序或过滤

#### 建议 3：持久化导航顺序
- 当前顺序仅在内存中维护
- 考虑在会话恢复时恢复顺序

#### 建议 4：增强错误处理
- 当前 `get()` 返回 `Option`，调用者需处理缺失情况
- 可考虑添加更详细的缺失原因（如从未见过 vs 已被清除）

### 6.4 性能特征

| 操作 | 时间复杂度 | 空间复杂度 | 说明 |
|------|-----------|-----------|------|
| `upsert()` | O(1) 平均 | O(n) | HashMap 插入 |
| `adjacent_thread_id()` | O(n) | O(n) | 需要构建 ordered_threads |
| `ordered_threads()` | O(n) | O(n) | 过滤并收集 |
| `active_agent_label()` | O(1) 平均 | O(1) | HashMap 查找 |

其中 n 为跟踪的线程数量。考虑到实际使用场景（通常 < 20 个线程），性能完全可接受。
