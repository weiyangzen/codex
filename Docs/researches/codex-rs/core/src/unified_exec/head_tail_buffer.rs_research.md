# head_tail_buffer.rs 深度研究文档

## 场景与职责

`HeadTailBuffer` 是一个**内存受限的循环缓冲区**，用于保留进程输出的"头部 + 尾部"，丢弃中间内容。这是处理大输出场景的关键组件，确保：
1. **内存安全**：输出不会无限增长导致 OOM
2. **信息价值**：保留开头的命令和上下文，以及最新的输出结果
3. **流式处理**：支持边写入边读取，无需等待命令完成

## 功能点目的

### 核心设计：对称预算分配

```
总预算: max_bytes (默认 1 MiB)
├── 头部预算: max_bytes / 2 (保留最早的输出)
└── 尾部预算: max_bytes - head_budget (保留最新的输出)
```

当总输出超过预算时，中间部分被丢弃，保留 "... (X bytes omitted) ..." 的语义。

### 关键操作

| 方法 | 用途 |
|-----|------|
| `push_chunk` | 追加输出块，自动处理预算超额 |
| `snapshot_chunks` | 获取当前保留的块列表（head + tail）|
| `to_bytes` | 合并为连续字节向量 |
| `drain_chunks` | 取出所有块并重置缓冲区 |
| `retained_bytes` / `omitted_bytes` | 统计信息（测试用）|

## 具体技术实现

### 数据结构

```rust
pub(crate) struct HeadTailBuffer {
    max_bytes: usize,      // 总预算
    head_budget: usize,    // 头部预算 (max_bytes / 2)
    tail_budget: usize,    // 尾部预算
    head: VecDeque<Vec<u8>>,  // 头部块队列
    tail: VecDeque<Vec<u8>>,  // 尾部块队列
    head_bytes: usize,     // 头部当前字节数
    tail_bytes: usize,     // 尾部当前字节数
    omitted_bytes: usize,  // 已丢弃字节数（统计用）
}
```

### 核心算法

#### 写入流程 (`push_chunk`)

```
push_chunk(chunk):
1. 如果 max_bytes == 0：全部丢弃，计入 omitted_bytes
2. 如果 head 未满：
   - chunk 能完全放入 head：直接追加
   - chunk 超出 head 预算：分割为 (head_part, tail_part)
3. 如果 head 已满：
   - 直接写入 tail (push_to_tail)
```

#### 尾部管理 (`push_to_tail`)

```
push_to_tail(chunk):
1. 如果 chunk >= tail_budget：
   - 清空现有 tail
   - 只保留 chunk 的最后 tail_budget 字节
2. 否则：
   - 追加到 tail
   - 调用 trim_tail_to_budget 裁剪超额部分
```

#### 裁剪策略 (`trim_tail_to_budget`)

```
trim_tail_to_budget:
- 从 tail 头部开始移除块，直到满足预算
- 若部分块超出：分割该块，保留后半
- 所有移除的字节计入 omitted_bytes
```

### 代码路径

- **构造**：`HeadTailBuffer::new(max_bytes)` / `Default` (使用 `UNIFIED_EXEC_OUTPUT_MAX_BYTES`)
- **写入**：`push_chunk()` (line 65)
- **读取**：`snapshot_chunks()` (line 97) / `to_bytes()` (line 108)
- **重置**：`drain_chunks()` (line 123)

## 依赖与外部交互

| 依赖 | 用途 |
|-----|------|
| `UNIFIED_EXEC_OUTPUT_MAX_BYTES` | 默认 1 MiB 预算，来自 mod.rs |
| `VecDeque` | 双端队列，支持 O(1) 头部弹出/尾部追加 |

### 使用场景

```rust
// async_watcher.rs: 存储进程输出
transcript.lock().await.push_chunk(prefix.to_vec());

// process_manager.rs: 收集输出响应
let collected = Self::collect_output_until_deadline(&output_buffer, ...).await;

// process.rs: 检查沙箱拒绝时的输出快照
let collected_chunks = self.snapshot_output().await;
```

## 风险、边界与改进建议

### 边界情况处理

| 场景 | 行为 |
|-----|------|
| max_bytes = 0 | 所有输入立即丢弃，omitted_bytes 累计 |
| 单块 > tail_budget | 保留块的最后 tail_budget 字节，其余丢弃 |
| 频繁小写入 | head 先填满，后续全部进入 tail 并持续轮换 |
| 并发访问 | 通过 `Arc<Mutex<HeadTailBuffer>>` 保护 |

### 已知风险

1. **块碎片化**：频繁小写入导致大量小块，增加内存开销
2. **无压缩**：重复内容（如进度条）占用宝贵预算
3. **字符边界**：字节级截断可能破坏多字节 UTF-8 字符（调用方需处理）

### 改进建议

1. **块合并**：当 tail 中相邻小块总大小较小时，合并以减少碎片化
   ```rust
   // 例如：当 tail 前端小块 < 1KB 时合并
   const MIN_CHUNK_SIZE: usize = 1024;
   ```

2. **行感知截断**：优先在换行符处截断，避免截断到行中间
   ```rust
   // 在 trim_tail_to_budget 中尝试找最近的 \n
   ```

3. **压缩/去重**：对重复内容（如进度条更新）进行去重
   ```rust
   // 检测相似块，只保留最新版本
   ```

4. **可配置预算比例**：允许调整 head/tail 比例（如 30/70 而非 50/50）
