# mod.rs 深度研究文档

## 场景与职责

`mod.rs` 是 `streaming` 模块的根模块，定义了 `StreamState` 结构体——流式处理的核心状态容器。它持有基于换行符门控的 Markdown 收集器和已提交渲染行的 FIFO 队列。

### 核心场景
- **流式内容收集**：累积增量内容，按换行符分割
- **行队列管理**：维护待显示的已提交行队列
- **节奏化排空**：支持单步、批量和全量排空
- **队列压力监控**：提供队列深度和最老行年龄查询

### 模块架构
```
streaming/
├── mod.rs           # StreamState 核心状态
├── chunking.rs      # 自适应分块策略
├── commit_tick.rs   # 提交 tick 编排
└── controller.rs    # 流控制器适配
```

### 职责边界
**负责**：
- 持有 `MarkdownStreamCollector` 和队列
- 管理队列的入队、出队操作
- 跟踪最老行的入队时间（用于年龄计算）
- 提供队列状态查询

**不负责**：
- 分块策略决策（委托给 `chunking.rs`）
- 历史单元格发射规则（委托给 `controller.rs`）
- Markdown 解析（委托给 `MarkdownStreamCollector`）

## 功能点目的

### 1. 队列顺序保证
关键不变性：所有排空操作都从队列前端弹出，保持 FIFO 顺序。

### 2. 时间戳追踪
每行入队时记录 `Instant`，支持：
- 计算最老行的年龄（用于分块策略）
- 无需查看文本内容即可推理队列延迟

### 3. 多控制器协调
`StreamState` 被两个控制器共享：
- `StreamController`：常规消息流
- `PlanStreamController`：计划流

## 具体技术实现

### 关键数据结构

```rust
/// 队列中的行，包含入队时间戳
struct QueuedLine {
    line: Line<'static>,      // 渲染后的行
    enqueued_at: Instant,     // 入队时间
}

/// 流状态容器
pub(crate) struct StreamState {
    pub(crate) collector: MarkdownStreamCollector,  // Markdown 收集器
    queued_lines: VecDeque<QueuedLine>,             // 待显示行队列
    pub(crate) has_seen_delta: bool,                // 是否接收过增量
}
```

### 构造与清理

```rust
impl StreamState {
    /// 创建流状态
    pub(crate) fn new(width: Option<usize>, cwd: &Path) -> Self {
        Self {
            collector: MarkdownStreamCollector::new(width, cwd),
            queued_lines: VecDeque::new(),
            has_seen_delta: false,
        }
    }
    
    /// 重置状态（用于下一个流生命周期）
    pub(crate) fn clear(&mut self) {
        self.collector.clear();
        self.queued_lines.clear();
        self.has_seen_delta = false;
    }
}
```

### 排空操作

#### 单步排空
```rust
/// 从队列前端排空一行
pub(crate) fn step(&mut self) -> Vec<Line<'static>> {
    self.queued_lines
        .pop_front()
        .map(|queued| queued.line)
        .into_iter()
        .collect()
}
```

#### 批量排空
```rust
/// 从队列前端排空最多 max_lines 行
pub(crate) fn drain_n(&mut self, max_lines: usize) -> Vec<Line<'static>> {
    let end = max_lines.min(self.queued_lines.len());  // 限制为可用长度
    self.queued_lines
        .drain(..end)
        .map(|queued| queued.line)
        .collect()
}
```

#### 全量排空
```rust
/// 排空所有队列行
pub(crate) fn drain_all(&mut self) -> Vec<Line<'static>> {
    self.queued_lines
        .drain(..)
        .map(|queued| queued.line)
        .collect()
}
```

### 队列状态查询

```rust
/// 是否空闲（队列为空）
pub(crate) fn is_idle(&self) -> bool {
    self.queued_lines.is_empty()
}

/// 队列深度
pub(crate) fn queued_len(&self) -> usize {
    self.queued_lines.len()
}

/// 最老行的年龄
pub(crate) fn oldest_queued_age(&self, now: Instant) -> Option<Duration> {
    self.queued_lines
        .front()
        .map(|queued| now.saturating_duration_since(queued.enqueued_at))
}
```

### 入队操作

```rust
/// 将已提交的行加入队列，使用统一的时间戳
pub(crate) fn enqueue(&mut self, lines: Vec<Line<'static>>) {
    let now = Instant::now();
    self.queued_lines
        .extend(lines.into_iter().map(|line| QueuedLine {
            line,
            enqueued_at: now,  // 同一批行使用相同时间戳
        }));
}
```

## 关键代码路径与文件引用

