# start.rs - 研究文档

## 场景与职责

`start.rs` 模块提供了记忆启动管道的入口点。它是记忆系统的触发器，负责在适当的条件下启动 Phase 1 和 Phase 2。

### 核心职责

1. **条件检查**: 验证记忆管道是否应该启动
2. **异步启动**: 在后台任务中启动记忆管道
3. **顺序执行**: 确保 Phase 1 在 Phase 2 之前完成

## 功能点目的

### 启动条件

记忆管道仅在以下所有条件满足时启动：

1. **非临时会话**: `!config.ephemeral`
2. **记忆功能启用**: `config.features.enabled(Feature::MemoryTool)`
3. **非子代理会话**: `!matches!(source, SessionSource::SubAgent(_))`
4. **状态数据库可用**: `session.services.state_db.is_some()`

### 主函数

```rust
/// 启动异步启动记忆管道
pub(crate) fn start_memories_startup_task(
    session: &Arc<Session>,
    config: Arc<Config>,
    source: &SessionSource,
) {
    // 1. 条件检查
    if config.ephemeral
        || !config.features.enabled(Feature::MemoryTool)
        || matches!(source, SessionSource::SubAgent(_))
    {
        return;
    }

    if session.services.state_db.is_none() {
        warn!("state db unavailable for memories startup pipeline; skipping");
        return;
    }

    // 2. 创建弱引用并启动后台任务
    let weak_session = Arc::downgrade(session);
    tokio::spawn(async move {
        // 3. 尝试升级弱引用
        let Some(session) = weak_session.upgrade() else {
            return;
        };

        // 4. 执行管道
        phase1::prune(&session, &config).await;      // 清理过期记忆
        phase1::run(&session, &config).await;        // Phase 1 提取
        phase2::run(&session, config).await;         // Phase 2 整合
    });
}
```

## 关键代码路径与文件引用

### 函数签名

| 函数 | 行号 | 签名 |
|------|------|------|
| `start_memories_startup_task` | 14 | `pub(crate) fn start_memories_startup_task(session: &Arc<Session>, config: Arc<Config>, source: &SessionSource)` |

### 代码流程

```
start_memories_startup_task
├── 条件检查 (行 19-24)
│   ├── 临时会话检查
│   ├── 功能标志检查
│   └── 子代理检查
├── 数据库可用性检查 (行 26-29)
├── 创建弱引用 (行 31)
└── 启动后台任务 (行 32-43)
    ├── 弱引用升级 (行 33-35)
    ├── 清理过期记忆 (行 38)
    ├── Phase 1 执行 (行 40)
    └── Phase 2 执行 (行 42)
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::codex::Session` | 会话上下文 |
| `crate::config::Config` | 配置 |
| `crate::features::Feature` | 功能标志检查 |
| `crate::memories::phase1` | Phase 1 执行 |
| `crate::memories::phase2` | Phase 2 执行 |
| `codex_protocol::protocol::SessionSource` | 会话来源类型 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `std::sync::Arc` | 引用计数 |
| `tokio::spawn` | 异步任务 |
| `tracing::warn` | 警告日志 |

### 调用方

| 模块 | 用途 |
|------|------|
| `crate::codex` | 会话启动时调用 |
| `mod.rs` | 公开导出 |

## 风险、边界与改进建议

### 已知风险

1. **弱引用升级失败**:
   - 如果在任务启动后会话被丢弃，`upgrade()` 返回 None
   - 管道不会执行，但也没有错误报告

2. **无错误传播**:
   - 后台任务的结果不会被等待或检查
   - Phase 1 或 Phase 2 失败不会通知调用方

3. **顺序依赖**:
   - Phase 2 依赖 Phase 1 完成
   - 如果 Phase 1  panic，Phase 2 不会执行
   - 但没有显式的依赖管理

4. **资源竞争**:
   - 多个会话可能同时启动记忆管道
   - 依赖数据库租约机制协调

### 边界条件

1. **快速关闭**: 如果会话在任务启动后立即关闭，管道不会执行
2. **数据库不可用**: 记录警告并跳过
3. **功能禁用**: 静默跳过
4. **子代理**: 静默跳过（防止递归）

### 改进建议

1. **错误报告**:
```rust
// 使用通道报告结果
let (tx, rx) = tokio::sync::oneshot::channel();
tokio::spawn(async move {
    let result = async {
        phase1::prune(&session, &config).await;
        phase1::run(&session, &config).await;
        phase2::run(&session, config).await;
        Ok(())
    }.await;
    let _ = tx.send(result);
});
// 调用方可以选择等待结果
```

2. **取消支持**:
```rust
pub(crate) fn start_memories_startup_task(
    session: &Arc<Session>,
    config: Arc<Config>,
    source: &SessionSource,
) -> Option<tokio::task::AbortHandle> {
    // 条件检查...
    let weak_session = Arc::downgrade(session);
    let handle = tokio::spawn(async move {
        // ...
    });
    Some(handle.abort_handle())
}
```

3. **健康检查**:
   - 添加记忆管道健康检查端点
   - 报告最后执行时间和状态

4. **指标增强**:
   - 记录启动尝试次数
   - 记录跳过原因分布

5. **配置验证**:
   - 在启动前验证记忆配置
   - 提前检测无效配置

6. **超时保护**:
   - 为整个管道添加超时
   - 防止无限期挂起
