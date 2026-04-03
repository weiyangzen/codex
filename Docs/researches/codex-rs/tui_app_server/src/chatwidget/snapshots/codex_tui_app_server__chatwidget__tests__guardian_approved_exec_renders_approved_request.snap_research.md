# guardian_approved_exec_renders_approved_request 快照研究文档

## 场景与职责

此快照测试验证 **tui_app_server** 中 **Guardian 自动审批通过执行请求** 的渲染。当 Guardian（自动审批系统）评估并批准一个执行请求时，系统在历史记录中显示批准状态，告知用户该操作已被自动批准。

这是 Guardian 安全系统的正向反馈测试，验证批准状态的正确渲染。

## 功能点目的

1. **透明度**：向用户展示 Guardian 的决策结果，增加系统透明度
2. **审计追踪**：记录自动批准的操作，便于后续审计
3. **用户信任**：通过清晰的批准指示，建立用户对自动审批系统的信任
4. **操作确认**：明确显示哪些操作被执行，避免用户困惑

### Guardian 系统概述

Guardian 是一个自动安全审查系统，用于：
- 评估 Agent 请求执行的操作的风险
- 根据风险评分决定是否自动批准
- 为高风险操作请求人工审批
- 记录所有审批决策

## 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/chatwidget/tests.rs` 第 10157-10200 行

```rust
#[tokio::test]
async fn guardian_approved_exec_renders_approved_request() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
    chat.show_welcome_banner = false;

    chat.handle_codex_event(Event {
        id: "guardian-assessment".into(),
        msg: EventMsg::GuardianAssessment(GuardianAssessmentEvent {
            id: "thread:child-thread:guardian-1".into(),
            turn_id: "turn-1".into(),
            status: GuardianAssessmentStatus::Approved,
            risk_score: Some(14),
            risk_level: Some(GuardianRiskLevel::Low),
            rationale: Some("Narrowly scoped to the requested file.".into()),
            action: Some(serde_json::json!({
                "tool": "shell",
                "command": "rm -f /tmp/guardian-approved.sqlite",
            })),
        }),
    });

    let width: u16 = 120;
    let ui_height: u16 = chat.desired_height(width);
    let vt_height: u16 = 12;
    let viewport = Rect::new(0, vt_height - ui_height - 1, width, ui_height);

    let backend = VT100Backend::new(width, vt_height);
    let mut term = crate::custom_terminal::Terminal::with_options(backend).expect("terminal");
    term.set_viewport_area(viewport);

    for lines in drain_insert_history(&mut rx) {
        crate::insert_history::insert_history_lines(&mut term, lines)
            .expect("Failed to insert history lines in test");
    }

    term.draw(|f| {
        chat.render(f.area(), f.buffer_mut());
    })
    .expect("draw guardian approval history");

    assert_snapshot!(
        "guardian_approved_exec_renders_approved_request",
        term.backend().vt100().screen().contents()
    );
}
```

### 快照内容
```





✔ Auto-reviewer approved codex to run rm -f /tmp/guardian-approved.sqlite this
  time


› Ask Codex to do anything

  ? for shortcuts                                                                                    100% context left
```

### 核心事件类型

```rust
pub struct GuardianAssessmentEvent {
    pub id: String,
    pub turn_id: String,
    pub status: GuardianAssessmentStatus,  // Approved / Denied / InProgress
    pub risk_score: Option<i32>,           // 0-100 风险评分
    pub risk_level: Option<GuardianRiskLevel>,  // Low / Medium / High
    pub rationale: Option<String>,         // 审批理由
    pub action: Option<Value>,             // 被评估的操作（JSON）
}
```

### 核心实现逻辑

1. **事件处理** (`handle_codex_event`):
   - 匹配 `EventMsg::GuardianAssessment`
   - 根据状态（Approved/Denied/InProgress）分别处理

2. **批准状态处理** (`GuardianAssessmentStatus::Approved`):
   - 位于 `codex-rs/tui_app_server/src/chatwidget.rs` 第 2864-2890 行
   - 提取操作摘要（`guardian_action_summary`）
   - 更新底部状态栏
   - 创建历史记录单元格

   ```rust
   if status == GuardianAssessmentStatus::Approved
       && let Some(action) = ev.action.as_ref()
       && let Some(detail) = guardian_action_summary(action)
   {
       // 更新状态栏和待处理审查状态
       self.bottom_pane.ensure_status_indicator();
       self.bottom_pane.set_interrupt_hint_visible(true);
       self.pending_guardian_review_status
           .start_or_update(ev.id.clone(), detail);
   }
   ```