### 本文件内关键函数
- `StreamState::new` (line 41-47): 构造
- `StreamState::clear` (line 49-53): 清理
- `StreamState::step` (line 55-61): 单步排空
- `StreamState::drain_n` (line 66-72): 批量排空
- `StreamState::drain_all` (line 74-79): 全量排空
- `StreamState::is_idle` (line 81-83): 空闲检查
- `StreamState::queued_len` (line 85-87): 队列深度
- `StreamState::oldest_queued_age` (line 89-93): 最老行年龄
- `StreamState::enqueue` (line 95-102): 入队

### 调用方

#### controller.rs
- `StreamController::new` → `StreamState::new`
- `StreamController::push` → `state.enqueue`
- `StreamController::finalize` → `state.drain_all`, `state.clear`
- `StreamController::on_commit_tick` → `state.step`
- `StreamController::on_commit_tick_batch` → `state.drain_n`
- `StreamController::queued_lines` → `state.queued_len`
- `StreamController::oldest_queued_age` → `state.oldest_queued_age`
- `PlanStreamController` 使用相同的方法

### 被调用方

#### MarkdownStreamCollector (markdown_stream.rs)
- `MarkdownStreamCollector::new`: 构造收集器
- `MarkdownStreamCollector::push_delta`: 推送增量
- `MarkdownStreamCollector::commit_complete_lines`: 提交完整行
- `MarkdownStreamCollector::finalize_and_drain`: 最终化
- `MarkdownStreamCollector::clear`: 清理

### 模块导出

```rust
pub(crate) mod chunking;
pub(crate) mod commit_tick;
pub(crate) mod controller;
```

## 依赖与外部交互

### 依赖模块
- `std::collections::VecDeque`: 双端队列
- `std::path::Path`: 路径类型
- `std::time::{Duration, Instant}`: 时间类型
- `ratatui::text::Line`: 文本行类型

### 内部依赖
- `markdown_stream.rs`: `MarkdownStreamCollector`

### 被依赖模块
- `controller.rs`: 使用 `StreamState`

### 测试
包含一个单元测试 `drain_n_clamps_to_available_lines`（line 117-126）：
- 验证 `drain_n` 在请求行数超过可用时正确限制

## 风险、边界与改进建议

### 风险点

1. **时间戳精度**
   - `enqueue` 使用 `Instant::now()` 为整批行打时间戳
   - 如果一批行很多，最老行的实际年龄可能被低估

2. **内存使用**
   - `VecDeque` 会保留分配的容量
   - 长时间运行的大流量可能导致内存增长

3. **`has_seen_delta` 状态**
   - 当前只是简单的布尔值
   - 不区分空增量和非空增量后的空增量

### 边界条件

1. **空队列排空**
   - `step` 返回空 `Vec`
   - `drain_n(0)` 返回空 `Vec`
   - `drain_all` 在空队列时返回空 `Vec`

2. **批量排空上限**
   - `drain_n` 自动限制为 `min(max_lines, queued_lines.len())`
   - 调用方传入极大值也能安全处理

3. **时间回退**
   - `oldest_queued_age` 使用 `saturating_duration_since`
   - 处理系统时间回退情况

4. **单元素队列**
   - `front()` 在单元素队列时正确返回唯一元素
   - 年龄计算正确

### 改进建议

1. **更精确的时间戳**
   ```rust
   // 建议：为每行单独打时间戳（如果需要更精确的年龄）
   pub(crate) fn enqueue_with_interval(&mut self, lines: Vec<Line<'static>>) {
       let base = Instant::now();
       self.queued_lines.extend(lines.into_iter().enumerate().map(|(i, line)| {
           QueuedLine {
               line,
               enqueued_at: base + Duration::from_micros(i as u64),  // 微秒级偏移
           }
       }));
   }
   ```

2. **内存优化**
   ```rust
   // 建议：定期收缩容量
   pub(crate) fn shrink_if_needed(&mut self) {
       if self.queued_lines.capacity() > self.queued_lines.len() * 2 {
           self.queued_lines.shrink_to_fit();
       }
   }
   ```

3. **增强状态追踪**
   ```rust
   // 建议：更详细的增量统计
   pub(crate) struct DeltaStats {
       pub total_deltas: u64,
       pub empty_deltas: u64,
       pub total_bytes: u64,
   }
   ```

4. **队列事件通知**
   ```rust
   // 建议：支持入队/出队回调
   pub(crate) fn set_enqueue_callback(&mut self, cb: Box<dyn Fn(usize)>) {
       self.enqueue_callback = Some(cb);
   }
   ```

5. **测试增强**
   - 添加 `oldest_queued_age` 测试
   - 添加并发测试（多线程入队/出队）
   - 添加大容量测试

6. **文档改进**
   - 添加关于 `QueuedLine` 内存布局的文档
   - 说明 `enqueue` 的时间戳策略选择原因
