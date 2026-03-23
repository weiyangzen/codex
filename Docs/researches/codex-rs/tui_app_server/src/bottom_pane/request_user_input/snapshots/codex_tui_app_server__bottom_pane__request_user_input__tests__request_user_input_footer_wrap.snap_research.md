# Research: request_user_input_footer_wrap.snap (tui_app_server)

## 场景与职责

本快照文件是 `codex-tui-app-server` crate 中 `request_user_input` 模块的 insta 快照测试结果，验证当底部提示栏(footer tips)需要换行显示时的 UI 渲染行为。与 `codex-tui` crate 的对应测试相比，本测试验证 tui_app_server 实现中的相同功能。

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
4. **与 tui crate 的区别**: 本快照来自 `tui_app_server` 实现，source 路径为 `tui_app_server/src/bottom_pane/request_user_input/mod.rs`

## 具体技术实现

### 代码复用关系

`tui_app_server` crate 的 `request_user_input` 模块与 `tui` crate 的实现保持平行结构：

| 组件 | tui crate | tui_app_server crate |
|------|-----------|---------------------|
| 主模块 | `tui/src/bottom_pane/request_user_input/mod.rs` | `tui_app_server/src/bottom_pane/request_user_input/mod.rs` |
| 布局 | `tui/src/bottom_pane/request_user_input/layout.rs` | `tui_app_server/src/bottom_pane/request_user_input/layout.rs` |
| 渲染 | `tui/src/bottom_pane/request_user_input/render.rs` | `tui_app_server/src/bottom_pane/request_user_input/render.rs` |

### AGENTS.md 约定

根据项目 `AGENTS.md` 文件中的 TUI 代码约定：

> When a change lands in `codex-rs/tui` and `codex-rs/tui_app_server` has a parallel implementation of the same behavior, reflect the change in `codex-rs/tui_app_server` too unless there is a documented reason not to.

这意味着两个 crate 的实现应该保持一致。

### 关键数据结构

**FooterTip 结构体**:
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

### 提示换行逻辑

`wrap_footer_tips()` 方法:
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

## 关键代码路径与文件引用

| 文件路径 | 相关代码行 | 说明 |
|---------|-----------|------|
| `codex-rs/tui_app_server/src/bottom_pane/request_user_input/mod.rs` | - | `footer_tips()` 方法生成提示列表 |
| `codex-rs/tui_app_server/src/bottom_pane/request_user_input/mod.rs` | - | `wrap_footer_tips()` 核心换行算法 |
| `codex-rs/tui_app_server/src/bottom_pane/request_user_input/render.rs` | - | 渲染底部提示到缓冲区 |

## 依赖与外部交互

### 外部依赖
1. **unicode-width**: 用于计算 Unicode 字符串的显示宽度
2. **ratatui**: TUI 渲染框架
3. **insta**: 快照测试框架

### 与 tui crate 的关系
- 两个 crate 共享相同的协议定义（`codex_protocol`）
- UI 渲染逻辑保持平行实现
- 快照测试用例类似，但 source 路径不同

## 风险、边界与改进建议

### 潜在风险
1. **实现漂移**: 两个 crate 的实现可能随时间产生差异
2. **测试重复**: 相同的测试逻辑在两个 crate 中重复

### 改进建议
1. **代码共享**: 考虑将共同逻辑提取到共享库
2. **同步测试**: 确保两个 crate 的测试用例保持同步更新
3. **差异检测**: 定期比较两个实现的差异
