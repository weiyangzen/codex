# Research: request_user_input_footer_wrap.snap

## 场景与职责

本快照文件是 `codex-tui` crate 中 `request_user_input` 模块的 insta 快照测试结果，验证当底部提示栏(footer tips)需要换行显示时的 UI 渲染行为。该测试用例专门验证在窄宽度窗口下，底部操作提示能够正确换行而不截断单个提示文本。

## 功能点目的

### 测试目标
验证当终端宽度不足以在一行内显示所有底部提示时，提示文本能够智能换行，且不会将单个提示拆分到多行。

### 快照内容分析
```
Question 1/2 (2 unanswered)                        
Choose an option.                                 
                                                    
  1. Option 1  First choice.                       
› 2. Option 2  Second choice.                      
  3. Option 3  Third choice.                       
                                                    
tab to add notes | enter to submit answer         
←/→ to navigate questions | esc to interrupt
```

关键观察点：
1. **问题进度显示**: `Question 1/2 (2 unanswered)` 显示当前是第1个问题，共2个，还有2个未回答
2. **选项列表**: 显示3个选项，当前选中第2个(用 `›` 标记)
3. **底部提示换行**: 由于宽度限制(52字符)，提示被分成两行显示
   - 第一行: `tab to add notes | enter to submit answer`
   - 第二行: `←/→ to navigate questions | esc to interrupt`

## 具体技术实现

### 关键数据结构

**FooterTip 结构体** (位于 `mod.rs` 第101-120行):
```rust
#[derive(Clone, Debug)]
pub(super) struct FooterTip {
    pub(super) text: String,
    pub(super) highlight: bool,
}
```

**TIP_SEPARATOR 常量**:
```rust
pub(super) const TIP_SEPARATOR: &str = " | ";
```

### 关键流程

1. **提示生成** (`footer_tips` 方法, 第430-463行):
```rust
fn footer_tips(&self) -> Vec<FooterTip> {
    let mut tips = Vec::new();
    // 根据状态添加不同提示
    if self.has_options() {
        if self.selected_option_index().is_some() && !notes_visible {
            tips.push(FooterTip::highlighted("tab to add notes"));
        }
        // ... 其他提示
    }
    // 添加提交提示
    let enter_tip = if question_count == 1 {
        FooterTip::highlighted("enter to submit answer")
    } else if is_last_question {
        FooterTip::highlighted("enter to submit all")
    } else {
        FooterTip::new("enter to submit answer")
    };
    tips.push(enter_tip);
    // ...
}
```

2. **提示换行逻辑** (`wrap_footer_tips` 方法, 第482-521行):
```rust
fn wrap_footer_tips(&self, width: u16, tips: Vec<FooterTip>) -> Vec<Vec<FooterTip>> {
    let max_width = width.max(1) as usize;
    let separator_width = UnicodeWidthStr::width(TIP_SEPARATOR);
    
    let mut lines: Vec<Vec<FooterTip>> = Vec::new();
    let mut current: Vec<FooterTip> = Vec::new();
    let mut used = 0usize;

    for tip in tips {
        let tip_width = UnicodeWidthStr::width(tip.text.as_str()).min(max_width);
        let extra = if current.is_empty() { tip_width } else { separator_width + tip_width };
        
        // 如果当前行加上新提示会超出宽度，则开启新行
        if !current.is_empty() && used + extra > max_width {
            lines.push(current);
            current = Vec::new();
            used = 0;
        }
        // ...
    }
}
```

### 测试用例代码

位于 `mod.rs` 第2679-2704行:
```rust
#[test]
fn request_user_input_footer_wrap_snapshot() {
    let (tx, _rx) = test_sender();
    let mut overlay = RequestUserInputOverlay::new(
        request_event(
            "turn-1",
            vec![
                question_with_options("q1", "Pick one"),
                question_with_options("q2", "Pick two"),
            ],
        ),
        tx,
        true,
        false,
        false,
    );
    let answer = overlay.current_answer_mut().expect("answer missing");
    answer.options_state.selected_idx = Some(1);

    let width = 52u16;  // 窄宽度触发换行
    let height = overlay.desired_height(width);
    let area = Rect::new(0, 0, width, height);
    insta::assert_snapshot!(
        "request_user_input_footer_wrap",
        render_snapshot(&overlay, area)
    );
}
```

## 关键代码路径与文件引用

| 文件路径 | 相关代码行 | 说明 |
|---------|-----------|------|
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 430-463 | `footer_tips()` 方法生成提示列表 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 465-480 | `footer_tip_lines()` 和 `footer_tip_lines_with_prefix()` |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 482-521 | `wrap_footer_tips()` 核心换行算法 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 523-525 | `footer_required_height()` 计算所需高度 |
| `codex-rs/tui/src/bottom_pane/request_user_input/render.rs` | 334-383 | 渲染底部提示到缓冲区 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 2679-2704 | 本快照对应的测试用例 |

## 依赖与外部交互

### 外部依赖
1. **unicode-width**: 用于计算 Unicode 字符串的显示宽度
2. **ratatui**: TUI 渲染框架
3. **insta**: 快照测试框架

### 与其他模块的交互
1. **ScrollState**: 管理选项滚动状态
2. **ChatComposer**: 复用聊天输入组件处理 notes 输入
3. **GenericDisplayRow**: 通用选项行显示结构

## 风险、边界与改进建议

### 潜在风险
1. **宽度计算精度**: 使用 `UnicodeWidthStr::width` 计算显示宽度，但在某些特殊字符或组合字符场景下可能出现计算偏差
2. **提示文本过长**: 如果单个提示文本长度超过可用宽度，当前实现会将其截断到最大宽度，可能导致信息丢失

### 边界情况
1. **极小宽度**: 当宽度小于单个提示文本长度时，渲染可能异常
2. **多行提示**: 当前实现假设提示文本不包含换行符
3. **高亮样式**: 高亮提示在换行后保持样式一致性

### 改进建议
1. **添加溢出指示**: 当提示被截断时显示省略号(...)
2. **动态优先级**: 根据重要性动态决定哪些提示优先显示
3. **响应式布局**: 在极窄宽度下考虑垂直堆叠而非水平排列
4. **测试覆盖**: 添加更多边界情况测试，如极小宽度、超长提示文本等
