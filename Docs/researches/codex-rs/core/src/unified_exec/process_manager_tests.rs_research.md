# process_manager_tests.rs 深度研究文档

## 场景与职责

`process_manager_tests.rs` 是 `process_manager.rs` 的单元测试模块，专注于测试环境变量注入和进程清理策略。与 `mod_tests.rs` 的集成测试不同，本文件测试纯逻辑函数，无需真实 PTY 进程。

## 功能点目的

### 测试覆盖场景

| 测试 | 目标函数 | 验证点 |
|-----|---------|--------|
| `unified_exec_env_injects_defaults` | `apply_unified_exec_env` | 10 个默认环境变量正确注入 |
| `unified_exec_env_overrides_existing_values` | `apply_unified_exec_env` | 默认值覆盖用户值，保留其他变量 |
| `pruning_prefers_exited_processes_outside_recently_used` | `process_id_to_prune_from_meta` | 优先清理已退出且不在最近 8 个的进程 |
| `pruning_falls_back_to_lru_when_no_exited` | `process_id_to_prune_from_meta` | 无退出进程时按 LRU 清理 |
| `pruning_protects_recent_processes_even_if_exited` | `process_id_to_prune_from_meta` | 最近 8 个进程受保护，即使已退出 |

## 具体技术实现

### 环境变量测试

```rust
#[test]
fn unified_exec_env_injects_defaults() {
    let env = apply_unified_exec_env(HashMap::new());
    let expected = HashMap::from([
        ("NO_COLOR", "1"),
        ("TERM", "dumb"),
        ("LANG", "C.UTF-8"),
        ("LC_CTYPE", "C.UTF-8"),
        ("LC_ALL", "C.UTF-8"),
        ("COLORTERM", ""),
        ("PAGER", "cat"),
        ("GIT_PAGER", "cat"),
        ("GH_PAGER", "cat"),
        ("CODEX_CI", "1"),
    ]);
    assert_eq!(env, expected);
}

#[test]
fn unified_exec_env_overrides_existing_values() {
    let mut base = HashMap::new();
    base.insert("NO_COLOR", "0");  // 用户设置
    base.insert("PATH", "/usr/bin");  // 应保持
    
    let env = apply_unified_exec_env(base);
    
    assert_eq!(env.get("NO_COLOR"), Some(&"1"));  // 被覆盖
    assert_eq!(env.get("PATH"), Some(&"/usr/bin"));  // 保留
}
```

### 清理策略测试

测试数据格式：`(process_id, last_used, has_exited)`

```rust
#[test]
fn pruning_prefers_exited_processes_outside_recently_used() {
    let now = Instant::now();
    let meta = vec![
        (1, now - Duration::from_secs(40), false),  // 老，运行中
        (2, now - Duration::from_secs(30), true),   // 老，已退出 ← 应被选
        (3, now - Duration::from_secs(20), false),
        // ... 4-10 为最近使用
    ];
    
    let candidate = UnifiedExecProcessManager::process_id_to_prune_from_meta(&meta);
    
    assert_eq!(candidate, Some(2));  // 优先清理已退出的老进程
}

#[test]
fn pruning_falls_back_to_lru_when_no_exited() {
    let meta = vec![
        (1, now - Duration::from_secs(40), false),  // 最老 ← 应被选
        (2, now - Duration::from_secs(30), false),
        // ... 全部运行中
    ];
    
    let candidate = UnifiedExecProcessManager::process_id_to_prune_from_meta(&meta);
    
    assert_eq!(candidate, Some(1));  // LRU 清理
}

#[test]
fn pruning_protects_recent_processes_even_if_exited() {
    let meta = vec![
        (1, now - Duration::from_secs(40), false),  // 老，运行中 ← 应被选
        (2, now - Duration::from_secs(30), false),
        // ...
        (10, now - Duration::from_secs(13), true),  // 最近，但已退出（受保护）
    ];
    
    let candidate = UnifiedExecProcessManager::process_id_to_prune_from_meta(&meta);
    
    assert_eq!(candidate, Some(1));  // 不选 10，因为受保护
}
```

## 依赖与外部交互

| 依赖 | 用途 |
|-----|------|
| `apply_unified_exec_env` | 被测函数：环境变量注入 |
| `process_id_to_prune_from_meta` | 被测函数：清理策略 |
| `pretty_assertions` | 测试断言美化 |
| `tokio::time::Instant` | 模拟时间戳 |

## 风险、边界与改进建议

### 当前覆盖局限

❌ 未测试：
- `exec_command` 完整流程
- `write_stdin` 流程
- `collect_output_until_deadline` 超时逻辑
- `store_process` 并发安全
- 网络审批注册/注销
- 沙箱重试逻辑

### 测试盲区

1. **并发场景**：`prepare_process_handles` 和 `refresh_process_state` 的竞态
2. **错误处理**：`UnknownProcessId`、`StdinClosed` 等错误路径
3. **边界值**：
   - 进程数 = 64 时的清理行为
   - yield_time = MIN/MAX 边界
   - max_output_tokens = None vs Some(0)

### 改进建议

1. **添加更多单元测试**：
   ```rust
   #[test]
   fn clamp_yield_time_bounds() {
       assert_eq!(clamp_yield_time(100), 250);  // 低于最小值
       assert_eq!(clamp_yield_time(250), 250);  // 最小值
       assert_eq!(clamp_yield_time(30000), 30000);  // 最大值
       assert_eq!(clamp_yield_time(60000), 30000);  // 超过最大值
   }
   
   #[test]
   fn resolve_max_tokens_default() {
       assert_eq!(resolve_max_tokens(None), DEFAULT_MAX_OUTPUT_TOKENS);
       assert_eq!(resolve_max_tokens(Some(5000)), 5000);
   }
   ```

2. **添加属性测试**：
   ```rust
   #[quickcheck]
   fn pruning_never_selects_recent_8(meta: Vec<(i32, u64, bool)>) -> bool {
       // 验证最近 8 个永远不会被选中
   }
   ```

3. **添加并发测试**：
   ```rust
   #[tokio::test]
   async fn concurrent_allocate_and_release() {
       // 多任务并发分配和释放进程 ID，验证无重复
   }
   ```

4. **提取可测试单元**：
   当前 `process_manager.rs` 中许多函数是 `async` 且依赖外部服务，建议：
   - 将纯逻辑（如清理策略）提取为独立模块
   - 使用 trait 抽象外部依赖，便于 mock 测试
