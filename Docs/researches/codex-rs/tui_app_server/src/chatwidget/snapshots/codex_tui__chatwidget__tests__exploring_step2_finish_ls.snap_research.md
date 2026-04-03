# 研究文档：探索步骤2 - 完成 ls 命令

## 场景与职责

该快照测试是探索模式系列测试的第二步，验证当 `ls -la` 命令执行完成后，活动单元格的显示状态变化。

**测试场景**：
- `ls -la` 命令执行完成
- 验证活动单元格从 "Exploring" 变为 "Explored"
- 状态指示器从活动变为静态

## 功能点目的

1. **完成状态标识**：清晰区分进行中和已完成的探索操作
2. **历史记录整合**：完成的探索操作成为历史记录的一部分
3. **视觉反馈**：通过状态变化提供操作完成的视觉反馈

## 具体技术实现

### 测试代码路径
- **文件**: `codex-rs/tui/src/chatwidget/tests.rs` (第 8199-8201 行)
- **测试函数**: `exec_history_extends_previous_when_consecutive`

### 核心测试逻辑

```rust
// 1. 开始 "ls -la"（已在 step1 完成）
let begin_ls = begin_exec(&mut chat, "call-ls", "ls -la");

// 2. 完成 "ls -la" 命令
end_exec(&mut chat, begin_ls, "", "", 0);

// 3. 验证活动单元格显示 "Explored"
assert_snapshot!("exploring_step2_finish_ls", active_blob(&chat));
```

### 辅助函数

```rust
fn end_exec(
    chat: &mut ChatWidget,
    begin: ExecCommandBeginEvent,
    stdout: &str,
    stderr: &str,
    exit_code: i32,
) {
    chat.handle_codex_event(Event {
        id: begin.call_id.clone().into(),
        msg: EventMsg::ExecCommandEnd(ExecCommandEndEvent {
            call_id: begin.call_id,
            process_id: None,
            turn_id: begin.turn_id,
            command: begin.command,
            cwd: begin.cwd,
            stdout: Some(stdout.to_string()),
            stderr: Some(stderr.to_string()),
            exit_code,
            formatted_output: format!("{}{}", stdout, stderr),
        }),
    });
}
```

### 快照内容分析

```
• Explored
  └ List ls -la
```

与 step1 的对比：

| 属性 | Step1 (开始) | Step2 (完成) |
|------|-------------|--------------|
| 状态文本 | `Exploring` | `Explored` |
| 指示器 | 旋转动画 `•` | 静态 `•` |
| 样式 | 加粗 | 加粗 |

### 状态变化逻辑

```rust
// exec_cell/render.rs
fn exploring_display_lines(&self, width: u16) -> Vec<Line<'static>> {
    let mut out: Vec<Line<'static>> = Vec::new();
    out.push(Line::from(vec![
        if self.is_active() {
            spinner(self.active_start_time(), self.animations_enabled())
        } else {
            "•".dim()  // 完成后的静态指示器
        },
        " ".into(),
        if self.is_active() {
            "Exploring".bold()  // 进行中
        } else {
            "Explored".bold()   // 已完成
        },
    ]));
    // ...
}
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/exec_cell/render.rs` | 探索模式渲染逻辑，第 253-354 行 |
| `codex-rs/tui/src/exec_cell/model.rs` | `is_active()` 状态检查 |
| `codex-rs/tui/src/chatwidget/tests.rs` | 测试用例 |

## 依赖与外部交互

### 事件流
```
ExecCommandBeginEvent (step1)
  ↓
[命令执行中]
  ↓
ExecCommandEndEvent (step2)
  ↓
is_active() 返回 false
  ↓
显示 "Explored"
```

### 状态管理
- `ExecCell::active`：标记单元格是否活动
- `active_start_time`：用于旋转动画计时

## 风险、边界与改进建议

### 潜在风险
1. **状态丢失**：如果 `ExecCommandEnd` 事件丢失，状态将永远停留在 "Exploring"
2. **错误处理**：命令失败时（exit_code != 0）的显示

### 边界情况
- 命令执行超时
- 命令被用户中断
- 命令输出非常大

### 改进建议
1. **结果指示**：成功/失败的不同图标（✓/✗）
2. **输出预览**：显示命令输出的摘要（如文件数量）
3. **展开查看**：允许用户展开查看完整输出
4. **时间戳**：显示命令执行耗时

### 系列测试上下文
```
Step1: exploring_step1_start_ls
   ↓ 执行 ls -la
Step2: exploring_step2_finish_ls (当前)
   ↓ 开始读取 foo.txt
Step3: exploring_step3_start_cat_foo
   ↓ 完成读取
Step4: exploring_step4_finish_cat_foo
```
