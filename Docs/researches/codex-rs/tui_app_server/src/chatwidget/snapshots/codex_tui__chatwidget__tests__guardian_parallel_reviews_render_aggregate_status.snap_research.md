# Snapshot Research: guardian_parallel_reviews_render_aggregate_status

## 场景与职责

此快照测试验证当多个 Guardian 审核请求并行进行时，TUI 如何正确渲染聚合状态。这是并发安全审核场景的关键测试，确保用户能够同时跟踪多个正在审核的操作。

测试场景：
- 系统同时发起多个需要 Guardian 审核的操作（如多个文件删除命令）
- 每个操作都触发独立的 Guardian 评估流程
- TUI 需要在底部状态栏显示所有进行中的审核状态
- 用户可以通过状态栏了解当前有多少操作正在被审核

## 功能点目的

1. **并发审核可视化**：同时显示多个进行中的 Guardian 审核请求
2. **聚合状态展示**：在状态栏头部显示审核请求总数
3. **详细信息列表**：列出每个审核请求的具体命令
4. **动态更新**：随着审核完成，动态更新显示列表

## 具体技术实现

### 关键流程

```
多个 GuardianAssessmentEvent(InProgress) → 聚合状态计算 → 底部状态栏渲染
```

### 状态聚合逻辑

```rust
// PendingGuardianReviewStatus 结构体跟踪多个审核请求
#[derive(Clone, Debug, Default, PartialEq, Eq)]
struct PendingGuardianReviewStatus {
    entries: Vec<PendingGuardianReviewStatusEntry>,
}

struct PendingGuardianReviewStatusEntry {
    id: String,    // 审核请求 ID
    detail: String, // 命令详情
}
```

### 状态栏渲染逻辑

```rust
impl PendingGuardianReviewStatus {
    fn status_indicator_state(&self) -> Option<StatusIndicatorState> {
        let details = if self.entries.len() == 1 {
            // 单个审核：显示命令详情
            self.entries.first().map(|entry| entry.detail.clone())
        } else if self.entries.is_empty() {
            None
        } else {
            // 多个审核：列出前3个，其余显示为 "+N more"
            let mut lines = self
                .entries
                .iter()
                .take(3)
                .map(|entry| format!("• {}", entry.detail))
                .collect::<Vec<_>>();
            let remaining = self.entries.len().saturating_sub(3);
            if remaining > 0 {
                lines.push(format!("+{remaining} more"));
            }
            Some(lines.join("\n"))
        };
        
        let header = if self.entries.len() == 1 {
            String::from("Reviewing approval request")
        } else {
            format!("Reviewing {} approval requests", self.entries.len())
        };
        // ...
    }
}
```

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 测试定义和快照断言 |
| `codex-rs/tui/src/chatwidget.rs` | ChatWidget 主逻辑，处理 Guardian 事件和状态聚合 |
| `codex-rs/tui/src/bottom_pane/mod.rs` | 底部状态栏渲染 |

### 关键函数

- `PendingGuardianReviewStatus::start_or_update()` - 添加或更新审核请求
- `PendingGuardianReviewStatus::finish()` - 完成审核请求
- `PendingGuardianReviewStatus::status_indicator_state()` - 生成状态栏显示状态
- `render_bottom_popup()` - 测试辅助函数，渲染底部弹窗

### 测试代码位置

```rust
// codex-rs/tui/src/chatwidget/tests.rs
async fn guardian_parallel_reviews_render_aggregate_status_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;
    chat.on_task_started();

    // 模拟两个并行的 Guardian 审核请求
    for (id, command) in [
        ("guardian-1", "rm -rf '/tmp/guardian target 1'"),
        ("guardian-2", "rm -rf '/tmp/guardian target 2'"),
    ] {
        chat.handle_codex_event(Event {
            msg: EventMsg::GuardianAssessment(GuardianAssessmentEvent {
                id: id.to_string(),
                status: GuardianAssessmentStatus::InProgress,
                action: Some(serde_json::json!({
                    "tool": "shell",
                    "command": command,
                })),
                // ...
            }),
        });
    }

    let rendered = render_bottom_popup(&chat, 72);
    assert_snapshot!("guardian_parallel_reviews_render_aggregate_status", rendered);
}
```

## 依赖与外部交互

### 内部依赖

- `PendingGuardianReviewStatus` - 跟踪多个 Guardian 审核请求的状态
- `StatusIndicatorState` - 状态栏显示状态
- `BottomPane` - 底部面板渲染

### 外部交互

- **Guardian 服务**：接收多个并行的风险评估结果
- **codex-core**：协调多个命令的执行和审核流程

## 风险、边界与改进建议

### 潜在风险

1. **状态同步问题**：多个并行审核请求的状态更新可能导致竞态条件
2. **显示溢出**：大量并行审核请求可能导致状态栏信息过长
3. **性能问题**：频繁的审核状态更新可能影响 UI 响应性

### 边界情况

- 超过 3 个并行审核请求时的折叠显示
- 审核请求在渲染过程中完成的状态变化
- 部分审核被拒绝、部分被批准的混合场景

### 改进建议

1. **显示优化**：
   - 添加审核请求优先级指示
   - 支持点击/选择查看单个审核详情
   - 为长时间审核添加进度指示

2. **交互改进**：
   - 支持批量批准/拒绝操作
   - 添加审核请求排序选项（按时间、风险级别等）
   - 提供审核历史记录查看

3. **性能优化**：
   - 批量处理审核状态更新
   - 使用虚拟列表渲染大量审核请求
   - 添加审核状态更新节流机制

4. **可访问性**：
   - 添加审核完成的声音提示
   - 支持键盘导航在审核请求间切换

---

**快照内容**：
```
• Reviewing 2 approval requests (0s • esc to interrupt)
  └ • rm -rf '/tmp/guardian target 1'
    • rm -rf '/tmp/guardian target 2'


› Ask Codex to do anything

  ? for shortcuts                                    100% context left
```

**说明**：
- 状态栏头部显示 "Reviewing 2 approval requests"，明确告知用户有 2 个审核请求正在进行
- 使用项目符号列表显示每个审核请求的具体命令
- 缩进格式使层级关系清晰
- 底部显示输入提示和上下文信息
