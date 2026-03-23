# mod_tests.rs 深度研究文档

## 场景与职责

`mod_tests.rs` 是 Unified Exec 模块的集成测试文件，测试完整的 `exec_command` → `write_stdin` 流程，验证进程持久化、超时处理、暂停机制等端到端场景。

**测试特点**：
- 使用真实 PTY 进程（非 mock）
- 需要 Unix 环境（`#[cfg(unix)]`）
- 跳过沙箱环境（`skip_if_sandbox!`）

## 功能点目的

### 测试场景覆盖

| 测试 | 场景 | 验证点 |
|-----|------|--------|
| `push_chunk_preserves_prefix_and_suffix` | HeadTailBuffer 默认行为 | 1MiB 预算下保留首尾 |
| `head_tail_buffer_default_preserves_prefix_and_suffix` | 默认缓冲区配置 | 大输出下的 Head/Tail 语义 |
| `unified_exec_persists_across_requests` | 进程状态持久化 | 环境变量在多次 write_stdin 间保持 |
| `multi_unified_exec_sessions` | 多进程隔离 | 不同进程间状态隔离 |
| `unified_exec_timeouts` | 超时机制 | 短超时截断输出，后续 poll 可获取完整输出 |
| `unified_exec_pause_blocks_yield_timeout` | 暂停机制 | out_of_band_elicitation_pause 阻塞等待 |
| `requests_with_large_timeout_are_capped` | 超时上限 | 超长超时自动限制（当前 #[ignore]）|
| `completed_commands_do_not_persist_sessions` | 短命令清理 | 快速完成的命令不保留进程（当前 #[ignore]）|
| `reusing_completed_process_returns_unknown_process` | 进程退出检测 | 向已退出进程写入返回 UnknownProcessId |

## 具体技术实现

### 测试基础设施

```rust
// 创建测试会话，配置为无审批、危险沙箱模式
async fn test_session_and_turn() -> (Arc<Session>, Arc<TurnContext>)

// 便捷封装：执行命令
async fn exec_command(
    session: &Arc<Session>,
    turn: &Arc<TurnContext>,
    cmd: &str,
    yield_time_ms: u64,
) -> Result<ExecCommandToolOutput, UnifiedExecError>

// 便捷封装：写入 stdin
async fn write_stdin(
    session: &Arc<Session>,
    process_id: i32,
    input: &str,
    yield_time_ms: u64,
) -> Result<ExecCommandToolOutput, UnifiedExecError>
```

### 关键测试详解

#### 1. 进程持久化测试

```rust
async fn unified_exec_persists_across_requests() {
    // 1. 启动交互式 shell
    let open_shell = exec_command(&session, &turn, "bash -i", 2_500).await?;
    let process_id = open_shell.process_id.expect("expected process_id");
    
    // 2. 设置环境变量
    write_stdin(&session, process_id, "export VAR=codex\n", 2_500).await?;
    
    // 3. 验证环境变量持久化
    let out = write_stdin(&session, process_id, "echo $VAR\n", 2_500).await?;
    assert!(out.truncated_output().contains("codex"));
}
```

#### 2. 超时机制测试

```rust
async fn unified_exec_timeouts() {
    // 设置环境变量
    write_stdin(&session, process_id, "export VAR=test\n", 2_500).await?;
    
    // 短超时：sleep 5s 但只等 10ms，应截断
    let out_short = write_stdin(&session, process_id, "sleep 5 && echo $VAR\n", 10).await?;
    assert!(!out_short.truncated_output().contains("test"));
    
    // 等待命令完成
    tokio::time::sleep(Duration::from_secs(7)).await;
    
    // 再次 poll：应获取完整输出
    let out_poll = write_stdin(&session, process_id, "", 100).await?;
    assert!(out_poll.truncated_output().contains("test"));
}
```

#### 3. 暂停机制测试

```rust
async fn unified_exec_pause_blocks_yield_timeout() {
    // 设置暂停状态
    session.set_out_of_band_elicitation_pause_state(true);
    
    // 后台任务：2秒后解除暂停
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_secs(2)).await;
        paused_session.set_out_of_band_elicitation_pause_state(false);
    });
    
    // 执行命令（yield_time=250ms）
    let started = Instant::now();
    let response = exec_command(&session, &turn, "sleep 1 && echo done", 250).await?;
    
    // 验证：总耗时 >= 2s（暂停期间不计入 yield_time）
    assert!(started.elapsed() >= Duration::from_secs(2));
    assert!(response.truncated_output().contains("done"));
}
```

## 依赖与外部交互

| 依赖 | 用途 |
|-----|------|
| `core_test_support::skip_if_sandbox` | 沙箱环境跳过宏 |
| `make_session_and_context` | 测试会话工厂 |
| `AskForApproval::Never` | 禁用审批加速测试 |
| `SandboxPolicy::DangerFullAccess` | 禁用沙箱加速测试 |
| `tokio::time::Duration` | 异步超时控制 |

### 测试配置

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
// 多线程运行时，模拟真实并发场景
```

## 风险、边界与改进建议

### 当前局限

1. **被忽略的测试**：
   - `requests_with_large_timeout_are_capped`：需要更好的测试方式
   - `completed_commands_do_not_persist_sessions`：行为可能已变更

2. **平台限制**：
   - 仅 Unix（依赖 `bash -i`）
   - 沙箱环境跳过（无法测试沙箱集成）

3. **时间敏感**：
   - 依赖 `tokio::time::sleep`，在慢机器上可能 flaky
   - 硬编码超时值（2s, 5s, 7s）

### 改进建议

1. **条件编译优化**：
   ```rust
   #[cfg(all(unix, not(sandbox)))]
   mod tests {
       // 而非每个测试都用 skip_if_sandbox!
   }
   ```

2. **超时参数化**：
   ```rust
   const TEST_TIMEOUT_MS: u64 = std::env::var("TEST_TIMEOUT_MS")
       .unwrap_or("2500".to_string())
       .parse()
       .unwrap();
   ```

3. **添加更多场景**：
   ```rust
   // 进程清理测试
   async fn process_cleanup_on_session_drop()
   
   // 并发写入测试
   async fn concurrent_write_stdin()
   
   // 大输出测试
   async fn large_output_truncation()
   
   // 信号处理测试
   async fn signal_handling()
   ```

4. **稳定性改进**：
   ```rust
   // 使用 wait_for_condition 替代固定 sleep
   async fn wait_for_output(
       session: &Session,
       process_id: i32,
       predicate: impl Fn(&str) -> bool,
       timeout: Duration,
   ) -> Result<(), TimeoutError>
   ```
