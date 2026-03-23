# async_watcher.rs 深度研究文档

## 场景与职责

`async_watcher.rs` 是 Unified Exec 模块的异步输出监控组件，负责：
1. **实时输出流处理**：从 PTY 进程持续读取输出，转换为 UTF-8 文本并分块发送事件
2. **进程退出监控**：监听进程终止信号，收集最终输出并生成 `ExecCommandEnd` 事件
3. **输出缓冲管理**：与 `HeadTailBuffer` 协作，确保输出在内存限制内保留

该模块是连接底层 PTY 进程和上层事件系统的桥梁，实现"边执行边流式输出"的交互体验。

## 功能点目的

### 1. 流式输出监控 (`start_streaming_output`)
- **目的**：让用户实时看到命令执行输出，而非等待命令完成
- **机制**：后台 tokio 任务持续从 broadcast channel 接收输出块
- **关键约束**：
  - 单事件负载上限 8KB (`UNIFIED_EXEC_OUTPUT_DELTA_MAX_BYTES`)
  - 每调用最多 10,000 个 delta 事件 (`MAX_EXEC_OUTPUT_DELTAS_PER_CALL`)
  - 100ms 优雅期 (`TRAILING_OUTPUT_GRACE`) 确保尾部输出被捕获

### 2. UTF-8 边界安全处理 (`split_valid_utf8_prefix`)
- **目的**：避免在多字节 UTF-8 字符中间截断，导致乱码
- **机制**：从最大允许长度逆向扫描，找到有效的 UTF-8 前缀
- **退化处理**：若无法找到有效前缀（如非法字节），单字节推进确保流不卡住

### 3. 进程退出处理 (`spawn_exit_watcher`)
- **目的**：进程退出后统一生成结束事件，包含完整执行统计
- **触发条件**：`cancellation_token.cancelled()` + `output_drained.notified()`
- **输出**：`ExecCommandEnd` 事件，包含 exit_code、duration、aggregated_output

## 具体技术实现

### 核心流程

```
start_streaming_output
├── 创建 broadcast receiver 订阅 PTY 输出
├── tokio::spawn 后台任务
│   ├── select! 多路复用
│   │   ├── exit_token.cancelled() → 启动 grace_sleep
│   │   ├── grace_sleep 到期 → 通知 output_drained，退出
│   │   └── receiver.recv() → process_chunk()
│   └── process_chunk
│       ├── 追加到 pending buffer
│       ├── split_valid_utf8_prefix 提取有效 UTF-8
│       ├── 写入 HeadTailBuffer (transcript)
│       └── 发送 ExecCommandOutputDelta 事件
└── 返回（监控任务在后台运行）
```

### 关键数据结构

```rust
// 每个 delta 事件的最大字节数
const UNIFIED_EXEC_OUTPUT_DELTA_MAX_BYTES: usize = 8192;

// 尾部输出等待时间
pub(crate) const TRAILING_OUTPUT_GRACE: Duration = Duration::from_millis(100);
```

### 依赖与外部交互

| 依赖模块 | 用途 |
|---------|------|
| `HeadTailBuffer` | 输出缓冲，保留首尾丢弃中间 |
| `Session::send_event` | 发送输出 delta 事件到客户端 |
| `ToolEmitter` | 生成 ExecCommandEnd 事件 |
| `MAX_EXEC_OUTPUT_DELTAS_PER_CALL` | 限制每调用事件数，防止事件风暴 |

### 代码路径

1. **流式输出入口**：`start_streaming_output()` (line 39)
2. **UTF-8 分割**：`split_valid_utf8_prefix_with_max()` (line 220)
3. **退出监控**：`spawn_exit_watcher()` (line 106)
4. **结束事件生成**：`emit_exec_end_for_unified_exec()` (line 178)

## 风险、边界与改进建议

### 已知风险

1. **事件数量限制**：`MAX_EXEC_OUTPUT_DELTAS_PER_CALL` (10,000) 达到后，输出仍写入 transcript 但不再发送事件，用户可能看不到最新输出
2. **内存上限**：`UNIFIED_EXEC_OUTPUT_MAX_BYTES` (1MiB) 是硬限制，超大输出会被截断
3. **非法 UTF-8**：单字节退避策略可能导致非法字节以原始形式出现在输出中

### 边界情况

| 场景 | 处理行为 |
|------|---------|
| 进程快速退出 | grace_sleep 确保 100ms 内输出被收集 |
| broadcast lag | 忽略 `RecvError::Lagged`，继续接收新数据 |
| channel 关闭 | 通知 output_drained 并退出 |
| 超长 UTF-8 序列 | 最多回退 4 字节，否则单字节推进 |

### 改进建议

1. **可观测性**：添加 metrics 监控 delta 事件丢弃率、grace period 实际等待时间
2. **配置化**：将 `TRAILING_OUTPUT_GRACE`、`UNIFIED_EXEC_OUTPUT_DELTA_MAX_BYTES` 改为可配置
3. **流控优化**：考虑实现背压机制，当消费端慢于生产端时主动降速
4. **编码检测**：对非 UTF-8 输出（如二进制数据）提供更友好的处理方式