3. **操作摘要提取** (`guardian_action_summary`):
   - 解析 JSON action 提取可读的命令描述
   - 支持 `shell` 工具和其他工具类型

4. **VT100 渲染**：
   - 使用 `VT100Backend` 进行终端渲染测试
   - 捕获完整屏幕内容用于快照比较

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试用例定义 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | Guardian 事件处理逻辑 |
| `codex-rs/tui_app_server/src/history_cell.rs` | 历史记录单元格实现 |
| `codex-rs/tui_app_server/src/test_backend.rs` | VT100Backend 测试后端 |
| `codex-protocol/src/protocol.rs` | Guardian 事件定义 |

### 关键数据结构

```rust
// Guardian 评估状态
pub enum GuardianAssessmentStatus {
    InProgress,
    Approved,
    Denied,
}

// 风险等级
pub enum GuardianRiskLevel {
    Low,
    Medium,
    High,
}

// 待处理审查状态跟踪
#[derive(Default)]
struct PendingGuardianReviewStatus {
    entries: Vec<PendingGuardianReviewStatusEntry>,
}
```

## 依赖与外部交互

### 协议层依赖
- **codex-protocol**: 定义 Guardian 评估事件
  - `GuardianAssessmentEvent`: 评估事件结构
  - `GuardianAssessmentStatus`: 评估状态枚举
  - `GuardianRiskLevel`: 风险等级枚举

### 内部模块交互
```
GuardianAssessmentEvent (Approved)
    └── handle_codex_event()
            └── 提取 action 和 detail
                    └── 更新 PendingGuardianReviewStatus
                            └── 更新底部状态栏
                                    └── 渲染历史记录
```

### 渲染流程
1. 处理 Guardian 批准事件
2. 创建历史记录单元格（显示批准信息）
3. 更新底部状态栏（显示"Auto-reviewer approved..."）
4. VT100 终端捕获屏幕内容

## 风险、边界与改进建议

### 潜在风险

1. **误批准风险**：
   - 低评分操作仍可能存在风险
   - 需要持续优化风险模型

2. **信息泄露**：
   - 批准消息中显示的命令可能包含敏感信息
   - 需要适当的脱敏处理

3. **用户忽视**：
   - 用户可能忽略自动批准的消息
   - 重要操作需要更明显的提示

### 边界情况

1. **高风险但批准**：
   - 理论上不应发生，但需要处理异常情况
   - 应添加警告或二次确认

2. **无操作详情**：
   - 当 `action` 字段缺失时的处理
   - 应显示通用批准消息

3. **长命令截断**：
   - 测试使用 120 字符宽度
   - 长命令需要正确换行

4. **并行批准**：
   - 多个操作同时被批准时的显示
   - 见 `guardian_parallel_reviews_render_aggregate_status` 测试

### 改进建议

1. **风险可视化**：
   - 在批准消息中显示风险评分（如"✔ Approved (risk: 14/100)"）
   - 让用户了解批准的可信度

2. **操作分类**：
   - 按操作类型使用不同图标（文件操作、网络操作等）
   - 增强视觉识别

3. **时间戳记录**：
   - 显示批准发生的时间
   - 便于审计和问题追溯

4. **一键撤销**：
   - 对于刚批准的操作，提供快速撤销选项
   - 防止误批准造成损失

5. **详细理由展示**：
   - 可选展开显示 Guardian 的详细推理过程
   - 增加透明度（当前 `rationale` 字段未在 UI 中显示）

6. **聚合显示优化**：
   - 当多个操作被批准时，提供更清晰的汇总视图
   - 支持展开查看详情

### 相关测试

- `guardian_denied_exec_renders_warning_and_denied_request`：测试拒绝情况
- `guardian_parallel_reviews_render_aggregate_status`：测试并行审查聚合
- `app_server_guardian_review_denied_renders_denied_request_snapshot`：App Server 拒绝测试

### 对比：批准 vs 拒绝

| 方面 | 批准 | 拒绝 |
|------|------|------|
| 图标 | ✔ | ⚠ / ✗ |
| 颜色 | 绿色/正常 | 黄色/红色（警告）|
| 消息 | "Auto-reviewer approved..." | "Automatic approval review denied..." |
| 后续 | 继续执行 | 阻止执行，可能需要人工审批 |
| 风险显示 | 可选显示 | 必须显示（risk: high）|

两个测试共同确保 Guardian 系统的各种决策都能正确渲染。
