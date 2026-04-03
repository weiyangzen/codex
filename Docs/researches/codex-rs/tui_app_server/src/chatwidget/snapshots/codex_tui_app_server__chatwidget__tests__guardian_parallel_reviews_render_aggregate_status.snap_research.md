# guardian_parallel_reviews_render_aggregate_status 快照研究文档

## 场景与职责

此快照测试验证 **tui_app_server** 中 **Guardian 并行审查的聚合状态渲染**。当 Guardian 同时评估多个执行请求时，系统需要在底部状态栏显示聚合的审查状态，让用户了解所有待审查操作的整体情况。

这是 Guardian 系统的高级功能，处理并发安全审查的 UI 展示。

## 功能点目的

1. **并发审查可视化**：同时展示多个正在审查的操作
2. **状态聚合**：将多个审查状态汇总为简洁的概览
3. **用户感知**：让用户了解当前有多少操作正在等待安全审查
4. **操作透明度**：列出所有待审查的操作详情

### 并行审查场景

当 Agent 在一次对话中请求执行多个命令时：
- 每个命令都需要 Guardian 评估
- 评估可能同时进行
- UI 需要清晰展示所有评估的状态

## 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/chatwidget/tests.rs` 第 10407-10437 行

```rust
#[tokio::test]
async fn guardian_parallel_reviews_render_aggregate_status_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;
    chat.on_task_started();

    // 模拟两个并行的 Guardian 审查请求
    for (id, command) in [
        ("guardian-1", "rm -rf '/tmp/guardian target 1'"),
        ("guardian-2", "rm -rf '/tmp/guardian target 2'"),
    ] {
        chat.handle_codex_event(Event {
            id: format!("event-{id}"),
            msg: EventMsg::GuardianAssessment(GuardianAssessmentEvent {
                id: id.to_string(),
                turn_id: "turn-1".to_string(),
                status: GuardianAssessmentStatus::InProgress,
                risk_score: None,
                risk_level: None,
                rationale: None,
                action: Some(serde_json::json!({
                    "tool": "shell",
                    "command": command,
                })),
            }),
        });
    }

    let rendered = render_bottom_popup(&chat, 72);
    assert_snapshot!(
        "guardian_parallel_reviews_render_aggregate_status",
        rendered
    );
}
```

### 快照内容
```
• Reviewing 2 approval requests (0s • esc to interrupt)
  └ • rm -rf '/tmp/guardian target 1'
    • rm -rf '/tmp/guardian target 2'


› Ask Codex to do anything

  ? for shortcuts                                    100% context left
```

### 核心实现逻辑

1. **待处理审查状态跟踪** (`PendingGuardianReviewStatus`):
   - 位于 `codex-rs/tui_app_server/src/chatwidget.rs` 第 609-650 行
   - 维护一个审查条目向量
   
   ```rust
   #[derive(Clone, Debug, Default, PartialEq, Eq)]
   struct PendingGuardianReviewStatus {
       entries: Vec<PendingGuardianReviewStatusEntry>,
   }

   struct PendingGuardianReviewStatusEntry {
       id: String,
       detail: String,
   }
   ```

2. **状态更新** (`start_or_update`):
   ```rust
   fn start_or_update(&mut self, id: String, detail: String) {
       if let Some(existing) = self.entries.iter_mut().find(|entry| entry.id == id) {
           existing.detail = detail;
       } else {
           self.entries.push(PendingGuardianReviewStatusEntry { id, detail });
       }
   }
   ```

3. **聚合状态渲染** (`current_status` 计算):
   - 当多个审查在进行中时，显示数量汇总
   - 格式：`"Reviewing N approval requests"`
   - 列出所有待审查的操作详情

4. **底部状态栏更新**：
   - 使用树形缩进展示多个操作
   - `└ •` 和 `•` 用于视觉层次

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试用例定义 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | PendingGuardianReviewStatus 实现 |
| `codex-rs/tui_app_server/src/bottom_pane/mod.rs` | 底部状态栏渲染 |
| `codex-rs/tui_app_server/src/bottom_pane/status_indicator_widget.rs` | 状态指示器渲染 |
| `codex-protocol/src/protocol.rs` | Guardian 事件定义 |

