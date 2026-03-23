# Research: request_user_input_wrapped_options.snap (tui_app_server)

## 场景与职责

本快照文件是 `codex-tui-app-server` crate 中 `request_user_input` 模块的 insta 快照测试结果，验证选项文本自动换行后的渲染行为。

## 功能点目的

### 测试目标
验证当选项文本长度超过可用宽度时，文本能够正确换行，且描述文本与标签正确对齐。

### 快照内容分析
```
Question 1/1 (1 unanswered)                                                                                 
Choose the next step for this task.                                                                         
                                                                                                              
› 1. Discuss a code change  Walk through a plan, then implement it together with careful checks.            
  2. Run targeted tests     Pick the most relevant crate and validate the current behavior first.           
  3. Review the diff        Summarize the changes and highlight the most important risks and gaps.          
                                                                                                              
tab to add notes | enter to submit answer | esc to interrupt
```

关键观察点：
1. **适度换行**: 在48字符宽度下，选项文本有适度换行
2. **描述对齐**: 描述文本与标签对齐，保持视觉层次
3. **完整显示**: 所有选项的完整文本都可见

## 具体技术实现

### 选项行构建

`option_rows()` 方法:
```rust
pub(super) fn option_rows(&self) -> Vec<GenericDisplayRow> {
    // ...
    let prefix_label = format!("{prefix} {number}. ");
    let wrap_indent = UnicodeWidthStr::width(prefix_label.as_str());
    GenericDisplayRow {
        name: format!("{prefix_label}{label}"),
        description: Some(opt.description.clone()),
        wrap_indent: Some(wrap_indent),
        ..Default::default()
    }
}
```

### 换行缩进计算

```rust
let prefix_label = format!("{prefix} {number}. ");
let wrap_indent = UnicodeWidthStr::width(prefix_label.as_str());
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui_app_server/src/bottom_pane/request_user_input/mod.rs` | `option_rows()` 构建选项行 |
| `codex-rs/tui_app_server/src/bottom_pane/selection_popup_common.rs` | 选项渲染和换行处理 |

## 风险、边界与改进建议

### 潜在风险
1. **对齐偏差**: 不同字体的字符宽度可能导致对齐偏差
2. **CJK 字符**: 中日韩字符的宽度计算可能不准确

### 改进建议
1. **动态测量**: 使用更精确的字符宽度测量
2. **断词优化**: 优先在语义边界处断行
