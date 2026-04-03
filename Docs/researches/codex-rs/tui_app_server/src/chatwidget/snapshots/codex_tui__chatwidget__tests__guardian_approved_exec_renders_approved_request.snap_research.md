# 研究文档：Guardian 批准的执行请求渲染

## 场景与职责

本快照测试验证 Codex TUI 对 Guardian 自动审核通过的执行请求的渲染效果。当 Guardian（Codex 的安全审核系统）自动批准一个命令执行请求时，系统会在历史记录中显示一条特殊的批准记录，告知用户该命令已通过自动审核并执行。

Guardian 是 Codex 的安全防护系统，用于自动评估命令的风险等级并决定是否批准执行。

## 功能点目的

1. **自动审核透明化**：让用户知道命令是通过自动审核而非手动批准的
2. **信任建立**：显示 Guardian 的批准信息，建立用户对自动审核系统的信任
3. **审计追踪**：记录哪些命令是通过 Guardian 批准的
4. **风险提示**：显示风险分数和等级，让用户了解命令的风险程度

## 具体技术实现

### 核心数据结构

```rust
// Guardian 评估事件
pub struct GuardianAssessmentEvent {
    pub id: String,                    // 评估 ID
    pub turn_id: String,               // 所属回合 ID
    pub status: GuardianAssessmentStatus,  // 批准/拒绝状态
    pub risk_score: Option<i32>,       // 风险分数 (0-100)
    pub risk_level: Option<GuardianRiskLevel>,  // 风险等级
    pub rationale: Option<String>,     // 批准/拒绝理由
    pub action: Option<Value>,         // 相关动作（如命令）
}

pub enum GuardianAssessmentStatus {
    Approved,   // 已批准
    Denied,     // 已拒绝
}

pub enum GuardianRiskLevel {
    Low,        // 低风险
    Medium,     // 中等风险
    High,       // 高风险
}
```

### 测试代码（来自 tests.rs）

```rust
// tui/src/chatwidget/tests.rs
#[tokio::test]
async fn guardian_approved_exec_renders_approved_request() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
    chat.show_welcome_banner = false;

    // 模拟 Guardian 批准事件
    chat.handle_codex_event(Event {
        id: "guardian-assessment".into(),
        msg: EventMsg::GuardianAssessment(GuardianAssessmentEvent {
            id: "thread:child-thread:guardian-1".into(),
            turn_id: "turn-1".into(),
            status: GuardianAssessmentStatus::Approved,
            risk_score: Some(14),                    // 低风险分数
            risk_level: Some(GuardianRiskLevel::Low), // 低风险等级
            rationale: Some("Narrowly scoped to the requested file.".into()), // 批准理由
            action: Some(serde_json::json!({
                "tool": "shell",
                "command": "rm -f /tmp/guardian-approved.sqlite",
            })),
        }),
    });

    // 渲染并验证
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

### Guardian 事件处理

```rust
// chatwidget.rs
fn handle_codex_event(&mut self, event: Event) {
    match event.msg {
        EventMsg::GuardianAssessment(assessment) => {
            if assessment.status == GuardianAssessmentStatus::Approved {
                // 构建批准记录
                let command = assessment.action
                    .and_then(|a| a.get("command").and_then(|c| c.as_str()))
                    .unwrap_or("unknown command");
                
                let approval_text = format!(
                    "✔ Auto-reviewer approved codex to run {} this time",
                    command
                );
                
                // 插入历史记录
                self.app_event_tx.send(AppEvent::InsertHistoryCell(
                    history_cell::new_guardian_approval_cell(approval_text)
                ));
            }
        }
        // ...
    }
}
```

### 快照输出解析

```





✔ Auto-reviewer approved codex to run rm -f /tmp/guardian-approved.sqlite this
  time


› Ask Codex to do anything

  ? for shortcuts                                                                                    100% context left