### 关键数据结构

```rust
// 待处理审查状态
#[derive(Default)]
struct PendingGuardianReviewStatus {
    entries: Vec<PendingGuardianReviewStatusEntry>,
}

struct PendingGuardianReviewStatusEntry {
    id: String,      // Guardian 评估 ID
    detail: String,  // 操作描述（如命令）
}

impl PendingGuardianReviewStatus {
    fn start_or_update(&mut self, id: String, detail: String);
    fn finish(&mut self, id: &str) -> bool;
    fn is_empty(&self) -> bool;
    fn len(&self) -> usize;
}
```

## 依赖与外部交互

### 内部状态管理
```
GuardianAssessmentEvent (InProgress) x N
    └── PendingGuardianReviewStatus::start_or_update()
            └── 更新 entries 向量
                    └── 触发状态栏重新渲染
                            └── 聚合显示："Reviewing N approval requests"
                                    └── 列出所有操作详情
```

### 状态转换
| 事件 | 状态变化 | UI 更新 |
|------|---------|---------|
| InProgress (新) | 添加条目 | 数量 +1 |
| InProgress (更新) | 更新详情 | 详情更新 |
| Approved | 移除条目 | 数量 -1，显示批准 |
| Denied | 移除条目 | 数量 -1，显示拒绝 |

## 风险、边界与改进建议

### 潜在风险

1. **状态不同步**：
   - 如果事件丢失或乱序，可能导致状态显示错误
   - 需要超时机制清理过期条目

2. **性能问题**：
   - 大量并行审查时，列表可能过长
   - 需要限制显示数量或分页

3. **视觉混乱**：
   - 多个操作同时显示可能造成信息过载
   - 需要良好的视觉层次和分组

### 边界情况

1. **单一审查**：
   - 只有一个审查时显示 `"Reviewing 1 approval request"`
   - 不显示列表，仅显示详情

2. **大量并行审查**：
   - 测试 2 个，但生产环境可能有更多
   - 需要处理 5+ 个操作的显示

3. **混合状态**：
   - 部分批准、部分拒绝、部分审查中
   - 需要清晰的分类展示

4. **长命令截断**：
   - 测试使用 72 字符宽度
   - 长命令需要正确换行或截断

5. **审查完成清理**：
   - 所有审查完成后的状态清理
   - 见 `guardian_parallel_reviews_keep_remaining_review_visible_after_denial` 测试

### 改进建议

1. **智能分组**：
   - 按操作类型分组（文件操作、网络操作等）
   - 显示每组的统计信息

2. **优先级指示**：
   - 根据风险评分排序
   - 高风险操作优先显示

3. **进度指示**：
   - 显示每个审查的预计完成时间
   - 或显示审查队列位置

4. **批量操作**：
   - 提供"批准全部"/"拒绝全部"选项
   - 适用于信任当前 Agent 行为的场景

5. **折叠/展开**：
   - 默认折叠长列表，显示摘要
   - 用户可以展开查看详情

6. **历史记录**：
   - 保留已完成的审查记录
   - 便于回顾和审计

7. **动画效果**：
   - 新审查进入时的动画提示
   - 审查完成时的状态过渡

### 相关测试

- `guardian_parallel_reviews_keep_remaining_review_visible_after_denial`：测试部分拒绝后的状态
- `guardian_approved_exec_renders_approved_request`：单个批准测试
- `guardian_denied_exec_renders_warning_and_denied_request`：单个拒绝测试

### 测试策略说明

此测试验证了 Guardian 系统的**并发处理能力**：

1. **单条测试**：验证单个审查的基本功能
2. **并行测试**（本测试）：验证多个审查的聚合显示
3. **混合测试**：验证审查完成后的状态清理

这种分层测试确保 Guardian 在各种负载情况下都能正确工作。

### UI 设计考虑

```
• Reviewing N approval requests (time • esc to interrupt)
  └ • command 1
    • command 2
    • command 3
    ...
```

- **树形结构**：使用 `└` 和缩进创建视觉层次
- **计数器**：明确显示待审查数量
- **时间**：显示审查已进行的时间
- **中断提示**：提醒用户可以按 Esc 中断

这种设计在有限的空间内最大化信息密度，同时保持可读性。
