# 研究文档: interrupt_preserves_unified_exec_wait_streak.snap

## 场景与职责

该快照文件测试中断操作如何保持统一执行等待序列（unified exec wait streak）的状态。

## 功能点目的

1. **状态保持**: 中断后保持执行等待序列的连续性
2. **序列管理**: 管理多个连续的后台执行等待状态
3. **用户体验**: 确保中断不会破坏用户的执行上下文

## 具体技术实现

### 统一执行等待

```rust
struct UnifiedExecProcessSummary {
    key: String,
    call_id: String,
    command_display: String,
    recent_chunks: Vec<String>,
}

// 等待序列
chat.unified_exec_processes: Vec<UnifiedExecProcessSummary>
chat.unified_exec_wait_streak: Option<UnifiedExecWaitStreak>
```

### 中断处理

中断后保持 `unified_exec_wait_streak` 不被重置，确保：
- 后台进程继续运行
- 等待状态保持
- 用户可以继续与后台进程交互

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs`
- **统一执行**: `unified_exec_processes` 管理

## 改进建议
1. 添加等待序列的可视化指示
2. 提供单独中断某个后台进程的选项