```

关键观察：
- 使用 `✔` 符号表示批准（绿色）
- 显示 "Auto-reviewer approved" 表明是自动审核
- 显示完整的命令 `rm -f /tmp/guardian-approved.sqlite`
- 添加 "this time" 强调这是单次批准
- 下方显示正常的输入提示符

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/chatwidget.rs` | ChatWidget 实现，Guardian 事件处理 |
| `codex-rs/tui/src/chatwidget/tests.rs` | 快照测试定义（约第 9555-9598 行） |
| `codex-rs/tui/src/history_cell.rs` | 历史记录单元格实现，包含 Guardian 批准单元格 |
| `codex-protocol/src/protocol.rs` | GuardianAssessmentEvent 定义 |
| `codex-rs/tui/src/insert_history.rs` | 历史记录插入逻辑 |
| `codex-rs/tui/src/chatwidget/snapshots/codex_tui__chatwidget__tests__guardian_approved_exec_renders_approved_request.snap` | 本快照文件 |

### 相关测试函数

- `guardian_approved_exec_renders_approved_request()` - 本测试（批准场景）
- `guardian_denied_exec_renders_warning_and_denied_request()` - 对比测试（拒绝场景）
- `guardian_parallel_reviews_render_aggregate_status()` - 并行审核测试

### 相关 Guardian 测试

```rust
// 拒绝场景测试
async fn guardian_denied_exec_renders_warning_and_denied_request() {
    // 测试 Guardian 拒绝时的渲染
    // 显示警告图标和拒绝信息
}

// 并行审核测试
async fn guardian_parallel_reviews_render_aggregate_status() {
    // 测试多个 Guardian 审核的聚合显示
}
```

## 依赖与外部交互

### 依赖模块

1. **Guardian 协议定义**
   ```rust
   // codex-protocol/src/protocol.rs
   pub struct GuardianAssessmentEvent {
       pub id: String,
       pub turn_id: String,
       pub status: GuardianAssessmentStatus,
       pub risk_score: Option<i32>,
       pub risk_level: Option<GuardianRiskLevel>,
       pub rationale: Option<String>,
       pub action: Option<Value>,
   }
   ```

2. **VT100 后端**
   ```rust
   // 用于测试中的终端渲染
   VT100Backend::new(width, vt_height)
   ```

3. **历史记录系统**
   ```rust
   // 插入 Guardian 批准记录
   insert_history_lines(&mut term, lines)
   ```

### Guardian 工作流程

```
用户请求执行命令
    ↓
Guardian 评估风险
    ↓
风险分数: 14 (Low)
    ↓
自动批准
    ↓
显示: ✔ Auto-reviewer approved codex to run {command} this time
    ↓
执行命令
```

## 风险、边界与改进建议

### 潜在风险

1. **过度信任自动审核**
   - 用户可能过度信任 Guardian 的批准
   - 需要确保用户理解 "this time" 的含义

2. **信息展示不足**
   - 当前快照不显示风险分数和理由
   - 用户可能希望了解更多审核细节

3. **命令截断**
   - 长命令可能在显示时被截断
   - 需要确保用户能看到完整的命令

### 边界情况

| 场景 | 预期行为 |
|------|---------|
| Guardian 拒绝 | 显示警告和拒绝信息（参考对比测试） |
| 风险分数很高 | 可能不自动批准，转人工审核 |
| 命令很长 | 需要正确处理换行 |
| 多个 Guardian 审核 | 聚合显示状态 |
| rationale 为空 | 只显示基本批准信息 |

### 改进建议

1. **信息展示增强**
   - 添加风险等级图标（如 🟢🟡🔴）
   - 显示批准理由（rationale）
   - 提供查看详细审核信息的选项

2. **用户体验优化**
   - 添加 Guardian 审核的动画效果
   - 提供快速撤销批准的机制
   - 显示审核耗时

3. **教育引导**
   - 添加 Guardian 工作原理的说明
   - 解释风险分数的含义
   - 提供安全最佳实践建议

4. **测试覆盖**
   - 添加长命令的显示测试
   - 测试不同风险等级的显示
   - 测试 rationale 为空的情况
   - 测试并发 Guardian 事件

5. **可访问性**
   - 确保颜色不是唯一的信息传达方式
   - 为屏幕阅读器优化批准信息
   - 支持高对比度主题
