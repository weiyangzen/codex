# ChatWidget 小尺寸终端空闲状态测试 (高度3)

## 场景与职责

该 snapshot 测试验证 `ChatWidget` 在极小终端高度（高度为3行）且空闲状态下的渲染表现。测试场景模拟用户在使用非常紧凑的终端窗口时，UI 如何优雅地降级显示核心功能。

### 测试目的
- 验证终端高度受限时的布局适应性
- 确保核心 UI 元素（输入框、状态提示）在极小空间内仍可访问
- 捕获高度为3时空闲状态的视觉快照，用于回归测试

## 功能点目的

### 1. 响应式布局降级
当终端高度不足以显示完整 UI 时，`ChatWidget` 需要：
- 优先保留输入框（composer）的可见性
- 在可能的情况下显示状态行
- 优雅地隐藏或压缩非关键元素

### 2. 空闲状态指示
空闲状态下，UI 应显示：
- 输入提示符（placeholder）
- 基础帮助信息（如 `? for shortcuts`）
- 上下文窗口使用百分比

## 具体技术实现

### 测试代码位置
```rust
// codex-rs/tui_app_server/src/chatwidget/tests.rs
#[tokio::test]
async fn ui_snapshots_small_heights_idle() {
    use ratatui::Terminal;
    use ratatui::backend::TestBackend;
    let (chat, _rx, _op_rx) = make_chatwidget_manual(None).await;
    for h in [1u16, 2, 3] {
        let name = format!("chat_small_idle_h{h}");
        let mut terminal = Terminal::new(TestBackend::new(40, h)).expect("create terminal");
        terminal
            .draw(|f| chat.render(f.area(), f.buffer_mut()))
            .expect("draw chat idle");
        assert_snapshot!(name, terminal.backend());
    }
}
```

### 渲染流程
1. 使用 `TestBackend::new(40, 3)` 创建 40x3 的虚拟终端
2. 调用 `chat.render()` 渲染 `ChatWidget` 到缓冲区
3. 使用 `insta::assert_snapshot!` 捕获并比对渲染结果

### Snapshot 内容
```
"                                        "
"                                        "
"                                        "
```

**分析**：在高度为3的空闲状态下，所有三行都显示为空格。这表明：
- 输入框可能占据了所有可用空间
- 或者渲染逻辑在极小高度时简化了输出
- 实际渲染内容可能被截断或隐藏

## 关键代码路径与文件引用

### 核心渲染逻辑
- `codex-rs/tui_app_server/src/chatwidget.rs`
  - `ChatWidget::render()` - 主渲染入口
  - `desired_height()` - 计算所需高度

### 底部面板渲染
- `codex-rs/tui_app_server/src/bottom_pane/mod.rs`
  - `BottomPane::render()` - 底部输入区域渲染
  - 处理 composer、状态行、帮助提示的布局

### 高度计算
```rust
// ChatWidget 中的高度计算逻辑
pub(crate) fn desired_height(&self, _width: u16) -> u16 {
    // 根据内容动态计算所需高度
    // 考虑：状态指示器、消息队列、输入框等
}
```

## 依赖与外部交互

### 直接依赖
| 依赖项 | 用途 |
|--------|------|
| `ratatui::backend::TestBackend` | 提供内存中的终端模拟 |
| `ratatui::Terminal` | 终端抽象，处理渲染循环 |
| `insta::assert_snapshot` | 快照测试框架 |

### 相关事件类型
- `AppEvent::InsertHistoryCell` - 历史记录插入事件
- `TurnStartedEvent` - 任务开始事件（本测试中未触发）

### 配置依赖
- `test_config()` - 使用默认测试配置
- 模型目录通过 `test_model_catalog()` 提供

## 风险、边界与改进建议

### 已知边界情况

1. **高度极度受限**
   - 当高度 < 3 时，某些 UI 元素可能完全不可见
   - 输入框的可用行数可能不足以显示多行输入

2. **宽度与高度的交互**
   - 测试使用固定宽度 40，实际终端可能更窄
   - 文本换行可能进一步压缩可用空间

3. **状态转换**
   - 空闲到运行状态的转换在极小高度下可能不明显
   - 用户可能难以察觉任务开始/结束

### 改进建议

1. **增强小高度模式**
   ```rust
   // 建议：添加专用的小高度渲染模式
   fn render_compact(&self, area: Rect, buf: &mut Buffer) {
       if area.height <= 3 {
           // 极简模式：仅显示输入框 + 单行状态
       }
   }
   ```

2. **添加视觉指示器**
   - 在极小高度下使用颜色或符号指示状态变化
   - 考虑使用反转视频或下划线突出输入区域

3. **测试覆盖扩展**
   - 添加交互测试：验证小高度下键盘输入仍可用
   - 测试状态转换（空闲→运行→完成）的视觉反馈
   - 测试不同宽度（20, 30, 40, 80）的组合

4. **文档改进**
   - 在 user manual 中说明最小推荐终端尺寸
   - 提供小终端使用的最佳实践

### 相关测试
- `chat_small_idle_h1` - 高度为1的空闲状态
- `chat_small_idle_h2` - 高度为2的空闲状态
- `chat_small_running_h1/h2/h3` - 运行状态下的对应测试

---

*文档生成时间：2026-03-23*
*对应 snapshot：codex_tui_app_server__chatwidget__tests__chat_small_idle_h3.snap*
